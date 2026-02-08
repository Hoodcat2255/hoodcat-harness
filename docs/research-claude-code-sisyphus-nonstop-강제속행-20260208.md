# Claude Code Sisyphus 스타일 논스탑 강제속행 구현 가능성 조사

> 조사일: 2026-02-08

## 개요

Claude Code에서 Sisyphus 스타일의 논스탑 강제속행(자동으로 작업을 계속하며 멈추지 않는 패턴)을 구현하는 방법을 조사했다. 핵심은 **Stop Hook**을 활용한 exit 차단 메커니즘이며, 이를 공식 플러그인화한 **Ralph Wiggum**이 anthropics/claude-code 레포에 존재한다. 다만 Task 도구의 model 파라미터 버그(haiku/sonnet 라우팅 불가)가 2026년 2월 현재까지 미해결 상태이며, 무한 루프 방지를 위한 iteration 제한 설계가 필수적이다.

## 상세 내용

### 1. Hook 시스템으로 session.idle 감지 및 자동 재개

Claude Code의 Hook 시스템은 **14개 라이프사이클 이벤트**를 지원한다:

| 이벤트 | 용도 |
|--------|------|
| `Stop` | **메인 에이전트가 응답 완료 시** 실행. `decision: "block"`으로 종료 차단 가능 |
| `SubagentStop` | 서브에이전트 종료 시 실행. 동일하게 block 가능 |
| `Notification` | `idle_prompt` 매처로 유휴 상태 감지 가능 |
| `TeammateIdle` | Agent Team 동료가 유휴 상태로 전환될 때 실행 |
| `TaskCompleted` | 태스크 완료 시 검증 게이트로 사용 가능 |

**Stop Hook이 핵심 메커니즘이다.** exit code 2를 반환하거나 JSON으로 `{"decision": "block", "reason": "..."}`을 출력하면 Claude가 멈추지 않고 계속 작업한다.

중요한 안전장치: Stop Hook의 입력에 `stop_hook_active: true` 필드가 포함되어, 이미 Stop Hook에 의해 계속 실행 중인지 확인할 수 있다. 이를 체크하지 않으면 무한 루프에 빠진다.

```json
{
  "Stop": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Verify task completion: tests run, build succeeded. Return 'approve' to stop or 'block' with reason to continue."
        }
      ]
    }
  ]
}
```

**Notification 이벤트의 `idle_prompt` 매처**로 유휴 상태를 감지할 수 있지만, 이는 알림 목적이며 직접적인 재개 메커니즘은 아니다. 자동 재개의 핵심은 Stop Hook이다.

### 2. TaskCreate/TaskList로 todo 기반 강제속행 구현

Claude Code의 Task 시스템은 **세션 범위 태스크 관리**를 지원한다:

- `TaskCreate`: 태스크 생성 (subject, description, activeForm 필드)
- `TaskList`: 전체 태스크 목록 조회
- `TaskUpdate`: 상태 변경 (pending → in_progress → completed)
- `addBlockedBy`: 태스크 간 의존성 체인 설정

**강제속행 패턴 구현 방법:**

