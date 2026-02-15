# hoodcat-harness 사용 가이드

Claude Code 멀티에이전트 시스템의 사용법을 설명합니다.

## 개요

hoodcat-harness는 Claude Code의 커스텀 스킬과 에이전트를 조합하여 소프트웨어 개발 워크플로우를 자동화합니다. 8개 에이전트와 11개 스킬이 2-tier Orchestrator-Driven 아키텍처로 협력합니다.

Main Agent는 순수한 디스패처로, 슬래시 커맨드만 직접 호출하고 그 외 모든 요청은 Orchestrator에게 위임합니다. Orchestrator가 스킬을 동적으로 조합하고 실행합니다.

## 새 프로젝트에 적용하기

```bash
# harness CLI로 설치 (권장)
harness install ~/Projects/my-project

# 또는 경로 지정 + 자동 확인
harness install ~/Projects/my-project -f
```

필요한 것:
- Claude Code CLI
- `rsync` (설치/업데이트에 필요)
- `jq` (품질 게이트 훅에 필요, 미설치 시 graceful skip)

설치 시 CLAUDE.md가 없으면 자동 생성되며, 최상단에 `@.claude/harness.md` import가 주입됩니다.

## 아키텍처

### 2-tier, Orchestrator-Driven

```
Tier 1: Main Agent (순수 디스패처)
  ├─ 슬래시 커맨드 (/test, /commit 등) → 해당 스킬 직접 호출
  └─ 그 외 모든 요청 → Orchestrator에게 위임

Tier 2: Orchestrator + 워커 스킬 + 리뷰 에이전트
```

Main Agent의 디스패치 규칙:
1. **슬래시 커맨드** (`/test`, `/commit`, `/deepresearch` 등) → 해당 스킬 직접 호출
2. **그 외 모든 요청** → Orchestrator에 위임

이 규칙에 예외는 없습니다. 버그 수정, 기능 구현, 코드 설명, 리팩토링 등 슬래시 커맨드가 아닌 모든 요청은 Orchestrator가 처리합니다.

### Orchestrator의 역할

Orchestrator는 하드코딩된 워크플로우를 따르지 않습니다. 요청마다 다음 과정을 동적으로 수행합니다:

1. **분석**: 요구의 성격 파악 (버그? 기능? 리서치? 배포?)
2. **계획**: 스킬 카탈로그에서 적절한 스킬 선택, 실행 순서 결정
3. **이행**: `Skill()`과 `Task()`를 순차/병렬 호출하여 계획 실행
4. **판단**: 각 단계 결과를 평가하고 다음 행동 결정 (적응적 실행)
5. **보고**: 최종 결과를 Main Agent에 반환

Orchestrator는 레시피를 참고하되, 상황에 따라 단계를 건너뛰거나 추가하거나 순서를 바꿉니다.

### 실행 흐름 예시

```
[사용자] "로그인 버그 고쳐줘"
     │
     ▼
[Main Agent] → Task(orchestrator, "로그인 버그 고쳐줘")
     │
     ▼
[Orchestrator]
     ├── 1. Task(navigator)     → 코드베이스 탐색, 영향 범위 파악
     ├── 2. Skill("code")       → 버그 진단 + 패치 (agent: coder)
     ├── 3. Skill("test")       → 회귀 테스트 (agent: coder)
     ├── 4. Task(reviewer)      → 코드 품질 리뷰
     └── 5. 보고                → Main Agent에 결과 반환
```

## 스킬 목록

모든 스킬은 `context: fork`로 서브에이전트에서 격리 실행됩니다.

### 코드 작성/수정

| 스킬 | 호출 | Agent | 용도 |
|------|------|-------|------|
| `/code` | `/code "인증 미들웨어 추가"` | coder | 코드 작성, 수정, 진단, 패치. 모든 코드 변경의 기본 스킬 |
| `/scaffold` | `/scaffold worker auth-check -- "인증 검사 스킬"` | coder | 새 스킬/에이전트 파일 자동 생성. 기존 패턴 참조 |

### 테스트/검증

| 스킬 | 호출 | Agent | 용도 |
|------|------|-------|------|
| `/test` | `/test "로그인 모듈"` | coder | 테스트 작성 및 실행 (`--unit`, `--e2e`, `--regression`) |
| `/security-scan` | `/security-scan` | coder | 의존성 취약점 + 코드 보안 패턴 검사 |

### 조사/기획

