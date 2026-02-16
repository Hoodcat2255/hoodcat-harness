# LLM 병렬 도구 호출 유도 방법 심층 조사

> 조사일: 2026-02-17

## 개요

Claude(및 기타 LLM)가 단일 턴에서 여러 도구를 동시에 호출하도록 유도하는 방법에 대한 심층 조사 결과이다. 핵심 발견: Claude API는 기본적으로 병렬 도구 호출을 지원하지만, 모델이 이를 자발적으로 사용하는 빈도는 모델 버전, 프롬프트 설계, 도구 구조에 따라 크게 달라진다. Anthropic 공식 문서에서는 `<use_parallel_tool_calls>` 태그, batch tool 패턴, 그리고 Claude Code의 시스템 프롬프트 패턴 등 여러 유도 기법을 제시하고 있다. 그러나 Claude Code의 커스텀 에이전트(fork 컨텍스트)에서 Task/Skill 호출의 병렬화는 API 수준의 병렬 tool_use와는 다른 층위의 문제이다.

## 상세 내용

### 1. Claude API의 병렬 도구 호출 메커니즘

#### 기본 동작

Claude API는 기본적으로 병렬 도구 호출(parallel tool use)을 허용한다. 하나의 assistant 턴에서 여러 `tool_use` 블록을 포함할 수 있으며, 후속 user 메시지에서 모든 `tool_result`를 한꺼번에 제공해야 한다.

```
Assistant 턴: [text, tool_use_1, tool_use_2, tool_use_3]
User 턴:      [tool_result_1, tool_result_2, tool_result_3]
```

#### `disable_parallel_tool_use` 파라미터

`tool_choice` 객체 내에 `disable_parallel_tool_use` 필드가 있다:
- `false` (기본값): 모델이 여러 도구를 동시에 호출할 수 있음
- `true`: 모델이 정확히 1개의 도구만 호출함

```json
{
  "tool_choice": {
    "type": "auto",
    "disable_parallel_tool_use": false
  }
}
```

출처: Anthropic API 공식 문서 (platform.claude.com/docs/en/api)

#### 모델별 차이

Anthropic 공식 쿡북(`tool_use/parallel_tools.ipynb`)에서 명시적으로 언급:

> "Claude 3.7 Sonnet may be less likely to make parallel tool calls in a response, even when you have not set `disable_parallel_tool_use`."

이는 병렬 호출이 API 수준에서 허용되더라도, 모델의 학습 패턴에 따라 실제 병렬 호출 빈도가 달라진다는 것을 의미한다. Claude 4 계열 모델(Opus, Sonnet)에서는 개선되었지만, 여전히 프롬프트 유도가 필요한 경우가 있다.

### 2. 공식 프롬프트 유도 기법

#### 기법 A: `<use_parallel_tool_calls>` XML 태그

Anthropic 공식 문서에서 제시하는 가장 직접적인 방법:

```
<use_parallel_tool_calls>
For maximum efficiency, whenever you perform multiple independent operations,
invoke all relevant tools simultaneously rather than sequentially.
Prioritize calling tools in parallel whenever possible. For example, when
reading 3 files, run 3 tool calls in parallel to read all 3 files into
context at the same time. When running multiple read-only commands like
`ls` or `list_dir`, always run all of the commands in parallel. Err on
the side of maximizing parallel tool calls rather than running too many
tools sequentially.
</use_parallel_tool_calls>
```

출처: platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use

#### 기법 B: 시스템 프롬프트 지시문

더 간결한 버전:

```
For maximum efficiency, whenever you need to perform multiple independent
operations, invoke all relevant tools simultaneously rather than sequentially.
```

#### 기법 C: Claude Code의 시스템 프롬프트 패턴

Claude Code는 자체 시스템 프롬프트에서 다음과 같은 패턴을 사용한다:

```
You can call multiple tools in a single response. When multiple independent
pieces of information are requested and all commands are likely to succeed,
run multiple tool calls in parallel for optimal performance.
```

이 문구는 Claude Code의 모든 에이전트(메인, 서브)에 자동 주입되며, 특정 맥락(git 작업, 파일 읽기 등)에서 반복적으로 강조된다.

### 3. Batch Tool 패턴 (공식 워크어라운드)

#### 문제 상황

일부 모델이 병렬 호출을 자발적으로 하지 않는 경우, Anthropic은 "batch tool"이라는 메타 도구를 도입하는 워크어라운드를 공식 쿡북에서 제시한다.

#### 구현

