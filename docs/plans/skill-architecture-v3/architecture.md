# 스킬 아키텍처 v3: 전체 Fork 전환

> 작성일: 2026-02-12

## 1. 핵심 변경

**현재 (v2)**: 워크플로우 5개(bugfix, hotfix, implement, improve, new-project)는 메인 컨텍스트에서 실행, 워커 10개는 `context: fork`로 서브에이전트에서 실행.

**목표 (v3)**: **모든 스킬이 `context: fork`로 실행**. 메인 에이전트는 순수한 오케스트레이터/디스패처 역할만 수행.

```
[사용자 입력]
     │
     ▼
[메인 에이전트: 오케스트레이터]
     │  - 사용자 의도 파악
     │  - 적절한 스킬 디스패치
     │  - 결과 요약/보고
     │
     ├── Skill("bugfix")      → fork (agent: workflow)
     ├── Skill("implement")   → fork (agent: workflow)
     ├── Skill("blueprint")   → fork (agent: default)
     ├── Skill("test")        → fork (agent: default)
     ├── Skill("fix")         → fork (agent: default)
     ├── Skill("deepresearch")→ fork (agent: general-purpose)
     └── ...
```

## 2. 설계 원칙

### 2.1 메인 에이전트의 역할

메인 에이전트는 다음만 수행한다:
- 사용자 의도 파싱 및 적절한 스킬 선택
- `Skill()` 호출로 디스패치
- 결과를 사용자에게 요약/보고
- 사용자와의 대화형 상호작용 (질문, 확인, 피드백)

메인 에이전트는 다음을 **하지 않는다**:
- Phase별 실행 로직 직접 수행
- Sisyphus 플래그 직접 관리
- 코드 작성/수정 (스킬을 통해서만)

### 2.2 에이전트 계층

```
┌─────────────────────────────────────────┐
│ 레벨 0: 메인 에이전트 (오케스트레이터)      │
│   - 사용자 인터페이스                      │
│   - 스킬 디스패치                          │
└──────────────┬──────────────────────────┘
               │ Skill()
┌──────────────▼──────────────────────────┐
│ 레벨 1: 스킬 서브에이전트                   │
│   - 워크플로우: bugfix, hotfix, implement, │
│     improve, new-project                 │
│   - 워커: fix, test, blueprint, commit,  │
│     deploy, security-scan, deepresearch, │
│     decide, team-review, qa-swarm        │
└──────────────┬──────────────────────────┘
               │ Task() / Skill()
┌──────────────▼──────────────────────────┐
│ 레벨 2: 에이전트 / 중첩 스킬               │
│   - 리뷰: reviewer, security, architect  │
│   - 탐색: navigator                      │
│   - 워커에서 호출된 중첩 스킬              │
└─────────────────────────────────────────┘
```

## 3. 신규 에이전트: workflow

워크플로우 스킬 전용 에이전트를 신규 정의한다.

**파일**: `.claude/agents/workflow.md`

**역할**: 다중 Phase 워크플로우를 서브에이전트 컨텍스트에서 자율적으로 오케스트레이션한다.

**핵심 지침**:
- Skill()로 워커 스킬을 호출
- Task()로 리뷰/탐색 에이전트를 호출
- Phase별 진행/BLOCK 판단
- BLOCK 시 재시도 (최대 2회)
- 팀 기반 작업 시 TeamCreate/SendMessage/TeamDelete 사용

**도구 접근**: Skill, Task, Read, Write, Edit, Glob, Grep, Bash + 팀 도구 (TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete)

**모델**: opus (복잡한 오케스트레이션 판단 필요)

## 4. 스킬별 변경 매트릭스

### 4.1 워크플로우 스킬 (v2: no fork → v3: fork)

| 스킬 | agent | allowed-tools | 변경 요약 |
|------|-------|--------------|----------|
| **bugfix** | workflow | Skill, Task, Read, Write, Edit, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete | `context: fork` 추가, agent 지정 |
| **hotfix** | workflow | Skill, Task, Read, Write, Edit, Glob, Grep, Bash | `context: fork` 추가, agent 지정 |
| **implement** | workflow | Skill, Task, Read, Write, Edit, Glob, Grep, Bash | `context: fork` 추가, agent 지정 |
| **improve** | workflow | Skill, Task, Read, Write, Edit, Glob, Grep, Bash | `context: fork` 추가, agent 지정 |
| **new-project** | workflow | Skill, Task, Read, Write, Edit, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete | `context: fork` 추가, agent 지정 |

