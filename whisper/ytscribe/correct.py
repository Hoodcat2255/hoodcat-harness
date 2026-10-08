"""교정 입력 구성, 교정 결과 적용, 결과물 렌더링."""

import copy
import re
from typing import Any

from .asr import fmt_ts
from .subs import overlap_text

# 화면 텍스트는 발화보다 먼저/늦게 뜨는 경우가 많아 창을 넓게 잡는다
OCR_WINDOW_BEFORE = 5.0
OCR_WINDOW_AFTER = 10.0
DESCRIPTION_LIMIT = 8000
# 숫자는 멀쩡한 오답으로 나와 눈에 띄지 않는다. 문맥만으로 바꾼 숫자는 지어낸 값일 수 있다
NUMBER_RE = re.compile(r"\d+(?:[.,]\d+)*")
NUM_CHECK_MARK = " (수치 확인 필요)"


def numbers(text: str) -> list[str]:
    return sorted(n.replace(",", "") for n in NUMBER_RE.findall(text))


def meta_from_info(info: dict) -> dict:
    return {
        "title": info.get("title"),
        "channel": info.get("channel") or info.get("uploader"),
        "upload_date": info.get("upload_date"),
        "url": info.get("webpage_url"),
        "description": (info.get("description") or "")[:DESCRIPTION_LIMIT],
        "tags": info.get("tags") or [],
        "chapters": [
            {"start": c.get("start_time"), "title": c.get("title")} for c in (info.get("chapters") or [])
        ],
    }


def ocr_near(spans: list[dict], start: float, end: float) -> list[str]:
    lo, hi = start - OCR_WINDOW_BEFORE, end + OCR_WINDOW_AFTER
    seen: list[str] = []
    for s in spans:
        if s["end"] > lo and s["start"] < hi and s["text"] not in seen:
            seen.append(s["text"])
    return seen


def build_correction_input(
    meta: dict, segments: list[dict], cues: list[dict], sub_kind: str, ocr_spans: list[dict], uncovered: list[dict]
) -> dict:
    rows = []
    for s in segments:
        row: dict[str, Any] = {"id": s["id"], "start": s["start"], "end": s["end"], "text": s["text"]}
        if s.get("recovered"):
            row["recovered"] = True  # 본 전사에서 빠져 해당 구간만 다시 전사한 문장
        if cues:
            row["sub"] = overlap_text(cues, s["start"], s["end"])
        near = ocr_near(ocr_spans, s["start"], s["end"])
        if near:
            row["ocr"] = near
        rows.append(row)
    return {"meta": meta, "youtube_sub_kind": sub_kind, "segments": rows, "uncovered": uncovered}


def apply_corrections(segments: list[dict], corrections: list[dict], source: str) -> tuple[list[dict], list[dict]]:
    """before가 세그먼트 원문에 글자 그대로, 정확히 한 번 있을 때만 그 부분만 바꾼다.

    한 세그먼트의 교정들은 모두 '교정 전 원문' 기준 위치로 확정한 뒤 뒤에서부터 한꺼번에 치환한다.
    (앞 교정이 넣은 글자를 뒤 교정이 다시 바꾸는 연쇄 오적용 방지) 적용 여부는 모두 기록한다.
    """
    segs = copy.deepcopy(segments)
    by_id = {s["id"]: s for s in segs}
    log: list[dict] = []
    planned: dict[int, list[tuple[int, int, str, dict]]] = {}
    for c in corrections:
        entry = {**c, "source": source}
        log.append(entry)
        seg = by_id.get(c["id"])
        before = c.get("before") or ""
        if seg is None:
            entry["status"] = "skipped: unknown id"
            continue
        if not before or before == c.get("after"):
            entry["status"] = "skipped: empty or no-op"
            continue
        if c.get("evidence") == "context" and numbers(before) != numbers(c.get("after") or ""):
            entry["status"] = "skipped: 숫자는 문맥 근거만으로 고치지 않음"
            continue
        count = seg["text"].count(before)
        if count == 0:
            entry["status"] = "skipped: before not found"
            continue
        if count > 1:
            entry["status"] = "skipped: ambiguous (before appears multiple times)"
            continue
        pos = seg["text"].index(before)
        span = (pos, pos + len(before))
        if any(span[0] < e and s < span[1] for s, e, _, _ in planned.get(seg["id"], [])):
            entry["status"] = "skipped: overlaps another correction"
            continue
        planned.setdefault(seg["id"], []).append((span[0], span[1], c["after"], entry))
    for seg_id, edits in planned.items():
        text = by_id[seg_id]["text"]
        for start, end, after, entry in sorted(edits, key=lambda e: e[0], reverse=True):
            text = text[:start] + after + text[end:]
            entry["status"] = "applied"
        by_id[seg_id]["text"] = text
    return segs, log


