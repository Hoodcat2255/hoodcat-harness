# hoodcat-harness → oh-my-claudecode 전환 매핑 plan

> 작성일: 2026-05-22
> 자신감 라벨: 추정 (실제 OMC 카탈로그·스킬 동작 검증 필요. 본 문서는 매핑 가설서이며 실제 호환층 작성 시 보정 필요.)
> 정본 위치: 본 문서. 전환 진행 중 변동되는 사항은 별도 changelog로 관리한다.

---

## 개요

hoodcat-harness는 Claude Code 위에 얹은 커스텀 2-tier 멀티에이전트 시스템이다. Main Agent(순수 디스패처) → Orchestrator → 워커 스킬·에이전트로 이어지는 구조로, 위임 강제·공유 컨텍스트·에이전트 메모리·텔레그램 알림을 직접 구현해왔다.

oh-my-claudecode(OMC)는 Claude Code 공식 플러그인 기반의 멀티에이전트 오케스트레이션 레이어로, executor·planner·architect 등 표준 에이전트 카탈로그와 notepad·shared-memory·trace 등 내장 MCP 도구를 제공한다. 전환의 핵심 가치는 hoodcat 고유 인프라 유지 비용을 낮추고, OMC가 제공하는 표준 워크플로(autopilot·ultrawork·ralph·team 등)와 지속적 업데이트를 활용하는 것이다.

---

## 1. 에이전트 매핑 (8개)

| hoodcat-harness 에이전트 | OMC 대응 | 매핑 신뢰도 | 비고 |
|---|---|---|---|
| orchestrator | planner + 메인 디스패치 | 중간 | OMC는 Claude main agent가 디스패처 역할을 직접 수행. orchestrator의 동적 계획·레시피 조합은 planner로, 위임 강제는 글로벌 룰로 이전. enforce-delegation.sh 회귀 테스트 필요. |
| coder | executor (model=opus override 가능) | 높음 | OMC executor가 동일 역할(코드 작성·수정·빌드·테스트·패치). context-mode MCP 의존성 별도 검토 필요. |
| researcher | document-specialist + scientist | 중간 | deepresearch→document-specialist, blueprint/decide의 웹 조사→scientist, Context7 MCP 활용 방식 차이 확인 필요. |
| committer | git-master | 높음 | OMC commit protocol(HEREDOC 커밋, pre-commit 훅 처리) 활용. 거의 1:1 매핑. |
| navigator | explore agent (Claude 내장) | 높음 | Glob·Grep·Read 전용 read-only 탐색 에이전트. OMC explore가 동일 패턴. |
| reviewer | code-reviewer | 높음 | 코드 품질·패턴 준수 검토 역할 동일. 거의 1:1 매핑. |
| architect | architect (OMC) | 높음 | 이름·역할(구조적 건전성·확장성 검토) 동일. |
| security | security-reviewer | 높음 | OWASP·의존성 감사(npm audit·pip audit·cargo audit·govulncheck) 역할 동일. |

---

## 2. 스킬 매핑 (12개)