```python
batch_tool = {
    "name": "batch_tool",
    "description": "Invoke multiple other tool calls simultaneously",
    "input_schema": {
        "type": "object",
        "properties": {
            "invocations": {
                "type": "array",
                "description": "The tool calls to invoke",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {
                            "type": "string",
                            "description": "The name of the tool to invoke"
                        },
                        "arguments": {
                            "type": "string",
                            "description": "The arguments to the tool"
                        }
                    },
                    "required": ["name", "arguments"]
                }
            }
        },
        "required": ["invocations"]
    }
}
```

#### 효과

쿡북의 실험 결과, batch_tool을 도구 목록에 추가하는 것만으로도 모델이 자발적으로 이를 사용하여 여러 도구를 한 번에 호출하는 경향이 크게 증가했다. 이는 모델에게 "병렬로 묶어서 호출할 수 있다"는 명시적인 인터페이스를 제공하기 때문이다.

출처: anthropics/anthropic-cookbook/tool_use/parallel_tools.ipynb

### 4. Claude Code 커스텀 에이전트에서의 병렬 호출 문제

#### 문제 분석

현재 Orchestrator가 Skill()과 Task()를 항상 순차적으로 호출하는 이유는 여러 층위에서 분석해야 한다:

**층위 1: API 수준 (tool_use)**
- Claude Code는 내부적으로 Claude API를 사용하며, 에이전트의 각 "턴"은 하나의 API 호출에 해당
- API 수준에서 병렬 tool_use는 지원됨 (모델이 한 턴에서 여러 tool_use 블록 반환)
- 하지만 Claude Code가 `disable_parallel_tool_use`를 어떻게 설정하는지는 외부에서 제어 불가

**층위 2: Claude Code 런타임**
- Claude Code의 도구(Task, Skill, Bash, Read 등)는 Claude Code 런타임이 관리
- 모델이 한 턴에서 여러 도구를 호출하면, Claude Code 런타임이 이를 병렬로 실행할 수 있음
- 실제로 Claude Code의 시스템 프롬프트에는 "You can call multiple tools in a single response"라는 지시가 포함됨

**층위 3: fork 컨텍스트 제약**
- Skill()과 Task()는 `context: fork`로 별도 프로세스에서 실행됨
- fork된 에이전트는 독립적인 컨텍스트를 가짐
- 이론적으로 여러 fork를 동시에 시작할 수 있음 (에이전트팀 병렬 패턴이 이를 증명)

**층위 4: 모델 행동 패턴**
- 473회 도구 호출 중 병렬 0건이라는 관찰은, 모델이 Orchestrator 맥락에서 Skill/Task를 순차적으로 호출하는 것이 "안전한" 기본 패턴임을 시사
- 코드 변경 작업은 본질적으로 순차적 의존성이 많아 (code → test → review → commit), 모델이 보수적으로 순차 실행을 선택할 가능성이 높음
- 프롬프트에 병렬 호출 지시를 넣어도, 모델의 RLHF 학습 패턴이 이를 override할 수 있음

#### Task() vs Skill()의 병렬 호출 가능성

**기술적으로 가능한 경우:**
- `Task(navigator, ...)` + `Skill("deepresearch", ...)` — 독립적 정보 수집
- `Task(reviewer, ...)` + `Task(security, ...)` — 독립적 리뷰
- 에이전트팀(TeamCreate + TaskCreate × N)으로 병렬 실행 — 이미 작동하는 패턴

**기술적으로 불확실한 경우:**
- 일반 Task/Skill 호출의 병렬화는 Claude Code가 `run_in_background` 패턴을 지원하는지에 의존
- Claude Code의 시스템 프롬프트에서 "run multiple tool calls in parallel" 지시가 있으므로, Task/Skill도 병렬 호출이 가능할 수 있으나, 모델이 자발적으로 이를 수행하는지는 별개 문제

### 5. 다른 에이전트 프레임워크의 병렬 실행 접근법

#### Anthropic 공식 패턴: Orchestrator-Workers

Anthropic 쿡북(`patterns/agents/orchestrator_workers.ipynb`)에서 제시하는 패턴:
1. Orchestrator가 태스크를 분석하고 서브태스크로 분해
2. 각 Worker가 독립적으로 서브태스크 실행
3. 결과 수집 및 종합

핵심: 이 패턴은 **프레임워크 수준**에서 `asyncio.gather()` 등으로 병렬 실행을 강제한다. LLM에게 "병렬로 호출해줘"라고 부탁하는 것이 아니라, 프레임워크가 분해된 태스크를 동시에 실행한다.

