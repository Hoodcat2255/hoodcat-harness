---
name: team-review
description: |
  Multi-lens code review using agent teams for thorough, multi-perspective verification.
  Spawns reviewer, security, and architect agents as team members who independently review
  and then exchange findings via SendMessage for deeper coverage.
  Triggers on: "멀티렌즈 리뷰", "팀 리뷰", "team-review", "다관점 리뷰",
  or when a large/high-risk change needs comprehensive review from multiple perspectives.
argument-hint: "<리뷰 대상 파일 또는 변경 설명>"
user-invocable: true
context: fork
allowed-tools: Task, Read, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete
---

# Team Review Skill (Multi-Lens Review)

## 개요

에이전트팀을 활용하여 코드 변경을 3가지 관점(코드 품질, 보안, 아키텍처)에서 동시에 리뷰한다.
단일 리뷰어는 한 유형의 이슈에 집중하는 경향이 있으므로, 독립 리뷰어들이 자신의 전문 영역을 깊이 있게 검토한 후 상호 피드백을 교환하여 누락을 최소화한다.

## 적용 기준

- **사용**: 대규모 변경 (파일 5개+), 고위험 코드 (인증, 결제, 데이터 처리), 아키텍처 변경
- **미사용**: 단순 변경 (파일 1-2개, 기존 패턴 내 수정) → 기존 서브에이전트 리뷰 사용

## 프로세스

### 1. 리뷰 대상 파악

$ARGUMENTS에서 리뷰 대상 파일/변경 범위를 파악한다.
명시적 파일 목록이 없으면 `git diff --name-only` 또는 변경 설명에서 추론한다.

### 2. 리뷰팀 생성

```
TeamCreate("review-team")
```

### 3. 리뷰 태스크 생성

```
TaskCreate({
  subject: "코드 품질 리뷰",
  description: "변경된 파일들의 코드 품질을 리뷰하라. 가독성, 유지보수성, 패턴 일관성, 테스트 커버리지에 집중. 리뷰 완료 후 다른 리뷰어에게 SendMessage로 주요 발견을 공유하라.",
  activeForm: "코드 품질 리뷰 중"
})

TaskCreate({
  subject: "보안 리뷰",
  description: "변경된 파일들의 보안을 리뷰하라. OWASP Top 10, 인증/인가, 입력 검증, 의존성 취약점에 집중. 리뷰 완료 후 다른 리뷰어에게 SendMessage로 주요 발견을 공유하라.",
  activeForm: "보안 리뷰 중"
})

TaskCreate({
  subject: "아키텍처 리뷰",
  description: "변경된 파일들의 구조적 적합성을 리뷰하라. 모듈 경계, 의존성 방향, 확장성, 결합도에 집중. 리뷰 완료 후 다른 리뷰어에게 SendMessage로 주요 발견을 공유하라.",
  activeForm: "아키텍처 리뷰 중"
})
```

### 4. 리뷰어 스폰

3명의 리뷰어를 팀원으로 스폰한다:

```
Task(team_name="review-team", name="quality-reviewer"):
  "당신은 코드 품질 리뷰어입니다. 다음 파일들을 리뷰하세요: [대상 파일 목록].
   가독성, 유지보수성, 패턴 일관성, 테스트 커버리지에 집중하세요.
   리뷰 완료 후:
   1. TaskUpdate로 태스크를 completed 처리하세요.
   2. SendMessage로 security-reviewer와 arch-reviewer에게 주요 발견을 공유하세요.
   3. 다른 리뷰어의 메시지를 받으면 보충 의견을 제시하세요."

Task(team_name="review-team", name="security-reviewer"):
  "당신은 보안 리뷰어입니다. 다음 파일들을 리뷰하세요: [대상 파일 목록].
   OWASP Top 10, 인증/인가, 입력 검증, 의존성 취약점에 집중하세요.
   리뷰 완료 후:
   1. TaskUpdate로 태스크를 completed 처리하세요.
   2. SendMessage로 quality-reviewer와 arch-reviewer에게 주요 발견을 공유하세요.
   3. 다른 리뷰어의 메시지를 받으면 보충 의견을 제시하세요."

Task(team_name="review-team", name="arch-reviewer"):
  "당신은 아키텍처 리뷰어입니다. 다음 파일들을 리뷰하세요: [대상 파일 목록].
   모듈 경계, 의존성 방향, 확장성, 결합도에 집중하세요.
   리뷰 완료 후:
   1. TaskUpdate로 태스크를 completed 처리하세요.
   2. SendMessage로 quality-reviewer와 security-reviewer에게 주요 발견을 공유하세요.
   3. 다른 리뷰어의 메시지를 받으면 보충 의견을 제시하세요."
```

### 5. 모니터링 및 종합

리드는 TaskList로 진행 상황을 주기적으로 확인한다.
3개 태스크가 모두 completed 상태가 되면:

1. 각 리뷰어의 결과를 수집
2. 리뷰어 간 교환된 보충 의견도 포함
3. 최종 verdict를 종합

### 6. 정리

```
SendMessage(type="shutdown_request", recipient="quality-reviewer")
SendMessage(type="shutdown_request", recipient="security-reviewer")
SendMessage(type="shutdown_request", recipient="arch-reviewer")
TeamDelete()
```

## 출력

```markdown
## 멀티렌즈 리뷰 완료

### 최종 Verdict: [PASS / WARN / BLOCK]

### 코드 품질 리뷰 (quality-reviewer)
**Verdict**: [PASS/WARN/BLOCK]
[주요 발견 요약]

### 보안 리뷰 (security-reviewer)
**Verdict**: [PASS/WARN/BLOCK]
[주요 발견 요약]

### 아키텍처 리뷰 (arch-reviewer)
**Verdict**: [PASS/WARN/BLOCK]
[주요 발견 요약]

### 교차 의견
- [리뷰어 간 상호 피드백에서 나온 추가 발견]

### 리뷰 대상 파일
[파일 목록]
```

## 비용 주의

이 스킬은 3개의 별도 Claude 인스턴스를 스폰하므로, 단일 리뷰 대비 약 3배의 토큰을 사용한다.
단순 변경에는 기존 서브에이전트 방식의 리뷰를 사용하라.