| 스킬 | 호출 | Agent | 용도 |
|------|------|-------|------|
| `/deepresearch` | `/deepresearch "WebSocket vs SSE 비교"` | researcher | 주제별 심층 자료조사. `docs/research-*.md` 저장 |
| `/blueprint` | `/blueprint "사용자 인증 시스템"` | researcher | 요구사항 분석, 아키텍처, 태스크 분해. `docs/plans/` 저장 |
| `/decide` | `/decide "Redux vs Zustand vs Jotai"` | researcher | 근거 기반 의사결정. `docs/decide-*.md` 저장 |

### 운영

| 스킬 | 호출 | Agent | 용도 |
|------|------|-------|------|
| `/commit` | `/commit` | committer | 변경사항 분석 후 Conventional Commits 형식 커밋 |
| `/deploy` | `/deploy "docker"` | coder | Dockerfile, CI/CD, 환경변수 문서 생성 |

### 팀 기반 (에이전트팀 사용)

| 스킬 | 호출 | 용도 | 비용 |
|------|------|------|------|
| `/team-review` | `/team-review "인증 모듈 리팩토링"` | 3관점(품질/보안/아키텍처) 동시 독립 리뷰 | ~3배 |
| `/qa-swarm` | `/qa-swarm "./my-project"` | 병렬 QA (테스트/린트/빌드/보안 동시 실행) | ~4배 |

## 에이전트 목록

8개의 에이전트가 역할에 따라 자동으로 호출됩니다.

### 실행 에이전트

| 에이전트 | 역할 | 호출 방식 |
|----------|------|----------|
| **orchestrator** | 동적 계획 + 이행. 스킬 조합, 적응적 실행 | Main Agent가 `Task()`로 호출 |
| **coder** | 코딩, 빌드, 테스트 실행 | `/code`, `/test` 등 스킬의 agent로 지정 |
| **committer** | Git 커밋 전용 (최소 권한, sonnet 모델) | `/commit` 스킬의 agent |
| **researcher** | 웹 검색, Context7 문서, 구조화된 문서 작성 | `/deepresearch`, `/blueprint`, `/decide` 스킬의 agent |

### 리뷰 에이전트

| 에이전트 | 역할 | 호출 시점 |
|----------|------|----------|
| **navigator** | 코드베이스 탐색, 파일 매핑, 영향 범위 파악 | 코드 변경 전 컨텍스트 수집 |
| **reviewer** | 코드 품질 리뷰 (가독성, 일관성, 에러 처리) | 코드 변경 후 품질 검증 |
| **security** | 보안 리뷰 (OWASP Top 10, 인증, 입력 검증) | 인증/보안 관련 코드 변경 시 |
| **architect** | 아키텍처 리뷰 (구조, 확장성, 기술 스택) | 설계 문서 리뷰, 대규모 구조 변경 시 |

리뷰 에이전트는 PASS / WARN / BLOCK 판정을 내립니다:
- **PASS**: 이상 없음, 다음 단계로 진행
- **WARN**: 경고 사항 있지만 진행 가능
- **BLOCK**: 수정 필요, 최대 2회 재시도 후에도 BLOCK이면 사용자에게 판단 요청

## Orchestrator 레시피

Orchestrator가 참고하는 대표적인 스킬 조합 패턴입니다. 실제로는 상황에 따라 동적으로 변합니다.

### 기능 구현

```
기본:  Task(navigator) → Skill("code") → Skill("test") → Task(reviewer) → Skill("commit")
단순:  Task(navigator) → Skill("code") → Skill("test") → Skill("commit")
보안:  Task(navigator) → Skill("code") → Skill("test") → Task(reviewer) + Task(security) → Skill("commit")
대규모: Skill("blueprint") → Task(architect) → Skill("code") x N → Skill("test") → /team-review → Skill("commit")
```

### 버그 수정

```
기본:  Task(navigator) → Skill("code", 진단+패치) → Skill("test", 회귀) → Task(reviewer) → Skill("commit")
단순:  Skill("code", 패치) → Skill("test") → Skill("commit")
난해:  Skill("deepresearch", 유사 사례) → Skill("code", 진단+패치) → Skill("test") → Skill("commit")
보안:  Task(security, 심각도) → Skill("code", 패치) → Task(security) + Task(reviewer) → Skill("commit")
```

### 새 프로젝트

