# 좋은 AI Agents 작성법 조사 결과

> 조사일: 2026-02-08

## 개요

좋은 AI 에이전트를 작성하려면 **단순성을 우선**하고, 검증된 디자인 패턴을 적용하며, 프로덕션 환경에서 발생하는 실패 패턴을 사전에 방지해야 한다. Anthropic, Google, OpenAI 등 주요 기업들이 2025-2026년에 걸쳐 발표한 가이드라인을 종합하면, 가장 성공적인 에이전트 구현은 복잡한 프레임워크가 아니라 **단순하고 조합 가능한 패턴**으로 구축된 시스템이다.

## 상세 내용

### 1. 핵심 원칙 (Anthropic의 3가지 기본 원칙)

Anthropic은 에이전트 구축의 세 가지 기본 원칙을 제시한다:

1. **단순성(Simplicity)**: 에이전트 설계를 직관적으로 유지하고 불필요한 복잡성을 피한다. 간단한 프롬프트로 시작하여, 더 단순한 접근이 실패했을 때만 복잡성을 추가한다.
2. **투명성(Transparency)**: 에이전트의 계획 단계와 추론 과정을 명시적으로 표시한다.
3. **문서화 & 테스트**: 도구(Tool) 설계에 인간-컴퓨터 인터페이스(HCI)만큼의 정성을 들이고, 에이전트-컴퓨터 인터페이스(ACI) 사양을 철저히 문서화한다.

**핵심 구분**: Anthropic은 **워크플로우**(사전 정의된 코드 경로로 LLM 오케스트레이션)와 **에이전트**(LLM이 동적으로 프로세스와 도구 사용을 결정)를 명확히 구분한다.

### 2. 검증된 디자인 패턴

#### Anthropic의 워크플로우 패턴 5가지

| 패턴 | 설명 | 적합한 상황 |
|------|------|------------|
| **Prompt Chaining** | 작업을 순차적 단계로 분해, 각 LLM 호출이 이전 출력을 처리 | 명확한 하위 작업 분해가 가능한 고정 작업 |
| **Routing** | 입력을 분류하여 전문 핸들러로 전달 | 서로 다른 접근이 필요한 여러 입력 유형 |
| **Parallelization** | 독립 하위 작업을 동시 실행(Sectioning) 또는 동일 작업을 다중 실행(Voting) | 속도 최적화 또는 다양한 관점 필요 시 |
| **Orchestrator-Workers** | 중앙 LLM이 동적으로 작업 분해 후 워커에 위임 | 예측 불가능한 하위 작업 (예: 멀티파일 코드 변경) |
| **Evaluator-Optimizer** | 하나의 LLM이 응답 생성, 다른 LLM이 반복 피드백 제공 | 명확한 평가 기준이 있는 작업 |

#### Google의 8가지 멀티에이전트 디자인 패턴

1. **Sequential Pipeline**: 조립 라인처럼 에이전트가 순차적으로 출력을 전달. 선형적이고 결정론적이며 디버깅이 용이.
2. **Coordinator/Dispatcher**: 하나의 에이전트가 의사결정자로서 요청을 수신하고 전문 에이전트에 라우팅.
3. **Parallel Fan-Out/Gather**: 여러 에이전트가 동시 작업 후 합성 에이전트가 결과를 집계하고 승인/거부 결정.
4. **Hierarchical Decomposition**: 상위 에이전트가 복잡한 목표를 하위 작업으로 분해하여 계층적으로 위임.
5. **Generator and Critic**: 하나의 에이전트가 콘텐츠를 생성하고 다른 에이전트가 검증 및 피드백을 제공.
6. **Iterative Refinement**: Generator-Critic의 확장으로, 비평과 개선 에이전트가 반복적으로 협력.
7. **Human in the Loop**: 금융 거래나 프로덕션 배포 같은 비가역적 결정 시 인간 검토를 위해 실행을 일시 중지.
8. **Composite Pattern**: 이전 패턴들을 결합. 예: 코디네이터 + 병렬 처리 + Generator-Critic 루프.

### 3. 도구(Tool) 설계 베스트 프랙티스

Anthropic은 도구 설계를 전체 프롬프트 엔지니어링과 동등한 수준으로 다룰 것을 권장한다:

1. **포맷 선택**: 자연스러운 인터넷 텍스트에 맞는 포맷 사용 (코드 → JSON보다 마크다운 선호)
2. **토큰 효율성**: 모델이 생성 전 추론할 충분한 공간 제공
3. **오버헤드 최소화**: 줄 번호 세기나 문자열 이스케이핑 같은 포맷팅 요구 회피
4. **문서화**: 예제, 엣지 케이스, 입력 포맷 요구사항, 명확한 경계 포함
5. **Poka-Yoke 설계**: 상대 경로 대신 절대 경로 사용 등, 일반적 실수를 방지하도록 파라미터 재구성
6. **테스트**: 다양한 입력에서 도구 사용 검증, 실제 모델 동작 기반으로 정의 반복

### 4. 서브에이전트 안티패턴 (피해야 할 것들)

| 안티패턴 | 설명 | 대응 방안 |
|---------|------|----------|
| **불일치 활성화** | 명시적으로 이름을 지정하지 않으면 적합한 서브에이전트를 무시 | 에이전트 description을 명확히 작성하고 호출 조건을 구체화 |
| **상태 손실** | 에이전트 초안을 거부하면 새 복사본이 생성되어 컨텍스트 소실 | 반복 가능한 워크플로우 설계 |
| **중간 대화 불가** | 실행 중인 에이전트는 블랙박스처럼 동작, 방향 조정 불가 | 체크포인트 메커니즘 도입 |
| **불투명한 내부 동작** | 내부 도구 호출과 부분 사고가 숨겨져 디버깅 불가 | 로깅과 모니터링 강화 |
| **토큰 & 시간 낭비** | 다중 에이전트는 컨텍스트 윈도우를 급속히 소모 | 에이전트 수를 최소화하고 역할을 명확히 분리 |
| **에이전트 과다** | 긴 에이전트 목록은 관련성 신호를 희석, 선택에 시간 낭비 | 3-5개 이내로 유지, 중복 책임 제거 |
| **도구 범위 혼란** | 보편적 도구 접근은 노이즈를 유발 | 각 에이전트에 필요한 도구만 제한적으로 할당 |
| **얕은 출력** | 잘 정의된 에이전트도 최소 응답만 반환하는 경우 발생 | 프롬프트에 상세 출력 요구사항 명시 |

### 5. 프로덕션 실패 패턴과 방지

2024-2026년 프로덕션 AI 에이전트의 주요 실패 원인:

#### 아키텍처 실패
- **Dumb RAG**: 잘못된 메모리 관리. 모든 데이터를 벡터 DB에 덤프하면 컨텍스트 플러딩 발생
- **Brittle Connectors**: 취약한 I/O 연결. API 통합 실패가 LLM 품질보다 더 큰 문제
- **Polling Tax**: 이벤트 기반이 아닌 폴링 아키텍처로 인한 비효율

#### 메모리 관리 실패
- 모델의 컨텍스트 윈도우에만 의존하여 과거 상호작용을 "기억"하려는 시도
- 토큰 비용 급증, 중요 세부사항 사라짐, 추론 품질 저하

#### 보안 실패
- 에이전트에 API, 데이터베이스, 금융 액션에 대한 무제한 접근 권한 부여
- 프롬프트 인젝션으로 인한 데이터 손실, 미승인 환불, 정책 위반
- **대응**: 최소 권한 접근, 속도 제한, 로깅, 모니터링, 가드레일 적용

#### 비용 관리 실패
- 모든 작업에 비싼 추론 모델 사용
- **대응**: 작업 복잡도에 따라 모델 선택 (간단한 작업 → 빠른 모델, 복잡한 작업 → 고급 모델)

#### 테스트 부재
- "대화해보니 잘 되더라"는 테스트가 아님
- 구조화된 평가 없이 배포하면 엣지 케이스에서 실패, 업데이트 후 동작 드리프트

### 6. 프레임워크 비교 및 선택 가이드

| 프레임워크 | 철학 | 적합한 상황 |
|-----------|------|------------|
| **LangGraph** | 그래프 기반 워크플로우, 상태 관리 | 최대 제어력, 컴플라이언스, 프로덕션급 상태 관리가 필요한 미션 크리티컬 시스템 |
| **CrewAI** | 역할 기반 협업 설계 | 역할과 책임 중심으로 사고하는 팀, 빠른 프로토타이핑 |
| **AutoGen** | 에이전트 간 대화 기반 | 반복적 개선과 대화가 필요한 코드 생성, 연구, 창작 문제 해결 |
| **Claude Agent SDK** | 서브에이전트 기반 모듈러 설계 | Claude 기반 에이전트 구축, 파일/코드 작업 자동화 |

