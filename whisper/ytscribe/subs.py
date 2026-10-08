"""유튜브 자막(VTT) 파싱과 Whisper 전사와의 시간 정렬·교차검증."""

import html
import re
from pathlib import Path

# WebVTT는 시(hour)를 생략할 수 있다 (MM:SS.mmm)
_TS = r"(?:(\d+):)?(\d{2}):(\d{2})\.(\d{3})"
_CUE = re.compile(rf"^{_TS}\s+-->\s+{_TS}")
_TAG = re.compile(r"<[^>]+>")


def _sec(h: str | None, m: str, s: str, ms: str) -> float:
    return int(h or 0) * 3600 + int(m) * 60 + int(s) + int(ms) / 1000


def parse_vtt(path: Path) -> list[dict]:
    """VTT를 (start, end, text) 목록으로 바꾼다.

    큐 본문은 타임스탬프 줄 다음부터 '완전히 빈 줄' 전까지다. 유튜브 자동자막의 공백 한 칸(" ") 줄은
    본문 안의 줄로 취급한다. 큐 식별자·NOTE/STYLE 블록은 본문 수집 중이 아니므로 자연히 무시된다.
    자동자막은 직전 줄을 반복하는 롤링 형식이라 각 큐의 마지막 줄만 취하고, 10ms 전환 큐와 연속 중복은 버린다.
    """
    raw: list[tuple[float, float, list[str]]] = []
    collecting = False
    for line in path.read_text(encoding="utf-8").splitlines():
        m = _CUE.match(line)
        if m:
            g = m.groups()
            raw.append((_sec(*g[:4]), _sec(*g[4:]), []))
            collecting = True
        elif line == "":
            collecting = False
        elif collecting:
            raw[-1][2].append(line)

    rolling = any("<c>" in ln for _, _, body in raw for ln in body)
    cues: list[dict] = []
    for start, end, body in raw:
        lines = [html.unescape(_TAG.sub("", ln)).strip() for ln in body]
        lines = [ln for ln in lines if ln]
        if end - start < 0.05 or not lines:
            continue
        text = lines[-1] if rolling else " ".join(lines)
        if cues and cues[-1]["text"] == text:
            cues[-1]["end"] = end
        else:
            cues.append({"start": start, "end": end, "text": text})
    return cues


def overlap_text(cues: list[dict], start: float, end: float) -> str:
    return " ".join(c["text"] for c in cues if c["end"] > start and c["start"] < end)


def uncovered_spans(cues: list[dict], segments: list[dict], min_len: float = 2.0, pad: float = 0.5) -> list[dict]:
    """자막에는 말소리가 있는데 Whisper 세그먼트가 없는 구간 (누락 후보)."""
    def covered(c: dict) -> bool:
        mid = (c["start"] + c["end"]) / 2
        return any(s["start"] - pad <= mid <= s["end"] + pad for s in segments)

    spans: list[dict] = []
    for c in cues:
        if covered(c):
            continue
        if spans and c["start"] - spans[-1]["end"] < 1.0:
            spans[-1]["end"] = c["end"]
            spans[-1]["text"] += " " + c["text"]
        else:
            spans.append(dict(c))
    return [s for s in spans if s["end"] - s["start"] >= min_len]
