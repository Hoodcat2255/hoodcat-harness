"""Claude로 보내기 전 전사문의 개인정보를 가린다 (녹음본 기본).

전사 원본(asr.json)은 로컬에만 남기고, 교정·문서 단계에는 가린 텍스트만 넘긴다.
Whisper가 숫자를 한글로 받아 적은 경우("공일공 일이삼사…")는 잡지 못한다.
"""

import re

# 순서가 중요하다: 주민번호·카드번호를 전화·계좌 패턴보다 먼저 가린다
PATTERNS: list[tuple[str, re.Pattern]] = [
    ("주민등록번호", re.compile(r"(?<!\d)\d{6}\s?-\s?[1-8]\d{6}(?!\d)")),
    ("카드번호", re.compile(r"(?<!\d)\d{4}(?:[\s-]\d{4}){3}(?!\d)")),
    ("이메일", re.compile(r"[\w.+-]+@[\w-]+(?:\.[\w-]+)+")),
    ("전화번호", re.compile(r"(?<!\d)(?:\+82[\s-]?)?0\d{1,2}[\s.-]?\d{3,4}[\s.-]?\d{4}(?!\d)")),
    ("계좌번호", re.compile(r"(?<!\d)\d{2,6}-\d{2,6}-\d{2,8}(?:-\d{1,4})?(?!\d)")),
]

_DATE_RE = re.compile(r"(?:19|20)\d{2}-(?:0?[1-9]|1[0-2])-(?:0?[1-9]|[12]\d|3[01])")


def _is_account(m: re.Match) -> bool:
    # 날짜(2026-10-04)는 제외하고, 국내 계좌번호 길이(10자리 이상)일 때만 가린다
    text = m.group(0)
    return not _DATE_RE.fullmatch(text) and sum(c.isdigit() for c in text) >= 10


def mask(text: str) -> tuple[str, dict[str, int]]:
    counts: dict[str, int] = {}
    for label, pat in PATTERNS:
        n = 0

        def repl(m: re.Match, label=label) -> str:
            nonlocal n
            if label == "계좌번호" and not _is_account(m):
                return m.group(0)
            n += 1
            return f"[{label}]"

        text = pat.sub(repl, text)
        if n:
            counts[label] = counts.get(label, 0) + n
    return text, counts


def mask_segments(segments: list[dict]) -> tuple[list[dict], dict[str, int]]:
    total: dict[str, int] = {}
    out = []
    for s in segments:
        text, counts = mask(s["text"])
        for k, v in counts.items():
            total[k] = total.get(k, 0) + v
        out.append({**s, "text": text})
    return out, total
