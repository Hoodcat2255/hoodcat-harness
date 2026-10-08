"""유튜브 URL 또는 로컬 음원/영상을 전사하고, 메타데이터·자막·화면(OCR/프레임)으로 교정한 뒤 요약한다.

단계 (결과는 output/<영상ID>/ 에 캐시되어 재실행 시 건너뜀, --force로 무시):
  1. fetch     음원·720p 영상·info.json·유튜브 자막(수동/자동)
  2. ocr       영상 프레임 추출(N초 간격) → 중복 제거 → 화면 텍스트 OCR (--ocr) [P2]
  3. glossary  설명란·태그·OCR에서 고유명사 추출 → Whisper hotwords            [P0]
  4. asr       faster-whisper large-v3
  5. correct   Claude 교정: 설명란·자막·OCR 근거로 오인식 교체, 누락 복원, 환각 삭제 [P0/P1]
  6. visual    화면을 봐야 하는 발화만 프레임을 Claude가 직접 보고 설명·교정   [P3]
  7. document  영상 성격에 맞춰 요약/정리/학습 노트 + 이미지 (--summarize, --mode)

사용 예:
    uv run transcribe.py "https://www.youtube.com/watch?v=..." --summarize            # 형식 자동 판별
    uv run transcribe.py URL --summarize --mode notes                                 # 학습 노트
    uv run transcribe.py lecture.mp4 --no-visual
    uv run transcribe.py URL --summarize --ocr     # 화면 자막으로 고유명사 교정 (느림)
    uv run transcribe.py URL --asr-only            # 전사만 (Claude 호출 없음)
"""

import argparse
import hashlib
import json
import os
import re
import shutil
import sys
from pathlib import Path
from typing import Any

import datetime

from ytscribe import correct, fetch, frames, llm, privacy, report, verify
from ytscribe.asr import transcribe as run_asr
from ytscribe.subs import parse_vtt, uncovered_spans

# Whisper 힌트 비교 실험 (CER):
#   KBS 리포트(설명란 원고 대비): 힌트 없음 0.205 / 제목 initial_prompt 0.373 + 크레딧 환각 / 상위 12개 hotwords 0.202
#   전기 강의(유튜브 자막 대비): 힌트 없음 0.104 / 용어 hotwords 0.374 + "정전기 전병칠…" 반복 환각 8건
# → 자동 추출 용어를 Whisper에 넣지 않는다. 용어집은 교정 단계(Claude)에 표기 참고 자료로만 준다.
ASR_VERSION = 4  # 전사 로직이 바뀌면 올린다 (asr.json 캐시 무효화). 2: 단어 타임스탬프 + 누락 구간 재전사, 3: 재전사 환각 필터, 4: 반복 세그먼트 제거


def fingerprint(obj: Any) -> str:
    return hashlib.sha256(json.dumps(obj, ensure_ascii=False, sort_keys=True).encode()).hexdigest()[:16]


def load_or(path: Path, key: Any, force: bool, fn, required: tuple[str, ...] = ()):
    """단계 결과 캐시. 입력 지문(key)이 같고 필수 키가 모두 있을 때만 재사용한다."""
    fp = fingerprint(key)
    if path.exists() and not force:
        try:
            cached = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            print(f"[warn] 캐시가 손상되어 다시 계산합니다: {path.name} ({e})")
        else:
            if cached.get("_key") == fp and all(k in cached for k in required):
                print(f"[cache] {path.name}")
                return cached
            print(f"[cache] {path.name} 입력이 바뀌어 다시 계산합니다")
    data = {**fn(), "_key": fp}
    write_atomic(path, json.dumps(data, ensure_ascii=False, indent=1))
    return data


def write_atomic(path: Path, text: str) -> None:
    tmp = path.with_name(path.name + ".tmp")
    tmp.write_text(text, encoding="utf-8")
    os.replace(tmp, path)


def use_video(work: Path, args) -> bool:
    return not (args.no_video or args.asr_only) and (work / "video.mp4").exists()


