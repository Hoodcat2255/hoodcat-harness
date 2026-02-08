# AI 코딩 에이전트 구현 전략 판단 결과

> 판단일: 2026-02-08

## 결정 요약

**권고**: **Claude Agent SDK (Python/TypeScript) 기반으로 커스텀 에이전트를 구현**하되, my-harness의 오케스트레이션 로직을 SDK 위에 재구현하는 방식 추천

**확신도**: 중간-높음 - my-harness가 이미 상당히 성숙한 오케스트레이션 시스템을 갖추고 있어, "완전히 새로 만들기"보다 "기존 자산 활용 + SDK 기반 재구현"이 현실적

## 배경: 현재 상황 분석

### my-harness 현황
- **20개 전문 에이전트** (Product, Strategy, Engineering, QA, DevOps, Research, Architecture 팀)
- **멀티 에이전트 오케스트레이션**: 위임 플로우차트, 병렬 실행, 회의 시스템
- **Tier 기반 스킬 체계**: fullstack(Tier 3) > ultrawork(Tier 2) > superplan/superanalyze/superforge(Tier 1)
- **인프라**: Hooks(로깅, 변경 추적), 메모리 시스템(영속+시맨틱 검색), 대시보드, 메시지 큐
- **한계**: bash 스크립트 기반 CLI, Claude Code에 종속적, 독립 실행 불가

### 시장 현황 (2026.02 기준)
| 도구 | 언어 | TUI | GitHub Stars | 특징 |
|------|------|-----|-------------|------|
| **OpenCode** | Go | Bubble Tea | 97K+ | 75+ 모델 지원, 클라이언트/서버 아키텍처 |
| **Aider** | Python | readline | 40K+ | Git 통합 최강, 가장 성숙 |
| **Claude Code** | TypeScript | Ink (React) | 비공개 | Anthropic 공식, Agent SDK 기반 |
| **Gemini CLI** | TypeScript | - | 50K+ | Google 공식, 프론트엔드 강점 |
| **OpenAI Codex** | Rust | Ratatui | - | 네이티브 바이너리, 최고 성능 |

## 후보 분석

### 후보 A: Go + Bubble Tea (OpenCode 방식)

OpenCode가 검증한 스택. Go의 컴파일 바이너리 + Bubble Tea의 Elm Architecture TUI.

- **장점**:
  - 단일 바이너리 배포 (설치 간편)
  - 뛰어난 동시성 처리 (goroutine)
  - Bubble Tea의 선언적 UI 모델 (Model-Update-View)
  - SQLite 기반 세션 관리
  - 97K+ stars 커뮤니티 검증
- **단점**:
  - Go 학습 곡선 (기존 스킬셋과 다를 경우)
  - AI SDK 생태계가 Python/TS 대비 빈약
  - 프로토타이핑 속도 느림
  - my-harness의 기존 로직(bash/markdown) 재작성 필요량 큼
- **적합한 경우**: 성능과 배포 편의성이 최우선이고, Go에 익숙한 경우

### 후보 B: Python + Claude Agent SDK

Anthropic 공식 Claude Agent SDK를 활용. Claude Code와 동일한 인프라 사용 가능.

- **장점**:
  - **Claude Code와 동일한 에이전트 루프** 사용 가능
  - 커스텀 도구, 훅(PreToolUse/PostToolUse), MCP 서버 통합 내장
  - my-harness의 오케스트레이션 로직을 SDK 훅으로 자연스럽게 이식 가능
  - Pydantic 기반 타입 안전 도구 정의
  - 서브에이전트, 세션 관리, 메시지 컴팩션 내장
  - Python AI 생태계 풍부 (LangChain, LiteLLM 등과 호환)
  - Xcode, VS Code 등 IDE 통합 사례 존재 (2026.02)
- **단점**:
  - Anthropic(Claude) 종속 (다른 LLM 사용 시 별도 처리)
  - Python 런타임 필요
  - TUI를 직접 구현해야 함 (Textual, Rich 등 별도 라이브러리)
  - 배포가 Go 대비 복잡
- **적합한 경우**: Claude 중심으로 사용하고, 기존 my-harness 자산을 최대 활용하고 싶은 경우

