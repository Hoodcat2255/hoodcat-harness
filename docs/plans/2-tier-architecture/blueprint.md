# Blueprint: Planner-Driven 2-tier 아키텍처

## 현재 구조의 문제 (3-tier, 정적)

```
User → Main Agent → Skill("implement")                    [fork: workflow agent]
                         ├─ Phase 1: Task(navigator)        ← 하드코딩된 순서
                         ├─ Phase 2: 코드 작성
                         ├─ Phase 3: 린트
                         ├─ Phase 4: Skill("test")          ← 2중 fork
                         └─ Phase 5: Task(reviewer)
```

1. **경직된 실행**: 워크플로우가 Phase를 하드코딩. 순서 변경, 단계 생략 불가
2. **2중 fork**: workflow → Skill() 호출 시 fork 안에서 또 fork
3. **중복 오케스트레이션**: Main Agent와 workflow 에이전트 모두 오케스트레이터
4. **맥락 단절**: 각 Skill() 호출마다 컨텍스트 리셋

---

## 목표 구조 (2-tier)

```
Tier 1: Main Agent (순수 디스패처)
  │
  ├─ 단순 요청 → 워커 스킬 직접 호출
  │    예: /test, /commit, /deepresearch
  │
  └─ 복합 요청 → Planner에게 위임
       │
       Tier 2: Planner [fork: planner agent]
       │  1. 요구사항 분석
       │  2. 스킬 카탈로그에서 필요한 스킬 선택
       │  3. 실행 계획 생성 (동적 워크플로우)
       │  4. 계획을 이행 (Skill/Task 호출, 결과 판단, 적응)
       │
       ├─ Skill("code", "JWT 미들웨어 구현")          [fork: coder]
       ├─ Skill("test", "auth 모듈 테스트")            [fork: coder]
       ├─ Task(reviewer) + Task(security)              [병렬]
       └─ Skill("commit", "JWT auth 구현")             [fork: committer]
```

### 핵심 원칙

1. **Main Agent = 디스패처**: 요청 성격만 판단. 단순이면 직접 Skill(), 복합이면 Planner에 위임
2. **Planner = 계획 + 이행**: 요구를 분석하고, 스킬을 조합하여 동적 워크플로우를 생성하고, 직접 이행
3. **스킬 = 단일 책임 워커**: 각 스킬은 하나의 일만 잘한다. 다른 스킬을 호출하지 않는다
4. **적응적 실행**: Planner는 각 단계 결과를 보고 다음 행동을 판단 (계획 수정 가능)

### Main Agent의 디스패치 기준

```
사용자 요청 수신
  │
  ├─ 명시적 단일 스킬 호출? (/test, /commit, /deepresearch, /scaffold 등)
  │    → 해당 스킬 직접 호출
  │
  └─ 복합 요청? (구현, 버그 수정, 개선, 프로젝트 생성, 긴급 수정 등)
       → Planner에게 위임: Task(planner, "$USER_REQUEST")
```

---

## Planner 설계

### Planner의 정체

**Planner는 에이전트다.** `.claude/agents/planner.md`로 정의한다.
Main Agent가 `Task(planner, "$USER_REQUEST")`로 호출하면,
fork 컨텍스트에서 계획 수립 → 이행을 자율 실행한다.

기존 `workflow` 에이전트를 대체한다.

### Planner의 역할

Planner는 코드를 직접 쓰지 않는다. 대신:

1. **분석**: 요구의 성격을 파악 (버그? 기능? 리서치? 배포?)
2. **계획**: 스킬 카탈로그에서 스킬을 선택하고 실행 순서를 결정
3. **이행**: Skill()과 Task()를 순차/병렬 호출하여 계획을 실행
4. **판단**: 각 단계 결과를 평가 (진행 / 재시도 / 계획 수정 / 사용자에게 판단 요청)
5. **보고**: 최종 결과를 Main Agent에 반환

### 계획 생성 방식

Planner는 하드코딩된 워크플로우를 따르지 않는다.
**레시피(Recipe)**를 참고하여 요구에 맞게 계획을 조합한다.

