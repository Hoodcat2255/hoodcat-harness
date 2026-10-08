from pathlib import Path

from ytscribe.asr import fmt_ts, uncovered_intervals
from ytscribe.correct import apply_corrections, apply_structure, ocr_near, render_md
from ytscribe.frames import to_spans
from ytscribe.subs import overlap_text, parse_vtt, uncovered_spans

SP = " "  # 유튜브 자동자막의 공백 한 칸 줄
AUTO_VTT = "\n".join([
    "WEBVTT", "Kind: captions", "Language: ko", "",
    "00:00:00.760 --> 00:00:02.510 align:start position:0%", SP,
    "유회<00:00:01.040><c> 물질을</c><00:00:01.439><c> 사용하는</c>", "",
    "00:00:02.510 --> 00:00:02.520 align:start position:0%", "유회 물질을 사용하는", SP, "",
    "00:00:02.520 --> 00:00:05.070 align:start position:0%", "유회 물질을 사용하는",
    "주기적으로<00:00:03.080><c> 노동자의</c>", "",
    "00:00:05.070 --> 00:00:05.080 align:start position:0%", "주기적으로 노동자의", SP, "",
])

MANUAL_VTT = """WEBVTT

NOTE 이 블록은 무시되어야 한다

1
00:00:01.000 --> 00:00:03.000
첫 줄
둘째 줄

2
00:10.000 --> 00:14.000
인터뷰 발화 &amp; 효과음
"""


def test_parse_auto_vtt_rolling(tmp_path: Path):
    p = tmp_path / "a.vtt"
    p.write_text(AUTO_VTT, encoding="utf-8")
    cues = parse_vtt(p)
    assert [c["text"] for c in cues] == ["유회 물질을 사용하는", "주기적으로 노동자의"]
    assert cues[0]["start"] == 0.76 and cues[1]["end"] == 5.07


def test_parse_manual_vtt_joins_lines(tmp_path: Path):
    p = tmp_path / "m.vtt"
    p.write_text(MANUAL_VTT, encoding="utf-8")
    cues = parse_vtt(p)
    # 큐 식별자("2")와 NOTE 블록이 본문에 섞이지 않고, 시 생략 타임스탬프(MM:SS.mmm)도 읽는다
    assert [c["text"] for c in cues] == ["첫 줄 둘째 줄", "인터뷰 발화 & 효과음"]
    assert cues[1]["start"] == 10.0
    assert overlap_text(cues, 9, 11) == "인터뷰 발화 & 효과음"


def test_uncovered_spans_detects_missing_interview():
    cues = [{"start": 1, "end": 3, "text": "a"}, {"start": 10, "end": 14, "text": "인터뷰"}]
    segs = [{"id": 0, "start": 0.5, "end": 3.5, "text": "a"}]
    assert uncovered_spans(cues, segs) == [{"start": 10, "end": 14, "text": "인터뷰"}]


def test_apply_corrections_only_exact_substring():
    segs = [{"id": 0, "start": 0, "end": 1, "text": "송낙규 기자의 단독 보도입니다."}]
    corr = [
        {"id": 0, "before": "송낙규", "after": "송락규", "evidence": "description", "evidence_detail": ""},
        {"id": 0, "before": "없는말", "after": "x", "evidence": "context", "evidence_detail": ""},
        {"id": 9, "before": "a", "after": "b", "evidence": "context", "evidence_detail": ""},
    ]
    out, log = apply_corrections(segs, corr, "correct")
    assert out[0]["text"] == "송락규 기자의 단독 보도입니다."
    assert segs[0]["text"].startswith("송낙규")  # 원본 불변
    assert [e["status"] for e in log] == ["applied", "skipped: before not found", "skipped: unknown id"]