def step_ocr(work: Path, args) -> list[dict]:
    if not args.ocr or not use_video(work, args):
        return []
    video = work / "video.mp4"

    def run():
        all_frames = frames.extract_frames(video, work, args.frame_interval, force=args.force)
        kept = frames.dedupe(all_frames)
        print(f"[ocr] 프레임 {len(all_frames)}장 → 중복 제거 후 {len(kept)}장")
        ocr = frames.ocr_frames(kept)
        return {"frames": ocr, "spans": frames.to_spans(ocr, args.frame_interval)}

    key = {"interval": args.frame_interval, "video_size": video.stat().st_size, "v": 3}  # 3: 30초 최소 유지
    return load_or(work / "ocr.json", key, args.force, run)["spans"]


def step_glossary(work: Path, args, info: dict, spans: list[dict]) -> list[str]:
    if args.asr_only:
        return []
    meta = correct.meta_from_info(info)
    if not (meta["description"] or meta["tags"] or spans):
        return []
    payload = {"meta": {k: meta[k] for k in ("title", "description", "tags", "chapters")},
               "ocr_texts": sorted({s["text"] for s in spans})}

    def run():
        # 단순 추출 작업이라 빠른 모델로 충분하다
        return llm.run_claude(llm.adapt(llm.GLOSSARY_PROMPT, args.kind), json.dumps(payload, ensure_ascii=False),
                              schema=llm.GLOSSARY_SCHEMA, model="haiku", label="glossary")

    return load_or(work / "glossary.json", [payload, llm.GLOSSARY_PROMPT], args.force, run)["terms"]


def asr_options(args) -> dict[str, Any]:
    return {
        "model": args.model, "device": args.device, "compute_type": args.compute_type,
        "language": None if args.language == "auto" else args.language,
        "beam_size": args.beam_size, "batch_size": args.batch_size, "chunk_length": args.chunk_length,
        "initial_prompt": args.prompt, "hotwords": args.hotwords,
    }


def step_asr(work: Path, args, opts: dict) -> dict:
    audio = fetch.find_audio(work)

    def run():
        segments, meta = run_asr(audio, opts)
        return {"options": opts, "meta": meta, "segments": segments}

    # device는 OOM 시 CPU로 바뀌므로 지문에서 뺀다 (같은 설정의 GPU/CPU 결과는 재사용)
    key = {k: v for k, v in opts.items() if k not in ("device", "compute_type")} | {"v": ASR_VERSION, "audio": audio.name,
                                                                                      "size": audio.stat().st_size}
    return load_or(work / "asr.json", key, args.force or args.force_asr, run)


def load_subs(work: Path, langs: list[str]) -> tuple[list[dict], str]:
    for kind in ("manual", "auto"):
        p = fetch.find_subs(work, kind, langs)
        if p:
            cues = parse_vtt(p)
            print(f"[subs] {kind} 자막 {len(cues)}개 큐 ({p.name})")
            return cues, kind
    return [], "none"


CORRECT_CHUNK_CHARS = 20000   # 전사 텍스트가 이보다 길면 구간별로 나눠 교정한다 (한국어 약 1시간)
CORRECT_CHUNK_SECONDS = 900   # 구간 길이 15분


def chunk_by_time(segments: list[dict], seconds: float) -> list[list[dict]]:
    chunks: list[list[dict]] = []
    for s in segments:
        if not chunks or s["start"] - chunks[-1][0]["start"] >= seconds:
            chunks.append([])
        chunks[-1].append(s)
    return chunks


