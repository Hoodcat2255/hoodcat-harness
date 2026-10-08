"""분야 판별 프롬프트 비교: eval/domains_gold.txt 정답 대비 정확도.

    uv run eval/classify_check.py [--model haiku]
"""

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from transcribe import CLASSIFY_TRANSCRIPT_CHARS  # noqa: E402
from ytscribe import llm  # noqa: E402
from ytscribe.correct import meta_from_info  # noqa: E402

OLD_PROMPT = (ROOT / "eval" / "classify_prompt_v1.txt").read_text(encoding="utf-8")


def payload_for(vid: str) -> str:
    work = ROOT / "output" / vid
    meta = meta_from_info(json.loads((work / "info.json").read_text(encoding="utf-8")))
    md = (work / "transcript.md").read_text(encoding="utf-8")
    return json.dumps({k: meta[k] for k in ("title", "channel", "description", "tags", "chapters")},
                      ensure_ascii=False)[:4000] + "\n\n" + md[:CLASSIFY_TRANSCRIPT_CHARS]


def main() -> None:
    p = argparse.ArgumentParser()
    p.add_argument("--model", default="haiku")
    p.add_argument("--gold", default=str(ROOT / "eval" / "domains_gold.txt"))
    args = p.parse_args()
    gold = []
    for line in Path(args.gold).read_text(encoding="utf-8").splitlines():
        if line.strip() and not line.startswith("#"):
            vid, primary, alt, *desc = line.split()
            ok = {primary} | (set(alt.split("|")) if alt != "-" else set())
            gold.append((vid, primary, ok, " ".join(desc)))
    score = {"old": 0, "new": 0}
    missing = [vid for vid, *_ in gold if not (ROOT / "output" / vid / "transcript.md").exists()]
    if missing:
        print(f"[skip] 전사가 없어 제외: {', '.join(missing)}")
    gold = [g for g in gold if g[0] not in missing]
    for vid, primary, ok, desc in gold:
        pl = payload_for(vid)
        row = []
        for name, prompt in (("old", OLD_PROMPT), ("new", llm.CLASSIFY_PROMPT)):
            r = llm.run_claude(prompt, pl, schema=llm.CLASSIFY_SCHEMA, model=args.model, label=f"{name}:{vid}")
            hit = r["domain"] in ok
            score[name] += hit
            row.append(f"{name}={r['domain']}{'+' + ','.join(r['secondary_domains']) if r['secondary_domains'] else ''}"
                       f"{'' if hit else ' ✗'}")
        print(f"{desc[:24]:24s} 정답={primary:9s} " + "  ".join(row), flush=True)
    n = len(gold)
    print(f"\n정확도 old {score['old']}/{n}, new {score['new']}/{n} (model={args.model})")


if __name__ == "__main__":
    main()