def test_apply_structure_insert_and_delete_sorted():
    segs = [{"id": 0, "start": 0, "end": 5, "text": "a"}, {"id": 1, "start": 20, "end": 22, "text": "다음 영상에서 만나요"}]
    ins = [{"start": 10, "end": 14, "text": "복원", "evidence": "description", "evidence_detail": ""}]
    out, _ = apply_structure(segs, ins, [{"id": 1, "reason": "환각"}])
    assert [s["text"] for s in out] == ["a", "복원", "다음 영상에서 만나요"]
    assert out[2]["deleted"] == "환각" and out[1]["inserted"] == "description"
    md = render_md({"title": "t"}, out, [{"id": 0, "time": 2, "description": "표"}])
    assert "다음 영상에서 만나요" not in md and "(복원) 복원" in md and "[화면 00:00:02] 표" in md
    # 삭제된 세그먼트(id=1)를 가리키는 화면 설명도 시각 기준으로 살아 있는 세그먼트 아래에 남는다
    md = render_md({"title": "t"}, out, [{"id": 1, "time": 21, "description": "엔딩 화면"}])
    assert md.rstrip().endswith("[화면 00:00:21] 엔딩 화면")


def test_to_spans_drops_static_overlay_and_merges():
    ocr = [{"t": t, "texts": ["KBS"] + (["DN오토모티브 울산 공장"] if 3 <= t <= 6 else [])} for t in range(0, 30, 3)]
    spans = to_spans(ocr, 3.0)
    assert [s["text"] for s in spans] == ["DN오토모티브 울산 공장"]
    assert spans[0]["start"] == 1.5 and spans[0]["end"] == 7.5
    assert ocr_near(spans, 10, 12) == ["DN오토모티브 울산 공장"]  # 5초 앞 창 안
    assert ocr_near(spans, 13, 14) == []


def test_fmt_ts_rounding():
    assert fmt_ts(59.9996) == "00:01:00,000"
    assert fmt_ts(3661.5, ".") == "01:01:01.500"


def test_apply_corrections_no_chain_and_ambiguous():
    segs = [{"id": 0, "start": 0, "end": 1, "text": "A 그리고 B"}, {"id": 1, "start": 1, "end": 2, "text": "납 납"}]
    corr = [
        {"id": 0, "before": "A", "after": "AB", "evidence": "context", "evidence_detail": ""},
        {"id": 0, "before": "B", "after": "C", "evidence": "context", "evidence_detail": ""},
        {"id": 1, "before": "납", "after": "남", "evidence": "context", "evidence_detail": ""},
    ]
    out, log = apply_corrections(segs, corr, "correct")
    # 두 번째 교정은 원문의 B만 바꾸고, 첫 교정이 넣은 B는 건드리지 않는다
    assert out[0]["text"] == "AB 그리고 C"
    assert out[1]["text"] == "납 납" and log[2]["status"].startswith("skipped: ambiguous")


def test_apply_structure_rejects_bad_insertions():
    segs = [{"id": 0, "start": 0, "end": 10, "text": "a"}, {"id": 1, "start": 10, "end": 12, "text": "환각"}]
    ins = [
        {"start": 2, "end": 8, "text": "중복", "evidence": "description", "evidence_detail": ""},
        {"start": 9, "end": 5, "text": "역전", "evidence": "description", "evidence_detail": ""},
        {"start": 10, "end": 12, "text": "", "evidence": "description", "evidence_detail": ""},
        {"start": 10, "end": 12, "text": "복원", "evidence": "description", "evidence_detail": ""},
    ]
    out, log = apply_structure(segs, ins, [{"id": 1, "reason": "환각"}], duration=12)
    assert [e["status"] for e in log[1:]] == [
        "skipped: overlaps existing speech", "skipped: invalid time range", "skipped: empty text", "applied",
    ]
    assert [s["text"] for s in out if not s.get("deleted")] == ["a", "복원"]


def test_to_spans_extends_over_deduped_frames():
    # 이름 자막이 1.5~28.5초 프레임 동안 떠 있었지만 dedupe로 1.5초 프레임만 남은 경우
    ocr = [{"t": 1.5, "texts": ["김부욱 교수"]}, {"t": 31.5, "texts": []}]
    spans = to_spans(ocr, 3.0)
    assert spans == [{"start": 0.0, "end": 30.0, "text": "김부욱 교수"}]


