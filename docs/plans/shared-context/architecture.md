# Shared Context System - Architecture

## Design Overview

파일 기반 공유 컨텍스트 + Claude Code 훅 시스템을 활용한 에이전트 간 정보 공유 아키텍처.

세 가지 메커니즘을 조합하여 안정적인 컨텍스트 공유를 구현한다:
1. **Hook 기반 자동 주입/수집** (SubagentStart/SubagentStop)
2. **에이전트 자발적 기록** (에이전트 지침 기반)
3. **세션 수명주기 관리** (SessionStart/SessionEnd)

---

## 시스템 구성도

```
                        Claude Code Session
                              |
                    +---------+---------+
                    |    Main Agent     |
                    |  (Orchestrator)   |
                    +---------+---------+
                              |
                    Task() / Skill()
                              |
              +---------------+---------------+
              |               |               |
     SubagentStart      SubagentStart     SubagentStart
       Hook (1)           Hook (1)          Hook (1)
              |               |               |
     +--------+--+   +-------+---+   +-------+---+
     | navigator |   |  coder    |   | reviewer  |
     | (agent)   |   |  (agent)  |   | (agent)   |
     +--------+--+   +-------+---+   +-------+---+
              |               |               |
     Writes to         Writes to        Writes to
     shared-ctx        shared-ctx       shared-ctx
     (voluntary)       (voluntary)      (voluntary)
              |               |               |
     SubagentStop     SubagentStop    SubagentStop
       Hook (2)         Hook (2)        Hook (2)
              |               |               |
              +-------+-------+-------+-------+
                      |
              .claude/shared-context/{session-id}/
              +-----------------------------------+
              | _summary.md        (집계 요약)     |
              | navigator-abc.md   (탐색 결과)     |
              | coder-def.md       (구현 결과)     |
              | reviewer-ghi.md    (리뷰 결과)     |
              +-----------------------------------+
```

---

## 핵심 컴포넌트

### 1. 공유 컨텍스트 저장소

```
.claude/shared-context/
  {session-id}/
    _summary.md           # 전체 요약 (SubagentStart에서 주입)
    _config.json           # 세션 설정 (TTL, 필터 등)
    navigator-{id}.md      # navigator 에이전트 기록
    coder-{id}.md          # coder 에이전트 기록
    reviewer-{id}.md       # reviewer 에이전트 기록
    ...
```

**_summary.md 구조:**

```markdown
# Shared Context Summary
> Session: {session-id}
> Updated: {timestamp}
> Entries: {count}

## Navigation Results
- [navigator-abc] 관련 파일 목록: src/auth.ts, src/db.ts, ...
- [navigator-abc] 주요 패턴: JWT 토큰 사용, Express 미들웨어

## Code Changes
- [coder-def] 수정: src/auth.ts (인증 로직 추가)
- [coder-def] 생성: src/auth.test.ts

## Review Findings
- [reviewer-ghi] PASS: 코드 품질 양호
- [reviewer-ghi] WARN: 에러 핸들링 개선 필요
```

**_config.json 구조:**

```json
{
  "created_at": "2026-02-12T10:00:00Z",
  "ttl_hours": 24,
  "max_summary_chars": 4000,
  "filters": {
    "reviewer": ["navigation", "code_changes"],
    "security": ["navigation", "code_changes"],
    "coder": ["navigation"],
    "navigator": []
  }
}
```

### 2. SubagentStart Hook (`shared-context-inject.sh`)

**역할**: 서브에이전트 시작 시 공유 컨텍스트 요약을 `additionalContext`로 주입.

**입력** (stdin):
```json
{
  "session_id": "abc123",
  "agent_id": "agent-xyz",
  "agent_type": "navigator",
  "hook_event_name": "SubagentStart",
  "cwd": "/path/to/project"
}
```

**처리 로직:**
1. `session_id`로 공유 컨텍스트 디렉토리 탐색
2. `_summary.md` 읽기
3. 에이전트 타입별 필터 적용 (`_config.json`의 `filters`)
4. 크기 제한 적용 (`max_summary_chars`)
5. `additionalContext`로 출력

