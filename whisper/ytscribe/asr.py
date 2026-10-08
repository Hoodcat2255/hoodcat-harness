"""faster-whisper(CUDA/CPU) 또는 mlx-whisper(Apple Silicon) 전사 (정확도 우선 설정)."""

import ctypes
import glob
import re
import time
from pathlib import Path
from typing import Any


def preload_cuda_libs() -> None:
    # LD_LIBRARY_PATH는 프로세스 시작 시에만 반영되므로,
    # pip로 설치한 cuBLAS/cuDNN을 ctranslate2 import 전에 직접 로드한다.
    # 라이브러리 간 의존 순서를 몰라도 되도록, 더 이상 진전이 없을 때까지 반복 로드한다.
    import nvidia.cublas
    import nvidia.cudnn

    pending = [
        so
        for pkg in (nvidia.cublas, nvidia.cudnn)
        for so in sorted(glob.glob(str(Path(pkg.__path__[0]) / "lib" / "*.so*")))
    ]
    while pending:
        failed = []
        for so in pending:
            try:
                ctypes.CDLL(so, mode=ctypes.RTLD_GLOBAL)
            except OSError:
                failed.append(so)
        if len(failed) == len(pending):
            # 일부는 이 GPU 경로에서 쓰이지 않는 부가 라이브러리라 실패해도 무방하다
            break
        pending = failed


OOM_MARKERS = ("out of memory", "cublas_status_alloc_failed", "cudnn_status_alloc_failed")


def default_device() -> str:
    """Apple Silicon에서 mlx-whisper가 있으면 mlx, 아니면 cuda (OOM이면 CPU로 넘어간다)."""
    import platform

    if platform.system() == "Darwin" and platform.machine() == "arm64":
        try:
            import mlx_whisper  # noqa: F401
            return "mlx"
        except ImportError:
            return "cpu"
    return "cuda"


def transcribe(audio: Path, opts: dict[str, Any]) -> tuple[list[dict], dict]:
    if opts["device"] == "auto":
        opts = opts | {"device": default_device()}
    if opts["device"] == "mlx":
        return _run_mlx(audio, opts)
    if opts["device"] == "cuda":
        try:
            preload_cuda_libs()
        except ImportError as e:
            print(f"[warn] nvidia cuBLAS/cuDNN 패키지를 불러오지 못했습니다: {e}")
    compute_type = opts["compute_type"] if opts["device"] == "cuda" else "int8"
    try:
        return _run(audio, opts, opts["device"], compute_type)
    except RuntimeError as e:
        # ComfyUI 등 다른 프로세스가 VRAM을 점유하면 OOM이 날 수 있다 → CPU로 재시도
        if opts["device"] != "cuda" or not any(m in str(e).lower() for m in OOM_MARKERS):
            raise
        print(f"[warn] GPU 메모리 부족 ({e}) → CPU(int8)로 재시도합니다. 느리지만 같은 모델입니다.")
        return _run(audio, opts, "cpu", "int8")


# 다시 전사한 조각의 품질 필터 (음악·잡음에서 나온 환각 차단).
# no_speech_prob는 쓰지 않는다: BGM 깔린 인터뷰는 0.76~0.84로 높게 나오지만 실제 발화였다.
GAP_MIN_LEN = 1.5
GAP_MIN_LOGPROB = -1.0
GAP_MAX_COMPRESSION = 2.4
# 한국어 발화는 초당 5~7자. 구간 길이에 비해 글자가 너무 적으면 잡음에서 나온 환각으로 본다
# (예: 인터뷰 첫 3초를 단독 재전사 → "기상캐스터" 5자 = 1.6자/초)
GAP_MIN_CHARS_PER_SEC = 2.0
# 방송 크레딧·유튜브 엔딩 같은 정형 환각 문구
HALLUCINATION_RE = re.compile(r"기상캐스터|영상편집|촬영기자|자료조사|자막 ?제공|시청해 ?주셔서|구독|좋아요|다음 영상")
# 실제 발화로는 나올 수 없는 문자열 (깨진 문자, 자막 제작 크레딧). 본 전사에도 위치와 무관하게 적용한다.
# "구독"·"좋아요"는 유튜버가 실제로 말하므로 여기에 넣지 않는다 (재전사 조각에만 위 HALLUCINATION_RE로 거른다)
UNSPEAKABLE_RE = re.compile(r"\ufffd|Amara\.org|Sous-titr", re.I)
# 한국어 전사에 한자가 2자 이상 섞이면 저음량 구간의 깨진 디코딩이다 (예: "閉을閉을")
HANJA_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff\uf900-\ufaff]")
# 같은 문장이 별도 세그먼트로 이만큼 연속되면 반복 루프로 본다 (예: "이곳은 한창의 한가운데요." ×11)
REPEAT_RUN = 3
# 이보다 짧은 문장("네", "감사합니다")은 실제 맞장구로 반복될 수 있어 연속 반복 판정에서 뺀다
REPEAT_MIN_CHARS = 6
# 발화 시간 중 인식된 단어가 덮은 비율이 이보다 낮으면 누락 가능성을 경고한다
COVERAGE_WARN = 0.9
# 숫자가 든 단어의 인식 확률이 이보다 낮으면 '수치 확인 필요'로 표시한다 (녹음본)
NUM_MIN_PROB = 0.5


