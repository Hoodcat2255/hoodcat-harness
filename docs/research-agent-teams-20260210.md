# Claude Code 에이전트팀(TeamCreate/SendMessage) 활용 사례 및 hoodcat-harness 도입 가능 영역 조사

> 조사일: 2026-02-10 (2차 심화 조사: hoodcat-harness 도입 분석 포함)

## 개요

Claude Code Agent Teams는 실험적 기능으로, 여러 Claude Code 인스턴스가 공유 태스크 리스트, 직접 메시징(SendMessage), 팀 리드 조율을 통해 협업하는 멀티세션 오케스트레이션 시스템이다. 기존 서브에이전트(Task)가 단방향 결과 보고만 가능한 것과 달리, 에이전트팀의 팀원들은 서로 직접 통신하고 자율적으로 태스크를 클레임하여 작업할 수 있다. hoodcat-harness 프로젝트는 이미 `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` 설정이 활성화되어 있어 즉시 도입이 가능하며, 기존 서브에이전트 기반 워크플로우(implement, bugfix, improve, new-project, hotfix)를 에이전트팀으로 확장하면 병렬 처리, 컨텍스트 격리, 전문화된 협업에서 유의미한 개선을 얻을 수 있다.

## 상세 내용

### 1. Agent Teams vs Subagents: 핵심 차이점

| 항목 | Subagents (현재 hoodcat-harness) | Agent Teams |
|------|----------------------------------|-------------|
| **컨텍스트** | 자체 컨텍스트 윈도우, 결과만 호출자에게 반환 | 자체 컨텍스트 윈도우, 완전 독립 |
| **통신** | 메인 에이전트에게만 결과 보고 | 팀원 간 직접 메시징(SendMessage) |
| **조율** | 메인 에이전트가 모든 작업 관리 | 공유 태스크 리스트로 자율 조율 |
| **적합한 작업** | 결과만 중요한 집중 작업 | 토론과 협업이 필요한 복잡한 작업 |
| **토큰 비용** | 낮음: 결과가 요약되어 반환 | 높음: 각 팀원이 별도 Claude 인스턴스 |

**핵심 판단 기준**: 작업자들이 서로 통신해야 하는가? 단방향 결과 보고만 필요하면 서브에이전트, 팀원 간 발견 공유/상호 검증/자율 조율이 필요하면 에이전트팀을 사용한다.

### 2. 에이전트팀의 7가지 핵심 프리미티브

1. **TeamCreate**: 팀 네임스페이스 및 설정 디렉토리 초기화 (`~/.claude/teams/{team-name}/config.json`)
2. **TaskCreate**: 디스크의 JSON 파일로 작업 단위 정의 (`~/.claude/tasks/{team-name}/`)
3. **TaskUpdate**: 팀원이 태스크 클레임(owner 설정) 및 완료 처리, 의존성(blockedBy) 관리
4. **TaskList**: 모든 태스크 상태(pending/in_progress/completed) 확인
5. **Task (team_name + name 파라미터)**: 개별 팀원 스폰 (persistent team member)
6. **SendMessage**: 팀원 간 직접 통신 (message, broadcast, shutdown_request/response, plan_approval_response)
7. **TeamDelete**: 작업 완료 후 팀 인프라 제거 (active member가 있으면 실패)

### 3. 실증된 강력한 활용 사례

#### 3.1 병렬 코드 리뷰 (Multi-Lens Review)
단일 리뷰어는 한 번에 한 유형의 이슈에 집중하는 경향이 있다. 리뷰 기준을 독립적 도메인으로 분할하면 보안, 성능, 테스트 커버리지가 동시에 철저한 검토를 받는다.

```
3명의 리뷰어 스폰:
- 보안 관점 리뷰어
- 성능 영향 리뷰어
- 테스트 커버리지 검증 리뷰어
→ 각 리뷰어가 독립 리뷰 후 SendMessage로 상호 보충 의견 제시
→ 리드가 최종 종합 리포트 생성
```