레시피는 일반적인 패턴을 제공하지만, Planner는 상황에 따라:
- 단계를 건너뛸 수 있다 (단순한 타이포 수정에 blueprint 불필요)
- 단계를 추가할 수 있다 (보안 민감 코드에 security-scan 추가)
- 순서를 바꿀 수 있다 (기존 테스트 실패 → 코드 작성 전에 먼저 수정)
- 동적으로 반복할 수 있다 (테스트 실패 → code 수정 → 재테스트)

### 적응적 실행

```
정적 워크플로우 (현재):
  Phase 1 → Phase 2 → Phase 3 → Phase 4 → Phase 5
  (실패해도 하드코딩된 재시도 로직만)

적응적 Planner (목표):
  Step 1 결과 분석 →
    양호 → Step 2 진행
    불충분 → 추가 리서치 삽입, 또는 다른 접근법 전환
    예상 밖 발견 → 계획 자체를 수정
```

---

## planner 에이전트 설계

### frontmatter

```yaml
---
name: planner
description: |
  Dynamic workflow planner and executor.
  Analyzes requirements, creates execution plans by composing skills,
  and carries out plans adaptively.
  Called by Main Agent for complex multi-step requests.
  NOT called directly by users.
tools:
  - Skill
  - Task
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Bash(git *)
  - Bash(npm *)
  - Bash(npx *)
  - Bash(yarn *)
  - Bash(pnpm *)
  - Bash(pytest *)
  - Bash(cargo *)
  - Bash(go *)
  - Bash(make *)
  - Bash(gh *)
  - TeamCreate
  - TaskCreate
  - TaskUpdate
  - TaskList
  - SendMessage
  - TeamDelete
model: opus
memory: project
---
```

### 본문 구조

```markdown
# Planner Agent

## Purpose

You are a dynamic workflow planner running inside a forked sub-agent context.
Your job is to analyze requirements, create execution plans by composing
skills from the catalog, and carry out those plans adaptively.

## Skill Catalog

[스킬/에이전트 목록 + 선택 기준 — harness.md에서 @import]

## Planning Rules

[계획 수립 규칙]

## Recipes

[일반적인 스킬 조합 패턴 — 강제 아닌 가이드라인]

## Execution Protocol

[이행 규칙: 적응적 실행, 실패 처리, 병렬 호출, 리뷰 처리]

## Shared Context Protocol / Memory Management

[기존 정형 텍스트]
```

---

## 스킬 카탈로그

Planner가 조합할 수 있는 모든 스킬과 에이전트.

### 리서치 & 기획

| 스킬 | Agent | 용도 | 언제 선택 |
|------|-------|------|----------|
| `deepresearch` | researcher | 주제 심층 조사 | 기술 선택, 패턴 조사, 사전 조사 |
| `blueprint` | researcher | 설계 문서 생성 | 복잡한 기능, 새 프로젝트, 아키텍처 결정 |
| `decide` | researcher | 비교 분석·의사결정 | 기술 스택 선택, 라이브러리 비교 |

### 코딩

| 스킬 | Agent | 용도 | 언제 선택 |
|------|-------|------|----------|
| `code` | coder | 코드 작성·수정·진단·패치 | 모든 코드 변경 |
| `test` | coder | 테스트 작성·실행 | 코드 변경 후 검증 |
| `scaffold` | coder | 스킬/에이전트 생성 | 하네스 확장 시 |

### 운영

| 스킬 | Agent | 용도 | 언제 선택 |
|------|-------|------|----------|
| `commit` | committer | Git 커밋 | 코드 변경 완료 후 |
| `deploy` | coder | 배포 설정 | 프로덕션/스테이징 배포 시 |
| `security-scan` | coder | 보안 스캔 | 배포 전, 보안 민감 변경 시 |

### 리뷰 에이전트 (Task()로 호출)

