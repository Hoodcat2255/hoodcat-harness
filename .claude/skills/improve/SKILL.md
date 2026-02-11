---
name: improve
description: |
  Workflow for enhancing existing features or code.
  Analyzes impact scope, implements changes, and verifies with regression tests.
  Triggers on: "개선해줘", "업그레이드", "기능 추가", "improve", or any request
  to enhance, extend, or improve existing functionality.
argument-hint: "<개선할 기능 설명>"
user-invocable: true
context: fork
agent: workflow
allowed-tools: Skill, Task, Read, Write, Edit, Glob, Grep, Bash(git *), Bash(npm *), Bash(npx *), Bash(yarn *), Bash(pnpm *), Bash(pytest *), Bash(cargo *), Bash(go *), Bash(make *), Bash(gh *)
---

# Improve Workflow

## 트리거 조건

기존 기능을 개선하거나 확장할 때 사용한다.
완전히 새로운 프로젝트는 /new-project, 버그 수정은 /bugfix를 사용한다.

## DO/REVIEW 시퀀스

### Phase 1: 분석

navigator 에이전트로 영향 범위를 파악한다:

```
DO: Task(navigator): "$ARGUMENTS와 관련된 코드를 탐색하라. 변경 영향 범위를 파악하라."
```

navigator 결과를 바탕으로 변경 규모를 판단한다:

- **큰 변경** (모듈 3개+ 영향, 새 모듈 추가, API 변경): → Phase 1.5 기획
- **작은 변경** (파일 1-2개, 기존 패턴 내 수정): → Phase 2 개발로 직행

### Phase 1.5: 기획 (큰 변경인 경우만)

```
DO: Skill("blueprint", "$ARGUMENTS")
REVIEW: Task(architect): "개선 설계가 기존 아키텍처와 조화로운가?"
```

- PASS/WARN → Phase 2로 진행
- BLOCK → 설계 수정 후 재리뷰

### Phase 2: 개발

```
DO: Skill("implement", "$ARGUMENTS")
REVIEW: Task(reviewer): "변경된 코드의 품질을 리뷰하라. 기존 패턴과의 일관성에 주의."
```

- PASS/WARN → Phase 3로 진행
- BLOCK → 수정 후 재리뷰

### Phase 3: 검증

**검증 규칙**: 빌드/테스트 결과는 실제 명령어의 exit code로만 판단한다. 텍스트 보고("통과했습니다")를 신뢰하지 않는다.

```
DO: Skill("test", "--regression")
```

- 전체 통과 → 완료
- 실패 있음 → 자동 수정 시도:
  ```
  DO: Skill("fix", "<실패 에러>")
  DO: Skill("test", "--regression")
  ```
  재테스트 후에도 실패하면 사용자에게 보고

## 종료 조건

1. 회귀 테스트 전체 통과
2. 사용자가 중단을 요청

## 완료 보고

```markdown
## 개선 완료: $ARGUMENTS

### 변경 규모
[큰 변경 / 작은 변경] - 영향 범위: [모듈 목록]

### 실행된 단계
- [x] 분석: 영향 범위 N개 파일
- [x] 기획: (큰 변경인 경우만)
- [x] 개발: N개 파일 수정
- [x] 검증: 회귀 테스트 N개 통과

### 리뷰 결과
- reviewer: [PASS/WARN 요약]

### 변경된 파일
[목록]
```