def step_correct(work: Path, args, meta: dict, segments, cues, sub_kind, spans, terms: list[str]) -> dict:
    uncovered = uncovered_spans(cues, segments) if cues else []
    if uncovered:
        print(f"[subs] Whisper 누락 의심 구간 {len(uncovered)}개: " +
              ", ".join(f"{s['start']:.0f}-{s['end']:.0f}s" for s in uncovered))
    max_visual = 0 if args.no_visual or not use_video(work, args) else args.max_visual
    prompt = llm.adapt(llm.CORRECT_PROMPT.format(max_visual=max_visual), args.kind)
    user = {"context": meta.get("context"), "terms": meta.get("user_terms"), "speakers": meta.get("speakers")}

    total_chars = sum(len(s["text"]) for s in segments)
    parts = [segments] if total_chars <= CORRECT_CHUNK_CHARS else chunk_by_time(segments, CORRECT_CHUNK_SECONDS)
    if len(parts) > 1:
        print(f"[correct] 전사가 길어 {len(parts)}개 구간으로 나눠 교정 ({total_chars:,}자)")
    merged: dict[str, list] = {"corrections": [], "insertions": [], "deletions": [], "visual_checks": []}
    for i, part in enumerate(parts):
        lo, hi = part[0]["start"], part[-1]["end"]
        part_uncovered = [u for u in uncovered if lo - 5 <= u["start"] <= hi + 5]
        payload = correct.build_correction_input(meta, part, cues, sub_kind, spans, part_uncovered)
        payload["glossary"] = terms
        payload["user"] = user
        if len(parts) > 1:
            payload["part"] = f"{i + 1}/{len(parts)} ({fmt_hms(lo)}~{fmt_hms(hi)})"
        text = json.dumps(payload, ensure_ascii=False)

        def run(text=text, i=i):
            return llm.run_claude(prompt, text, schema=llm.CORRECT_SCHEMA,
                                  label="correct" if len(parts) == 1 else f"correct {i + 1}/{len(parts)}")

        name = "correct.json" if len(parts) == 1 else f"correct_p{i + 1}.json"
        res = load_or(work / name, [payload, prompt], args.force, run,
                      required=("corrections", "insertions", "deletions", "visual_checks"))
        for k in merged:
            merged[k] += res[k]
    merged["visual_checks"] = merged["visual_checks"][: args.max_visual]
    return merged


def fmt_hms(sec: float) -> str:
    h, rem = divmod(int(sec), 3600)
    return f"{h:d}:{rem // 60:02d}:{rem % 60:02d}"


VISUAL_REASON_LIMIT = 100


def step_visual(work: Path, args, segments: list[dict], checks: list[dict], duration: float) -> dict:
    empty = {"notes": [], "corrections": []}
    if args.no_visual or not checks or not use_video(work, args):
        return empty
    video, vis_dir = work / "video.mp4", work / "visual"
    by_id = {s["id"]: s for s in segments}
    items = []
    for c in checks[: args.max_visual]:
        t = min(max(0.0, float(c["time"])), max(0.0, duration - 0.5))
        img = frames.grab_frame(video, t, vis_dir / f"t{t:07.1f}.jpg")
        if img is None:
            continue
        seg = by_id.get(c["id"], {})
        text = seg.get("text", "")
        if seg.get("deleted"):
            text = "(이 구간 전사는 환각으로 판정되어 삭제됨 — 화면으로 내용을 파악할 것)"
        # reason은 앞 단계 LLM이 쓴 자유 텍스트라 길이를 제한한다 (프롬프트 인젝션 전파 완화)
        items.append(f"- id={c['id']} time={t:.1f}s 이미지=./{img.name}\n"
                     f"  발화: {text}\n  확인 이유: {str(c['reason'])[:VISUAL_REASON_LIMIT]}")
    if not items:
        return empty
    prompt = llm.VISUAL_PROMPT.format(items="\n".join(items))

    def run():
        print(f"[visual] 프레임 {len(items)}장을 Claude로 분석")
        # 프레임 디렉터리 안의 jpg만 읽을 수 있게 제한한다
        return llm.run_claude(prompt, schema=llm.VISUAL_SCHEMA, image_dir=vis_dir.resolve(), label="visual")

    return load_or(work / "visual.json", prompt, args.force, run)


CLASSIFY_TRANSCRIPT_CHARS = 3000