| Agent | 용도 | 언제 선택 |
|-------|------|----------|
| `navigator` | 코드베이스 탐색 | 코드 변경 전 관련 파일 파악 |
| `reviewer` | 코드 품질 리뷰 | 코드 변경 후 품질 검증 |
| `security` | 보안 리뷰 | 인증/인가, 입력 처리, 보안 민감 코드 |
| `architect` | 아키텍처 리뷰 | 구조 변경, 새 모듈 추가 시 |

### 팀 기반 (대규모 작업용)

| 스킬 | Agent | 용도 | 언제 선택 |
|------|-------|------|----------|
| `team-review` | coder | 멀티렌즈 리뷰 | 대규모/고위험 변경 |
| `qa-swarm` | coder | 병렬 QA | 다양한 테스트 스위트 |

---

## `code` 스킬 (신규)

현재 "코드 작성"은 workflow 에이전트가 직접 수행하거나 fix 스킬을 호출한다.
2-tier에서는 코드 작성이 독립 스킬로 분리된다.

### 역할

- 프로젝트 컨벤션에 따라 코드 작성/수정
- 버그 진단 + 패치 (fix 흡수)
- 린트/포맷 실행
- Planner가 전달한 설계/스펙에 따라 구현

### 기존 스킬과의 관계

- `fix` → `code`에 흡수 (진단+패치는 code의 한 가지 모드)
- `implement`의 Phase 2(코드 작성) → code로 분리
- `test`와는 분리 유지 (테스트는 별도 관심사)

### SKILL.md 설계 방향

```
입력: 작업 지시 (구현 스펙, 버그 설명, 리팩토링 요청 등)
프로세스:
  1. 관련 코드 탐색 (Task(navigator) 또는 직접 Glob/Grep)
  2. 프로젝트 컨벤션 파악 (CLAUDE.md, 기존 코드 패턴)
  3. 코드 작성/수정
  4. 린트/포맷 실행
출력: 변경 파일 목록, 변경 요약
```

---

## 레시피 (Recipe)

Planner가 참고하는 일반적인 스킬 조합 패턴.
가이드라인이지 강제 순서가 아니다. Planner는 상황에 맞게 변형한다.

### 기능 구현

```
기본: Task(navigator) → [deepresearch] → [blueprint] → code → test → Task(reviewer) → commit

변형:
- 단순 기능:    Task(navigator) → code → test → commit
- 보안 민감:    Task(navigator) → code → test → Task(reviewer) + Task(security) → commit
- 대규모:       blueprint → Task(architect) → code × N → test → team-review → commit
```

### 버그 수정

```
기본: Task(navigator) → code(진단+패치) → test(회귀) → Task(reviewer) → commit

변형:
- 단순 버그:    code(패치) → test → commit
- 재현 어려움:  deepresearch(유사 사례) → code(진단+패치) → test → commit
- 보안 버그:    Task(security, 심각도) → code(패치) → Task(security) + Task(reviewer) → commit
```

### 새 프로젝트

```
기본: [deepresearch] → blueprint → Task(architect) →
      code(기초) → code(기능 1) → ... → test → qa-swarm → [deploy] → commit

변형:
- 기술 스택 미정: decide → deepresearch → blueprint → ...
- 대규모:        blueprint → 에이전트팀 병렬 개발 → team-review → ...
```

### 코드 개선

```
기본: Task(navigator, 영향 범위) → [blueprint] → code → test(회귀) → Task(reviewer) → commit

변형:
- 성능 개선:  deepresearch(최적화 패턴) → code → test(벤치마크) → commit
- 리팩토링:   Task(navigator) → code → test(전체) → Task(architect) → commit
```

### 긴급 수정 (Hotfix)

```
기본: Task(security, 심각도) → code(최소 패치) →
      Task(reviewer) + Task(security) [병렬] → test(회귀) → security-scan → commit

변형:
- Critical: code(즉시 패치) → Task(security) → commit  (속도 우선)
```

---

## Planner 지침

### 계획 수립 규칙

