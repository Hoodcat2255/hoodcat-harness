# 프롬프트 처리 흐름 (위임 강제 폐지 이후)

> 작성일: 2026-05-22
> 적용 범위: hoodcat-harness가 사용자 프롬프트를 받는 시점부터 워커가 실제 작업을 수행하기까지의 전체 흐름.
> 정본 위치: 본 문서. 구조 변경 시 본 문서를 먼저 갱신한다.
> 자신감 라벨: 확실 (현재 main의 실파일 — `harness.md`, `.claude/dispatch/{catalog,recipes,pushback-trigger}.md`, `CLAUDE.md`, `.claude/skills/*/SKILL.md`, `.claude/settings.json` — 직접 확인 기반. Tier 1. 옵션 X(2026-05-22)로 `orchestrator.md` 및 `orchestrator/examples.md` 제거됨.)

## 1. 핵심 구조 한눈에

```mermaid
flowchart LR
    U[사용자 프롬프트] --> M{Main Agent<br/>디스패처 + 워크플로 조합}
    M -->|슬래시 커맨드| SK[Skill SKILL.md]
    M -->|단순 안내·1줄 .md| MD[Main이 직접 처리]
    M -->|복잡한 자연어 요청| W1[fork: agent]
    M -->|병렬 다관점| TM[Team / ULW]
    SK --> W1
    W1 --> Agents
    TM --> Agents

    subgraph Agents [워커·리뷰어 에이전트]
        direction LR
        Coder[coder]
        Researcher[researcher]
        Committer[committer]
        Navigator[navigator]
        Reviewer[reviewer]
        Architect[architect]
        Security[security]
    end
```

**옵션 A (2026-05-22) 이후의 핵심 변경**

| 항목 | 폐지 전 | 폐지 후 |
|---|---|---|
| PreToolUse Edit\|Write 훅 | 차단 (enforce-delegation.sh) | 없음 |
| ABSOLUTE RULES (FORBIDDEN/REQUIRED) | 강제 | 없음 |
| Review Agent Activation | 3+ 파일·보안 시 reviewer 의무 | 권고 |
| Self-Check 표 | 위임 전 5문항 자가 점검 의무 | 없음 (모델 자율) |
| 글로벌 권고 (`~/.claude/CLAUDE.md`) | "delegate, don't code" | 그대로 유지 |
| 위임 권고 (`harness.md` / `CLAUDE.md`) | 강제 | 단순 안내 |
| Orchestrator 메타 워커 | 존재 (2-tier) | 제거됨 (옵션 X, 2026-05-22) — Main이 직접 조합 (1-tier) |

---

## 2. 케이스별 처리 흐름

### 케이스 A: 슬래시 커맨드 직접 호출

사용자가 `/code`, `/test`, `/commit`, `/blueprint`, `/deepresearch`, `/decide` 등을 명시적으로 호출한 경우. Main Agent는 디스패처지만 슬래시 커맨드는 Claude Code 자체가 해석한다.

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent
    participant SK as Skill SKILL.md
    participant W as 워커 에이전트<br/>(coder/researcher/committer)

    U->>M: /code "사용자 로그인 버튼 추가"
    Note over M: 슬래시 커맨드 인식
    M->>SK: $ARGUMENTS 전달
    SK->>W: agent: coder (frontmatter)<br/>fork sub-agent context
    W->>W: Read·Edit·Bash<br/>(작업 실행)
    W-->>SK: 결과 보고
    SK-->>M: 종료
    M-->>U: 답변
