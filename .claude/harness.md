# hoodcat-harness 공통 지침

이 문서는 hoodcat-harness 멀티에이전트 시스템이 설치된 모든 프로젝트에 적용되는 공통 지침이다.

## 스킬 아키텍처 (1-tier, Main-Agent-Driven)

```
Main Agent (디스패처 + 워크플로 조합자)
  ├─ 슬래시 커맨드 → 해당 스킬 직접 호출
  └─ 그 외 요청 → dispatch/catalog.md 참조 → 워커·스킬을 직접 호출하여 조합
```

### 워크플로 조합 정본 파일

Main Agent는 아래 세 파일을 직접 참조하여 워크플로를 조합한다:

- `.claude/dispatch/catalog.md` — Skill·Agent 카탈로그 (호출 형태·신뢰도·OMC 매핑 표 포함)
- `.claude/dispatch/recipes.md` — Feature / Bug Fix / Hotfix / Code Improvement / Harness Maintenance 레시피
- `.claude/dispatch/pushback-trigger.md` — 사용자 반박 자동 대응 (Main Agent가 직접 평가)

### Main Agent의 역할

Main Agent는 디스패처이자 워크플로 조합자다. `dispatch/catalog.md`의 워커·스킬을 직접 호출하여 작업을 이행하고, 결과를 사용자에게 전달한다.

#### 디스패치 기준

1. **슬래시 커맨드** (`/`로 시작하는 요청) → 해당 스킬을 Skill()로 직접 호출
2. **그 외 자연어 요청** → `dispatch/catalog.md`와 `dispatch/recipes.md`를 참조하여 적합한 워커·스킬을 직접 호출

#### 자기 검증 체크리스트 (매 턴 실행)

응답을 생성하기 전에 아래를 점검한다:

1. **이 요청이 `/`로 시작하는 슬래시 커맨드인가?**
   - YES → 해당 스킬을 Skill()로 호출
   - NO → `dispatch/recipes.md`에서 해당 레시피를 찾아 워커·스킬을 조합한다
2. **나는 지금 코드 수정·빌드·테스트·심층 분석을 직접 수행하려 하는가?**
   - 이런 작업은 catalog의 워커(executor, coder 등)에 위임하는 것이 품질과 추적성 면에서 낫다

#### 권고 행위

- 슬래시 커맨드 → Skill() 호출
- 복잡한 작업 → `dispatch/catalog.md`의 워커·스킬을 직접 호출하여 조합
- 단순 안내·명확화 질문·1줄 .md 수정 → Main Agent가 직접 처리 (위임 오버헤드가 더 큰 경우)
- 워커 결과를 사용자에게 전달

> Main Agent는 디스패처 + 워크플로 조합자 역할을 수행한다. 복잡한 작업은 `dispatch/catalog.md`를 참조하여 워커·스킬을 직접 호출하되, 단순 안내·질문·1줄 .md 수정처럼 위임 오버헤드가 더 큰 경우 직접 처리 가능.

#### `/goal` 자율 루프

Claude Code 2.1.139의 `/goal "<완료 조건>"`은 조건이 충족될 때까지 여러 턴 자율 실행을 지속한다. 자율 루프 안에서도 위 디스패치 기준이 그대로 적용된다: 종료 조건만 자동 평가될 뿐, 도구 권한 모델은 동일하다.

### 워커 스킬 (12개)

모든 스킬은 `context: fork`로 격리 실행. 스킬 안에서 다른 스킬을 호출하지 않는다.

| 스킬 | Agent | 용도 |
|------|-------|------|
| `code` | coder | 코드 작성·수정·진단·패치 |
| `test` | coder | 테스트 작성·실행 |
| `blueprint` | researcher | 설계 문서 생성 |
| `commit` | committer | Git 커밋 |
| `deploy` | coder | 배포 설정 |
| `security-scan` | coder | 보안 스캔 |
| `deepresearch` | researcher | 심층 자료조사 |
| `decide` | researcher | 비교 분석·의사결정 |
| `scaffold` | coder | 스킬/에이전트 생성 |
| `team-review` | coder | 멀티렌즈 리뷰 (에이전트팀) |
| `qa-swarm` | coder | 병렬 QA (에이전트팀) |
| `sync-docs` | coder | harness 문서 자동 동기화 |

### 에이전트 (7개)

