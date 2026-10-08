# 영상 프레임 분석을 결합한 전사 정확도 향상 조사 결과

> 조사일: 2026-10-03
> 대상: `/home/hoodcat/Projects/whisper/transcribe.py` (yt-dlp → faster-whisper large-v3 → claude -p 요약)
> 모드: 일반 조사 / 도메인: 소프트웨어·기술 (1-B)

## 개요

**결론부터 말하면, 제안은 방향이 맞지만 우선순위로는 2순위입니다.** 화면 텍스트(이름 자막, 슬라이드, 하드코딩 자막)를 전사 보정에 쓰는 것은 연구로도 효과가 확인된 방법입니다. 슬라이드 OCR 키워드를 LLM 기반 ASR에 넣으면 키워드 단어 오류율(B-WER)이 약 44~46% 줄었습니다 (MaLa-ASR, SlideSpeech). 영상 맥락으로 사후 보정하면 WER이 7~21% 상대 개선됐습니다 (VPC). 하지만 지금 겪는 오류의 상당수(송낙규/송락규, 인지심리학자, 태백산맥)는 **영상 제목·설명·챕터·업로더 자막** 같은 메타데이터와, **요약과 분리된 "제약된 보정 단계"**만으로도 더 싸게 잡을 수 있습니다. 그래서 다음 순서를 권장합니다.

1. 메타데이터 활용
2. 보정 단계를 요약에서 분리
3. 저비용 로컬 OCR 프레임 분석
4. 일부 구간만 Claude 이미지 분석

LLM 보정의 가장 큰 위험은 "말하지 않은 단어를 넣는 과잉 보정(환각)"입니다. 그래서 보정은 **후보 목록이 있을 때만, 변경 내역을 남기면서** 하도록 제한해야 합니다.

## 상세 내용

### 1. 현재 오류 유형별로 영상 프레임이 실제로 도움이 되는가

| 오류 유형 | 프레임 분석의 효과 | 더 싼 대안 |
|---|---|---|
| 고유명사 오인식 (인명·지명) | **높음.** 뉴스·인터뷰의 이름 자막(lower third), 강연 슬라이드에 정답 표기가 나오는 경우가 많음 | 제목·설명·챕터·고정 댓글 → hotwords/initial_prompt, 보정 단계 용어집 |
| 일반 단어 오인식 (인지심의학자 등) | 낮음~중간. 화면에 그 단어가 나올 때만 | LLM 문맥 보정 (이미 효과 있음) |
| BGM 깔린 인터뷰 구간 누락 | **한국 예능·다큐처럼 하드코딩 자막(화면에 박힌 자막)이 있으면 높음.** OCR로 대사를 직접 복원 가능 | 업로더 수동 자막, 유튜브 자동자막 교차검증, VAD 임계값 조정 |
| 영상 끝 환각 문장 | 거의 없음 | `hallucination_silence_threshold`, no_speech/compression 필터, 자동자막 대조 |
| "이것 보세요" 같은 지시어 | 중간. 전사 정확도보다는 **요약 품질**(무엇을 가리키는지)에 기여 | — |

판단: 프레임 분석이 가장 효과적인 곳은 **(a) 이름 자막·슬라이드가 있는 뉴스·강연·인터뷰 영상**과 **(b) 하드코딩 자막이 있는 한국 예능·다큐 영상**입니다. 토킹헤드 브이로그 같은 영상에서는 얻는 게 거의 없습니다. (추정, Tier 4 일반론 + 아래 연구 근거)

### 2. 프레임 추출 전략

| 전략 | 장점 | 단점 | 권장 용도 |
|---|---|---|---|
| 고정 간격 (`fps=1/5` 등) | 단순하고 누락이 적음 | 중복 프레임이 많음 → 중복 제거 필수 | 기본 백업 |
| 장면 전환 감지: ffmpeg `select='gt(scene,0.3)'` | 추가 의존성 없음, 빠름 | 이름 자막이 페이드인할 때는 장면 변화로 잡히지 않을 수 있음 | 슬라이드 전환 감지 |
| PySceneDetect `ContentDetector`/`AdaptiveDetector` | HSV 기반, 적응형 임계값 지원 | 컷 검출용이라 자막 등장 검출과는 목적이 다름 | 편집이 많은 영상 |
| 전사 기반 타겟팅 | 비용이 최소 | 화면 텍스트가 발화보다 먼저 또는 나중에 나옴 → ±수 초 창이 필요 | Claude 이미지 분석 대상 선정 |

