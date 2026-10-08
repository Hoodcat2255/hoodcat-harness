# Whisper 로컬(Linux) 세팅 조사 결과

> 조사일: 2026-10-03
> 대상 디렉토리: /home/hoodcat/Projects/whisper (현재 비어 있음, `.omc/`만 존재)

## 개요

이 머신(RTX 2060 6GB, CUDA 13 드라이버, Python 3.12, ffmpeg 6.1)에서는 **faster-whisper + pip 설치 CUDA 12 런타임(cuBLAS/cuDNN 9)** 조합이 가장 현실적이다. 시스템 CUDA Toolkit을 설치할 필요가 없다.
모델은 한국어 정확도를 우선하면 `large-v3`(int8_float16), 속도를 우선하면 `large-v3-turbo`(`turbo`)를 쓴다. turbo는 디코더를 32층에서 4층으로 줄인 모델이며, 한국어 같은 비영어권 언어에서는 정확도가 약간 떨어진다는 보고가 있다(Tier 3/4, 추정).
화자 분리나 단어 단위 타임스탬프가 필요하면 WhisperX를 쓴다(한국어 정렬 모델이 기본 제공됨). GPU가 없거나 빌드 하나로 끝내고 싶다면 whisper.cpp가 대안이다.
Whisper가 아닌 대안 중에서는 Qwen3-ASR(2026-01, Apache 2.0, 한국어 지원)이 가장 유력하다. 다만 6GB VRAM에서 돌려 본 사례와 한국어 수치는 확인하지 못했다.

## 상세 내용

### 1. 로컬 환경 점검 결과 (직접 확인, 확실)

| 항목 | 값 | 비고 |
|---|---|---|
| OS | Ubuntu 24.04.5 LTS | |
| CPU | AMD Ryzen 7 2700X (8C/16T), AVX2 지원 | CPU int8 추론 가능하나 large급은 느림 |
| RAM | 46GiB (가용 약 30GiB) | 충분 |
| GPU | NVIDIA GeForce RTX 2060, **6144MiB**, Compute Capability **7.5 (Turing)** | 조사 시점에 이미 **약 2.4GB 사용 중**(python 프로세스 1.7GB 포함), 남은 VRAM 약 3.7GB |
| 드라이버 | 580.178.04, CUDA 13.0 지원 | 하위 호환으로 CUDA 12 런타임 실행 가능 |
| CUDA Toolkit / cuDNN | **시스템에 없음** (`nvcc` 없음, ldconfig에 libcudnn/libcublas 없음) | pip wheel(`nvidia-cublas-cu12`, `nvidia-cudnn-cu12`)로 해결 |
| Python | 3.12.9 (asdf), `uv`, `pip` 사용 가능 | conda 없음 |
| ffmpeg | 6.1.1 (/usr/bin/ffmpeg) | 설치되어 있음 |
| 디스크 | 남은 공간 88G (사용률 80%) | large-v3 모델 약 3GB, torch 스택 수 GB |

시사점:
- Turing(7.5)은 FP16과 INT8을 지원하지만 **bfloat16은 지원하지 않는다**. CTranslate2 CHANGELOG에 따르면 `bfloat16`/`int8_bfloat16`은 Compute Capability 8.0 이상이 필요하다(Tier 1). 따라서 `compute_type`은 `float16` 또는 `int8_float16`을 쓴다.
- VRAM을 이미 다른 python 프로세스가 쓰고 있다. large-v3 int8에 batch까지 켜면 메모리가 부족할 수 있으므로 실행 전에 확인한다.

### 2. 구현체 비교 (최신 버전은 2026-10-03에 `gh release`로 확인, Tier 1)

