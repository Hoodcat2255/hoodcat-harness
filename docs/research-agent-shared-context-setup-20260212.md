# 에이전트 정의에서 공유 컨텍스트 설정 가능 여부 조사

> 조사일: 2026-02-12

## 개요

Claude Code 에이전트 정의 파일(`.claude/agents/*.md`)에서 "공유 컨텍스트"를 직접 세팅할 수 있는지 조사한 결과, **에이전트 frontmatter에 `additionalContext`를 직접 선언하는 공식 필드는 없다.** 그러나 에이전트 정의에서 지원하는 `hooks`, `skills`, 시스템 프롬프트(본문) 세 가지 메커니즘을 조합하면 동등한 효과를 달성할 수 있다.

## 상세 내용

### 1. 에이전트 frontmatter 공식 필드 목록

공식 문서(https://code.claude.com/docs/en/sub-agents)에 따르면, 에이전트 frontmatter에서 지원하는 필드는 다음과 같다:

| 필드 | 필수 | 설명 |
|------|------|------|
| `name` | Yes | 에이전트 식별자 |
| `description` | Yes | 언제 이 에이전트에 위임할지 |
| `tools` | No | 사용 가능한 도구 목록 |
| `disallowedTools` | No | 금지할 도구 |
| `model` | No | 사용할 모델 |
| `permissionMode` | No | 권한 모드 |
| `maxTurns` | No | 최대 턴 수 |
| `skills` | No | 스타트업 시 주입할 스킬 |
| `mcpServers` | No | MCP 서버 |
| `hooks` | No | 라이프사이클 훅 |
| `memory` | No | 영속 메모리 스코프 |

**`additionalContext`, `sharedContext`, `context` 같은 필드는 없다.**

### 2. 공유 컨텍스트를 세팅하는 3가지 방법

#### 방법 A: 에이전트 frontmatter의 `hooks` 필드 (현재 시스템과 동등)

에이전트 정의에 `hooks` 필드를 직접 넣어 `SubagentStart` 시점에 컨텍스트를 주입할 수 있다. **그러나 주의점이 있다**: 에이전트 frontmatter의 hooks는 **해당 에이전트가 활성화된 동안**만 실행된다. `SubagentStart`는 에이전트가 시작할 때 발생하지만, 이 훅은 settings.json에 정의해야 의미가 있다. 에이전트 자체 frontmatter에서 `SubagentStart`를 정의하면 "내가 서브에이전트를 생성할 때"의 이벤트에 반응하게 된다.

```yaml
---
name: researcher
hooks:
  # 이 에이전트가 서브에이전트를 생성할 때 실행 (이 에이전트 자신에게 주입되지 않음)
  SubagentStart:
    - hooks:
        - type: command
          command: "./shared-context-inject.sh"
  # Stop 이벤트는 SubagentStop으로 자동 변환
  Stop:
    - hooks:
        - type: command
          command: "./shared-context-collect.sh"
---
```

**핵심 구분**:
- **settings.json의 SubagentStart**: 메인 세션에서 서브에이전트가 생성될 때 발생 -> 서브에이전트에 컨텍스트 주입
- **에이전트 frontmatter의 SubagentStart**: 해당 에이전트(서브에이전트)가 또 다른 서브에이전트를 생성할 때 발생 -> 서브에이전트는 서브에이전트를 생성할 수 없으므로 **의미 없음**
- **에이전트 frontmatter의 Stop**: SubagentStop으로 변환되어 에이전트 종료 시 실행 -> 결과 수집에 활용 가능

따라서 **공유 컨텍스트 주입(inject)은 에이전트 frontmatter가 아닌 settings.json(또는 settings.local.json)에 정의해야 한다.** 결과 수집(collect)은 에이전트 frontmatter의 `Stop` 훅으로 가능하다.

#### 방법 B: `skills` 필드로 도메인 지식 주입

에이전트 frontmatter의 `skills` 필드를 사용하면 스타트업 시 스킬의 전체 내용이 에이전트 컨텍스트에 주입된다. 이는 **정적 컨텍스트**를 주입하는 데 적합하다.

```yaml
---
name: coder
skills:
  - api-conventions
  - error-handling-patterns
---
```

스킬 내용이 시작 시 전부 주입되므로, "공유 컨텍스트"가 **고정된 도메인 지식**이라면 이 방법이 가장 간단하다. 단, **동적 런타임 데이터**(이전 에이전트의 작업 결과 등)는 주입할 수 없다.

#### 방법 C: 시스템 프롬프트(에이전트 본문)에 직접 작성

에이전트 정의의 마크다운 본문이 시스템 프롬프트가 된다. 여기에 공유 컨텍스트 프로토콜 지침을 직접 작성하면, 에이전트가 이를 따라 행동한다. **현재 hoodcat-harness 시스템이 이 방식을 사용하고 있다.**

```markdown
## Shared Context Protocol

이전 에이전트의 작업 결과가 additionalContext로 주입되면, 이를 참고하여 중복 작업을 줄인다.
작업 완료 시, 핵심 발견 사항을 지정된 공유 컨텍스트 파일에 기록한다.
```

### 3. 현재 hoodcat-harness의 공유 컨텍스트 아키텍처 분석

현재 시스템은 다음과 같이 작동한다:

```
[settings.local.json]
    |
    +-- SubagentStart hook (전역)
    |   -> shared-context-inject.sh
    |   -> 이전 에이전트 결과를 additionalContext로 주입
    |   -> 기록 경로를 additionalContext로 전달
    |
    +-- SubagentStop hook (전역)
        -> shared-context-collect.sh
        -> 에이전트 결과를 _summary.md에 수집

[에이전트 정의 (.md)]
    -> 시스템 프롬프트에 "Shared Context Protocol" 섹션 포함
    -> additionalContext로 받은 정보를 참고하라는 지침
    -> 지정된 파일에 결과를 기록하라는 지침
```

**이 아키텍처의 장점**:
1. SubagentStart/SubagentStop 훅이 전역(settings.local.json)에 있으므로, 모든 에이전트에 일괄 적용
2. 에이전트별 차별화는 `shared-context-config.json`의 `filters`로 처리
3. 에이전트 정의의 시스템 프롬프트에 프로토콜 지침이 있어, 에이전트가 자발적으로 기록

### 4. 에이전트 정의에서 직접 할 수 있는 것 vs 할 수 없는 것

| 기능 | 에이전트 frontmatter에서 가능? | 방법 |
|------|-------------------------------|------|
| 정적 도메인 지식 주입 | O | `skills` 필드 |
| 공유 컨텍스트 프로토콜 지침 | O | 시스템 프롬프트(본문) |
| 결과 수집 (종료 시) | O | `hooks.Stop` (SubagentStop으로 변환) |
| 동적 컨텍스트 주입 (시작 시) | **X** | settings.json의 SubagentStart 필요 |
| 이전 에이전트 결과 읽기 | **X** (자동 주입 불가) | Hook 또는 에이전트가 직접 파일 읽기 |

### 5. 대안: 에이전트 frontmatter에서 Stop 훅으로 결과 수집 이동

현재 settings.local.json의 SubagentStop에서 실행하는 `shared-context-collect.sh`를 각 에이전트의 frontmatter `Stop` 훅으로 이동할 수 있다. 이렇게 하면:

**장점**: 에이전트별로 수집 로직을 커스터마이즈 가능
**단점**: 모든 에이전트에 중복 정의 필요, 유지보수 부담 증가

```yaml
---
name: researcher
hooks:
  Stop:
    - hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/hooks/shared-context-collect.sh"
---
```

그러나 **주입(inject) 부분은 여전히 settings.json에 남아야 한다**. 에이전트 frontmatter의 SubagentStart는 "이 에이전트가 다른 서브에이전트를 생성할 때" 실행되며, 서브에이전트는 서브에이전트를 생성할 수 없으므로 사실상 실행되지 않는다.

## 코드 예제

### 에이전트 정의에서 할 수 있는 최대한의 공유 컨텍스트 설정

```yaml
---
name: researcher
description: Research and planning worker
tools: Read, Write, Glob, Grep, Bash(gh *), Bash(git *), Task, WebSearch, WebFetch
mcpServers:
  - context7
model: opus
memory: project
skills:
  - shared-context-guide  # 정적 가이드라인을 스킬로 주입 (가능)
hooks:
  Stop:  # SubagentStop으로 변환됨
    - hooks:
        - type: command
          command: "$CLAUDE_PROJECT_DIR/.claude/hooks/shared-context-collect.sh"
---

# Researcher Agent

## Shared Context Protocol
# (시스템 프롬프트에 직접 작성 - 가능)
이전 에이전트의 작업 결과가 additionalContext로 주입되면 참고한다.
작업 완료 시, 핵심 발견 사항을 지정된 공유 컨텍스트 파일에 기록한다.
```

### settings.json에 반드시 남아야 하는 부분

```json
{
  "hooks": {
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/shared-context-inject.sh"
          }
        ]
      }
    ]
  }
}
```

## 주요 포인트

1. **에이전트 frontmatter에 `additionalContext`나 `sharedContext` 같은 직접적인 컨텍스트 주입 필드는 없다.**

2. **공유 컨텍스트 주입(inject)은 settings.json의 SubagentStart 훅에서만 가능하다.** 에이전트 frontmatter의 SubagentStart는 "에이전트가 서브에이전트를 생성할 때" 실행되므로, 서브에이전트인 에이전트 자신에게 컨텍스트를 주입하는 데 사용할 수 없다.

3. **에이전트 frontmatter에서 가능한 공유 컨텍스트 관련 설정**:
   - `skills` 필드: 정적 도메인 지식 주입
   - 시스템 프롬프트(본문): 공유 컨텍스트 프로토콜 지침 작성
   - `hooks.Stop`: SubagentStop으로 변환되어 결과 수집에 활용

4. **현재 hoodcat-harness의 아키텍처(settings.local.json 전역 훅 + 에이전트 시스템 프롬프트 지침)가 가장 적합한 패턴이다.** 에이전트 정의만으로는 동적 컨텍스트 주입을 자체 완결할 수 없다.

5. **부분적 이동은 가능하다**: 결과 수집(collect)을 에이전트 frontmatter의 Stop 훅으로 이동하면 에이전트별 커스터마이즈가 가능하지만, 주입(inject)은 여전히 전역 설정에 남아야 한다.

## 출처

- [Claude Code - Create custom subagents (공식 문서)](https://code.claude.com/docs/en/sub-agents) - 에이전트 frontmatter 필드 전체 목록, skills 필드, hooks 필드 설명
- [Claude Code - Hooks reference (공식 문서)](https://code.claude.com/docs/en/hooks) - SubagentStart/SubagentStop 이벤트, additionalContext 출력, 에이전트 frontmatter hooks 동작 방식
- [Feature Request #5812: Allow Hooks to Bridge Context Between Sub-Agents and Parent Agents](https://github.com/anthropics/claude-code/issues/5812) - 서브에이전트 간 컨텍스트 브릿징 요청 (NOT_PLANNED으로 종료)
- [Claude Code Release Notes - February 2026](https://releasebot.io/updates/anthropic/claude-code) - hooks/skills/memory frontmatter 필드 추가 이력
- [Claude Code 2.1 Agent Skills](https://medium.com/@richardhightower/build-agent-skills-faster-with-claude-code-2-1-release-6d821d5b8179) - hooks를 에이전트/스킬 frontmatter에 직접 추가 가능