**Anthropic의 권장사항**: 프레임워크를 사용하기 전에 직접 LLM API로 시작하라. 많은 패턴이 최소한의 코드만 필요하며, 추상화 레이어가 프롬프트와 응답을 가리는 것에 주의하라.

### 7. Claude Agent SDK를 활용한 실전 패턴

#### 서브에이전트 정의 (AgentDefinition)

```python
from claude_agent_sdk import query, ClaudeAgentOptions, AgentDefinition

async def main():
    async for message in query(
        prompt="Use the code-reviewer agent to review this codebase",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Glob", "Grep", "Task"],
            agents={
                "code-reviewer": AgentDefinition(
                    description="Expert code reviewer for quality and security reviews.",
                    prompt="Analyze code quality and suggest improvements.",
                    tools=["Read", "Glob", "Grep"]
                )
            }
        )
    ):
        if hasattr(message, "result"):
            print(message.result)
```

#### 동적 에이전트 팩토리 패턴

```python
def create_security_agent(security_level: str) -> AgentDefinition:
    is_strict = security_level == "strict"
    return AgentDefinition(
        description="Security code reviewer",
        prompt=f"You are a {'strict' if is_strict else 'balanced'} security reviewer...",
        tools=["Read", "Grep", "Glob"],
        # 핵심: 고위험 리뷰에는 더 강력한 모델 사용
        model="opus" if is_strict else "sonnet"
    )
```

**AgentDefinition 구성 필드**:

| 필드 | 타입 | 필수 | 설명 |
|------|------|------|------|
| `description` | string | Yes | 에이전트 활용 시점을 자연어로 설명. Claude가 이 설명으로 서브에이전트 호출 시기를 판단 |
| `prompt` | string | Yes | 에이전트의 역할, 전문성, 행동 지침을 정의하는 시스템 프롬프트 |
| `tools` | string[] | No | 허용 도구 목록. 생략 시 부모 에이전트의 모든 도구 상속 |
| `model` | string | No | 특정 서브에이전트의 모델 오버라이드 (sonnet, opus, haiku, inherit) |

**제약사항**:
- 서브에이전트는 자신의 서브에이전트를 생성할 수 없음
- 서브에이전트의 tools 배열에 `Task` 도구를 포함하지 말 것
- 서브에이전트 호출을 위해 부모 에이전트의 allowedTools에 `Task` 포함 필수

### 8. 실전 적용 체크리스트

#### 설계 단계
- [ ] 단순한 프롬프트로 시작하고, 복잡성은 검증된 개선이 있을 때만 추가
- [ ] 워크플로우(결정론적)와 에이전트(자율적) 중 적절한 방식 선택
- [ ] 에이전트 수는 3-5개 이내로 유지
- [ ] 각 에이전트의 역할과 도구를 명확히 분리

#### 구현 단계
- [ ] 도구(Tool) 설계에 HCI 수준의 정성을 투입
- [ ] 도구 파라미터는 실수 방지(Poka-Yoke) 원칙 적용
- [ ] 에이전트 간 상태 전달 메커니즘 정의
- [ ] 인간 검토(Human-in-the-Loop) 체크포인트 설정

#### 보안 단계
- [ ] 최소 권한 원칙(Least Privilege) 적용
- [ ] 프롬프트 인젝션 방어 가드레일 구축
- [ ] API 접근에 속도 제한과 로깅 적용
- [ ] 민감 작업(금융, 삭제 등)에 명시적 승인 요구

#### 배포 단계
- [ ] 구조화된 평가(eval) 파이프라인 구축
- [ ] 다양한 엣지 케이스에서 테스트
- [ ] 비용 모니터링 및 모델 선택 최적화
- [ ] 에이전트 동작 드리프트 추적

## 코드 예제

### 최소 에이전트 루프 (Python - Claude Agent SDK)