def test_uncovered_intervals_finds_dropped_interview():
    # 0~16초가 말소리인데 단어는 0~5초와 15.5~16초에만 인식된 경우 → 5.3~15.2초가 누락 의심
    speech = [(0.0, 16.0), (20.0, 21.0)]
    words = [(0.0, 2.0), (2.1, 5.0), (15.5, 16.0)]
    assert uncovered_intervals(speech, words, min_len=1.5) == [(5.3, 15.2)]
    # 짧은 미인식(1초)과 단어가 덮은 구간은 무시
    assert uncovered_intervals([(0, 3)], [(0, 1), (2.0, 3.0)], min_len=1.5) == []


def test_is_degenerate():
    from ytscribe.asr import is_degenerate
    assert is_degenerate("정전기 전병칠 정전기 전병칠")
    assert is_degenerate("380V 380V 380V 380V 380V")
    assert not is_degenerate("전압은 물의 수압과 같은 개념이 됩니다")
    assert not is_degenerate("네 네")  # 짧은 맞장구는 판단하지 않음


def test_report_finalize_and_html(tmp_path: Path):
    from ytscribe import report
    (tmp_path / "visual").mkdir()
    (tmp_path / "visual" / "t00070.0.jpg").write_bytes(b"\xff\xd8fakejpeg")
    cands = report.build_candidates(tmp_path, [{"id": 1, "time": 70, "description": "비교표"}], [], None)
    assert [c["path"] for c in cands] == ["summary_images/t00070.jpg"]
    md = "# 제목\n\n![비교표 (01:10)](summary_images/t00070.jpg)\n\n![가짜](../../etc/passwd)\n<script>alert(1)</script>\n"
    cleaned, used = report.finalize(tmp_path, md, cands)
    assert used == ["summary_images/t00070.jpg"] and "passwd" not in cleaned
    assert (tmp_path / "summary_images" / "t00070.jpg").exists()
    page = report.render_html(tmp_path, cleaned, {"title": "t"})
    assert "data:image/jpeg;base64," in page and "<figcaption>비교표 (01:10)</figcaption>" in page
    assert "<script>" not in page and "&lt;script&gt;" in page


def test_verify_downgrades_untrusted_sources():
    from ytscribe import verify
    trusted = ["go.kr", "bok.or.kr", "reuters.com"]
    claims = [{"id": 1, "claim": "기준금리는 2.5%다", "as_of": ""}, {"id": 2, "claim": "수출 비중 20%", "as_of": ""},
              {"id": 3, "claim": "x", "as_of": ""}]
    results = [
        {"id": 1, "verdict": "supported", "summary": "한은 발표와 일치", "sources": [{"url": "https://www.bok.or.kr/a", "title": "한은"}]},
        # 공격자 페이지만 근거 → 보류
        {"id": 2, "verdict": "supported", "summary": "맞음", "sources": [{"url": "https://evil-go.kr/x", "title": "가짜"}]},
        {"id": 99, "verdict": "supported", "summary": "목록에 없는 id", "sources": []},
        {"id": 3, "verdict": "contradicted", "summary": "js", "sources": [{"url": "javascript:alert(1)", "title": "x"}]},
    ]
    checked = verify.validate(results, claims, trusted)
    assert [(c["id"], c["verdict"]) for c in checked] == [(1, "supported"), (2, "unverified"), (3, "unverified")]
    assert checked[1]["note"]
    table = verify.render(checked, "2026-10-03")
    assert "javascript:" not in table and "(비신뢰)" in table and "✅ 사실" in table
    assert verify.is_trusted("https://news.kbs.co.kr/a", ["kbs.co.kr"]) and not verify.is_trusted("https://kbs.co.kr.evil.com", ["kbs.co.kr"])


