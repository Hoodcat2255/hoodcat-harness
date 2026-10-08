# 유튜브 스킬과 녹음본 스킬 분리 여부 조사 결과

> 조사일: 2026-10-03
> 대상: `~/Projects/whisper` 파이프라인, `~/.claude/skills/youtube-digest/SKILL.md`

## 결론

| 질문 | 답 |
|---|---|
| 분리할까? | **분리한다.** 다만 엔진은 나누지 않는다. 스킬(사용자 진입점)만 둘로 나눈다. |
| 어떤 구조로? | **(b) 공통 엔진 1개 + 얇은 스킬 2개.** `youtube-digest`(URL·영상 콘텐츠)와 `recording-notes`(직접 녹음한 음성: 회의·인터뷰·강의·통화·음성메모). 코드는 계속 `~/Projects/whisper` 한 곳에 둔다. |
| 무엇부터? | ① 입력 종류(`--source video\|recording`) 분리와 사용자 맥락 입력(`--context`, `--terms`, `--speakers`) → ② 녹음용 문서 형식(`meeting`, `memo`) → ③ 개인정보 기본값(마스킹, 분석·팩트체크 끔) → ④ 긴 녹음의 교정·문서 단계 분할 → ⑤ 화자 분리(선택 기능) → ⑥ 다국어 혼용 |

근거 요약
- 두 용도는 **엔진의 80% 이상(fetch 이후의 ASR·환각 제거·교정 규칙·캐시)을 공유**하지만, **트리거 문구, 문서 형식, 개인정보 기본값, 교정 근거**가 다르다. 공유할 것은 코드, 다를 것은 스킬 지시문이다.
- 스킬 설명은 항상 컨텍스트에 실린다. 현재 `youtube-digest` 설명은 이미 **1,224자**다. Claude Code는 설명과 `when_to_use`를 합쳐 **1,536자에서 자른다**(아래 1절). 녹음 트리거까지 넣으면 한도에 닿아 키워드가 잘린다.
- 녹음본에는 팩트체크(`--verify`)와 정치·경제 분석이 맞지 않는다. 하나의 스킬에 두면 "개인 통화 녹음 → 웹검색으로 주장 전송" 같은 기본값 충돌을 지시문 분기로 막아야 한다. 스킬을 나누면 기본값 자체가 달라진다.

자신감: 구조 권고는 공식 문서(Tier 1)의 사실과 현재 코드 상태에 근거한 **판단**이다. 화자 분리 성능·VRAM 수치는 대부분 Tier 2~4라서 **추정**이며 자체 측정이 필요하다.

---

## 1. Claude Code 스킬 설계 공식 가이드 (트리거·설명 길이·컨텍스트 비용)

