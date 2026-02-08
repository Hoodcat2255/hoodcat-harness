# 시시포스(Sisyphus)의 Todo 기반 강제속행 메커니즘 조사 결과

> 조사일: 2026-02-08

## 개요

시시포스(Sisyphus)는 oh-my-opencode 프로젝트의 핵심 AI 에이전트 오케스트레이터로, "Todo Continuation Enforcer"라는 강제속행 메커니즘을 통해 LLM 에이전트가 작업을 중간에 포기하지 않고 끝까지 완료하도록 강제한다. 이름은 그리스 신화의 시시포스에서 따왔으며, 바위를 계속 굴리듯 에이전트가 모든 todo 항목을 완료할 때까지 멈추지 않는 것이 핵심 철학이다. 이 패턴은 LLM 에이전트의 고질적 문제인 "조기 완료 선언", "컨텍스트 오염", "작업 방기"를 구조적으로 해결한다.

## 상세 내용

### 1. 핵심 문제: LLM 에이전트의 3대 실패 모드

LLM 기반 코딩 에이전트가 자율적으로 작업할 때 발생하는 전형적인 실패 패턴:

1. **조기 완료 선언(Premature Completion)**: 에이전트가 작업이 끝나지 않았는데 "완료했습니다"라고 선언하는 현상. 테스트가 실패하거나 기능이 미구현인 상태에서 정지.
2. **컨텍스트 오염(Context Rot)**: 장시간 세션에서 이전 정보가 누적되어 에이전트의 판단력이 저하되는 현상. 토큰 한계에 도달하면서 초기 지시사항을 잊어버림.
3. **작업 방기(Task Abandonment)**: 에이전트가 어려운 작업에서 방향을 바꾸거나, 원래 작업과 무관한 탐색을 시작하는 현상.

### 2. Todo Continuation Enforcer의 작동 원리

oh-my-opencode의 `src/hooks/todo-continuation-enforcer.ts`에 구현된 핵심 메커니즘:

#### 이벤트 기반 감시 루프

```
session.idle 이벤트 감지
    │
    ├─ 메인 세션 또는 백그라운드 태스크 세션인지 확인
    ├─ 복구 중(recovering) 상태이면 건너뜀
    ├─ 에이전트가 abort(중단)된 경우 감지하여 건너뜀
    ├─ 백그라운드 태스크가 실행 중이면 건너뜀
    │
    ├─ todo 목록 조회
    ├─ 미완료 항목 수 계산
    │
    ├─ 미완료 항목 == 0 → 종료 허용
    ├─ 미완료 항목 > 0 → 카운트다운 시작 (2초)
    │                        │
    │                        └─ 카운트다운 종료 → session.prompt() 주입
    │                           "Incomplete tasks remain. Continue working."
    │
    └─ 사용자 메시지 감지 시 카운트다운 취소 (사용자 개입 우선)
```

#### 핵심 상수 및 설정

| 상수 | 값 | 설명 |
|------|-----|------|
| COUNTDOWN_SECONDS | 2 | 강제속행까지 대기 시간 |
| TOAST_DURATION_MS | 900 | UI 알림 표시 시간 |
| COUNTDOWN_GRACE_PERIOD_MS | 500 | 사용자 메시지 감지 유예 기간 |
| ABORT_WINDOW_MS | 3000 | abort 감지 후 무시 윈도우 |
| DEFAULT_SKIP_AGENTS | prometheus, compaction | 강제속행 제외 에이전트 |

#### 강제속행 프롬프트 구조

```
[시스템 지시문]
Incomplete tasks remain in your todo list. Continue working on the next pending task.
- Proceed without asking for permission
- Mark each task complete when finished
- Do not stop until all tasks are done

[Status: 3/7 completed, 4 remaining]

Remaining tasks:
- [in_progress] API 엔드포인트 구현
- [pending] 테스트 코드 작성
- [pending] 에러 핸들링 추가
- [pending] README 업데이트
```

### 3. 시시포스의 4단계 위상 워크플로우

#### Phase 0: Intent Gate (의도 판별)
모든 사용자 요청을 분류:
- Step 0: 스킬 매칭 확인
- Step 1: 요청 유형 분류 (trivial/explicit/exploratory/open-ended/ambiguous)
- Step 2: 모호성 검사
- Step 3: 가정 검증 및 도구/에이전트 선택

#### Phase 1: Codebase Assessment
개방형 작업 시 코드베이스 성숙도 평가

#### Phase 2: Pre-Delegation Planning (필수)
모든 `sisyphus_task` 호출 전:
- 작업을 3-5개 단계로 분해
- 각 단계별 필요 에이전트/도구 식별
- 의존성 매핑

#### Phase 3: Verification Loop
자가보고를 신뢰하지 않는 검증:
- `lsp_diagnostics`: 컴파일 오류 확인
- `bash` (테스트 실행): 테스트 스위트 실행
- `read` (파일 확인): 변경사항 실제 검증

