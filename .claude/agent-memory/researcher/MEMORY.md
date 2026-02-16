# Researcher Agent Memory

## Context7 Library IDs
- React Flow: /websites/reactflow_dev (snippet 1113, score 79.2, High rep)
- React Flow (GitHub): /xyflow/xyflow (snippet 43)
- Xyflow web/docs: /xyflow/web (snippet 1840, score 81.8)
- Claude Code (official): /anthropics/claude-code (snippet 778, score 80.6, High rep)
- Claude Code (website): /websites/code_claude (snippet 1476, score 53.3, High rep)
- Claude Code Tools: /pchalasani/claude-code-tools (snippet 541, score 55.5)

## Research Patterns
- GitHub 이슈 검색 시 `gh search issues "keyword" --repo owner/repo --sort updated` 사용
- README 조회: `gh api repos/{owner}/{repo}/readme --jq '.content' | base64 -d`
- GitHub 파일 내용 조회: `gh api repos/{owner}/{repo}/contents/{path} --jq '.content' | base64 -d`
- ComfyUI mobile frontend repos: cosmicbuffalo, viyiviyi, XelaNull
- Claude Code hooks 참조 레포: disler/claude-code-hooks-mastery (3051 stars), karanb192/claude-code-hooks

## Done
- 2026-02-16: 모바일 노드 에디터 UX 패턴 조사 -> docs/research-mobile-node-editor-ux-20260216.md
  - 핵심: 노드 그래프는 모바일 비친화적, 리스트 뷰가 모범 사례
  - React Flow touch props: connectOnClick, zoomOnPinch, panOnDrag
- 2026-02-16: Claude Code Hooks 전체 스펙 조사 -> docs/research-claude-code-hooks-spec-20260216.md
  - 13개 훅 이벤트: Setup, SessionStart/End, UserPromptSubmit, PreToolUse, PostToolUse, PostToolUseFailure, PermissionRequest, PreCompact, Stop, SubagentStart/Stop, Notification + TaskCompleted, TeammateIdle
  - PreToolUse: exit 2로 차단, hookSpecificOutput으로 allow/deny/ask + updatedInput
  - SubagentStart: additionalContext로 서브에이전트에 컨텍스트 주입
  - PreToolUse에서 메인/서브에이전트 구분 불가 (공식 필드 없음)
