# Claude Agent SDK Python 조사 결과

> 조사일: 2026-02-08

## 개요

Claude Agent SDK (Python)는 Anthropic이 공식 제공하는 Python SDK로, Claude Code를 구동하는 동일한 도구, 에이전트 루프, 컨텍스트 관리 기능을 프로그래밍 방식으로 사용할 수 있게 해준다. `pip install claude-agent-sdk`로 설치 가능하며, Python 3.10+ 환경이 필요하다. **API 없이는 사용할 수 없으며**, 반드시 Anthropic API 키 또는 Claude Pro/Max 구독이 필요하다.

## 상세 내용

### API 키 없이 사용 가능한가?

**결론: 불가능하다.** Claude Agent SDK는 다음 중 하나의 인증이 반드시 필요하다:

1. **Anthropic API 키 (종량제)**: `ANTHROPIC_API_KEY` 환경변수 설정. Console에서 발급. 구독 불필요, 사용한 만큼 과금.
2. **Claude Pro/Max 구독**: Claude Code CLI를 통한 인증. Pro($20/월) 또는 Max($100~200/월) 구독 필요.
3. **서드파티 클라우드 제공자**: Amazon Bedrock(`CLAUDE_CODE_USE_BEDROCK=1`), Google Vertex AI(`CLAUDE_CODE_USE_VERTEX=1`), Microsoft Azure(`CLAUDE_CODE_USE_FOUNDRY=1`) 경유 가능.

무료 티어는 존재하지 않는다. 로컬에서 실행되더라도 모델 추론은 Anthropic 서버에서 이루어지므로 네트워크 연결과 인증이 필수다.

**주의사항**: `ANTHROPIC_API_KEY` 환경변수가 설정되어 있으면, Claude Pro/Max 구독이 있어도 API 키 기반 종량제 과금이 우선 적용된다. 구독 기반으로 사용하려면 API 키 환경변수를 제거해야 한다.

### SDK 구조 및 핵심 기능

#### 두 가지 사용 방식

| 방식 | 용도 | 특징 |
|------|------|------|
| `query()` | 단발성 질의 | 간단, 대화 이력 불필요 시 |
| `ClaudeSDKClient` | 양방향 대화 | 컨텍스트 유지, 커스텀 도구, 훅 지원 |

#### 내장 도구

SDK에는 Claude Code와 동일한 내장 도구가 포함되어 있다:

- **Read/Write/Edit** - 파일 읽기/생성/수정
- **Bash** - 터미널 명령 실행
- **Glob/Grep** - 파일 탐색/내용 검색
- **WebSearch/WebFetch** - 웹 검색/페이지 조회
- **AskUserQuestion** - 사용자에게 질문

#### 커스텀 도구 (In-Process MCP 서버)

Python 함수를 `@tool` 데코레이터로 정의하여 Claude에게 제공할 수 있다. 별도 프로세스 없이 동일 프로세스에서 실행되므로 IPC 오버헤드가 없다.

```python
from claude_agent_sdk import tool, create_sdk_mcp_server

@tool("greet", "Greet a user", {"name": str})
async def greet_user(args):
    return {"content": [{"type": "text", "text": f"Hello, {args['name']}!"}]}

server = create_sdk_mcp_server(name="my-tools", version="1.0.0", tools=[greet_user])
```

#### 훅 (Hooks)

에이전트 루프의 특정 시점에 커스텀 로직을 주입할 수 있다:
- `PreToolUse` / `PostToolUse` - 도구 사용 전/후
- `SessionStart` / `SessionEnd` - 세션 시작/종료
- `Stop` - 에이전트 중지 시
- `UserPromptSubmit` - 사용자 프롬프트 제출 시

#### 서브에이전트

`AgentDefinition`으로 전문 에이전트를 정의하고 `Task` 도구를 통해 위임할 수 있다.

#### 세션 관리

`session_id`를 캡처하여 대화를 이어가거나(`resume`), 포크하여 다른 접근을 탐색할 수 있다.

### 설치 및 빠른 시작

```bash
pip install claude-agent-sdk
export ANTHROPIC_API_KEY=your-api-key
```