def _run(audio: Path, opts: dict[str, Any], device: str, compute_type: str) -> tuple[list[dict], dict]:
    from faster_whisper import BatchedInferencePipeline, WhisperModel
    from faster_whisper.audio import decode_audio

    print(f"[asr] {opts['model']} / {device} / {compute_type}")
    if opts.get("initial_prompt"):
        print(f"[asr] initial_prompt: {opts['initial_prompt']}")
    if opts.get("hotwords"):
        print(f"[asr] hotwords: {opts['hotwords']}")
    t0 = time.time()
    model = WhisperModel(opts["model"], device=device, compute_type=compute_type, cpu_threads=8)
    wave = decode_audio(str(audio))
    common = dict(
        language=opts["language"],
        beam_size=opts["beam_size"],
        best_of=opts["beam_size"],
        # 이전 문장에 끌려 같은 문장이 반복되는 루프 방지
        condition_on_previous_text=False,
        initial_prompt=opts.get("initial_prompt"),
        hotwords=opts.get("hotwords"),
    )

    # 순차 모드(30초 창)는 BGM 깔린 인터뷰 구간을 통째로 건너뛰는 문제가 있었다.
    # VAD로 자른 짧은 조각을 독립적으로 전사하면 누락이 크게 줄어든다 (KBS 리포트로 확인).
    # 단어 타임스탬프로 '실제로 인식된 구간'을 알아야 아래 누락 복구가 가능하다 (세그먼트 시각은 조각 단위라 부정확).
    segments, info = BatchedInferencePipeline(model).transcribe(
        wave, batch_size=opts["batch_size"], chunk_length=opts["chunk_length"], word_timestamps=True, **common,
    )
    result, covered = _collect([
        {"start": seg.start, "end": seg.end, "text": seg.text, "words": [(w.start, w.end) for w in (seg.words or [])],
         "word_info": [(w.word, w.probability) for w in (seg.words or [])]}
        for seg in segments
    ], opts["language"] or info.language)
    def decode_clip(clip):
        return [{"text": s.text, "avg_logprob": s.avg_logprob, "compression_ratio": s.compression_ratio}
                for s in model.transcribe(clip, vad_filter=False, **common)[0]]

    recovered, coverage = _recover_gaps(wave, covered, decode_clip, opts["language"] or info.language)
    result = _finish(result + recovered)
    elapsed = time.time() - t0
    print(f"[asr] {elapsed:.0f}s 소요 (실시간 대비 x{info.duration / max(elapsed, 1):.1f})")
    meta = {"language": info.language, "duration": info.duration, "device": device, "compute_type": compute_type,
            "coverage": coverage}
    return result, meta


# opts["model"] → mlx-community 변환 모델
MLX_MODELS = {
    "large-v3": "mlx-community/whisper-large-v3-mlx",
    "turbo": "mlx-community/whisper-large-v3-turbo",
    "large-v3-turbo": "mlx-community/whisper-large-v3-turbo",
}