1. **최소 단계 원칙**: 필요한 만큼만 스킬 사용. 타이포 수정에 blueprint를 붙이지 않는다
2. **보안 민감 감지**: 인증, 인가, 입력 검증, 암호화 → Task(security) 필수 추가
3. **복잡도 임계값**: 파일 5개+ 변경 → blueprint 선행, 독립 태스크 3개+ → 팀 병렬 고려
4. **실패 시 적응**: 테스트 실패 → code(수정) → 재테스트. 2회 실패 → 사용자에게 판단 요청
5. **리뷰는 마지막**: 코드 변경 완료 후 리뷰. 중간 리뷰는 비효율
6. **커밋 확인**: 자동 commit 금지. 이행 완료 시 사용자에게 커밋 여부 확인

### 스킬 선택 의사결정 트리

```
요구 분석 → 코드 변경이 필요한가?
  ├─ Yes → code 스킬
  │   ├─ 변경 전 탐색 필요? → Task(navigator)
  │   ├─ 기술 조사 필요? → deepresearch
  │   ├─ 설계 필요? → blueprint
  │   ├─ 변경 후 테스트? → test
  │   └─ 변경 후 리뷰? → Task(reviewer) [+ Task(security)]
  │
  ├─ 조사만 필요 → deepresearch / decide
  ├─ 기획만 필요 → blueprint
  ├─ 테스트만 필요 → test
  └─ 배포 필요 → deploy [+ security-scan]
```

### Worktree 관리

Planner는 코드 변경이 포함된 계획을 이행할 때, 첫 번째 code 스킬 호출 전에 worktree를 생성한다.
모든 code/test 스킬 호출에 worktree 경로를 전달한다.
이행 완료 후 worktree를 정리한다.

```
계획 이행 시작
  ├─ 코드 변경 포함? → worktree 생성 (feat/{feature-name})
  ├─ Skill("code", "... (worktree: $WORKTREE_DIR)")
  ├─ Skill("test", "... (worktree: $WORKTREE_DIR)")
  ├─ ...
  └─ 이행 완료 → 사용자에게 병합 안내, worktree 정리
```

---

## 실행 흐름 비교

### Before: "user auth 구현해줘" (3-tier, 정적)

```
User → Main Agent
         └─ Skill("implement", "user auth 구현")      [fork: workflow agent]
              ├─ Phase 1: Task(navigator)               하드코딩된 순서
              ├─ Phase 2: (직접 코드 작성)               workflow가 수행
              ├─ Phase 3: (린트)
              ├─ Phase 4: Skill("test")                 2중 fork
              └─ Phase 5: Task(reviewer)
```

### After: "user auth 구현해줘" (2-tier, 동적)

```
User → Main Agent (디스패처)
         └─ Task(planner, "user auth 구현해줘")        [fork: planner agent]
              │
              │  분석: "인증 기능 → 보안 민감, 설계 필요"
              │  계획: navigator → deepresearch → blueprint →
              │        code × 3 → test → reviewer + security → commit
              │
              ├─ Task(navigator): "auth 관련 기존 코드 탐색"
              │     → "세션 미들웨어 있음, users 테이블 존재"
              │
              ├─ Skill("deepresearch", "Express JWT best practices")
              │     → "JWT + refresh token 패턴 권장"
              │
              │  [판단: 기존 세션 → JWT 전환, 설계 필요]
              │
              ├─ Skill("blueprint", "세션 → JWT 전환 설계")
              │     → tasks.md 생성
              │
              ├─ Skill("code", "태스크 1: JWT 미들웨어")
              ├─ Skill("code", "태스크 2: 로그인/로그아웃")
              ├─ Skill("code", "태스크 3: 세션 마이그레이션")
              │
              ├─ Skill("test", "auth 모듈")
              │     → 2개 실패
              │
              │  [판단: 실패 → 수정 필요]
              │
              ├─ Skill("code", "테스트 실패 원인 수정")
              ├─ Skill("test", "--regression")
              │     → 전체 통과
              │
              ├─ Task(reviewer) + Task(security)  [병렬]
              │     → PASS / WARN
              │
              └─ 사용자에게 결과 보고 + 커밋 여부 확인
```

### Before: "로그인 버그 고쳐" (3-tier, 정적)