### 후보 C: TypeScript + Ink (React) (Claude Code 방식)

Claude Code가 사용하는 스택. React 기반 터미널 UI.

- **장점**:
  - Claude Code와 동일한 기술 스택
  - React 패러다임으로 UI 컴포넌트화
  - npm 생태계 활용 (Zod, Anthropic SDK 등)
  - Claude Agent SDK TypeScript 버전 사용 가능
  - 스트리밍 응답 처리가 자연스러움
- **단점**:
  - Node.js 런타임 필요
  - Ink의 레이아웃 제약 (CSS 일부만 지원)
  - React 터미널 렌더링 성능 이슈 가능
  - 멀티 에이전트 오케스트레이션 구현이 Python 대비 번거로움
- **적합한 경우**: TypeScript/React에 익숙하고, Claude Code와 유사한 UX를 원하는 경우

### 후보 D: Rust + Ratatui (Codex CLI 방식)

OpenAI Codex CLI가 검증. 네이티브 성능 + Ratatui TUI.

- **장점**:
  - 최고 성능 (60+ FPS TUI, 메모리 효율)
  - 단일 바이너리 배포
  - Netflix, OpenAI, AWS, Vercel 검증
  - 메모리 안전성
- **단점**:
  - Rust 학습 곡선 가장 가파름
  - AI SDK 생태계 최빈약
  - 프로토타이핑 속도 최느림
  - 오케스트레이션 로직 구현 복잡도 높음
- **적합한 경우**: 시스템 프로그래밍 경험 풍부, 최고 성능이 필수인 경우

### 후보 E: 기존 my-harness 점진적 강화

현재 bash 스크립트 + markdown 기반 시스템을 그대로 유지하면서 기능 추가.

- **장점**:
  - 즉시 사용 가능 (이미 동작 중)
  - 20개 에이전트, 스킬 체계, 훅, 메모리 시스템 등 완성도 높음
  - Claude Code 생태계와 완벽 통합
  - 신규 개발 비용 없음
- **단점**:
  - Claude Code에 완전 종속 (독립 실행 불가)
  - bash 스크립트 유지보수 한계
  - TUI 없음 (Claude Code의 UI에 의존)
  - 다른 LLM 사용 불가
  - 배포/공유가 심볼릭 링크 기반으로 제한적
- **적합한 경우**: Claude Code 사용을 계속할 예정이고, 독립 도구가 불필요한 경우

## 평가 매트릭스

| 기준 | Go+BubbleTea | Python+AgentSDK | TS+Ink | Rust+Ratatui | my-harness 강화 |
|------|:-----------:|:---------------:|:------:|:------------:|:--------------:|
| **my-harness 자산 활용** | C | A | B | D | A+ |
| **프로토타이핑 속도** | B | A | A | D | A+ |
| **TUI 품질** | A | B | B+ | A+ | N/A |
| **멀티 에이전트 구현** | B | A | B | C | A (이미 완성) |
| **배포 편의** | A | C | C | A | D (종속적) |
| **LLM 유연성** | A | C | C | B | D |
| **성능** | A | C | C | A+ | B |
| **생태계/커뮤니티** | A | A | A | C | D |
| **독립성** | A | A | A | A | F |
| **유지보수성** | B | A | A | B | C |

## 트레이드오프

### "Claude Agent SDK 기반 재구현"을 선택하면:
- **얻는 것**: Claude Code와 동일한 에이전트 루프, 내장 도구/훅/세션 관리, my-harness 오케스트레이션을 SDK 네이티브로 이식, Python AI 생태계 전체 활용
- **잃는 것**: 다른 LLM 사용 유연성, 단일 바이너리 배포 편의성, 고성능 TUI

### "Go + Bubble Tea"를 선택하면:
- **얻는 것**: 검증된 아키텍처(OpenCode), 뛰어난 TUI, 단일 바이너리, 멀티 모델 지원
- **잃는 것**: my-harness 로직 전면 재작성 필요, Go 학습 투자, AI SDK 빈약

### "my-harness 점진적 강화"를 선택하면:
- **얻는 것**: 즉시 활용 가능, 개발 비용 최소, 현재 워크플로우 유지
- **잃는 것**: 독립성, 다른 LLM 사용 가능성, 확장성, 외부 배포/공유 가능성