#### 3.2 경쟁 가설 디버깅 (Competing Hypotheses)
단일 에이전트는 하나의 그럴듯한 설명을 찾으면 탐색을 멈추는 경향(앵커링)이 있다. 여러 팀원이 각자의 이론을 조사하면서 동시에 다른 팀원의 이론에 도전하는 적대적 구조가 핵심이다. 살아남는 이론이 실제 근본 원인일 가능성이 훨씬 높다.

#### 3.3 크로스레이어 기능 개발
프론트엔드, 백엔드, 테스트를 각각 다른 팀원이 소유하여 컨텍스트 스위칭 오버헤드를 제거한다. 각 팀원이 독립적 Git Worktree에서 작업하여 코드 충돌을 방지하는 구조.

#### 3.4 연구 및 탐색 (Research Swarm)
여러 팀원이 서로 다른 접근법을 동시에 조사하고, 발견을 직접 공유하며, 최적 경로로 수렴한다.

#### 3.5 QA 스웜
실증 사례에서 5개 병렬 QA 에이전트가 동시에 서로 다른 유형의 테스트를 실행하여 포괄적 검증을 수행:
- qa-pages: URL HTTP 상태 코드 검증
- qa-posts: 블로그 포스트 메타데이터 테스트
- qa-links: 내부 URL 깨진 링크 확인
- qa-seo: RSS, robots.txt, 구조화 데이터 검증
- qa-a11y: 접근성 및 HTML 구조 평가

### 4. 성능 이점 및 비용 트레이드오프

**이점**:
- **컨텍스트 활용**: 단일 에이전트는 컨텍스트 윈도우의 80-90%를 소비하지만, 팀 오케스트레이션은 약 40%만 사용 (각 팀원이 자체 컨텍스트 보유)
- **병렬 처리**: 독립적 작업의 동시 실행으로 전체 소요 시간 단축
- **전문화**: 도메인별 전문 에이전트가 범용 에이전트보다 나은 결과 산출

**비용**:
- 각 팀원이 별도 Claude 인스턴스이므로, 5인 팀은 단일 세션의 약 5배 토큰을 사용
- 멀티에이전트 시스템은 일반적으로 동일 작업에 대해 3-10배 더 많은 토큰을 소비
- 조율 오버헤드(메시지 교환, 태스크 관리)가 추가됨

### 5. 주의사항 및 함정

#### 5.1 작업 분해 방식 (Anthropic 권장: Context-Centric)
- **잘못된 방식 (Problem-Centric)**: 작업 유형으로 분할 (기능 작성 에이전트 / 테스트 작성 에이전트 / 리뷰 에이전트) → 핸드오프마다 컨텍스트 손실
- **올바른 방식 (Context-Centric)**: 컨텍스트 경계로 분할 (기능 A를 담당하는 에이전트가 해당 테스트도 작성) → 컨텍스트 보존

#### 5.2 파일 충돌
두 팀원이 같은 파일을 동시에 편집하면 덮어쓰기 발생. CLAUDE.md에 명시적 파일 소유권 규칙을 추가해야 한다.

#### 5.3 태스크 크기
- 너무 작으면: 조율 오버헤드가 이점을 초과
- 너무 크면: 팀원이 체크인 없이 너무 오래 작업하여 낭비 위험 증가
- 적정: 명확한 산출물을 생산하는 자체 완결적 단위 (팀원당 5-6개 태스크가 적합)

#### 5.4 리드의 직접 구현 문제
리드가 팀원을 기다리지 않고 직접 구현을 시작하는 경우 발생. **Delegate Mode** (Shift+Tab)로 리드를 조율 전용으로 제한 가능.

#### 5.5 알려진 제한사항
- 세션 재개 시 인프로세스 팀원 복원 불가 (/resume, /rewind)
- 태스크 상태가 지연될 수 있음 (팀원이 완료 표시를 놓치는 경우)
- 세션당 하나의 팀만 관리 가능
- 중첩 팀 불가 (팀원이 자체 팀 생성 불가)
- 리드 고정 (리더십 이전 불가)
- 권한이 스폰 시 리드 설정 상속

### 6. 고급 기능

