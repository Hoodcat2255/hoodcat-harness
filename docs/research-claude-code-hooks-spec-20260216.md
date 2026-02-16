# Claude Code Hooks PreToolCall/PostToolCall 스펙 조사

> 조사일: 2026-02-16

## 개요

Claude Code는 13개의 훅 이벤트를 제공하며, 이를 통해 도구 호출 전후에 검증/차단/수정/컨텍스트 주입 등의 자동화를 구현할 수 있다. PreToolUse 훅은 exit code 2로 도구 호출을 차단할 수 있고, hookSpecificOutput으로 permissionDecision(allow/deny/ask)과 updatedInput을 반환할 수 있다. 서브에이전트와 메인 에이전트를 stdin JSON의 특정 필드로 직접 구분하는 공식 메커니즘은 없으나, SubagentStart/SubagentStop 훅이 서브에이전트 전용으로 분리되어 있다.

## 상세 내용

### 1. 훅 이벤트 전체 목록 (13개)

| 이벤트 | 발생 시점 | 차단 가능 |
|--------|----------|----------|
| **Setup** | 레포 진입(init) 또는 주기적 유지보수(maintenance) | 아니오 |
| **SessionStart** | 세션 시작 (startup/resume/clear) | 아니오 |
| **SessionEnd** | 세션 종료 (exit/sigint/error) | 아니오 |
| **UserPromptSubmit** | 사용자 프롬프트 제출 직후 | exit 2로 차단 가능 |
| **PreToolUse** | 도구 실행 전 | exit 2로 차단 가능 |
| **PostToolUse** | 도구 실행 성공 후 | 아니오 (피드백만) |
| **PostToolUseFailure** | 도구 실행 실패 후 | 아니오 |
| **PermissionRequest** | 사용자에게 권한 다이얼로그 표시 시 | allow/deny 결정 가능 |
| **PreCompact** | 컨텍스트 압축 전 | 아니오 |
| **Stop** | 메인 에이전트 응답 완료 시 | exit 2로 차단 가능 |
| **SubagentStart** | 서브에이전트(Task) 시작 시 | 아니오 |
| **SubagentStop** | 서브에이전트(Task) 종료 시 | exit 2로 차단 가능 |
| **Notification** | 사용자 알림 발송 시 | 아니오 |
| **TaskCompleted** | 에이전트팀 팀원 태스크 완료 시 | exit 2로 차단 가능 |
| **TeammateIdle** | 에이전트팀 팀원 유휴 전환 시 | exit 2로 피드백 전송 |

### 2. PreToolUse 훅 상세 스펙

#### stdin으로 전달되는 JSON 필드

공통 필드:
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask|allow",
  "hook_event_name": "PreToolUse"
}
```

PreToolUse 전용 필드:
```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/build"
  }
}
```

전체 입력 예시:
```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "rm -rf /tmp/build"
  }
}
```

#### exit code별 동작

| Exit Code | 동작 |
|-----------|------|
| **0** | 허용 - stdout은 트랜스크립트에 표시됨 |
| **2** | 차단 - stderr가 Claude에게 피드백으로 전달됨 |
| **기타** | 비차단 에러 (훅 실패로 처리, 도구 실행은 진행) |

#### hookSpecificOutput으로 고급 제어

```json
{
  "hookSpecificOutput": {
    "permissionDecision": "allow|deny|ask",
    "updatedInput": {"field": "modified_value"}
  },
  "systemMessage": "Explanation for Claude"
}
```

- `permissionDecision`: "allow" = 무조건 허용, "deny" = 차단, "ask" = 사용자 확인 요청
- `updatedInput`: 도구 입력 파라미터를 수정하여 전달 가능 (선택적)
- `systemMessage`: Claude에게 추가 컨텍스트 제공 (선택적)

### 3. PostToolUse 훅 상세 스펙

#### stdin 전용 필드

```json
{
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  },
  "tool_result": "All tests passed"
}
```

#### 동작
- exit 0: stdout이 트랜스크립트에 표시
- exit 2: stderr가 Claude에게 피드백으로 전달
- systemMessage를 통해 Claude에게 추가 컨텍스트 주입 가능

### 4. SubagentStart/SubagentStop 훅 스펙

#### SubagentStart stdin 필드

```json
{
  "session_id": "abc123",
  "agent_id": "a1234567",
  "agent_type": "orchestrator",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "SubagentStart"
}
```

#### SubagentStart hookSpecificOutput

```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "서브에이전트에게 주입할 추가 컨텍스트 텍스트"
  }
}
```

- `additionalContext`: 서브에이전트의 시스템 프롬프트에 `<system-reminder>` 태그로 주입됨

#### SubagentStop stdin 필드

```json
{
  "session_id": "abc123",
  "agent_id": "a1234567",
  "agent_type": "researcher",
  "agent_transcript_path": "/path/to/agent/transcript.txt",
  "hook_event_name": "SubagentStop",
  "reason": "completed"
}
```

### 5. PermissionRequest 훅 스펙

#### stdin 필드

```json
{
  "session_id": "abc123",
  "tool_name": "Write",
  "tool_input": {"file_path": "/etc/passwd"},
  "tool_use_id": "tu_xxxxx",
  "hook_event_name": "PermissionRequest"
}
```

#### hookSpecificOutput으로 자동 승인/거부

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PermissionRequest",
    "decision": {
      "behavior": "allow|deny",
      "updatedInput": {},
      "message": "거부 사유",
      "interrupt": false
    }
  }
}
```

