---
name: code
description: |
  Writes, modifies, diagnoses, and patches code following project conventions.
  Handles implementation, bug fixing, refactoring, and lint/format.
  Called by Orchestrator for all code change tasks, or directly by users.
  Triggers on: "코드 작성", "코드 수정", "code", or any direct request
  to write or modify code without a broader workflow.
argument-hint: "<작업 지시: 구현 스펙, 버그 설명, 리팩토링 요청 등>"
user-invocable: true
context: fork
agent: coder
---

# Code Skill

## 입력

$ARGUMENTS: 작업 지시. 다음 중 하나:
- 구현 스펙 (blueprint 출력, 태스크 설명)
- 버그 설명 (에러 메시지, 재현 단계)
- 리팩토링 요청 (대상 코드, 목표)
- worktree 경로가 포함될 수 있음: `(worktree: /path/to/worktree)`

## 프로세스

### 1. 작업 환경 확인

worktree 경로가 지정되었으면 해당 디렉토리에서 작업한다.
지정되지 않았으면 현재 프로젝트 루트에서 작업한다.

### 2. 관련 코드 탐색

작업 대상 코드를 파악한다:
- $ARGUMENTS에 파일 경로가 포함되어 있으면 해당 파일부터 시작
- 아니면 Glob/Grep로 관련 파일을 탐색
- 대규모 탐색이 필요하면 Task(navigator) 호출

### 3. 프로젝트 컨벤션 파악

CLAUDE.md를 읽어 코딩 컨벤션을 파악한다.
기존 코드의 패턴을 참고하여 일관성을 유지한다:
- 네이밍 (변수, 함수, 파일)
- 에러 처리 패턴
- 디렉토리 구조
- 임포트 스타일

### 4. 코드 작성/수정

- **기존 파일 수정**: Edit 도구 사용
- **새 파일 생성**: Write 도구 사용
- **버그 수정 시**: 근본 원인을 진단한 후 최소한의 패치 적용
- **원칙**: 요청된 변경만 수행. 주변 코드 리팩토링 금지.

### 5. 린트/포맷 실행

프로젝트의 린터/포맷터를 감지하여 실행한다:
- `package.json`의 lint/format 스크립트
- `.eslintrc`, `prettier`, `ruff`, `black`, `rustfmt` 등
- 린트 에러가 발생하면 즉시 수정하고 재실행

린터가 없으면 이 단계를 건너뛴다.

## 출력

```markdown
## 코드 변경 완료

### 변경된 파일
- `path/to/file.ext:line` — [무엇을 어떻게 변경했는지]

### 새로 생성된 파일
- `path/to/new.ext` — [역할]

### 버그 진단 (버그 수정 시)
- **원인**: [근본 원인 1-2문장]
- **수정**: [패치 내용]

### 린트/포맷
- [실행한 도구와 결과]
```

## 대용량 출력 처리 (Context Mode)

context-mode MCP 서버가 활성화되어 있으면, 대용량 도구 출력에 대해 context-mode 도구를 활용하여 컨텍스트 윈도우를 절약한다.

### execute 사용 (대용량 명령 출력)

테스트/빌드 실행 등 출력이 50줄 이상 예상되는 명령에 사용한다:
- `mcp__context-mode__execute(language: "shell", code: "npm test 2>&1")`
- `mcp__context-mode__execute(language: "shell", code: "pytest -v 2>&1")`
- `mcp__context-mode__execute(language: "shell", code: "cargo test 2>&1")`

intent 파라미터로 관심 있는 부분만 추출할 수 있다:
- `mcp__context-mode__execute(language: "shell", code: "npm test 2>&1", intent: "failed tests and error messages")`

### execute_file 사용 (대용량 파일 분석)

분석 대상 파일이 200줄 이상일 때, 특정 정보만 추출하려면 사용한다:
- `mcp__context-mode__execute_file(path: "path/to/large-file.log", language: "shell", code: "grep -n 'ERROR' $FILE")`

### 사용하지 않는 경우

다음 상황에서는 일반 도구를 그대로 사용한다:
- **코드 편집 대상 파일 읽기**: Edit/Write를 위해 정확한 내용이 필요하므로 Read 사용
- **git add, git commit, git push**: 파일 변경 작업은 일반 Bash 사용
- **소규모 출력 (50줄 미만)**: 압축 오버헤드가 이점을 초과
- **에러 디버깅 중**: 정확한 스택 트레이스가 필요하면 일반 Bash로 실행
- **설정 파일 읽기**: package.json, tsconfig.json 등 정확한 구조가 필요한 파일

## REVIEW 연동

code 스킬은 자체 리뷰를 수행하지 않는다.
리뷰는 Orchestrator 또는 호출자가 별도로 Task(reviewer)를 호출하여 수행한다.
