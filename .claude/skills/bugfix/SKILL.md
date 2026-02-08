---
name: bugfix
description: |
  Workflow for diagnosing and fixing bugs with verification.
  Navigates to bug source, patches, reviews, and runs regression tests.
  Triggers on: "버그 고쳐", "bugfix", "이거 왜 안 돼", or any request
  to fix a bug, resolve an error, or debug unexpected behavior.
argument-hint: "<버그 설명 또는 에러 메시지>"
user-invocable: true
context: fork
allowed-tools: Task, Skill, Read, Write, Glob, Grep, Bash
---

# Bugfix Workflow

## 트리거 조건

버그를 진단하고 수정할 때 사용한다.
보안 취약점이나 긴급 이슈는 /hotfix, 기능 개선은 /improve를 사용한다.

## DO/REVIEW 시퀀스

### Phase 1: 진단 + 수정

/fix 스킬이 navigator 호출, 원인 진단, 패치를 모두 수행한다:

```
DO: Skill("fix", "$ARGUMENTS")
```

/fix 결과에서 확인:
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

회귀 테스트를 실행하여 수정이 다른 기능을 깨뜨리지 않았는지 확인한다:

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