def choose_mode(work: Path, args, meta: dict, md: str) -> dict:
    if args.mode != "auto":
        return {"mode": args.mode, "genre": "", "reason": "사용자 지정"}
    keys = ("title", "channel", "description", "tags", "chapters", "context", "speakers")
    payload = json.dumps({k: meta.get(k) for k in keys if meta.get(k)}, ensure_ascii=False)[:4000] + \
        "\n\n" + md[:CLASSIFY_TRANSCRIPT_CHARS]
    prompt = llm.CLASSIFY_RECORDING_PROMPT if args.kind == "recording" else llm.CLASSIFY_PROMPT
    allowed = llm.RECORDING_MODES if args.kind == "recording" else llm.VIDEO_MODES

    def run():
        res = llm.run_claude(prompt, payload, schema=llm.CLASSIFY_SCHEMA, model="haiku", label="classify")
        if res["mode"] not in allowed:  # 스키마는 모든 형식을 허용하므로 입력 종류에 맞게 보정한다
            res["mode"] = "summary"
        return res

    return load_or(work / "classify.json", [prompt, payload], args.force, run)


ANALYSIS_DOMAINS = {"politics", "economy"}


def domains_of(work: Path, args, meta: dict, md: str, choice: dict) -> list[str]:
    """주 분야 + 부 분야. --mode를 직접 지정해 판별을 건너뛴 경우에도 분야는 판별한다."""
    if "domain" not in choice:
        choice = choose_mode(work, argparse.Namespace(**{**vars(args), "mode": "auto"}), meta, md)
    return [choice["domain"], *[d for d in choice.get("secondary_domains", []) if d != choice["domain"]]]


def want_analysis(args, domains: list[str]) -> bool:
    if args.analysis != "auto":
        return args.analysis == "on"
    if args.verify:
        return True
    # 녹음본은 사적인 대화일 수 있어 분석·웹 검색을 기본으로 하지 않는다 (--analysis on으로 켬)
    return args.kind != "recording" and any(d in ANALYSIS_DOMAINS for d in domains)


MAX_CLAIMS = 8


def step_analysis(work: Path, args, meta: dict, md: str, doc: str, domains: list[str], mode: str) -> dict:
    guided = [d for d in domains if d in llm.DOMAIN_GUIDES]
    guide = "\n".join(llm.DOMAIN_GUIDES[d] for d in guided) or "- (일반 원칙만 적용)"
    outlook = llm.OUTLOOK_BY_DOMAIN.get(domains[0], llm.FORECAST_SECTION)
    prompt = llm.adapt(llm.ANALYSIS_PROMPT.format(outlook=outlook, domains=", ".join(domains), guide=guide,
                                                  max_claims=MAX_CLAIMS), args.kind)
    context = json.dumps({k: meta[k] for k in ("title", "channel", "upload_date", "description", "tags")},
                         ensure_ascii=False)
    stdin = f"{context}\n\n# 정리 문서\n{doc}\n\n# 전사문\n{md}"

    def run():
        return llm.run_claude(prompt, stdin, schema=llm.ANALYSIS_SCHEMA, label="analysis")

    return load_or(work / f"analysis_{mode}.json", [prompt, stdin], args.force, run, required=("markdown", "claims"))


_URL_RE = re.compile(r"https?://\S+|www\.\S+", re.I)