def test_render_html_blocks_local_files_and_js_links(tmp_path: Path):
    from ytscribe import report
    secret = tmp_path.parent / "secret.jpg"
    secret.write_bytes(b"\xff\xd8SECRET")
    (tmp_path / "x_images").mkdir()
    (tmp_path / "x_images" / "ok.jpg").write_bytes(b"\xff\xd8ok")
    md = (f"![a]({secret})\n\n![b](../secret.jpg)\n\n![c](x_images/ok.jpg)\n\n"
          "[클릭](javascript:alert(1)) [정상](https://example.com)\n\n> 인용문\n")
    page = report.render_html(tmp_path, md, {"title": "t"})
    import base64
    assert base64.b64encode(b"\xff\xd8SECRET").decode() not in page
    assert base64.b64encode(b"\xff\xd8ok").decode() in page
    assert 'href="javascript' not in page and 'href="https://example.com"' in page
    assert "<blockquote>" in page


def test_verify_rejects_backslash_bypass_and_fills_missing():
    from ytscribe import verify
    t = ["bok.or.kr"]
    assert not verify.is_trusted("https://evil.com\\@bok.or.kr/", t)
    assert not verify.is_trusted("https://evil.com\\.bok.or.kr/x", t)
    claims = [{"id": 1, "claim": "a"}, {"id": 2, "claim": "b"}]
    res = [{"id": 1, "verdict": "supported", "summary": "s", "sources": [{"url": "https://www.bok.or.kr/a", "title": "[x](javascript:y)"}]},
           {"id": 1, "verdict": "contradicted", "summary": "dup", "sources": []}]
    checked = verify.validate(res, claims, t)
    assert [(c["id"], c["verdict"]) for c in checked] == [(1, "supported"), (2, "unverified")]
    assert "](javascript" not in verify.render(checked, "2026-10-03")


def test_privacy_mask():
    from ytscribe.privacy import mask
    text = ("제 번호는 010-1234-5678이고 주민번호 900101-1234567, 카드 1234 5678 9012 3456, "
            "계좌 110-123-456789, 메일 hong@example.co.kr 입니다. 회의는 2026-10-04 3시, 예산 1,200만원")
    out, counts = mask(text)
    for raw in ("010-1234-5678", "900101-1234567", "1234 5678 9012 3456", "110-123-456789", "hong@example.co.kr"):
        assert raw not in out
    assert counts == {"주민등록번호": 1, "카드번호": 1, "이메일": 1, "전화번호": 1, "계좌번호": 1}
    assert "2026-10-04" in out and "1,200만원" in out  # 날짜·금액은 가리지 않는다


def test_chunk_by_time_and_adapt():
    from transcribe import chunk_by_time
    from ytscribe.llm import adapt
    segs = [{"start": t, "end": t + 5, "text": "x"} for t in range(0, 2000, 100)]
    chunks = chunk_by_time(segs, 900)
    assert [len(c) for c in chunks] == [9, 9, 2] and chunks[1][0]["start"] == 900
    assert adapt("유튜브 영상의 제목과 영상 내용", "recording") == "녹음의 제목과 녹음 내용"
    assert adapt("영상 내용", "video") == "영상 내용"


def test_normalize_lists_renders_nested_lists(tmp_path: Path):
    from ytscribe import report
    md = "**버튼**\n  - HOLD: 고정\n  - Hz: 주파수\n\n① AC 전압\n1. 꽂는다\n2. 넣는다\n   - 하위\n"
    page = report.render_html(tmp_path, md, {"title": "t"})
    assert page.count("<li>") == 5 and "<ol>" in page and page.count("<ul>") == 2 and "<pre>" not in page


def test_group_windows_keeps_timeline_and_limits_length():
    from ytscribe.asr import group_windows
    speech = [(0.0, 4.0), (5.0, 12.0), (13.0, 20.0), (40.0, 41.0)]
    assert group_windows(speech, 15) == [(0.0, 12.0), (13.0, 20.0), (40.0, 41.0)]
    assert group_windows([], 15) == []