```
User → Main Agent
         └─ Skill("bugfix", "로그인 버그")             [fork: workflow]
              ├─ Phase 1: 복잡도 판단
              ├─ Phase 2: Skill("fix")                  2중 fork
              ├─ Phase 3: Task(reviewer)
              └─ Phase 4: Skill("test")                 2중 fork
```

### After: "로그인 버그 고쳐" (2-tier, 동적)

```
User → Main Agent (디스패처)
         └─ Task(planner, "로그인 버그 고쳐")           [fork: planner agent]
              │
              │  분석: "버그 수정"
              │  계획: navigator → code(진단+패치) → test(회귀) → reviewer
              │
              ├─ Task(navigator): "로그인 관련 코드"
              │     → "auth.js:45 세션 체크 로직"
              │
              ├─ Skill("code", "auth.js:45 진단 후 수정")
              │     → "null 체크 누락, 패치 완료"
              │
              ├─ Skill("test", "auth 회귀 테스트")
              │     → 전체 통과
              │
              │  [판단: 단순 버그, 리뷰 가볍게]
              │
              ├─ Task(reviewer): "auth.js 패치 리뷰"
              │     → PASS
              │
              └─ 사용자에게 보고 + 커밋 여부 확인
```

---

## 삭제 대상

### 스킬 (6개 삭제)

| 스킬 | 이유 |
|------|------|
| `implement` | Planner가 code + test + review를 동적 조합 |
| `bugfix` | Planner가 code(진단+패치) + test + review를 동적 조합 |
| `hotfix` | Planner가 security + code + review를 동적 조합 |
| `improve` | Planner가 navigator + code + test + review를 동적 조합 |
| `new-project` | Planner가 blueprint + code + test + deploy를 동적 조합 |
| `fix` | code 스킬에 흡수 |

### 에이전트 (1개 삭제 → 1개 신규 = 총 8개 유지)

| 변경 | 에이전트 | 이유 |
|------|---------|------|
| **삭제** | `workflow` | Planner가 대체 |
| **신규** | `planner` | 동적 워크플로우 계획 + 이행 |

---

## 최종 구조

### 스킬 (15개 → 10개)

```
워커 스킬 (모든 스킬: context: fork, Skill() 호출 금지)
├── code          (coder)      ← 신규: 코드 작성·수정·진단·패치
├── test          (coder)
├── blueprint     (researcher)
├── commit        (committer)
├── deploy        (coder)
├── security-scan (coder)
├── deepresearch  (researcher)
├── decide        (researcher)
├── scaffold      (coder)
├── team-review   (coder)      ← agent 변경
└── qa-swarm      (coder)      ← agent 변경
```

### 에이전트 (8개 → 8개)

```
오케스트레이션
└── planner     — 동적 계획 + 이행 (Skill + Task + 팀 도구)  ← 신규, workflow 대체

실행 에이전트
├── coder       — 코드 작성 + 빌드/테스트
├── committer   — Git 커밋 (최소 권한, sonnet)
└── researcher  — 웹 검색 + 문서 작성

리뷰/탐색 에이전트
├── reviewer    — 코드 품질
├── security    — 보안
├── architect   — 아키텍처
└── navigator   — 코드베이스 탐색
```

---

## Planner vs Workflow 비교

| | workflow (현재) | planner (목표) |
|---|---|---|
| **인스턴스** | 스킬당 1개 (implement, bugfix...) | 1개 (모든 복합 요청 처리) |
| **실행 순서** | SKILL.md에 하드코딩 | 런타임에 동적 생성 |
| **실패 대응** | "최대 2회 재시도" 고정 | 계획 자체를 수정 가능 |
| **스킬 호출** | Skill() + Task() 혼용 | 동일 (변경 없음) |
| **판단 주체** | SKILL.md 규칙 | Planner 에이전트 자체 판단 |
| **워커 호출** | Skill("fix") 등 2중 fork | Skill("code") 등 (동일 depth) |
| **스킬 카탈로그** | 없음 (각 워크플로우가 사용할 스킬을 알고 있음) | 명시적 카탈로그 참조 |

---

## 트레이드오프

### 장점

