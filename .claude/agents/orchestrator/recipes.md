# Orchestrator Recipes
> orchestrator의 Recipes 정본. 본 파일이 정본이며 orchestrator.md에서는 cross-link로 참조한다.

Common skill composition patterns. These are guidelines, not rigid sequences.
Adapt based on context: skip unnecessary steps, add extra steps, reorder, repeat.

### Recipe Notation

- `→` 순차 실행 (앞 단계 결과가 필요)
- `‖` 병렬 실행 (독립적, 동시 호출)
- `[ ]` 선택적 단계
- `TeamExplore(...)` 에이전트팀 탐색 (navigator ‖ researcher 동시 실행)
- `TeamReview(...)` 에이전트팀 리뷰 (reviewer ‖ security [‖ architect] 동시 실행)

### Feature Implementation

```
Basic:    [Task(navigator) ‖ deepresearch] → [blueprint] → code → test → Task(reviewer) → commit
Simple:   Task(navigator) → code → test → commit
Security: Task(navigator) → code → test → [Task(reviewer) ‖ Task(security)] → commit
Large:    blueprint → Task(architect) → code × N → test → team-review → commit
Team:     TeamExplore(navigator ‖ researcher) → blueprint → code × N → test → TeamReview(reviewer ‖ security [‖ architect]) → commit
```

### Bug Fix

```
Basic:    Task(navigator) → code(diagnose+patch) → test(regression) → Task(reviewer) → commit
Simple:   code(patch) → test → commit
Hard:     [Task(navigator) ‖ deepresearch(similar cases)] → code(diagnose+patch) → test → commit
Security: Task(security, severity) → code(patch) → [Task(security) ‖ Task(reviewer)] → commit
Team-Sec: Task(security, severity) → code(patch) → TeamReview(reviewer ‖ security) → test(regression) → commit
```

### New Project

```
Basic:    [deepresearch ‖ Task(navigator)] → blueprint → Task(architect) →
          code(scaffold) → code(feature 1) → ... → test → qa-swarm → [deploy] → commit
Undecided: decide(tech comparison) → deepresearch → blueprint → ...
Large:    blueprint → agent team parallel dev → team-review → ...
```

### Code Improvement

```
Basic:    Task(navigator, impact scope) → [blueprint] → code → test(regression) → Task(reviewer) → commit
Perf:     [Task(navigator) ‖ deepresearch(optimization)] → code → test(benchmark) → commit
Refactor: Task(navigator) → code → test(full) → Task(architect) → commit
Team:     TeamExplore(navigator ‖ researcher) → blueprint → code → test(full) → TeamReview(reviewer ‖ architect) → commit
```

### Hotfix

```
Basic:    Task(security, severity) → code(minimal patch) →
          [Task(reviewer) ‖ Task(security)] → test(regression) → security-scan → commit
Critical: code(immediate patch) → Task(security) → commit
Team:     Task(security, severity) → code(minimal patch) → TeamReview(reviewer ‖ security) → test(regression) → security-scan → commit
```

### Team-based Parallel Patterns

병렬 실행이 구조적으로 보장되어야 하는 패턴에서는 에이전트팀(TeamCreate)을 사용한다.
단순 `Task()` 병렬 호출과 달리, 팀은 런타임 수준에서 동시 실행을 강제한다.

#### 패턴 1: 팀 리뷰 (Review Phase)

코드 변경 후 리뷰 단계에서 reviewer, security, architect를 팀으로 동시 수행:

```
# 3+ 파일 변경 또는 보안 민감 코드
TeamCreate("review-team")
TaskCreate({subject: "코드 품질 리뷰", owner: "reviewer-agent"})
TaskCreate({subject: "보안 리뷰", owner: "security-agent"})
TaskCreate({subject: "아키텍처 리뷰", owner: "architect-agent"})  # 구조 변경 시
# → 3개 에이전트가 동시에 리뷰 수행
# → 모든 리뷰 완료 후 결과 종합
TeamDelete()
```

이 패턴을 적용하는 기준:
- 3+ 파일 변경 AND (보안 민감 OR 구조 변경) → 팀 리뷰 사용
- 1-2 파일, 비보안 → 기존 단일 Task(reviewer)로 충분

#### 패턴 2: 팀 탐색 (Exploration Phase)

복잡한 기능 구현 전 탐색과 리서치를 팀으로 동시 수행:

```
# 복잡한 기능 (5+ 파일 예상) 또는 새 기술 도입
TeamCreate("explore-team")
TaskCreate({subject: "코드베이스 구조 및 영향 범위 탐색", owner: "navigator-agent"})
TaskCreate({subject: "관련 기술/패턴 심층 조사", owner: "researcher-agent"})
# → 탐색과 리서치가 동시에 진행
# → 두 결과를 합쳐서 blueprint 또는 code 단계로 진행
TeamDelete()
```

이 패턴을 적용하는 기준:
- 5+ 파일 예상 AND 새 기술/패턴 필요 → 팀 탐색 사용
- 단순 탐색만 필요 → Task(navigator) 단독으로 충분

#### 패턴 3: 레시피 통합 예시

Feature Implementation (Large + Security):
```
TeamCreate("explore-team")     ← 탐색 팀
  navigator + researcher 병렬
TeamDelete()
  → blueprint → Task(architect)
  → code × N → test
TeamCreate("review-team")      ← 리뷰 팀
  reviewer + security + architect 병렬
TeamDelete()
  → commit
```

### Harness Maintenance

```
Basic:    code(harness file change) → sync-docs → commit
Scaffold: scaffold(new skill/agent) → sync-docs → commit
Check:    sync-docs(--check-only) → [code(fix docs)] → commit
```