def _run_mlx(audio: Path, opts: dict[str, Any]) -> tuple[list[dict], dict]:
    """Apple Silicon(Metal) 전사. faster-whisper(CTranslate2)는 macOS에서 CPU로만 돈다.

    mlx-whisper에는 VAD 배치 모드가 없으므로, faster-whisper의 VAD로 발화 구간을 찾아
    chunk_length 이하의 창으로 묶어 창마다 전사한다 (CUDA 경로의 15초 조각 전사와 같은 효과).
    mlx-whisper는 빔 서치와 hotwords를 지원하지 않아 greedy(+온도 폴백)로 디코딩한다.
    """
    import mlx_whisper
    from faster_whisper.audio import decode_audio
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    repo = MLX_MODELS.get(opts["model"], opts["model"])
    print(f"[asr] {repo} / mlx")
    if opts.get("initial_prompt"):
        print(f"[asr] initial_prompt: {opts['initial_prompt']}")
    if opts.get("hotwords"):
        print("[warn] mlx-whisper는 hotwords를 지원하지 않아 무시합니다.")
    t0 = time.time()
    sr = 16000
    wave = decode_audio(str(audio))
    duration = len(wave) / sr
    common = dict(
        path_or_hf_repo=repo,
        language=opts["language"],
        condition_on_previous_text=False,
        initial_prompt=opts.get("initial_prompt"),
        verbose=None,
    )

    speech = [(t["start"] / sr, t["end"] / sr) for t in get_speech_timestamps(
        wave, VadOptions(max_speech_duration_s=opts["chunk_length"], min_silence_duration_ms=160))]
    raw, language = [], opts["language"]
    for w_start, w_end in group_windows(speech, opts["chunk_length"]):
        out = mlx_whisper.transcribe(wave[int(w_start * sr): int(w_end * sr)], word_timestamps=True, **common)
        language = language or out.get("language")
        for seg in drop_tail_hallucination(out["segments"], w_end - w_start):
            raw.append({
                "start": w_start + seg["start"], "end": w_start + seg["end"], "text": seg["text"],
                "words": [(w_start + w["start"], w_start + w["end"]) for w in seg.get("words", [])],
                "word_info": [(w["word"], w["probability"]) for w in seg.get("words", [])],
            })
    result, covered = _collect(raw, language)

    def decode_clip(clip):
        return [{"text": s["text"], "avg_logprob": s["avg_logprob"], "compression_ratio": s["compression_ratio"]}
                for s in mlx_whisper.transcribe(clip, **common)["segments"]]

    recovered, coverage = _recover_gaps(wave, covered, decode_clip, language)
    result = _finish(result + recovered)
    elapsed = time.time() - t0
    print(f"[asr] {elapsed:.0f}s 소요 (실시간 대비 x{duration / max(elapsed, 1):.1f})")
    meta = {"language": language, "duration": duration, "device": "mlx", "compute_type": "float16", "coverage": coverage}
    return result, meta


# greedy 디코딩은 창 끝 무음 패딩에서 짧은 환각을 만든다 ("이 시각 세계였습니다.", "SBS 김현우입니다.").
# 뉴스 3편에서 환각은 모두 창 끝 0.05초 이내, 단어 확률 평균 0.54 이하였고 실제 발화는 0.46이어도 창 끝에서 0.64초 떨어져 있었다.
MLX_TAIL_GAP = 0.2
MLX_TAIL_MIN_PROB = 0.6


def drop_tail_hallucination(segments: list[dict], window_len: float) -> list[dict]:
    """창 맨 끝에 붙은 저신뢰 세그먼트를 버린다. 실제 발화였다면 누락 재전사가 다시 다룬다."""
    if not segments:
        return segments
    last = segments[-1]
    probs = [w["probability"] for w in last.get("words", [])]
    if probs and window_len - last["end"] <= MLX_TAIL_GAP and sum(probs) / len(probs) < MLX_TAIL_MIN_PROB:
        print(f"  (창 끝 저신뢰 출력 버림) {last['text'].strip()[:60]}")
        return segments[:-1]
    return segments


def group_windows(speech: list[tuple[float, float]], max_len: float) -> list[tuple[float, float]]:
    """연속된 발화 구간을 원래 시간축 그대로 max_len초 이하의 창으로 묶는다."""
    windows: list[list[float]] = []
    for s, e in speech:
        if windows and e - windows[-1][0] <= max_len:
            windows[-1][1] = e
        else:
            windows.append([s, e])
    return [(round(s, 3), round(e, 3)) for s, e in windows]


