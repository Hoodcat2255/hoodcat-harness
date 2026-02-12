# Claude Code 에이전트-스킬 프롬프트 주입 관계 조사 결과

> 조사일: 2026-02-12

## 개요

Claude Code에서 에이전트(agents)와 스킬(skills)의 프롬프트가 어떻게 조합되는지 조사했다. 핵심 질문은 "에이전트에 지침을 넣으면 스킬에도 중복으로 넣어야 하는가?"이다. 공식 문서, GitHub 이슈, 시스템 프롬프트 분석, 커뮤니티 자료를 종합한 결과, **두 가지 실행 모드(인라인 vs. context: fork)에 따라 프롬프트 조합 방식이 완전히 다르다**는 것을 확인했다.

---

## 1. 두 가지 실행 모드

### 1.1 인라인 실행 (기본값, context: fork 없음)

스킬이 **메인 대화 컨텍스트에서 직접 실행**된다.

- SKILL.md의 body가 현재 대화에 사용자 메시지로 주입된다
- 메인 에이전트의 시스템 프롬프트, CLAUDE.md, 대화 이력이 모두 유지된다
- `agent` 필드는 **무시된다** (인라인이므로 서브에이전트를 생성하지 않음)
- `allowed-tools`만 활성화되어 도구 접근을 제한한다

```
[메인 시스템 프롬프트] + [CLAUDE.md] + [대화 이력] + [스킬 body 주입]
```

### 1.2 포크 실행 (context: fork)

스킬이 **격리된 서브에이전트에서 실행**된다.

- 새로운 컨텍스트 윈도우가 생성된다
- **에이전트 body가 시스템 프롬프트**로 사용된다
- **스킬 body가 태스크(사용자 프롬프트)**로 사용된다
- CLAUDE.md가 **함께 로드된다** (공식 문서의 테이블에서 확인)
- 부모 대화 이력은 **전달되지 않는다**

```
[에이전트 body = 시스템 프롬프트] + [CLAUDE.md] + [스킬 body = 태스크 프롬프트]
```

---

## 2. 공식 문서의 핵심 테이블

공식 문서(code.claude.com/docs/en/skills)에 명시된 두 방향의 비교표:

| 접근 방식 | System prompt 소유자 | Task (작업 내용) | 추가 로드 |
|:---|:---|:---|:---|
| Skill + `context: fork` | agent 타입 (Explore, Plan, 커스텀 등) | SKILL.md content | CLAUDE.md |
| Subagent + `skills` 필드 | Subagent의 markdown body | Claude의 delegation 메시지 | preloaded skills + CLAUDE.md |

> "With `context: fork` in a skill, the skill content is injected into the agent you specify. With `skills` in a subagent, the subagent controls the system prompt and loads skill content. Both use the same underlying system."
> -- 공식 문서

이 테이블에서 알 수 있는 핵심:
1. **context: fork 스킬**: 에이전트 body = 시스템 프롬프트, 스킬 body = 태스크
2. **skills 필드 서브에이전트**: 서브에이전트 body = 시스템 프롬프트, 스킬은 컨텍스트에 주입됨
3. **두 경우 모두 CLAUDE.md가 로드된다**

---

## 3. 서브에이전트의 시스템 프롬프트 구성

공식 문서(code.claude.com/docs/en/sub-agents)에 따르면:

> "The body becomes the system prompt that guides the subagent's behavior. Subagents receive only this system prompt (plus basic environment details like working directory), not the full Claude Code system prompt."

서브에이전트가 받는 프롬프트 구성:
1. **에이전트 body** (`.claude/agents/xxx.md`의 마크다운 부분) -- 시스템 프롬프트
2. **기본 환경 정보** (작업 디렉토리 등)
3. **CLAUDE.md** (system-reminder로 주입됨) -- Issue #24773에서 확인
4. **Task tool 기본 프롬프트** -- Piebald 레포에서 확인된 표준 지침
5. **태스크 내용** (스킬 body 또는 부모의 delegation 메시지) -- 사용자 메시지

**full Claude Code 시스템 프롬프트는 포함되지 않는다.** 이것은 메인 에이전트만 받는다.

### 3.1 실제 프롬프트 구성 순서 (추정)

Piebald-AI/claude-code-system-prompts 레포와 공식 문서를 종합하면:

