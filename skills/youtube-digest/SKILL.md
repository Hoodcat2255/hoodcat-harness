---
name: youtube-digest
description: |
  Turns a YouTube video (or a downloaded/local video file) into a Korean document that fits the
  video's nature: a summary (news, interviews, talk shows, vlogs), an outline (talks, explainers,
  reviews, how-tos), or study notes (lectures, tutorials, courses). Runs the local pipeline in
  ~/Projects/whisper: yt-dlp download → (optional frame OCR) → faster-whisper large-v3 transcription →
  Claude correction grounded in the description, YouTube captions (and on-screen text with --ocr) → frame
  analysis → document with the relevant video frames embedded (Markdown + single-file HTML).
  For politics and economy videos it appends a clearly labeled analysis section by Claude
  (issues and stakeholders, critique with domain-specific checklists, future outlook scenarios or
  evidence assessment for science/health, points to fact-check). With --verify it fact-checks those
  claims by web search and accepts only sources on a trusted-domain allowlist.
  Use when the user gives a YouTube URL (youtube.com / youtu.be) or a video file and asks to
  summarize, organize, take notes, transcribe, or "정리" it. For local audio recordings (meetings,
  calls, interviews, voice memos) use recording-notes instead.
  Triggers on: "유튜브 요약", "영상 요약해줘", "영상 정리해줘", "강의 노트 만들어줘", "필기해줘",
  "이 영상 뭐래", "전사해줘", "자막 뽑아줘", "분석해줘", "전망", "비판", "yt:", or a bare YouTube link
  with a request.
argument-hint: "<YouTube URL | 파일 경로> [요약|정리|노트|전사만] [분석|분석 없이] [빠르게]"
user-invocable: true
---

# YouTube Digest

Pipeline home: `~/Projects/whisper` (`transcribe.py`, package `ytscribe/`, README.md).
Always run it with `uv run` from that directory. Talk to the user in Korean.

## 1. Parse the request

| User says | Flag |
|---|---|
| 요약, 핵심만, 뭐래 | `--mode summary` |
| 정리, 구조화, 개요 | `--mode outline` |
| 노트, 필기, 공부, 학습, 강의 정리 | `--mode notes` |
| nothing specific | `--mode auto` (the pipeline classifies the video with a cheap model) |
| 전사만, 자막만, 텍스트만 | `--asr-only` and no `--summarize` (no Claude calls) |
| 빠르게, 화면 분석 없이 | `--no-video` (skips 720p video, frame analysis, images) |
| 화면 자막까지, 고유명사 정확히, OCR | `--ocr` (off by default: reads on-screen text as correction evidence; adds ≈ 1–1.5× video length on CPU) |
| 이미지 없이 | `--no-images` |
| PDF로, PDF 파일 | `--pdf` (A4 PDF via headless Chrome; on an already processed video it reuses all caches, no Claude calls) |
| 분석, 전망, 비판, 평가, 의견 | `--analysis on` (any domain) |
| 팩트체크, 사실 확인, 검증, 맞는 말이야? | `--verify` (turns on the analysis section unless `--analysis off` is also given, in which case verify is skipped; web search, trusted sources only; `--verify-budget` caps cost, default 1 USD) |
| 분석 빼고, 요약만 | `--analysis off` |
| nothing about analysis | `--analysis auto` (default: added when the primary or a secondary domain is politics/economy) |
| 영어 영상 / other language | `--language en` (or `auto`) |

Accept `youtube.com/watch?v=`, `youtu.be/`, `/shorts/`, and `/live/` links. Reject playlist-only
URLs (the pipeline refuses them); ask for a single video. For a local video file, pass its absolute
path. If the user hands over an audio-only recording, switch to the `recording-notes` skill.

## 2. Run the pipeline in the background

It takes minutes (with `--ocr`, OCR adds ≈ 1–1.5× video length on CPU; transcription ≈ 0.1× on GPU or ≈ 2× on CPU
when ComfyUI holds the GPU; ≈ 0.3× on the Apple Silicon Mac via mlx-whisper). Run it in the background and log to the session scratchpad:

```bash
cd ~/Projects/whisper && uv run transcribe.py "<URL>" --summarize --mode <mode> [--analysis on|off] [--verify] \
  > <scratchpad>/ytdigest-<id>.log 2>&1; echo "exit=$?" >> <scratchpad>/ytdigest-<id>.log
```

- Use `run_in_background: true` with a generous timeout (≥ 2 h for videos over 30 min).
- Watch progress with Monitor on the log, filtering the stage lines so failures also surface:
  `grep --line-buffered -E "^\[(fetch|ocr\] 프레임|asr\] [0-9]|warn\] (GPU|[^/]*실패)|subs|correct|visual|document|analysis|verify|result)|exit=|Traceback|Error"`
- Tell the user up front: expected duration from the video length, and that it may fall back to
  CPU if ComfyUI is using the GPU. Give short updates at stage changes, not every line.
- Results are cached per stage in `output/<video-id>/`. Rerunning the same URL with another
  `--mode` regenerates the document, and also the analysis (and verify, if on) for that mode,
  since they are cached per mode (`analysis_<mode>.json`, `verify_<mode>.json`). Rerunning the
  same mode is free. Fact checks are not repeated on later days unless `--force` is given. Do not
  pass `--force` unless the user asks.

## 3. Report the result

The last log line is `[result] mode=<mode> md=<path> html=<path>`. Then:

1. Read `<mode>.md` and present it in chat (it is the deliverable). For long documents show the
   one-line summary and the section headings plus the most useful part, and point to the file.
2. Give the HTML path for viewing with images: suggest `! xdg-open <html>`.
3. State which mode was used and why (from the `[document] 형식:` line when auto), and whether
   the analysis section was added. When it was, remind the user in one line that it is Claude's
   opinion with a knowledge cutoff, not the video's content, and that "확인 필요" items need checking.
   With `--verify`, report the verdict counts from the `[verify]` log line and highlight any
   `❌ 사실과 다름` items; explain that `❔ 미확인` includes verdicts downgraded for lack of a
   trusted source (`trusted_domains.txt` can be extended).
4. Briefly report quality signals from `output/<id>/corrections.json`: number of applied
   corrections by evidence (`description`, `youtube_*`, `ocr`, `frame`, `context`), any
   `(복원)` / `(재전사)` lines in `transcript.md`, and anything skipped. Mention the Claude cost
   (sum of the `비용 $` lines).
5. Offer follow-ups in one line: another mode, transcript (`transcript.md` / `.srt`), or
   publishing the HTML as a private Artifact. Do not publish unless asked; video frames belong to
   the uploader.

## 4. Failure handling

| Symptom in log | Action |
|---|---|
| `HTTP Error 429` on subtitles | Harmless; the pipeline continues without captions. |
| `GPU 메모리 부족 → CPU` | Expected when ComfyUI is busy; just slower. Tell the user. |
| `PDF 변환 실패` on macOS | Desktop Chrome cannot start without a GUI login. Install `chrome-headless-shell` (command in README) and rerun with `--pdf` (cached stages are skipped). |
| yt-dlp extraction error | YouTube changes often break old yt-dlp. Upgrade inside the project (`uv lock --upgrade-package yt-dlp && uv sync`), then rerun. |
| `claude CLI를 찾을 수 없습니다` | `claude` must be on PATH; ask the user. |
| `전사된 세그먼트가 없습니다` | Silent/music-only audio; report it, no document is produced. |
| Traceback | Show the last lines, diagnose in `~/Projects/whisper`, fix, rerun (caches keep finished stages). That copy is overwritten by the next hoodcat-harness install, so apply the same fix to `hoodcat-harness/whisper/` too. |

## Known limits (tell the user when relevant)

- Without description script or captions, proper nouns can stay misheard (only context is left as
  evidence, plus on-screen text with `--ocr`; suggest `--ocr` when names on screen matter).
- Short interview fragments under background music can still be missed; they are filled only
  when the description or captions contain them, marked `(복원)`.
- Never add Whisper hints automatically: auto `hotwords`/`initial_prompt` caused repetition and
  credit hallucinations (see README). `--hotwords` only for rare proper nouns the user supplies.