1. **유연성**: 동적 워크플로우 생성, 하드코딩 순서 탈피
2. **적응적 실행**: 단계 결과에 따라 계획 수정, 불필요한 단계 생략
3. **스킬 수 감소**: 15개 → 10개, 관리 포인트 축소
4. **단일 진입점**: 5개 워크플로우 대신 1개 Planner
5. **Planner 컨텍스트 연속**: 전체 흐름을 보고 있으므로 단계 간 정보 전달 자연스러움

### 단점

1. **Planner 토큰 소비**: 계획 수립 + 결과 판단에 토큰 사용 (워크플로우보다 약간 증가)
2. **일관성 리스크**: 매번 판단하므로 같은 요청에 다른 계획이 나올 수 있음
3. **Planner 컨텍스트 소모**: 다단계 실행 시 Planner fork의 컨텍스트 윈도우 소진

### 완화 방안

| 단점 | 완화 |
|------|------|
| 토큰 소비 | 레시피가 판단 포인트 최소화 |
| 일관성 | 레시피가 기본 패턴 역할 + exit code 검증 |
| 컨텍스트 소모 | 각 Skill 결과를 요약으로 수신, 상세는 Shared Context 기록 |

---

## 마이그레이션 순서

### Phase 1: 신규 생성

1. `.claude/agents/planner.md` — Planner 에이전트 (스킬 카탈로그, 레시피, 실행 규칙 포함)
2. `.claude/skills/code/SKILL.md` — 코드 작성/수정 통합 스킬

### Phase 2: 에이전트 정리

3. `.claude/agents/workflow.md` 삭제
4. `.claude/agents/coder.md` — 팀 도구는 추가하지 않음 (planner가 팀 도구 소유)

### Phase 3: 워크플로우 스킬 삭제

5. `.claude/skills/implement/` 삭제
6. `.claude/skills/bugfix/` 삭제
7. `.claude/skills/hotfix/` 삭제
8. `.claude/skills/improve/` 삭제
9. `.claude/skills/new-project/` 삭제
10. `.claude/skills/fix/` 삭제

### Phase 4: 팀 스킬 전환

11. `.claude/skills/team-review/SKILL.md` — agent: workflow → coder
12. `.claude/skills/qa-swarm/SKILL.md` — agent: workflow → coder

### Phase 5: 문서 재작성

13. `.claude/harness.md` 재작성 — 2-tier 아키텍처, 디스패치 기준
14. `CLAUDE.md` 업데이트 — 스킬 목록, Planner 설명
15. `shared-context-config.json` — planner 필터 추가, workflow 제거

### Phase 6: 검증 및 정리

16. 시나리오별 검증 (기능 구현, 버그 수정, 리서치)
17. MEMORY.md 업데이트

---

## 변경 파일 요약

| 동작 | 파일 | 설명 |
|------|------|------|
| **신규** | `.claude/agents/planner.md` | Planner 에이전트 (~150줄) |
| **신규** | `.claude/skills/code/SKILL.md` | 코드 작성/수정 통합 스킬 (~100줄) |
| **삭제** | `.claude/agents/workflow.md` | Planner가 대체 |
| **삭제** | `.claude/skills/implement/` | Planner가 동적 조합 |
| **삭제** | `.claude/skills/bugfix/` | Planner가 동적 조합 |
| **삭제** | `.claude/skills/hotfix/` | Planner가 동적 조합 |
| **삭제** | `.claude/skills/improve/` | Planner가 동적 조합 |
| **삭제** | `.claude/skills/new-project/` | Planner가 동적 조합 |
| **삭제** | `.claude/skills/fix/` | code에 흡수 |
| **수정** | `.claude/skills/team-review/SKILL.md` | agent: workflow → coder |
| **수정** | `.claude/skills/qa-swarm/SKILL.md` | agent: workflow → coder |
| **수정** | `.claude/shared-context-config.json` | planner 추가, workflow 제거 |
| **재작성** | `.claude/harness.md` | 2-tier + 디스패치 기준 |
| **수정** | `CLAUDE.md` | 스킬/에이전트 목록 갱신 |
