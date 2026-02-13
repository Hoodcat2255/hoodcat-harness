---
name: commit
description: |
  Analyzes current changes and creates a well-structured git commit.
  Use when the user wants to commit current changes with a proper message.
  Triggers on: "커밋해줘", "커밋", "commit", or any request to commit changes.
argument-hint: "[커밋 메시지 힌트 (선택)]"
user-invocable: true
context: fork
agent: committer
---

# Commit Skill

## 입력

$ARGUMENTS: (선택) 커밋 메시지 힌트. 비어있으면 변경사항 분석으로 자동 생성.

## 프로세스

### 1. 변경사항 확인

```bash
git status
git diff --staged
git diff
```

변경사항이 없으면 "커밋할 변경사항이 없습니다"를 보고하고 종료한다.

### 2. 변경 내역 분석

변경된 파일들을 읽고 분석한다:

- **어떤 파일이 변경되었는가** (추가/수정/삭제)
- **변경의 성격은 무엇인가** (기능 추가, 버그 수정, 리팩토링, 문서, 설정 등)
- **변경의 목적은 무엇인가** (why)

### 3. 스테이징

커밋에 포함할 파일을 스테이징한다:

- 관련 있는 파일만 선택적으로 `git add` (전체 `git add .` 지양)
- 민감 파일 제외 (.env, credentials, secrets)
- 사용자가 특정 파일만 커밋하라고 했으면 해당 파일만

### 4. 커밋 메시지 생성

Conventional Commits 형식을 따른다:

```
<type>: <description>

[body (선택)]
```

타입:
- `feat`: 새로운 기능
- `fix`: 버그 수정
- `docs`: 문서 수정
- `refactor`: 리팩토링
- `style`: 포맷팅
- `test`: 테스트
- `chore`: 기타 변경

규칙:
- description은 한국어로, 간결하지만 구체적으로
- $ARGUMENTS에 힌트가 있으면 반영
- body는 변경이 복잡한 경우에만 추가
- Co-Authored-By 포함하지 않음

### 5. 커밋 실행

```bash
git commit -m "<메시지>"
```

pre-commit hook이 실패하면:
1. 에러 내용 분석
2. 문제 수정
3. 다시 스테이징
4. **새 커밋으로** 시도 (amend 하지 않음)

## 출력

```markdown
## 커밋 완료

**커밋**: `<hash>` <메시지>

### 포함된 변경
- `path/to/file.ext` - [변경 요약]
- `path/to/file2.ext` - [변경 요약]
```

## REVIEW 연동

commit은 리뷰 없이 자동 완료한다. 코드 품질 리뷰는 Orchestrator가 /code 이후 Task(reviewer)로 수행한다.