```
[Agent body = Custom System Prompt]
  ↕ (에이전트 frontmatter의 tools, model, memory 등 적용)
[Task tool base prompt] -- "You are an agent for Claude Code..."
[Task tool extra notes] -- "Agent threads always have their cwd reset..."
[CLAUDE.md] -- system-reminder로 주입
[Memory instructions] -- memory 필드가 있으면 MEMORY.md 내용 포함
[Skill body / Parent delegation message] -- 실제 작업 지시
```

---

## 4. 핵심 질문에 대한 답변

### Q: 에이전트에 지침을 넣으면 스킬에도 중복으로 넣어야 하는가?

**아니다. 역할이 다르기 때문에 중복이 아니라 분담이다.**

- **에이전트 body**: "누구인지" (identity), "어떻게 동작하는지" (behavior) -- **시스템 프롬프트**
- **스킬 body**: "무엇을 할지" (task), "어떤 단계로 할지" (workflow) -- **태스크 프롬프트**

예시:
```markdown
# 에이전트 (coder.md body) -- 시스템 프롬프트 역할
You are a coding worker. Use absolute paths. Follow project conventions.
Build/test results are judged by exit codes only.

# 스킬 (implement/SKILL.md body) -- 태스크 역할
## Phase 0: Worktree 준비
## Phase 1: 컨텍스트 파악
## Phase 2: 코드 작성
...
```

### Q: 어떤 지침을 어디에 넣어야 하는가?

| 지침 유형 | 넣어야 할 위치 | 이유 |
|:---|:---|:---|
| 에이전트 정체성/역할 | 에이전트 body | 시스템 프롬프트로 항상 적용됨 |
| 도구 사용 원칙 | 에이전트 body | 모든 스킬에 공통 적용 |
| 검증 규칙 (exit code 확인 등) | 에이전트 body | 모든 작업에 공통 적용 |
| 워크플로우 단계 | 스킬 body | 작업별로 다름 |
| 작업별 세부 지침 | 스킬 body | 작업별로 다름 |
| 프로젝트 규칙/컨벤션 | CLAUDE.md | 자동으로 모든 에이전트에 주입 |
| 에이전트 간 공통 규칙 | harness.md (@import) | CLAUDE.md를 통해 자동 주입 |

### Q: CLAUDE.md는 서브에이전트에도 적용되는가?

**그렇다.** 공식 테이블에서 "Also loads: CLAUDE.md"로 명시되어 있다. 다만 Issue #24773에서 보고된 바와 같이, 이것이 때로는 문제가 된다. 특히 CLAUDE.md에 메인 에이전트 전용 지침(팀 리드 역할 등)이 있으면 서브에이전트와 충돌할 수 있다.

