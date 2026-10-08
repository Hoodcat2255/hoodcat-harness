# 한국어 전사 엔진 비교 조사 결과 (Whisper large-v3 유지 여부)

> 조사일: 2026-10-09
> 대상: `~/Projects/hoodcat-harness/whisper` (설치본 `~/Projects/whisper`)의 ASR 단계
> 관련 문서: `research-whisper-local-setup-20261003.md`

## 개요

**결론: Whisper large-v3를 기본 엔진으로 유지하고, Qwen3-ASR-1.7B를 병행 후보로 A/B 측정할 것을 권한다. 지금 바로 교체할 근거는 부족하다.**

- 공개된 한국어 수치 중 Whisper large-v3를 확실하게 앞서는 로컬 모델은 Qwen3-ASR-1.7B뿐이다. Qwen 기술 보고서 기준 FLEURS ko CER 2.57%다(Tier 1, 자체 보고). 제3자가 같은 조건(FLEURS ko, Q8)으로 측정한 차이는 4.60% 대 4.89%로 0.3%p에 그친다(Tier 3/4).
- 현재 측정값(CER 0.205와 0.104)은 기준 텍스트가 설명란 원고와 유튜브 자막이어서 기준 자체의 불일치가 크게 섞여 있다. 엔진 간 0.3~2%p 차이는 이 잡음에 묻힐 가능성이 높다(추정). 따라서 기준 텍스트를 손으로 교정한 짧은 구간을 만들어 비교해야 의미가 있다.
- Qwen3-ASR을 RTX 2060(Turing)에서 돌릴 때는 걸림돌이 확인됐다. bf16과 FlashAttention 2를 쓸 수 없어 fp16과 sdpa로 돌려야 하는데, 공식 `qwen-asr` 패키지(0.0.6)의 transformers 백엔드는 이 경로에서 인코더 윈도 어텐션을 적용하지 않는다. 그 결과 반복 루프가 생겼다는 보고가 있다(이슈 #213, 열려 있음). 이 때문에 **Transformers 네이티브 구현(`-hf` 체크포인트, transformers ≥ 5.13)**으로 시험해야 한다.
- Mac M4에서는 `mlx-audio`가 Qwen3-ASR과 Qwen3-ForcedAligner(한국어 지원)를 공식 지원한다. 지금 Mac 경로는 greedy 디코딩만 되므로 빔 서치 차이가 없다는 점에서도 Mac 쪽이 먼저 시험하기 좋은 환경이다.
- NVIDIA Parakeet과 Canary-1b-v2, distil-whisper는 한국어를 지원하지 않는다. Omnilingual ASR, MMS, SenseVoice, Moonshine, Cohere Transcribe는 한국어 CER이 Whisper large-v3보다 나쁘다. 따라서 이 모델들은 후보에서 제외한다.

## 상세 내용

### 1. 한국어 벤치마크 수치 (출처별, 서로 직접 비교 불가)

측정 조건(정규화, 양자화, 세트 구성)이 출처마다 달라 **같은 표 안의 수치끼리만** 비교해야 한다.

#### 1-a. Handy 한국어 리더보드: FLEURS ko test, Q8_0, CER%, 제3자 측정 (Tier 3/4)

| 모델 | CER % | GPU 속도(×RT, Vulkan) | 크기 | 라이선스 |
|---|---|---|---|---|
| Qwen3-ASR-1.7B | **4.60** | 3.8× | 2.04 GB | Apache-2.0 |
| whisper-large-v3 | 4.89 | 2.1× | 1.55 GB | (표기 Apache-2.0, 원본은 MIT) |
| whisper-large-v2 | 4.99 | 2.1× | 1.55 GB | |
| Fun-ASR-MLT-Nano-2512 | 5.20 | 9.0× | 0.83 GB | FunASR 자체 라이선스 |
| whisper-large-v3-turbo | 5.24 | 3.4× | 0.83 GB | |
| Voxtral-Mini-4B-Realtime-2602 | 5.27 | 0.9× | 4.73 GB | Apache-2.0 |
| whisper-medium | 5.46 | 4.3× | 0.77 GB | |
| Qwen3-ASR-0.6B | 5.82 | 8.0× | 0.79 GB | Apache-2.0 |
| cohere-transcribe-03-2026 | 6.57 | 8.0× | 2.41 GB | Apache-2.0 |
| moonshine-base-ko | 8.12 | – | 0.07 GB | MIT |
| SenseVoiceSmall | 8.27 | 32.5× | 0.24 GB | FunASR |
| nemotron-3.5-asr-streaming-0.6b | 8.89 | 14.5× | 0.70 GB | OpenMDW |

- 하드웨어는 AMD Ryzen 4750U 내장 GPU(Vulkan)다. 신뢰구간과 측정 날짜는 표기되어 있지 않다.
- 이 표에서 turbo는 large-v3보다 CER이 0.35%p(상대 약 7%) 높다. "turbo는 한국어가 약간 나쁘다"는 기존 판단과 방향이 같다. 다만 낭독체 기준이다.

#### 1-b. Qwen3-ASR 기술 보고서 부록 Table A.2: CER%, 자체 보고 (Tier 1, 단 이해당사자 측정)

| 세트 (ko) | Qwen3-ASR-0.6B | Qwen3-ASR-1.7B | Qwen3-ASR-Flash (API) |
|---|---|---|---|
| FLEURS ko | 3.72 | **2.57** | 2.07 |
| CommonVoice ko | 8.48 | 5.88 | 3.82 |
| MLC-SLM ko (대화체) | 10.31 | 8.61 | 8.09 |

- 보고서에는 Whisper-large-v3의 언어별 수치가 없다. 12개 언어(ko 포함) FLEURS 평균만 있으며, Whisper-large-v3 5.27, Qwen3-ASR-1.7B 4.90이다(Table 5). 30개 언어 전체(Fleurs††)에서는 Whisper가 8.16으로 Qwen3-ASR-1.7B의 12.60보다 낫다.
- 한국어는 CER로 평가했다고 명시되어 있다(4.1절).

#### 1-c. BuzzASR 논문 Table 7 (EMNLP 2026 채택): CV+FLEURS 합산 ko CER% (Tier 1)

| Whisper-large-v3 | BuzzASR SFT (large-v3 한국어 파인튜닝) | Omnilingual 1B | Omnilingual 7B | MMS | Cohere* | Qwen3-ASR-1.7B* |
|---|---|---|---|---|---|---|
| 5.72 | **4.61** | 13.41 | 11.19 | 20.30 | 9.34 | 7.39 |

\* Cohere와 Qwen3는 **정규화하지 않은 raw CER**이라 다른 열과 직접 비교할 수 없다고 논문이 밝히고 있다(문장부호가 포함되어 불리하다).
- Omnilingual과 MMS는 같은 정규화 조건에서도 Whisper보다 2~4배 나쁘다. 한국어 후보에서 제외할 근거로 충분하다.
- BuzzASR/korean(MIT)은 FLEURS 5.16 대 5.31로 개선 폭이 작다. 학습 데이터도 FLEURS와 CommonVoice(낭독체)뿐이라 방송, 회의, 통화 녹음에서 나아질지는 미지수다.

#### 1-d. TeamUNIVA 한국어 평가: 원본 Qwen3-ASR-1.7B CER (Tier 4, 커뮤니티)

clova_call 4.48, common_voice_ko 7.19, fleurs_ko 1.42, **ksponspeech 8.65**, zeroth 2.64 (단위 %).
- 평가 세트를 손으로 교정했고, 정규화 전사와 역정규화 전사 중 더 나은 점수를 택했다. 그래서 수치가 낮게 나온다. 자유 대화체(KsponSpeech)에서는 낭독체보다 오류가 4~6배 많다는 점이 참고할 만하다.

#### 1-e. 리턴제로 Awesome-Korean-Speech-Recognition: AI-Hub 7개 세트 각 3,000문장, 평균 CER% (Tier 2/3, 업체 측정, 2025-02~08)

리턴제로 5.91 · 리턴제로 Whisper 파인튜닝 6.59 · Naver ClovaSpeech 7.52 · ETRI 10.19 · Azure 10.88 · AWS 11.11 · OpenAI Whisper API 11.39 · Google v2 11.50 · Gemini 2.0 Flash 16.58 · Deepgram nova-2 21.02
- 경쟁사가 측정한 표이고 OpenAI Whisper "API"(large-v2 계열) 기준이다. gpt-4o-transcribe, ElevenLabs Scribe, Deepgram Nova-3의 한국어 수치는 1차 자료에서 찾지 못했다(모름).
- 시사점: 한국어 회의, 통화, 강의 도메인에서는 국내 상용 엔진이 범용 Whisper보다 CER이 약 4~5%p 낮다. 다만 이 엔진들은 음성 원본을 외부로 보내야 하므로 개인정보 원칙(전사까지 로컬)과 충돌한다.

#### 1-f. Open ASR Leaderboard

- `huggingface/open_asr_leaderboard` 저장소의 `scripts/data/multilingual.csv` 열은 de/fr/it/es/pt뿐이다. **한국어 트랙은 없다**(Tier 1, 저장소 데이터 직접 확인).

### 2. 후보별 판정

| 후보 | 한국어 | 6GB RTX 2060 | Mac M4 16GB | 판정 |
|---|---|---|---|---|
| **Whisper large-v3** (현행) | 기준선 | int8_float16 약 3GB, 검증됨 | mlx-whisper, greedy | **유지** |
| **Qwen3-ASR-1.7B** | FLEURS에서 근소~중간 우위 | bf16/FA2 불가 → fp16+sdpa. 가중치만 약 4GB라 ComfyUI와 동시 사용 시 빠듯함(추정) | `mlx-audio`의 `mlx-community/Qwen3-ASR-1.7B-8bit` | **A/B 시험 1순위** |
| Qwen3-ASR-0.6B | large-v3보다 약간 나쁨(5.82 대 4.89) | 여유 있음 | 매우 빠름 | 속도가 필요할 때만 |
| Whisper large-v3-turbo | large-v3보다 상대 약 7% 나쁨(FLEURS) | 여유 있음 | mlx 지원 | Mac 속도용으로 시험해 볼 만함 |
| 한국어 파인튜닝 Whisper (BuzzASR/korean 등) | FLEURS 소폭 개선 | CT2 변환이 필요하고 변환본은 확인 못 함 | 변환 필요 | 우선순위 낮음 |
| Fun-ASR-MLT-Nano | 5.20 (turbo 수준) | 가능(추정) | – | 라이선스가 비표준이고 이점이 적음 |
| Cohere Transcribe 03-2026 | 6.57 (Handy) | 2B | – | 제외. 언어 자동 감지가 없음 |
| SenseVoice, Moonshine-ko, Nemotron | 8~9% | 가능 | 가능 | 제외(정확도) |
| Omnilingual ASR, MMS | 11~20% | – | – | 제외(정확도) |
| Parakeet, Canary-1b-v2 | 미지원(유럽 25개 언어) | – | – | 제외 |
| distil-whisper | 영어 전용 | – | – | 제외 |
| CrisperWhisper | 영어/독일어 중심(Tier 4, 추정) | – | – | 제외 |
| whisper.cpp, WhisperKit | 같은 Whisper 가중치라 정확도 이득 없음 | nvcc 필요 | WhisperKit 활발(v1.1.1, 2026-10-08) | 엔진 교체 이득 없음 |
| lightning-whisper-mlx | 같은 가중치 | – | 마지막 push 2024-05 | 제외(관리 중단) |
| WhisperX | 정렬(wav2vec2-ko) + pyannote | 6GB 빠듯 | – | 화자 분리가 필요할 때 따로 검토 |
| VibeVoice-ASR (MS, 7~9B) | 한국어 수치 없음 | 불가(크기) | `mlx-audio` 지원 | 화자 분리 통합형. 16GB에서는 부담됨(추정) |

### 3. Qwen3-ASR 도입 시 확인된 함정 (GitHub 이슈와 README, Tier 1/2)

1. **Turing GPU**: FlashAttention 2는 Ampere 이상만 지원하고, bf16도 Ampere 이상만 지원한다(flash-attention README). RTX 2060에서는 fp16과 sdpa를 써야 한다.
2. **인코더 윈도 버그(#213, 열려 있음)**: `qwen-asr` 0.0.6의 transformers 백엔드는 sdpa나 eager에서 8초 윈도 마스크를 적용하지 않는다. 그래서 8초를 넘는 클립은 학습 때와 다르게 인코딩된다. 실제 운용 환경에서 180초 조각에 반복 루프가 생겼다는 댓글이 있다. 고치는 PR #103은 2026-02부터 머지되지 않았다. 댓글에 따르면 Transformers 5.14.1 네이티브 구현은 윈도 경계를 나눠 처리한다(Tier 4). → **`Qwen/Qwen3-ASR-1.7B-hf` + transformers ≥ 5.13**으로 시험한다.
3. **반복 루프(#129)**: vLLM 환경에서 파일 10개 중 1개꼴로 같은 구절을 약 2,000번 반복했다는 보고가 있다(중국어). Whisper에서 겪은 환각과 같은 계열의 위험이므로 기존 `is_degenerate` 필터가 계속 필요하다.
4. **긴 오디오 조각 이어 붙이기(#217, 2026-10-06)**: `transcribe()`가 내부에서 나눈 조각을 공백 없이 이어 붙인다. 한국어에서는 조각 경계마다 어절이 붙는다. 우리 파이프라인처럼 VAD 조각을 직접 넘기면 이 문제는 피할 수 있다.
5. **긴 입력의 품질 저하(#37)**: 30분짜리를 한 번에 넣으면 품질이 떨어진다. 조각 단위(15~30초)로 넣는 현재 구조가 맞다.
6. **타임스탬프**: Qwen3-ASR은 단어 타임스탬프를 직접 출력하지 않는다. Qwen3-ForcedAligner-0.6B를 추가로 돌려야 한다. 이 정렬기는 한국어를 지원하지만 `soynlp`가 필요하고, 한 번에 5분까지 처리한다. 기술 보고서 Table 9의 한국어 AAS는 37.2ms다. 대신 VRAM을 약 1.2GB(fp16, 추정) 더 쓴다.
7. **VRAM**: VELA 카드(1.7B 파생)에 따르면 bf16 기준 약 4~5GB가 필요하고, Ampere 이전 GPU에서는 fp16으로 대체된다고 적혀 있다(Tier 4). ComfyUI가 최대 4.9GB를 쓰는 상황에서는 지금처럼 OOM이 나면 CPU로 넘기는 경로가 필수다. CPU에서는 1.7B fp32라 매우 느릴 것으로 추정된다.
8. **힌트(context)**: Qwen3-ASR은 시스템 프롬프트로 문맥을 주는 기능을 지원한다(기술 보고서 2.2절). 그러나 hotword 기능이 반복 출력을 일으켰다는 이슈(#140)가 있다. Whisper에서 겪은 것과 같은 이유로 처음에는 끄고 시험한다.

### 4. 하드웨어별 정리

- **Linux RTX 2060 6GB**: large-v3 int8_float16 + beam 5 구성은 VRAM 효율이 가장 좋고 이미 검증됐다. Qwen3-ASR-1.7B는 int8 경로(CTranslate2 같은)가 없어 fp16으로 약 2.6배 큰 메모리를 쓴다. 정확도 이득이 측정으로 확인되지 않는 한 교체할 이유가 약하다.
- **Mac M4 16GB**: 메모리 여유가 크고 지금도 greedy만 쓰므로, Qwen3-ASR-1.7B-8bit(mlx-audio)를 시험하는 비용이 가장 낮다. soniqo의 M5 Pro 영어 측정에서 Qwen3-ASR 1.7B 8bit는 RTF 0.033, 메모리 2.7GB였다. WhisperKit large-v3-turbo는 RTF 0.084였다(Tier 3/4, 영어). 따라서 속도도 현재 mlx-whisper large-v3(실시간 대비 3.5배, RTF 약 0.29)보다 빠를 가능성이 높다(추정).

## 바로 시험할 후보와 측정 방법

### 후보 (우선순위 순)

1. **Qwen3-ASR-1.7B on Mac** (`mlx-audio`, `mlx-community/Qwen3-ASR-1.7B-8bit`, `language="Korean"`). 이미 쓰는 VAD 15초 창을 그대로 넘긴다. 30초 창도 함께 비교한다(LALM 계열은 문맥이 길수록 유리할 수 있다는 추정이 있다).
2. **Qwen3-ASR-1.7B on Linux** (`Qwen/Qwen3-ASR-1.7B-hf`, transformers ≥ 5.13, `torch.float16`, sdpa). `qwen-asr` 패키지의 transformers 백엔드는 쓰지 않는다(#213). ComfyUI가 쉬는 상태와 생성 중인 상태 둘 다에서 최대 VRAM을 기록한다.
3. **Whisper large-v3-turbo** (두 플랫폼 모두, `--model turbo`). 정확도 손실이 우리 영상에서도 FLEURS처럼 약 7% 수준인지 확인하고, Mac 속도 개선 폭을 잰다.

### 측정 방법

```bash
# 0) 공통: 기존 두 영상의 오디오와 현행 large-v3 결과를 기준선으로 고정한다
#    - KBS 리포트 (설명란 원고 기준)
#    - 전기 강의 (유튜브 자막 기준)

# 1) 기준 텍스트 보강: 각 영상에서 3~5분 구간을 골라 사람이 직접 교정한 정답을 만든다.
#    설명란 원고와 자동 자막은 실제 발화와 어긋나므로, 엔진 간 차이(0.3~2%p)를 가린다.

# 2) 같은 VAD 창 목록(JSON)을 저장해 두고 모든 엔진에 똑같이 넘긴다 (VAD 차이를 없앤다)
```

```python
# CER 계산: 공백과 문장부호를 제거한 뒤 글자 단위로 비교한다
# (한국어 띄어쓰기 차이와 엔진별 문장부호 습관이 점수에 섞이지 않게 하려는 것)
import re, jiwer

def norm(s: str) -> str:
    s = re.sub(r"[^\w]", "", s)          # 문장부호와 공백 제거
    return s.lower()

def cer_parts(ref: str, hyp: str) -> dict:
    o = jiwer.process_characters(norm(ref), norm(hyp))
    return {"cer": o.cer, "S": o.substitutions, "D": o.deletions, "I": o.insertions}
# S/D/I를 나눠 기록한다: D가 크면 누락(BGM 인터뷰 등), I가 크면 환각이다
```

기록 항목 (엔진 × 영상 × 플랫폼):

| 항목 | 방법 |
|---|---|
| CER (전체 기준 + 교정 구간 기준) | 위 `cer_parts` |
| 환각 수 | 반복 루프(`is_degenerate` 적중), 무음 구간 삽입, 크레딧류 문구 |
| 누락 | D 비율, BGM 인터뷰 구간 수동 확인 |
| 속도 | 실시간 대비 배수 (오디오 길이 / 벽시계 시간) |
| 최대 VRAM / RSS | Linux `nvidia-smi --query-gpu=memory.used --format=csv -lms 500`, Mac `/usr/bin/time -l` |
| 타임스탬프 | Qwen은 ForcedAligner 결과, Whisper는 단어 타임스탬프. 자막 동기 오차 샘플 확인 |

**판정 규칙(제안)**:
- 교정 구간 CER이 두 영상 모두에서 **상대 10% 이상** 개선되고, 새로운 유형의 환각이 없으며, Linux에서 ComfyUI가 쉬는 상태로 VRAM 안에 들어가면 그 플랫폼의 기본 엔진을 바꾼다.
- 한쪽 영상에서만 좋아지면 `--engine` 옵션으로 병행만 한다.
- 녹음(회의, 통화) 용도가 주목적이면 실제 녹음 1~2개의 5분 구간도 교정 정답으로 추가한다. 유튜브 영상은 대화체와 저음질 전화망 조건을 대표하지 못한다. Qwen도 KsponSpeech에서 CER 8.65%로 크게 나빠진다.

## 주요 포인트

- Whisper large-v3는 2026-10 시점에도 한국어에서 오픈 모델 최상위권이다. 같은 조건에서 확실히 앞서는 로컬 대안은 Qwen3-ASR-1.7B 하나이고, 그 차이는 출처에 따라 0.3%p(제3자)에서 2%p 이상(자체 보고)까지 벌어진다.
- 공개 벤치마크는 대부분 낭독체(FLEURS, CV)다. 회의, 통화, 방송 같은 실제 사용 조건의 차이는 직접 측정해야 알 수 있다.
- RTX 2060은 Qwen3-ASR에 불리하다(bf16 없음, FA2 없음, int8 경로 없음, sdpa 경로 버그). Mac M4가 먼저 시험하기 좋은 환경이다.
- turbo의 한국어 손실은 FLEURS 기준 상대 약 7%다. 정확도 우선이면 large-v3를 유지하고, Mac에서 속도가 필요하면 turbo를 고려한다.
- 한국어 정확도만 보면 국내 상용 엔진(리턴제로, ClovaSpeech)이 가장 좋다는 업체 측정 자료가 있다. 그러나 음성 원본을 외부로 보내야 하므로 현재 개인정보 원칙에서는 선택지가 아니다.

## 출처

- (Tier 1) [Qwen3-ASR Technical Report, arXiv 2601.21337v2](https://arxiv.org/abs/2601.21337): Table 1, 5, 9, 부록 Table A.2 — 확인 2026-10-09
- (Tier 1) [QwenLM/Qwen3-ASR README](https://github.com/QwenLM/Qwen3-ASR): 2026-06-26 네이티브 Transformers 지원, ForcedAligner 언어 — 확인 2026-10-09
- (Tier 1/2) Qwen3-ASR 이슈 [#213](https://github.com/QwenLM/Qwen3-ASR/issues/213), [#129](https://github.com/QwenLM/Qwen3-ASR/issues/129), [#217](https://github.com/QwenLM/Qwen3-ASR/issues/217), [#37](https://github.com/QwenLM/Qwen3-ASR/issues/37), [#140](https://github.com/QwenLM/Qwen3-ASR/issues/140)
- (Tier 1) [Qwen/Qwen3-ASR-1.7B-hf 모델 카드](https://huggingface.co/Qwen/Qwen3-ASR-1.7B-hf): transformers ≥ 5.13, 한국어 정렬에 soynlp 필요
- (Tier 1) [BuzzASR, arXiv 2609.09554 (EMNLP 2026)](https://arxiv.org/abs/2609.09554): Table 7 Korean 행
- (Tier 1) [huggingface/open_asr_leaderboard `scripts/data/multilingual.csv`](https://github.com/huggingface/open_asr_leaderboard): 한국어 열 없음
- (Tier 1) [Dao-AILab/flash-attention README](https://github.com/Dao-AILab/flash-attention): Ampere 이상, bf16은 Ampere 이상
- (Tier 1) [Blaizzy/mlx-audio README](https://github.com/Blaizzy/mlx-audio): Qwen3-ASR, ForcedAligner, Parakeet(EU), Canary(EU) 지원 표, v0.5.8 (2026-10-05)
- (Tier 1) [cjpais/transcribe-rs README](https://github.com/cjpais/transcribe-rs): 엔진 목록
- (Tier 2) [NVIDIA NGC canary-riva-1b](https://catalog.ngc.nvidia.com/orgs/nvidia/teams/riva/models/canary-riva-1b): Riva 배포판에만 ko-KR 표기. 공개 HF Canary-1b-v2는 EU 25개 언어
- (Tier 2) [Cohere Transcribe changelog](https://docs.cohere.com/changelog/cohere-transcribe-03-2026): 14개 언어(ko 포함), Apache-2.0
- (Tier 2/3) [rtzr/Awesome-Korean-Speech-Recognition](https://github.com/rtzr/Awesome-Korean-Speech-Recognition): 업체 측정, 마지막 커밋 2025-08-15
- (Tier 3/4) [Handy 한국어 리더보드](https://models.handy.computer/languages/ko): FLEURS ko, Q8_0
- (Tier 4) [BuzzASR/korean 모델 카드](https://huggingface.co/BuzzASR/korean)
- (Tier 4) [TeamUNIVA/qwen3_asr_1.7b_ko_beta](https://huggingface.co/TeamUNIVA/qwen3_asr_1.7b_ko_beta)
- (Tier 4) [Vision21Tech/VELA](https://huggingface.co/Vision21Tech/VELA): VRAM과 fp16 대체 메모
- (Tier 3/4) [soniqo Apple Silicon 벤치마크](https://soniqo.audio/ko/benchmarks/qwen3-asr-vs-whisper): 영어 전용
- (Tier 4) [Whisper Notes: Qwen3-ASR vs Whisper](https://whispernotes.app/blog/qwen3-asr-vs-whisper)

자신감: Qwen3-ASR의 한국어 지원, 공식 수치, 이슈 내용, 하드웨어 제약은 **확실**(Tier 1)하다. 우리 영상에서 어느 엔진이 나은지는 **모름**(직접 측정 필요)이다. 그 외 비교와 VRAM 추정은 **추정**이다.