(Tier 1) Claude Code 공식 문서 [Skills](https://code.claude.com/docs/en/skills), 확인 2026-10-03:

- **설명 목록 예산**: "Claude Code loads a listing of skill names and descriptions into context … if you have many skills, Claude Code drops some descriptions to fit the listing's character budget … The budget scales at 1% of the model's context window."
- **설명 길이 한도**: "the combined `description` and `when_to_use` text is truncated at 1,536 characters in the skill listing … Put the key use case first."
- **본문은 호출 시에만 로드**: "a skill's body loads only when it's used, so long reference material costs almost nothing until you need it."
- **본문은 호출 후 계속 남는다**: "the rendered `SKILL.md` content enters the conversation as a single message and stays there across later turns." 압축(compaction) 후에는 스킬당 앞 5,000토큰만 다시 붙는다 → 중요한 지시는 위쪽에 둔다.
- **크기**: "Keep `SKILL.md` under 500 lines. Move detailed reference material to separate files."
- **보조 파일**: `SKILL.md` 옆에 `reference.md`, `examples.md`, `scripts/`를 두고 SKILL.md에서 링크한다. 스크립트는 "executed, not loaded".
- **스킬 간 공유**: 공식 문서가 제시하는 공유 수단은 `${CLAUDE_SKILL_DIR}`(스킬 자체 폴더), `${CLAUDE_PROJECT_DIR}`(프로젝트 루트), `${CLAUDE_PLUGIN_ROOT}`(플러그인 안의 스킬들이 공유)다. 개인 스킬 두 개가 한 엔진을 공유하는 경우는 **절대 경로로 외부 프로젝트를 호출**하는 현재 방식이 가장 단순하다(`youtube-digest`가 이미 `~/Projects/whisper`를 호출한다).

(Tier 1) Anthropic 공식 [Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices):

- `description`은 최대 1,024자(API 스킬 규격), 3인칭, "무엇을 하는지 + 언제 쓰는지".
- "Claude uses it to choose the right Skill from potentially 100+ available Skills." → 설명이 선택의 유일한 근거다.
- **도메인별 분리 패턴**: "For Skills with multiple domains, organize content by domain to avoid loading irrelevant context." (`reference/finance.md`, `reference/sales.md` 예시) — 하나의 스킬 안에서 유형별 참조 파일로 나누는 방식도 공식 패턴이다.
- 참조는 SKILL.md에서 한 단계 깊이까지만.
- "Avoid offering too many options … Provide a default." 

**공식 문서에 "스킬을 언제 둘로 나눠라"는 명시 규칙은 없다**(확인 범위 내). 따라서 아래 판단은 위 사실(설명 한도, 본문 상주 비용, 도메인별 로딩)에서 도출한 추론이다.

이 프로젝트에 적용하면:

| 관점 | 단일 스킬 | 스킬 2개 |
|---|---|---|
| 설명 길이 | 현재 1,224자 + 녹음 트리거 → 1,536자 한도 근접, 잘리면 뒤쪽 트리거("전사해줘" 등) 소실 위험 | 각자 1,000자 안팎으로 여유 |
| 호출 후 상주 비용 | 음성메모 하나 처리해도 OCR·프레임·분석·팩트체크 지시가 컨텍스트에 남음 | 필요한 지시만 로드 |
| 트리거 충돌 | 없음(하나뿐) | "전사해줘", "강의 노트" 같은 공통 문구는 두 설명에 **입력 형태로 구분하는 규칙**을 넣어야 함 |
| 유지보수 | 한 파일 | SKILL.md 2개. 엔진 공유로 중복은 지시문 수준 |

---

## 2. 녹음본 사용 사례별 요구사항

(Tier 4, 일반적 요구사항 정리 — 사용자 사용 패턴으로 검증 필요)

| 사례 | 길이 | 화자 | 필요한 출력 | 교정 근거 | 개인정보 위험 |
|---|---|---|---|---|---|
| 회의 | 30분~3시간 | 3~10명 | 안건별 논의, **결정사항, 액션아이템(담당자·기한)**, 미결 사항 | 안건·참석자 명단·용어집(사용자 제공) | 중~높음(사내 정보) |
| 인터뷰 | 30~90분 | 2~3명 | Q/A 구조, 화자 라벨, 인용구 | 질문지, 인터뷰이 이름 | 중 |
| 강의 녹음 | 1~3시간 | 1명(+질문) | 학습 노트(기존 `notes`와 거의 동일) | 강의자료·슬라이드(있으면) | 낮음 |
| 통화 | 5~30분 | 2명 | 요약, 약속·할 일 | 거의 없음 | **높음**(전화번호·계좌·주소) |
| 음성메모 | 수십 초~5분 | 1명 | 짧은 요약, **할 일·아이디어 목록** | 없음 | 중 |

유튜브 파이프라인과 비교

| 구분 | 공유 | 녹음본에서 다름 |
|---|---|---|
| 입력 | `prepare_local` (이미 구현) | 메타데이터 없음 → 제목=파일명 |
| ASR | large-v3, batched, 단어 타임스탬프, VAD 누락 재전사, 반복 환각 제거 | 그대로. 단 BGM 문제는 적고, 겹친 발화·원거리 마이크 문제가 큼 |
| 교정 | 부분 문자열 교체 규칙, 근거 기록 | 근거가 `context`뿐 → **사용자 제공 용어집·명단이 유일한 외부 근거**. 근거 없는 교정은 더 보수적으로 |
| OCR·프레임 | 영상 파일일 때만 | 녹음은 해당 없음 |
| 문서 형식 | `notes`(강의) | `meeting`, `interview`, `memo` 신규. `summary`는 통화에 재사용 가능 |
| 분석 섹션·팩트체크 | — | 기본 **끔**. 개인 대화의 '주장'을 웹검색에 보내는 것은 부적절 |
| 화자 분리 | 유튜브엔 거의 불필요 | 회의·인터뷰의 핵심 |

현재 코드 상태(직접 확인): `ytscribe/llm.py`의 프롬프트에 "영상·유튜브·YouTube"가 35회 등장한다. 녹음본을 넣으면 모델이 "영상"으로 가정한 문서를 만든다. 소스 중립 문구나 녹음 전용 프롬프트가 필요하다.

---

## 3. 화자 분리 옵션

| 옵션 | 라이선스·접근 | 6GB(RTX 2060) 적합성 | 한국어 근거 |
|---|---|---|---|
| **pyannote `speaker-diarization-community-1`** (pyannote.audio 4.x) | (Tier 1) [모델 카드](https://huggingface.co/pyannote/speaker-diarization-community-1): **CC-BY-4.0**, HF에서 조건 동의 후 토큰 필요. 받은 뒤 로컬 디렉터리에서 **오프라인 로드 가능**. `exclusive_speaker_diarization` 출력(겹침 없는 구간)이 ASR 정렬에 편함 | (Tier 2) [pyannote-audio 이슈 #1963](https://github.com/pyannote/pyannote-audio/issues/1963)(OPEN): 72분 음원에서 4.0.3 피크 **9.54GB**(3.3.2는 1.59GB). 원인은 임베딩 단계 배치 처리로 분석됨 → **6GB에서는 기본 설정 그대로 GPU 실행이 실패할 가능성이 높다(추정)**. 임베딩 배치 축소 또는 CPU 실행 필요 | 모델 카드 벤치마크 13개(AISHELL-4, AliMeeting, AMI, CALLHOME, DIHARD3 등)에 **한국어 데이터셋 없음** |
| **WhisperX** (`--diarize`) | (Tier 1) [README](https://github.com/m-bain/whisperX): 내부적으로 pyannote community-1 사용, HF 토큰 필요. 최신 v3.8.6(2026-05-25) | 위 pyannote 제약을 그대로 상속. 또 faster-whisper 위에 별도 래퍼라 **현재 파이프라인의 VAD 재전사·환각 제거 로직과 중복** | 정렬용 wav2vec2가 언어별로 필요. README: "Diarization is far from perfect" |
| **NVIDIA NeMo Sortformer** (`diar_sortformer_4spk-v1` 등) | NeMo 툴킷 의존(무거움) | (Tier 3) [Vast.ai 비교 글](https://vast.ai/article/whisper-pyannote-sortformer-diarization-vast): 16GB+ 권장, **최대 4화자**. 대화형 교환에서 과분할, 독백·겹침 발화엔 강함 | (Tier 1, 1차 논문) [arXiv 2606.10213](https://arxiv.org/html/2606.10213v1): 한국어 **유아-양육자** 음성에서 Sortformer DER 33.04%로 pyannote·SpeechBrain보다 우수. 단 일반 회의와 조건이 매우 다름 |

권장 (추정): 화자 분리는 **pyannote community-1을 선택 기능(`--diarize`)으로**, WhisperX를 통째로 들이지 말고 **pyannote만 추가**해 기존 단어 타임스탬프에 화자를 붙인다.
- Whisper 모델을 내린 뒤 실행한다(순차 VRAM 사용).
- GPU OOM이면 CPU로 전환한다(기존 ASR 폴백과 같은 방식). 임베딩 배치는 작게 한다(이슈 #1963의 분석, Tier 2).
- 회의는 `--speakers 4`(또는 min/max)를 받아 화자 수 추정 오류를 줄인다.
- **한국어 성능은 공개 근거가 없다.** 실제 회의 녹음 2~3개로 자체 평가(화자 수 정확도, 화자 교대 지점 오류)를 먼저 한다.
- 라벨은 `화자1/화자2`로 두고, 실명 매핑은 사용자가 준 `--speakers "김OO,이OO"` 명단과 발화 문맥으로 Claude가 **제안만** 한다(기존 "얼굴로 식별하지 않는다" 원칙과 같은 맥락).

CPU 실행 속도·실제 6GB 피크는 **모름** — 측정 필요.

---

## 4. 개인정보

### 4.1 claude CLI로 나가는 데이터

(Tier 1) Claude Code 공식 [Data usage](https://code.claude.com/docs/en/data-usage):
- "To interact with the LLM, Claude Code sends data over the network. This data includes all user prompts and model outputs."
- 보존: 개인 플랜(Free/Pro/Max)은 모델 개선 허용 시 5년, 비허용 시 30일. 상업 플랜(Team/Enterprise/API)은 기본 30일, ZDR은 별도 승인.
- 로컬: 세션 기록은 `~/.claude/projects/`에 30일 평문 저장. 현재 파이프라인은 `--no-session-persistence`를 쓰므로 서브프로세스 호출은 저장하지 않는 것으로 보인다(코드 확인, 동작은 추정).

즉, 교정·문서·분석 단계에서 **전사 전문이 Anthropic으로 전송된다.** `--verify`는 추가로 주장 목록을 WebSearch에 쓴다.

### 4.2 권장 기본값 (`recording-notes`)

1. **로컬 전용 모드**: `--asr-only`(이미 있음)를 "Claude에 보내지 않음"으로 명시해 안내한다.
2. **사전 마스킹**: Claude 호출 전에 정규식으로 주민등록번호(`\d{6}-[1-4]\d{6}`), 휴대전화, 계좌번호 패턴, 이메일을 `[전화번호]`처럼 치환한다. 원본과 마스킹 대응표는 로컬에만 둔다. 이름 마스킹은 정규식으로 어렵다 → 선택 기능으로 둔다.
3. **분석·팩트체크 기본 끔.** 사용자가 명시할 때만 켠다.
4. 결과 폴더(`output/`)에 녹음 원본·전사가 남는다는 점을 알린다. 삭제 옵션을 둔다.

### 4.3 녹음 적법성 (간단히)

- 통신비밀보호법 제3조 제1항: "누구든지 … 공개되지 아니한 타인간의 대화를 녹음 또는 청취하지 못한다." 제14조 제1항: "누구든지 공개되지 아니한 타인간의 대화를 녹음하거나 전자장치 또는 기계적 수단을 이용하여 청취할 수 없다." 위반 시 제16조 제1항: 1년 이상 10년 이하의 징역과 5년 이하의 자격정지.
  - **출처 등급 주의**: 국가법령정보센터(law.go.kr) 원문 페이지를 직접 열지 못했다(동적 렌더링). 조문은 검색 결과에 인용된 문구다. **Tier 1 원문 직접 확인은 못 했다** → 조문 문구는 **추정(높은 신뢰)**. 현행 시행일도 미확인.
- 판례 해석: '타인간의 대화' 금지는 대화에 원래 참여하지 않은 제3자의 녹음을 막는 취지다. 따라서 **대화 당사자가 자기 대화를 녹음하는 것은 이 조항 위반이 아니다**. 이 해석은 널리 알려져 있으나 이번에 판결 원문을 확인하지 못했다 → 추정.
- (Tier 1, 법원 공식 판례속보 제목) [대법원 2024. 2. 29. 선고 2023도8603](https://www.scourt.go.kr/portal/news/NewsViewAction.work?pageIndex=1&searchWord=&searchOption=&gubun=4&type=5&seqnum=9749): "종료된 대화의 녹음물을 재생하여 듣는 것이 통신비밀보호법상 '청취'에 해당하는지 여부". 검색 요약(Tier 3)에 따르면, 대화가 끝난 뒤 녹음물을 재생해 듣는 것은 '청취'가 아니라고 보았다(홈캠 자동녹음 사안, 무죄). 판결문 원문은 확인하지 못했다.
- **스킬 동작에 주는 시사점**: 파이프라인은 녹음이 적법한지 판단할 수 없다. 스킬은 "본인이 참여한 대화이거나 참석자 동의를 받은 녹음인지"를 **한 줄로 안내만** 하고 처리를 막지는 않는다. 개인정보보호법이 개인 용도 처리에 어떻게 적용되는지는 이번 조사 범위 밖이다(모름).

---

## 5. 구조 대안 비교

### (a) 단일 스킬 + 입력 유형 라우팅
- 장점: 진입점이 하나라 트리거 충돌이 없다. 파일 하나만 관리한다.
- 단점
  - 설명이 1,536자 한도에 근접한다.
  - 음성메모 하나에도 영상용 지시 전체가 컨텍스트에 상주한다.
  - 기본값이 충돌한다(유튜브: 분석 auto·verify 가능 / 녹음: 둘 다 끔, 마스킹 켬). 지시문 안의 조건 분기는 모델이 놓칠 수 있다.
- 완화책: 공식 "도메인별 참조 파일" 패턴(`reference/youtube.md`, `reference/recording.md`). 설명 길이 문제는 남는다.

### (b) 공통 엔진 + 얇은 스킬 2개 — **권장**
- 장점
  - 트리거가 입력 형태로 자연스럽게 갈린다. URL·"영상"이면 유튜브, 녹음 파일·"회의/통화/녹음"이면 녹음.
  - 기본값이 스킬 단위로 분리된다.
  - 엔진은 하나라 ASR·교정 개선이 양쪽에 동시에 반영된다.
- 단점: 공통 문구("전사해줘", "강의 노트")를 두 설명에서 서로 양보하도록 써야 한다. 실패 대응 표 등 일부 지시가 중복된다(엔진 README를 링크해 줄인다).

### (c) 3개 이상 (meeting-notes / lecture-notes / voice-memo / youtube-digest)
- 장점: 각 형식 지시가 가장 짧다.
- 단점
  - 같은 `.m4a` 파일에 어느 스킬이 걸릴지 **내용을 듣기 전에는 알 수 없다**. 트리거가 겹친다.
  - "강의 노트"는 유튜브 강의와 녹음 강의 모두에 해당한다.
  - 문서 형식 자동 판별(`--mode auto`)이 이미 엔진에 있으므로 형식별 스킬은 그 기능을 중복한다.
- 판단: 현재 사용량에서는 과분할이다(추정).

### 권장 구조 (b) 상세

```
~/Projects/whisper/                      # 공통 엔진 (유일한 코드 위치)
├── transcribe.py                        # --source video|recording (URL이면 video, 오디오 확장자면 recording 기본)
└── ytscribe/
    ├── llm.py                           # 프롬프트를 source별로: VIDEO_*, RECORDING_* (또는 소스 중립 + 블록 삽입)
    ├── privacy.py                       # (신규) 정규식 마스킹·복원
    └── diarize.py                       # (신규, 선택) pyannote → 단어별 화자

~/.claude/skills/
├── youtube-digest/SKILL.md              # URL·영상 파일 전용으로 좁힘
└── recording-notes/SKILL.md             # 녹음본 전용 (신규)
```

트리거 경계 (설명에 넣을 문구)

| 입력 | 스킬 |
|---|---|
| youtube.com / youtu.be 링크, "영상 요약" | youtube-digest |
| `.mp4/.mkv/.webm` + "강의 영상", "화면" | youtube-digest (OCR·프레임 필요) |
| `.m4a/.mp3/.wav/.ogg/.aac/.flac` 또는 "녹음", "회의록", "통화", "인터뷰 녹음", "음성메모", "보이스 메모" | recording-notes |
| 애매함("이 파일 전사해줘" + `.mp4` 회의 녹화) | recording-notes가 `--source recording`으로 처리하되, 화면 공유가 있으면 OCR을 켤지 묻는다 |

`youtube-digest` 설명 끝에 "For audio recordings (meetings, calls, voice memos) use recording-notes instead."를, `recording-notes`에는 반대 문구를 넣어 서로 양보시킨다.

`recording-notes` 설명 초안 (영어, 약 700자):

```yaml
name: recording-notes
description: |
  Turns a personal audio recording (meeting, interview, lecture recording, phone call, voice memo)
  into a Korean document: meeting minutes with decisions and action items (owner, due date),
  interview Q&A, study notes, a call summary, or a to-do list from a voice memo. Runs the local
  pipeline in ~/Projects/whisper (faster-whisper large-v3, optional speaker diarization) and uses
  Claude only for correction and the document, after masking phone numbers, resident registration
  numbers and account numbers. Accepts a user glossary, attendee list and agenda as context.
  Use when the user gives an audio file path (.m4a .mp3 .wav .ogg .aac .flac) or says 녹음, 회의록,
  통화, 인터뷰, 음성메모. For YouTube links or videos with on-screen content use youtube-digest.
  Triggers on: "회의록 만들어줘", "녹음 정리해줘", "통화 내용 요약", "음성메모 정리", "rec:".
```

---

## 6. 구현 순서 (우선순위)

| 순서 | 작업 | 이유 | 규모 |
|---|---|---|---|
| 1 | `--source recording` + 프롬프트 소스 중립화. 사용자 맥락 입력 `--context "회의 안건…"`, `--terms terms.txt`, `--speakers "김OO,이OO"`. 이 입력을 glossary·교정의 근거로 쓴다(근거 종류 `user`, 우선순위는 `description`과 같게) | 녹음본은 교정 근거가 문맥뿐이다. 사용자 용어집이 가장 싸고 효과가 크다. "영상" 가정 문서가 나오는 문제도 함께 해결한다 | 소 |
| 2 | 문서 형식 `meeting`(안건·결정·액션아이템 표: 할 일/담당/기한/근거 타임스탬프), `memo`(할 일·아이디어), `interview`(Q/A). `auto` 판별에 추가 | 화자 분리 없이도 가능하다. 담당자는 발화 내용("제가 할게요" + 문맥)으로만 추정하고 불명확하면 "미정"으로 둔다 | 소~중 |
| 3 | `recording-notes` SKILL.md 작성. `youtube-digest` 설명을 좁히고 서로 양보 문구 추가 | 1·2가 있어야 스킬이 의미가 있다 | 소 |
| 4 | `privacy.py` 마스킹. recording 기본값: 마스킹 켬, `--analysis off`, `--verify` 금지 | 통화·회의 데이터 외부 전송 최소화 | 소 |
| 5 | 긴 녹음(1~3시간) 처리: ASR은 이미 VAD 배치로 처리 가능(추정). **교정·문서 단계를 20~30분 단위로 나누고 마지막에 병합**한다. 체크포인트 캐시를 둔다 | 3시간 전사 전체를 한 번에 Claude에 넣으면 출력 한도·비용·교정 누락 위험이 있다(추정) | 중 |
| 6 | `--diarize` (pyannote community-1, 선택 기능, HF 토큰). GPU OOM이면 CPU로. 한국어 회의 샘플로 자체 평가 | 가치는 크지만 VRAM·토큰·성능 불확실성이 가장 크다. 2번의 결정·액션아이템은 화자 없이도 상당 부분 나온다 | 중~대 |
| 7 | 다국어 혼용(한·영 코드스위칭): 세그먼트별 언어 감지 또는 `--language ko` 유지 후 교정 단계에서 영어 용어 복원 | 수요를 확인한 뒤 진행 | 중 |

---

## 주요 포인트

- 엔진은 하나, 스킬은 둘(`youtube-digest`, `recording-notes`). 공유 코드는 `~/Projects/whisper`에 그대로 둔다.
- 분리의 핵심 근거: 설명 1,536자 한도(현재 1,224자 사용), 호출 후 본문 상주 비용, 녹음본의 개인정보 기본값이 다름.
- 녹음본 품질은 화자 분리보다 **사용자 맥락(용어집·참석자·안건)과 회의록 형식**이 먼저다. 둘 다 싸고 GPU 제약이 없다.
- pyannote community-1은 라이선스(CC-BY-4.0)와 오프라인 사용은 괜찮다. 그러나 4.x의 VRAM 피크 이슈(#1963, 미해결)와 한국어 벤치마크 부재 때문에 6GB 환경에서는 선택 기능 + CPU 폴백 + 자체 평가가 전제다.
- 전사 전문은 Claude 호출 시 Anthropic으로 간다(Tier 1). 녹음본은 마스킹을 기본으로 하고 분석·팩트체크는 끈다. 녹음 적법성은 안내만 한다.

## 개정·시행 정보

- 통신비밀보호법: 현행 시행일 **미확인**(law.go.kr 직접 조회 실패). 실제로 적용하기 전에 국가법령정보센터에서 제3조·제14조·제16조 현행 문구를 확인한다.
- pyannote.audio 최신 4.0.7(2026-06-30), WhisperX 최신 v3.8.6(2026-05-25) — `gh release list` 확인.

## 출처

- (Tier 1) [Claude Code Docs — Skills](https://code.claude.com/docs/en/skills) — 확인 2026-10-03
- (Tier 1) [Claude Docs — Skill authoring best practices](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices) — 확인 2026-10-03
- (Tier 1) [Claude Code Docs — Data usage](https://code.claude.com/docs/en/data-usage) — 확인 2026-10-03
- (Tier 1) [pyannote/speaker-diarization-community-1 모델 카드](https://huggingface.co/pyannote/speaker-diarization-community-1) — 확인 2026-10-03
- (Tier 1) [m-bain/whisperX README](https://github.com/m-bain/whisperX) (gh api) — 확인 2026-10-03
- (Tier 1, 검색 요약으로만 확인) [arXiv 2606.10213 — Korean toddler speech diarization](https://arxiv.org/html/2606.10213v1)
- (Tier 1, 제목만 확인) [대법원 판례속보 2023도8603](https://www.scourt.go.kr/portal/news/NewsViewAction.work?pageIndex=1&searchWord=&searchOption=&gubun=4&type=5&seqnum=9749)
- (Tier 2) [pyannote-audio issue #1963 — 4.0.3 VRAM](https://github.com/pyannote/pyannote-audio/issues/1963) — OPEN, 확인 2026-10-03
- (Tier 3) [Vast.ai — Pyannote vs Sortformer](https://vast.ai/article/whisper-pyannote-sortformer-diarization-vast)
- (Tier 3) [CaseNote — 통신비밀보호법 제3조](https://casenote.kr/%EB%B2%95%EB%A0%B9/%ED%86%B5%EC%8B%A0%EB%B9%84%EB%B0%80%EB%B3%B4%ED%98%B8%EB%B2%95/%EC%A0%9C3%EC%A1%B0), [제14조](https://casenote.kr/%EB%B2%95%EB%A0%B9/%ED%86%B5%EC%8B%A0%EB%B9%84%EB%B0%80%EB%B3%B4%ED%98%B8%EB%B2%95/%EC%A0%9C14%EC%A1%B0) (검색 결과 인용 문구)
- (Tier 3) [법률신문 — 홈캠 자동녹음 청취 판결](http://www.lawtimes.co.kr/news/articleView.html?idxno=196994)
- 로컬 확인: `README.md`, `ytscribe/fetch.py`(`prepare_local`), `ytscribe/llm.py`(`run_claude` 격리 옵션, 프롬프트 내 "영상/유튜브" 35회), `youtube-digest` 설명 길이 1,224자
