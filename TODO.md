# 오케스트레이터 위임율 개선

claude-dashboard 실데이터 분석 결과, 오케스트레이터가 스킬/에이전트 위임 없이 직접 코드를 수정하는 비율이 98.7%임.
(18개 인스턴스, Skill 7회 vs 직접 도구 537회, 리뷰 에이전트 스폰 0회)

## 원인

- orchestrator.md에 Edit/Write 도구 권한이 있어서 직접 수정 가능
- "delegate, don't code" 지시가 있지만 도구가 있으면 직접 실행하는 경향
- 소규모 프로젝트에서 위임 오버헤드를 회피

## 할 일

- [x] orchestrator.md에서 Edit 도구 제거 (소스코드 직접 수정 불가하게)
- [x] Write는 .md 파일만 허용하도록 프롬프트에 명시
- [x] 소스코드 수정 금지 규칙 추가 (FORBIDDEN: Edit on .py/.html/.js/.ts/.css + 40개 확장자)
- [x] 필수 위임 규칙 추가 (REQUIRED: Skill("code"), Skill("test"), Skill("commit"))
- [x] 리뷰 에이전트 활용 규칙 추가 (3+ 파일 변경 또는 보안 관련 시 Task(reviewer) 의무)
- [ ] 변경 후 실제 세션에서 위임율 개선 여부 검증
- [ ] Small-Change Exceptions 절 적용 후 위임율·오버헤드 트레이드오프 재측정 (.md 1줄 수정 케이스 직접 처리율)

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

- [ ] enforce-delegation.sh 3-신호 OR 판별이 OMC executor 서브에이전트를 인식하는지 회귀 테스트 (최우선)
- [ ] OMC executor의 광범위 Bash 권한(npm/pytest/cargo/go/make/docker/pip audit/govulncheck/gh) 지원 검증
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