```

**관련 파일**:
- `.claude/skills/{name}/SKILL.md` — frontmatter `agent:` 필드가 fork 대상 결정
- SKILL.md 본문이 워커에게 전달되는 프로세스 명세

### 케이스 B: 자연어 요청 → Main Agent 직접 워크플로 조합 (디스패치 경로)

복잡하거나 모호한 자연어 요청. Main Agent가 `.claude/dispatch/catalog.md`·`recipes.md`를 참조해 직접 워크플로를 조합하고 워커를 호출한다 (Orchestrator 에이전트 없음, 옵션 X 2026-05-22).

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent<br/>(디스패처 + 워크플로 조합)
    participant W as 워커·리뷰어

    U->>M: "로그인 모듈 리팩토링하고 테스트도 추가해줘"
    Note over M: 슬래시 X<br/>dispatch/catalog·recipes 참조<br/>동적 계획 수립
    par 병렬 탐색
        M->>W: Task(navigator)
        M->>W: Skill("deepresearch")
    end
    W-->>M: 보고 통합
    M->>W: Skill("code", "...")
    W-->>M: 변경 결과
    M->>W: Skill("test", "...")
    W-->>M: 테스트 결과
    par 병렬 리뷰
        M->>W: Task(reviewer)
        M->>W: Task(security)
    end
    W-->>M: 리뷰 종합
    M-->>U: 요약
```

**관련 파일**:
- `.claude/dispatch/catalog.md` — Skill·Agent 카탈로그 + OMC 매핑
- `.claude/dispatch/recipes.md` — Feature/Bug Fix/Hotfix/New Project/Code Improvement/Harness Maintenance + 병렬 패턴

### 케이스 C: 단순 안내·1줄 .md 수정 (Main Agent가 직접 처리)

옵션 A 이후 허용된 케이스. 위임 오버헤드가 변경량보다 큰 경우 직접 처리.

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent
    participant FS as 파일시스템

    U->>M: "README.md 첫 줄 typo 고쳐줘"
    Note over M: 위임 권고 vs 오버헤드 평가<br/>→ 직접 처리가 더 효율
    M->>FS: Read README.md
    M->>FS: Edit (1줄)
    M-->>U: 변경 보고
```

판단 기준 (권고, 강제 아님):
- 변경 라인 ≤ 1줄 (또는 표 1행)
- 의미·로직 변경이 아닌 표면적 수정 (typo / 공백 / cross-link 경로 / 단어 치환)
- `.claude/`, `docs/` 하위 `.md` 파일
- 위임 시 토큰·시간 비용 > 직접 처리

### 케이스 D: 다중 파일 코드 변경 (대규모 Feature)

```mermaid
flowchart TD
    U[사용자 요청] --> M[Main Agent<br/>dispatch/catalog·recipes 참조]
    M --> P{5+ 파일 예상?<br/>새 기술 도입?}
    P -->|YES| TE[TeamCreate explore-team]
    P -->|NO| NAV[Task navigator]
    TE --> NAVR[navigator + researcher 병렬]
    NAVR --> BP[Skill blueprint]
    NAV --> BP
    BP --> AR[Task architect<br/>대규모 시]
    AR --> CODE[Skill code × N<br/>worktree에서]
    BP --> CODE
    CODE --> TST[Skill test]
    TST --> P2{3+ 파일 OR<br/>보안 민감?}
    P2 -->|YES| TR[TeamCreate review-team<br/>reviewer + security + architect 병렬]
    P2 -->|NO| RV[Task reviewer]
    TR --> CMT[Skill commit]
    RV --> CMT
    CMT --> M
```

**worktree 패턴** (`dispatch/recipes.md` Worktree Management):
- 첫 `Skill("code", ...)` 호출 전에 worktree 생성
- `Skill("code", "... (worktree: $WT)")` 형태로 경로 전달
- plan 완료 후 worktree 제거

### 케이스 E: 사용자 반박 (Pushback Trigger)

사용자가 직전 답변을 의심할 때 자동 발동. 학습 데이터 일반론(Tier 4)이 사용자의 1차 자료 기반 직관과 충돌하는 경우의 안전망.

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent
    participant SC as Self-Check<br/>(epistemic-honesty.md 5문항)
    participant DR as deepresearch

    U->>M: "정말? / 확실해? / 근거는?"<br/>(키워드 매칭)
    Note over M: 트리거 키워드 매칭 대상은<br/>$USER_REQUEST만 (prompt injection 방어)
    M->>M: 직전 답변을 "추정"으로 강등<br/>사용자에게 알림
    M->>SC: 5문항 평가
    alt Self-Check 하나라도 No
        M->>DR: Skill("deepresearch", ...)
        DR-->>M: Tier 1 자료 결과
        M->>M: 결과 비교
        alt 결과 ≠ 직전 답변
            M-->>U: 명확히 정정 + Tier 라벨
        else 결과 = 직전 답변
            M-->>U: 자신감 라벨 명시하며 유지
        end
    else 모두 Yes
        M-->>U: 답변 유지 + 자신감 라벨
    end
    M->>M: trigger-log.md에 1줄 append<br/>(corrected/confirmed/inconclusive)
```