def step_verify(work: Path, args, meta: dict, claims: list[dict], mode: str) -> str:
    """주장 목록만 넘겨 웹 검색으로 확인한다 (설명란·전사 원문은 넘기지 않아 인젝션 경로를 줄인다)."""
    # 번호를 1..N으로 다시 매기고, 주장 안의 URL은 지운다 (인젝션으로 '근거 URL'을 미리 심는 경로 차단)
    claims = [{"id": i, "claim": _URL_RE.sub("[URL 삭제]", c["claim"])[:300], "as_of": (c.get("as_of") or "")[:40]}
              for i, c in enumerate(claims[:MAX_CLAIMS], 1)]
    if not claims:
        return ""
    trusted = verify.load_trusted()
    upload = meta.get("upload_date") or "알 수 없음"
    payload = json.dumps({"claims": claims}, ensure_ascii=False)

    def run():
        today = datetime.date.today().isoformat()
        print(f"[verify] 주장 {len(claims)}개를 웹 검색으로 확인 (예산 ${args.verify_budget})")
        res = llm.run_claude(llm.adapt(llm.VERIFY_PROMPT.format(today=today, upload_date=upload), args.kind), payload,
                             schema=llm.VERIFY_SCHEMA, web_domains=trusted, max_budget_usd=args.verify_budget,
                             max_turns=60, label="verify")
        return {**res, "checked_at": today}

    # 날짜는 지문에서 뺀다: 같은 주장을 날마다 다시 검색하지 않는다 (다시 확인하려면 --force)
    try:
        res = load_or(work / f"verify_{mode}.json", [llm.VERIFY_PROMPT, upload, payload, trusted], args.force, run,
                      required=("results", "checked_at"))
    except RuntimeError as e:
        print(f"[warn] 사실 확인 실패: {e}")
        return f"> 사실 확인에 실패했다 (예산·턴 초과 등). `--verify-budget`을 올려 다시 실행할 수 있다. 원인: {str(e)[:200]}"
    checked = verify.validate(res["results"], claims, trusted)
    downgraded = sum(1 for c in checked if c["note"])
    counts = {v: sum(1 for c in checked if c["verdict"] == v) for v in verify.LABELS}
    print("[verify] " + ", ".join(f"{verify.LABELS[k]} {n}" for k, n in counts.items() if n)
          + (f" (신뢰 출처 없어 보류 {downgraded})" if downgraded else ""))
    return verify.render(checked, res["checked_at"])


DOC_DIRECT_CHARS = 50000   # 전사문이 이보다 길면(한국어 약 2시간 반) 구간 노트로 압축한 뒤 문서를 만든다
DOC_PART_CHARS = 30000


def condense(work: Path, args, meta: dict, md: str) -> tuple[str, bool]:
    """긴 전사문은 구간별 '구간 노트'로 압축해(map) 문서 단계(reduce)에 넘긴다."""
    if len(md) <= DOC_DIRECT_CHARS:
        return md, False
    parts, cur = [], []
    for line in md.splitlines():
        if cur and sum(len(x) + 1 for x in cur) + len(line) > DOC_PART_CHARS:
            parts.append("\n".join(cur))
            cur = []
        cur.append(line)
    if cur:
        parts.append("\n".join(cur))
    print(f"[document] 전사문이 길어 {len(parts)}개 구간 노트로 압축한 뒤 문서를 만든다 ({len(md):,}자)")
    media = "녹음" if args.kind == "recording" else "영상"
    notes = []
    for i, part in enumerate(parts, 1):
        prompt = llm.CHUNK_NOTES_PROMPT.format(media=media, part=i, total=len(parts))
        stdin = f"{json.dumps({'title': meta.get('title'), 'context': meta.get('context')}, ensure_ascii=False)}\n\n{part}"

        def run(prompt=prompt, stdin=stdin, i=i):
            return {"markdown": llm.run_claude(prompt, stdin, label=f"notes {i}/{len(parts)}")}

        notes.append(load_or(work / f"chunk_notes_p{i}.json", [prompt, stdin], args.force, run,
                             required=("markdown",))["markdown"])
    return "\n\n".join(f"## 구간 {i}\n{n}" for i, n in enumerate(notes, 1)), True