**권장 방식 (조합):**
1. 영상 전체를 2~3초 간격으로 저해상도 샘플링합니다.
2. perceptual hash(pHash/dHash)로 중복을 제거합니다.
3. 로컬 OCR을 전부 돌립니다 (비용 0).
4. 결과에서 "텍스트가 바뀐 시점"만 시간 구간이 붙은 화면 텍스트 목록으로 만듭니다.
5. Claude 이미지 분석은 지시어 구간이나 OCR 신뢰도가 낮은 구간 같은 소수 프레임에만 씁니다.

- 하단 1/3 영역(이름 자막)과 하단 자막 영역은 **크롭해서 따로 OCR**하면 정확도와 속도가 모두 좋아집니다 (Tier 4 일반 관행, 추정).
- ffmpeg `select` 필터의 scene 값과 `scdet` 필터의 값은 계산 방식이 달라 임계값을 따로 조정해야 합니다 (Tier 3 ffmpeg-cookbook).

**yt-dlp로 저해상도 영상 받기** (옵션은 yt-dlp README에서 확인, Tier 1):

```bash
# 영상만(오디오 제외) 480p 이하. 화면 텍스트용이면 480~720p가 적당
yt-dlp -f "bv*[height<=720][ext=mp4]/bv*[height<=720]" -o "%(id)s.video.%(ext)s" URL

# 특정 구간만: "*" 접두사 = 시간 범위
yt-dlp -f "bv*[height<=720]" --download-sections "*10:15-11:00" URL

# 메타데이터 + 수동/자동 자막만 (영상은 받지 않음)
yt-dlp --skip-download --write-info-json --write-subs --write-auto-subs \
       --sub-langs "ko.*" --sub-format "vtt/srt/best" URL
```

```bash
# 프레임 추출 예시 (ffmpeg 6.1)
# 1) 고정 간격 3초, 가로 1280으로 축소
ffmpeg -i in.mp4 -vf "fps=1/3,scale=1280:-2" -q:v 3 frames/%05d.jpg
# 2) 장면 전환 + 타임스탬프 로그
ffmpeg -i in.mp4 -vf "select='gt(scene,0.3)',showinfo,scale=1280:-2" -vsync vfr frames/s_%05d.jpg 2> scene.log
# 3) 특정 시각 1장 (전사 타겟팅)
ffmpeg -ss 00:10:21.5 -i in.mp4 -frames:v 1 -vf scale=1280:-2 t_621.jpg
```

해상도: 720p 정도면 이름 자막을 읽기에 충분하다고 봅니다 (추정). 작은 슬라이드 글씨가 있을 때만 1080p 크롭을 씁니다. 1280×720 이미지는 Claude 기준 약 1,196 visual token입니다 (아래 5절 공식).

### 3. 화면 텍스트 추출 엔진 비교

| 엔진 | 한국어 | 리소스 | 속도·비용 | 비고 |
|---|---|---|---|---|
| **PaddleOCR PP-OCRv5 `korean_PP-OCRv5_mobile_rec`** | 공식 한국어 데이터셋 정확도 88.0% (이전 세대 대비 +65%) (Tier 1 HF 모델카드) | CPU로 가능, 모바일 모델 | 무료 | **1순위 권장.** 크롭한 자막 영역에 적합 |
| EasyOCR (ko) | 지원 | GPU 권장(PyTorch) | 무료 | PaddleOCR 대비 정확도 비교 근거 미확보 (모름) |
| Tesseract `kor` | 지원 | CPU | 무료 | 장식 폰트·그림자 자막에 약하다는 게 일반 평가 (Tier 4, 추정) |
| **Qwen3-VL-2B/4B (GGUF, llama.cpp/Ollama)** | 32개 언어 OCR 지원 (Tier 1 Qwen 공식 HF) | 2B 양자화 약 1.9GB, 4B는 더 큼 | 무료, 느림 | 6GB에서 가능하지만 **ComfyUI(최대 약 4.9GB)와 동시 실행은 불가** → whisper·ComfyUI와 순차 실행 필요 |
| Qwen2.5-VL-3B (4bit) | 지원 | INT4 약 2GB (Tier 3/4) | 무료 | Qwen3-VL이 후속 모델이라 신규 도입 이점은 낮음 |
| **Claude (이미지 입력)** | 매우 좋음 (추정) | 없음 (원격) | 이미지당 약 1.2k 토큰(720p) | 지시어 해석·도표 설명처럼 "이해"가 필요한 구간에만 사용 권장 |