1. **스킬에서 TaskCreate로 작업 목록 생성** → 모든 하위 작업을 pending으로 등록
2. **Stop Hook에서 TaskList 확인** → pending/in_progress 태스크가 남아있으면 block
3. **TaskCompleted Hook으로 검증 게이트** → 태스크 완료 시 빌드/테스트 통과 여부 확인

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "agent",
          "prompt": "Check TaskList. If any tasks are pending or in_progress, return {\"ok\": false, \"reason\": \"Tasks remaining: [list]\"}. If all completed, return {\"ok\": true}.",
          "timeout": 60
        }
      ]
    }
  ]
}
```

**태스크 디스크 영속성**: 태스크는 디스크에 저장되어 세션 간 공유가 가능하다. 환경변수 설정으로 여러 Claude 세션이 동일 태스크 목록을 참조할 수 있다.

### 3. subagent Task에서 model 파라미터 라우팅

**공식 문서상 지원 사양:**

서브에이전트의 `model` 필드는 다음 값을 허용한다:
- `haiku` - 빠르고 저렴 (Explore 기본값)
- `sonnet` - 균형
- `opus` - 최대 성능
- `inherit` - 부모 모델 상속 (기본값)

**현실: 버그로 인해 동작하지 않음**

- GitHub Issue #18873, #16115, #11682: Task 도구의 `model` 파라미터가 Claude Code 2.1.12+ 이후 완전히 고장
- 짧은 모델명("haiku", "sonnet") → CLI 검증 통과 → API에서 404 에러
- 전체 모델 ID("claude-haiku-4-5-20251001") → CLI 검증 실패
- 2026년 2월 현재까지 미해결 (4개월 이상)
- 2026년 2월 릴리즈(2.1.25~2.1.37)에서도 수정 미포함

**YAML frontmatter의 `model` 필드는 정상 동작한다.** 서브에이전트 정의 파일(`.claude/agents/`)이나 스킬 정의에서 `model: haiku`로 지정하면 해당 모델로 실행된다. 문제는 런타임에 Task 도구를 직접 호출할 때의 model 파라미터뿐이다.

**현재 워크어라운드:**
- 서브에이전트 파일에서 `model: haiku` 사전 지정 → 해당 에이전트를 Task로 호출
- `ANTHROPIC_DEFAULT_*_MODEL` 환경변수 활용은 Task 도구에서 참조하지 않아 불가

### 4. 빌드/테스트 자동 검증 게이트 베스트 프랙티스

**Stop Hook + 빌드 검증 패턴:**

```json
{
  "Stop": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "prompt",
          "prompt": "Check if code was modified. If Write/Edit tools were used, verify the project was built (npm run build, cargo build, etc). If not built, block and request build."
        }
      ]
    }
  ]
}
```

**Agent 기반 Hook으로 테스트 실행 검증:**

```json
{
  "Stop": [
    {
      "hooks": [
        {
          "type": "agent",
          "prompt": "Verify that all unit tests pass. Run the test suite and check the results. $ARGUMENTS",
          "timeout": 120
        }
      ]
    }
  ]
}
```

**TaskCompleted Hook으로 태스크별 검증:**

```bash
#!/bin/bash
INPUT=$(cat)
TASK_SUBJECT=$(echo "$INPUT" | jq -r '.task_subject')

if ! npm test 2>&1; then
  echo "Tests not passing. Fix failing tests before completing: $TASK_SUBJECT" >&2
  exit 2
fi

exit 0
```

**핵심 베스트 프랙티스:**

1. **Stop Hook에서 `stop_hook_active` 체크 필수** → 이미 block 상태에서 또 block하면 무한 루프
2. **iteration 제한 설정** → `--max-iterations` 또는 파일 기반 카운터
3. **서브에이전트에 `disableAllHooks: true` 전파 방지** → 서브에이전트가 부모 훅을 상속하여 재귀 루프 발생 가능
4. **async hook 활용** → 빌드/테스트를 비동기로 실행하여 Claude 작업 차단 방지
5. **컨텍스트 윈도우 관리** → 긴 루프에서 컨텍스트가 소진되면 성능 급격히 저하

### 5. Ralph Wiggum Loop 플러그인

**상태: anthropics/claude-code 공식 레포의 `plugins/ralph-wiggum/` 디렉토리에 존재**

Ralph Wiggum은 Stop Hook을 이용한 자기참조 피드백 루프의 공식 구현체이다.

**작동 원리:**
1. `/ralph-loop "작업 설명" --completion-promise "DONE"` 실행
2. Claude가 작업 수행
3. 종료 시도 시 Stop Hook이 exit code 2로 차단
4. 동일 프롬프트를 다시 주입
5. completion promise 문자열이 출력될 때까지 반복

**핵심 명령어:**
- `/ralph-loop "<prompt>" --max-iterations <n> --completion-promise "<text>"`
- `/cancel-ralph` - 활성 루프 취소

**프롬프트 작성 베스트 프랙티스:**

```markdown
Build a REST API for todos.

When complete:
- All CRUD endpoints working
- Input validation in place
- Tests passing (coverage > 80%)
- README with API docs
- Output: <promise>COMPLETE</promise>
```

**주의사항:**
- `frankbria/ralph-claude-code`는 커뮤니티 포크이며, 공식 버전은 `anthropics/claude-code/plugins/ralph-wiggum/`
- 단순 반복 작업(대규모 리팩토링, 배치 작업, 테스트 커버리지 확장, 그린필드 빌드)에 최적
- 복잡한 상태 관리가 필요한 작업에는 Task 시스템 + Agent Team이 더 적합
- 토큰 비용 폭주 위험 → max-iterations 필수 설정
- 컨텍스트 윈도우 한계 → 자동 compaction 발동 가능

## 코드 예제

### Stop Hook 기반 Sisyphus 루프 (최소 구현)

```json
// .claude/settings.local.json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/sisyphus-gate.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/bin/bash
# .claude/hooks/sisyphus-gate.sh
INPUT=$(cat)
STOP_HOOK_ACTIVE=$(echo "$INPUT" | jq -r '.stop_hook_active // false')
ITERATION_FILE="/tmp/claude-sisyphus-count"