| 에이전트 | 역할 | 호출 방식 |
|---------|------|----------|
| **coder** | 코딩, 빌드/테스트 (context-mode MCP) | 스킬의 agent로 지정 |
| **committer** | Git 커밋 (최소 권한, sonnet) | commit 스킬의 agent |
| **researcher** | 웹 검색, 문서 작성 (context7, context-mode MCP) | 리서치 스킬의 agent |
| **reviewer** | 코드 품질 리뷰 | Main Agent가 Task()로 호출 |
| **security** | 보안 리뷰 | Main Agent가 Task()로 호출 |
| **architect** | 아키텍처 리뷰 | Main Agent가 Task()로 호출 |
| **navigator** | 코드베이스 탐색 | Main Agent가 Task()로 호출 |

## Git Worktree 규칙

코드를 수정하는 계획을 이행할 때 Main Agent가 git worktree를 생성하고 관리한다.

- 멀티 세션이 같은 working directory를 공유하면 파일 충돌이 발생한다
- 에이전트팀 병렬 개발 시 팀원들이 같은 파일을 동시에 수정하면 덮어쓰기가 발생한다
- worktree로 세션/팀원별 독립 작업 디렉토리를 확보하여 충돌을 원천 차단한다

### Worktree 생성

```bash
PROJECT_ROOT=$(git -C "$PWD" rev-parse --show-toplevel)
PROJECT_NAME=$(basename "$PROJECT_ROOT")
BRANCH_NAME="{type}/{feature-name}"           # feat/auth, fix/login-error, hotfix/xss
WORKTREE_DIR="$(dirname "$PROJECT_ROOT")/${PROJECT_NAME}-{type}-{feature-name}"
git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"
```

새 worktree에는 `node_modules`, `venv` 등이 없으므로 의존성을 설치한다:
```bash
cd "$WORKTREE_DIR" && npm install          # package.json
cd "$WORKTREE_DIR" && pip install -r requirements.txt  # requirements.txt
cd "$WORKTREE_DIR" && cargo build          # Cargo.toml
cd "$WORKTREE_DIR" && go mod download      # go.mod
```

### 절대 경로 원칙

서브에이전트의 Bash cwd는 호출 간에 리셋되므로, 항상 절대 경로를 사용한다:
- 파일 조작: `$WORKTREE_DIR/path/to/file` 절대 경로로 Read/Write/Edit
- Bash 명령: `cd "$WORKTREE_DIR" && command` 또는 절대 경로 사용
- 스킬 호출: worktree 경로를 인자에 포함 (예: `Skill("code", "... (worktree: $WORKTREE_DIR)")`)
- 팀원 스폰: worktree 절대 경로를 프롬프트에 명시

### Worktree 정리

작업 완료 후:
1. 미커밋 변경이 있으면 커밋한다
2. 사용자에게 브랜치 병합을 안내한다 (`git merge $BRANCH_NAME` 또는 PR)
3. worktree를 제거한다: `git -C "$PROJECT_ROOT" worktree remove "$WORKTREE_DIR"`

에러가 발생해도 worktree 정리를 시도한다 (고아 방지).

### 팀원별 Worktree

에이전트팀 병렬 개발 시 Main Agent가 팀원별 worktree를 사전 생성한다:
```bash
git -C "$PROJECT_ROOT" worktree add \
  "$(dirname "$PROJECT_ROOT")/${PROJECT_NAME}-dev-N" -b "feat/{task-N-name}"
```

### 고아 worktree 정리

```bash
git worktree prune          # 사라진 경로의 worktree 참조 정리
git worktree list           # 현재 worktree 목록 확인
git worktree remove <path>  # 특정 worktree 제거
```

## 검증 규칙

- 빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다
- 텍스트 보고("통과했습니다")를 신뢰하지 않는다
- `.claude/hooks/verify-build-test.sh`로 프로젝트별 빌드/테스트 자동 실행 가능

## 프로젝트 로컬 확장 (.harness-local)

하네스가 설치된 프로젝트에 프로젝트 전용 스킬·에이전트·룰·훅을 두려면, 그 경로를 `.claude/.harness-local` 매니페스트에 선언한다. 선언된 항목은 `harness.sh update`가 수행하는 `rsync --delete`로부터 보존된다.

- 경로는 `.claude/` 기준 상대경로로, 한 줄에 하나씩 적는다.
- `#`로 시작하거나 인라인 `#` 이후는 주석, 빈 줄은 무시된다.
- 형식 예시:

```
# 프로젝트 전용 청약 스킬/에이전트
skills/cheongyak
agents/cheongyak.md
```