**출력** (stdout):
```json
{
  "hookSpecificOutput": {
    "hookEventName": "SubagentStart",
    "additionalContext": "## Shared Context (이전 에이전트 작업 결과)\n\n### Navigation Results\n- 관련 파일: src/auth.ts, ...\n\n### Code Changes\n- src/auth.ts 수정됨\n"
  }
}
```

**실패 시**: `exit 0` (빈 출력). 서브에이전트 실행을 절대 차단하지 않는다.

### 3. SubagentStop Hook (`shared-context-collect.sh`)

**역할**: 서브에이전트 종료 시 작업 결과를 공유 컨텍스트에 기록.

**입력** (stdin):
```json
{
  "session_id": "abc123",
  "agent_id": "agent-xyz",
  "agent_type": "coder",
  "agent_transcript_path": "~/.claude/projects/.../subagents/agent-xyz.jsonl",
  "hook_event_name": "SubagentStop"
}
```

**처리 로직:**
1. 에이전트별 컨텍스트 파일 확인: `.claude/shared-context/{session-id}/{agent-type}-{agent-id}.md`
2. **1차 확인**: 에이전트가 자발적으로 기록한 파일이 있는지 확인
3. **2차 보완**: 자발적 기록이 없으면 transcript에서 핵심 정보 추출
4. `_summary.md` 업데이트 (flock 사용)

**Transcript 파싱 전략** (2차 보완용):
- transcript JSONL에서 `tool_name: "Write"`, `tool_name: "Edit"` 호출 추출
- `tool_response`에서 파일 경로와 성공 여부 추출
- 최근 500줄만 파싱 (성능 제한)

**출력**: 없음 (파일에 직접 기록). `exit 0` 보장.

### 4. 에이전트 자발적 기록 메커니즘

에이전트 정의(`.claude/agents/*.md`)에 다음 지침을 추가:

```markdown
## Shared Context Protocol

작업 완료 시, 다음 경로에 작업 결과 요약을 기록한다:
`.claude/shared-context/{SESSION_ID}/{AGENT_TYPE}-{AGENT_ID}.md`

환경 변수:
- `$CLAUDE_SHARED_CONTEXT_DIR`: 공유 컨텍스트 디렉토리 경로

기록 형식:
- 제목: `# {Agent Type} Report: {Agent ID}`
- 섹션: 발견 사항, 변경된 파일, 이슈, 권고 사항
```

**SubagentStart hook이 환경 변수를 설정할 수 없는 제약이 있다.**
(`CLAUDE_ENV_FILE`은 SessionStart에서만 사용 가능.)

대안: SubagentStart의 `additionalContext`에 공유 컨텍스트 디렉토리 경로를 포함시킨다:

```
작업 결과를 다음 파일에 기록하세요: .claude/shared-context/abc123/coder-xyz.md
```

### 5. 세션 수명주기 관리

**SessionStart hook** (`shared-context-cleanup.sh`):
- TTL이 지난 세션 디렉토리 정리
- 현재 세션의 디렉토리 생성

**SessionEnd hook** (`shared-context-finalize.sh`):
- 현재 세션의 최종 `_summary.md` 생성
- 메트릭 로깅 (총 에이전트 수, 컨텍스트 크기 등)

---

## 데이터 흐름

### 시나리오: `/implement` 워크플로우

```
1. SessionStart → shared-context-cleanup.sh
   - TTL 만료된 세션 정리
   - .claude/shared-context/{session-id}/ 생성

2. Phase 1: navigator 실행
   - SubagentStart hook → 공유 컨텍스트 비어있음 → additionalContext 없음
   - navigator 작업 수행 (코드 탐색)
   - navigator가 자발적으로 기록:
     .claude/shared-context/{session-id}/navigator-abc.md
       "관련 파일: src/auth.ts, src/db.ts
        패턴: JWT, Express middleware
        의존성: jsonwebtoken, express"
   - SubagentStop hook → _summary.md 업데이트