# 현재 반복 횟수 읽기
if [ -f "$ITERATION_FILE" ]; then
  COUNT=$(cat "$ITERATION_FILE")
else
  COUNT=0
fi

COUNT=$((COUNT + 1))
echo "$COUNT" > "$ITERATION_FILE"

# 최대 반복 제한 (50회)
if [ "$COUNT" -ge 50 ]; then
  rm -f "$ITERATION_FILE"
  exit 0  # 정상 종료 허용
fi

# 이미 stop hook에 의해 실행 중이면 트랜스크립트 분석
if [ "$STOP_HOOK_ACTIVE" = "true" ]; then
  # pending 태스크가 있는지 확인하는 로직을 여기에 추가
  echo '{"decision": "block", "reason": "Iteration '$COUNT'/50. Check remaining tasks and continue working."}'
  exit 0
fi

# 첫 번째 stop - 태스크 완료 여부 확인
echo '{"decision": "block", "reason": "Verify all tasks are complete before stopping. Run tests if code was modified."}'
exit 0
```

### 스킬 frontmatter에 Stop Hook 내장

```yaml
---
name: implement-loop
description: Implements features in a continuous loop until all tasks complete
hooks:
  Stop:
    - hooks:
        - type: prompt
          prompt: |
            Check if all requested tasks are complete by reviewing the conversation.
            If there are remaining tasks, return {"ok": false, "reason": "Remaining: [list tasks]"}.
            If all tasks are done and tests pass, return {"ok": true}.
          timeout: 30
---

You are an implementation agent. Work through all tasks systematically.
After each task, verify it works, then move to the next one.
```

## 주요 포인트

- **Stop Hook이 Sisyphus 강제속행의 핵심 메커니즘이다.** exit code 2 또는 `{"decision": "block"}`으로 Claude의 종료를 차단하고 계속 작업하게 만든다.
- **Ralph Wiggum 플러그인은 anthropics/claude-code 공식 레포에 존재하며**, `/ralph-loop` 명령으로 사용 가능하다. 단, 2026년 2월 릴리즈 노트에 별도 언급은 없다.
- **Task 도구의 model 파라미터 버그는 2026년 2월 현재 미해결이다.** 런타임 haiku/sonnet 라우팅이 불가하며, 워크어라운드는 서브에이전트 YAML에서 model을 사전 지정하는 것이다.
- **무한 루프 방지가 필수이다.** `stop_hook_active` 체크, iteration 카운터, max-iterations 설정, 서브에이전트 훅 상속 차단이 핵심 안전장치다.
- **빌드/테스트 검증 게이트는 Stop Hook, TaskCompleted Hook, Agent 기반 Hook 세 가지 방식으로 구현 가능하다.** Agent 기반 Hook은 실제 파일을 읽고 테스트를 실행할 수 있어 가장 강력하다.

## 출처

- [Claude Code Hooks Reference (공식 문서)](https://code.claude.com/docs/en/hooks)
- [Claude Code Subagents (공식 문서)](https://code.claude.com/docs/en/sub-agents)
- [Ralph Wiggum Plugin (anthropics/claude-code)](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [Task tool model parameter 404 Bug - Issue #18873](https://github.com/anthropics/claude-code/issues/18873)
- [Task subagent model 404 - Issue #16115](https://github.com/anthropics/claude-code/issues/16115)
- [Task tool model API 404 - Issue #11682](https://github.com/anthropics/claude-code/issues/11682)
- [How to Keep Claude Code Continuously Running (apidog.com)](https://apidog.com/blog/claude-code-continuously-running/)
- [Ralph Wiggum Explained (Dev Genius)](https://blog.devgenius.io/ralph-wiggum-explained-the-claude-code-loop-that-keeps-going-3250dcc30809)
- [Claude Code Todos to Tasks (Medium)](https://medium.com/@richardhightower/claude-code-todos-to-tasks-5a1b0e351a1c)
- [Claude Code Task Management (claudefa.st)](https://claudefa.st/blog/guide/development/task-management)
- [Claude Code Release Notes Feb 2026 (Releasebot)](https://releasebot.io/updates/anthropic/claude-code)
- [Claude Code Infinite Loop Issue #10205](https://github.com/anthropics/claude-code/issues/10205)
- [Stop Hook Infinite Loop Issue #3573](https://github.com/anthropics/claude-code/issues/3573)
- [frankbria/ralph-claude-code (커뮤니티 포크)](https://github.com/frankbria/ralph-claude-code)
- [Claude Code Best Practices (공식 문서)](https://code.claude.com/docs/en/best-practices)
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery)
