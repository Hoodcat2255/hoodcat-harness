# hoodcat-harness 공통 지침

이 문서는 hoodcat-harness 멀티에이전트 시스템이 설치된 모든 프로젝트에 적용되는 공통 지침이다.

## 스킬 아키텍처 (2-tier, Planner-Driven)

```
Tier 1: Main Agent (순수 디스패처)
  ├─ 슬래시 커맨드 → 해당 스킬 직접 호출
  └─ 그 외 모든 요청 → Planner에게 위임: Task(planner, "$USER_REQUEST")

Tier 2: Planner + 워커 스킬 + 리뷰 에이전트
```

### Main Agent의 역할

Main Agent는 코드를 쓰지 않고, 테스트를 실행하지 않는다.
사용자 의도를 파악하여 적절한 스킬 또는 Planner에게 위임한다.

#### 디스패치 기준

- **슬래시 커맨드** (`/test`, `/commit`, `/deepresearch`, `/scaffold` 등) → 해당 스킬 직접 호출
- **그 외 모든 자연어 요청** → `Task(planner, "$USER_REQUEST")`로 Planner에 위임. 사용자가 "planner"를 명시하지 않아도 자동으로 위임한다.

### Planner

Planner는 `.claude/agents/planner.md`로 정의된 에이전트다.
Main Agent가 `Task(planner, ...)`로 호출하면 fork 컨텍스트에서 자율 실행한다.

Planner의 역할:
1. **분석**: 요구의 성격 파악 (버그? 기능? 리서치? 배포?)
2. **계획**: 스킬 카탈로그에서 스킬을 선택하고 실행 순서를 동적으로 결정
3. **이행**: Skill()과 Task()를 순차/병렬 호출하여 계획 실행
4. **판단**: 각 단계 결과를 평가하고 다음 행동 결정 (적응적 실행)
5. **보고**: 최종 결과를 Main Agent에 반환

Planner는 하드코딩된 워크플로우를 따르지 않는다. 레시피를 참고하되, 상황에 따라 단계를 건너뛰거나, 추가하거나, 순서를 바꾸거나, 동적으로 반복한다.

### 워커 스킬 (11개)

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

### 에이전트 (8개)

| 에이전트 | 역할 | 호출 방식 |
|---------|------|----------|
| **planner** | 동적 계획 + 이행 | Main Agent가 Task()로 호출 |
| **coder** | 코딩, 빌드/테스트 | 스킬의 agent로 지정 |
| **committer** | Git 커밋 (최소 권한, sonnet) | commit 스킬의 agent |
| **researcher** | 웹 검색, 문서 작성 | 리서치 스킬의 agent |
| **reviewer** | 코드 품질 리뷰 | Planner가 Task()로 호출 |
| **security** | 보안 리뷰 | Planner가 Task()로 호출 |
| **architect** | 아키텍처 리뷰 | Planner가 Task()로 호출 |
| **navigator** | 코드베이스 탐색 | Planner가 Task()로 호출 |

## Git Worktree 규칙

코드를 수정하는 계획을 이행할 때 Planner가 git worktree를 생성하고 관리한다.

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

에이전트팀 병렬 개발 시 Planner가 팀원별 worktree를 사전 생성한다:
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

## 품질 게이트 훅

- `.claude/hooks/task-quality-gate.sh` (TaskCompleted): 구현 태스크 완료 시 빌드/테스트 자동 검증
- `.claude/hooks/teammate-idle-check.sh` (TeammateIdle): 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도

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