### 4.2 기존 워커 스킬 (변경 없음 또는 미미)

| 스킬 | agent | allowed-tools | 변경 |
|------|-------|--------------|------|
| **fix** | (기본) | Read, Write, Edit, Glob, Grep, Bash, Task | 변경 없음 |
| **test** | (기본) | Read, Write, Edit, Glob, Grep, Bash, Task | 변경 없음 |
| **blueprint** | (기본) | Read, Write, Glob, Grep, Bash, Task, WebSearch, WebFetch, Context7 | 변경 없음 |
| **commit** | (기본) | Read, Glob, Grep, Bash | 변경 없음 |
| **deploy** | (기본) | Read, Write, Edit, Glob, Grep, Bash, Task | 변경 없음 |
| **security-scan** | (기본) | Read, Write, Glob, Grep, Bash, Task | 변경 없음 |
| **deepresearch** | general-purpose | WebSearch, WebFetch, Context7, Read, Write, Glob, Grep, Bash | 변경 없음 |
| **decide** | general-purpose | WebSearch, WebFetch, Context7, Read, Write, Glob, Grep, Bash | 변경 없음 |
| **team-review** | (기본) | Task, Read, Glob, Grep, Bash, Team 도구 | 변경 없음 |
| **qa-swarm** | (기본) | Task, Skill, Read, Glob, Grep, Bash, Team 도구 | 변경 없음 |

## 5. Sisyphus 메커니즘 변경

### 5.1 현재 문제

v2에서 Sisyphus는 메인 에이전트의 Stop 이벤트를 차단하여 워크플로우가 끝까지 실행되게 한다. v3에서는 워크플로우가 서브에이전트에서 실행되므로:

- 서브에이전트는 자체 컨텍스트에서 완료까지 실행됨
- Stop Hook이 서브에이전트에게는 적용되지 않음
- Sisyphus의 기존 역할이 불필요해짐

### 5.2 v3 변경: Sisyphus 제거

**근거**: 서브에이전트는 자체 실행 범위 내에서 자율적으로 완료된다. 메인 에이전트는 Skill() 호출의 결과를 기다릴 뿐이므로 Stop 차단이 불필요하다.

**제거 대상**:
- `.claude/hooks/sisyphus-gate.sh` — Stop Hook 제거
- `.claude/flags/sisyphus.json` — 플래그 파일 제거
- 모든 SKILL.md의 Sisyphus Phase 0 / 비활성화 섹션 제거
- 모든 SKILL.md의 `jq '.phase=...'` 명령 제거

**대체**: 워크플로우 스킬 내부에서는 단순 순차 실행으로 대체. Phase 추적이 필요하면 로컬 변수로 관리 (파일 시스템 플래그 불필요).

### 5.3 남겨둘 훅

| 훅 | 상태 | 이유 |
|----|------|------|
| `sisyphus-gate.sh` | **제거** | 서브에이전트에 Stop Hook 불필요 |
| `subagent-monitor.sh` | **유지** | SubagentStop 로깅은 여전히 유용 |
| `verify-build-test.sh` | **유지** | 빌드/테스트 검증 유틸리티는 스킬에서 직접 호출 가능 |
| `task-quality-gate.sh` | **유지** | 에이전트팀 품질 게이트는 팀 스킬에서 여전히 유용 |
| `teammate-idle-check.sh` | **유지** | 팀원 유휴 검사는 팀 스킬에서 여전히 유용 |

## 6. 중첩 Fork 문제 및 대응

### 6.1 문제

워크플로우 스킬이 fork에서 실행되면서 다른 워커 스킬을 Skill()로 호출하면 중첩 fork가 발생한다:

```
메인 → Skill("bugfix")  [fork 1]
            → Skill("fix")  [fork 2]
                → Task(navigator)  [fork 3]
            → Skill("test") [fork 2]
            → Task(reviewer) [fork 2]
```

각 fork는 별도 컨텍스트를 생성하므로 토큰 오버헤드가 증가한다.

