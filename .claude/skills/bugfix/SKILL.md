---
name: bugfix
description: |
  Workflow for diagnosing and fixing bugs with verification.
  Navigates to bug source, patches, reviews, and runs regression tests.
  Triggers on: "고쳐줘", "버그 고쳐", "버그 수정", "에러 해결", "bugfix",
  "이거 왜 안 돼", "fix", or any request to fix a bug, resolve an error,
  or debug unexpected behavior.
argument-hint: "<버그 설명 또는 에러 메시지>"
user-invocable: true
context: fork
agent: workflow
---

# Bugfix Workflow

## 트리거 조건

버그를 진단하고 수정할 때 사용한다.
보안 취약점이나 긴급 이슈는 /hotfix, 기능 개선은 /improve를 사용한다.

## DO/REVIEW 시퀀스

### Phase 1: 진단 + 수정

먼저 버그 복잡도를 판단한다:

**단순 버그** (다음 중 하나라도 해당):
- 에러 메시지에 파일 경로/라인이 명시됨
- 단일 파일의 명확한 로직 오류
- 재현 방법이 명확함

→ 기존 /fix 서브에이전트로 진행:

```
DO: Skill("fix", "$ARGUMENTS")
```

**복잡 버그** (다음 중 2개 이상 해당):
- 재현이 어렵거나 간헐적
- 원인이 불명확 (에러 메시지만으로 위치 특정 불가)
- 다중 모듈에 걸친 상호작용 문제
- 여러 가능한 원인이 존재

→ 에이전트팀 기반 경쟁 가설 디버깅:

```
1. TeamCreate("debug-team")

2. navigator로 관련 코드 범위 파악:
   Task(navigator): "$ARGUMENTS와 관련된 코드를 탐색하라"

3. navigator 결과를 바탕으로 3개의 경쟁 가설 수립
   각 가설별 TaskCreate:
   TaskCreate({
     subject: "가설 1: [가설 제목]",
     description: "가설: [가설 설명]. 조사할 영역: [파일/모듈]. 이 가설이 맞다면 [예상 증거]. 틀리다면 [반증 조건].",
     activeForm: "가설 1 조사 중"
   })

4. 각 가설별 디버거 스폰 (최대 3명):
   Task(team_name="debug-team", name="debugger-N"):
     "당신은 디버거입니다. 가설 N을 조사하세요: [가설 설명].
      조사 방법: 관련 코드를 읽고, 로그를 분석하고, 테스트를 실행하세요.
      다른 디버거의 가설에 대한 반증을 찾으면 SendMessage로 공유하세요.
      조사 완료 후 TaskUpdate로 결과(확증/반증)를 보고하세요."

5. 리드가 결과 종합:
   - 확증된 가설의 디버거가 수정 구현
   - 모든 가설이 반증되면 새 가설 수립 후 반복
   - SendMessage(type="shutdown_request")로 팀원 종료
   - TeamDelete로 정리
```

/fix (또는 경쟁 가설 디버깅) 결과에서 확인:
- 근본 원인이 특정되었는가
- 패치가 적용되었는가
- 회귀 테스트가 작성되었는가

### Phase 2: 리뷰

수정된 코드의 품질을 검증한다:

```
REVIEW: Task(reviewer): "/fix가 수정한 코드를 리뷰하라. 수정이 적절한가? 원인: [/fix가 보고한 근본 원인]"
```

- PASS/WARN → Phase 3로 진행
- BLOCK → 수정 후 재리뷰 (최대 2회)

### Phase 3: 검증

회귀 테스트를 실행하여 수정이 다른 기능을 깨뜨리지 않았는지 확인한다.
**검증 규칙**: 빌드/테스트 결과는 실제 명령어의 exit code로만 판단한다. 텍스트 보고("통과했습니다")를 신뢰하지 않는다.

```
DO: Skill("test", "--regression")
```

- 전체 통과 → 완료
- 실패 있음 → 자동 수정 시도:
  ```
  DO: Skill("fix", "<새로 실패한 테스트 에러>")
  DO: Skill("test", "--regression")
  ```
  재테스트 후에도 실패하면 사용자에게 보고

## 종료 조건

1. 버그 수정 + 리뷰 통과 + 회귀 테스트 통과
2. 사용자가 중단을 요청

## 완료 보고

```markdown
## 버그 수정 완료

### 원인
[근본 원인 요약]

### 수정
- `path/to/file.ext:line` - [수정 내용]

### 리뷰 결과
- reviewer: [PASS/WARN 요약]

### 검증
- 회귀 테스트: N개 통과
- 새 테스트: [추가된 테스트 설명]
```