def step_document(work: Path, args, meta: dict, md: str, notes: list[dict]) -> None:
    if not shutil.which("claude"):
        sys.exit("[document] claude CLI를 찾을 수 없습니다.")
    choice = choose_mode(work, args, meta, md)
    mode = choice["mode"]
    label, fmt = llm.DOC_FORMATS[mode]
    print(f"[document] 형식: {mode}({label}) — {choice.get('genre', '')} {choice.get('reason', '')}".rstrip())

    image_dir = f"{mode}_images"
    cands: list[dict] = []
    if not args.no_images and use_video(work, args):
        ocr_path = work / "ocr.json"
        ocr_frames = json.loads(ocr_path.read_text(encoding="utf-8"))["frames"] if ocr_path.exists() else []
        frames_dir = work / f"frames_{args.frame_interval:g}"
        cands = report.build_candidates(work, notes, ocr_frames, frames_dir if frames_dir.exists() else None, image_dir)
    images = (llm.SUMMARY_IMAGES.format(max_images=args.max_images, candidates=report.candidates_prompt(cands))
              if cands else "")
    body, chunked = condense(work, args, meta, md)
    prompt = llm.adapt(llm.DOC_COMMON.format(label=label) + fmt, args.kind) + "\n" + images
    if args.kind == "recording":
        prompt += llm.RECORDING_DOC_RULES
    if chunked:
        prompt += llm.CHUNKED_INPUT_NOTE
    keys = ("title", "channel", "upload_date", "tags", "context", "speakers")
    context = json.dumps({k: meta.get(k) for k in keys if meta.get(k)}, ensure_ascii=False)
    stdin = f"{context}\n\n{body}"

    def run():
        return {"markdown": llm.run_claude(prompt, stdin, label=mode)}

    doc = load_or(work / f"{mode}.json", [prompt, stdin], args.force, run, required=("markdown",))["markdown"]
    domains = domains_of(work, args, meta, md, choice)
    if want_analysis(args, domains):
        print(f"[document] 분석 섹션 추가 (분야: {', '.join(domains)})")
        analysis = step_analysis(work, args, meta, body, doc, domains, mode)
        section = analysis["markdown"].strip()
        if args.verify:
            section += "\n\n" + step_verify(work, args, meta, analysis["claims"], mode).strip()
        doc = doc.rstrip() + "\n\n---\n\n" + section + "\n"
    elif args.verify:
        print("[warn] --analysis off라서 --verify를 건너뜁니다 (확인할 주장은 분석 단계에서 나온다)")
    # 분석·사실 확인 섹션까지 붙인 '최종 문서 전체'에서 후보 밖 이미지 태그를 지운다
    doc, used = report.finalize(work, doc, cands, image_dir)
    write_atomic(work / f"{mode}.md", doc)
    write_atomic(work / f"{mode}.html", report.render_html(work, doc, meta))
    print(f"[document] 이미지 {len(used)}장 (후보 {len(cands)}장)")
    pdf = ""
    if args.pdf:
        try:
            report.render_pdf(work / f"{mode}.html", work / f"{mode}.pdf")
            pdf = f" pdf={work / f'{mode}.pdf'}"
        except (RuntimeError, OSError) as e:  # PDF 실패로 문서 결과까지 잃지 않는다
            print(f"[warn] {e}")
    # 스킬 등 외부에서 결과 위치를 파싱할 수 있도록 마지막에 한 줄로 남긴다
    print(f"[result] mode={mode} md={work / f'{mode}.md'} html={work / f'{mode}.html'}{pdf}")