현재 CLAUDE.md 주입을 비활성화하는 공식 메커니즘은 없다 (Issue #24773이 OPEN 상태).

### Q: 스킬의 allowed-tools와 에이전트의 tools 필드의 관계는?

- **에이전트 tools**: 서브에이전트가 사용할 수 있는 도구의 allowlist
- **스킬 allowed-tools**: 인라인 실행 시 권한 없이 사용할 수 있는 도구

context: fork 실행 시에는 **에이전트의 tools가 적용되고 스킬의 allowed-tools는 무시된다** (에이전트가 실행 환경을 제어하므로). 인라인 실행 시에는 스킬의 allowed-tools가 메인 에이전트의 도구 권한에 추가된다.

---

## 5. 현재 프로젝트 (hoodcat-harness)의 구조 분석

현재 프로젝트의 구조를 이 조사 결과에 비추어 분석하면:

### 5.1 올바르게 설계된 부분

1. **에이전트와 스킬의 역할 분리**: workflow.md, coder.md 등의 body에는 정체성/원칙이, SKILL.md에는 워크플로우 단계가 들어 있다. 이는 올바른 패턴이다.

2. **CLAUDE.md + harness.md 분리**: 프로젝트 규칙을 CLAUDE.md에, 공통 지침을 harness.md에 넣고 @import로 주입하는 방식은 모든 에이전트에 자동 적용되므로 적절하다.

3. **에이전트에 검증 규칙 배치**: "Build/test results are judged by actual command exit codes only"가 에이전트 body에 있어 모든 스킬에 공통 적용된다.

### 5.2 잠재적 문제

1. **Worktree 지침 중복**: worktree 관련 지침이 에이전트 body(workflow.md, coder.md)와 스킬 body(implement/SKILL.md 등)에 모두 존재한다. 에이전트 body에는 원칙을, 스킬 body에는 구체적 단계를 넣는 것이 맞지만, 현재 구조에서는 중복이 있다.

2. **harness.md의 에이전트 전용 지침**: harness.md에 워크플로우 에이전트 관련 팀 운영 기준이 있는데, 이것이 researcher나 committer 같은 워커 에이전트에도 주입된다. 현재는 무해하지만 컨텍스트 효율성 면에서 비최적이다.

3. **Shared Context Protocol 중복**: 공유 컨텍스트 관련 지침이 모든 에이전트 body에 중복되어 있다. 이것은 CLAUDE.md/harness.md에 한 번만 넣으면 자동으로 모든 에이전트에 적용된다. 하지만 에이전트별로 기록 형식이 다르므로(Researcher Report vs. Workflow Report), 형식 부분만 에이전트에 유지하는 것이 적절하다.

### 5.3 개선 권고

1. **에이전트 body**: 정체성, 역할, 도구 사용 원칙, 검증 규칙, 에이전트별 고유 기록 형식만 유지
2. **스킬 body**: 워크플로우 단계, 작업별 세부 지침에 집중
3. **CLAUDE.md/harness.md**: 모든 에이전트에 공통인 규칙 (worktree 원칙, 검증 규칙 등)
4. **중복 제거**: 에이전트 body와 스킬 body에 동일한 지침이 있으면, 원칙은 에이전트/CLAUDE.md에, 구체적 단계는 스킬에만 유지

---

## 6. 알려진 이슈와 제한사항

### 6.1 context: fork 미작동 버그 (Issue #16803)

- Claude Code v2.1.0-2.1.1에서 `context: fork`가 작동하지 않아 스킬이 인라인으로 실행되는 버그가 보고됨
- 상태: OPEN (2026-02-12 기준)
- 영향: 이 버그가 해결되지 않은 버전에서는 `context: fork + agent` 조합이 의도대로 동작하지 않을 수 있음

### 6.2 Skill 도구에서 context: fork 무시 (Issue #17283)

- Skill 도구를 통해 프로그래밍적으로 호출할 때 `context: fork`와 `agent:` 필드가 무시됨
- 상태: CLOSED (중복으로 자동 종료, #16803 참조)
- 영향: `/skill-name`으로 직접 호출 시에는 작동하나, `Skill("name")` 호출 시 인라인 실행될 수 있음

### 6.3 CLAUDE.md 주입 비활성화 불가 (Issue #24773)

- 서브에이전트/팀원에게 CLAUDE.md가 항상 주입되어 정체성 충돌 발생
- 상태: OPEN
- 영향: CLAUDE.md에 메인 에이전트 전용 지침이 있으면 서브에이전트에도 적용되어 혼란 발생

### 6.4 스킬의 서브에이전트 전용 지정 불가 (Issue #12633)

- 특정 스킬을 서브에이전트에만 보이게 하고 메인 에이전트에서 숨기는 기능 없음
- 상태: OPEN
- 우회: `user-invocable: false` 또는 description에 "ONLY for xxx subagent" 추가

### 6.5 커맨드 기반 에이전트 스폰 + 스킬 주입 (Issue #14886)

- 슬래시 커맨드가 특정 에이전트를 스폰하면서 동적으로 스킬을 주입하는 기능 요청
- 상태: OPEN
- 관련: 모노레포에서 같은 에이전트를 다른 스킬 세트로 실행하는 유스케이스

---

## 7. 실용적 가이드라인

### 7.1 에이전트 body에 넣어야 할 것

```markdown
# [에이전트 이름] Agent

## Purpose
[정체성과 역할 - "You are a..."]

## Capabilities
[할 수 있는 것들]

## Constraints
[할 수 없는 것들]

## Working Principles
[도구 사용 원칙, 검증 규칙 등 모든 작업에 공통]

## Output Format
[이 에이전트 고유의 출력 형식]
```

### 7.2 스킬 body에 넣어야 할 것

```markdown
# [스킬 이름] Skill

## 입력
$ARGUMENTS: [인자 설명]

## 워크플로우
### Phase 1: [단계]
### Phase 2: [단계]
...

## 종료 조건
[완료 기준]

## 완료 보고
[보고 형식]
```

### 7.3 CLAUDE.md/harness.md에 넣어야 할 것

```markdown
## 프로젝트 규칙
[코딩 컨벤션, 네이밍, 에러 처리 패턴 등]

## 공통 지침
[모든 에이전트에 적용되는 원칙]
[worktree 규칙, 검증 규칙 등]
```

### 7.4 중복을 판단하는 기준

- **같은 문장이 에이전트 body와 스킬 body에 모두 있으면**: 에이전트 body에 유지 (모든 스킬에 적용)
- **같은 문장이 여러 에이전트 body에 있으면**: CLAUDE.md/harness.md로 이동 (자동 주입)
- **스킬별로 다른 구체적 단계면**: 스킬 body에만 유지

---

## 코드 예제

### context: fork + agent 조합의 실제 프롬프트 흐름

```
사용자: /implement auth 모듈 추가

[1] Claude가 implement SKILL.md 로드
    - frontmatter: context: fork, agent: workflow

[2] 새 서브에이전트 컨텍스트 생성
    - System Prompt = workflow.md body
      "You are a workflow orchestrator..."
    - + Task tool base prompt
      "You are an agent for Claude Code..."
    - + CLAUDE.md (system-reminder)
      프로젝트 규칙, harness.md 내용 포함
    - + Memory (MEMORY.md 처음 200줄)

[3] 스킬 body가 태스크로 주입
    User Message = implement/SKILL.md body
      "## Phase 0: Worktree 준비..."
      "ARGUMENTS: auth 모듈 추가"

[4] 서브에이전트가 자율 실행
    - workflow.md의 원칙에 따라 동작
    - SKILL.md의 단계를 순차 실행
    - CLAUDE.md의 프로젝트 규칙을 참조

[5] 결과 요약이 부모 대화로 반환
```

### 서브에이전트 skills 필드 조합의 실제 프롬프트 흐름

```
# 에이전트 정의 (api-developer.md)
---
name: api-developer
skills:
  - api-conventions
  - error-handling-patterns
---
Implement API endpoints.

[1] System Prompt = api-developer.md body
    "Implement API endpoints."
    + api-conventions/SKILL.md full content (주입됨)
    + error-handling-patterns/SKILL.md full content (주입됨)

[2] + CLAUDE.md (system-reminder)

[3] User Message = Claude의 delegation 메시지
    "POST /users 엔드포인트를 구현해줘"
```

---

## 주요 포인트

1. **context: fork가 있으면 에이전트 body = 시스템 프롬프트, 스킬 body = 태스크 프롬프트**이다. 역할이 다르므로 중복이 아니다.
2. **CLAUDE.md는 모든 서브에이전트에 자동 주입된다.** 따라서 프로젝트 공통 규칙은 CLAUDE.md에만 넣으면 된다.
3. **에이전트 body에는 정체성/원칙을, 스킬 body에는 워크플로우/단계를** 넣는 것이 올바른 패턴이다.
4. **여러 에이전트에 공통인 지침은 CLAUDE.md/harness.md에** 넣어 중복을 제거한다.
5. **context: fork 미작동 버그(#16803)가 OPEN 상태**이므로, 실제 동작을 확인할 때 주의가 필요하다.

---

## 출처

- [Claude Code Skills 공식 문서](https://code.claude.com/docs/en/skills)
- [Claude Code Sub-agents 공식 문서](https://code.claude.com/docs/en/sub-agents)
- [Issue #16803: context: fork doesn't work](https://github.com/anthropics/claude-code/issues/16803)
- [Issue #17283: Skill tool should honor context: fork and agent: fields](https://github.com/anthropics/claude-code/issues/17283)
- [Issue #24773: Allow teammates to use sub-agent MD instead of CLAUDE.md](https://github.com/anthropics/claude-code/issues/24773)
- [Issue #14886: Command-triggered agent spawning with skill injection](https://github.com/anthropics/claude-code/issues/14886)
- [Issue #12633: Allow skills to be hidden from the main agent](https://github.com/anthropics/claude-code/issues/12633)
- [Piebald-AI/claude-code-system-prompts](https://github.com/Piebald-AI/claude-code-system-prompts) -- Task tool 시스템 프롬프트 분석
- [Claude Agent Skills: First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Skills explained: How Skills compares to prompts, Projects, MCP, and subagents](https://claude.com/blog/skills-explained)
- [ClaudeLog: What is Context Fork](https://claudelog.com/faqs/what-is-context-fork-in-claude-code/)