MAX_INSERT_OVERLAP = 0.5


def apply_structure(
    segments: list[dict], insertions: list[dict], deletions: list[dict], duration: float | None = None
) -> tuple[list[dict], list[dict]]:
    segs = copy.deepcopy(segments)
    by_id = {s["id"]: s for s in segs}
    log = []
    for d in deletions:
        seg = by_id.get(d["id"])
        status = "applied" if seg else "skipped: unknown id"
        if seg:
            seg["deleted"] = d["reason"]
        log.append({"type": "deletion", **d, "text": seg["text"] if seg else None, "status": status})

    next_id = max((s["id"] for s in segs), default=-1) + 1
    for ins in insertions:
        entry = {"type": "insertion", **ins}
        log.append(entry)
        start, end, text = ins.get("start", -1), ins.get("end", -1), (ins.get("text") or "").strip()
        if not text:
            entry["status"] = "skipped: empty text"
            continue
        if not (0 <= start < end) or (duration is not None and end > duration + 1.0):
            entry["status"] = "skipped: invalid time range"
            continue
        # 이미 살아 있는 세그먼트가 덮고 있는 구간에 '복원'하면 발화가 중복된다
        covered = sum(
            max(0.0, min(end, s["end"]) - max(start, s["start"])) for s in segs if not s.get("deleted")
        )
        if covered / (end - start) > MAX_INSERT_OVERLAP:
            entry["status"] = "skipped: overlaps existing speech"
            continue
        segs.append({"id": next_id, "start": start, "end": end, "text": text, "inserted": ins.get("evidence")})
        entry.update(id=next_id, status="applied")
        next_id += 1
    segs.sort(key=lambda s: (s["start"], s["id"]))
    return segs, log


def flag_numbers(segments: list[dict], cues: list[dict], kind: str) -> int:
    """숫자 판독이 갈리는 세그먼트에 num_check를 단다. 표시한 수를 돌려준다.

    영상: 같은 시간대 유튜브 자막에도 숫자가 있는데 Whisper와 다르면 표시한다 (자막이 숫자를 한글로 썼으면 비교하지 않는다).
    녹음: 숫자가 든 단어의 인식 확률이 낮았던 세그먼트(num_low_conf)를 표시한다.
    """
    count = 0
    for s in segments:
        if s.get("deleted"):
            continue
        mine = set(numbers(s["text"]))
        if kind == "recording":
            flagged = bool(s.get("num_low_conf") and mine)
        else:
            theirs = set(numbers(overlap_text(cues, s["start"] - 1.0, s["end"] + 1.0)))
            flagged = bool(mine and theirs and not mine <= theirs)
        if flagged:
            s["num_check"] = True
            count += 1
    return count


def render_txt(segments: list[dict]) -> str:
    return "\n".join(s["text"] for s in segments if not s.get("deleted")) + "\n"


def render_srt(segments: list[dict]) -> str:
    out = []
    for i, s in enumerate((s for s in segments if not s.get("deleted")), 1):
        out.append(f"{i}\n{fmt_ts(s['start'])} --> {fmt_ts(s['end'])}\n{s['text']}\n")
    return "\n".join(out)


def render_md(meta: dict, segments: list[dict], notes: list[dict]) -> str:
    # 화면 설명은 세그먼트 id가 아니라 시각으로 붙인다.
    # (환각으로 삭제된 세그먼트를 가리키는 설명도 버리지 않고 직전의 살아 있는 세그먼트 아래에 둔다)
    alive = [s for s in segments if not s.get("deleted")]
    notes_by_id: dict[int, list[dict]] = {}
    orphans: list[dict] = []
    for n in sorted(notes, key=lambda n: n["time"]):
        host = next((s for s in reversed(alive) if s["start"] <= n["time"]), alive[0] if alive else None)
        if host is None:
            orphans.append(n)
        else:
            notes_by_id.setdefault(host["id"], []).append(n)
    lines = [f"# {meta.get('title')}", ""]
    for key, label in (("channel", "채널"), ("upload_date", "업로드"), ("url", "URL")):
        if meta.get(key):
            lines.append(f"- {label}: {meta[key]}")
    lines += ["", "## 전사", ""]
    for s in segments:
        if s.get("deleted"):
            continue
        mark = " (복원)" if s.get("inserted") else " (재전사)" if s.get("recovered") else ""
        lines.append(f"[{fmt_ts(s['start'], '.')[:8]}]{mark} {s['text']}{NUM_CHECK_MARK if s.get('num_check') else ''}")
        for n in notes_by_id.get(s["id"], []):
            lines.append(f"> [화면 {fmt_ts(n['time'], '.')[:8]}] {n['description']}")
    for n in orphans:
        lines.append(f"> [화면 {fmt_ts(n['time'], '.')[:8]}] {n['description']}")
    return "\n".join(lines) + "\n"