def _collect(segments: list[dict], language: str | None = None) -> tuple[list[dict], list[tuple[float, float]]]:
    """환각 출력을 버리고, 단어 타임스탬프로 세그먼트 시각을 맞춘다. 인식된 단어 구간도 함께 돌려준다.

    버린 세그먼트의 단어 구간은 covered에 넣지 않으므로, 그 자리는 누락 재전사가 다시 다룬다.
    """
    result, covered = [], []
    runs = repeated_runs([seg["text"] for seg in segments])
    for i, seg in enumerate(segments):
        text = seg["text"].strip()
        reason = ("연속 반복 버림" if i in runs else "반복 출력 버림" if is_degenerate(text)
                  else "발화 불가 문자열 버림" if is_unspeakable(text, language) else "")
        if reason:
            print(f"  [{fmt_ts(seg['start'], '.')}] ({reason}) {text[:60]}")
            continue
        words = seg["words"]
        covered += words
        start, end = (words[0][0], words[-1][1]) if words else (seg["start"], seg["end"])
        out = {"start": round(start, 2), "end": round(end, 2), "text": text}
        if any(p < NUM_MIN_PROB and any(ch.isdigit() for ch in w) for w, p in seg.get("word_info", [])):
            out["num_low_conf"] = True  # 값은 남기지 않는다 (마스킹 전 원문이 다른 경로로 새지 않게)
        result.append(out)
        print(f"  [{fmt_ts(start, '.')}] {text}")
    return result, covered


def _norm(text: str) -> str:
    return re.sub(r"\W", "", text)


def repeated_runs(texts: list[str]) -> set[int]:
    """정규화한 같은 문장이 REPEAT_RUN번 이상 연속된 세그먼트 번호 (짧은 맞장구는 제외)."""
    norm = [_norm(t) for t in texts]
    out: set[int] = set()
    i = 0
    while i < len(norm):
        j = i
        while j + 1 < len(norm) and norm[j + 1] == norm[i]:
            j += 1
        if j - i + 1 >= REPEAT_RUN and len(norm[i]) >= REPEAT_MIN_CHARS:
            out.update(range(i, j + 1))
        i = j + 1
    return out


def is_unspeakable(text: str, language: str | None) -> bool:
    """깨진 문자·자막 크레딧처럼 실제 발화일 수 없는 출력. 한자 판정은 한국어 전사에서만 한다."""
    return bool(UNSPEAKABLE_RE.search(text)) or (language == "ko" and len(HANJA_RE.findall(text)) >= 2)


def speech_coverage(speech: list[tuple[float, float]], covered: list[tuple[float, float]]) -> float:
    """VAD 발화 시간 중 인식된 단어 구간(앞뒤 pad 포함)이 덮은 비율. 발화가 없으면 1.0."""
    total = sum(e - s for s, e in speech)
    if total <= 0:
        return 1.0
    missing = sum(e - s for s, e in uncovered_intervals(speech, covered, min_len=0.0))
    return max(0.0, 1.0 - missing / total)


def _finish(result: list[dict]) -> list[dict]:
    result.sort(key=lambda s: s["start"])
    for i, s in enumerate(result):
        s["id"] = i
    return result


def _recover_gaps(wave, covered: list[tuple[float, float]], decode_clip,
                  language: str | None = None) -> tuple[list[dict], dict]:
    """VAD로는 말소리인데 어떤 단어도 인식되지 않은 구간을 그 부분만 잘라 다시 전사한다.

    BGM이 깔린 인터뷰는 앞뒤 발화와 한 조각으로 묶이면 통째로 빠지지만, 단독으로 넣으면 인식됐다.
    복구 전후의 발화 커버리지도 함께 돌려준다.
    """
    from faster_whisper.vad import VadOptions, get_speech_timestamps

    sr = 16000
    speech = [(t["start"] / sr, t["end"] / sr)
              for t in get_speech_timestamps(wave, VadOptions(min_silence_duration_ms=300))]
    gaps = uncovered_intervals(speech, covered, min_len=GAP_MIN_LEN)
    recovered, filled = [], []
    for g_start, g_end in gaps:
        lo, hi = max(0.0, g_start - 0.3), g_end + 0.3
        segs = decode_clip(wave[int(lo * sr): int(hi * sr)])
        good = [s for s in segs if s["avg_logprob"] >= GAP_MIN_LOGPROB
                and s["compression_ratio"] <= GAP_MAX_COMPRESSION and s["text"].strip()]
        text = " ".join(s["text"].strip() for s in good)
        density = len(re.sub(r"\W", "", text)) / max(g_end - g_start, 0.1)
        if text and (density < GAP_MIN_CHARS_PER_SEC or HALLUCINATION_RE.search(text) or is_degenerate(text)
                     or is_unspeakable(text, language)):
            status = f"버림(환각 의심, {density:.1f}자/초)"
            text = ""
        else:
            status = "복구" if text else "버림(품질 미달)"
        raw = " ".join(s["text"].strip() for s in segs)
        print(f"[asr] 누락 의심 {fmt_ts(g_start, '.')}~{fmt_ts(g_end, '.')} 재전사 → {status}: {(text or raw)[:60]}")
        if text:
            recovered.append({"start": round(lo, 2), "end": round(hi, 2), "text": text, "recovered": "vad_gap"})
            filled.append((g_start, g_end))
    # 버린 반복 루프가 구간마다 같은 문장으로 다시 복구되는 경우
    runs = repeated_runs([r["text"] for r in recovered])
    if runs:
        print(f"[asr] 재전사 결과의 연속 반복 {len(runs)}개 버림: {recovered[min(runs)]['text'][:60]}")
    recovered = [r for i, r in enumerate(recovered) if i not in runs]
    filled = [f for i, f in enumerate(filled) if i not in runs]
    return recovered, coverage_stats(speech, covered, filled)


