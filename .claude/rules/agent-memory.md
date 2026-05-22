# Agent Memory (에이전트 영속 메모리)

> 적용 범위: 모든 에이전트의 영속 메모리 관리.
> 정본 위치: 본 파일. 에이전트 파일에서는 cross-link + 에이전트 특수 항목(주제별 파일 예시 등)만 유지한다.
> 관련 정본 파일: 공유 컨텍스트(세션 간 파일 전달)는 `.claude/rules/shared-context-protocol.md` 참조.

## 개요

각 에이전트는 작업 이력과 축적된 지식을 영속 메모리 파일에 보관한다. 세션이 끊겨도 이전 맥락을 복원할 수 있고, 반복 실수를 줄이며, 프로젝트별 컨벤션을 빠르게 파악할 수 있다.

## 1. 파일 위치

```
.claude/agent-memory/<agent-name>/MEMORY.md   ← 주 메모리 파일 (200줄 이내 유지)
.claude/agent-memory/<agent-name>/<topic>.md  ← 주제별 분리 파일
```

예시:
```
.claude/agent-memory/main/MEMORY.md
.claude/agent-memory/main/lessons-learned.md
.claude/agent-memory/main/trigger-log.md
.claude/agent-memory/main/subagent-hallucination.md
.claude/agent-memory/coder/MEMORY.md
.claude/agent-memory/coder/build-patterns.md
.claude/agent-memory/reviewer/MEMORY.md
.claude/agent-memory/security/MEMORY.md
```

## 2. 공통 절차

### 작업 시작 전

1. `MEMORY.md`를 읽고 이전 작업 이력과 맥락을 파악한다.
2. 관련 주제별 파일이 있으면 함께 읽는다.
3. `## In Progress` 절에 중단된 작업이 있으면 해당 맥락부터 복원한다.

### 작업 완료 후

1. `MEMORY.md`를 갱신한다 (200줄 이내 유지).
2. 축적 가치가 높은 항목은 주제별 파일에 분리 기록한다.
3. 오래된 `## Done` 항목은 정리(삭제 또는 요약 압축)한다.

## 3. MEMORY.md 표준 섹션

모든 에이전트의 `MEMORY.md`는 다음 3개 섹션을 기본으로 유지한다.

```markdown
## TODO
- [후속 작업, 미해결 이슈, 재시도 필요 항목]

## In Progress
- [현재 진행 중인 작업. 중단된 경우 재개 지점 명시]

## Done
- [완료된 작업 요약. 오래된 항목은 정리]
```

섹션 내용이 없으면 해당 섹션을 생략하지 않고 빈 상태로 유지한다 (파일 구조 일관성).

## 4. 주제별 파일 분리 기준

다음 유형의 항목은 `MEMORY.md`에 계속 쌓지 않고 주제별 파일로 분리한다.

- 반복 패턴: 빌드·테스트 명령, 자주 쓰는 경로, 검색 전략
- 실패 원인: pre-commit 실패 패턴, 에러 메시지와 해결책, 취약점 재발 패턴
- 코드 컨벤션: 프로젝트별 네이밍·스타일·임포트 규칙
- 도메인 지식: 아키텍처 패턴, 기술 스택 근거, 의존성 관계
- 통계·로그: 트리거 발동 기록, 사용자 직관 정정 사례

주제별 파일명은 내용을 직접 반영하는 명사형으로 짓는다 (예: `build-patterns.md`, `lessons-learned.md`).

## 5. 에이전트별 주제별 파일 예시

에이전트 파일에서 구체적 예시를 유지한다. 공통 참고용 예시:

- main (Main Agent): `lessons-learned.md` (도메인별 사전 확률 가중치), `trigger-log.md` (pushback 트리거 통계), `subagent-hallucination.md` (데이터 날조 패턴)
- coder: `build-patterns.md` (빌드·테스트 명령, 에러 패턴), `code-conventions.md` (프로젝트 컨벤션)
- reviewer: `code-smells.md` (반복 지적 패턴), `test-coverage.md` (커버리지 기준)
- security: `vuln-patterns.md` (인증·인가 구조, 반복 취약점), `blocked-issues.md` (BLOCK 이슈 이력)
- navigator: `dir-structure.md` (디렉토리 구조, 핵심 파일 위치)
- researcher: `source-ids.md` (Context7 라이브러리 ID 매핑, 유용한 소스)
- committer: `commit-conventions.md` (커밋 컨벤션, pre-commit 실패 패턴)
- architect: `arch-patterns.md` (아키텍처 패턴, 확장성 교훈)

## 적용 규칙

1. **시작 전 읽기**: `MEMORY.md`와 관련 주제별 파일을 반드시 읽고 시작한다. 읽기를 생략하면 반복 실수가 발생한다.
2. **완료 후 갱신**: 작업 완료 후 반드시 `MEMORY.md`를 갱신한다. 세션 종료 직전도 포함한다.
3. **200줄 상한**: `MEMORY.md`는 200줄을 넘지 않도록 오래된 항목을 정리한다. 상세 내용은 주제별 파일로 분리한다.
4. **3개 섹션 유지**: `## TODO`, `## In Progress`, `## Done` 섹션 구조를 모든 에이전트가 동일하게 유지한다.
5. **주제별 파일 분리**: 반복 등장하거나 누적 가치가 있는 항목은 주제별 파일로 분리하여 `MEMORY.md` 비대화를 방지한다.
