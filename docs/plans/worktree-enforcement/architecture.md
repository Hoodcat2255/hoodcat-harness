# Git Worktree 강제 사용 - 아키텍처 설계

## 설계 원칙

1. **프롬프트 기반 강제**: Hook이나 외부 도구가 아닌, 스킬/에이전트 프롬프트 내에서 worktree 사용을 강제한다. 에이전트가 자율적으로 worktree를 생성하고 그 안에서 작업한다.
2. **절대 경로 우선**: 서브에이전트의 cwd 리셋 문제를 회피하기 위해, 모든 파일 조작과 명령 실행에 절대 경로를 사용한다.
3. **최소 변경**: 기존 스킬 구조(Phase 순서, DO/REVIEW 패턴)를 유지하면서 worktree Phase만 삽입한다.

## 현재 아키텍처 분석

### 문제점

```
사용자 → /implement "인증 모듈 추가"
  └── workflow 에이전트 (context: fork)
      ├── Phase 1: navigator 탐색 (메인 repo에서)
      ├── Phase 2: 브랜치 생성 (git checkout -b, 메인 repo 변경!)
      ├── Phase 3: 코드 작성 (메인 repo 파일 직접 수정!)
      ├── Phase 4: 린트/포맷
      ├── Phase 5: 테스트
      └── Phase 6: 리뷰
```

문제: Phase 2에서 `git checkout -b`로 메인 repo의 브랜치를 변경하면:
- 동시에 실행 중인 다른 세션의 파일 시스템이 영향을 받는다
- 작업 중 오류 시 메인 브랜치로 복구가 번거롭다
- 에이전트팀 병렬 개발 시 팀원들이 같은 파일을 덮어쓴다

### 목표 아키텍처

```
사용자 → /implement "인증 모듈 추가"
  └── workflow 에이전트 (context: fork)
      ├── Phase 0: Worktree 준비
      │   ├── git worktree add ../project-feat-auth-1707... -b feat/auth
      │   └── WORKTREE_DIR="../project-feat-auth-1707..." (이후 모든 Phase에서 사용)
      ├── Phase 1: navigator 탐색 (WORKTREE_DIR 내에서)
      ├── Phase 2: (브랜치 생성 Phase 제거 - worktree 생성 시 이미 완료)
      ├── Phase 3: 코드 작성 (WORKTREE_DIR 내 파일만 수정)
      ├── Phase 4: 린트/포맷 (WORKTREE_DIR에서 실행)
      ├── Phase 5: 테스트 (WORKTREE_DIR에서 실행)
      ├── Phase 6: 리뷰
      └── Phase 7: Worktree 정리
          ├── (커밋 완료 후) git worktree remove WORKTREE_DIR
          └── 또는 사용자에게 병합 안내
```

## 컴포넌트별 변경 설계

### 1. 워크플로우 스킬 변경 (5개)

각 워크플로우 스킬에 "Phase 0: Worktree 준비"와 "최종 Phase: Worktree 정리"를 추가한다.

#### Worktree 준비 패턴 (공통)

```markdown
### Phase 0: Worktree 준비

작업 전에 독립적인 worktree를 생성한다:

1. 현재 프로젝트의 git 루트 경로를 확인한다:
   ```bash
   PROJECT_ROOT=$(git -C "$PWD" rev-parse --show-toplevel)
   PROJECT_NAME=$(basename "$PROJECT_ROOT")
   ```

2. 브랜치명과 worktree 경로를 결정한다:
   - 브랜치: `{type}/{feature-name}` (예: feat/auth-module)
   - 경로: `../{project-name}-{type}-{feature-name}`
   ```bash
   BRANCH_NAME="{type}/{feature-name}"
   WORKTREE_DIR="$(dirname "$PROJECT_ROOT")/${PROJECT_NAME}-{type}-{feature-name}"
   ```

3. worktree를 생성한다:
   ```bash
   git -C "$PROJECT_ROOT" worktree add "$WORKTREE_DIR" -b "$BRANCH_NAME"
   ```

4. 이후 모든 Phase에서 WORKTREE_DIR의 절대 경로를 사용한다.
   - 파일 읽기/쓰기: `$WORKTREE_DIR/path/to/file`
   - 명령 실행: `cd "$WORKTREE_DIR" && command` 또는 절대 경로 사용
   - navigator 호출 시 WORKTREE_DIR을 기준으로 탐색 요청
```

