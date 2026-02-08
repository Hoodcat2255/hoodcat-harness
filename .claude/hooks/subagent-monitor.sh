#!/usr/bin/env bash
# SubagentStop Monitor - 서브에이전트 종료 이벤트를 로깅한다.
# 차단하지 않음 - 서브에이전트는 자연스럽게 종료된다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/sisyphus.log"

mkdir -p "$LOG_DIR"

HOOK_INPUT=$(cat)

echo "[$(date -Iseconds)] SUBAGENT_STOP: $HOOK_INPUT" >> "$LOG_FILE"

exit 0