### 4. 에이전트 위임 메커니즘

시시포스는 세 가지 방식으로 전문가 에이전트에 위임:

#### 카테고리 기반 위임
| 카테고리 | 온도 | 모델 | 용도 |
|----------|------|------|------|
| visual | 0.5 | Gemini | UI/UX 작업 |
| business-logic | 0.1 | Sonnet | 백엔드 로직 |
| general | 0.3 | Sonnet | 범용 작업 |

#### 전문 에이전트 직접 위임
- **Oracle**: 아키텍처/디버깅 (GPT 5.2)
- **Librarian**: 외부 문서/연구 (Claude Sonnet)
- **Explore**: 코드베이스 탐색 (AST 기반)
- **Frontend Engineer**: UI/UX (Gemini 3)

#### 병렬 백그라운드 실행
explore/librarian을 비차단(non-blocking)으로 백그라운드에서 실행하여 메인 에이전트 컨텍스트 절약

### 5. 안전장치와 반패턴 방지

| 반패턴 | 방지 메커니즘 |
|--------|---------------|
| 검증 없이 완료 선언 | Phase 3 검증 루프 (LSP/테스트/파일 확인) |
| Todo 생성 건너뜀 | TodoContinuationEnforcer 자동 감지 |
| 사전 계획 없이 실행 | Pre-Delegation Planning 필수화 |
| 무한 탐색 | 검색 정지 조건 |
| 사용자 abort 무시 | 이벤트 기반 + API 기반 이중 감지 |
| 복구 중 재진입 | isRecovering 플래그 |
| 쓰기 권한 없는 에이전트 속행 | 도구 권한 확인 |

### 6. 유사 패턴과의 비교

#### Ralph Wiggum Loop vs 시시포스 Todo Enforcer

| 측면 | Ralph Wiggum Loop | Sisyphus Todo Enforcer |
|------|-------------------|----------------------|
| **원리** | 외부 while 루프에서 반복 호출 | 내부 Hook에서 이벤트 기반 속행 |
| **컨텍스트** | 매 반복 초기화 (git이 메모리) | 세션 내 유지, todo가 상태 추적 |
| **제어** | completion promise / max iterations | 미완료 todo 기반 자동 판단 |
| **비용** | 매 반복 풀 컨텍스트 재입력 | 기존 세션 활용으로 효율적 |
| **정밀도** | 체크박스 기반 완료 판단 | todo API 기반 상태 관리 |
| **안전장치** | max-iterations 하드캡 | abort 감지, 사용자 개입 우선 |

#### Claude Code Native Tasks vs 시시포스

| 측면 | Claude Code Tasks | Sisyphus Todo Enforcer |
|------|-------------------|----------------------|
| **저장소** | ~/.claude/tasks 파일시스템 | OpenCode 세션 내장 |
| **세션 지속성** | 환경변수로 세션 간 공유 가능 | 세션 내 자동 관리 |
| **강제속행** | 없음 (사용자가 수동 속행) | 자동 속행 (2초 카운트다운) |
| **에이전트 연동** | TeammateTool / Swarm | 카테고리 기반 자동 위임 |

### 7. 실제 적용 시 고려사항

#### 토큰 비용 관리
- 자율 루프는 대규모 토큰을 소비한다. 50회 반복 루프는 $50-100+ 비용 발생 가능
- 시시포스는 백그라운드 에이전트를 저렴한 모델에 위임하여 비용 최적화
- Provider별 동시성 제한: provider당 3개, model당 2개, 전역 5개

#### 컨텍스트 윈도우 관리
- 토큰 사용량에 따른 단계적 대응이 필요
  - 초록 (60% 이하): 자유 작업
  - 노란 (60-80%): 마무리 준비
  - 빨강 (80% 이상): 강제 컨텍스트 교체
- Compaction 에이전트는 강제속행에서 제외 (skipAgents)

#### 검증 기준 설계
- 모호한 목표 ("좋은 코드 작성")는 강제속행에 부적합
- 테스트 통과, API 구현, 커버리지 달성 등 객관적 기준 필요
- PRD(Product Requirements Document) 형태로 기능 목록 작성 권장

## 코드 예제

### Claude Code에서의 간이 Todo 강제속행 구현 패턴

CLAUDE.md에 다음과 같은 규칙을 추가하는 방식으로 유사 효과를 낼 수 있다:

```markdown
## 작업 규칙

### Todo 리스트 필수
- 2단계 이상의 작업은 반드시 TodoCreate로 작업 목록 생성
- 각 작업 시작 시 in_progress로 표시
- 완료 시 completed로 표시
- 모든 작업이 completed가 될 때까지 작업 중단 금지

### 검증 필수
- 코드 변경 후 반드시 테스트 실행
- 테스트 실패 시 completed로 표시하지 말 것
- LSP 에러가 없는 상태에서만 작업 완료 처리
```

### Ralph Wiggum Loop 기본 구조 (Bash)

