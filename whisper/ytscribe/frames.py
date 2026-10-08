"""영상 프레임 추출 → 중복 제거 → 화면 텍스트 OCR (RapidOCR, PP-OCRv5 한국어)."""

import shutil
import subprocess
import time
from collections import Counter
from pathlib import Path

import cv2
import numpy as np

OCR_MIN_SCORE = 0.8


def has_video_stream(path: Path) -> bool:
    proc = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=codec_type",
         "-of", "csv=p=0", str(path)],
        capture_output=True, text=True,
    )
    return proc.returncode == 0 and "video" in proc.stdout


def extract_frames(video: Path, work: Path, interval: float, force: bool, width: int = 1280) -> list[tuple[float, Path]]:
    """interval초 간격 프레임을 frames_<interval>/ 에 뽑는다.

    간격별로 디렉터리를 나누고 임시 디렉터리에 다 뽑은 뒤 이름을 바꾸므로,
    간격을 바꾸거나 ffmpeg가 중간에 죽어도 다른 간격·잘린 프레임 세트를 재사용하지 않는다.
    """
    out_dir = work / f"frames_{interval:g}"
    if force and out_dir.exists():
        shutil.rmtree(out_dir)
    if not out_dir.exists():
        tmp = work / f".frames_{interval:g}.tmp"
        if tmp.exists():
            shutil.rmtree(tmp)
        tmp.mkdir(parents=True)
        subprocess.run(
            ["ffmpeg", "-y", "-loglevel", "error", "-i", str(video),
             "-vf", f"fps=1/{interval},scale='min({width},iw)':-2", "-q:v", "3",
             str(tmp / "f_%05d.jpg")],
            check=True,
        )
        tmp.rename(out_dir)
    frames = sorted(out_dir.glob("f_*.jpg"))
    # fps=1/N 필터는 각 N초 구간의 중앙 프레임을 내보낸다 → 시각 ≈ (i-0.5)*N (ffmpeg 6.1.1에서 실측)
    return [((int(p.stem[2:]) - 0.5) * interval, p) for p in frames]


def dedupe(
    frames: list[tuple[float, Path]], changed_ratio: float = 0.01, max_gap: float = 30.0
) -> list[tuple[float, Path]]:
    """직전에 남긴 프레임과 거의 같은 화면이면 버린다.

    평균 픽셀 차는 이름 자막처럼 화면 일부만 바뀌는 경우를 놓치므로,
    크게 바뀐 픽셀(밝기 차 > 30)의 비율로 판단한다.
    판서에 손글씨가 조금씩 더해지는 화면은 1% 미만으로 바뀌므로, max_gap초마다 최소 한 장은 남긴다.
    """
    kept: list[tuple[float, Path]] = []
    last = None
    for t, p in frames:
        img = cv2.imread(str(p), cv2.IMREAD_GRAYSCALE)
        if img is None:
            print(f"[warn] 프레임을 읽지 못해 건너뜀: {p}")
            continue
        small = cv2.resize(img, (160, 90), interpolation=cv2.INTER_AREA).astype(np.int16)
        stale = bool(kept) and t - kept[-1][0] >= max_gap
        if last is None or stale or float((np.abs(small - last) > 30).mean()) > changed_ratio:
            kept.append((t, p))
            last = small
    return kept


def make_ocr():
    from rapidocr import LangDet, LangRec, ModelType, OCRVersion, RapidOCR

    # det은 server 모델: mobile은 3.5배 빠르지만 이름 자막(lower third)을 놓쳤다.
    # 글자 방향 분류(cls)는 가로 자막뿐이라 끄고, 스레드는 물리 코어 수(8)일 때 가장 빨랐다 (4.7→3.2초/장)
    return RapidOCR(params={
        "Global.log_level": "error",
        "Global.use_cls": False,
        "EngineConfig.onnxruntime.intra_op_num_threads": 8,
        "Det.ocr_version": OCRVersion.PPOCRV5, "Det.model_type": ModelType.SERVER, "Det.lang_type": LangDet.CH,
        "Rec.ocr_version": OCRVersion.PPOCRV5, "Rec.model_type": ModelType.MOBILE, "Rec.lang_type": LangRec.KOREAN,
    })


def ocr_frames(frames: list[tuple[float, Path]]) -> list[dict]:
    engine = make_ocr()
    results = []
    t0 = time.time()
    for i, (t, p) in enumerate(frames, 1):
        r = engine(str(p))
        texts = [
            str(txt).strip()
            for txt, score in zip(r.txts or [], r.scores or [])
            if float(score) >= OCR_MIN_SCORE and len(str(txt).strip()) >= 2
        ]
        results.append({"t": round(t, 1), "frame": p.name, "texts": texts})
        if i % 10 == 0 or i == len(frames):
            print(f"[ocr] {i}/{len(frames)} 프레임 ({time.time() - t0:.0f}s)")
    return results


def to_spans(ocr: list[dict], interval: float) -> list[dict]:
    """중복 제거된 프레임별 OCR을 '텍스트 → 등장 구간' 목록으로 합친다.

    버려진 프레임은 직전 유지 프레임과 같은 화면이므로, 텍스트는 '다음 유지 프레임 직전'까지 떠 있었다고 본다.
    방송사 로고·제보 전화번호처럼 대부분의 프레임에 계속 떠 있는 텍스트는 버린다.
    """
    if not ocr:
        return []
    freq = Counter(txt for r in ocr for txt in set(r["texts"]))
    static = {txt for txt, n in freq.items() if len(ocr) >= 6 and n / len(ocr) > 0.4}

    half = interval / 2
    open_spans: dict[str, dict] = {}
    spans: list[dict] = []
    for r in ocr:
        current = set(r["texts"]) - static
        for txt in list(open_spans):
            if txt not in current:
                span = open_spans.pop(txt)
                span["end"] = r["t"] - half
                spans.append(span)
        for txt in current:
            if txt not in open_spans:
                open_spans[txt] = {"start": max(0.0, r["t"] - half), "end": None, "text": txt}
    last_end = ocr[-1]["t"] + half
    for span in open_spans.values():
        span["end"] = last_end
        spans.append(span)
    return sorted(spans, key=lambda s: (s["start"], s["text"]))


def grab_frame(video: Path, t: float, out: Path, width: int = 1280) -> Path | None:
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{t:.2f}", "-i", str(video),
         "-frames:v", "1", "-vf", f"scale='min({width},iw)':-2", "-q:v", "3", str(out)],
        capture_output=True, text=True,
    )
    if proc.returncode != 0 or not out.exists():
        print(f"[warn] {t:.1f}s 프레임 추출 실패: {proc.stderr.strip()[:200]}")
        return None
    return out
