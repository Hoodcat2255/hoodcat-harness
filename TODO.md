# 오케스트레이터 위임율 개선 (종결, 2026-05-22)

> 결말: 옵션 A로 위임 강제 시스템 전체를 폐지함. 본 절은 역사적 기록.

claude-dashboard 실데이터 분석 결과 오케스트레이터가 스킬/에이전트 위임 없이 직접 코드를 수정하는 비율이 98.7%였음 (18개 인스턴스, Skill 7회 vs 직접 도구 537회, 리뷰 에이전트 스폰 0회). FORBIDDEN/REQUIRED 표 + PreToolUse 차단 훅(enforce-delegation.sh)으로 강제하는 안전망을 도입했으나, 작은 변경에 대한 오버헤드와 OMC 전환 호환성 부담을 고려해 2026-05-22 옵션 A로 시스템 전체 폐지. 글로벌 ~/.claude/CLAUDE.md 의 "delegate, don't code" 권고만 남음.

옵션 A 폐지 시점에 진행된 정리:
- orchestrator.md의 `## Delegation Enforcement (ABSOLUTE RULES)` 절 전체 제거 (FORBIDDEN/REQUIRED/Review Agent Activation/Small-Change Exceptions/Self-Check)
- harness.md의 FORBIDDEN 행위·위임 강제 절·차단 메시지 예시 제거
- CLAUDE.md의 "위임 강제 시스템 (3층 방어)" 절을 "위임 권고" 단순 안내로 교체
- `.claude/hooks/enforce-delegation.sh` 삭제
- `.claude/settings.json` 의 PreToolUse Edit|Write 훅 등록 제거
- `.claude/settings-omc.json.example` 갱신 (hooks 빈 객체)

# hoodcat-harness → oh-my-claudecode 전환

전환 매핑 plan: `docs/migration-omc-mapping-20260522.md`.

## Phase 진행 상황 (2026-05-22)

- [x] Phase 0: 백업·worktree 준비 (hoodcat-harness.archive.20260521 + feat/agent-cleanup)
- [x] Phase 1: 사전 정리 (룰 정본화·본문 슬림화·orchestrator 분할·examples 일관화·Small-Change Exceptions)
- [x] Phase 2: 12 스킬에 OMC 호환 절 추가 (정적 매핑)
- [x] Phase 3: orchestrator catalog/recipes에 OMC 호환 매핑 표·패턴 추가
- [x] Phase 4: 10 운영 훅에 OMC 매핑 주석 + settings-omc.json.example 작성
- [x] Phase 5: 정적 검증 (V1~V6) 모두 통과

## Phase 5+ 운영 검증 항목 (settings.json 실제 swap 전 필수)

- [ ] OMC executor의 광범위 Bash 권한(npm/pytest/cargo/go/make/docker/pip audit/govulncheck/gh) 지원 검증 (최우선)
- [ ] OMC ultraqa vs hoodcat qa-swarm 기능 동등성 검증 (병렬 스폰 + 결과 통합)
- [ ] context-mode MCP가 OMC 환경에서 동작하는지 확인 (coder·researcher 의존성)
- [ ] OMC notepad/shared-memory TTL·gc 정책 호환성 검증 (shared-context-config.json 기준)
- [ ] OMC team의 TeammateIdle 이벤트 내장 처리 확인
- [ ] shared_memory_write 동시성 안전성 ↔ flock 동등성 확인
- [ ] 글로벌 telegram plugin이 SubagentStop을 받는지 알림 도달 테스트
- [ ] verifier 명시 호출로 task-quality-gate 자동 트리거 없이 동등 검증 강도 유지되는지 운영 관찰
- [ ] OMC analyst가 hoodcat decide의 trade-off 표·자료 등급 분석을 동등하게 제공하는지 확인

## 미매핑 항목 결정 필요

- [ ] `deploy` 스킬: 커스텀 유지 / 신규 OMC 스킬 작성 / 폐기 — 결정
- [ ] `scaffold` 스킬: 동일 — 결정
- [ ] `sync-docs` 스킬: 동일 — 결정
- [ ] 프로젝트 로컬 `.claude/rules/` (source-hierarchy / epistemic-honesty / antipatterns-{general,python,typescript}) 와 글로벌 `~/.claude/rules/` 중복: 글로벌 동기화 후 로컬 제거 가능 여부 결정

## 전환 안정화 후

- [ ] hoodcat-harness.archive.20260521 제거
- [ ] 본 TODO.md 정리 (완료 항목 archive 또는 삭제)
- [ ] 매핑 plan 문서를 changelog로 분리
