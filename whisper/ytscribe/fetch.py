"""yt-dlp로 음원·저해상도 영상·메타데이터·자막을 받는다."""

import hashlib
import json
import shutil
import time
from pathlib import Path
from typing import Any

import yt_dlp
from yt_dlp.utils import DownloadError, sanitize_filename

from .frames import has_video_stream

VIDEO_EXTS = {".mp4", ".mkv", ".webm", ".mov", ".avi"}


def _base_opts(**extra: Any) -> Any:  # yt-dlp의 _Params TypedDict 대신 Any
    return {"quiet": True, "no_warnings": True, "noprogress": True, "noplaylist": True, **extra}


RETRY_DELAYS = (5, 15)


def _download(url: str, opts: Any, what: str) -> None:
    """YouTube가 간헐적으로 403을 돌려줘서, 실패하면 잠시 쉬고 YoutubeDL을 새로 만들어
    (서명된 다운로드 주소를 새로 받아) 다시 시도한다. 수동 재시도로는 바로 성공하는 경우가 대부분이었다."""
    for attempt, delay in enumerate((*RETRY_DELAYS, None), 1):
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.download([url])
            return
        except DownloadError as e:
            if delay is None:
                raise
            print(f"[warn] {what} 다운로드 실패 ({attempt}회차, {delay}초 후 재시도): {str(e)[:120]}")
            time.sleep(delay)


def fetch_url(url: str, root: Path, want_video: bool, sub_langs: list[str]) -> Path:
    with yt_dlp.YoutubeDL(_base_opts()) as ydl:
        raw = ydl.extract_info(url, download=False)
        if raw is None:
            raise RuntimeError(f"영상 정보를 가져오지 못했습니다: {url}")
        info: Any = ydl.sanitize_info(raw)
    if info.get("_type") == "playlist":
        raise RuntimeError("플레이리스트 URL은 지원하지 않습니다. 개별 영상 URL을 넣어 주세요.")
    work = root / sanitize_filename(str(info["id"]), restricted=True)
    work.mkdir(parents=True, exist_ok=True)
    (work / "info.json").write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    print(f"[fetch] {info.get('title')} ({info.get('duration')}s) -> {work}")

    if not (work / "audio.m4a").exists():
        opts = _base_opts(
            format="bestaudio/best",
            outtmpl=str(work / "audio.%(ext)s"),
            postprocessors=[{"key": "FFmpegExtractAudio", "preferredcodec": "m4a"}],
        )
        _download(url, opts, "음원")

    if want_video and not (work / "video.mp4").exists():
        # 화면 텍스트 판독용이라 720p면 충분하다 (이름 자막·슬라이드 글자 크기 기준)
        opts = _base_opts(
            format="bv*[height<=720][ext=mp4]/bv*[height<=720]/b[height<=720]",
            outtmpl=str(work / "video.%(ext)s"),
            merge_output_format="mp4",
        )
        try:
            _download(url, opts, "영상")
            _normalize_video(work)
        except DownloadError as e:
            print(f"[warn] 영상 다운로드 실패, 프레임 분석 생략: {e}")

    # 업로더 수동 자막과 자동자막을 언어별로 받는다. 429가 잦아 실패해도 계속 진행한다.
    for kind, flags in (("manual", {"writesubtitles": True}), ("auto", {"writeautomaticsub": True})):
        missing = [lang for lang in sub_langs if not (work / f"subs.{kind}.{lang}.vtt").exists()]
        if not missing:
            continue
        opts = _base_opts(
            skip_download=True,
            subtitleslangs=missing,
            subtitlesformat="vtt",
            outtmpl=str(work / f"subs.{kind}"),
            **flags,
        )
        try:
            with yt_dlp.YoutubeDL(opts) as ydl:
                ydl.download([url])
        except DownloadError as e:
            print(f"[warn] {kind} 자막 다운로드 실패: {e}")
    return work


def _normalize_video(work: Path) -> None:
    for p in work.glob("video.*"):
        if p.suffix != ".mp4" and p.suffix in VIDEO_EXTS:
            p.rename(work / "video.mp4")


def prepare_local(path: Path, root: Path, link_video: bool = True, title: str | None = None) -> Path:
    """로컬 파일용 작업 디렉터리. 경로·크기·수정시각 해시를 붙여 같은 이름의 다른 파일과 섞이지 않게 한다."""
    src = path.resolve()
    st = src.stat()
    digest = hashlib.sha1(f"{src}|{st.st_size}|{st.st_mtime_ns}".encode()).hexdigest()[:8]
    work = root / f"{sanitize_filename(path.stem).strip('.') or 'recording'}-{digest}"
    work.mkdir(parents=True, exist_ok=True)

    info_path = work / "info.json"
    info = (json.loads(info_path.read_text(encoding="utf-8")) if info_path.exists() else
            {"id": work.name, "title": path.stem, "description": "", "tags": [], "chapters": None,
             "source_path": str(src)})
    if title:
        info["title"] = title
    info_path.write_text(json.dumps(info, ensure_ascii=False), encoding="utf-8")
    audio = work / f"audio{src.suffix}"
    if not audio.exists():
        shutil.copy(src, audio)

    video = work / "video.mp4"
    if video.is_symlink() and not video.exists():
        video.unlink()  # 원본을 옮겨 깨진 링크
    if link_video and not video.exists() and src.suffix.lower() in VIDEO_EXTS and has_video_stream(src):
        video.symlink_to(src)
    return work


def find_audio(work: Path) -> Path:
    candidates = [p for p in sorted(work.glob("audio.*")) if p.suffix not in {".part", ".ytdl", ".tmp"}]
    if not candidates:
        raise FileNotFoundError(f"오디오 파일이 없습니다: {work}/audio.*")
    return candidates[0]


def find_subs(work: Path, kind: str, langs: list[str]) -> Path | None:
    for lang in langs:
        p = work / f"subs.{kind}.{lang}.vtt"
        if p.exists():
            return p
    return None
