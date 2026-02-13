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
agent: coder
---

# QA Swarm Skill

## 개요

에이전트팀을 활용하여 여러 유형의 QA를 병렬로 동시 실행한다.
각 QA 영역의 전문 팀원이 동시에 작업하여 전체 QA 소요 시간을 단축한다.

## 적용 기준

- **사용**: 대규모 프로젝트 (테스트 스위트가 다양), 새 프로젝트의 QA 단계, 릴리즈 전 종합 검증
- **미사용**: 단위 테스트만 있는 소규모 프로젝트 → 기존 /test 스킬 사용

## 프로세스

### 1. 프로젝트 분석

$ARGUMENTS에서 프로젝트 경로/대상을 파악한다.
프로젝트 루트의 설정 파일(package.json, Cargo.toml, pyproject.toml, go.mod, Makefile 등)을 읽어 사용 가능한 테스트/린트/빌드/감사 도구를 감지한다.

### 2. QA팀 생성 및 태스크 동적 배정

```
TeamCreate("qa-team")
```

감지된 도구에 따라 아래 4개 카테고리 중 해당하는 것만 태스크로 생성한다:

| 카테고리 | 팀원 이름 | 역할 |
|---------|----------|------|
| 단위/통합 테스트 | qa-tester | 테스트 프레임워크 감지 → 전체 테스트 실행 → 실패 시 에러/스택 트레이스 보고 |
| 린트/정적 분석 | qa-linter | 프로젝트 린터 전체 실행 → 자동 수정 적용 → 수동 수정 항목 보고 |
| 빌드 검증 | qa-builder | 빌드 명령 실행 → 컴파일/타입 에러, 경고 보고 |
| 보안 스캔 | qa-security | 패키지 매니저 감사 도구 실행 → 취약점 심각도별 분류 보고 |

각 카테고리에 대해 동일 패턴으로 태스크 생성 및 팀원 스폰:

```
# 감지된 각 카테고리에 대해 반복:
TaskCreate({
  subject: "<카테고리명>",
  description: "<위 표의 역할 설명>",
  activeForm: "<카테고리명> 실행 중"
})

Task(team_name="qa-team", name="<팀원 이름>"):
  "<카테고리명>을 실행하세요. 프로젝트 경로: [경로].
   결과는 실제 명령어의 exit code로 판단하세요.
   완료 후 TaskUpdate로 결과를 보고하세요."
```

### 3. 결과 종합

모든 태스크가 completed 상태가 되면:

1. 각 팀원의 결과를 수집
2. 실패 항목을 심각도별로 분류
3. 자동 수정이 적용된 항목 정리
4. 수동 수정이 필요한 항목 목록 생성

### 4. 정리

```
SendMessage(type="shutdown_request")로 모든 팀원 종료
TeamDelete()
```

## 검증 규칙

빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다.
텍스트 보고("통과했습니다")를 신뢰하지 않는다.
TaskCompleted 훅(task-quality-gate.sh)이 구현 태스크의 빌드/테스트를 자동 검증한다.

## 출력

@output-template.md 참조

## Orchestrator 통합

Orchestrator가 새 프로젝트 또는 대규모 변경의 QA 단계에서 qa-swarm을 선택할 수 있다:
- 테스트 스위트가 다양한 프로젝트 → `Skill("qa-swarm", "<프로젝트 경로>")`
- 단순 프로젝트 → `Skill("test", "<전체 또는 변경된 모듈>")`

## 비용 주의

최대 4개의 별도 Claude 인스턴스를 스폰하므로, 단일 테스트 대비 최대 4배의 토큰을 사용한다.
테스트 스위트가 하나뿐인 프로젝트에는 기존 /test 스킬을 사용하라.