- `behavior`: "allow" = 자동 승인, "deny" = 자동 거부
- `updatedInput`: allow 시 도구 입력 수정 (선택적)
- `message`: deny 시 표시할 메시지 (선택적)
- `interrupt`: deny 시 Claude 실행 중단 여부 (선택적)

### 6. 기타 훅 stdin 필드

#### UserPromptSubmit
```json
{
  "hook_event_name": "UserPromptSubmit",
  "user_prompt": "사용자가 입력한 텍스트"
}
```

#### Stop
```json
{
  "hook_event_name": "Stop",
  "reason": "completed|error|..."
}
```

#### SessionStart
```json
{
  "hook_event_name": "SessionStart",
  "source": "startup|resume|clear"
}
```

- SessionStart 전용: `$CLAUDE_ENV_FILE` 환경변수로 영구 환경변수 설정 가능

#### SessionEnd
```json
{
  "hook_event_name": "SessionEnd",
  "reason": "exit|sigint|error"
}
```

#### PreCompact
```json
{
  "hook_event_name": "PreCompact",
  "trigger": "manual|auto",
  "custom_instructions": "수동 압축 시 사용자 지시"
}
```

#### Setup
```json
{
  "hook_event_name": "Setup",
  "trigger": "init|maintenance"
}
```

- Setup 전용: `$CLAUDE_ENV_FILE`로 환경변수 영구화, `additionalContext`로 컨텍스트 주입 가능

#### TaskCompleted (에이전트팀)
```json
{
  "hook_event_name": "TaskCompleted",
  "task": {
    "id": "task_id",
    "subject": "태스크 제목"
  },
  "agent": {
    "name": "에이전트 이름"
  }
}
```

#### TeammateIdle (에이전트팀)
```json
{
  "hook_event_name": "TeammateIdle",
  "agent": {
    "name": "에이전트 이름"
  },
  "team": {
    "name": "팀 이름"
  }
}
```

### 7. settings.json 설정 형식

#### hooks 설정

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "bash /path/to/validate.sh",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

- `matcher`: 도구 이름 매칭 (정규식). "" 또는 생략 = 모든 도구에 매치
- `"*"` = 모든 도구 와일드카드
- `"Write|Edit"` = 파이프로 OR 매칭
- `"mcp__.*__delete.*"` = 정규식 패턴
- `"Bash"` = 정확한 이름 매칭 (대소문자 구분)

#### hooks 타입

| 타입 | 설명 |
|------|------|
| `command` | bash 명령 실행 (결정적 검증) |
| `prompt` | LLM 프롬프트 기반 판단 (컨텍스트 인식) |

- prompt 타입 지원 이벤트: Stop, SubagentStop, UserPromptSubmit, PreToolUse
- prompt에서 `$TOOL_INPUT`, `$TOOL_RESULT`, `$USER_PROMPT` 등 환경변수 참조 가능

