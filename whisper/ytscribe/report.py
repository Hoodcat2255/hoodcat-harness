"""이미지가 들어간 요약 보고서: 후보 프레임 구성 → 요약에 삽입된 이미지 검증 → 단일 HTML 렌더링."""

import base64
import html
import re
import shutil
from pathlib import Path

import markdown

from .asr import fmt_ts

MAX_CANDIDATES = 25
NOTE_NEARBY_S = 10.0
_IMG_RE = re.compile(r"!\[([^\]]*)\]\(([^)\s]+)\)")


def build_candidates(
    work: Path, notes: list[dict], ocr_frames: list[dict], frames_dir: Path | None, image_dir: str = "summary_images"
) -> list[dict]:
    """요약에 넣을 수 있는 이미지 후보.

    1) 화면 분석(visual) 프레임: Claude가 쓴 설명이 있다.
    2) OCR 프레임 중 앞선 후보에 없던 화면 글자가 2개 이상 새로 나온 것 (판서·슬라이드 진행).
    """
    cands: list[dict] = []
    for n in notes:
        src = work / "visual" / f"t{float(n['time']):07.1f}.jpg"
        if src.exists():
            cands.append({"time": float(n["time"]), "src": src, "desc": n["description"]})

    seen: set[str] = set()
    for f in ocr_frames:
        new = [t for t in f["texts"] if t not in seen]
        seen.update(f["texts"])
        src = frames_dir / f["frame"] if frames_dir else None
        if len(new) < 2 or src is None or not src.exists():
            continue
        if any(abs(c["time"] - f["t"]) < NOTE_NEARBY_S for c in cands):
            continue  # 설명이 있는 화면 분석 프레임을 우선한다
        cands.append({"time": float(f["t"]), "src": src, "desc": "화면 글자: " + " / ".join(new[:8])})

    cands.sort(key=lambda c: c["time"])
    cands = cands[:MAX_CANDIDATES]
    for c in cands:
        c["path"] = f"{image_dir}/t{int(c['time']):05d}.jpg"
    return cands


def candidates_prompt(cands: list[dict]) -> str:
    return "\n".join(f"- {c['path']} [{fmt_ts(c['time'], '.')[3:8]}] {c['desc']}" for c in cands)


def finalize(work: Path, summary_md: str, cands: list[dict], image_dir: str = "summary_images") -> tuple[str, list[str]]:
    """문서가 참조한 이미지만 image_dir/로 복사한다. 후보에 없는 경로의 이미지 태그는 지운다."""
    by_path = {c["path"]: c for c in cands}
    used: list[str] = []
    dropped: list[str] = []

    def repl(m: re.Match) -> str:
        path = m.group(2)
        if path not in by_path:
            dropped.append(path)
            return ""
        if path not in used:
            used.append(path)
        return m.group(0)

    cleaned = _IMG_RE.sub(repl, summary_md)
    out_dir = work / image_dir
    if out_dir.exists():
        shutil.rmtree(out_dir)
    if used:
        out_dir.mkdir()
        for path in used:
            shutil.copy(by_path[path]["src"], work / path)
    if dropped:
        print(f"[report] 후보에 없는 이미지 참조 {len(dropped)}건 제거: {', '.join(dropped[:5])}")
    return cleaned, used


