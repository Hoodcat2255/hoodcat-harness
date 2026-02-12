# Shared Context System - Requirements

## Overview

Claude Code 에이전트 간 공유 컨텍스트 시스템. 서브에이전트가 시작될 때 공유 컨텍스트를 읽고, 종료 시 작업 결과를 공유 컨텍스트에 기록하는 훅 기반 시스템.

## 배경 및 동기

### 현재 문제

hoodcat-harness는 `context: fork`로 모든 스킬을 서브에이전트에서 격리 실행한다. 이 격리 모델은 안정성을 높이지만, 에이전트 간 정보 공유에 구조적 한계가 있다:

1. **컨텍스트 격리**: 서브에이전트는 독립 컨텍스트 윈도우에서 실행되므로 메인 에이전트의 대화 이력을 물려받지 않는다.
2. **작업 결과 유실**: 서브에이전트(navigator, reviewer 등)의 발견 사항이 후속 서브에이전트에 전달되지 않는다.
3. **중복 탐색**: navigator가 코드베이스를 탐색한 결과를 coder가 다시 탐색해야 한다.
4. **워크플로우 비효율**: implement 스킬에서 Phase 1(navigator) 결과를 Phase 3(코드 작성)에서 활용하려면 workflow 에이전트가 중계해야 한다.

### 공식 지원 현황

- **SubagentStart hook**: `additionalContext` 필드로 서브에이전트에 컨텍스트 주입 가능 (공식 지원)
- **SubagentStop hook**: `decision: "block"` 또는 로깅만 가능. 부모 에이전트 컨텍스트에 직접 주입하는 공식 메커니즘은 없음.
- **Feature Request #5812**: 서브에이전트와 부모 에이전트 간 컨텍스트 브리징 요청. "NOT_PLANNED"으로 종료됨.
- **Agent Teams**: TaskList, SendMessage로 팀원 간 통신 가능하나, SubAgent(Task tool) 모델에는 적용 불가.

### 실현 가능한 접근

공식 API 범위 내에서 파일 기반 공유 컨텍스트를 구축한다:
- **SubagentStart hook** → 공유 컨텍스트 파일을 읽어 `additionalContext`로 주입 (공식 지원)
- **SubagentStop hook** → 서브에이전트의 transcript를 파싱하여 공유 컨텍스트 파일에 기록 (파일 기반 우회)
- **CLAUDE.md/rules** → 서브에이전트에게 공유 컨텍스트 파일에 직접 쓰도록 지시 (에이전트 지침 기반)

---

## 기능 요구사항

### FR-1: 공유 컨텍스트 저장소

- **FR-1.1**: 프로젝트별 공유 컨텍스트 파일을 `.claude/shared-context/` 디렉토리에 저장한다.
- **FR-1.2**: 세션 단위로 격리한다. 세션 ID별 디렉토리: `.claude/shared-context/{session-id}/`
- **FR-1.3**: 각 에이전트의 기여를 개별 파일로 저장한다: `{agent-type}-{agent-id}.md`
- **FR-1.4**: 세션 요약 파일 `_summary.md`에 전체 공유 컨텍스트를 집계한다.

### FR-2: 컨텍스트 주입 (SubagentStart Hook)

- **FR-2.1**: 서브에이전트 시작 시 해당 세션의 공유 컨텍스트 요약을 `additionalContext`로 주입한다.
- **FR-2.2**: 주입할 컨텍스트가 없으면 아무 것도 주입하지 않는다 (빈 상태).
- **FR-2.3**: 에이전트 타입별 필터링을 지원한다 (예: reviewer에게는 코드 변경 컨텍스트만 주입).
- **FR-2.4**: 컨텍스트 크기를 제한한다 (기본 4000자, 설정 가능).

### FR-3: 컨텍스트 기록 (SubagentStop Hook)