#### Worktree 정리 패턴 (공통)

```markdown
### 최종 Phase: Worktree 정리

작업 완료 후:

1. 변경사항이 커밋되었는지 확인한다:
   ```bash
   cd "$WORKTREE_DIR" && git status --porcelain
   ```

2. 커밋되지 않은 변경이 있으면 Skill("commit")을 호출한다.

3. 사용자에게 병합 방법을 안내한다:
   ```
   worktree 브랜치: {BRANCH_NAME}
   병합 방법: git merge {BRANCH_NAME} 또는 PR 생성
   ```

4. worktree를 정리한다:
   ```bash
   git -C "$PROJECT_ROOT" worktree remove "$WORKTREE_DIR"
   ```
```

#### 스킬별 특이사항

| 스킬 | Phase 0 위치 | 정리 위치 | 브랜치 타입 | 특이사항 |
|------|-------------|----------|------------|---------|
| implement | Phase 1 전 | Phase 6 후 | `feat/` | 기존 Phase 2(브랜치 생성) 제거 |
| bugfix | Phase 1 전 | Phase 3 후 | `fix/` | 복잡 버그의 에이전트팀도 worktree 필요 |
| hotfix | Phase 1 전 | Phase 4 후 | `hotfix/` | 긴급성 고려, 정리는 사용자 확인 후 |
| improve | Phase 1 전 | Phase 3 후 | `improve/` | Phase 1.5 기획도 worktree 내에서 |
| new-project | Phase 1 전 | Phase 4 후 | `feat/` | Phase 3a 병렬 개발 시 팀원별 worktree |

### 2. workflow 에이전트 변경

`/home/hoodcat/Projects/hoodcat-harness/.claude/agents/workflow.md`에 다음 섹션을 추가한다:

```markdown
## Worktree Management

모든 코드 수정 워크플로우는 git worktree 내에서 실행한다.

### Worktree 생성 규칙
- 작업 시작 시 git worktree를 생성한다
- 경로: `../{project-name}-{type}-{feature-name}`
- 브랜치: `{type}/{sanitized-feature-name}`
- 이후 모든 파일 경로는 worktree의 절대 경로를 사용한다

### 절대 경로 규칙
- WORKTREE_DIR 변수를 설정하고, 모든 Phase에서 이를 기준으로 경로를 구성한다
- Task(navigator) 호출 시 worktree 경로를 명시한다
- Skill 호출 시 worktree 경로를 인자에 포함한다
- 서브에이전트의 cwd는 Bash 호출 간에 리셋되므로, 매 Bash 호출에 절대 경로를 사용한다

### 정리 규칙
- 작업 완료 후 반드시 worktree를 제거한다
- 커밋되지 않은 변경이 있으면 먼저 커밋한다
- 에러로 비정상 종료 시에도 정리 시도한다
```

### 3. coder 에이전트 변경

`/home/hoodcat/Projects/hoodcat-harness/.claude/agents/coder.md`에 다음 지침을 추가한다:

```markdown
## Worktree 작업 지침

워크플로우에서 호출될 때, 작업 경로가 worktree일 수 있다.

- 파일 조작 시 항상 절대 경로를 사용한다
- Bash 명령 실행 시 worktree 경로에서 실행되도록 한다:
  `cd "$WORKTREE_DIR" && npm test` 또는 `npm test --prefix "$WORKTREE_DIR"`
- git 명령은 worktree 내에서 자연스럽게 해당 브랜치를 사용한다
```

### 4. parallel-dev.md 변경

에이전트팀 병렬 개발 시 팀원별 worktree를 사용하도록 수정한다:

```markdown
## 프로세스 (worktree 적용)

1. TeamCreate("dev-team")

2. 리드가 tasks.md에서 독립 태스크 그룹을 식별한다

3. 리드가 각 팀원을 위한 worktree를 생성한다:
   ```bash
   git worktree add "../{project}-dev-1" -b "feat/{task-1-name}"
   git worktree add "../{project}-dev-2" -b "feat/{task-2-name}"
   ```

4. 팀원 스폰 시 worktree 경로를 명시한다:
   Task(team_name="dev-team", name="dev-1"):
     "당신의 작업 디렉토리는 /absolute/path/to/{project}-dev-1 입니다.
      모든 파일 조작과 명령 실행은 이 디렉토리 내에서 수행하세요.
      태스크: [태스크 설명]
      소유 파일: [파일 목록]"

5. 모든 태스크 완료 후:
   - 각 worktree의 변경을 커밋한다
   - 리드가 각 브랜치를 main으로 병합하거나, PR 생성을 안내한다
   - worktree를 정리한다:
     ```bash
     git worktree remove "../{project}-dev-1"
     git worktree remove "../{project}-dev-2"
     ```
```

### 5. committer 에이전트 변경

최소한의 변경. worktree 내에서 git 명령이 자연스럽게 해당 브랜치에서 동작하므로, 절대 경로 사용만 강조한다:

```markdown
## Worktree 호환성

- worktree 내에서 실행될 때, git 명령은 자동으로 해당 worktree의 브랜치에서 동작한다
- `git status`, `git diff` 등은 worktree의 변경사항만 표시한다
- 파일 경로는 항상 절대 경로로 참조한다
```

## 데이터 흐름

```
workflow 에이전트
  │
  ├── Phase 0: Worktree 준비
  │   └── git worktree add → WORKTREE_DIR 확정
  │
  ├── Task(navigator): "WORKTREE_DIR 내 관련 파일 탐색"
  │   └── navigator가 WORKTREE_DIR 기준 절대 경로로 보고
  │
  ├── Skill("implement/fix/test", "WORKTREE_DIR 내에서 작업")
  │   └── coder 에이전트가 WORKTREE_DIR 내 파일만 수정
  │
  ├── Task(reviewer): "WORKTREE_DIR 내 변경 파일 리뷰"
  │   └── reviewer가 WORKTREE_DIR 절대 경로로 파일 접근
  │
  ├── Skill("commit"): "WORKTREE_DIR 내 변경 커밋"
  │   └── committer가 WORKTREE_DIR에서 git commit
  │
  └── 최종 Phase: Worktree 정리
      └── git worktree remove WORKTREE_DIR
```

## 제약사항과 트레이드오프

### Task 도구의 cwd 미지원
- Claude Code의 Task 도구에 cwd 파라미터가 없다 (Issue #12748)
- 서브에이전트는 부모의 PWD를 상속하지만, Bash 호출 간 리셋된다
- **대응**: 프롬프트에 worktree 절대 경로를 명시하고, 에이전트가 절대 경로로 작업하도록 지시한다
- 이 방식은 프롬프트 지시에 의존하므로 100% 강제는 아니지만, 현재 공식 API 제약 내에서 최선의 방법이다

### 에이전트팀 팀원의 작업 디렉토리
- 팀원도 리드와 같은 PWD를 상속한다
- **대응**: 리드가 팀원 프롬프트에 worktree 절대 경로를 포함시킨다
- 팀원은 지시받은 경로 내에서만 작업한다

### worktree 정리 실패 가능성
- 에이전트가 비정상 종료되면 worktree가 남을 수 있다
- **대응**: SessionStart 훅이나 수동 `git worktree prune`로 고아 worktree를 정리한다
- 완료 보고에 worktree 정리 상태를 포함하여 사용자가 인지할 수 있도록 한다

### 의존성 설치
- 새 worktree에는 node_modules, venv 등이 없을 수 있다
- **대응**: worktree 생성 후 의존성 설치 명령을 자동 실행한다 (npm install, pip install 등)
- 이는 프로젝트마다 다르므로, 프로젝트 루트의 설정 파일을 감지하여 적절한 명령을 실행한다