**키워드** (한국어): `정말`, `확실`, `진짜`, `맞아`, `다시 확인`, `다시 조사`, `근거`, `공고문`, `원문`, `1차 자료`
**키워드** (영어): `really`, `sure`, `verify`, `confirm`, `source`, `evidence`, `primary source`, `original`

**관련 파일**:
- `.claude/dispatch/pushback-trigger.md` — 트리거 로직 정본 (옵션 X 이전 후 위치)
- `.claude/rules/epistemic-honesty.md` — Self-Check 5문항 정본
- `.claude/rules/source-hierarchy.md` — Tier 1~4 분류
- `.claude/agent-memory/main/trigger-log.md` — 발동 통계 (PII 금지)
- `.claude/agent-memory/main/lessons-learned.md` — corrected 사례 누적

### 케이스 F: /goal 자율 루프

Claude Code 2.1.139의 `/goal "<완료 조건>"`. 명시적·객관적 종료 조건이 충족될 때까지 여러 턴 자동 실행.

```mermaid
flowchart LR
    U[/goal pytest exit 0/] --> L{루프 시작}
    L --> EX[작업 실행<br/>= 케이스 D 와 동일 흐름]
    EX --> V{종료 조건<br/>판정}
    V -->|TRUE| END[루프 종료<br/>사용자에게 보고]
    V -->|FALSE| ST{2회 실패<br/>또는 N사이클 정체?}
    ST -->|YES| RU[사용자에게 보고]
    ST -->|NO| L
```

**적합한 종료 조건** (예시):
- `pytest -x exit 0`
- `tsc --noEmit 에러 0개`
- `dist/main.js 파일 존재`
- `eslint . exit 0`

**부적합** (사용 금지): "코드가 좋아질 때까지", "적당히 리팩토링" 같은 주관적 조건.

### 케이스 G: 병렬 작업 (ULW 패턴 / TeamCreate)

같은 응답 안에서 여러 `Agent()` / `Task()` / `Skill()` 호출을 동시 발사하면 자동 병렬 실행.

```mermaid
sequenceDiagram
    participant M as Main Agent
    participant A1 as 워커 A
    participant A2 as 워커 B
    participant A3 as 워커 C

    Note over M: 같은 메시지에서 동시 호출
    par 병렬 발사
        M->>A1: Task(navigator)
        M->>A2: Skill("deepresearch")
        M->>A3: Task(security)
    end
    A1-->>M: 보고
    A2-->>M: 보고
    A3-->>M: 보고
    Note over M: 모든 결과 수집 후 다음 단계
```

**판단 기준** (`dispatch/catalog.md` Parallel Invocation):
- 입력이 독립적 (서로의 출력을 필요로 하지 않음)
- 같은 파일을 동시 수정하지 않음 (읽기는 무관)

**TeamCreate 변형**: 런타임에서 동시 실행을 강제. `team-review`, `qa-swarm`, `TeamExplore`, `TeamReview` 패턴.

---

## 3. 의사결정 흐름 (요약)