#### 6.1 계획 승인 워크플로우 (Plan Approval)
고위험 작업에서 팀원이 구현 전에 계획을 제출하도록 요구. 리드가 계획을 검토하고 승인/거부. 거부 시 피드백과 함께 수정 요청.

#### 6.2 훅을 통한 품질 게이트
- **TeammateIdle**: 팀원이 유휴 상태로 전환될 때 실행. Exit code 2로 피드백 전송 및 작업 계속.
- **TaskCompleted**: 태스크 완료 표시 시 실행. Exit code 2로 완료 차단 및 피드백 전송.

#### 6.3 디스플레이 모드
- **In-process** (기본): 메인 터미널에서 모든 팀원 실행, Shift+Up/Down으로 팀원 전환
- **Split panes**: tmux/iTerm2로 각 팀원에게 전용 패인 제공

### 7. Anthropic의 멀티에이전트 도입 판단 기준

Anthropic은 멀티에이전트 시스템 도입 전 단일 에이전트부터 시작할 것을 권장한다. 다음 3가지 시나리오에서만 멀티에이전트가 효과적이다:

1. **컨텍스트 오염 방지**: 한 작업의 무관한 정보가 다른 작업 성능을 저하시킬 때
2. **병렬화**: 여러 에이전트가 다른 측면을 동시 조사할 수 있을 때
3. **전문화**: 20개 이상 도구 관리, 무관한 도메인 간 혼동, 도구 추가 시 성능 저하가 발생할 때

**핵심 원칙**: 문제 유형이 아닌 컨텍스트 경계를 기준으로 작업을 분할하라.

### 8. 프레임워크/패턴 비교

| 프레임워크 | 핵심 특징 | 적합 용도 |
|-----------|----------|----------|
| **Claude Code Agent Teams** | 실시간 팀 협업, 공유 태스크, SendMessage | 개발 워크플로우 병렬화 |
| **Claude Code Subagents** | 단방향 결과 보고, 가벼운 포크 | 집중 작업 위임 |
| **LangGraph** | 그래프 기반 상태 관리, DAG 워크플로우 | 복잡한 상태 관리 |
| **Google ADK** | 8대 패턴, 풍부한 프리미티브 | 엔터프라이즈급 멀티에이전트 |

---

## hoodcat-harness 프로젝트 도입 가능 영역 분석

### 현재 아키텍처 평가

hoodcat-harness는 이미 정교한 서브에이전트 기반 워크플로우를 갖추고 있다:
- **에이전트 4개**: architect, reviewer, security, navigator (전부 opus, read-only tools)
- **워크플로우 스킬 5개**: implement, bugfix, improve, new-project, hotfix
- **Sisyphus 논스탑 메커니즘**: Stop Hook 기반 강제속행
- **DO/REVIEW 시퀀스**: 순차적 서브에이전트 호출 패턴
- **이미 활성화**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` (settings.json)

현재 워크플로우의 **구조적 한계**:
1. 리뷰가 서브에이전트 수준 병렬 (run_in_background=true 사용하지만 상호 통신 불가)
2. /new-project Phase 3에서 다중 태스크가 순차 실행 (`Skill("implement", ...)` 반복)
3. 팀원 간 직접 통신 불가 (모든 정보가 워크플로우 오케스트레이터를 경유)
4. 컨텍스트 윈도우가 워크플로우 Phase 진행 중 계속 팽창

### 도입 영역 1: /new-project 워크플로우의 병렬 개발 (HIGH IMPACT)

**현재**: Phase 3에서 tasks.md의 태스크를 순차적으로 `Skill("implement", ...)` 호출
**개선**: 독립적 태스크를 에이전트팀으로 병렬 구현

```
Phase 3 (개선안):
1. TeamCreate로 개발팀 생성
2. tasks.md에서 의존성이 없는 태스크 그룹 식별
3. 각 독립 태스크에 팀원 할당 (각 팀원이 자체 파일 소유)
4. 의존성 있는 태스크는 TaskUpdate의 blockedBy로 관리
5. 모든 팀원 작업 완료 후 리드가 통합 검증
6. TeamDelete로 정리
```

**예상 이점**: 독립 태스크 3-5개를 동시 구현하면 개발 Phase 소요 시간 60-70% 단축
**적합 조건**: /design이 태스크를 충분히 세분화하고 파일 소유권이 명확할 때
**Sisyphus 통합**: 팀 리드가 Phase 상태를 관리하되, 각 팀원의 완료는 TaskCompleted 훅으로 검증

### 도입 영역 2: 멀티렌즈 코드 리뷰 스킬 신규 생성 (HIGH IMPACT)

**현재**: implement의 Phase 6에서 reviewer/security를 서브에이전트로 병렬 호출 (단방향, 상호 피드백 불가)
**개선**: 에이전트팀 기반 토론형 리뷰

```
/team-review 스킬 (신규):
1. TeamCreate로 리뷰팀 생성
2. 3명의 리뷰어 스폰:
   - reviewer: 코드 품질 관점
   - security: 보안 관점
   - architect: 구조적 관점
