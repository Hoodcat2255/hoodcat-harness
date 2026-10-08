---
name: recording-notes
description: |
  Turns a local audio recording (meeting, interview, lecture recording, phone call, voice memo;
  .m4a .mp3 .wav .ogg .flac .webm, or a video file the user calls a recording) into Korean meeting
  minutes, interview notes, study notes, or a memo. Runs the local pipeline in ~/Projects/whisper
  (faster-whisper large-v3 → Claude correction using the user's context, terms and attendee list →
  document). Masks phone numbers, resident registration numbers, account/card numbers and emails
  before anything is sent to Claude; analysis and web fact-checking are off by default.
  Use when the user gives a local audio/recording file path and asks to transcribe, summarize,
  take minutes, or organize it. For YouTube links or online videos use youtube-digest instead.
  Triggers on: "녹음 정리", "회의록", "회의 녹음", "녹취록", "통화 녹음", "인터뷰 녹음",
  "음성메모", "강의 녹음", "받아 적어줘", "rec:", or a path to an audio file with a request.
argument-hint: "<녹음 파일 경로> [회의록|인터뷰|노트|메모|전사만] [참석자: ...] [용어: ...]"
user-invocable: true
---

# Recording Notes

Pipeline home: `~/Projects/whisper` (`transcribe.py`, README.md). Same engine as
`youtube-digest`; this skill only covers local recordings. Talk to the user in Korean.
The pipeline is installed from `hoodcat-harness/whisper/` and overwritten on the next install, so
code fixes made in `~/Projects/whisper` must be applied there too.

## 1. Gather context first (it is the main accuracy lever)

Recordings have no description or captions, so corrections rely on what the user tells you.
Before running, if the user has not said them and the recording is not a quick memo, ask once
(AskUserQuestion, or one short prose question) for:

- what the recording is (`--context`, e.g. "3분기 예산 회의, 영업팀")
- attendees/speakers (`--speakers "홍길동,김철수"`) — used only to *guess* speakers, marked "(추정)"
- names and jargon likely to be misheard (`--terms "OKR,하이브리드 근무,김민수"`)
- optional title (`--title`)

If the user wants to skip, run without them.

## 2. Map the request to flags

| User says | Flag |
|---|---|
| 회의록, 회의 정리, 결정사항, 할 일 | `--mode meeting` |
| 인터뷰, 상담, 면접, 취재 | `--mode interview` |
| 강의, 수업, 세미나 | `--mode notes` |
| 음성메모, 메모, 아이디어 | `--mode memo` |
| nothing specific | `--mode auto` (classifies among meeting/interview/notes/memo/summary) |
| 전사만, 받아 적기만, 텍스트만 | `--asr-only`, no `--summarize` (no Claude calls; nothing leaves the machine) |
| 분석해줘, 비판, 전망 | `--analysis on` (off by default for recordings) |
| 개인정보 가리지 마 | `--mask off` (confirm once: the unmasked transcript is sent to Claude) |
| a video file that is really a recording | `--source-kind recording` |
| PDF로, PDF 파일 | `--pdf` (A4 PDF via headless Chrome; reuses caches when rerun) |

## 3. Run in the background

```bash
cd ~/Projects/whisper && uv run transcribe.py "<file>" --summarize --mode <mode> \
  [--context "..."] [--speakers "..."] [--terms "..."] [--title "..."] \
  > <scratchpad>/recnotes.log 2>&1; echo "exit=$?" >> <scratchpad>/recnotes.log
```

- `run_in_background: true`; transcription is ≈ 0.1× the length on GPU, ≈ 2× on CPU (when ComfyUI
  holds the GPU), ≈ 0.3× on the Apple Silicon Mac (mlx-whisper). Long recordings (> ~1 hour) are corrected in 15-minute parts, and over ~2.5 hours
  the document is built from per-part notes; tell the user it takes longer.
- Monitor the log with
  `grep --line-buffered -E "^\[(input|privacy|asr\] [0-9]|warn\] (GPU|[^/]*실패)|correct|classify|document|result)|exit=|Traceback|Error"`.
- Output goes to `output/<file-stem>-<hash>/`. The same file with another `--mode` reuses the
  transcript and only regenerates the document.

## 4. Report

1. Read `<mode>.md` from the `[result]` line and present it (decisions and action items first for
   meetings). Point to `<mode>.html` (`! xdg-open <html>`) and `transcript.md` / `.srt`.
2. Say which mode was used and why, and how many items were masked (`[privacy]` line).
3. Remind briefly: speaker names are guesses (no diarization), unstated owners/deadlines are "미정",
   and numbers spoken as Korean words ("공일공…") are not masked.
4. Corrections: count by evidence from `corrections.json`; `user` = based on the terms/attendees given.

## Privacy and legality

- Masking happens before Claude calls; the raw transcript stays only in local `asr.json`.
  Claude calls still send the masked transcript to Anthropic.
- Do not judge whether a recording was lawfully made. If the user indicates a third party secretly
  recorded others' private conversation, mention once that this may be restricted by law
  (통신비밀보호법) and continue only with the user's own responsibility; never help conceal it.
- Do not publish results as an Artifact unless the user asks; recordings are usually private.

## Known limits

- No speaker diarization (decided against: pyannote needs more VRAM than this GPU reliably has).
- Proper nouns not given via `--terms` may stay misheard.