### 6.2 수용 가능한 수준

- **최대 깊이 3** (워크플로우 → 워커 → 에이전트): 현재도 이 패턴은 존재
- **병렬 fork**: team-review, qa-swarm에서 이미 다중 fork 사용 중
- **비용 증가**: 워크플로우별 약 1.5~2배 (이전에는 레벨1이 메인 컨텍스트에서 실행)

### 6.3 최적화 옵션 (향후)

필요시 적용 가능한 최적화:
1. **워크플로우 내 직접 실행**: 단순 Phase는 Skill() 대신 워크플로우가 직접 수행 (예: implement가 test 호출 대신 직접 테스트 실행)
2. **경량 워커**: 단순한 워커 스킬에는 haiku 모델 사용
3. **인라인 리뷰**: 단순 리뷰는 Task(reviewer) 대신 워크플로우가 자체 판단

## 7. CLAUDE.md 업데이트

### 7.1 스킬 아키텍처 섹션 재작성

```markdown
## 스킬 아키텍처

모든 스킬은 `context: fork`로 서브에이전트에서 격리 실행된다.
메인 에이전트는 순수한 오케스트레이터로, 사용자 의도를 파악하여 적절한 스킬을 디스패치한다.

### 워크플로우 스킬 (오케스트레이터)
서브에이전트에서 다중 Phase를 자율 실행하며, 워커 스킬과 에이전트를 조율한다.
`agent: workflow` 사용.
- bugfix, hotfix, implement, improve, new-project

### 워커 스킬
단일 책임의 독립 작업을 수행한다.
- fix, test, blueprint, commit, deploy, security-scan,
  deepresearch, decide, team-review, qa-swarm
```

### 7.2 Sisyphus 섹션

현재 Sisyphus 관련 전체 섹션 제거. 다음으로 대체:

```markdown
## 스킬 실행 모델

모든 스킬은 `context: fork`로 서브에이전트에서 실행된다.
서브에이전트는 자체 컨텍스트에서 완료까지 자율 실행되므로,
별도의 강제속행 메커니즘이 불필요하다.
```

## 8. 마이그레이션 영향도

### 8.1 변경 파일 목록

| 파일 | 변경 유형 |
|------|----------|
| `.claude/agents/workflow.md` | **신규 생성** |
| `.claude/skills/bugfix/SKILL.md` | 수정 (fork 추가, Sisyphus 제거) |
| `.claude/skills/hotfix/SKILL.md` | 수정 (fork 추가, Sisyphus 제거) |
| `.claude/skills/implement/SKILL.md` | 수정 (fork 추가, Sisyphus 제거) |
| `.claude/skills/improve/SKILL.md` | 수정 (fork 추가, Sisyphus 제거) |
| `.claude/skills/new-project/SKILL.md` | 수정 (fork 추가, Sisyphus 제거) |
| `.claude/hooks/sisyphus-gate.sh` | **삭제** |
| `.claude/flags/sisyphus.json` | **삭제** |
| `CLAUDE.md` | 수정 (아키텍처 섹션 재작성) |

### 8.2 변경되지 않는 파일

- `.claude/skills/` 워커 스킬 10개 (Sisyphus 참조 없음, 이미 fork)
- `.claude/agents/` 기존 에이전트 4개 (reviewer, security, navigator, architect)
- `.claude/hooks/` 나머지 훅 3개 (subagent-monitor, verify-build-test, task-quality-gate, teammate-idle-check)

## 9. 리스크 및 완화

| 리스크 | 영향 | 완화 |
|--------|------|------|
| 중첩 fork로 토큰 비용 증가 | 워크플로우당 ~1.5-2배 | 최적화 옵션 적용 가능 (섹션 6.3) |
| 워크플로우 중간 결과를 사용자가 실시간으로 볼 수 없음 | UX 변화 | 워크플로우가 완료 보고서를 상세하게 작성 |
| 서브에이전트 내 에러 시 메인 에이전트가 맥락 부족 | 디버깅 난이도 | 워크플로우가 에러 컨텍스트를 상세히 포함하여 반환 |
| workflow 에이전트가 Skill() 호출 시 중첩 컨텍스트 로딩 | 실행 속도 저하 | 병렬 호출 활용, 향후 인라인 최적화 |