3. 각 리뷰어가 독립 리뷰 후 SendMessage로 상호 피드백
4. 리뷰어 간 이견이 있으면 토론을 통해 합의 도출
5. 리드가 최종 종합 리포트 생성 (PASS/WARN/BLOCK)
```

**예상 이점**: 단일 관점 리뷰 대비 더 깊이 있는 다면적 검증. 리뷰어 간 상호작용으로 놓치는 이슈 감소.
**주의**: 비용이 높으므로 대규모 변경이나 고위험 코드에만 적용. 일상적 리뷰는 기존 서브에이전트 방식 유지.

### 도입 영역 3: /bugfix의 경쟁 가설 디버깅 (MEDIUM IMPACT)

**현재**: /fix 스킬이 단일 에이전트로 순차 진단 (navigator 호출 → 원인 진단 → 패치)
**개선**: 복잡한 버그에 대해 에이전트팀으로 경쟁 가설 동시 조사

```
/bugfix 개선안 (복잡 버그 감지 시):
Phase 1에서 버그 복잡도 판단:
  - 단순 (에러 메시지 명확, 단일 파일): 기존 /fix 서브에이전트 호출
  - 복잡 (재현 어려움, 원인 불명확, 다중 모듈 관련):
    1. TeamCreate로 디버깅팀 생성
    2. 3-5명의 디버거가 각각 다른 가설 조사
    3. SendMessage로 가설 간 상호 반박
    4. 살아남은 가설의 팀원이 수정 구현
```

**적합 조건**: 원인이 불명확하고 재현이 어려운 복잡한 버그
**비적합**: 명확한 에러 메시지가 있는 단순 버그 (기존 서브에이전트가 효율적)

### 도입 영역 4: QA 스웜 스킬 신규 생성 (MEDIUM IMPACT)

**현재**: /test 스킬이 단일 에이전트로 테스트 실행
**개선**: 에이전트팀 기반 병렬 QA

```
/qa-swarm 스킬 (신규):
1. TeamCreate로 QA팀 생성
2. 테스트 유형별 팀원 스폰:
   - 단위 테스트 실행
   - 통합 테스트 실행
   - 린트/정적 분석
   - 보안 스캔 (security-scan 스킬 활용)
