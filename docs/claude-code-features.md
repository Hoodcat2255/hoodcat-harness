# Claude Code 핵심 기능 가이드

> Agents, Skills, Hooks에 대한 종합 문서

---

## 목차

1. [Agents (서브에이전트)](#1-agents-서브에이전트)
2. [Skills (스킬)](#2-skills-스킬)
3. [Hooks (훅)](#3-hooks-훅)
4. [기능 간 비교 및 선택 가이드](#4-기능-간-비교-및-선택-가이드)

---

## 1. Agents (서브에이전트)

### 1.1 개요

서브에이전트는 특정 유형의 작업을 처리하는 전문화된 AI 어시스턴트입니다. 각 서브에이전트는:
- 독립적인 컨텍스트 윈도우에서 실행
- 커스텀 시스템 프롬프트 사용
- 특정 도구 접근 권한 보유
- 독립적인 권한 설정

### 1.2 내장 서브에이전트

| 에이전트 | 모델 | 도구 | 용도 |
|---------|------|------|------|
| **Explore** | Haiku (빠름) | Read-only (Write, Edit 제외) | 파일 탐색, 코드 검색, 코드베이스 분석 |
| **Plan** | 상속 | Read-only | 계획 모드에서 코드베이스 리서치 |
| **general-purpose** | 상속 | 모든 도구 | 복잡한 리서치, 멀티스텝 작업 |
| **Bash** | 상속 | Bash | 터미널 명령 실행 |
| **Claude Code Guide** | Haiku | - | Claude Code 기능 관련 질문 답변 |

### 1.3 커스텀 서브에이전트 생성

#### 저장 위치 및 우선순위

| 위치 | 범위 | 우선순위 |
|------|------|----------|
| `--agents` CLI 플래그 | 현재 세션 | 1 (최고) |
| `.claude/agents/` | 현재 프로젝트 | 2 |
| `~/.claude/agents/` | 모든 프로젝트 | 3 |
| Plugin의 `agents/` | 플러그인 활성화 시 | 4 (최저) |

#### 서브에이전트 파일 구조

```markdown
---
name: code-reviewer
description: 코드 품질 및 보안 리뷰 전문가
tools: Read, Grep, Glob
model: sonnet
permissionMode: default
skills:
  - api-conventions
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh"
memory: user
---

당신은 코드 리뷰어입니다. 코드 분석 시 품질, 보안,
베스트 프랙티스에 대한 구체적인 피드백을 제공하세요.
```

#### Frontmatter 필드

| 필드 | 필수 | 설명 |
|------|------|------|
| `name` | O | 고유 식별자 (소문자, 하이픈) |
| `description` | O | 언제 이 에이전트를 사용해야 하는지 설명 |
| `tools` | X | 사용 가능한 도구 목록 |
| `disallowedTools` | X | 거부할 도구 목록 |
| `model` | X | `sonnet`, `opus`, `haiku`, `inherit` |
| `permissionMode` | X | `default`, `acceptEdits`, `dontAsk`, `bypassPermissions`, `plan` |
| `skills` | X | 사전 로드할 스킬 목록 |
| `hooks` | X | 라이프사이클 훅 정의 |
| `memory` | X | 영구 메모리 범위: `user`, `project`, `local` |

### 1.4 도구 접근 제어

```yaml
# Read-only 분석 에이전트
tools: ["Read", "Grep", "Glob"]

# 코드 생성 에이전트
tools: ["Read", "Write", "Grep"]

# 테스트 에이전트
tools: ["Read", "Bash", "Grep"]

# 전체 접근 (필드 생략 또는 와일드카드)
tools: ["*"]
```

### 1.5 CLI로 에이전트 정의

```bash
claude --agents '{
  "code-reviewer": {
    "description": "코드 리뷰 전문가",
    "prompt": "당신은 시니어 코드 리뷰어입니다.",
    "tools": ["Read", "Grep", "Glob", "Bash"],
    "model": "sonnet"
  }
}'
```

### 1.6 에이전트 사용 패턴

```
# 자동 위임 (Claude가 description 기반으로 판단)
이 프로젝트의 인증 모듈을 분석해줘

# 명시적 요청
code-reviewer 서브에이전트를 사용해서 최근 변경사항을 검토해줘

# 백그라운드 실행
이 작업을 백그라운드에서 실행해줘

# 에이전트 재개
이전 코드 리뷰를 이어서 진행해줘
```

---

## 2. Skills (스킬)

### 2.1 개요

스킬은 Claude의 기능을 확장하는 재사용 가능한 지식과 워크플로우입니다.
- `SKILL.md` 파일로 정의
- 자동 또는 수동으로 호출 가능 (`/skill-name`)
- 지원 파일(스크립트, 템플릿, 예시) 포함 가능

### 2.2 저장 위치

| 위치 | 범위 |
|------|------|
| `.claude/skills/<skill-name>/SKILL.md` | 현재 프로젝트 |
| `~/.claude/skills/<skill-name>/SKILL.md` | 모든 프로젝트 |
| `<plugin>/skills/<skill-name>/SKILL.md` | 플러그인 활성화 시 |

### 2.3 스킬 파일 구조

```
my-skill/
├── SKILL.md           # 메인 지침 (필수)
├── template.md        # 템플릿
├── examples/
│   └── sample.md      # 예시 출력
└── scripts/
    └── validate.sh    # 실행 스크립트
```

### 2.4 SKILL.md 작성

```yaml
---
name: explain-code
description: 시각적 다이어그램과 비유를 사용해 코드를 설명합니다.
  "이게 어떻게 작동해?"라고 물을 때 사용하세요.
argument-hint: [file-path]
disable-model-invocation: false
user-invocable: true
allowed-tools: Read, Grep, Glob
model: sonnet
context: fork
agent: Explore
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./scripts/validate.sh"
---

코드를 설명할 때 항상 포함하세요:

1. **비유로 시작**: 일상적인 것과 비교
2. **다이어그램 그리기**: ASCII 아트로 흐름 표시
3. **코드 워크스루**: 단계별 설명
4. **주의점 강조**: 흔한 실수나 오해

복잡한 개념은 여러 비유를 사용하세요.
```

### 2.5 Frontmatter 필드

| 필드 | 필수 | 설명 |
|------|------|------|
| `name` | X | 스킬 이름 (디렉토리명 사용 시 생략 가능) |
| `description` | 권장 | 스킬 용도 및 트리거 조건 |
| `argument-hint` | X | 자동완성 시 표시될 인자 힌트 |
| `disable-model-invocation` | X | `true`: Claude 자동 호출 방지 |
| `user-invocable` | X | `false`: `/` 메뉴에서 숨김 |
| `allowed-tools` | X | 허용할 도구 목록 |
| `model` | X | 사용할 모델 |
| `context` | X | `fork`: 서브에이전트에서 실행 |
| `agent` | X | `context: fork` 시 사용할 에이전트 유형 |
| `hooks` | X | 스킬 라이프사이클 훅 |

### 2.6 호출 제어

| Frontmatter | 사용자 호출 | Claude 호출 | 컨텍스트 로딩 |
|-------------|------------|-------------|--------------|
| (기본값) | O | O | description만 로드, 호출 시 전체 로드 |
| `disable-model-invocation: true` | O | X | description 미포함 |
| `user-invocable: false` | X | O | description만 로드 |

### 2.7 문자열 치환

| 변수 | 설명 |
|------|------|
| `$ARGUMENTS` | 호출 시 전달된 모든 인자 |
| `$ARGUMENTS[N]` 또는 `$N` | N번째 인자 (0-based) |
| `${CLAUDE_SESSION_ID}` | 현재 세션 ID |

### 2.8 동적 컨텍스트 주입

```yaml
---
name: pr-summary
description: PR 변경사항 요약
context: fork
agent: Explore
---

## PR 컨텍스트
- PR diff: !`gh pr diff`
- PR 코멘트: !`gh pr view --comments`
- 변경된 파일: !`gh pr diff --name-only`

## 작업
이 PR을 요약하세요...
```

`!`command`` 구문은 스킬 실행 전에 셸 명령을 실행하고 결과를 주입합니다.

### 2.9 서브에이전트에서 스킬 실행

```yaml
---
name: deep-research
description: 주제를 철저히 조사
context: fork
agent: Explore
---

$ARGUMENTS를 철저히 조사하세요:

1. Glob과 Grep으로 관련 파일 찾기
2. 코드 읽고 분석
3. 특정 파일 참조와 함께 결과 요약
```

---

## 3. Hooks (훅)

### 3.1 개요

훅은 Claude Code 라이프사이클의 특정 지점에서 자동 실행되는 셸 명령 또는 LLM 프롬프트입니다.

### 3.2 훅 이벤트

| 이벤트 | 발생 시점 | 차단 가능 |
|--------|----------|----------|
| `SessionStart` | 세션 시작/재개 시 | X |
| `UserPromptSubmit` | 프롬프트 제출 시 | O |
| `PreToolUse` | 도구 호출 전 | O |
| `PermissionRequest` | 권한 다이얼로그 표시 시 | O |
| `PostToolUse` | 도구 호출 성공 후 | X |
| `PostToolUseFailure` | 도구 호출 실패 후 | X |
| `Notification` | 알림 발생 시 | X |
| `SubagentStart` | 서브에이전트 시작 시 | X |
| `SubagentStop` | 서브에이전트 종료 시 | O |
| `Stop` | Claude 응답 완료 시 | O |
| `PreCompact` | 컨텍스트 압축 전 | X |
| `SessionEnd` | 세션 종료 시 | X |

### 3.3 훅 저장 위치

| 위치 | 범위 |
|------|------|
| `~/.claude/settings.json` | 모든 프로젝트 |
| `.claude/settings.json` | 현재 프로젝트 |
| `.claude/settings.local.json` | 현재 프로젝트 (gitignore) |
| Plugin `hooks/hooks.json` | 플러그인 활성화 시 |
| Skill/Agent frontmatter | 해당 컴포넌트 활성 시 |

### 3.4 훅 설정 구조

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Bash",
        "hooks": [
          {
            "type": "command",
            "command": ".claude/hooks/validate-bash.sh",
            "timeout": 30
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": "Write|Edit",
        "hooks": [
          {
            "type": "command",
            "command": "npx prettier --write \"$file_path\"",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "모든 작업이 완료되었는지 확인: $ARGUMENTS",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### 3.5 훅 타입

#### Command 훅

```json
{
  "type": "command",
  "command": "./scripts/validate.sh",
  "timeout": 600,
  "async": false
}
```

#### Prompt 훅 (LLM 평가)

```json
{
  "type": "prompt",
  "prompt": "이 작업이 안전한지 평가: $ARGUMENTS",
  "model": "haiku",
  "timeout": 30
}
```

#### Agent 훅 (다중 턴 검증)

```json
{
  "type": "agent",
  "prompt": "모든 유닛 테스트가 통과하는지 확인하세요. $ARGUMENTS",
  "timeout": 120
}
```

### 3.6 Matcher 패턴

| 이벤트 | Matcher 대상 | 예시 |
|--------|-------------|------|
| `PreToolUse`, `PostToolUse` | 도구 이름 | `Bash`, `Edit\|Write`, `mcp__.*` |
| `SessionStart` | 시작 방식 | `startup`, `resume`, `clear`, `compact` |
| `SessionEnd` | 종료 이유 | `clear`, `logout`, `other` |
| `Notification` | 알림 유형 | `permission_prompt`, `idle_prompt` |
| `SubagentStart/Stop` | 에이전트 유형 | `Bash`, `Explore`, `Plan` |
| `PreCompact` | 트리거 | `manual`, `auto` |

### 3.7 입력 및 출력

#### 공통 입력 필드 (stdin JSON)

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.jsonl",
  "cwd": "/home/user/project",
  "permission_mode": "default",
  "hook_event_name": "PreToolUse",
  "tool_name": "Bash",
  "tool_input": {
    "command": "npm test"
  }
}
```

#### 종료 코드

| 코드 | 의미 |
|------|------|
| `0` | 성공 - JSON 출력 처리 |
| `2` | 차단 - stderr를 에러로 표시 |
| 기타 | 비차단 오류 - 실행 계속 |

#### JSON 출력 (stdout)

```json
{
  "continue": true,
  "stopReason": "빌드 실패, 오류 수정 필요",
  "suppressOutput": false,
  "systemMessage": "경고 메시지",
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "deny",
    "permissionDecisionReason": "위험한 명령 차단"
  }
}
```

### 3.8 PreToolUse 결정 제어

```json
{
  "hookSpecificOutput": {
    "hookEventName": "PreToolUse",
    "permissionDecision": "allow",
    "permissionDecisionReason": "안전한 명령",
    "updatedInput": {
      "command": "npm run lint"
    },
    "additionalContext": "추가 컨텍스트"
  }
}
```

| permissionDecision | 동작 |
|--------------------|------|
| `allow` | 권한 시스템 우회, 즉시 실행 |
| `deny` | 도구 호출 차단 |
| `ask` | 사용자에게 확인 요청 |

### 3.9 실용적인 훅 예시

#### 위험한 명령 차단

```bash
#!/bin/bash
# .claude/hooks/block-rm.sh
COMMAND=$(jq -r '.tool_input.command')

if echo "$COMMAND" | grep -q 'rm -rf'; then
  jq -n '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: "파괴적인 명령이 훅에 의해 차단됨"
    }
  }'
else
  exit 0
fi
```

#### 파일 수정 후 자동 포맷팅

```json
{
  "PostToolUse": [
    {
      "matcher": "Write|Edit",
      "hooks": [
        {
          "type": "command",
          "command": "npx prettier --write \"$file_path\"",
          "async": true
        }
      ]
    }
  ]
}
```

#### 세션 시작 시 환경 설정

```bash
#!/bin/bash
# SessionStart 훅

if [ -n "$CLAUDE_ENV_FILE" ]; then
  echo 'export NODE_ENV=production' >> "$CLAUDE_ENV_FILE"
  echo 'export DEBUG=true' >> "$CLAUDE_ENV_FILE"
fi

exit 0
```

### 3.10 TypeScript Hook SDK

```typescript
import { runHook } from '@mizunashi_mana/claude-code-hook-sdk';

void runHook({
  preToolUseHandler: async (input) => {
    console.error(`Tool: ${input.tool_name}`);

    if (input.tool_name === 'Bash' &&
        input.tool_input.command.includes('rm -rf')) {
      return {
        decision: 'block',
        reason: '위험한 명령 차단'
      };
    }

    return {};
  },

  postToolUseHandler: async (input) => {
    console.error(`Tool ${input.tool_name} completed`);
    return {};
  },

  stopHandler: async (input) => {
    if (!input.stop_hook_active) {
      return {
        decision: 'block',
        reason: '테스트 미완료'
      };
    }
    return {};
  },
});
```

---

## 4. 기능 간 비교 및 선택 가이드

### 4.1 비교 표

| 특성 | Agents | Skills | Hooks |
|------|--------|--------|-------|
| **목적** | 작업 위임 | 지식/워크플로우 확장 | 자동화/검증 |
| **실행 컨텍스트** | 독립 컨텍스트 | 메인 또는 포크 | 이벤트 기반 |
| **호출 방식** | 자동/명시적 | 자동/`/skill-name` | 자동 (이벤트) |
| **도구 제어** | O | O | X (검증만) |
| **모델 선택** | O | O | O (prompt/agent 훅) |
| **지속성** | 재개 가능 | 세션 내 | 세션 내 |

### 4.2 사용 시나리오

#### Agents 사용

- 대용량 출력 격리 (테스트, 로그 분석)
- 병렬 리서치
- 특정 도구 제한 필요 시
- 독립적인 작업 컨텍스트 필요 시

#### Skills 사용

- 재사용 가능한 워크플로우
- 도메인 지식 공유
- 팀 간 베스트 프랙티스 표준화
- 동적 컨텍스트 주입

#### Hooks 사용

- 도구 호출 검증/차단
- 자동 포맷팅/린팅
- 세션 시작/종료 시 작업
- 작업 완료 검증

### 4.3 조합 사용

```yaml
# Agent에서 Skill 사용
---
name: api-developer
description: API 엔드포인트 구현
skills:
  - api-conventions
  - error-handling
---

# Agent에서 Hook 사용
---
name: db-reader
description: 읽기 전용 DB 쿼리
tools: Bash
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./validate-readonly.sh"
---

# Skill에서 Hook 사용
---
name: secure-operations
description: 보안 검사와 함께 작업 수행
hooks:
  PreToolUse:
    - matcher: "Bash"
      hooks:
        - type: command
          command: "./security-check.sh"
---
```

---

## 참고 자료

- [공식 Skills 문서](https://code.claude.com/docs/en/skills)
- [공식 Hooks 문서](https://code.claude.com/docs/en/hooks)
- [공식 Sub-agents 문서](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Hook SDK](https://github.com/mizunashi-mana/claude-code-hook-sdk)
- [Everything Claude Code](https://github.com/affaan-m/everything-claude-code)
- [Awesome Claude Code](https://github.com/hesreallyhim/awesome-claude-code)