def coverage_stats(speech: list[tuple[float, float]], covered: list[tuple[float, float]],
                   filled: list[tuple[float, float]]) -> dict:
    """재전사 전후 커버리지. filled는 복구에 성공한 원래 누락 구간(덧댄 여유 제외)이다."""
    return {"speech_sec": round(sum(e - s for s, e in speech), 1),
            "before": round(speech_coverage(speech, covered), 4),
            "after": round(speech_coverage(speech, covered + filled), 4)}


def report_coverage(stats: dict | None) -> None:
    """커버리지를 로그로 남기고, 기준 미만이면 누락 가능성을 경고한다 (캐시를 재사용해도 매번 출력)."""
    if not stats:
        return
    before, after = stats["before"], stats["after"]
    print(f"[asr] 커버리지: 발화 {fmt_ts(stats['speech_sec'], '.')[:8]} 중 {before:.1%}"
          + (f" → 재전사 후 {after:.1%}" if after != before else ""))
    if after < COVERAGE_WARN:
        print(f"[warn] 커버리지 {after:.1%} (기준 {COVERAGE_WARN:.0%} 미만): 발화가 빠졌을 수 있습니다. "
              "마이크 미수록·배경음 때문일 수 있으니 무음으로 단정하지 말고 해당 구간을 직접 확인하세요.")


def is_degenerate(text: str) -> bool:
    """'정전기 전병칠 정전기 전병칠…'처럼 고유 단어가 절반 이하인 반복 출력 (4단어 이상일 때만 판단)."""
    toks = text.split()
    return len(toks) >= 4 and len(set(toks)) <= len(toks) // 2


def uncovered_intervals(
    speech: list[tuple[float, float]], covered: list[tuple[float, float]], min_len: float, pad: float = 0.3
) -> list[tuple[float, float]]:
    """speech 구간에서 covered(단어 구간, 앞뒤 pad)를 뺀 나머지 중 min_len 이상인 것."""
    cov = sorted((max(0.0, s - pad), e + pad) for s, e in covered)
    merged: list[list[float]] = []
    for s, e in cov:
        if merged and s <= merged[-1][1]:
            merged[-1][1] = max(merged[-1][1], e)
        else:
            merged.append([s, e])
    out: list[tuple[float, float]] = []
    for s, e in speech:
        cur = s
        for cs, ce in merged:
            if ce <= cur or cs >= e:
                continue
            if cs > cur:
                out.append((cur, cs))
            cur = max(cur, ce)
        if cur < e:
            out.append((cur, e))
    # 짧은 쉼(0.5초 미만)으로 갈라진 조각은 합친다
    joined: list[tuple[float, float]] = []
    for s, e in out:
        if joined and s - joined[-1][1] < 0.5:
            joined[-1] = (joined[-1][0], e)
        else:
            joined.append((s, e))
    return [(round(s, 2), round(e, 2)) for s, e in joined if e - s >= min_len]


def fmt_ts(sec: float, sep: str = ",") -> str:
    total_s, ms = divmod(int(round(sec * 1000)), 1000)
    h, rem = divmod(total_s, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}{sep}{ms:03d}"