#### permissions 설정 (allowedTools/disabledTools 대응)

```json
{
  "permissions": {
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Bash(ls:*)",
      "Bash(git:*)",
      "Write",
      "Edit"
    ],
    "deny": [
      "Bash(rm -rf:*)"
    ]
  }
}
```

- `allow`: 사용자 확인 없이 자동 허용할 도구 패턴
- `deny`: 완전 차단할 도구 패턴
- `Bash(command:*)` 형식으로 특정 bash 명령 패턴 지정 가능

### 8. 환경변수

모든 command 훅에서 사용 가능:
- `$CLAUDE_PROJECT_DIR`: 프로젝트 루트 경로
- `$CLAUDE_PLUGIN_ROOT`: 플러그인 디렉토리 (플러그인 내부 훅 전용)
- `$CLAUDE_ENV_FILE`: SessionStart/Setup 전용, 환경변수 영구화 파일
- `$CLAUDE_CODE_REMOTE`: 원격 실행 환경일 때 설정됨

prompt 타입 훅에서 사용 가능:
- `$TOOL_INPUT`: 도구 입력 JSON
- `$TOOL_RESULT`: 도구 결과 (PostToolUse)
- `$USER_PROMPT`: 사용자 프롬프트 텍스트
- `$TRANSCRIPT_PATH`: 트랜스크립트 경로

### 9. Main Agent(top-level)와 서브에이전트 구분

공식적으로 PreToolUse stdin에 "이 훅이 메인 에이전트에서 실행 중인지 서브에이전트에서 실행 중인지"를 알려주는 전용 필드는 없다. 그러나 다음 방법으로 구분할 수 있다:

1. **훅 이벤트 분리**: SubagentStart/SubagentStop은 서브에이전트 전용, Stop은 메인 에이전트 전용
2. **agent_type/agent_id 필드**: SubagentStart/SubagentStop stdin에 `agent_type`과 `agent_id` 필드가 포함됨
3. **PreToolUse는 모든 에이전트에서 실행**: 메인 에이전트든 서브에이전트든 PreToolUse 훅은 동일하게 트리거됨
4. **환경변수 기반 구분**: Setup 또는 SessionStart 훅에서 `$CLAUDE_ENV_FILE`로 환경변수를 설정한 후, PreToolUse에서 이를 참조하는 패턴은 가능하나, 서브에이전트별 구분은 불가
5. **세션 ID 기반 추적**: session_id는 모든 훅에서 공통이므로, SubagentStart에서 agent_id를 기록해두고 다른 훅에서 참조하는 패턴 가능

**결론**: PreToolUse 훅 자체에서는 메인 에이전트와 서브에이전트를 직접 구분할 수 없다. 서브에이전트 전용 로직은 SubagentStart/SubagentStop 훅에서 구현해야 한다.

### 10. 훅 실행 특성

- **병렬 실행**: 동일 이벤트에 등록된 여러 훅은 병렬 실행됨
- **독립적**: 훅 간에 서로의 출력을 볼 수 없음
- **세션 시작 시 로드**: 훅 설정 변경은 세션 재시작 필요
- **기본 타임아웃**: command 60초, prompt 30초
- **/hooks 명령**: 현재 세션에 로드된 훅 목록 확인 가능

## 코드 예제

### PreToolUse에서 위험한 명령 차단 (Bash)

```bash
#!/bin/bash
INPUT=$(cat)
COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q "drop table"; then
  echo "Blocked: dropping tables is not allowed" >&2
  exit 2  # exit 2 = 차단, stderr가 Claude에게 피드백
fi

exit 0  # exit 0 = 허용
```

### PreToolUse에서 도구 입력 수정 (JSON 출력)

```bash
#!/bin/bash
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

if [ "$TOOL_NAME" = "Write" ]; then
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path')

  # .env 파일 접근 차단
  if echo "$FILE_PATH" | grep -q '\.env'; then
    echo '{"hookSpecificOutput":{"permissionDecision":"deny"},"systemMessage":".env 파일은 수정할 수 없습니다"}'
    exit 0
  fi
fi

exit 0
```