3. 모든 팀원 결과 종합
4. 실패 항목에 대한 수정 권고
```

**적합 조건**: 대규모 프로젝트에서 테스트 스위트가 다양할 때
**Sisyphus 통합**: /new-project의 Phase 4(QA)에서 단일 test 호출 대신 qa-swarm 호출

### 도입 영역 5: TeammateIdle/TaskCompleted 훅으로 품질 게이트 강화 (LOW EFFORT, HIGH VALUE)

**현재**: Sisyphus의 Stop Hook으로 워크플로우 속행 관리, verify-build-test.sh 유틸리티 존재
**추가**: 에이전트팀 전용 훅으로 품질 검증 자동화

```json
// settings.json 훅 추가안
{
  "hooks": {
    "TaskCompleted": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/hooks/task-quality-gate.sh"
      }]
    }],
    "TeammateIdle": [{
      "matcher": "",
      "hooks": [{
        "type": "command",
        "command": ".claude/hooks/teammate-idle-check.sh"
      }]
    }]
  }
}
```

**이점**: 비용 증가 없이 기존 Sisyphus 품질 게이트를 에이전트팀으로 확장

### 도입 영역 6: /deepresearch의 병렬 조사팀 (LOW IMPACT)

**현재**: 단일 에이전트가 WebSearch 병렬 호출 후 순차 분석 (이미 효과적)
**개선**: 에이전트팀으로 분야별 조사원 스폰

**주의**: 현재 deepresearch가 이미 5-7개 병렬 WebSearch를 효과적으로 활용하므로, 에이전트팀 도입 시 개선 폭이 제한적이며 비용 대비 효과가 낮을 수 있음. 우선순위가 가장 낮음.

### 도입 우선순위 권고

| 순위 | 영역 | 영향도 | 구현 난이도 | 비용 증가 |
|------|------|--------|-------------|-----------|
| 1 | TeammateIdle/TaskCompleted 훅 | 높음 | 낮음 | 없음 |
| 2 | /new-project 병렬 개발 | 높음 | 중간 | 높음 |
| 3 | 멀티렌즈 리뷰 스킬 (/team-review) | 높음 | 중간 | 중간 |
| 4 | 경쟁 가설 디버깅 (/bugfix 확장) | 중간 | 중간 | 높음 |
| 5 | QA 스웜 (/qa-swarm) | 중간 | 중간 | 중간 |
| 6 | deepresearch 병렬 조사 | 낮음 | 중간 | 높음 |

## 코드 예제

### 에이전트팀 활성화 설정 (hoodcat-harness에 이미 적용됨)

```json
// ~/.claude/settings.json (이미 설정됨)
{
  "env": {
    "CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS": "1"
  }
}
```

### /new-project Phase 3 병렬 개발 패턴 (의사코드)

```
Phase 3: 개발 (에이전트팀 버전)

1. tasks.md 파싱하여 태스크 의존성 그래프 생성
2. TeamCreate("dev-team")
3. 독립 태스크 그룹 식별 (blockedBy가 비어있는 태스크들)

4. 각 독립 태스크에 대해:
   TaskCreate({
     subject: "태스크 제목",
     description: "상세 설명 + 소유할 파일 목록 + CLAUDE.md 규칙 준수 지시",
     activeForm: "구현 중..."
   })

5. 의존 태스크에 대해:
   TaskCreate({...})
   TaskUpdate({ addBlockedBy: ["선행 태스크 ID"] })

6. 독립 태스크 수만큼 팀원 스폰:
   Task(team_name="dev-team", name="dev-1", subagent_type="general-purpose"):
     "tasks.md의 태스크 1을 구현하라. 소유 파일: [파일 목록].
      다른 팀원의 파일은 절대 수정하지 마라.
      완료 후 TaskUpdate로 completed 처리하라."

7. 리드는 Delegate Mode로 조율만 담당
8. TaskCompleted 훅이 각 태스크 완료 시 빌드/테스트 검증
9. 모든 태스크 완료 후:
   - 통합 빌드/테스트 실행
   - SendMessage(type="shutdown_request")로 팀원 종료
   - TeamDelete로 정리
```

### 멀티렌즈 리뷰 패턴 (/team-review 스킬 초안)

```
/team-review 스킬:

1. TeamCreate("review-team")

2. TaskCreate 3개:
   - "코드 품질 리뷰" (reviewer 관점)
   - "보안 리뷰" (security 관점)
   - "아키텍처 리뷰" (architect 관점)

3. 팀원 3명 스폰 (각각 해당 에이전트 정의 기반):
   Task(team_name="review-team", name="quality-reviewer"):
     "변경된 파일들의 코드 품질을 리뷰하라.
      리뷰 완료 후 다른 리뷰어에게 SendMessage로 주요 발견 공유.
      다른 리뷰어의 메시지를 받으면 보충 의견 제시."