| 구현 | 최신 릴리스 | 엔진 | 장점 | 단점 / 이 머신에서 주의할 점 |
|---|---|---|---|---|
| **faster-whisper** (SYSTRAN) | v1.2.1 (2025-10-31) | CTranslate2 (최신 v4.8.2, 2026-08-31) | README 기준 openai/whisper보다 최대 4배 빠르고 메모리도 덜 씀. int8 양자화, Silero VAD 내장, `turbo`/`distil` 모델 지원 | CTranslate2 최신판은 CUDA 12 + cuDNN 9만 지원 |
| **WhisperX** (m-bain) | v3.8.6 (2026-05-25), 3.8.7rc1 | faster-whisper + wav2vec2 정렬 + pyannote | 단어 단위 타임스탬프, 화자 분리, 배치 처리. **한국어 정렬 모델 기본 매핑**(`kresnik/wav2vec2-large-xlsr-korean`) | torch 2.8 (cu128) 스택이 무거움. 화자 분리에는 HF 토큰과 pyannote 약관 동의가 필요. 정렬 모델까지 올리면 6GB가 빠듯함 |
| **whisper.cpp** (ggml-org) | v1.9.4 (2026-09-11) | ggml (C/C++) | 의존성이 거의 없음. CPU 성능 좋음, Q5 등 양자화, `--vad` 지원, CUDA 빌드 가능 | CUDA 빌드에는 **nvcc(CUDA Toolkit)가 필요**한데 현재 없음. 설치하지 않으면 CPU로만 돌아감 |
| **openai/whisper** (원본) | v20250625 | PyTorch | 기준 구현 | 느리고 VRAM을 많이 씀(large 약 10GB로 알려짐, Tier 4). 6GB에서는 large 실행이 사실상 어려움(추정) |

### 3. 모델 선택

| 모델 | 파라미터 | 특징 |
|---|---|---|
| large-v3 | 약 1.55B | 한국어 정확도가 가장 높음(Whisper 계열 중). 디코더 32층 |
| large-v3-turbo (`turbo`) | 809M | 공식 모델 카드(Tier 1)에 따르면 디코더를 32층에서 **4층**으로 줄여 크게 빨라졌고 품질 저하는 작다. 99개 언어 지원, MIT 라이선스 |
| distil-large-v3 | - | **영어 전용**이라 한국어에는 쓸 수 없음 |

- 한국어 품질(Tier 3/4, 추정): 일부 블로그는 turbo가 한국어 같은 "Tier 2 언어"에서 large-v3보다 CER이 2~4%p 높다고 하는데, 이를 뒷받침하는 1차 벤치마크는 확인하지 못했다. 공식 모델 카드도 언어별 성능이 "uneven"하다고만 적고 있다. → **가진 음원으로 두 모델을 직접 비교하는 것을 권장**한다.
- 한국어로 파인튜닝한 파생 모델(예: Zeroth-KO로 파인튜닝한 turbo)이 HF에 있다. 품질과 라이선스는 모델마다 다르므로 확인이 필요하다.

### 4. VRAM 예산 (RTX 2060 6GB, 이미 약 2.4GB 사용 중)

faster-whisper README 벤치마크(Tier 1, RTX 3070 Ti, 13분 오디오) 기준:
- large-v2 int8, beam 5: **2926MB**
- large-v2 int8, `batch_size=8`: **4500MB**

→ 이 머신에서 쓸 수 있는 VRAM은 약 3.7GB다. **large-v3 int8_float16에 배치를 끄면 들어갈 가능성이 높고(추정)**, batch 8은 기존 프로세스를 종료하지 않는 한 OOM 위험이 있다. turbo는 파라미터가 절반 수준이라 여유가 더 있다.

### 5. 대안(비 Whisper) 모델

| 모델 | 한국어 | 크기 / 라이선스 | 비고 |
|---|---|---|---|
| **Qwen3-ASR-1.7B** | 지원 (52개 언어, 모델 카드 Tier 1) | 약 2B / Apache 2.0, 2026-01-29 | 모델 카드상 News-Multilingual 평균 WER 12.80으로 Whisper-large-v3(14.80)보다 낮다. **한국어 단독 수치는 모델 카드에 없음**. 타임스탬프는 별도 모델 Qwen3-ForcedAligner-0.6B로 처리. transformers/vLLM 백엔드 |
| **Cohere Transcribe (03-2026)** | 지원 (14개 언어) | 2B / Apache 2.0 | 영어 Open ASR 리더보드 1위(평균 WER 5.42). **타임스탬프와 화자 분리 미지원**(모델 카드) |
| **SenseVoiceSmall** | 지원 (zh/yue/en/ja/ko) | 소형 / 비자기회귀(non-autoregressive) | README 기준 Whisper-large보다 매우 빠름. 감정·이벤트 태그 제공. 긴 음원의 품질은 확인 필요 |

