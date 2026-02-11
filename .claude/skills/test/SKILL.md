---
name: test
description: |
  Writes and runs tests for specified code targets.
  Use when the user wants to add tests, run existing tests, or check test coverage.
  Triggers on: "테스트 작성", "테스트 해줘", "테스트 돌려", "test", or any request
  for writing, running, or analyzing tests.
argument-hint: "<테스트 대상: 파일, 모듈, 또는 --unit/--e2e/--regression>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Edit, Glob, Grep, Bash(git *), Bash(npm *), Bash(npx *), Bash(yarn *), Bash(pnpm *), Bash(pytest *), Bash(cargo *), Bash(go *), Bash(make *), Task
---

# Test Skill

## 입력

$ARGUMENTS: 테스트 대상 설명. 옵션 포함 가능:
- `--unit`: 단위 테스트만
- `--e2e`: E2E 테스트
- `--regression`: 변경된 파일 관련 회귀 테스트만

## 프로세스

### 1. 테스트 대상 파악

navigator 에이전트를 호출하여 대상 코드를 매핑한다:

```
Task(navigator): "$ARGUMENTS의 테스트 대상 코드와 기존 테스트를 탐색하라"
```

파악할 것:
- 테스트할 소스 파일과 핵심 함수/클래스
- 기존 테스트 파일 (이미 있는 테스트)
- 테스트 설정 파일

### 2. 테스트 프레임워크 감지

프로젝트의 설정 파일과 기존 테스트 파일 패턴을 분석하여 테스트 프레임워크를 자동 감지한다.
감지 실패 시 사용자에게 어떤 프레임워크를 사용할지 물어본다.

### 3. 테스트 작성

기존 테스트 패턴을 따라 작성한다:

#### 파일 위치
- 기존 테스트가 있으면 같은 위치/네이밍 패턴을 따름
- 없으면 언어 관례를 따름 (`__tests__/`, `*_test.go`, `test_*.py` 등)

#### 테스트 구조
```
각 테스트 대상 함수/클래스에 대해:
1. Happy path: 정상 입력 → 기대 출력
2. Edge cases: 빈 값, null, 경계값
3. Error cases: 잘못된 입력 → 적절한 에러
```

#### --regression 옵션 시
- `git diff --name-only`로 변경된 파일 확인
- 변경된 파일과 관련된 테스트만 작성/실행

### 4. 테스트 실행

프레임워크에 맞는 테스트 실행 명령을 사용하여 작성한 테스트를 실행하고 결과를 수집한다.

### 5. 커버리지 확인 (가능한 경우)

프레임워크가 지원하면 커버리지 옵션을 추가하여 실행한다.

## 출력

```markdown
## 테스트 결과

### 작성된 테스트
- `path/to/test.ext` - N개 테스트 케이스
  - [테스트 1 설명]
  - [테스트 2 설명]
  - ...

### 실행 결과
- 통과: N개
- 실패: N개
- 건너뜀: N개

### 실패한 테스트 (있으면)
- `testName`: [실패 원인 요약]

### 커버리지 (측정 가능한 경우)
- 라인 커버리지: N%
- 브랜치 커버리지: N%
```

## REVIEW 연동

테스트는 자동 판정한다:
- **전체 통과**: 자동 PROCEED
- **실패 있음**: 실패 원인 분석 후, 테스트 코드 문제인지 소스 코드 문제인지 판단하여 보고