### SubagentStart에서 additionalContext 주입 (우리 프로젝트 패턴)

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type')

CONTEXT="이전 에이전트 작업 결과를 여기에 주입"

jq -n --arg ctx "$CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: $ctx
  }
}'

exit 0
```

### PermissionRequest에서 읽기 전용 자동 승인

```bash
#!/bin/bash
INPUT=$(cat)
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# 읽기 전용 도구 자동 허용
if [ "$TOOL_NAME" = "Read" ] || [ "$TOOL_NAME" = "Glob" ] || [ "$TOOL_NAME" = "Grep" ]; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PermissionRequest",
      decision: {
        behavior: "allow"
      }
    }
  }'
  exit 0
fi

exit 0
```

## 주요 포인트

- PreToolUse 훅은 exit 2로 도구 호출을 차단할 수 있으며, stderr 메시지가 Claude에게 피드백으로 전달된다
- hookSpecificOutput의 permissionDecision으로 allow/deny/ask 세밀한 제어가 가능하고, updatedInput으로 도구 입력을 실시간 수정할 수 있다
- SubagentStart의 hookSpecificOutput.additionalContext로 서브에이전트에 컨텍스트를 주입할 수 있다 (우리 프로젝트에서 이미 활용 중)
- PreToolUse 훅은 메인 에이전트와 서브에이전트 모두에서 동일하게 실행되며, 둘을 구분하는 공식 필드는 없다
- matcher로 특정 도구에만 훅을 적용할 수 있으며, 정규식 패턴 지원 (대소문자 구분)
- prompt 타입 훅은 LLM이 판단하는 방식으로, PreToolUse/Stop/SubagentStop/UserPromptSubmit에서 사용 가능
- 모든 훅은 병렬 실행되므로 독립적으로 설계해야 한다
- 훅 설정은 세션 시작 시 로드되므로, 변경 후 재시작이 필요하다

## hoodcat-harness 프로젝트와의 관계

현재 프로젝트에서 이미 활용 중인 훅:
- **SubagentStart** (shared-context-inject.sh): additionalContext로 공유 컨텍스트 주입 -- 정확히 공식 스펙대로 구현됨
- **SubagentStop** (subagent-monitor.sh + shared-context-collect.sh): 서브에이전트 종료 로깅 및 컨텍스트 수집
- **TaskCompleted** (task-quality-gate.sh): exit 2로 빌드/테스트 미통과 시 태스크 완료 차단
- **TeammateIdle** (teammate-idle-check.sh): exit 2로 유휴 팀원에게 작업 재개 피드백 전송
- **SessionStart** (shared-context-cleanup.sh): TTL 만료 세션 정리
- **SessionEnd** (shared-context-finalize.sh): 세션 메트릭 기록

활용 가능하지만 아직 미사용인 훅:
- **PreToolUse**: 위험한 명령 차단, 파일 보호, 보안 정책 적용 등
- **PostToolUse**: 자동 git stage, 코드 품질 체크 등
- **PermissionRequest**: 읽기 전용 도구 자동 승인으로 워크플로우 가속
- **Setup**: 프로젝트 환경 자동 감지 및 설정
- **PreCompact**: 압축 전 중요 컨텍스트 보존
- **UserPromptSubmit**: 프롬프트 유효성 검사, 보안 필터링

## 출처

- [Claude Code 공식 GitHub - Hook Development SKILL.md](https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/hook-development/SKILL.md)
- [Claude Code 공식 문서 - Hooks](https://code.claude.com/docs/en/hooks)
- [Claude Code 공식 문서 - Hooks Guide](https://code.claude.com/docs/en/hooks-guide)
- [disler/claude-code-hooks-mastery](https://github.com/disler/claude-code-hooks-mastery) - 13개 훅 전체 구현 예제 (3,051 stars)
- [karanb192/claude-code-hooks](https://github.com/karanb192/claude-code-hooks) - 실용적 훅 컬렉션 (144 stars)
- [anthropics/claude-code#19561](https://github.com/anthropics/claude-code/issues/19561) - Blocking Hooks 기능 요청
- [anthropics/claude-code#21537](https://github.com/anthropics/claude-code/issues/21537) - BeforeToolSelection Hook 기능 요청