- 매니페스트는 **명시적 opt-in**이다. 여기에 선언되지 않은 dst 전용 파일(업데이트 시 업스트림에 없는 파일)은 업데이트 때 삭제된다. 이는 업스트림에서 의도적으로 제거한 항목과 유저 추가 항목을 혼동하지 않기 위함이다.
- `harness.sh update`의 변경 미리보기에서 보존 대상은 `= (보존됨, .harness-local)`로, 삭제 예정 항목은 `- (삭제 예정)`로 표시된다.

## 사실 검증 & 사용자 반박 대응

사실 진술이 포함된 모든 에이전트는 자료 등급 규칙과 인식적 정직 규칙을 따른다. 사용자 직관이 에이전트 결론과 충돌할 때는 단정형 답변을 보류하고 1차 자료를 재확인한다.

- 자료 등급(Source Hierarchy) Tier 1~4 정본: `.claude/rules/source-hierarchy.md`. 1차 자료 도달 강제 도메인(법률·청약·세무·의료·금융 등) 목록과 Tier 1 도달 불가 시 fallback 규칙을 정의한다.
- 단정 회피·자신감 라벨(`확실`/`추정`/`모름`)·비유 사용 제약 정본: `.claude/rules/epistemic-honesty.md`. 모든 사실 주장에 Tier 라벨과 자신감 라벨을 동반한다.
- 사용자 반박 키워드 감지 시 자동 Self-Check 5문항 + 미충족 시 deepresearch 호출 메커니즘의 정본은 `.claude/dispatch/pushback-trigger.md`에 있다. Main Agent가 직접 평가한다. researcher 에이전트(`.claude/agents/researcher.md`)에도 동일 절이 있다.
- 도메인 사전 확률 가중치(사용자 직관이 옳았던 사례) 누적: `.claude/agent-memory/main/lessons-learned.md`.

## 훅

### 품질 게이트

- `.claude/hooks/task-quality-gate.sh` (TaskCompleted): 구현 태스크 완료 시 빌드/테스트 자동 검증
- `.claude/hooks/teammate-idle-check.sh` (TeammateIdle): 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도

### 텔레그램 알림

- `.claude/hooks/notify-telegram.sh` (SubagentStop): 서브에이전트 완료 시 텔레그램으로 알림 전송
- 환경변수 `HARNESS_TG_BOT_TOKEN`, `HARNESS_TG_CHAT_ID`가 설정된 경우에만 동작
- 환경변수는 `~/.claude/.env`에서 관리 (전역), 프로젝트별 `.env`로 오버라이드 가능
- 설정: `./harness.sh config`으로 대화형 설정, 또는 `~/.claude/.env` 직접 편집
- 참고: `.claude/.env.example` 템플릿

### 서브에이전트 모니터링

- `.claude/hooks/subagent-monitor.sh` (SubagentStop): 서브에이전트 종료 이벤트를 로깅
- 차단하지 않음 - 순수 로깅 목적

## 공유 컨텍스트 시스템

서브에이전트 간 작업 결과를 공유하는 파일 기반 시스템.

**동작 원리:**
1. **SubagentStart** (`shared-context-inject.sh`): 이전 에이전트의 작업 요약을 `additionalContext`로 주입
2. **에이전트 자발적 기록**: 작업 결과를 `.claude/shared-context/{session-id}/{agent-type}-{agent-id}.md`에 기록
3. **SubagentStop** (`shared-context-collect.sh`): 자발적 기록이 없으면 transcript에서 자동 추출
4. **SessionStart** (`shared-context-cleanup.sh`): TTL 만료 세션 정리
5. **SessionEnd** (`shared-context-finalize.sh`): 세션 메트릭 기록

**설정:** `.claude/shared-context-config.json`

## 에이전트팀 활용 기준

- 독립 태스크 3개 이상이면 에이전트팀 병렬 개발, 2개 이하면 순차 개발
- **/team-review**: 대규모/고위험 변경에만 사용, 단순 변경은 Task(reviewer)
- **/qa-swarm**: 테스트 스위트가 다양한 프로젝트에만 사용, 소규모는 /test

## 에이전트 & 스킬 Best Practices / Anti-Patterns

@docs/research-claude-agent-skill-best-practices-antipatterns-20260212.md

## 스킬 작성 규칙

스킬 파일은 `.claude/skills/<skill-name>/SKILL.md` 경로에 생성합니다.

필수 frontmatter 필드:
- `name`: 스킬 식별자
- `description`: 스킬 용도 및 트리거 조건
- `context: fork` - 모든 스킬에 필수

선택적 필드:
- `agent` - 사용할 에이전트 유형. 도구 권한은 에이전트가 관리한다.
