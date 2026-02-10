---
name: new-project
description: |
  End-to-end workflow for building a new project or major feature from scratch.
  Orchestrates planning, research, implementation, testing, and deployment.
  Triggers on: "새 프로젝트", "처음부터 만들어", "new-project", or any request
  to build something new from the ground up.
argument-hint: "<프로젝트 또는 기능 설명>"
user-invocable: true
---

# New Project Workflow

## 트리거 조건

새로운 프로젝트나 대규모 기능을 처음부터 구축할 때 사용한다.
기존 코드 개선은 /improve, 버그 수정은 /bugfix를 사용한다.

## DO/REVIEW 시퀀스

$ARGUMENTS를 기반으로 다음 단계를 논스탑으로 순차 실행한다.
각 단계에서 BLOCK이 반환되면 수정 후 재리뷰한다. 최대 2회 재시도 후에도 BLOCK이면 사용자에게 판단을 요청한다.

### Phase 0: Sisyphus 관리

Sisyphus 상태를 확인한다:

```bash
ACTIVE=$(jq -r '.active' .claude/flags/sisyphus.json 2>/dev/null || echo "false")
```

- **`active=false`** (최상위 호출): Sisyphus를 활성화한다 (maxIterations=20). 이후 종료 시 비활성화 책임이 있다.
  ```bash
  jq --arg wf "new-project" --arg ts "$(date -Iseconds)" \
    '.active=true | .workflow=$wf | .maxIterations=20 | .currentIteration=0 | .startedAt=$ts | .phase="init"' \
    .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
  ```

- **`active=true`** (서브워크플로우): 활성화를 건너뛴다. 부모 워크플로우가 Sisyphus 생명주기를 관리한다.

### Phase 1: 기획

```bash
jq '.phase="planning"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

```
DO: Skill("blueprint", "$ARGUMENTS")
```

/blueprint이 산출물을 생성하면, architect 에이전트에게 리뷰를 요청한다:

```
REVIEW: Task(architect): "docs/plans/{project-name}/architecture.md를 리뷰하라. 구조가 적합한가?"
```

- PASS/WARN → Phase 2로 진행
- BLOCK → /blueprint 산출물 수정 후 재리뷰

### Phase 2: 기술조사 (필요시)

```bash
jq '.phase="research"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

/blueprint 과정에서 기술 선택이 불확실한 경우에만 실행한다:

```
DO: Skill("deepresearch", "<조사 주제>")
REVIEW: Task(architect): "조사 결과를 바탕으로, 이 기술 선택이 아키텍처에 적합한가?"
```

- PASS/WARN → Phase 3로 진행
- BLOCK → 대안 기술 조사 후 재리뷰

### Phase 3: 개발

```bash
jq '.phase="development"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

/blueprint이 생성한 tasks.md의 태스크를 구현한다.

**병렬 개발 판단**: tasks.md의 태스크 의존성을 분석하여 실행 방식을 결정한다:

#### 3a: 에이전트팀 병렬 개발 (독립 태스크 3개 이상인 경우)

파일 소유권이 겹치지 않는 독립 태스크가 3개 이상이면 에이전트팀을 사용한다:

```
1. TeamCreate("dev-team")

2. tasks.md에서 의존성 없는 태스크 그룹 식별
   - 각 태스크의 대상 파일 목록을 명시하여 파일 충돌 방지

3. 각 독립 태스크에 대해:
   TaskCreate({
     subject: "태스크 제목",
     description: "상세 설명 + 소유할 파일 목록",
     activeForm: "구현 중..."
   })

4. 의존 태스크에 대해:
   TaskCreate({...})
   TaskUpdate({ addBlockedBy: ["선행 태스크 ID"] })

5. 독립 태스크 수만큼 팀원 스폰 (최대 5명):
   Task(team_name="dev-team", name="dev-N"):
     "태스크 N을 구현하라. 소유 파일: [파일 목록].
      다른 팀원의 파일은 절대 수정하지 마라.
      CLAUDE.md의 코딩 컨벤션을 준수하라.
      완료 후 TaskUpdate로 completed 처리하라."

6. 리드는 TaskList로 진행 상황을 모니터링
   - TaskCompleted 훅이 각 태스크 빌드/테스트 자동 검증
   - TeammateIdle 훅이 미완료 팀원에게 작업 재개 유도

7. 모든 태스크 완료 후:
   - 통합 빌드/테스트 실행
   - 리뷰 수행 (아래 공통 리뷰 참조)
   - SendMessage(type="shutdown_request")로 팀원 종료
   - TeamDelete로 정리
```

#### 3b: 순차 개발 (독립 태스크 2개 이하인 경우)

기존 방식으로 태스크를 순서대로 구현한다:

```
tasks.md의 각 태스크에 대해:
  DO: Skill("implement", "<태스크 설명>")
```

#### 공통 리뷰 (3a, 3b 모두)

```
REVIEW: Task(reviewer): "구현된 코드의 품질을 리뷰하라"
```

인증, 데이터 처리, 외부 입력 관련 태스크인 경우 security 리뷰도 추가:

```
REVIEW: Task(security): "보안 관점에서 리뷰하라"
```

- PASS/WARN → 다음 태스크(3b) 또는 Phase 4(3a)로 진행
- BLOCK → 해당 태스크 수정 후 재리뷰

### Phase 4: QA

```bash
jq '.phase="qa"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

모든 구현이 완료되면 테스트를 실행한다.
**검증 규칙**: 빌드/테스트 결과는 실제 명령어의 exit code로만 판단한다. 텍스트 보고("통과했습니다")를 신뢰하지 않는다.

```
DO: Skill("test", "<전체 또는 변경된 모듈>")
```

- 전체 통과 → Phase 5로 진행
- 실패 있음 → 자동으로 수정 시도:
  ```
  DO: Skill("fix", "<실패한 테스트 에러 메시지>")
  DO: Skill("test", "--regression")
  ```
  재테스트 후에도 실패하면 사용자에게 보고

### Phase 5: 배포 (선택)

```bash
jq '.phase="deploy"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

사용자가 배포를 요청한 경우에만 실행:

```
DO: Skill("deploy", "<배포 환경>")  (Phase 4에서 구현 예정)
REVIEW: Task(security): "배포 설정이 안전한가?"
```

배포 스킬이 아직 없으면 이 단계를 건너뛰고 사용자에게 알린다.

## 종료 조건

다음 중 하나를 만족하면 워크플로우가 완료된다:
1. 모든 Phase가 성공적으로 완료
2. 배포 없이 QA까지 통과 (배포 미요청 시)
3. 사용자가 중단을 요청

## Sisyphus 비활성화

이 워크플로우가 Sisyphus를 직접 활성화한 경우(최상위 호출)에만 비활성화한다:

```bash
jq '.active=false | .phase="done"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```
서브워크플로우로 호출된 경우 비활성화를 건너뛴다.

## 완료 보고

```markdown
## 프로젝트 완료: {project-name}

### 실행된 단계
- [x] 기획: docs/plans/{project-name}/
- [x] 기술조사: (실행 여부)
- [x] 개발: N개 태스크 구현
- [x] QA: N개 테스트 통과
- [ ] 배포: (실행 여부)

### 리뷰 결과 요약
- architect: PASS/WARN (N건)
- reviewer: PASS/WARN (N건)
- security: PASS/WARN (N건)

### 생성된 파일
[목록]
```