```python
import asyncio
from claude_agent_sdk import query, ClaudeAgentOptions, AssistantMessage, ResultMessage

async def main():
    async for message in query(
        prompt="Review utils.py for bugs. Fix any issues you find.",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Edit", "Glob"],
            permission_mode="acceptEdits"
        )
    ):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if hasattr(block, "text"):
                    print(block.text)        # 추론 과정
                elif hasattr(block, "name"):
                    print(f"Tool: {block.name}")  # 도구 호출
        elif isinstance(message, ResultMessage):
            print(f"Done: {message.subtype}")     # 최종 결과

asyncio.run(main())
```

### 멀티에이전트 시스템 (Claude Agent SDK)

```python
async def run_multi_agent():
    async for message in query(
        prompt="Analyze this codebase for quality and security issues",
        options=ClaudeAgentOptions(
            allowed_tools=["Read", "Glob", "Grep", "Task"],
            agents={
                "code-reviewer": AgentDefinition(
                    description="Code quality and maintainability reviewer",
                    prompt="Analyze code quality, naming, structure, and suggest improvements.",
                    tools=["Read", "Glob", "Grep"],
                    model="sonnet"
                ),
                "security-reviewer": AgentDefinition(
                    description="Security vulnerability scanner",
                    prompt="Identify security vulnerabilities, injection risks, and unsafe patterns.",
                    tools=["Read", "Glob", "Grep"],
                    model="opus"  # 보안 리뷰에는 더 강력한 모델
                )
            }
        )
    ):
        if hasattr(message, "result"):
            print(message.result)
```

## 주요 포인트

1. **단순성 우선**: 복잡한 프레임워크보다 단순하고 조합 가능한 패턴이 더 성공적이다. 직접 LLM API로 시작하고, 검증된 개선이 있을 때만 복잡성을 추가하라.

2. **도구 설계 = 프롬프트 엔지니어링**: 도구(Tool)는 에이전트의 손과 발이다. Poka-Yoke 원칙으로 실수를 방지하고, 충분한 문서화와 테스트를 수행하라.

3. **에이전트 수 최소화**: 에이전트가 많을수록 토큰 소모, 선택 지연, 중복 작업이 증가한다. 3-5개 이내로 유지하고, 각각의 역할과 도구 범위를 명확히 분리하라.

4. **프로덕션 실패의 원인은 모델 품질이 아니라 아키텍처**: 메모리 관리, I/O 통합, 보안, 테스트 등 시스템 설계 문제가 대부분의 실패를 초래한다. 구조화된 eval 파이프라인이 필수다.

5. **보안은 설계 단계부터**: 최소 권한, 가드레일, 프롬프트 인젝션 방어를 초기부터 적용하라. 코드 실행이 가능한 에이전트는 강력한 엔지니어 계정처럼 관리해야 한다.

## 출처

- [Building Effective Agents - Anthropic](https://www.anthropic.com/research/building-effective-agents)
- [Google's Eight Essential Multi-Agent Design Patterns - InfoQ](https://www.infoq.com/news/2026/01/multi-agent-design-patterns/)
- [Choose a Design Pattern for Agentic AI - Google Cloud](https://docs.google.com/architecture/choose-design-pattern-agentic-ai-system)
- [AI Agent Orchestration Patterns - Microsoft Azure](https://learn.microsoft.com/en-us/azure/architecture/ai-ml/guide/ai-agent-design-patterns)
- [Common Sub-Agent Anti-Patterns - Steve Kinney](https://stevekinney.com/courses/ai-development/subagent-anti-patterns)
- [12 Failure Patterns of Agentic AI Systems - Concentrix](https://www.concentrix.com/insights/blog/12-failure-patterns-of-agentic-ai-systems/)
- [Claude Agent SDK Documentation](https://platform.claude.com/docs/en/agent-sdk)
- [AI Agent Frameworks Comparison 2026 - Medium](https://medium.com/@kia556867/best-ai-agent-frameworks-in-2026-crewai-vs-autogen-vs-langgraph-06d1fba2c220)
- [Best Practices for AI Agent Implementations 2026](https://onereach.ai/blog/best-practices-for-ai-agent-implementations/)
- [Common AI Agent Development Mistakes](https://www.wildnetedge.com/blogs/common-ai-agent-development-mistakes-and-how-to-avoid-them)
- [Microsoft AI Agents for Beginners](https://github.com/microsoft/ai-agents-for-beginners)
- [Agentic AI Design Patterns 2026 Edition](https://medium.com/@dewasheesh.rana/agentic-ai-design-patterns-2026-ed-e3a5125162c5)