| hoodcat-harness 스킬 | OMC 스킬·워크플로 | 매핑 신뢰도 | 비고 |
|---|---|---|---|
| code | executor 직접 호출 | 높음 | 코드 변경 위임. Agent(subagent_type="oh-my-claudecode:executor") 형태로 전환. context-mode MCP 의존성 확인 필요. |
| test | executor + 검증 (ultraqa 보조) | 중간 | test-engineer OMC 에이전트가 있으나 카탈로그 확인 필요. executor로 fallback 가능. |
| blueprint | planner | 높음 | 요구사항·아키텍처 설계·태스크 분해 역할 동일. /oh-my-claudecode:plan 또는 ralplan으로 대체. |
| commit | git-master / commit protocol | 높음 | OMC 커밋 프로토콜(HEREDOC, Co-Authored-By 태그) 활용. |
| decide | analyst | 중간 | OMC analyst의 근거 기반 평가 기능 활용. deep-dive·deep-interview와 결합 가능. |
| deepresearch | document-specialist | 높음 | external-context 워크플로·wiki 도구와 결합 가능. WebSearch·WebFetch 동일 도구 사용. |
| deploy | 매핑 없음 | 낮음 | OMC에 deploy 전용 워크플로 없음. 커스텀 스킬 유지 또는 executor에 직접 위임. |
| qa-swarm | ultraqa | 중간 | 병렬 멀티카테고리 QA 동등 기능 추정. ultraqa의 실제 병렬 에이전트 스폰 방식 검증 필요. |
| scaffold | 매핑 없음 | 낮음 | hoodcat-harness 고유(스킬·에이전트 파일 생성). OMC deepinit과 일부 중복이나 직접 대응 없음. 커스텀 유지 필요. |
| security-scan | security-reviewer | 중간 | OMC security-reviewer가 npm audit·pip audit·govulncheck 등 동등 기능 제공하는지 확인 필요. |
| sync-docs | 매핑 없음 | 낮음 | hoodcat-harness 고유(CLAUDE.md·harness.sh와 .claude/ 하위 디렉토리 동기화). 커스텀 유지 필요. |
| team-review | team 워크플로 | 중간 | OMC /team으로 reviewer·security·architect 병렬 스폰 가능. ultrareview는 별도 과금으로 자동 호출 불가. |

---

## 3. 훅 매핑 (10개)

settings.json 기준 실제 이벤트 매핑:

| hoodcat-harness 훅 | 이벤트 | OMC 대응 | 비고 |
|---|---|---|---|
| enforce-delegation.sh | PreToolUse | OMC 글로벌 룰 + 훅 유지 | OMC는 위임 강제를 룰 차원에서 처리. 3-신호 OR 판별(agent_transcript_path / subagents/ / agent_id+agent_type)이 OMC executor를 서브에이전트로 인식하는지 회귀 테스트 필수. |
| shared-context-inject.sh | SubagentStart | OMC shared-memory / notepad | mcp__plugin_oh-my-claudecode_t__shared_memory_read + notepad_read로 대체 가능. additionalContext 주입 방식은 OMC SubagentStart 훅으로 유지 가능. |
| subagent-monitor.sh | SubagentStop | OMC trace_summary / trace_timeline | trace_summary·trace_timeline MCP 도구로 대체 가능. 로깅 상세도 비교 필요. |
| shared-context-collect.sh | SubagentStop | OMC shared-memory / notepad | shared_memory_write·notepad_write_working으로 대체 가능. flock 기반 동시성 처리 OMC 내부 메커니즘 확인 필요. |
| notify-telegram.sh | SubagentStop | telegram plugin | 글로벌 telegram plugin(mcp__plugin_telegram_telegram__reply)으로 전환. 현재 orchestrator 공유 컨텍스트 파싱 로직은 별도 정리 필요. |
| shared-context-finalize.sh | SessionEnd | OMC state_write / notepad | state_write·notepad_write_manual로 세션 종료 메트릭 기록 가능. |
| shared-context-cleanup.sh | SessionStart | OMC state_clear / shared_memory_cleanup | state_clear·shared_memory_cleanup으로 TTL 만료 세션 정리 대체 가능. |
| task-quality-gate.sh | TaskCompleted | verifier 에이전트 | OMC verifier가 빌드/테스트 자동 검증 동등 기능 제공. TaskCompleted 훅으로 verifier 호출 구조 유지 또는 OMC ultraqa로 통합 가능. |
| teammate-idle-check.sh | TeammateIdle | OMC 자체 메커니즘 | OMC team 워크플로 내 유휴 팀원 재개 메커니즘 확인 필요. 동등 기능 미확인 시 훅 유지. |
| verify-build-test.sh | (직접 Bash 호출) | verifier | 스킬 내부에서 Bash로 호출되는 헬퍼 스크립트. OMC verifier 또는 executor 내 직접 실행으로 대체. |
| test-notify-telegram.sh | (수동 테스트용) | 해당 없음 | 개발·디버그용. 전환 후 제거 대상. |
| test-shared-context.sh | (수동 테스트용) | 해당 없음 | 개발·디버그용. 전환 후 제거 대상. |

