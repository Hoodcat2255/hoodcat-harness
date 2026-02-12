# Git Worktree 강제 사용 - 요구사항 정의

## 배경

현재 `harness.md`의 "Git Worktree 규칙" 섹션에 worktree 사용이 명시되어 있지만, 실제 스킬/에이전트 코드에는 worktree 생성/사용 로직이 전혀 없다. 규칙은 선언적이지만 강제가 아니어서, 에이전트가 이를 무시하고 메인 worktree에서 직접 작업하는 상황이 발생할 수 있다.

## 기능 요구사항

### FR-1: 워크플로우 스킬에 worktree Phase 추가
- 대상: implement, bugfix, hotfix, improve, new-project (5개 워크플로우 스킬)
- 코드 수정이 시작되기 전에 git worktree를 생성하는 Phase를 추가한다
- worktree 경로: `../{project-name}-{skill-name}-{timestamp}` 형식
- 브랜치: `{type}/{feature-name}` (예: `feat/auth-module`, `fix/login-error`)
- 작업 완료 후 worktree를 정리(remove)하는 Phase를 추가한다

### FR-2: workflow 에이전트에 worktree 관리 지침 추가
- workflow 에이전트 정의에 worktree 생성/관리 패턴을 명시한다
- 작업 디렉토리 전환 후 모든 후속 명령에 절대 경로를 사용하도록 지시한다

### FR-3: coder 에이전트에 작업 디렉토리 인식 추가
- coder 에이전트가 worktree 내에서 작업할 때의 지침을 추가한다
- 파일 경로를 항상 절대 경로로 사용하도록 강화한다

### FR-4: parallel-dev.md에 팀원별 worktree 패턴 추가
- 에이전트팀 병렬 개발 시 각 팀원이 별도의 worktree에서 작업하도록 패턴을 추가한다
- 리드가 팀원별 worktree를 생성하고, 팀원은 해당 경로에서만 작업한다

### FR-5: commit 스킬/committer 에이전트의 worktree 호환성
- committer가 worktree 내에서 git 명령을 정확히 실행할 수 있도록 한다
- worktree의 현재 브랜치를 인식하여 커밋한다

## 비기능 요구사항

### NFR-1: 하위 호환성
- 기존 스킬 호출 방식과 인터페이스를 변경하지 않는다
- 사용자는 동일한 `/implement`, `/bugfix` 등의 명령을 사용한다

### NFR-2: 안전한 정리
- worktree 작업 중 에러가 발생해도 worktree가 정리되도록 한다
- 비정상 종료 시에도 고아 worktree가 남지 않도록 권장 패턴을 문서화한다

### NFR-3: 절대 경로 일관성
- 모든 에이전트 간 통신(공유 컨텍스트 등)에서 worktree 절대 경로를 사용한다
- Task(navigator) 결과의 파일 경로가 worktree 내 경로로 보고되어야 한다

### NFR-4: 성능 영향 최소화
- worktree 생성/삭제는 수 초 이내로 완료되어야 한다
- 추가되는 git 명령은 최소한으로 유지한다

## 가정 사항

1. **Task 도구에 cwd 파라미터가 없다**: 2026-02 기준, Claude Code의 Task 도구에 working directory를 지정하는 파라미터가 공식 지원되지 않는다 (Issue #12748 OPEN 상태). 따라서 에이전트가 명시적으로 worktree 경로를 인식하고 절대 경로로 작업해야 한다.

2. **서브에이전트의 cwd는 부모를 상속한다**: 서브에이전트(context: fork)는 부모의 PWD를 상속하지만, Bash 호출 간에 cwd가 리셋된다. 따라서 `cd` 대신 절대 경로를 사용하거나, 매 Bash 호출마다 `cd /worktree && command` 패턴을 사용해야 한다.

3. **에이전트팀 팀원도 같은 PWD를 상속한다**: TeamCreate로 생성된 팀원들도 리드와 같은 작업 디렉토리에서 시작한다. 팀원별로 다른 worktree에서 작업하려면 프롬프트에 worktree 경로를 명시해야 한다.

4. **git worktree는 프로젝트 루트에서만 생성 가능하다**: worktree는 메인 repo의 형제 디렉토리로 생성하는 것이 관례이다.

## 범위 제한

- Hook 기반 worktree 자동 생성은 이번 범위에서 제외한다 (향후 SubagentStart 훅에서 자동화 가능)
- IDE/에디터 통합은 범위 밖이다
- worktree 기반 PR 자동 생성은 이번 범위에서 제외한다