CSS = """
:root { --bg:#fff; --fg:#1f2328; --muted:#59636e; --border:#d1d9e0; --code:#f6f8fa; --accent:#0969da; }
@media (prefers-color-scheme: dark) {
  :root { --bg:#0d1117; --fg:#e6edf3; --muted:#9198a1; --border:#3d444d; --code:#151b23; --accent:#4493f8; }
}
* { box-sizing: border-box; }
body { margin:0; background:var(--bg); color:var(--fg);
  font: 16px/1.7 -apple-system, "Segoe UI", "Noto Sans KR", "Noto Sans CJK KR", "Apple SD Gothic Neo", sans-serif; }
main { max-width: 860px; margin: 0 auto; padding: 32px 16px 64px; }
h1 { font-size: 1.8em; border-bottom: 1px solid var(--border); padding-bottom: .3em; }
h2 { font-size: 1.4em; margin-top: 2em; border-bottom: 1px solid var(--border); padding-bottom: .2em; }
h3 { font-size: 1.15em; margin-top: 1.6em; }
a { color: var(--accent); }
table { border-collapse: collapse; margin: 1em 0; display: block; overflow-x: auto; }
th, td { border: 1px solid var(--border); padding: 6px 12px; }
th { background: var(--code); }
code { background: var(--code); padding: .1em .4em; border-radius: 4px; }
figure { margin: 1.2em 0; }
figure img { max-width: 100%; border: 1px solid var(--border); border-radius: 6px; display: block; }
figcaption { color: var(--muted); font-size: .9em; margin-top: .4em; }
.meta { color: var(--muted); font-size: .9em; }
@page { size: A4; margin: 16mm 14mm; }
@media print {
  :root { --bg:#fff; --fg:#1f2328; --muted:#59636e; --border:#d1d9e0; --code:#f6f8fa; --accent:#0969da; }
  body { font-size: 10.5pt; }
  main { max-width: none; padding: 0; }
  h1, h2, h3 { break-after: avoid; }
  figure, tr, img { break-inside: avoid; }
  figure img { max-height: 95mm; width: auto; margin: 0 auto; }
  table { display: table; width: 100%; font-size: 9.5pt; }
  a { color: var(--fg); text-decoration: none; }
}
"""


_ATTR_RE = re.compile(r'\b(href|src)="([^"]*)"')
_LIST_RE = re.compile(r"^( *)([-*+]|\d+[.)])\s")


def normalize_lists(md: str) -> str:
    """LLM이 쓴 마크다운을 Python-Markdown 규칙에 맞춘다.

    Python-Markdown은 하위 목록에 4칸 들여쓰기와 목록 앞 빈 줄을 요구하지만, 생성된 문서는 2칸 들여쓰기에
    문단 바로 다음 줄에서 목록을 시작하는 경우가 많아 목록이 한 문단으로 뭉개졌다.
    원래 들여쓰기의 '상대적 깊이'를 구해 단계마다 4칸으로 다시 쓴다 (목록 첫 항목은 0단계).
    """
    out: list[str] = []
    stack: list[int] = []  # 현재 열린 목록 단계들의 원래 들여쓰기
    in_code = False
    for line in md.splitlines():
        if line.lstrip().startswith("```"):
            in_code = not in_code
        m = None if in_code else _LIST_RE.match(line)
        if m:
            indent = len(m.group(1))
            if not stack:
                prev = out[-1] if out else ""
                if prev.strip() and not prev.lstrip().startswith("|"):
                    out.append("")
            while stack and indent < stack[-1]:
                stack.pop()
            if not stack or indent > stack[-1]:
                stack.append(indent)
            out.append("    " * (len(stack) - 1) + line[indent:])
            continue
        if line.strip() and not line.startswith(" "):
            stack = []  # 들여쓰지 않은 일반 줄이 나오면 목록이 끝난 것
        elif line.strip() and stack:
            line = "    " * len(stack) + line.lstrip()  # 항목의 이어지는 줄
        out.append(line)
    return "\n".join(out)


def sanitize_urls(body: str) -> str:
    """Python-Markdown은 링크 URL을 정화하지 않는다. href는 http(s)·#·상대경로만, src는 직접 넣은 jpeg data URI만 남긴다."""

    def check(m: re.Match) -> str:
        attr, url = m.group(1), m.group(2)
        low = html.unescape(url).strip().lower()
        if attr == "src":
            ok = low.startswith("data:image/jpeg;base64,")
        else:
            scheme = re.match(r"^([a-z][a-z0-9+.-]*):", low)
            ok = low.startswith("#") or (scheme is None and not low.startswith("//")) or \
                (scheme is not None and scheme.group(1) in ("http", "https"))
        return f'{attr}="{url}"' if ok else f'{attr}="#"'

    return _ATTR_RE.sub(check, body)