---

## 4. 규칙 파일 매핑 (.claude/rules/)

| hoodcat-harness 룰 | 글로벌 ~/.claude/rules/ 존재 여부 | 처리 방안 |
|---|---|---|
| source-hierarchy.md | 글로벌 존재 (동일 내용) | 글로벌 정본 유지. 프로젝트 로컬은 글로벌과 동기화 확인 후 제거 가능. |
| epistemic-honesty.md | 글로벌 존재 (동일 내용) | 동상. |
| antipatterns-general.md | 글로벌 존재 (동일 내용) | 동상. |
| antipatterns-python.md | 글로벌 존재 (동일 내용) | 동상. |
| antipatterns-typescript.md | 글로벌 존재 (동일 내용) | 동상. |
| response-format.md | 글로벌 없음 (프로젝트 신규) | hoodcat-harness 고유 (대화 출력 마크다운 금지 등). OMC executor 룰로 흡수 검토 또는 글로벌 이전 고려. |
| shared-context-protocol.md | 글로벌 없음 (프로젝트 신규) | OMC notepad/shared-memory로 대체 후 제거 가능. 전환 전까지 유지. |
| agent-memory.md | 글로벌 없음 (프로젝트 신규) | OMC notepad_write_*/notepad_read 사용 시 대체 가능. .claude/agent-memory/ 디렉토리와 함께 검토. |

---

## 5. 디렉토리·메모리·shared-context 매핑

| hoodcat-harness 경로 | OMC 대응 경로·메커니즘 | 결정 필요 사항 |
|---|---|---|
| `.claude/agent-memory/` | OMC notepad (`.omc/notepad.md`, `.omc/notepads/`) | notepad_write_manual·notepad_read로 세션 간 지식 축적 대체 가능. 기존 MEMORY.md·lessons-learned.md 내용 마이그레이션 필요. |
| `.claude/shared-context/` | OMC shared-memory + `.omc/state/` | shared_memory_write·read로 런타임 에이전트 간 컨텍스트 전달 대체. TTL·gc 정책 호환성 확인 필요. |
| `.claude/shared-context-config.json` | OMC shared_memory_cleanup 설정 | TTL 설정이 OMC 메커니즘과 호환되는지 확인 필요. |
| `.claude/log/` | `.omc/logs/` | OMC 표준 로그 경로로 이전. subagent-monitor.sh 로그 대상 경로 변경 필요. |

---

## 6. harness.sh / install.sh / uninstall.sh 매핑

| hoodcat-harness 기능 | OMC 대응 | 비고 |
|---|---|---|
| harness.sh install/update | OMC plugin install + 프로젝트별 커스텀 스크립트 | OMC 설치는 /oh-my-claudecode:omc-setup. hoodcat 고유 파일(deploy, scaffold, sync-docs 스킬 등) 배포는 별도 스크립트 유지. |
| harness.sh config (텔레그램 설정) | telegram plugin configure (/oh-my-claudecode:configure-notifications) | 글로벌 telegram plugin 설정으로 전환. |
| harness mode on/off | OMC kill switch (DISABLE_OMC, OMC_SKIP_HOOKS 환경변수) | 환경변수 기반 토글로 대체. OMC_SKIP_HOOKS에 특정 훅 이름 지정 가능. |
| harness.sh uninstall | 역방향 제거 스크립트 | OMC 제거는 plugin 제거. hoodcat 고유 파일 제거는 별도 처리. |

---

## 7. 전환 단계 (Phase 0~5)

### Phase 0: 백업·worktree 준비
- 상태: 완료 (2026-05-21)
- hoodcat-harness.archive.20260521 백업 생성
- feat/agent-cleanup worktree 생성