```
기본:     Skill("deepresearch") → Skill("blueprint") → Task(architect) →
          Skill("code", 스캐폴드) → Skill("code", 기능1) → ... → Skill("test") → /qa-swarm → Skill("commit")
미정:     Skill("decide", 기술 비교) → Skill("deepresearch") → Skill("blueprint") → ...
대규모:   Skill("blueprint") → 에이전트팀 병렬 개발 → /team-review → ...
```

### 코드 개선

```
기본:     Task(navigator, 영향 범위) → Skill("code") → Skill("test", 회귀) → Task(reviewer) → Skill("commit")
성능:     Skill("deepresearch", 최적화) → Skill("code") → Skill("test", 벤치마크) → Skill("commit")
리팩토링: Task(navigator) → Skill("code") → Skill("test", 전체) → Task(architect) → Skill("commit")
```

## 공유 컨텍스트 시스템

서브에이전트 간 작업 결과를 공유하는 파일 기반 시스템입니다.

### 동작 흐름

1. **SubagentStart**: 이전 에이전트의 작업 요약을 `additionalContext`로 자동 주입
2. **에이전트 실행**: 작업 결과를 `.claude/shared-context/{session-id}/` 에 기록
3. **SubagentStop**: 자발적 기록이 없으면 transcript에서 자동 추출
4. **SessionStart**: TTL 만료된 세션 정리 (기본 24시간)
5. **SessionEnd**: 세션 메트릭 기록

### 설정

`.claude/shared-context-config.json`에서 다음을 설정할 수 있습니다:
- `ttl_hours`: 세션 만료 시간 (기본: 24)
- `max_summary_chars`: 요약 최대 글자수 (기본: 4000)
- `filters`: 에이전트별 컨텍스트 필터 (navigation, code_changes)

## Git Worktree

코드를 수정하는 작업 시 Orchestrator가 git worktree를 자동으로 생성하고 관리합니다.

### 왜 worktree를 사용하나?

- 멀티 세션이 같은 working directory를 공유하면 파일 충돌이 발생
- 에이전트팀 병렬 개발 시 같은 파일 동시 수정으로 덮어쓰기 발생
- worktree로 세션/팀원별 독립 작업 디렉토리를 확보하여 충돌 원천 차단

### 동작 방식

```bash
# Orchestrator가 자동으로 생성
PROJECT_ROOT=$(git -C "$PWD" rev-parse --show-toplevel)
WORKTREE_DIR="$(dirname "$PROJECT_ROOT")/${PROJECT_NAME}-{type}-{feature-name}"
git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" -b "{type}/{feature-name}"
```

작업 완료 후:
1. 미커밋 변경이 있으면 커밋
2. 사용자에게 브랜치 병합 안내 (`git merge` 또는 PR)
3. worktree 자동 제거

### 고아 worktree 정리

```bash
git worktree prune          # 사라진 경로의 worktree 참조 정리
git worktree list           # 현재 worktree 목록 확인
git worktree remove <path>  # 특정 worktree 제거
```

## 검증 규칙

- 빌드/테스트 결과는 실제 명령어의 exit code로만 판단
- 에이전트의 텍스트 보고("통과했습니다")를 신뢰하지 않음
- `.claude/hooks/verify-build-test.sh`로 프로젝트별 빌드/테스트 자동 실행 가능

## 품질 게이트 훅

- `task-quality-gate.sh` (TaskCompleted): 에이전트팀 태스크 완료 시 빌드/테스트 자동 검증
- `teammate-idle-check.sh` (TeammateIdle): 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도

## 에이전트팀 활용 기준

- 독립 태스크 3개 이상 → 에이전트팀 병렬 개발
- 독립 태스크 2개 이하 → 순차 개발
- `/team-review` → 대규모/고위험 변경에만 사용. 단순 변경은 `Task(reviewer)`
- `/qa-swarm` → 테스트 스위트가 다양한 프로젝트에만 사용. 소규모는 `/test`

## 사용 예시

```
# 기능 구현 (자연어 → Orchestrator가 처리)
"사용자 인증 미들웨어 추가해줘"

# 버그 수정 (자연어 → Orchestrator가 처리)
"로그인 시 비밀번호 검증이 안 되는 문제 고쳐줘"

# 코드 작성 (슬래시 커맨드 → 직접 호출)
/code "검색 API 엔드포인트 추가"

# 리서치
/deepresearch "WebSocket vs SSE 실시간 통신 비교"

# 의사결정
/decide "상태관리: Redux vs Zustand vs Jotai"

# 설계
/blueprint "마이크로서비스 인증 시스템"

# 테스트
/test "로그인 모듈 회귀 테스트"

# 멀티렌즈 리뷰 (대규모 변경에만)
/team-review "인증 모듈 전면 리팩토링"

# 병렬 QA (다양한 테스트 스위트가 있는 프로젝트)
/qa-swarm "./my-project"

# 보안 스캔
/security-scan

# 새 스킬 생성
/scaffold worker rate-limiter -- "API 요청 속도 제한 스킬"

# 커밋
/commit
```