- Claude 공식 제약 (Tier 1 vision 문서): **사진 속 사람의 얼굴로 신원을 밝히는 일은 하지 않습니다.** 다만 화면에 **글자로 적힌 이름 자막을 읽는 것은 OCR 작업**이라 문제없습니다. 화질이 낮거나 200px 미만인 이미지에서는 환각 가능성이 있다고 명시돼 있습니다.
- VRAM 운영: whisper(int8_float16 large-v3)와 VLM을 동시에 올리지 말고, 단계별로 프로세스를 끝내 메모리를 해제하는 방식을 권장합니다 (추정).

### 4. 연구 근거: 화면 텍스트·영상 맥락으로 ASR 보정

| 연구 | 방법 | 결과 | 시사점 |
|---|---|---|---|
| MaLa-ASR (arXiv 2406.05839) | 슬라이드 OCR 키워드를 LLM-ASR 프롬프트에 넣음 ("관련 없으면 무시") | WER 9.4→9.0% (소폭), **B-WER 10.8→5.8% (약 46% 감소)**. 키워드의 약 88.8%가 원래 쉽게 인식되는 일반 단어라 전체 WER 개선은 작음 | **고유명사·전문용어에만 효과가 집중됨** → 현재 오류 유형과 정확히 맞음 |
| VPC, Video-guided Post-ASR Correction (arXiv 2506.07323) | VideoLLaMA2로 영상 맥락 추출 → GPT-4o로 사후 보정, 학습 없음 | WER 상대 개선 7.5~20.8% (예: WavLM 29.83→23.64) | 학습 없이 "전사 → LLM 보정" 구조로도 효과가 있음. 단, 영어 TV 데이터셋 기준 |
| VAPO / SlideSpeech (arXiv 2510.08618) | 슬라이드 이미지와 음성을 함께 처리 | 파이프라인(OCR→키워드) 대비 개선 | **슬라이드 텍스트를 그대로 넣으면 실제로 말하지 않은 내용이 생기는 환각**이 보고됨 |
| DeRAGEC (ACL Findings 2025), RLLM-CF 등 | 고유명사 후보를 검색·정제한 뒤 보정 | WER 28% 상대 감소 (DeRAGEC) | LLM 보정의 핵심 위험은 **과잉 보정(말하지 않은 개체명 삽입)** → 후보 제한, 검증 단계가 필요 |

정리하면, "화면 텍스트 → 후보 용어집 → LLM이 제약된 보정"이 근거가 가장 탄탄한 형태입니다. 다만 위 연구는 모두 영어 또는 중국어 기준이라, **한국어 효과 크기는 확인하지 못했습니다** (추정).

### 5. claude CLI(-p)에 이미지를 넘기는 방법 (공식 문서 기준)

| 방법 | 근거 | 비고 |
|---|---|---|
| **A. Read 도구 허용 + 프롬프트에 경로 명시** | (Tier 1) tools-reference: "PNG, JPG 같은 이미지는 Claude가 볼 수 있는 시각 콘텐츠로 반환된다. 큰 이미지는 리사이즈·재압축되며, v2.1.196부터는 리사이즈 후에도 500KB를 넘으면 JPEG으로 재인코딩" | 지금 쓰는 `--tools ""`를 `--tools "Read" --allowedTools "Read"`로 바꿔야 함. 작업 디렉터리 밖 파일이면 `--add-dir` 필요. 도구 호출 턴 수만큼 지연과 토큰이 늘어남 |
| B. `--input-format stream-json`으로 image content block 직접 전송 | (Tier 1) Agent SDK 스트리밍 입력 문서: 스트리밍 입력 모드는 이미지 첨부를 지원하고, single message 모드는 "Direct image attachments" 미지원. CLI `--input-format stream-json`이 같은 프로토콜인지는 **문서에 명시되어 있지 않음** | **실측 필요 (추정).** 되면 도구 턴 없이 한 번에 여러 이미지를 보낼 수 있음 |
| C. Python `claude-agent-sdk` 스트리밍 입력 | (Tier 1) 공식 예제가 base64 image block 사용 | 파이썬 파이프라인에 넣기 쉬움 |
| D. Anthropic API 직접 호출 | (Tier 1) vision 문서 | API 키와 종량 과금 필요. 구독 계정의 CLI와는 별개 |
| `@경로` 멘션 | -p 모드에서 이미지를 첨부하는 동작은 **문서에서 확인하지 못함** | 모름 |