- **FR-3.1**: 서브에이전트 종료 시 transcript에서 주요 발견 사항을 추출하여 공유 컨텍스트에 기록한다.
- **FR-3.2**: 추출할 정보: 변경된 파일, 발견된 이슈, 리뷰 결과, 탐색된 코드 영역.
- **FR-3.3**: transcript 파싱 실패 시 안전하게 무시한다 (에이전트 종료를 차단하지 않음).
- **FR-3.4**: `_summary.md`를 업데이트하여 새 정보를 반영한다.

### FR-4: 에이전트 자발적 기록 (보완 메커니즘)

- **FR-4.1**: 에이전트에게 공유 컨텍스트 파일에 직접 쓸 수 있는 지침을 제공한다.
- **FR-4.2**: CLAUDE.md 또는 에이전트 정의에 공유 컨텍스트 기록 지침을 포함한다.
- **FR-4.3**: transcript 파싱보다 에이전트 자발적 기록을 우선시한다 (더 정확).

### FR-5: 세션 수명주기

- **FR-5.1**: SessionStart hook에서 이전 세션의 공유 컨텍스트를 정리한다 (TTL 기반).
- **FR-5.2**: SessionEnd hook에서 현재 세션의 최종 요약을 생성한다.
- **FR-5.3**: 기본 TTL: 24시간. 설정 파일로 변경 가능.

---

## 비기능 요구사항

### NFR-1: 성능

- 훅 실행 시간: SubagentStart < 500ms, SubagentStop < 2000ms
- 파일 I/O 최소화: 요약 파일 1개만 읽기/쓰기
- transcript 파싱은 최근 N줄만 대상 (기본 500줄)

### NFR-2: 안정성

- 훅 실패가 에이전트 실행을 차단하지 않는다 (exit 0 보장)
- 파일 잠금: flock으로 동시 쓰기 방지
- 잘못된 JSON, 빈 transcript 등 예외 상황을 안전하게 처리

### NFR-3: 보안

- 공유 컨텍스트에 비밀 정보(API 키, 토큰 등)가 포함되지 않도록 필터링
- `.gitignore`에 `.claude/shared-context/` 추가

### NFR-4: 유지보수성

- 순수 bash 스크립트 (jq 의존)
- 기존 hooks 구조와 일관된 패턴 사용
- 설정은 환경 변수 또는 JSON 설정 파일로 관리

### NFR-5: 확장성

- 에이전트 타입별 컨텍스트 필터 추가 용이
- 커스텀 추출 규칙 플러그인 구조
- Agent Teams 통합 대비 (향후)

---

## 가정 및 제약

### 가정

1. `jq`가 시스템에 설치되어 있다.
2. 서브에이전트의 transcript 파일 경로가 SubagentStop hook의 `agent_transcript_path`로 제공된다.
3. Claude Code의 훅 시스템이 현재 문서대로 동작한다 (SubagentStart의 additionalContext 주입 포함).
4. 서브에이전트는 프로젝트 디렉토리에 대한 파일 쓰기 권한이 있다.

### 제약

1. **부모 컨텍스트 직접 주입 불가**: SubagentStop에서 부모 에이전트 컨텍스트에 직접 주입하는 공식 방법이 없다. 파일 기반 우회로 대체.
2. **transcript 파싱의 한계**: transcript JSONL 형식이 내부 구현이므로 변경될 수 있다. 에이전트 자발적 기록을 1차 메커니즘으로 삼는다.
3. **컨텍스트 크기 제한**: 서브에이전트의 additionalContext에 너무 많은 정보를 주입하면 토큰 낭비. 요약 + 크기 제한 필요.
4. **동시성**: 워크플로우 에이전트가 병렬로 서브에이전트를 실행할 수 있으므로 파일 잠금이 필수.

---

## 출처

- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Agent Teams Documentation](https://code.claude.com/docs/en/agent-teams)
- [Feature Request #5812: Context Bridging Between Sub-Agents and Parent Agents](https://github.com/anthropics/claude-code/issues/5812)
- [Claude Code Hooks Multi-Agent Observability](https://github.com/disler/claude-code-hooks-multi-agent-observability)
- [Claude Code Hooks Mastery](https://github.com/disler/claude-code-hooks-mastery)