```python
# 프레임워크가 강제하는 병렬 실행 (개념)
import asyncio

async def orchestrate(tasks):
    # Orchestrator가 분해한 서브태스크를 동시 실행
    results = await asyncio.gather(*[
        execute_worker(task) for task in subtasks
    ])
    return synthesize(results)
```

#### LangChain / LangGraph

- `RunnableParallel`로 여러 체인을 명시적으로 병렬 실행
- 그래프 기반 실행에서 분기(fork) 노드 이후 병렬 실행 가능
- LLM에게 병렬 호출을 요청하는 것이 아니라, 프레임워크가 실행 그래프를 분석하여 독립 노드를 동시 실행

#### CrewAI

- `Process.hierarchical` 모드에서 Manager Agent가 태스크를 분배
- `async_execution=True`로 태스크 병렬 실행 명시
- 역시 프레임워크 수준에서 강제

#### 공통 패턴

모든 프레임워크는 **LLM에게 병렬 호출을 부탁하지 않는다**. 대신:
1. LLM이 태스크를 분해 (계획 단계)
2. 프레임워크가 독립적인 태스크를 식별
3. 프레임워크가 병렬 실행을 강제 (asyncio, threading 등)

### 6. 구조적 강제 방법

#### 방법 A: 에이전트팀 패턴 활용 (현재 가능)

Claude Code의 에이전트팀(TeamCreate/TaskCreate/SendMessage)은 이미 병렬 실행을 지원한다. Orchestrator가 이를 활용하면 구조적으로 병렬화를 달성할 수 있다.

```
# 현재 가능한 병렬 패턴
TeamCreate(tasks: [
  { description: "코드베이스 탐색", agent: "navigator" },
  { description: "기술 조사", agent: "researcher" }
])
# → 두 에이전트가 동시에 실행됨
```

장점: 이미 작동하는 메커니즘
단점: 가벼운 병렬 작업에도 에이전트팀 오버헤드가 발생

#### 방법 B: PreToolUse 훅으로 배치 수집

개념: Orchestrator의 순차 Tool 호출을 훅에서 가로채서 배치로 모아 동시 실행하는 미들웨어 패턴.

문제점:
- Claude Code 훅의 PreToolUse는 도구 호출을 수정하거나 지연시킬 수 있지만, 여러 호출을 모아서 동시 실행하는 메커니즘은 없음
- PreToolUse는 개별 도구 호출에 대해 동기적으로 실행됨

결론: 현재 Claude Code 훅으로는 불가능

#### 방법 C: 파이프라인 시스템 (설계 완료, 미구현)

현재 설계된 파이프라인 시스템(Fork/Join 노드)이 구조적 병렬화의 정답이 될 수 있다:
- Fork 노드에서 독립 브랜치를 분기
- 각 브랜치를 별도 에이전트/스킬로 동시 실행
- Join 노드에서 결과 수집 (wait_policy: all/any/n_of)

이 방식은 LLM에게 병렬 호출을 부탁하는 것이 아니라, 파이프라인 런타임이 실행 그래프를 분석하여 강제한다.

#### 방법 D: Orchestrator 프롬프트 최적화

현재 Orchestrator 프롬프트에 이미 병렬 호출 지침이 있지만, 더 강화할 수 있는 방법:

1. **XML 태그 유도** (공식 권장):
```
<use_parallel_tool_calls>
독립적인 Skill/Task 호출은 반드시 한 턴에서 동시에 수행하라.
예: Task(navigator)와 Skill("deepresearch")가 서로의 결과를 필요로 하지 않으면,
두 호출을 같은 응답에서 함께 수행하라.
</use_parallel_tool_calls>
```

2. **Few-shot 예시 추가**:
```
# 좋은 예 (한 턴에서 2개 동시 호출):
<assistant>
독립적인 탐색과 조사를 병렬로 시작합니다.
[Task(navigator, "코드베이스 구조 파악")]
[Skill("deepresearch", "관련 기술 조사")]
</assistant>

# 나쁜 예 (불필요한 순차 호출):
<assistant>
먼저 코드베이스를 탐색하겠습니다.
[Task(navigator, "코드베이스 구조 파악")]
</assistant>
<assistant>
탐색 결과를 바탕으로 기술 조사를 시작합니다.  # ← 실제로는 탐색 결과를 참조하지 않음
[Skill("deepresearch", "관련 기술 조사")]
</assistant>
```