```python
import anyio
from claude_agent_sdk import query

async def main():
    async for message in query(prompt="What is 2 + 2?"):
        print(message)

anyio.run(main)
```

CLI는 패키지에 자동 번들되어 별도 설치 불필요. 시스템 설치 또는 특정 버전 사용 시 `ClaudeAgentOptions(cli_path="/path/to/claude")` 지정 가능.

### 릴리즈 현황

매우 활발하게 개발 중이며, 2026년 2월 기준 v0.1.33이 최신 버전이다:

- v0.1.33 (2026-02-07) - Latest
- v0.1.32 (2026-02-07)
- v0.1.31 (2026-02-06)
- v0.1.30 (2026-02-05)
- v0.1.29 (2026-02-04)

거의 매일 릴리즈가 이루어지고 있어 빠른 발전 속도를 보여준다.

### 경쟁 도구 비교

| 특성 | Claude Agent SDK | OpenAI AgentKit | Cline (오픈소스) |
|------|-----------------|-----------------|-----------------|
| 로컬 실행 | O (추론은 서버) | X (클라우드) | O |
| 커스텀 도구 | MCP 서버 | 함수 호출 | VS Code 확장 |
| 무료 사용 | X | X | O (자체 API 키 필요) |
| 권한 제어 | 세밀한 도구 권한 | 기본적 | 제한적 |
| 프로덕션 활용 | SDK 설계 목적 | 제품 임베딩 특화 | 개발자 보조 |

## 코드 예제

### 버그 찾기 에이전트

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    async for message in query(
        prompt="Find and fix the bug in auth.py",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Edit", "Bash"],
            permission_mode="acceptEdits"
        )
    ):
        print(message)

asyncio.run(main())
```

### 읽기 전용 코드 리뷰 에이전트

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    async for message in query(
        prompt="Review this code for best practices",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Glob", "Grep"],
            permission_mode="bypassPermissions"
        )
    ):
        if hasattr(message, "result"):
            print(message.result)

asyncio.run(main())
```

### MCP 서버 연동 (Playwright 브라우저 자동화)

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions

async def main():
    async for message in query(
        prompt="Open example.com and describe what you see",
        options=ClaudeAgentOptions(
            mcp_servers={
                "playwright": {"command": "npx", "args": ["@playwright/mcp@latest"]}
            }
        )
    ):
        if hasattr(message, "result"):
            print(message.result)

asyncio.run(main())
```

## 주요 포인트

- **API 키 필수**: 무료 사용 불가. Anthropic API 키(종량제) 또는 Claude Pro/Max 구독 필요
- **Claude Code 동일 기능**: Claude Code를 구동하는 모든 도구와 에이전트 루프를 프로그래밍 방식으로 사용 가능
- **In-Process MCP 서버**: 커스텀 도구를 별도 프로세스 없이 Python 함수로 정의하여 사용 가능
- **빠른 개발 속도**: 거의 매일 릴리즈, v0.1.33 (2026-02-07 기준)
- **서드파티 클라우드 지원**: AWS Bedrock, Google Vertex AI, Azure 경유 인증 가능

## 출처

- [GitHub - anthropics/claude-agent-sdk-python](https://github.com/anthropics/claude-agent-sdk-python)
- [Agent SDK overview - Claude API Docs](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Agent SDK Quickstart](https://platform.claude.com/docs/en/agent-sdk/quickstart)
- [Agent SDK Python Reference](https://platform.claude.com/docs/en/agent-sdk/python)
- [PyPI - claude-agent-sdk](https://pypi.org/project/claude-agent-sdk/)
- [Using Claude Code with Pro/Max plan](https://support.claude.com/en/articles/11145838-using-claude-code-with-your-pro-or-max-plan)
- [DataCamp Tutorial](https://www.datacamp.com/tutorial/how-to-use-claude-agent-sdk)
- [KDnuggets Getting Started Guide](https://www.kdnuggets.com/getting-started-with-the-claude-agent-sdk)
- [Claude Agent SDK Demos](https://github.com/anthropics/claude-agent-sdk-demos)
