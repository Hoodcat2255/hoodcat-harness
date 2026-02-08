---
name: plan
description: |
  Creates project plans with requirements, architecture design, and task breakdown.
  Use when the user wants to plan a new feature, project, or significant change.
  Triggers on: "계획 세워줘", "설계해줘", "기획해줘", "plan", or any request
  for structured planning of a feature or project.
argument-hint: "<기능 또는 프로젝트 설명>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Glob, Grep, Bash, Task, WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs
---

# Plan Skill

**현재 연도: !`date +%Y`**

## 입력

$ARGUMENTS: 아이디어, 기능 설명, 또는 프로젝트 요구사항

## 프로세스

### 1. 코드베이스 탐색

navigator 에이전트를 Task로 호출하여 기존 코드 구조를 파악한다:

```
Task(navigator): "$ARGUMENTS와 관련된 기존 코드를 탐색하라"
```

프로젝트가 비어있으면(신규) 이 단계를 건너뛴다.

### 2. 요구사항 정리

기능 요구사항과 비기능 요구사항을 분리하여 정리한다:

- **기능 요구사항**: 시스템이 무엇을 해야 하는가?
- **비기능 요구사항**: 성능, 보안, 확장성, 유지보수성 제약사항

사용자의 입력이 모호하면, 합리적인 가정을 세우고 명시적으로 기록한다.

### 3. 기술 스택 결정

기존 프로젝트가 있으면 기존 스택을 따른다.
새 기술 선택이 필요하면 근거를 명시한다. 판단이 어려우면:

```
필요시: WebSearch로 기술 비교 조사
```

### 4. 아키텍처 설계

프로젝트 규모에 맞게 설계한다:

- **소규모** (파일 5개 이하): 컴포넌트 목록 + 데이터 흐름
- **중규모** (모듈 2-5개): 모듈 구조 + API 명세 + 데이터 모델
- **대규모** (서비스 2개+): 시스템 구성도 + 서비스 간 통신 + 인프라 구조

### 5. 태스크 분해

구현 가능한 단위로 태스크를 분해한다:

- 각 태스크는 독립적으로 구현/테스트 가능해야 함
- 의존 관계를 명시 (어떤 태스크가 먼저 완료되어야 하는지)
- 예상 복잡도 표시: S(소) / M(중) / L(대)

### 6. 산출물 저장

`docs/plans/{project-name}/` 디렉토리에 저장한다:

```
docs/plans/{project-name}/
├── requirements.md    # 요구사항 정의
├── architecture.md    # 아키텍처 설계
├── api-spec.md        # API 명세 (해당 시)
└── tasks.md           # 구현 태스크 목록
```

## 출력

사용자에게 요약 보고:

```markdown
## 기획 완료: {project-name}

### 요구사항
- 기능 요구사항 N개
- 비기능 요구사항 N개

### 아키텍처
- 패턴: [선택한 패턴]
- 주요 컴포넌트: [목록]

### 태스크
- 총 N개 (S: n개, M: n개, L: n개)
- 구현 순서: [첫 번째 → 두 번째 → ...]

### 산출물 위치
docs/plans/{project-name}/
```

## REVIEW 연동

산출물 생성 후, architect 에이전트에게 리뷰를 요청한다:

```
Task(architect): "docs/plans/{project-name}/architecture.md를 리뷰하라"
```

architect가 BLOCK을 반환하면 해당 부분을 수정하고 재리뷰한다.