def main() -> None:
    # 로그를 파일로 리다이렉트해도 단계 진행이 바로 보이도록 줄 단위로 내보낸다
    sys.stdout.reconfigure(line_buffering=True)  # type: ignore[union-attr]
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("source", help="유튜브 URL 또는 로컬 음원/영상 파일 경로")
    p.add_argument("--source-kind", choices=["auto", "video", "recording"], default="auto",
                   help="입력 종류. auto: URL·영상 파일은 video, 오디오만 있는 파일은 recording")
    p.add_argument("--title", help="로컬 파일의 제목 (기본: 파일명)")
    p.add_argument("--context", help="무슨 녹음/영상인지 한두 문장 (예: '3분기 예산 회의, 영업팀')")
    p.add_argument("--terms", help="고유명사·용어 (쉼표 구분). 교정 단계의 표기 근거로 쓴다")
    p.add_argument("--speakers", help="참석자·화자 (쉼표 구분). 화자는 문맥으로 추정만 한다")
    p.add_argument("--mask", choices=["auto", "on", "off"], default="auto",
                   help="Claude로 보내기 전 전화번호·주민번호·계좌·카드·이메일 가리기. auto: 녹음이면 켬")
    p.add_argument("--out-dir", default="output")
    # ASR
    p.add_argument("--model", default="large-v3")
    p.add_argument("--device", default="auto", choices=["auto", "cuda", "cpu", "mlx"],
                   help="auto: Apple Silicon이면 mlx, 그 외 cuda (OOM이면 CPU)")
    p.add_argument("--compute-type", default="int8_float16", help="CUDA 전용. RTX 2060은 bfloat16 미지원")
    p.add_argument("--language", default="ko", help="'auto'면 자동 감지")
    p.add_argument("--beam-size", type=int, default=5)
    p.add_argument("--chunk-length", type=int, default=15,
                   help="VAD 조각 최대 길이(초). 30이면 인터뷰 누락, 10이면 문장이 잘림")
    p.add_argument("--batch-size", type=int, default=4, help="VRAM이 부족하면 낮추기")
    p.add_argument("--prompt", help="initial_prompt (기본 없음: 제목을 넣으면 크레딧 환각이 생겼다)")
    p.add_argument("--hotwords", help="Whisper 힌트 단어 (공백 구분). 흔한 단어를 넣으면 반복 환각이 생기므로 드문 고유명사만")
    # 교정/화면
    p.add_argument("--asr-only", action="store_true",
                   help="OCR·교정·화면 분석 없이 전사만 (--summarize를 함께 주면 요약만 Claude 호출)")
    p.add_argument("--no-video", action="store_true", help="영상 다운로드·OCR·프레임 분석 생략")
    p.add_argument("--no-visual", action="store_true", help="Claude 프레임 분석(P3) 생략")
    p.add_argument("--max-visual", type=int, default=12, help="Claude가 볼 프레임 최대 수 (20 이하 권장)")
    p.add_argument("--ocr", action="store_true",
                   help="화면 텍스트 OCR로 고유명사 교정 근거 추가 (CPU, 영상 길이의 1~1.5배 소요)")
    p.add_argument("--frame-interval", type=float, default=3.0, help="OCR용 프레임 추출 간격(초)")
    p.add_argument("--summarize", action="store_true",
                   help="교정본으로 결과 문서 생성 (<mode>.md + 이미지 포함 <mode>.html)")
    p.add_argument("--mode", choices=["auto", *llm.DOC_MODES], default="auto",
                   help="문서 형식: summary(요약) / outline(정리) / notes(학습 노트) / meeting(회의록) / "
                        "interview(인터뷰) / memo(메모) / auto(입력 성격으로 판별)")
    p.add_argument("--analysis", choices=["auto", "on", "off"], default="auto",
                   help="Claude의 분석 섹션(쟁점·비판적 검토·전망, 분야별 점검 항목). auto: 주/부 분야가 정치·경제일 때")
    p.add_argument("--verify", action="store_true",
                   help="분석의 '확인 필요' 주장을 웹 검색으로 사실 확인 (신뢰 도메인 출처만 인정, 분석 섹션 포함)")
    p.add_argument("--verify-budget", type=float, default=1.0, help="사실 확인 단계 비용 상한 (USD)")
    p.add_argument("--pdf", action="store_true", help="결과 문서를 PDF로도 저장 (<mode>.pdf, Chrome headless 사용)")
    p.add_argument("--no-images", action="store_true", help="요약에 영상 프레임 이미지를 넣지 않음")
    p.add_argument("--max-images", type=int, default=8, help="요약에 넣을 이미지 최대 수")
    p.add_argument("--force", action="store_true", help="캐시 무시하고 모든 단계 재실행")
    p.add_argument("--force-asr", action="store_true",
                   help="전사만 강제로 다시 (이후 단계는 입력이 바뀌면 자동으로 다시 계산)")
    args = p.parse_args()

    root = Path(args.out_dir)
    root.mkdir(parents=True, exist_ok=True)
    langs = [args.language, f"{args.language}-orig"] if args.language != "auto" else ["ko", "ko-orig", "en"]
    if args.source.startswith(("http://", "https://")):
        args.kind = "video" if args.source_kind == "auto" else args.source_kind
        work = fetch.fetch_url(args.source, root, want_video=not (args.no_video or args.asr_only), sub_langs=langs)
    else:
        src = Path(args.source)
        if not src.exists():
            sys.exit(f"파일이 없습니다: {src}")
        args.kind = args.source_kind if args.source_kind != "auto" else \
            ("video" if frames.has_video_stream(src) else "recording")
        work = fetch.prepare_local(src, root, link_video=args.kind == "video", title=args.title)
    if args.kind == "recording":
        args.no_video = True  # 녹음은 화면이 없다 (영상 파일을 녹음으로 지정한 경우 포함)
    print(f"[input] 종류: {'녹음' if args.kind == 'recording' else '영상'}")
    info = json.loads((work / "info.json").read_text(encoding="utf-8"))
    meta = correct.meta_from_info(info)
    meta["context"] = args.context
    meta["speakers"] = [x.strip() for x in args.speakers.split(",") if x.strip()] if args.speakers else []
    meta["user_terms"] = [x.strip() for x in args.terms.split(",") if x.strip()] if args.terms else []

    spans = [] if args.asr_only else step_ocr(work, args)
    terms = meta["user_terms"] + [t for t in step_glossary(work, args, info, spans) if t not in meta["user_terms"]]
    asr = step_asr(work, args, asr_options(args))
    segments, duration = asr["segments"], asr["meta"]["duration"]
    if args.mask == "on" or (args.mask == "auto" and args.kind == "recording"):
        # 원본은 asr.json에만 남고, 이후 단계(Claude 전송·결과물)는 가린 텍스트만 쓴다
        segments, masked = privacy.mask_segments(segments)
        if masked:
            print("[privacy] 가림: " + ", ".join(f"{k} {v}건" for k, v in masked.items()))

    final, notes, log = segments, [], []
    if not segments:
        print("[warn] 전사된 세그먼트가 없습니다 (무음이거나 VAD가 음성을 찾지 못함). 교정 단계를 건너뜁니다.")
    elif not args.asr_only:
        cues, sub_kind = load_subs(work, langs)
        res = step_correct(work, args, meta, segments, cues, sub_kind, spans, terms)
        final, log1 = correct.apply_corrections(segments, res["corrections"], "correct")
        final, log2 = correct.apply_structure(final, res["insertions"], res["deletions"], duration)
        vis = step_visual(work, args, final, res["visual_checks"], duration)
        final, log3 = correct.apply_corrections(final, vis["corrections"], "visual")
        notes, log = vis["notes"], log1 + log2 + log3
        applied = sum(1 for e in log if e["status"] == "applied")
        print(f"[correct] 변경 {applied}건 적용 / {len(log)}건 제안, 화면 설명 {len(notes)}건")

    write_atomic(work / "transcript.json", json.dumps({"segments": final, "notes": notes}, ensure_ascii=False, indent=1))
    write_atomic(work / "corrections.json", json.dumps(log, ensure_ascii=False, indent=1))
    write_atomic(work / "transcript.txt", correct.render_txt(final))
    write_atomic(work / "transcript.srt", correct.render_srt(final))
    md = correct.render_md(meta, final, notes)
    write_atomic(work / "transcript.md", md)
    print(f"[done] {work}/transcript.md (.txt .srt), 변경 내역: corrections.json")

    if args.summarize:
        step_document(work, args, meta, md, notes)


if __name__ == "__main__":
    main()
