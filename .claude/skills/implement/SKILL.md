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
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task, Skill
---

# Implement Skill

## 입력

$ARGUMENTS: 태스크 설명, 또는 `/design`이 생성한 tasks.md의 특정 태스크 참조

## DO/REVIEW 시퀀스

$ARGUMENTS를 기반으로 다음 단계를 논스탑으로 순차 실행한다.
각 단계에서 BLOCK이 반환되면 수정 후 재리뷰한다. 최대 2회 재시도 후에도 BLOCK이면 사용자에게 판단을 요청한다.

### Phase 0: Sisyphus 활성화

논스탑 모드를 활성화한다:

```bash
jq --arg wf "implement" --arg ts "$(date -Iseconds)" \
  '.active=true | .workflow=$wf | .currentIteration=0 | .startedAt=$ts | .phase="init"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

### Phase 1: 컨텍스트 파악

phase 상태를 업데이트하고 프로젝트 규칙과 관련 코드를 탐색한다:

```bash
jq '.phase="context"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

```
DO: Task(navigator): "$ARGUMENTS 구현에 관련된 파일을 탐색하라"
```

navigator 결과에서 다음을 파악:
- 수정할 기존 파일
- 참고할 패턴 (기존 코드와 일관성 유지)
- 영향 받을 의존 코드

프로젝트 루트의 CLAUDE.md를 읽어 코딩 컨벤션을 파악한다.

### Phase 2: 브랜치 생성 (선택)

사용자가 브랜치를 요청했거나, 변경 규모가 큰 경우:

```bash
git checkout -b feat/{feature-name}
```

별도 지시가 없으면 현재 브랜치에서 작업한다.

### Phase 3: 코드 작성

```bash
jq '.phase="coding"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

기존 코드 패턴을 따라 구현한다:

- **기존 파일 수정**: Edit 도구 사용 (정확한 old_string 매칭)
- **새 파일 생성**: Write 도구 사용 (기존 파일 구조와 일관되게)
- **네이밍**: 프로젝트의 기존 네이밍 패턴을 따름
- **에러 처리**: 프로젝트의 기존 에러 처리 패턴을 따름

### Phase 4: 린트/포맷 실행

프로젝트에 린터/포맷터가 설정되어 있으면 실행한다:

```
감지 우선순위:
1. package.json scripts (lint, format)
2. Makefile targets (lint, fmt)
3. 설정 파일 (.eslintrc, .prettierrc, rustfmt.toml, pyproject.toml 등)
```

린트 에러가 발생하면 즉시 수정하고 재실행한다.

### Phase 5: 테스트

```bash
jq '.phase="testing"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

구현한 코드에 대한 테스트를 작성하고 실행한다.
**검증 규칙**: 빌드/테스트 결과는 실제 명령어의 exit code로만 판단한다. 텍스트 보고("통과했습니다")를 신뢰하지 않는다.

```
DO: Skill("test", "$ARGUMENTS")
```

- 전체 통과 → Phase 6으로 진행
- 실패 있음 → 자동 수정 시도:
  ```
  DO: Skill("fix", "<실패한 테스트 에러 메시지>")
  DO: Skill("test", "--regression")
  ```
  재테스트 후에도 실패하면 사용자에게 보고

테스트 프레임워크가 없거나 단순 스크립트인 경우 건너뛴다.

### Phase 6: 리뷰

```bash
jq '.phase="review"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

구현 완료 후, reviewer 에이전트에게 리뷰를 요청한다.
인증/보안 관련 코드가 포함된 경우, security 에이전트에게도 리뷰를 요청한다.

**두 리뷰가 모두 필요한 경우, 반드시 하나의 응답에서 두 Task를 동시에 호출하여 병렬 실행한다:**

```
REVIEW (병렬 실행):
  Task(reviewer, run_in_background=true): "다음 파일들의 코드 품질을 리뷰하라: [변경된 파일 목록]"
  Task(security, run_in_background=true): "다음 파일들의 보안을 리뷰하라: [변경된 파일 목록]"
두 결과를 모두 수집한 후 판단한다.
```

reviewer만 필요한 경우(보안 무관 코드):

```
REVIEW: Task(reviewer): "다음 파일들의 코드 품질을 리뷰하라: [변경된 파일 목록]"
```

- PASS/WARN → 완료
- BLOCK → 수정 후 재리뷰 (최대 2회)

## 종료 조건

다음 중 하나를 만족하면 워크플로우가 완료된다:
1. 모든 Phase가 성공적으로 완료
2. 테스트 프레임워크 없이 리뷰까지 통과 (Phase 5 건너뜀)
3. 사용자가 중단을 요청

## Sisyphus 비활성화

완료 보고 직전에 논스탑 모드를 비활성화한다:

```bash
jq '.active=false | .phase="done"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

## 완료 보고

```markdown
## 구현 완료

### 실행된 단계
- [x] 컨텍스트 파악: 관련 파일 N개 확인
- [x] 코드 작성: N개 파일 수정/생성
- [x] 린트: 통과
- [x] 테스트: N개 통과
- [x] 리뷰: PASS

### 변경된 파일
- `path/to/file.ext` - [무엇을 했는지]

### 새로 생성된 파일
- `path/to/new.ext` - [역할]

### 리뷰 결과
- reviewer: [PASS/WARN 요약]
- security: [PASS/WARN 요약 또는 "해당 없음"]
```
