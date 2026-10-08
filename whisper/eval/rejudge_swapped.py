"""위치 편향 보정: results.jsonl에 저장된 A/B 분석을 반대 순서로 다시 채점하고, 두 채점을 합친 보고서를 만든다.

    uv run eval/rejudge_swapped.py

첫 채점에서 B가 X였으면 이번에는 Y로 둔다(첫 채점 순서는 저장하지 않았으므로 무작위 재배치 대신
두 순서를 모두 새로 채점한다). 두 순서의 선호가 엇갈리면 동률로 기록한다. 전사문은 자르지 않는다.
"""

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT))

from eval.ab_analysis import JUDGE_PROMPT, JUDGE_SCHEMA, RUBRIC, build_inputs  # noqa: E402
from ytscribe import llm  # noqa: E402

RESULTS = ROOT / "eval" / "results.jsonl"
SWAPPED = ROOT / "eval" / "results_balanced.jsonl"


def judge(ctx: dict, domains: list[str], x: str, y: str, label: str) -> dict:
    checklist = "\n".join(llm.DOMAIN_GUIDES.get(d, "") for d in domains).strip() or "(분야 점검 항목 없음)"
    payload = json.dumps({"meta": ctx["meta"], "domains": domains, "checklist": checklist, "transcript": ctx["md"],
                          "X": x, "Y": y}, ensure_ascii=False)
    return llm.run_claude(JUDGE_PROMPT, payload, schema=JUDGE_SCHEMA, label=label)


def main() -> None:
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]
    done = {}
    if SWAPPED.exists():
        for line in SWAPPED.read_text(encoding="utf-8").splitlines():
            try:
                r = json.loads(line)
                done[r["id"]] = r
            except json.JSONDecodeError:
                print("[rejudge] 손상된 줄 건너뜀")
    rows = []
    for line in RESULTS.read_text(encoding="utf-8").splitlines():
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            print("[rejudge] results.jsonl 손상된 줄 건너뜀")
    for r in rows:
        if r["id"] in done:
            continue
        ctx, _, _ = build_inputs(ROOT / "output" / r["id"])
        # 두 순서로 각각 채점: AB(A=X), BA(B=X)
        ab = judge(ctx, r["domains"], r["analysis_A"], r["analysis_B"], f"judge-AB:{r['id']}")
        ba = judge(ctx, r["domains"], r["analysis_B"], r["analysis_A"], f"judge-BA:{r['id']}")
        score_a = {k: (ab["X"][k] + ba["Y"][k]) / 2 for k in RUBRIC}
        score_b = {k: (ab["Y"][k] + ba["X"][k]) / 2 for k in RUBRIC}
        p1 = {"X": "A", "Y": "B", "tie": "tie"}[ab["preference"]]
        p2 = {"X": "B", "Y": "A", "tie": "tie"}[ba["preference"]]
        pref = p1 if p1 == p2 else "tie"
        out = {k: r[k] for k in ("id", "expected", "desc", "domains")}
        out.update(A=score_a, B=score_b, preference=pref, prefs=[p1, p2], reason=f"AB: {ab['reason']} / BA: {ba['reason']}")
        with SWAPPED.open("a", encoding="utf-8") as f:
            f.write(json.dumps(out, ensure_ascii=False) + "\n")
        done[r["id"]] = out
        print(f"[rejudge] {r['id']} AB={p1} BA={p2} → {pref}")

    from eval.ab_analysis import report
    ordered = [done[r["id"]] for r in rows if r["id"] in done]
    text = report(ordered).replace("# 분야별 분석 지침 A/B 평가",
                                   "# 분야별 분석 지침 A/B 평가 (두 순서 채점 평균, 위치 편향 보정)", 1)
    text += ("\n## 방법 보정\n\n- 같은 분석 쌍을 AB·BA 두 순서로 채점해 점수를 평균했고, 두 순서의 선호가 엇갈리면 동률로 처리했다.\n"
             "- 채점자에게 전사문 전체를 줬다 (첫 채점은 30,000자까지).\n"
             "- 과학·건강은 B에만 '근거 수준' 섹션 제목이 있어 블라인드가 완전하지 않다.\n")
    out_path = ROOT / "docs" / "eval-domain-guides.md"
    out_path.write_text(text, encoding="utf-8")
    print(f"[rejudge] 보고서 -> {out_path} ({len(ordered)}개)")


if __name__ == "__main__":
    main()