3. Phase 3: coder 실행
   - SubagentStart hook → _summary.md 읽기 → additionalContext 주입:
     "## Shared Context
      ### Navigation Results
      - 관련 파일: src/auth.ts, src/db.ts
      - 패턴: JWT, Express middleware"
   - coder가 탐색 없이 바로 코딩 시작 (중복 탐색 제거)
   - coder가 자발적으로 기록:
     .claude/shared-context/{session-id}/coder-def.md
       "수정: src/auth.ts (인증 미들웨어 추가)
        생성: src/auth.test.ts"
   - SubagentStop hook → _summary.md 업데이트

4. Phase 6: reviewer 실행
   - SubagentStart hook → _summary.md 읽기 → additionalContext 주입:
     "## Shared Context
      ### Navigation Results (필터: coder와 동일)
      ### Code Changes
      - src/auth.ts 수정됨 (인증 미들웨어)
      - src/auth.test.ts 생성됨"
   - reviewer가 변경 파일 목록을 이미 알고 있어 빠르게 리뷰 시작
```

---

## 훅 설정 통합

기존 `.claude/settings.local.json`에 통합:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-cleanup.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-inject.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-collect.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-finalize.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

**기존 hooks와의 공존**: `SubagentStop`에 이미 `subagent-monitor.sh`가 있다. 동일 이벤트에 여러 훅을 등록할 수 있으므로 충돌 없이 공존한다.

---

## 대안 검토

### 대안 1: Agent Teams 활용

Agent Teams의 TaskList/SendMessage를 사용하여 에이전트 간 정보를 공유.

**장점**: 공식 지원, 직접 통신 가능
**단점**: Agent Teams는 실험적(experimental), Task() 기반 서브에이전트와 별도 모델, 토큰 비용 대폭 증가, 기존 워크플로우 스킬 전면 재설계 필요
**결론**: 현재 아키텍처(context: fork + Task)와 호환되지 않음. 향후 Agent Teams가 안정화되면 재검토.

### 대안 2: CLAUDE.md 동적 수정

서브에이전트 종료 시 CLAUDE.md에 작업 결과를 추가하고, 다음 서브에이전트가 자동으로 읽도록 함.

**장점**: 추가 훅 불필요
**단점**: CLAUDE.md는 프로젝트 전역 지침. 세션별 동적 데이터를 넣으면 충돌 및 오염 위험. Git tracked 파일이므로 의도치 않은 커밋 위험.
**결론**: 부적절.

### 대안 3: Transcript 파싱 전용

SubagentStop에서 transcript만 파싱하여 정보를 추출.

**장점**: 에이전트 수정 불필요
**단점**: transcript 형식이 내부 구현이라 변경 위험. 파싱 복잡도 높음. 추출 정확도 낮음.
**결론**: 보완 메커니즘으로만 사용. 1차는 에이전트 자발적 기록.

### 대안 4: MCP 서버 기반

MCP 서버로 공유 컨텍스트를 관리하고 에이전트에 도구로 제공.

**장점**: 구조화된 API, 에이전트가 명시적으로 읽기/쓰기
**단점**: MCP 서버 개발/운영 비용. 에이전트에 MCP 도구 추가 필요. 과잉 설계.
**결론**: 현 규모에서는 과잉. 파일 기반으로 시작하고 필요 시 전환.

---

## 기술 스택

- **언어**: Bash (기존 hooks와 일관)
- **의존성**: `jq` (JSON 파싱), `flock` (파일 잠금), `date` (타임스탬프)
- **설정**: JSON (`.claude/shared-context-config.json`) 또는 환경 변수
- **저장**: 로컬 파일시스템 (`.claude/shared-context/`)

---

## 출처

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks) - SubagentStart/SubagentStop hook spec
- [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams) - Agent Teams architecture
- [Feature Request #5812](https://github.com/anthropics/claude-code/issues/5812) - Context bridging discussion
- [Claude Code Hooks Multi-Agent Observability](https://github.com/disler/claude-code-hooks-multi-agent-observability) - Hook monitoring patterns
