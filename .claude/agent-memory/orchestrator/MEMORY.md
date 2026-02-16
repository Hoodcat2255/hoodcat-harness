# Orchestrator Memory

## Done
- 2026-02-15: Write 도구 경로 제한 보강 - `.claude/`, `docs/` 하위만 허용, Self-Check에 경로 검증 추가
- 2026-02-15: 오케스트레이터 위임율 개선 - Edit 도구 제거, FORBIDDEN/REQUIRED 규칙, 리뷰 의무화 기준 추가
- 2026-02-15: 대시보드 독립 레포 분리 (~/Projects/claude-dashboard, Docker 배포)
- 2026-02-15: 대화 이력 대시보드 구현 (feat/conversation-dashboard 브랜치, tools/conversation-dashboard/)
- 2026-02-14: 텔레그램 봇 알림 훅 구현 (feat/telegram-notify 브랜치)

## Patterns
- SubagentStop 훅 stdin JSON 필드: session_id, agent_type, agent_id, agent_transcript_path
- sed bracket expression 안에서는 `\[`, `\]` 같은 이스케이프가 작동하지 않음 -> 개별 `-e` 옵션으로 분리해야 함
- settings.json은 `.claude/` 하위이며, `.claude/` 전체가 gitignore됨 (settings.local.json에서 settings.json으로 변경됨)
- Claude Code 대화 저장: `~/.claude/projects/{path-encoded}/{session-uuid}.jsonl` (프로젝트별 관리)
- JSONL 레코드 타입: user, assistant, system, progress, file-history-snapshot
- 서브에이전트: `{session-uuid}/subagents/agent-{id}.jsonl`
- history.jsonl은 readline history만 (display, timestamp, project, sessionId)