3. **자기 검증 체크리스트 추가**:
```
매 Skill/Task 호출 전에 확인:
- 이 호출이 이전 호출의 결과를 필요로 하는가?
  - YES → 순차 실행 (이전 결과 대기)
  - NO → 현재 턴에서 다른 독립 호출과 함께 동시 수행
```

### 7. Claude Code의 내부 병렬 도구 실행 메커니즘

Claude Code의 시스템 프롬프트에는 다음이 포함되어 있다 (직접 관찰):

```
You can call multiple tools in a single response. When multiple independent
pieces of information are requested and all commands are likely to succeed,
run multiple tool calls in parallel for optimal performance.
```

이 지시는 특정 도구 조합에 대해 반복적으로 강조된다:
- Git 작업 (git status와 git diff를 병렬로)
- 파일 읽기 (여러 파일을 동시에 Read)
- PR 생성 시 여러 정보를 병렬 수집

그러나 이것이 Task/Skill 같은 "무거운" 도구에도 적용되는지는 명시적으로 언급되지 않는다. Read, Bash 같은 가벼운 도구에서는 병렬 호출이 자연스럽지만, fork 컨텍스트를 생성하는 Task/Skill은 모델이 보수적으로 접근할 수 있다.

### 8. GitHub 이슈에서 발견된 관련 문제

- `anthropics/claude-code#25714` - "Uncontrolled background agent parallelization causes context overflow, session death, and wasted tokens": 병렬 에이전트가 과도하게 생성되면 컨텍스트 오버플로우가 발생하는 문제. 이는 병렬 실행에 상한선이 필요함을 시사한다.

- `anthropics/claude-code#22472` - "git worktree fails with 'branch already used' when parallel agents attempt same branch": 병렬 에이전트가 같은 브랜치를 사용하려 할 때 충돌. 병렬 실행 시 리소스 격리가 중요하다.

- `anthropics/anthropic-sdk-python#739` - "`disable_parallel_tool_use` is not permitted": SDK에서 이 파라미터 사용에 문제가 있었던 이슈 (해결됨).

## 코드 예제

### API 수준에서 병렬 도구 호출 유도

```python
from anthropic import Anthropic

client = Anthropic()

# 방법 1: 시스템 프롬프트로 유도
system_prompt = """
<use_parallel_tool_calls>
For maximum efficiency, whenever you perform multiple independent operations,
invoke all relevant tools simultaneously rather than sequentially.
Prioritize calling tools in parallel whenever possible.
</use_parallel_tool_calls>
"""

# 방법 2: disable_parallel_tool_use가 false인지 확인 (기본값)
response = client.messages.create(
    model="claude-opus-4-6",
    system=system_prompt,
    messages=[{"role": "user", "content": "SF와 NYC의 날씨와 시간을 알려줘"}],
    tools=[weather_tool, time_tool],
    tool_choice={"type": "auto", "disable_parallel_tool_use": False}
)

# 결과: tool_use 블록이 여러 개 반환될 수 있음
tool_uses = [b for b in response.content if b.type == "tool_use"]
print(f"병렬 호출 수: {len(tool_uses)}")
```

### Batch Tool 패턴 (Sonnet 등 순차 경향 모델 대응)

```python
batch_tool = {
    "name": "batch_tool",
    "description": "Invoke multiple other tool calls simultaneously",
    "input_schema": {
        "type": "object",
        "properties": {
            "invocations": {
                "type": "array",
                "description": "The tool calls to invoke",
                "items": {
                    "type": "object",
                    "properties": {
                        "name": {"type": "string"},
                        "arguments": {"type": "string"}
                    },
                    "required": ["name", "arguments"]
                }
            }
        },
        "required": ["invocations"]
    }
}

# 기존 도구 목록에 batch_tool 추가
tools = [weather_tool, time_tool, batch_tool]

# 모델이 자발적으로 batch_tool을 사용하여 여러 도구를 묶어 호출
```

### Orchestrator 프롬프트 병렬 호출 강화 제안

```markdown
<use_parallel_tool_calls>
독립적인 Skill() 및 Task() 호출은 반드시 같은 턴에서 동시에 수행하라.

판단 기준:
- 호출 A의 결과가 호출 B의 입력에 필요한가?
  - YES → 순차 (A 완료 후 B)
  - NO → 같은 턴에서 A와 B를 동시 호출

예시 (병렬):
Task(navigator, "코드 구조 파악")  ← 동시 시작
Skill("deepresearch", "기술 조사") ← 동시 시작

예시 (순차 - 의존성 있음):
Skill("code", "구현") → Skill("test", "테스트") → Skill("commit")
</use_parallel_tool_calls>
```