## 최종 권고

### 단계적 접근 권고 (확신도: 높음)

**1단계 (즉시): my-harness 계속 활용 + Claude Agent SDK 학습**
- 현재 my-harness는 이미 프로덕션 수준의 오케스트레이션을 갖추고 있음
- Claude Agent SDK Python 문서를 학습하고 프로토타입 실험
- my-harness의 핵심 오케스트레이션 패턴(위임, 병렬 실행, 회의)을 SDK 구조로 매핑

**2단계 (2-4주): Claude Agent SDK 기반 코어 구현**
- SDK의 `query()`, 커스텀 도구(`@tool`), 훅(`PreToolUse/PostToolUse`) 활용
- my-harness의 에이전트 위임 로직을 SDK 훅으로 구현
- Python Textual 또는 Rich 라이브러리로 기본 TUI 구성
- SQLite 기반 세션/메모리 관리 (OpenCode 참고)

**3단계 (선택): 독립 실행 도구로 발전**
- 멀티 LLM 지원 추가 (LiteLLM 래퍼)
- MCP 서버 통합으로 외부 도구 확장
- PyInstaller 또는 Nuitka로 패키징

### 조건부 권고

- **Go에 익숙하고 OpenCode 같은 완성도를 원한다면**: Go + Bubble Tea가 최선. 단, my-harness 로직 재작성에 상당한 시간 투자 필요
- **최소 투자로 최대 효과를 원한다면**: my-harness를 그대로 사용하면서 Claude Agent SDK로 일부 기능만 확장
- **OpenCode를 직접 포크하고 싶다면**: OpenCode는 오픈소스이므로 포크 후 my-harness의 오케스트레이션 로직을 Go로 포팅하는 것도 유효한 전략

### 핵심 아키텍처 설계 원칙 (어떤 스택을 선택하든)

1. **에이전트 루프**: 컨텍스트 수집 -> 행동 -> 검증의 반복 루프
2. **도구 시스템**: MCP 프로토콜 기반으로 확장 가능한 도구 인터페이스
3. **오케스트레이션**: 서브에이전트 위임, 병렬 실행, 의존성 관리
4. **컨텍스트 관리**: 리포지토리 맵(Aider 참고), 자동 컴팩션, 시맨틱 검색
5. **영속성**: SQLite 기반 세션/메모리, 파일 기반 아티팩트
6. **훅 시스템**: Pre/Post 훅으로 보안 검증, 로깅, 커스텀 로직 주입

## 출처

- [OpenCode GitHub](https://github.com/opencode-ai/opencode)
- [OpenCode vs Claude Code 비교](https://www.builder.io/blog/opencode-vs-claude-code)
- [Building your own CLI Coding Agent with Pydantic-AI (Martin Fowler)](https://martinfowler.com/articles/build-own-coding-agent.html)
- [Deep Agent Architecture for AI Coding Assistants](https://dev.to/apssouza22/a-deep-dive-into-deep-agent-architecture-for-ai-coding-assistants-3c8b)
- [Claude Agent SDK 공식 문서](https://platform.claude.com/docs/en/agent-sdk/overview)
- [Building Agents with the Claude Agent SDK](https://claude.com/blog/building-agents-with-the-claude-agent-sdk)
- [Building a Coding CLI with React Ink](https://ivanleo.com/blog/migrating-to-react-ink)
- [Bubble Tea TUI Framework](https://github.com/charmbracelet/bubbletea)
- [Ratatui TUI Framework](https://github.com/ratatui/ratatui)
- [Aider GitHub](https://github.com/Aider-AI/aider)
- [Top 5 CLI Coding Agents in 2026](https://dev.to/lightningdev123/top-5-cli-coding-agents-in-2026-3pia)
- [Claude Code Alternatives](https://openalternative.co/alternatives/claude-code)
- [Building Effective AI Agents (Anthropic)](https://www.anthropic.com/research/building-effective-agents)
- [OpenAI Codex CLI](https://github.com/openai/codex)
- [Aider vs OpenCode 비교](https://openalternative.co/compare/aider/vs/opencode)