참고: HF Open ASR Leaderboard의 다국어 트랙은 독일어·프랑스어·이탈리아어·스페인어·포르투갈어만 평가하고 **한국어는 없다**(Tier 3). 한국어 비교는 직접 평가해야 한다.

### 6. 흔한 함정

1. **CUDA/cuDNN 버전 불일치**: ctranslate2 최신판은 CUDA 12 + cuDNN 9 전용이다. cuDNN 8 환경이면 ctranslate2 4.4.0으로 다운그레이드해야 한다(README Tier 1). 이 머신에는 시스템 cuDNN이 없으므로 pip wheel + `LD_LIBRARY_PATH` 설정이 핵심이다. `Could not load library libcudnn_ops.so.9` 오류가 나면 대부분 이 문제다.
2. **bfloat16 사용 금지**: Turing GPU에서는 지원하지 않는다.
3. **무음 구간 환각**: 무음 구간에서 "시청해주셔서 감사합니다" 같은 자막 문구를 생성하는 현상이 있다. `vad_filter=True`를 켜고, 반복 출력이 생기면 `condition_on_previous_text=False`로 바꾼다(Tier 3/4 커뮤니티 합의, faster-whisper 이슈 #843 등).
4. **언어 자동 감지 오류**: 짧거나 시작 부분에 음악이 있는 음원은 언어를 잘못 감지할 수 있으므로 `language="ko"`로 고정한다.
5. **WhisperX와 torch 버전 충돌**: WhisperX는 `torch~=2.8.0`(cu128 인덱스)에 고정되어 있다. 다른 torch 프로젝트와 같은 venv를 쓰지 않는다.
6. **whisper.cpp CUDA 빌드**: `-DGGML_CUDA=1`로 빌드하려면 nvcc가 필요하다. RTX 2060은 `-DCMAKE_CUDA_ARCHITECTURES="75"`로 지정한다.

## 코드 예제

### A. faster-whisper (권장)

```bash
cd /home/hoodcat/Projects/whisper
uv venv --python 3.12 .venv
source .venv/bin/activate

# faster-whisper와 CUDA 12 런타임 라이브러리(시스템 CUDA Toolkit 불필요)
uv pip install faster-whisper "nvidia-cublas-cu12" "nvidia-cudnn-cu12==9.*"

# pip로 설치한 cuBLAS/cuDNN 경로를 등록 (README 공식 방법)
export LD_LIBRARY_PATH=$(python -c 'import os, nvidia.cublas.lib, nvidia.cudnn.lib; print(os.path.dirname(nvidia.cublas.lib.__file__) + ":" + os.path.dirname(nvidia.cudnn.lib.__file__))')
```

```python
# transcribe.py
from faster_whisper import WhisperModel

# RTX 2060(Turing): float16 / int8_float16 사용 (bfloat16 불가)
model = WhisperModel("large-v3", device="cuda", compute_type="int8_float16")
# 속도 우선: WhisperModel("turbo", device="cuda", compute_type="int8_float16")
# CPU 대안:  WhisperModel("large-v3", device="cpu", compute_type="int8", cpu_threads=8)

segments, info = model.transcribe(
    "input.mp3",                       # ffmpeg 없이 PyAV로 디코딩
    language="ko",                     # 자동 감지 오류 방지
    beam_size=5,
    vad_filter=True,                   # 무음 구간 환각 감소
    vad_parameters={"min_silence_duration_ms": 500},
    condition_on_previous_text=False,  # 반복 환각 방지 (문맥 연결은 약해짐)
)
for s in segments:  # 제너레이터: 순회할 때 실제 추론이 실행됨
    print(f"[{s.start:7.2f} -> {s.end:7.2f}] {s.text}")
```

### B. WhisperX (단어 타임스탬프 + 화자 분리)

```bash
uv venv .venv-wx --python 3.12 && source .venv-wx/bin/activate
uv pip install whisperx
whisperx input.mp3 --model large-v3 --language ko --compute_type int8_float16 --batch_size 4 \
  --diarize --hf_token "$HF_TOKEN"   # 토큰은 환경변수로 전달
```

### C. whisper.cpp (CPU 또는 CUDA 빌드)

```bash
git clone https://github.com/ggml-org/whisper.cpp && cd whisper.cpp
sh ./models/download-ggml-model.sh large-v3-turbo
cmake -B build                       # CPU
# cmake -B build -DGGML_CUDA=1 -DCMAKE_CUDA_ARCHITECTURES="75"   # nvcc 필요
cmake --build build -j --config Release
ffmpeg -i input.mp3 -ar 16000 -ac 1 -c:a pcm_s16le input.wav   # 16kHz mono WAV 권장
./build/bin/whisper-cli -m models/ggml-large-v3-turbo.bin -l ko -f input.wav -osrt
```

## 주요 포인트

- 이 머신의 1순위는 **faster-whisper 1.2.1 + pip cuBLAS/cuDNN 9 + `int8_float16`**. 시스템 CUDA Toolkit은 설치하지 않아도 된다.
- RTX 2060(CC 7.5)에서는 bfloat16을 쓸 수 없다. VRAM은 실질적으로 약 3.7GB만 남아 있으므로 배치 크기에 주의한다.
- 한국어 정확도는 large-v3가 우선이고, turbo는 약 4배 이상 빠른 대신 정확도가 약간 낮다고 보고된다(추정). 실제 음원으로 A/B 테스트한다.
- 화자 분리나 단어 타임스탬프가 필요하면 WhisperX(한국어 정렬 모델 기본 제공)를 쓴다.
- 비 Whisper 대안으로는 Qwen3-ASR-1.7B와 SenseVoiceSmall을 검토할 수 있다. 한국어 수치는 1차 자료에서 확인하지 못했다.

## 출처

- (Tier 1) 로컬 환경: `nvidia-smi`, `lscpu`, `python3 --version`, `ffmpeg -version`, `ldconfig -p` 직접 실행 — 확인 2026-10-03
- (Tier 1) [SYSTRAN/faster-whisper README](https://github.com/SYSTRAN/faster-whisper) 및 릴리스 v1.2.1 — 확인 2026-10-03
- (Tier 1) [OpenNMT/CTranslate2 CHANGELOG / 릴리스 v4.8.2](https://github.com/OpenNMT/CTranslate2) — 확인 2026-10-03
- (Tier 1) [m-bain/whisperX README, pyproject.toml, alignment.py](https://github.com/m-bain/whisperX) — 확인 2026-10-03
- (Tier 1) [ggml-org/whisper.cpp README](https://github.com/ggml-org/whisper.cpp) 및 릴리스 v1.9.4 — 확인 2026-10-03
- (Tier 1) [openai/whisper-large-v3-turbo 모델 카드](https://huggingface.co/openai/whisper-large-v3-turbo) — 확인 2026-10-03
- (Tier 1) [Qwen/Qwen3-ASR-1.7B 모델 카드](https://huggingface.co/Qwen/Qwen3-ASR-1.7B) — 확인 2026-10-03
- (Tier 1) [CohereLabs/cohere-transcribe-03-2026 모델 카드](https://huggingface.co/CohereLabs/cohere-transcribe-03-2026) — 확인 2026-10-03
- (Tier 2) [QwenAudio/SenseVoice GitHub](https://github.com/QwenAudio/SenseVoice)
- (Tier 2) [faster-whisper Issue #843 (Silero VAD 환각)](https://github.com/SYSTRAN/faster-whisper/issues/843), [openai/whisper Discussion #679](https://github.com/openai/whisper/discussions/679)
- (Tier 3) [Open ASR Leaderboard 논문 (arXiv 2510.06961)](https://arxiv.org/html/2510.06961v4)
- (Tier 4) [vexascribe: Whisper Large-v3 vs Turbo](https://vexascribe.com/whisper-large-v3-vs-turbo), [gigagpu: Whisper VRAM Requirements](https://gigagpu.com/whisper-vram-requirements/), [Gladia: Best open-source STT 2026](https://www.gladia.io/blog/best-open-source-speech-to-text-models)