4. 리뷰어들이 각자 리뷰 후 SendMessage로 상호 피드백
5. 리드가 최종 verdict 종합 (PASS/WARN/BLOCK)
6. SendMessage(type="shutdown_request") → TeamDelete
```

### TaskCompleted 품질 게이트 훅

```bash
#!/bin/bash
# .claude/hooks/task-quality-gate.sh
# TaskCompleted 훅: 태스크 완료 전 빌드/테스트 자동 검증

input=$(cat)
task_subject=$(echo "$input" | jq -r '.task.subject // ""')

# 구현 태스크인 경우만 검증
if echo "$task_subject" | grep -qiE '구현|implement|개발|develop'; then
  if [ -f ".claude/hooks/verify-build-test.sh" ]; then
    result=$(.claude/hooks/verify-build-test.sh 2>&1)
    if [ $? -ne 0 ]; then
      echo "빌드/테스트 검증 실패. 태스크 완료를 차단합니다: $result"
      exit 2  # exit 2 = 완료 차단 + 피드백 전송
    fi
  fi
fi

exit 0
```

## 주요 포인트

1. **에이전트팀은 서브에이전트의 보완 관계이지 상위 호환이 아니다**: 단순한 작업에는 서브에이전트가 더 효율적이며, 에이전트팀은 병렬 탐색이 실질적 가치를 더하는 경우에만 사용해야 한다.

2. **hoodcat-harness는 즉시 도입 가능**: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1`이 이미 활성화되어 있고, 기존 Sisyphus 메커니즘/DO-REVIEW 시퀀스와의 통합이 핵심 과제이다.

3. **Context-Centric 분해가 필수적**: 기능 A를 담당하는 팀원이 해당 테스트도 작성해야 하며, "코딩 에이전트/테스트 에이전트/리뷰 에이전트"로 나누면 핸드오프 시 컨텍스트 손실이 발생한다 (Anthropic 공식 권장).

4. **비용은 팀원 수에 비례하므로 선택적 적용이 경제적**: 일상적 작업에는 기존 서브에이전트를 유지하고, 대규모 병렬 작업(new-project의 다중 태스크 구현, 멀티렌즈 리뷰, 복잡 버그 디버깅)에만 에이전트팀을 적용한다.

5. **TeammateIdle/TaskCompleted 훅이 가장 효율적인 첫 도입 지점**: 비용 증가 없이 기존 Sisyphus 품질 게이트를 에이전트팀으로 확장할 수 있으며, 기존 verify-build-test.sh를 재활용할 수 있다.

## 출처

- [Orchestrate teams of Claude Code sessions - 공식 문서](https://code.claude.com/docs/en/agent-teams)
- [Claude Code Swarms - Addy Osmani](https://addyosmani.com/blog/claude-code-agent-teams/)
- [From Tasks to Swarms: Agent Teams in Claude Code - alexop.dev](https://alexop.dev/posts/from-tasks-to-swarms-agent-teams-in-claude-code/)
- [Claude Code Swarm Orchestration Skill - Kieran Klaassen (GitHub Gist)](https://gist.github.com/kieranklaassen/4f2aba89594a4aea4ad64d753984b2ea)
- [When to Use Multi-Agent Systems - Anthropic 공식 블로그](https://claude.com/blog/building-multi-agent-systems-when-and-how-to-use-them)
- [wshobson/agents - Multi-agent orchestration for Claude Code (GitHub)](https://github.com/wshobson/agents)
- [Claude Code multiple agent systems: Complete 2026 guide - eesel.ai](https://www.eesel.ai/blog/claude-code-multiple-agent-systems-complete-2026-guide)
- [Claude Code Agent Teams: Multi-Session Orchestration - claudefast](https://claudefa.st/blog/guide/agents/agent-teams)
- [How to Set Up and Use Claude Code Agent Teams - Medium](https://darasoba.medium.com/how-to-set-up-and-use-claude-code-agent-teams-and-actually-get-great-results-9a34f8648f6d)
- [PermissionRequest hooks not triggered for subagent in Agent Teams - GitHub Issue](https://github.com/anthropics/claude-code/issues/23983)
