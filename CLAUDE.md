@.claude/harness.md

# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

이 저장소는 Claude Code의 커스텀 멀티에이전트 시스템(hoodcat-harness)을 관리하는 프로젝트입니다.
스킬, 에이전트, 훅, 안티패턴 규칙, 공유 컨텍스트 시스템을 포함하며, `harness.sh`를 통해 다른 프로젝트에 설치/업데이트할 수 있습니다.

## 디렉토리 구조

- `.claude/skills/` - 커스텀 Claude Code 스킬 정의 (SKILL.md 파일, 12개)
- `.claude/agents/` - 커스텀 에이전트 정의 (7개)
- `.claude/hooks/` - Claude Code 훅 스크립트 (품질 게이트, 공유 컨텍스트, 텔레그램 알림 등)
- `.claude/rules/` - 공통 규칙 파일 5개: 안티패턴 3종(Python, TypeScript, General) + `source-hierarchy.md`(자료 등급 Tier 1~4 정본) + `epistemic-honesty.md`(단정 회피·자신감 라벨·비유 제약 정본)
- `.claude/dispatch/` - 디스패치 카탈로그·레시피·반박 트리거 정본 (Main Agent가 직접 참조): `catalog.md`(Skill·Agent 카탈로그), `recipes.md`(워크플로 레시피), `pushback-trigger.md`(사용자 반박 자동 대응)
- `.claude/agent-memory/` - 에이전트별 영속 메모리 저장소 (세션 간 지식 축적, 예: `main/lessons-learned.md`에 사용자 직관 옳았던 사례·도메인 사전 확률 가중치 누적)
- `.claude/shared-context/` - 에이전트 간 공유 컨텍스트 저장소 (런타임 생성, .gitignore)
- `.claude/shared-context-config.json` - 공유 컨텍스트 설정 (TTL, 최대 항목 수 등)
- `docs/` - 기능 문서 및 리서치 결과 저장
- `harness.sh` - CLI 설치/업데이트 도구 (다른 프로젝트에 harness 설치)
- `TODO.md` - 미해결 작업 추적

## 아키텍처 (1-tier, Main-Agent-Driven)

Main Agent는 디스패처 + 워크플로 조합 역할을 모두 수행합니다. `dispatch/catalog.md`를 참조하여 워커·스킬을 직접 호출하고 조합합니다. 자세한 흐름은 `docs/prompt-flow-after-cleanup-20260522.md` 참조.

### 위임 권고

Main Agent는 가능하면 워커 스킬·에이전트에 작업을 위임한다. 단, 위임은 권고이며 강제하지 않는다. 단순 안내·질문·1줄 .md 수정처럼 위임 오버헤드가 더 큰 경우 Main Agent의 직접 처리도 허용된다.

## 사용자 반박 대응 메커니즘

사용자 직관과 에이전트 결론이 충돌할 때의 동작 규칙입니다. 학습 데이터의 일반론(Tier 4)이 사용자의 1차 자료 기반 직관과 충돌하는 경우, 에이전트는 단정형 답변 대신 자가 점검 후 1차 자료를 재확인합니다.

- 자료 등급(Source Hierarchy) Tier 1~4의 정본은 `.claude/rules/source-hierarchy.md`에 있습니다. 법률·청약·세무·의료·금융 등 1차 자료 도달 강제 도메인 목록도 같은 파일에서 관리합니다.
- 단정 회피·자신감 라벨(`확실`/`추정`/`모름`)·비유 사용 제약의 정본은 `.claude/rules/epistemic-honesty.md`에 있습니다. 모든 사실 진술에 Tier 라벨과 자신감 라벨을 동반합니다.
- 사용자 반박 키워드(예: "정말?", "확실해?", "근거는?", "내 생각엔 X인데") 감지 시 자동 Self-Check 5문항을 수행하고 한 문항이라도 No이면 deepresearch를 호출해 1차 자료를 재확인하는 메커니즘의 정본은 `.claude/dispatch/pushback-trigger.md`에 있습니다. Main Agent가 직접 평가합니다. researcher 에이전트(`.claude/agents/researcher.md`)에도 동일한 Self-Check 절이 있습니다.
- 도메인별 사전 확률 가중치(사용자 직관이 옳았던 사례·반복 패턴)는 `.claude/agent-memory/main/lessons-learned.md`에 누적되며, 반박 대응 시 참고됩니다.

## 주요 스킬 (12개)

### code
코드 작성/수정/진단/패치 통합 스킬입니다.
- 호출: `/code <작업 지시>`
- Main Agent가 모든 코드 변경 작업에 사용
- context-mode MCP로 대용량 빌드/테스트 출력의 컨텍스트 윈도우 절약

### test
테스트 작성 및 실행 스킬입니다.
- 호출: `/test <테스트 대상>`

