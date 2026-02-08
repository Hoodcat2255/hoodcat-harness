---
name: fix
description: |
  Diagnoses and patches bugs with regression tests.
  Use when the user reports a bug, error message, or unexpected behavior.
  Triggers on: "고쳐줘", "버그 수정", "에러 해결", "fix", or any request
  to debug, fix, or resolve an error or unexpected behavior.
argument-hint: "<버그 설명 또는 에러 메시지>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Fix Skill

## 입력

$ARGUMENTS: 버그 설명, 에러 메시지, 또는 재현 단계

## 프로세스

### 1. 관련 코드 탐색

navigator 에이전트를 호출하여 버그 관련 코드를 찾는다:

```
Task(navigator): "$ARGUMENTS와 관련된 코드를 탐색하라. 에러가 발생할 수 있는 파일, 호출 체인, 관련 테스트를 찾아라."
```

에러 메시지에 파일 경로/라인이 포함되어 있으면 해당 위치부터 시작한다.

### 2. 버그 재현 시도

가능한 경우 버그를 재현한다:

- 기존 테스트 실행으로 재현 가능한지 확인
- 에러 메시지의 스택 트레이스 분석
- 관련 로그 확인

재현이 불가능한 경우, 코드 분석만으로 진행하되 이를 명시한다.

### 3. 원인 진단

코드를 분석하여 근본 원인을 찾는다:

```
진단 순서:
1. 에러 발생 지점 확인 (스택 트레이스, 에러 메시지)
2. 관련 코드 흐름 추적 (호출자 → 피호출자)
3. 입력 데이터/상태 조건 확인
4. 최근 변경 사항 확인 (git log, git diff)
5. 근본 원인 특정
```

### 4. 패치 작성

원인에 맞는 최소한의 수정을 적용한다:

- **원칙**: 버그만 고친다. 주변 코드 리팩토링은 하지 않는다.
- **기존 패턴 유지**: 프로젝트의 코딩 스타일과 에러 처리 패턴을 따른다.
- **부작용 최소화**: 변경이 다른 기능에 영향을 주지 않도록 한다.

### 5. 회귀 테스트 작성/실행

수정한 버그가 재발하지 않도록 테스트를 추가한다:

- 버그를 재현하는 테스트 케이스 작성 (패치 전이면 실패해야 하는 케이스)
- 기존 테스트가 여전히 통과하는지 확인
- 관련 테스트 전체 실행

### 6. 수정 사항 요약

## 출력

```markdown
## 버그 수정 완료

### 원인
[근본 원인 1-2문장]

### 수정 내용
- `path/to/file.ext:line` - [무엇을 어떻게 고쳤는지]

### 회귀 테스트
- `path/to/test.ext` - [추가한 테스트 케이스 설명]

### 테스트 결과
- 기존 테스트: N개 통과
- 새 회귀 테스트: 통과

### 재현 불가 시
[재현할 수 없었던 이유와 코드 분석 기반 수정 근거]
```

## REVIEW 연동

패치 완료 후, reviewer 에이전트에게 수정 품질을 리뷰받는다:

```
Task(reviewer): "다음 버그 수정의 코드 품질을 리뷰하라: [수정된 파일 목록]. 원인: [근본 원인 요약]"
```

BLOCK이 반환되면 수정하고 재리뷰한다.