def test_drop_tail_hallucination_only_at_window_end():
    from ytscribe.asr import drop_tail_hallucination
    real = {"text": "합니다.", "end": 5.7, "words": [{"probability": 0.99}]}
    fake = {"text": "이 시각 세계였습니다.", "end": 6.28, "words": [{"probability": p} for p in (0.09, 0.57, 0.97)]}
    assert drop_tail_hallucination([real, fake], 6.3) == [real]
    # 창 끝에서 떨어진 저신뢰 발화는 남긴다
    assert drop_tail_hallucination([real, fake | {"end": 5.5}], 6.3) == [real, fake | {"end": 5.5}]
    assert drop_tail_hallucination([], 6.3) == []


def test_repeated_runs_drops_loops_but_keeps_backchannels():
    from ytscribe.asr import repeated_runs
    loop = ["이곳은 한창의 한가운데요."] * 3 + ["다른 말입니다"]
    assert repeated_runs(loop) == {0, 1, 2}
    assert repeated_runs(["네", "네.", "네", "네"]) == set()            # 짧은 맞장구
    assert repeated_runs(["감사합니다."] * 4) == set()                  # 5자
    assert repeated_runs(["이곳은 한창의 한가운데요."] * 2) == set()      # 2회는 루프로 보지 않는다


def test_is_unspeakable():
    from ytscribe.asr import is_unspeakable
    assert is_unspeakable("閉을閉을", "ko") and not is_unspeakable("閉을閉을", None)
    assert is_unspeakable("자막 Amara.org 커뮤니티", None) and is_unspeakable("깨진 � 문자", "ko")
    assert not is_unspeakable("구독과 좋아요 부탁드립니다", "ko")      # 유튜버의 실제 발화
    assert not is_unspeakable("中 하나는 괜찮다", "ko")


def test_collect_drops_hallucinations_and_flags_low_conf_numbers():
    from ytscribe.asr import _collect

    def seg(t, text, word_info=None):
        return {"start": t, "end": t + 2, "text": text, "words": [(t, t + 2)], "word_info": word_info or []}

    raw = [seg(0, "시작합니다 여러분")] + [seg(2 + 2 * i, "이곳은 한창의 한가운데요.") for i in range(3)] + [
        seg(8, "閉을閉을"), seg(10, "매출은 9억 건입니다", [("매출은", 0.9), ("9억", 0.3), ("건입니다", 0.9)]),
        seg(12, "3시에 봐요", [("3시에", 0.95), ("봐요", 0.9)]),
    ]
    result, covered = _collect(raw, "ko")
    assert [r["text"] for r in result] == ["시작합니다 여러분", "매출은 9억 건입니다", "3시에 봐요"]
    assert covered == [(0, 2), (10, 12), (12, 14)]   # 버린 자리는 누락 재전사 대상으로 남는다
    assert result[1].get("num_low_conf") and "num_low_conf" not in result[2]


def test_speech_coverage_and_warning(capsys):
    from ytscribe.asr import coverage_stats, report_coverage, speech_coverage
    assert speech_coverage([], []) == 1.0
    assert abs(speech_coverage([(0, 10)], [(0, 4)]) - 0.43) < 1e-6   # 단어 구간 앞뒤 0.3초 포함
    stats = coverage_stats([(0, 10)], [(0, 4)], [(4, 10)])
    assert stats["before"] < 0.9 and stats["after"] == 1.0
    report_coverage(stats)
    out = capsys.readouterr().out
    assert "재전사 후 100.0%" in out and "[warn]" not in out
    report_coverage(coverage_stats([(0, 10)], [(0, 4)], []))
    assert "[warn] 커버리지" in capsys.readouterr().out
    report_coverage(None)   # 예전 캐시(asr.json)에는 커버리지가 없다
    assert capsys.readouterr().out == ""