### blueprint
프로젝트 설계 및 기획 스킬입니다.
- 호출: `/blueprint <기획 대상>`

### commit
변경 사항을 분석하여 구조화된 Git 커밋을 생성합니다.
- 호출: `/commit [커밋 메시지 힌트]`
- 에이전트: committer (최소 권한, sonnet)

### deploy
배포 설정 파일을 생성합니다 (Dockerfile, CI/CD, 환경 문서).
- 호출: `/deploy <배포 환경>`

### security-scan
코드와 의존성의 보안 취약점을 스캔합니다.
- 호출: `/security-scan [대상 디렉토리]`

### deepresearch
웹 검색과 Context7을 활용한 심층 자료조사 스킬입니다.
- 호출: `/deepresearch [주제]`
- 결과는 `docs/research-[주제]-YYYYMMDD.md` 형식으로 저장됨
- context-mode MCP로 대용량 웹 페이지의 fetch_and_index 지원

### decide
근거 기반 비교 분석 및 의사결정 지원 스킬입니다.
- 호출: `/decide [결정할 주제]`

### scaffold
기존 패턴을 런타임에 참조하여 새 스킬/에이전트 파일을 자동 생성합니다.
- 호출: `/scaffold <type> <name> [options] -- <description>`
- 지원 유형: worker, workflow, agent, pair (에이전트+스킬 쌍)

### team-review (에이전트팀 기반)
멀티렌즈 코드 리뷰 스킬입니다.
- 호출: `/team-review [대상 파일 또는 변경 설명]`
- 대규모/고위험 변경에만 사용
- 비용: 단일 리뷰 대비 약 3배 토큰

### qa-swarm (에이전트팀 기반)
병렬 QA 스웜 스킬입니다.
- 호출: `/qa-swarm [프로젝트 경로]`
- 비용: 단일 테스트 대비 최대 4배 토큰

### sync-docs
harness 내부 파일 변경 시 관련 문서를 자동 동기화하는 스킬입니다.
- 호출: `/sync-docs [--check-only]`
- `.claude/` 하위 스킬/에이전트/훅 변경을 감지하여 CLAUDE.md, harness.md를 업데이트
- Main Agent가 scaffold 또는 harness 파일 변경 후 자동 호출

## 훅

| 훅 | 이벤트 | 용도 |
|----|--------|------|
| `task-quality-gate.sh` | TaskCompleted | 구현 태스크 완료 시 빌드/테스트 자동 검증 |
| `teammate-idle-check.sh` | TeammateIdle | 미완료 팀원 유휴 시 작업 재개 유도 |
| `verify-build-test.sh` | - | 프로젝트별 빌드/테스트 자동 실행 |
| `notify-telegram.sh` | SubagentStop | 서브에이전트 완료 시 텔레그램 알림 |
| `shared-context-inject.sh` | SubagentStart | 이전 에이전트 작업 요약 주입 |
| `shared-context-collect.sh` | SubagentStop | 에이전트 작업 결과 수집 |
| `shared-context-cleanup.sh` | SessionStart | TTL 만료 세션 정리 |
| `shared-context-finalize.sh` | SessionEnd | 세션 메트릭 기록 |
| `subagent-monitor.sh` | SubagentStop | 서브에이전트 종료 이벤트 로깅 |

## harness.sh CLI

`harness.sh`로 다른 프로젝트에 harness 시스템을 설치/업데이트합니다:
- `./harness.sh install <프로젝트 경로>` - 새 프로젝트에 설치
- `./harness.sh update <프로젝트 경로>` - 기존 설치 업데이트
- `./harness.sh config` - 텔레그램 알림 등 대화형 설정
- install/update 시 context-mode MCP 서버 자동 등록 (Node.js 18+ 필요)
- `update`의 `rsync --delete`는 프로젝트 전용 스킬/에이전트를 삭제하므로, 보존할 경로는 대상 프로젝트의 `.claude/.harness-local` 매니페스트에 선언한다 (상세: `.claude/harness.md`의 "프로젝트 로컬 확장" 절).

## 파이프라인 시스템 (설계 완료, 미구현)

Main Agent의 워크플로 조합을 정형화된 파이프라인으로 확장하는 시스템입니다.

- JSON 스키마 설계 완료: 노드 8종 (start, end, skill, agent, fork, join, condition, loop)
- 설계 문서: `docs/research-pipeline-json-schema-20260216.md`
- 비주얼 에디터: 별도 프로젝트 (`~/Projects/pipeline-editor/`, React + React Flow)
- Main Agent는 파이프라인을 Read-only로 실행, 생성/수정은 사용자만 수행

## 문서 작성 규칙

리서치 결과는 `docs/` 디렉토리에 마크다운으로 저장:
- 파일명: `docs/research-[주제]-YYYYMMDD.md`
- 필수 섹션: 개요, 상세 내용, 주요 포인트, 출처