def render_pdf(html_path: Path, pdf_path: Path) -> None:
    """Chrome headless로 HTML을 PDF로 출력한다 (이미지·표·한글 그대로). 사용자 Chrome 프로필은 건드리지 않는다."""
    import shutil
    import subprocess
    import tempfile

    # macOS에서 GUI 로그인 없이(SSH 등) 실행하면 데스크톱 Chrome은 headless로도 뜨지 않는다 → chrome-headless-shell 우선
    # 설치: npx @puppeteer/browsers install chrome-headless-shell@stable --path ~/.cache/chrome-headless-shell
    shells = sorted(Path.home().glob(".cache/chrome-headless-shell/chrome-headless-shell/*/*/chrome-headless-shell"))
    mac_apps = ("/Applications/Google Chrome.app/Contents/MacOS/Google Chrome",
                "/Applications/Chromium.app/Contents/MacOS/Chromium")
    chrome = next((shutil.which(b) for b in ("google-chrome", "google-chrome-stable", "chromium", "chromium-browser")
                   if shutil.which(b)), None) or next(
        (str(a) for a in [*shells[-1:], *map(Path, mac_apps)] if a.exists()), None)
    if chrome is None:
        raise RuntimeError("PDF 변환에 필요한 Chrome/Chromium을 찾을 수 없습니다.")
    headless = [] if chrome.endswith("chrome-headless-shell") else ["--headless=new"]
    with tempfile.TemporaryDirectory() as profile:
        proc = subprocess.run(
            [chrome, *headless, "--disable-gpu", "--no-first-run", f"--user-data-dir={profile}",
             "--no-pdf-header-footer", "--run-all-compositor-stages-before-draw", "--virtual-time-budget=5000",
             f"--print-to-pdf={pdf_path}", html_path.resolve().as_uri()],
            capture_output=True, text=True, timeout=180,
        )
    if proc.returncode != 0 or not pdf_path.exists():
        raise RuntimeError(f"PDF 변환 실패: {proc.stderr.strip()[-300:]}")


def render_html(work: Path, summary_md: str, meta: dict) -> str:
    """이미지를 base64로 넣은 단일 HTML (파일 하나로 열람·공유 가능)."""

    root = work.resolve()

    def embed(m: re.Match) -> str:
        alt, path = m.group(1), m.group(2)
        p = (work / path).resolve()
        # 작업 디렉터리의 *_images/ 안 jpg만 넣는다 (절대경로·../ 로 로컬 파일을 끌어오는 것 차단)
        if not (p.is_relative_to(root) and p.parent.name.endswith("_images") and p.suffix == ".jpg" and p.is_file()):
            return ""
        data = base64.b64encode(p.read_bytes()).decode()
        cap = html.escape(alt)
        return f'\n<figure><img src="data:image/jpeg;base64,{data}" alt="{cap}"><figcaption>{cap}</figcaption></figure>\n'

    # 요약문은 LLM 출력이므로 원본 HTML은 글자로 보이게 이스케이프한다 (스크립트 삽입 방지). 그다음 이미지만 figure로 바꾼다.
    escaped = normalize_lists(summary_md).replace("<", "&lt;")
    body_md = _IMG_RE.sub(embed, escaped)
    body = sanitize_urls(markdown.markdown(body_md, extensions=["tables", "sane_lists"]))
    src = ""
    if meta.get("url"):
        url = html.escape(meta["url"])
        src = f'<p class="meta">원본: <a href="{url}">{html.escape(meta.get("title") or url)}</a>'
        if meta.get("channel"):
            src += f" · {html.escape(meta['channel'])}"
        src += "</p>"
    title = html.escape(meta.get("title") or "요약")
    return (f'<!doctype html><html lang="ko"><head><meta charset="utf-8">'
            f'<meta name="viewport" content="width=device-width, initial-scale=1">'
            f"<title>{title}</title><style>{CSS}</style></head><body><main>{src}{body}</main></body></html>\n")
