---
name: hotfix
description: |
  Urgent workflow for security vulnerabilities and critical issues.
  Security agent evaluates severity first, then fix with dual review.
  Triggers on: "보안 수정", "긴급 수정", "hotfix", "취약점 패치",
  or any request to fix a security vulnerability or critical production issue.
argument-hint: "<보안 이슈 또는 긴급 이슈 설명>"
user-invocable: true
context: fork
allowed-tools: Task, Skill, Read, Write, Glob, Grep, Bash
---

# Hotfix Workflow

## 트리거 조건

보안 취약점이나 프로덕션 긴급 이슈를 수정할 때 사용한다.
일반 버그는 /bugfix, 기능 개선은 /improve를 사용한다.

## DO/REVIEW 시퀀스

### Phase 0: Sisyphus 활성화

논스탑 모드를 활성화한다:

```bash
jq --arg wf "hotfix" --arg ts "$(date -Iseconds)" \
  '.active=true | .workflow=$wf | .currentIteration=0 | .startedAt=$ts | .phase="init"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

### Phase 1: 심각도 평가

```bash
jq '.phase="severity-assessment"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

security 에이전트가 먼저 이슈의 심각도를 판단한다:

```
REVIEW: Task(security): "다음 이슈의 심각도를 평가하라: $ARGUMENTS. 공격 벡터, 영향 범위, 긴급도를 판단하라."
```

security 결과에서 확인:
- **Critical/High** → 즉시 Phase 2로 진행
- **Medium/Low** → 사용자에게 보고하고 /bugfix로 전환할지 물어봄

### Phase 2: 수정

```bash
jq '.phase="patching"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

/fix 스킬이 취약 코드를 찾고 패치한다:

```
DO: Skill("fix", "$ARGUMENTS")
```

### Phase 3: 이중 리뷰

```bash
jq '.phase="dual-review"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

보안 수정은 security + reviewer 두 에이전트가 모두 리뷰한다:

```
REVIEW: Task(security): "패치가 취약점을 완전히 해결하는가? 새로운 공격 벡터가 생기지 않았는가?"
REVIEW: Task(reviewer): "패치의 코드 품질을 리뷰하라."
```

두 리뷰를 병렬로 요청할 수 있다.

- 둘 다 PASS/WARN → Phase 4로 진행
- 하나라도 BLOCK → 수정 후 재리뷰 (최대 2회)

### Phase 4: 검증

```bash
jq '.phase="verification"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

**검증 규칙**: 빌드/테스트 결과는 실제 명령어의 exit code로만 판단한다. 텍스트 보고("통과했습니다")를 신뢰하지 않는다.

테스트와 보안 스캔을 함께 실행한다:

```
DO: Skill("test", "--regression")
```

보안 스캔 스킬이 있으면 함께 실행:
```
DO: Skill("security-scan", "<대상 디렉토리>")  (Phase 4에서 구현 예정)
```

- 전체 통과 → 완료
- 실패 있음 → 수정 후 재검증
  ```
  DO: Skill("fix", "<실패 내용>")
  DO: Skill("test", "--regression")
  ```

security-scan 스킬이 아직 없으면 테스트 통과만으로 진행하고 사용자에게 알린다.

## 종료 조건

1. 패치 + 이중 리뷰 통과 + 테스트 통과
2. 사용자가 중단을 요청

## Sisyphus 비활성화

완료 보고 직전에 논스탑 모드를 비활성화한다:

```bash
jq '.active=false | .phase="done"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

## 완료 보고

```markdown
## 긴급 수정 완료

### 심각도
[Critical/High/Medium] - [security 에이전트 평가 요약]

### 취약점
[취약점 설명]

### 수정
- `path/to/file.ext:line` - [패치 내용]

### 이중 리뷰 결과
- security: [PASS/WARN 요약]
- reviewer: [PASS/WARN 요약]

### 검증
- 회귀 테스트: N개 통과
- 보안 스캔: [결과 또는 "미실행"]
```