## 주요 포인트

1. **API는 병렬을 지원하지만 모델은 보수적**: `disable_parallel_tool_use: false`가 기본값이지만, 모델이 실제로 병렬 호출을 수행하는 빈도는 모델 버전과 맥락에 따라 크게 다르다. 프롬프트 유도가 필수.

2. **공식 유도 기법 3가지**: (a) `<use_parallel_tool_calls>` XML 태그, (b) 시스템 프롬프트 지시문, (c) batch tool 메타 도구. Anthropic이 직접 권장하는 방법들이다.

3. **Claude Code 서브에이전트의 병렬 호출은 기술적으로 가능하나 모델이 선호하지 않음**: Claude Code 시스템 프롬프트에 "multiple tools in a single response" 지시가 있지만, Task/Skill 같은 무거운 fork 도구에 대해서는 모델이 순차 실행을 선호하는 경향이 강하다.

4. **프레임워크 수준 강제가 정답**: LangChain, CrewAI, Anthropic 쿡북 패턴 모두 "LLM에게 병렬 호출을 부탁"하지 않는다. 프레임워크가 독립 태스크를 식별하고 `asyncio.gather()`등으로 동시 실행을 강제한다. 현재 시스템에서는 파이프라인의 Fork/Join 노드가 이 역할을 할 수 있다.

5. **현실적 접근법 조합**: (a) Orchestrator 프롬프트에 `<use_parallel_tool_calls>` 태그 + few-shot 예시 추가, (b) 병렬이 필요한 패턴에서 에이전트팀(TeamCreate) 활용, (c) 장기적으로 파이프라인 시스템의 Fork/Join으로 구조적 병렬화 달성.

## 출처

- Anthropic 공식 문서: Tool Use 구현 가이드 - https://platform.claude.com/docs/en/agents-and-tools/tool-use/implement-tool-use
- Anthropic 공식 문서: Tool Use 개요 (Parallel tool use) - https://platform.claude.com/docs/en/agents-and-tools/tool-use/overview
- Anthropic API 문서: tool_choice 및 disable_parallel_tool_use - https://platform.claude.com/docs/en/api
- Anthropic Cookbook: parallel_tools.ipynb (Batch Tool 패턴) - https://github.com/anthropics/anthropic-cookbook/blob/main/tool_use/parallel_tools.ipynb
- Anthropic Cookbook: Orchestrator-Workers 패턴 - https://github.com/anthropics/anthropic-cookbook/blob/main/patterns/agents/orchestrator_workers.ipynb
- Claude Code GitHub: 병렬 에이전트 관련 이슈 #25714, #22472 - https://github.com/anthropics/claude-code/issues/25714
- Claude Code 플러그인 문서: MCP Tool Usage 병렬 호출 - https://github.com/anthropics/claude-code/blob/main/plugins/plugin-dev/skills/mcp-integration/references/tool-usage.md

## 부록: hoodcat-harness Orchestrator에 대한 구체적 권고

### 즉시 적용 가능 (프롬프트 수정)

1. Orchestrator 에이전트 프롬프트(`.claude/agents/orchestrator.md`)의 Parallel Invocation 섹션에 `<use_parallel_tool_calls>` XML 태그 추가
2. 구체적인 병렬 호출 few-shot 예시 추가 (Task + Skill 동시 호출 패턴)
3. "매 턴마다 이전 호출의 결과가 다음 호출에 필요한지 자기 검증" 체크리스트 강화

### 단기 적용 가능 (구조적 변경)

4. 병렬이 명확한 패턴(탐색+리서치, 다중 리뷰)에서 에이전트팀 패턴을 기본으로 사용하도록 레시피 수정
5. 에이전트팀의 오버헤드를 줄이기 위해 "경량 팀" 패턴 도입 검토

### 장기 적용 (파이프라인 시스템)

6. 파이프라인 JSON의 Fork/Join 노드를 활용한 구조적 병렬화
7. 파이프라인 런타임이 독립 노드를 자동으로 병렬 실행하도록 구현
8. Orchestrator가 파이프라인을 실행할 때 Fork 노드 이후 브랜치를 동시 실행

### 실험 제안

9. `<use_parallel_tool_calls>` 태그 추가 전/후로 동일 작업을 5회씩 실행하여 병렬 호출 빈도 비교
10. Batch tool 패턴을 Claude Code 커스텀 도구로 구현 가능한지 검증 (Claude Code 플러그인/MCP 활용)