방법 A를 권장하는 예시입니다.

```bash
# 프레임 파일들을 작업 디렉터리 아래에 두고 Read만 허용
claude -p "$(cat correct_prompt.txt)" \
  --tools "Read" --allowedTools "Read" \
  --strict-mcp-config --no-session-persistence \
  --output-format json --max-turns 30
# 프롬프트 안에서: "다음 프레임을 Read로 읽어 화면 텍스트를 추출: frames/t_621.jpg (10:21) ..."
```

**토큰 비용** (Tier 1 vision 문서):
- 공식: `⌈W/28⌉ × ⌈H/28⌉` visual token. Claude 4.7 이후 모델은 긴 변 2576px, 최대 4,784 토큰. 그 외 모델은 1568px, 1,568 토큰.
- 854×480 ≈ 558 토큰, 1280×720 ≈ 1,196 토큰, 1920×1080 ≈ 2,691 토큰(고해상도 등급).
- 예: 720p 30장 ≈ 36k 입력 토큰. 문서의 예시 단가(Opus 5 입력 $5/M)로 계산하면 약 $0.18입니다. 구독형 CLI라면 사용량 한도에서 차감됩니다 (추정).
- 요청당 이미지 수: API는 최대 600장이지만, **20장을 넘으면 장당 크기 제한이 더 엄격해짐** (양 변 2000px 이하 권장). 32MB 요청 크기 한도도 있음.

### 6. 프레임보다 싸고 효과적인 대안·보완책

1. **메타데이터 → hotwords / initial_prompt** (P0)
   - `--write-info-json`의 `title`, `description`, `chapters`, `uploader`, `tags`에서 고유명사 후보를 추출합니다.
   - faster-whisper `BatchedInferencePipeline.transcribe()`도 `initial_prompt`와 `hotwords`를 받아 내부로 전달합니다 (Tier 1 소스 확인. batched 모드는 `condition_on_previous_text=False` 고정).
   - initial_prompt는 Whisper 구조상 **약 224 토큰 이내**여야 합니다. 넘으면 앞부분이 잘리거나 무시될 수 있습니다 (Tier 4, 정확한 동작은 구현마다 다름). 고유명사 20~30개 이내로 짧게 유지하세요.
   - hotwords는 강한 logit bias라 남용하면 오삽입 위험이 있습니다 (Tier 4).
2. **업로더 수동 자막이 있으면 그대로 정답에 가까운 기준으로 사용** (P0). 수동 자막과 자동 자막을 구분해 받으세요.
3. **유튜브 자동자막 교차검증** (P1). Whisper large-v3가 일반적으로 더 정확하다는 보고가 있습니다 (Tier 4, 한국어 직접 비교는 미확보). 대신 **Whisper가 비운 구간(BGM 인터뷰)이나 끝부분 환각 탐지**에는 "두 번째 의견"으로 유용합니다. 시간이 겹치는데 한쪽에만 텍스트가 있으면 플래그를 세우는 방식입니다.
4. **보정 단계를 요약에서 분리** (P0). 현재는 요약하면서 보정하므로 보정된 전사본(.srt/.txt)이 남지 않습니다. 보정 결과는 `{시각, 원문, 수정안, 근거(메타데이터/OCR/문맥), 확신도}` JSON 목록으로 받고, 적용은 스크립트가 하게 합니다.

### 7. 권장 파이프라인

