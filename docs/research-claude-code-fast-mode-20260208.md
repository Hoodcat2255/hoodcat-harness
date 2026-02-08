# Claude Code Fast Mode 조사 결과

> 조사일: 2026-02-08

## 개요

Claude Code Fast Mode는 2026년 2월 5일 Claude Opus 4.6 출시와 함께 도입된 기능으로, 동일한 Opus 4.6 모델을 더 빠른 추론 구성으로 실행하여 최대 2.5배 빠른 출력 토큰 생성 속도를 제공한다. 별도의 모델이 아니라 동일한 모델의 속도 우선 구성이므로 지능이나 기능의 차이는 없다. 현재 Research Preview 상태이며, 2026년 2월 16일까지 50% 할인이 적용된다.

## 상세 내용

### 사용 방법

#### Claude Code CLI/VS Code에서 사용

1. **슬래시 명령어**: `/fast`를 입력하고 Tab을 눌러 토글 (켜기/끄기)
2. **설정 파일**: 사용자 설정 파일에 `"fastMode": true` 추가
3. Fast mode는 세션 간에 유지됨 (한번 켜면 끌 때까지 유지)

#### 활성화 시 동작

- 다른 모델을 사용 중이면 자동으로 Opus 4.6으로 전환
- "Fast mode ON" 확인 메시지 표시
- 프롬프트 옆에 `↯` 아이콘 표시
- `/fast`를 다시 실행하면 현재 상태 확인 가능

#### 비활성화 시 주의사항

- `/fast`를 다시 실행하면 비활성화
- 비활성화해도 Opus 4.6에 머무름 (이전 모델로 자동 복귀하지 않음)
- 다른 모델로 전환하려면 `/model` 명령어 사용

#### API에서 사용

```python
import anthropic

client = anthropic.Anthropic()

response = client.beta.messages.create(
    model="claude-opus-4-6",
    max_tokens=4096,
    speed="fast",
    betas=["fast-mode-2026-02-01"],
    messages=[{
        "role": "user",
        "content": "Refactor this module to use dependency injection"
    }]
)
```

API 요청 시 `speed: "fast"` 파라미터와 `betas: ["fast-mode-2026-02-01"]` 헤더를 추가한다.

### 가격

| 모드 | Input (MTok) | Output (MTok) |
|------|-------------|---------------|
| 표준 Opus 4.6 | $5 | $25 |
| Fast mode (<=200K) | $30 | $150 |
| Fast mode (>200K) | $60 | $225 |

- 표준 대비 6배 가격 (<=200K 기준)
- 200K 초과 시 12배 가격
- 프롬프트 캐싱, 데이터 레지던시 멀티플라이어가 추가 적용됨
- **2026년 2월 16일까지 모든 플랜에서 50% 할인**

### 사용 조건

1. **구독 플랜 필요**: Pro/Max/Team/Enterprise 플랜 사용자
2. **Extra Usage 활성화 필수**: 추가 사용량 과금이 활성화되어야 함
3. **Teams/Enterprise**: 관리자가 먼저 Fast mode를 활성화해야 함
4. **서드파티 클라우드 미지원**: Amazon Bedrock, Google Vertex AI, Microsoft Azure Foundry에서는 사용 불가
5. **Batch API 미지원**: Batch API에서는 사용 불가
6. **Priority Tier 미지원**

### Fast Mode vs Effort Level

| 설정 | 효과 |
|------|------|
| **Fast mode** | 동일한 모델 품질, 낮은 지연시간, 높은 비용 |
| **Lower effort level** | 적은 사고 시간, 빠른 응답, 복잡한 작업에서 품질 저하 가능 |

두 가지를 조합 가능: 단순한 작업에서 fast mode + 낮은 effort level로 최대 속도 달성

### Rate Limit 처리

- Fast mode는 표준 Opus 4.6과 별도의 rate limit 사용
- Rate limit 초과 시:
  1. 자동으로 표준 Opus 4.6으로 폴백
  2. `↯` 아이콘이 회색으로 변경 (쿨다운 표시)
  3. 표준 속도와 가격으로 계속 작업
  4. 쿨다운 만료 시 자동으로 fast mode 재활성화

### 주의사항 및 제한사항

1. **프롬프트 캐시 무효화**: fast와 standard 간 전환 시 프롬프트 캐시가 무효화됨. 서로 다른 속도의 요청은 캐시된 프리픽스를 공유하지 않음
2. **비용 최적화**: 세션 시작 시 fast mode를 활성화하는 것이 중간에 전환하는 것보다 비용 효율적
3. **TTFT 개선 없음**: 속도 이점은 출력 토큰/초(OTPS)에 집중. 첫 토큰까지의 시간(TTFT)은 개선되지 않음
4. **Opus 4.6 전용**: 현재 Opus 4.6에서만 지원. 미지원 모델에서 사용 시 에러 반환
5. **Research Preview**: 기능, 가격, 가용성이 피드백에 따라 변경될 수 있음

## 코드 예제

### API에서 Fast Mode + 표준 폴백 패턴 (Python)

```python
import anthropic

client = anthropic.Anthropic()

def create_message_with_fast_fallback(max_retries=None, max_attempts=3, **params):
    try:
        return client.beta.messages.create(**params, max_retries=max_retries)
    except anthropic.RateLimitError:
        if params.get("speed") == "fast":
            del params["speed"]
            return create_message_with_fast_fallback(**params)
        raise
    except (anthropic.InternalServerError, anthropic.OverloadedError, anthropic.APIConnectionError):
        if max_attempts > 1:
            return create_message_with_fast_fallback(max_attempts=max_attempts - 1, **params)
        raise

message = create_message_with_fast_fallback(
    model="claude-opus-4-6",
    max_tokens=1024,
    messages=[{"role": "user", "content": "Hello"}],
    betas=["fast-mode-2026-02-01"],
    speed="fast",
    max_retries=0,
)
```

### 응답에서 사용된 속도 확인

```python
response = client.beta.messages.create(
    model="claude-opus-4-6",
    max_tokens=1024,
    speed="fast",
    betas=["fast-mode-2026-02-01"],
    messages=[{"role": "user", "content": "Hello"}]
)

print(response.usage.speed)  # "fast" or "standard"
```

## 주요 포인트

- Fast mode는 동일한 Opus 4.6 모델을 빠른 추론 구성으로 실행하여 최대 2.5배 빠른 출력 속도를 제공
- Claude Code에서 `/fast` 명령어로 간편하게 토글 가능
- 표준 대비 6배(<=200K) ~ 12배(>200K) 비용이 발생하므로 인터랙티브 작업에 선택적 사용 권장
- 세션 시작 시 활성화하는 것이 중간 전환보다 비용 효율적 (캐시 무효화 방지)
- Extra Usage 활성화가 필수이며, 구독 플랜의 기본 사용량에 포함되지 않음

## 출처

- [Speed up responses with fast mode - Claude Code Docs](https://code.claude.com/docs/en/fast-mode)
- [Fast mode (research preview) - Claude API Docs](https://platform.claude.com/docs/en/build-with-claude/fast-mode)
- [Introducing Claude Opus 4.6 - Anthropic](https://www.anthropic.com/news/claude-opus-4-6)
- [Fast mode for Claude Opus 4.6 - GitHub Copilot Changelog](https://github.blog/changelog/2026-02-07-claude-opus-4-6-fast-is-now-in-public-preview-for-github-copilot/)
- [Claude Code Fast Mode Waitlist](https://claude.com/fast-mode)