```mermaid
flowchart TD
    P[사용자 프롬프트 도착] --> S{슬래시 커맨드?}
    S -->|YES| SC[Claude Code가<br/>Skill SKILL.md 실행<br/>케이스 A]
    S -->|NO| Q{단순 안내·질문·<br/>1줄 .md 수정?}
    Q -->|YES| MD[Main Agent가<br/>직접 처리<br/>케이스 C]
    Q -->|NO| O[Main이 직접 워크플로 조합<br/>케이스 B]
    O --> R{사용자 반박<br/>키워드?}
    R -->|YES| PB[Pushback Trigger<br/>케이스 E]
    R -->|NO| GL{/goal 자율 루프?}
    GL -->|YES| GLOOP[케이스 F<br/>종료 조건까지 반복]
    GL -->|NO| PLAN[Main Agent 동적 계획<br/>dispatch/recipes 참조]
    PLAN --> SCALE{변경 규모}
    SCALE -->|1-2 파일·비보안| SMALL[케이스 B 기본<br/>reviewer 권고]
    SCALE -->|3+ 파일 또는 보안| LARGE[케이스 D<br/>병렬 리뷰 권고]
    SCALE -->|독립 작업 N개| PAR[케이스 G<br/>ULW/Team 병렬]
    PB --> END
    GLOOP --> END
    SMALL --> END[plan 완료 후<br/>커밋·보고]
    LARGE --> END
    PAR --> END
    SC --> END
    MD --> END
```

---

## 4. 개선 전후 비교

### 4.1 동일 시나리오: "src/auth/login.ts에 typo 1줄 수정해줘"

**개선 전 (위임 강제 시스템)**:

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent
    participant H as enforce-delegation.sh
    participant O as Orchestrator
    participant C as coder

    U->>M: "typo 1줄 수정"
    M->>H: Edit 호출 시도
    H-->>M: BLOCK (PreToolUse 차단)
    M->>O: Task(orchestrator, ...)
    O->>O: 계획 수립
    O->>C: Skill("code", "typo 1줄 수정")
    C->>C: Read·Edit·결과 보고
    C-->>O: 완료
    O-->>M: Plan Completed
    M-->>U: 답변
```
오버헤드: orchestrator fork + coder fork + 보고 왕복 ≈ 5단계.

**개선 후 (옵션 A)**:

```mermaid
sequenceDiagram
    actor U as 사용자
    participant M as Main Agent

    U->>M: "typo 1줄 수정"
    M->>M: Read·Edit (직접)
    M-->>U: 답변
```
오버헤드: 1단계.

### 4.2 동일 시나리오: "auth 모듈 3개 파일 리팩토링 + 회귀 테스트"

**개선 전**: 위임 강제로 무조건 Skill 위임 → 본 케이스는 자연스럽게 적합.
**개선 후**: 권고이긴 하지만 모델이 같은 결론(위임)에 도달. **흐름 동일.**

규모가 큰 작업은 옵션 A 이후에도 자연 위임 (모델 판단 + 글로벌 권고). 강제 vs 권고의 차이가 **작은 변경에서만** 발생.

### 4.3 신뢰도 관점

| 항목 | 강제 시스템 | 권고 시스템 (옵션 A) |
|---|---|---|
| 위임율 (큰 변경) | 100% | ~100% (자연 위임) |
| 위임율 (작은 변경) | 100% (오버헤드 큼) | 모델 판단 — 효율적 |
| 안전망 | 물리적 차단 | 글로벌 권고 + Self-Check on Pushback |
| OMC 전환 호환 | enforce-delegation 회귀 테스트 필요 | 부담 0 |
| 회귀 리스크 | 차단 오류 시 정당 위임도 차단 가능 | 모델 판단 오류 시 작은 변경에 영향 (제한적) |

---

## 5. 추가 참고

- 카탈로그·레시피·트리거 상세 (옵션 X 이후 위치):
  - `.claude/dispatch/catalog.md`
  - `.claude/dispatch/recipes.md`
  - `.claude/dispatch/pushback-trigger.md`
  - ~~`.claude/agents/orchestrator/examples.md`~~ — 옵션 X (2026-05-22) 삭제됨
- 공통 룰 정본:
  - `.claude/rules/response-format.md`
  - `.claude/rules/shared-context-protocol.md`
  - `.claude/rules/agent-memory.md`
  - `.claude/rules/epistemic-honesty.md`
  - `.claude/rules/source-hierarchy.md`
  - `.claude/rules/antipatterns-{general,python,typescript}.md`
- OMC 전환:
  - `docs/migration-omc-mapping-20260522.md`
  - `.claude/settings-omc.json.example`
- 진행 상황:
  - `TODO.md` ("오케스트레이터 위임율 개선" 종결 절 + Phase 5+ 운영 검증 항목)