```
[0] yt-dlp: 오디오(m4a) + info.json + 수동/자동 자막(ko) ── 영상은 아직 받지 않음
[1] 용어집 v1 = 제목/설명/챕터/태그/업로더에서 고유명사 추출 (claude -p 1회, 텍스트만)
[2] faster-whisper 전사 (hotwords/initial_prompt = 용어집 상위 N개, 224 토큰 이내)
[3] 화면 텍스트 필요성 판정 (영상 유형 휴리스틱: 뉴스/강연/인터뷰/예능 → 진행, 브이로그 → 생략)
    └ 진행 시: 720p 영상만 다운로드 → 3초 간격 + 장면 전환 프레임 → pHash 중복 제거
              → PaddleOCR(ko) 전체 + 하단 영역 크롭 OCR → 시간 구간별 화면 텍스트 목록
              → 용어집 v2 = v1 + OCR 고유명사(시각 포함)
[4] 보정 단계 (claude -p, 텍스트만):
    입력 = SRT + 용어집 v2 + 자동자막 diff
    규칙 = "용어집이나 화면 텍스트에 근거가 있을 때만 교체", "새 문장 생성 금지",
           "누락 의심 구간은 수정하지 말고 표시만"
    출력 = 변경 목록 JSON → 스크립트가 적용 → .corrected.srt
[5] (선택) 타겟 이미지 분석: 지시어 구간·누락 의심 구간·OCR 신뢰도 낮은 구간의 프레임
    ≤20장만 claude -p --tools Read로 확인 (설명 주석 추가, 하드코딩 자막 복원)
[6] 요약: .corrected.srt 기준으로 기존 요약 단계 실행
```

**프레임과 발화의 시간 정렬**:
- 이름 자막은 보통 발화 시작 후 수 초 뒤에 나타나 수 초간 유지됩니다.
- 슬라이드는 발화보다 먼저 바뀌는 경우가 많습니다 (Tier 4, 추정).
- 그래서 세그먼트별로 정확한 시각을 매칭하지 말고 **[start−5s, end+10s] 창 안의 화면 텍스트를 후보로 제공**합니다.
- `--download-sections`로 일부 구간만 받으면 키프레임 경계 때문에 앞부분이 어긋날 수 있습니다. 정확한 컷이 필요할 때만 `--force-keyframes-at-cuts`를 쓰세요(재인코딩이라 느림, Tier 1 README).

### 8. 위험 요소

| 위험 | 내용 | 완화책 |
|---|---|---|
| 과잉 보정·환각 | 슬라이드나 화면 텍스트를 "말한 것"으로 삽입 (VAPO 보고), 개체명 오삽입 (DeRAGEC 등) | 교체만 허용(삽입 금지), 근거 필드 필수, 변경 목록 diff 검토, 원본 전사 보존 |
| 비용·한도 | 프레임 전체를 Claude에 넣으면 영상 1시간당 수백 장, 수십만 토큰 | 로컬 OCR을 기본으로, Claude는 20장 이하 타겟 분석만 |
| VRAM 경합 | ComfyUI 최대 약 4.9GB + whisper + VLM → OOM | 단계별 순차 실행. OCR은 PaddleOCR CPU 모드 우선 |
| 시간 불일치 | 화면 텍스트와 발화 시각 차이 | 창(window) 매칭, 근거 시각 기록 |
| 저작권·약관 | YouTube 약관은 "서비스가 명시적으로 허용하지 않는 한 콘텐츠를 access, reproduce, download" 하는 것을 금지 (Tier 1 YouTube ToS 인용, 검색 요약 경유) | 영상 다운로드는 오디오 다운로드와 같은 약관 위험이 있음. 개인 학습·접근성 용도로 한정하고, 산출물(프레임, 전사본) 재배포는 하지 말 것. 법적 판단은 Tier 1 직접 검토 필요 (확인 필요) |
| 얼굴 기반 인물 식별 | Claude 정책상 불가 | 이름은 반드시 화면 텍스트(자막)에서만 가져오기 |

## 주요 포인트

- **제안은 타당합니다.** 다만 "모든 구간에서 프레임 분석"이 아니라 **"화면 텍스트가 있는 영상 유형에서, 로컬 OCR로 용어집을 만들어 제약된 보정에 쓰는 형태"**가 비용 대비 효과가 가장 좋습니다. 근거: MaLa-ASR의 B-WER 약 46% 감소, VPC의 WER 7~21% 개선.
- **우선순위:**
  - P0: 메타데이터 용어집 + hotwords/initial_prompt + 보정 단계 분리(JSON 변경 목록)
  - P1: 수동/자동 자막 교차검증
  - P2: PaddleOCR 기반 프레임 OCR
  - P3: Claude 이미지 타겟 분석
  - P4: 로컬 VLM
