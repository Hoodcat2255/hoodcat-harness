---
name: qa-swarm
description: |
  Parallel QA using agent teams for comprehensive multi-type testing.
  Spawns specialized QA agents that simultaneously run different test categories
  (unit, integration, lint, security scan) and consolidate results.
  Triggers on: "QA 스웜", "전체 QA", "qa-swarm", "병렬 테스트", "종합 테스트",
  or when comprehensive multi-category testing is needed for a project.
argument-hint: "<프로젝트 경로 또는 테스트 대상 설명>"
user-invocable: true
context: fork
allowed-tools: Task, Skill, Read, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete
---

# QA Swarm Skill

## 개요

에이전트팀을 활용하여 여러 유형의 QA를 병렬로 동시 실행한다.
단일 에이전트가 순차적으로 테스트 유형을 실행하는 대신, 각 QA 영역의 전문 팀원이 동시에 작업하여 전체 QA 소요 시간을 단축한다.

## 적용 기준

- **사용**: 대규모 프로젝트 (테스트 스위트가 다양), /new-project의 Phase 4(QA), 릴리즈 전 종합 검증
- **미사용**: 단위 테스트만 있는 소규모 프로젝트 → 기존 /test 스킬 사용

## 프로세스

### 1. 프로젝트 분석

$ARGUMENTS에서 프로젝트 경로/대상을 파악한다.
프로젝트 루트의 설정 파일을 읽어 사용 가능한 테스트 유형을 감지한다:

```
감지 대상:
- package.json: scripts.test, scripts.lint, scripts.build
- Cargo.toml: cargo test, cargo clippy
- pyproject.toml/setup.py: pytest, flake8, mypy
- go.mod: go test, go vet
- Makefile: test, lint, build 타겟
```

### 2. QA팀 생성

```
TeamCreate("qa-team")
```

### 3. 감지된 테스트 유형별 태스크 생성

프로젝트에서 감지된 테스트 유형에 따라 동적으로 태스크를 생성한다.
다음은 최대 구성이며, 프로젝트에 해당 도구가 없으면 해당 태스크를 건너뛴다:

```
# 단위/통합 테스트 (거의 항상 존재)
TaskCreate({
  subject: "단위/통합 테스트 실행",
  description: "프로젝트의 테스트 스위트를 실행하라. 테스트 프레임워크를 감지하고 전체 테스트를 실행. 실패한 테스트가 있으면 에러 메시지와 스택 트레이스를 정리하여 보고.",
  activeForm: "테스트 실행 중"
})

# 린트/정적 분석 (있는 경우만)
TaskCreate({
  subject: "린트 및 정적 분석",
  description: "프로젝트의 린터와 정적 분석 도구를 실행하라. ESLint, Prettier, Clippy, Flake8, MyPy 등 프로젝트에 설정된 도구를 모두 실행. 경고와 에러를 분류하여 보고.",
  activeForm: "린트 분석 중"
})

# 빌드 검증 (있는 경우만)
TaskCreate({
  subject: "빌드 검증",
  description: "프로젝트 빌드를 실행하라. 컴파일 에러, 타입 에러, 빌드 경고를 보고.",
  activeForm: "빌드 검증 중"
})

# 보안 스캔 (의존성이 있는 경우)
TaskCreate({
  subject: "보안 의존성 스캔",
  description: "의존성 보안 감사를 실행하라. npm audit, pip audit, cargo audit 등 해당 패키지 매니저의 감사 도구 실행. 취약점 발견 시 심각도와 영향 범위를 보고.",
  activeForm: "보안 스캔 중"
})
```

### 4. QA 팀원 스폰

감지된 태스크 수만큼 팀원을 스폰한다 (최대 4명):

```
Task(team_name="qa-team", name="qa-tester"):
  "단위/통합 테스트를 실행하세요. 프로젝트 경로: [경로].
   테스트 프레임워크를 감지하고, 전체 테스트를 실행하세요.
   결과는 실제 명령어의 exit code로 판단하세요.
   실패가 있으면 에러 메시지를 정리하여 보고하세요.
   완료 후 TaskUpdate로 결과를 보고하세요."

Task(team_name="qa-team", name="qa-linter"):
  "린트 및 정적 분석을 실행하세요. 프로젝트 경로: [경로].
   프로젝트에 설정된 린터를 모두 실행하세요.
   자동 수정 가능한 항목은 수정하고, 수동 수정 필요 항목은 보고하세요.
   완료 후 TaskUpdate로 결과를 보고하세요."

Task(team_name="qa-team", name="qa-builder"):
  "빌드 검증을 실행하세요. 프로젝트 경로: [경로].
   프로젝트의 빌드 명령을 실행하고 결과를 보고하세요.
   완료 후 TaskUpdate로 결과를 보고하세요."

Task(team_name="qa-team", name="qa-security"):
  "보안 의존성 스캔을 실행하세요. 프로젝트 경로: [경로].
   해당 패키지 매니저의 감사 도구를 실행하세요.
   취약점 발견 시 심각도별로 분류하여 보고하세요.
   완료 후 TaskUpdate로 결과를 보고하세요."
```

### 5. 결과 종합

모든 태스크가 completed 상태가 되면:

1. 각 팀원의 결과를 수집
2. 실패 항목을 심각도별로 분류
3. 자동 수정이 적용된 항목 정리
4. 수동 수정이 필요한 항목 목록 생성

### 6. 정리

```
SendMessage(type="shutdown_request")로 모든 팀원 종료
TeamDelete()
```

## 검증 규칙

빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다.
텍스트 보고("통과했습니다")를 신뢰하지 않는다.
TaskCompleted 훅(task-quality-gate.sh)이 구현 태스크의 빌드/테스트를 자동 검증한다.

## 출력

```markdown
## QA 스웜 완료

### 종합 결과: [PASS / FAIL]

### 단위/통합 테스트
- 상태: [PASS/FAIL]
- 실행: N개 테스트
- 통과: N개 / 실패: N개
- 실패 항목: [있는 경우 목록]

### 린트/정적 분석
- 상태: [PASS/FAIL/SKIP]
- 에러: N개 / 경고: N개
- 자동 수정: N개 항목
- 수동 수정 필요: [있는 경우 목록]

### 빌드 검증
- 상태: [PASS/FAIL/SKIP]
- 빌드 에러: [있는 경우 목록]

### 보안 스캔
- 상태: [PASS/WARN/FAIL/SKIP]
- 취약점: Critical N / High N / Medium N / Low N
- 주요 취약점: [있는 경우 목록]

### 수동 수정 필요 항목
[전체 수동 수정 항목 종합 목록]
```

## /new-project 통합

/new-project의 Phase 4(QA)에서 기존 단일 test 스킬 대신 qa-swarm을 호출할 수 있다:

```
Phase 4 (개선안):
  테스트 스위트가 다양한 프로젝트 → DO: Skill("qa-swarm", "<프로젝트 경로>")
  단순 프로젝트 → DO: Skill("test", "<전체 또는 변경된 모듈>")
```

## 비용 주의

최대 4개의 별도 Claude 인스턴스를 스폰하므로, 단일 테스트 대비 최대 4배의 토큰을 사용한다.
테스트 스위트가 하나뿐인 프로젝트에는 기존 /test 스킬을 사용하라.
