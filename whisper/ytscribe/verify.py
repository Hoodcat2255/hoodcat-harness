"""분석에서 뽑은 주장을 웹 검색으로 확인하고, 출처를 코드에서 다시 검증한다.

WebSearch는 검색어·결과 도메인을 권한으로 제한할 수 없으므로(공식 문서), 모델이 '확인됨'이라고 해도
근거 URL이 신뢰 도메인에 없으면 '미확인'으로 낮춘다. 영상 설명란에 심은 지시로 공격자 페이지를 근거 삼는
'거짓 검증'을 막기 위함이다.
"""

import re
from pathlib import Path
from urllib.parse import quote, urlparse

TRUSTED_FILE = Path(__file__).resolve().parent.parent / "trusted_domains.txt"
POSITIVE = {"supported", "contradicted", "partly", "outdated"}
LABELS = {
    "supported": "✅ 사실",
    "contradicted": "❌ 사실과 다름",
    "partly": "⚠️ 일부 사실",
    "outdated": "🕒 이후 변경",
    "unverified": "❔ 미확인",
}


def load_trusted(path: Path = TRUSTED_FILE) -> list[str]:
    domains = []
    for line in path.read_text(encoding="utf-8").splitlines():
        line = line.split("#", 1)[0].strip().lower()
        if line:
            domains.append(line)
    return domains


_HOST_RE = re.compile(r"^[a-z0-9.-]+$")
# 역슬래시·userinfo·공백·제어문자: urlparse와 브라우저(WHATWG)가 호스트를 다르게 해석하는 우회에 쓰인다
_BAD_URL_RE = re.compile(r"[\\@\s\x00-\x1f\x7f]")


def is_trusted(url: str, trusted: list[str]) -> bool:
    if _BAD_URL_RE.search(url):
        return False
    try:
        parsed = urlparse(url)
    except ValueError:
        return False
    host = (parsed.hostname or "").lower().rstrip(".")
    if parsed.scheme not in ("http", "https") or not host or not _HOST_RE.match(host):
        return False
    return any(host == d or host.endswith("." + d) for d in trusted)


def safe_url(url: str) -> str | None:
    """표에 링크로 넣어도 되는 http(s) URL만 퍼센트 인코딩해서 돌려준다."""
    if _BAD_URL_RE.search(url) or urlparse(url).scheme not in ("http", "https"):
        return None
    return quote(url, safe=":/?#&=%.-_~+,;")


def validate(results: list[dict], claims: list[dict], trusted: list[str]) -> list[dict]:
    """모델 판정을 출처 기준으로 재검증한다. 신뢰 출처가 없으면 판정을 unverified로 낮춘다."""
    # 주장 목록 기준으로 순회한다: 모델이 빠뜨린 주장은 미확인으로 채우고, 중복 결과는 첫 번째만 쓴다
    first: dict = {}
    for r in results:
        first.setdefault(r.get("id"), r)
    out = []
    for claim in claims:
        r = first.get(claim["id"]) or {"verdict": "unverified", "summary": "검색 결과 없음", "sources": []}
        sources = [{**s, "trusted": is_trusted(s.get("url", ""), trusted)} for s in r.get("sources", [])]
        verdict = r.get("verdict", "unverified")
        note = ""
        if verdict in POSITIVE and not any(s["trusted"] for s in sources):
            note = f"신뢰 출처가 없어 '{LABELS.get(verdict, verdict)}' 판정을 보류함"
            verdict = "unverified"
        out.append({"id": claim["id"], "claim": claim["claim"], "verdict": verdict,
                    "summary": r.get("summary", ""), "sources": sources, "note": note})
    return out


def _cell(text: str) -> str:
    # 표 셀 안에서 마크다운 링크·이미지 문법이 만들어지지 않도록 기호를 이스케이프한다
    text = re.sub(r"([\\`*_\[\]()!|<>])", r"\\\1", text)
    return text.replace("\n", " ").strip()


def render(checked: list[dict], today: str) -> str:
    lines = [f"### 사실 확인 결과 (웹 검색, {today} 기준)", "",
             "> 신뢰 도메인 목록(`trusted_domains.txt`)에 있는 출처만 근거로 인정했다. "
             "판정은 검색 시점 기준이며, 중요한 내용은 원문을 직접 확인할 것.", "",
             "| 주장 | 판정 | 확인 내용 | 출처 |", "|---|---|---|---|"]
    for c in checked:
        # http(s)가 아닌 URL(javascript: 등)이나 우회 문자가 든 URL은 링크로 만들지 않는다
        web = [{**s, "safe": safe_url(s.get("url", ""))} for s in c["sources"]]
        web = [s for s in web if s["safe"]]
        srcs = [s for s in web if s["trusted"]] or web
        links = " · ".join(
            f"[{_cell(s.get('title') or urlparse(s['safe']).hostname or '출처')}]({s['safe']})"
            + ("" if s["trusted"] else " (비신뢰)")
            for s in srcs[:3]
        ) or "–"
        summary = _cell(c["summary"]) + (f" ({c['note']})" if c["note"] else "")
        lines.append(f"| {_cell(c['claim'])} | {LABELS.get(c['verdict'], c['verdict'])} | {summary} | {links} |")
    return "\n".join(lines) + "\n"