```bash
#!/bin/bash
MAX_ITERATIONS=20
ITERATION=0

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))
  echo "=== Iteration $ITERATION ==="

  claude -p "$(cat <<'EOF'
PRD.md를 읽고 미완료 항목을 확인하세요.
다음 미완료 항목 하나를 구현하세요.
테스트를 실행하고 통과하면 git commit하세요.
PRD.md에서 해당 항목을 완료 표시하세요.
모든 항목이 완료되면 <promise>COMPLETE</promise>를 출력하세요.
EOF
  )" --completion-promise "COMPLETE" --max-iterations 1

  if [ $? -eq 0 ]; then
    echo "All tasks completed!"
    break
  fi
done
```

### OpenCode oh-my-opencode 방식 (설치)

```bash
# OpenCode 설치 (미설치 시)
curl -fsSL https://opencode.ai/install | bash

# oh-my-opencode 플러그인 설치
bunx oh-my-opencode install

# ultrawork 키워드로 시시포스 활성화
# 프롬프트에 "ultrawork" 또는 "ulw" 포함 시 자동 활성화
```

## 주요 포인트

1. **Todo Continuation Enforcer는 이벤트 기반 Hook**: `session.idle` 이벤트를 감지하여 미완료 todo가 있으면 2초 카운트다운 후 자동으로 `session.prompt()`를 주입한다. 사용자 개입, abort, 복구 중 등의 상황을 정교하게 처리한다.

2. **구조가 지능보다 중요**: 에이전트 신뢰성의 핵심은 더 똑똑한 모델이 아니라 더 나은 구조이다. Todo 리스트, 검증 게이트, 강제속행의 조합이 프로덕션 실패의 80%를 방지한다.

3. **시시포스의 4단계 위상 워크플로우**: Intent Gate → Codebase Assessment → Pre-Delegation Planning → Verification Loop의 순서로 진행되며, 특히 Phase 3의 검증 루프가 "자가보고 신뢰 금지" 원칙을 구현한다.

4. **Ralph Loop과의 상호보완**: Ralph Wiggum Loop은 외부 반복(컨텍스트 초기화)에, 시시포스의 Todo Enforcer는 세션 내부 속행에 특화되어 있다. 두 패턴을 결합하면 컨텍스트 오염도 해결하고 작업 포기도 방지할 수 있다.

5. **비용과 안전의 균형**: 자율 실행은 토큰 비용이 크므로 max-iterations 하드캡, 토큰 사용량 기반 단계적 대응, 저렴한 모델로의 백그라운드 위임 등의 비용 최적화 전략이 필수적이다.

## 출처

- [Oh My OpenCode - Sisyphus Orchestrator (DeepWiki)](https://deepwiki.com/fractalmind-ai/oh-my-opencode/4.2-sisyphus-orchestrator)
- [Oh My OpenCode - Agent Orchestration Overview (DeepWiki)](https://deepwiki.com/code-yeongyu/oh-my-opencode/4.1-sisyphus-orchestrator)
- [Oh My OpenCode GitHub Repository](https://github.com/code-yeongyu/oh-my-opencode)
- [Sisyphus Agent Harness (switch-keys)](https://github.com/switch-keys/sisyphus)
- [Why Your AI Agents Need a Todo List - JustCopy.AI](https://blog.justcopy.ai/p/why-your-ai-agents-need-a-todo-list)
- [Self-Improving Coding Agents - Addy Osmani](https://addyosmani.com/blog/self-improving-agents/)
- [The Ralph Wiggum Technique - Awesome Claude](https://awesomeclaude.ai/ralph-wiggum)
- [Ralph Wiggum Loop vs Open Spec - RedReamality](https://redreamality.com/blog/ralph-wiggum-loop-vs-open-spec/)
- [2026 - The Year of the Ralph Loop Agent - DEV Community](https://dev.to/alexandergekov/2026-the-year-of-the-ralph-loop-agent-1gkj)
- [Effective Harnesses for Long-Running Agents - Anthropic](https://www.anthropic.com/engineering/effective-harnesses-for-long-running-agents)
- [Boost AI Agent Reliability with Stateful Todo Lists - WebProNews](https://www.webpronews.com/boost-ai-agent-reliability-with-stateful-todo-lists/)
- [Claude Code Tasks - VentureBeat](https://venturebeat.com/orchestration/claude-codes-tasks-update-lets-agents-work-longer-and-coordinate-across)
- [Claude Code Todos to Tasks - Medium](https://medium.com/@richardhightower/claude-code-todos-to-tasks-5a1b0e351a1c)
- [How Agents Plan Tasks with To-Do Lists - Towards Data Science](https://towardsdatascience.com/how-agents-plan-tasks-with-to-do-lists/)
- [todo-continuation-enforcer.ts 소스코드](https://github.com/code-yeongyu/oh-my-opencode/blob/dev/src/hooks/todo-continuation-enforcer.ts)