### Phase 1: 사전 정리
- 상태: 완료 임박 (2026-05-22)
- 모델 다운그레이드 (navigator·reviewer → sonnet)
- 공통 룰 정본화 (response-format / shared-context-protocol / agent-memory)
- 8 에이전트 본문 슬림화 (cross-link 치환)
- orchestrator.md 분할 (catalog·recipes·pushback-trigger)
- agent-memory 디렉토리 생성
- Small-Change Exceptions 추가
- OMC 매핑 plan 문서 작성 (본 문서)

### Phase 2: 스킬 매핑 + 호출 호환층
- hoodcat 스킬 12개 → OMC skill·agent 호출 매핑 구현
- 슬래시 커맨드(/code, /test 등) 호환층 작성
- enforce-delegation.sh가 OMC executor 위임도 정당한 서브에이전트로 인식하도록 패치

### Phase 3: 에이전트 프롬프트 OMC 카탈로그 호환 변환
- 8 에이전트 .md에서 hoodcat 고유 Skill 카탈로그 참조를 OMC agent 호출 표기로 변경
- Recipes의 Skill·Task 표기를 Agent(subagent_type="oh-my-claudecode:...") 형태로 변환

### Phase 4: 훅 마이그레이션
- shared-context-*.sh → OMC notepad/shared-memory 이전
- notify-telegram.sh → telegram plugin으로 이전
- task-quality-gate.sh → verifier 호출로 대체
- 테스트용 훅(test-notify-telegram.sh, test-shared-context.sh) 제거

### Phase 5: 검증·전환 완료
- 통합 테스트 (각 워크플로 실제 호출)
- TODO.md 정리
- 프로젝트 로컬 rules/ 중 글로벌 중복 항목 제거
- archive 제거 (전환 안정화 후)

---

## 8. 미해결 이슈 및 검증 항목

- enforce-delegation.sh의 3-신호 OR 판별이 OMC executor를 정당한 서브에이전트로 인식하는지 회귀 테스트 필요. OMC executor의 .agent_transcript_path·.agent_id·.agent_type 신호 값 확인 필요.
- OMC executor의 model override가 hoodcat coder의 광범위 Bash 권한(npm·pytest·cargo·go·make·docker·pip audit·govulncheck·gh)을 그대로 지원하는지 검증 필요.
- OMC ultraqa vs hoodcat qa-swarm 기능 동등성 검증 필요. 특히 병렬 에이전트 스폰 방식과 결과 통합 메커니즘.
- context-mode MCP가 OMC 환경에서 동작하는지 확인 필요. coder·researcher 에이전트가 mcpServers: [context-mode]를 선언하고 있음.
- OMC notepad/shared-memory의 TTL·gc 정책이 hoodcat shared-context-config.json(TTL, 최대 항목 수 설정)과 호환되는지 검토 필요.
- OMC team 워크플로에서 TeammateIdle 이벤트 처리 메커니즘 확인. teammate-idle-check.sh 대체 가능 여부.
- shared-context-collect.sh의 flock 기반 동시 안전 쓰기가 OMC shared_memory_write로 동등하게 보장되는지 확인 필요.

---

## 9. 자신감 라벨 및 다음 단계

본 매핑은 추정. 실제 진행 전 다음 검증 필요:

- (Tier 1) OMC 에이전트 정의 파일·SKILL.md 원문 직접 확인 (omc-reference 스킬 또는 글로벌 ~/.claude/ 경로)
- (Tier 1) hoodcat 각 스킬·훅 source와 OMC 대응 도구 직접 비교
- 매핑 신뢰도 "낮음"인 항목(deploy, scaffold, sync-docs)은 호환층 작성 또는 커스텀 유지 결정 필요
- enforce-delegation.sh OMC 호환 회귀 테스트를 Phase 2 착수 전 선행 실행 권장

다음 단계: 본 문서 검토 후 Phase 2 착수 여부 결정.
