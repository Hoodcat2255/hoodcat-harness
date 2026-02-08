---
name: implement
description: |
  Implements features or tasks by writing code following project conventions.
  Use when the user wants to write new code, add a feature, or implement a planned task.
  Triggers on: "구현해줘", "만들어줘", "코드 작성", "implement", or any request
  to write or create code for a feature or task.
argument-hint: "<태스크 설명 또는 tasks.md 참조>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Implement Skill

## 입력

$ARGUMENTS: 태스크 설명, 또는 `/design`이 생성한 tasks.md의 특정 태스크 참조

## 프로세스

### 1. 컨텍스트 파악

#### 프로젝트 규칙 확인
프로젝트 루트의 CLAUDE.md를 읽어 코딩 컨벤션을 파악한다.

#### 코드베이스 탐색
navigator 에이전트를 호출하여 관련 코드를 매핑한다:

```
Task(navigator): "$ARGUMENTS 구현에 관련된 파일을 탐색하라"
```

navigator 결과에서 다음을 파악:
- 수정할 기존 파일
- 참고할 패턴 (기존 코드와 일관성 유지)
- 영향 받을 의존 코드

### 2. 브랜치 생성 (선택)

사용자가 브랜치를 요청했거나, 변경 규모가 큰 경우:

```bash
git checkout -b feat/{feature-name}
```

별도 지시가 없으면 현재 브랜치에서 작업한다.

### 3. 코드 작성

기존 코드 패턴을 따라 구현한다:

- **기존 파일 수정**: Edit 도구 사용 (정확한 old_string 매칭)
- **새 파일 생성**: Write 도구 사용 (기존 파일 구조와 일관되게)
- **네이밍**: 프로젝트의 기존 네이밍 패턴을 따름
- **에러 처리**: 프로젝트의 기존 에러 처리 패턴을 따름

### 4. 린트/포맷 실행

프로젝트에 린터/포맷터가 설정되어 있으면 실행한다:

```
감지 우선순위:
1. package.json scripts (lint, format)
2. Makefile targets (lint, fmt)
3. 설정 파일 (.eslintrc, .prettierrc, rustfmt.toml, pyproject.toml 등)
```

린트 에러가 발생하면 수정한다.

### 5. 기본 테스트 작성

구현한 코드에 대한 기본 테스트를 작성한다 (해당되는 경우):

- 기존 테스트 패턴을 따름 (테스트 파일 위치, 프레임워크, 네이밍)
- 핵심 동작에 대한 happy path 테스트
- 명확한 실패 케이스 테스트

테스트 프레임워크가 없거나 단순 스크립트인 경우 건너뛴다.

## 출력

사용자에게 구현 결과를 보고한다:

```markdown
## 구현 완료

### 변경된 파일
- `path/to/file.ext` - [무엇을 했는지]
- `path/to/file2.ext` - [무엇을 했는지]

### 새로 생성된 파일
- `path/to/new.ext` - [역할]

### 테스트
- [작성한 테스트 요약 또는 "테스트 해당 없음"]

### 린트
- [통과 / 수정사항]
```

## REVIEW 연동

구현 완료 후, reviewer 에이전트에게 리뷰를 요청한다:

```
Task(reviewer): "다음 파일들의 코드 품질을 리뷰하라: [변경된 파일 목록]"
```

인증/보안 관련 코드가 포함된 경우, security 에이전트에게도 리뷰를 요청한다:

```
Task(security): "다음 파일들의 보안을 리뷰하라: [변경된 파일 목록]"
```

BLOCK이 반환되면 해당 부분을 수정하고 재리뷰한다.
