# Committer Agent Memory

## TODO
- 없음

## In Progress
- 없음

## Done
- 2026-02-16: `b46faa4` feat: Main Agent 위임규칙 강제를 위한 2층 방어 시스템 구현
  - harness.md: 자기 검증 체크리스트, FORBIDDEN/ALLOWED 행위 목록, 위임 강제 훅 문서
  - enforce-delegation.sh: PreToolUse 훅 (Main Agent Edit/Write 차단)
  - settings.json: PreToolUse 훅 등록
- 2026-02-15: `d199000` feat: harness 삭제 기능 개선 및 orchestrator 위임율 강화
  - orchestrator.md: Edit 도구 제거, Delegation Enforcement 섹션 추가
  - harness.sh: delete 명령 개선 (선택적 삭제, unmerge_settings_json, remove_harness_import)
- 2026-02-15: `2c41631` docs: 텔레그램 알림 훅 문서화
  - harness.md에 텔레그램 알림 훅 섹션 추가
  - CLAUDE.md 디렉토리 설명 업데이트

## Commit Conventions (이 프로젝트)
- Conventional Commits 형식: `<type>: <description>`
- 타입: feat, fix, docs, refactor, style, test, chore
- 한국어 description 사용
- Co-Authored-By 포함하지 않음

## Pre-commit Hook Patterns
- 이 프로젝트에는 pre-commit hook이 없음

## Notes
- `.claude/agent-memory/`, `.claude/shared-context/`는 .gitignore에 포함되어 커밋하지 않음
- 민감 파일 패턴: .env, credentials, secrets