- **claude -p에서 이미지 입력**은 `--tools "Read" --allowedTools "Read"`와 파일 경로 지시 방식이 공식 문서로 확인된 가장 간단한 경로입니다. stream-json으로 이미지 블록을 직접 넣는 방식은 실측이 필요합니다.
- **BGM 구간 누락**은 하드코딩 자막 OCR이나 업로더 자막으로 복원할 수 있습니다. **영상 끝 환각**은 프레임으로는 못 잡고, whisper 쪽 필터와 자동자막 대조로 대응합니다.
- **효과 측정**: 테스트 영상 3~5개로 고유명사 정답 목록을 만들고, 보정 전후 고유명사 적중률(B-WER 대용)을 비교한 뒤 P2 이후 도입 여부를 결정하세요.

## 출처

- (Tier 1) [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) — `--tools`, `--allowedTools`, `--input-format stream-json`, `--add-dir` — 확인 2026-10-03
- (Tier 1) [Claude Code tools reference — Read 도구 이미지 처리](https://code.claude.com/docs/en/tools-reference) — 확인 2026-10-03
- (Tier 1) [Claude Code headless (-p) 문서](https://code.claude.com/docs/en/headless) — 확인 2026-10-03
- (Tier 1) [Agent SDK Streaming Input (이미지 첨부)](https://code.claude.com/docs/en/agent-sdk/streaming-vs-single-mode) — 확인 2026-10-03
- (Tier 1) [Claude Vision 문서 (토큰 공식, 한도, 제약)](https://platform.claude.com/docs/en/build-with-claude/vision) — 확인 2026-10-03
- (Tier 1) [yt-dlp README (gh api)](https://github.com/yt-dlp/yt-dlp) — `--download-sections`, `--write-subs`, `--write-auto-subs`, `--sub-langs`, `--write-info-json`, `--force-keyframes-at-cuts`
- (Tier 1) [faster-whisper transcribe.py 소스 (gh api)](https://github.com/SYSTRAN/faster-whisper/blob/master/faster_whisper/transcribe.py) — batched 모드의 initial_prompt/hotwords 전달 확인
- (Tier 1) [PaddlePaddle/korean_PP-OCRv5_mobile_rec 모델카드](https://huggingface.co/PaddlePaddle/korean_PP-OCRv5_mobile_rec)
- (Tier 1) [PP-OCRv5 다국어 문서](https://github.com/PaddlePaddle/PaddleOCR/blob/main/docs/version3.x/algorithm/PP-OCRv5/PP-OCRv5_multi_languages.en.md)
- (Tier 1) [Qwen/Qwen3-VL-2B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-2B-Instruct-GGUF), [Qwen3-VL-4B-Instruct-GGUF](https://huggingface.co/Qwen/Qwen3-VL-4B-Instruct-GGUF)
- (Tier 1) [MaLa-ASR: Multimedia-Assisted LLM-Based ASR (arXiv 2406.05839)](https://arxiv.org/html/2406.05839)
- (Tier 1) [Speech Recognition on TV Series with Video-Guided Post-ASR Correction (arXiv 2506.07323)](https://arxiv.org/html/2506.07323v3)
- (Tier 1) [VAPO: Slide-Enhanced Speech Recognition (arXiv 2510.08618)](https://arxiv.org/pdf/2510.08618)
- (Tier 1) [DeRAGEC (ACL Findings 2025)](https://aclanthology.org/2025.findings-acl.786.pdf)
- (Tier 1, 검색 요약 경유) [YouTube Terms of Service](https://www.youtube.com/static?template=terms)
- (Tier 3) [FFmpeg Scene Detection — ffmpeg-cookbook](https://ffmpeg-cookbook.com/en/articles/scene-detect/), [PySceneDetect 문서](https://www.scenedetect.com/docs/0.6.3/api/detectors.html)
- (Tier 4) [Qwen2.5-VL-3B VRAM 논의 (HF discussion)](https://huggingface.co/Qwen/Qwen2.5-VL-3B-Instruct/discussions/20), [Whisper initial_prompt 길이 논의](https://github.com/openai/whisper/discussions/1824), [YouTube 자동자막 vs Whisper 비교 블로그](https://mdisbetter.com/blog/youtube-auto-captions-vs-ai-transcription)

자신감: 사용법·비용·한도는 **확실**(Tier 1 문서). 한국어 효과 크기와 엔진 간 정확도 비교는 **추정**. stream-json 이미지 입력과 `@경로` 첨부 동작은 **모름(실측 필요)**.