## 디렉토리 구조

```
.claude/
├── agents/                          # 에이전트 정의 (8개)
│   ├── orchestrator.md              # 동적 계획 + 이행
│   ├── coder.md                     # 코딩 워커
│   ├── committer.md                 # Git 커밋 워커
│   ├── researcher.md                # 리서치/기획 워커
│   ├── reviewer.md                  # 코드 품질 리뷰
│   ├── security.md                  # 보안 리뷰
│   ├── architect.md                 # 아키텍처 리뷰
│   └── navigator.md                 # 코드베이스 탐색
├── skills/                          # 스킬 정의 (11개, 전부 context: fork)
│   ├── code/SKILL.md                # 코드 작성/수정 (agent: coder)
│   ├── test/SKILL.md                # 테스트 (agent: coder)
│   ├── blueprint/SKILL.md           # 설계/기획 (agent: researcher)
│   ├── commit/SKILL.md              # 커밋 (agent: committer)
│   ├── deploy/SKILL.md              # 배포 (agent: coder)
│   ├── security-scan/SKILL.md       # 보안 스캔 (agent: coder)
│   ├── deepresearch/SKILL.md        # 심층 조사 (agent: researcher)
│   ├── decide/SKILL.md              # 의사결정 (agent: researcher)
│   ├── scaffold/SKILL.md            # 스킬/에이전트 생성 (agent: coder)
│   ├── team-review/SKILL.md         # 멀티렌즈 리뷰 (에이전트팀)
│   └── qa-swarm/SKILL.md            # 병렬 QA (에이전트팀)
├── hooks/                           # 훅 스크립트 (9개)
│   ├── verify-build-test.sh         # 빌드/테스트 검증 유틸
│   ├── task-quality-gate.sh         # 태스크 완료 검증
│   ├── teammate-idle-check.sh       # 팀원 유휴 검사
│   ├── subagent-monitor.sh          # 서브에이전트 종료 로깅
│   ├── shared-context-inject.sh     # 컨텍스트 주입
│   ├── shared-context-collect.sh    # 컨텍스트 수집
│   ├── shared-context-cleanup.sh    # 세션 정리
│   ├── shared-context-finalize.sh   # 세션 메트릭
│   └── test-shared-context.sh       # 테스트용
├── rules/                           # 안티패턴 규칙
│   ├── antipatterns-general.md
│   ├── antipatterns-python.md
│   └── antipatterns-typescript.md
├── agent-memory/                    # 에이전트별 영속 메모리
├── shared-context-config.json       # 공유 컨텍스트 설정
├── harness.md                       # 공통 지침 (모든 프로젝트에 적용)
├── settings.json                    # 훅/상태표시줄 설정
└── statusline.sh                    # 상태표시줄
```

## 버전 히스토리

### v4 (2026-02-14) - 2-tier Orchestrator-Driven 전환
- workflow 에이전트를 orchestrator로 교체
- 워크플로우 스킬 5개(bugfix/hotfix/implement/improve/new-project) + fix 삭제
- `/code`와 `/scaffold` 스킬 신규 추가
- Main Agent를 순수 디스패처로 전환 (슬래시 커맨드 직접 호출 + 나머지 Orchestrator 위임)
- 공유 컨텍스트 시스템 도입 (훅 5개 추가)
- 에이전트 5개 → 8개 (orchestrator, coder, committer, researcher 추가)

### v3 (2026-02-12) - 전체 Fork 전환
- 모든 스킬에 `context: fork` 적용
- 메인 에이전트를 순수 오케스트레이터로 전환
- `workflow` 에이전트 신규 추가
- Sisyphus 강제속행 메커니즘 제거

### v2 (2026-02-08~11) - 멀티에이전트 시스템 구축
- 에이전트 4개 + 스킬 13개 체계 구축
- DO/REVIEW 패턴 도입
- Sisyphus 강제속행 메커니즘 구현
- 에이전트팀 기반 스킬 (team-review, qa-swarm) 추가
- 스킬 아키텍처 재구조화 (워크플로우/워커 분리)