def test_recover_gaps_drops_repeated_recoveries(monkeypatch):
    import faster_whisper.vad as vad
    import numpy as np

    from ytscribe import asr
    gaps = [(1.0, 3.0), (4.0, 6.0), (7.0, 9.0), (10.0, 12.0)]
    texts = iter(["이곳은 한창의 한가운데요."] * 3 + ["마지막에 실제로 한 말입니다"])
    real = asr.uncovered_intervals
    monkeypatch.setattr(asr, "uncovered_intervals",
                        lambda speech, covered, min_len, pad=0.3: gaps if min_len > 0 else real(speech, covered, min_len, pad))
    monkeypatch.setattr(vad, "get_speech_timestamps", lambda wave, opts: [{"start": 0, "end": 13 * 16000}])
    rec, stats = asr._recover_gaps(np.zeros(13 * 16000, dtype=np.float32), [(0.0, 1.0)], lambda clip: [
        {"text": next(texts), "avg_logprob": -0.2, "compression_ratio": 1.2}], "ko")
    assert [r["text"] for r in rec] == ["마지막에 실제로 한 말입니다"]
    assert stats["after"] < 0.5   # 반복으로 버린 구간은 커버리지에 넣지 않는다


def test_apply_corrections_never_changes_numbers_from_context_alone():
    segs = [{"id": 0, "start": 0, "end": 1, "text": "부업군적으로 처리"}, {"id": 1, "start": 1, "end": 2, "text": "9억 건 매출"},
            {"id": 2, "start": 2, "end": 3, "text": "츄르 중장"}]
    corr = [
        {"id": 0, "before": "부업군적으로", "after": "2억 건으로", "evidence": "context", "evidence_detail": ""},
        {"id": 1, "before": "9억", "after": "2억", "evidence": "ocr", "evidence_detail": "2억 건"},
        {"id": 2, "before": "츄르", "after": "츠루", "evidence": "context", "evidence_detail": ""},
    ]
    out, log = apply_corrections(segs, corr, "correct")
    assert log[0]["status"] == "skipped: 숫자는 문맥 근거만으로 고치지 않음" and out[0]["text"] == "부업군적으로 처리"
    assert out[1]["text"] == "2억 건 매출" and out[2]["text"] == "츠루 중장"


def test_flag_numbers_video_and_recording():
    from ytscribe.correct import flag_numbers
    cues = [{"start": 0, "end": 5, "text": "매출이 2억 건이었고"}, {"start": 5, "end": 10, "text": "오십 퍼센트 증가"},
            {"start": 10, "end": 15, "text": "1,000원 올랐다"}]
    segs = [{"id": 0, "start": 0, "end": 5, "text": "매출이 9억 건이었고"},
            {"id": 1, "start": 6, "end": 9, "text": "50퍼센트 증가"},          # 자막이 숫자를 한글로 썼으면 비교 안 함
            {"id": 2, "start": 10, "end": 15, "text": "1000원 올랐다"},        # 쉼표 차이는 같은 값
            {"id": 3, "start": 0, "end": 5, "text": "삭제됨 7", "deleted": "환각"}]
    assert flag_numbers(segs, cues, "video") == 1 and segs[0].get("num_check") and not segs[2].get("num_check")
    rec = [{"id": 0, "start": 0, "end": 1, "text": "3억", "num_low_conf": True},
           {"id": 1, "start": 1, "end": 2, "text": "[전화번호]", "num_low_conf": True}]   # 마스킹으로 숫자가 사라짐
    assert flag_numbers(rec, [], "recording") == 1 and rec[0]["num_check"] and "num_check" not in rec[1]
    md = render_md({"title": "t"}, rec, [])
    assert "[00:00:00] 3억 (수치 확인 필요)" in md


def test_prompts_carry_number_and_name_rules():
    from ytscribe import llm
    assert "숫자(금액·건수·비율·날짜·시각·순번)는 context만으로 고치지 마라" in llm.CORRECT_PROMPT
    assert "(수치 확인 필요)" in llm.DOC_COMMON
    assert "명단에 없는 호칭" in llm.RECORDING_DOC_RULES and "발언 미수록" in llm.RECORDING_DOC_RULES
