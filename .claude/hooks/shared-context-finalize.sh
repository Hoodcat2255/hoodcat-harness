#!/usr/bin/env bash
# SessionEnd Hook - Shared Context: finalize session summary with metrics
# exit 0 guaranteed - never blocks session shutdown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"
CONTEXT_BASE="$PROJECT_DIR/.claude/shared-context"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] SHARED_CTX_FINALIZE: $1" >> "$LOG_FILE"
}

# stdin from hook input
INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, skipping finalize"
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  log "WARN: session_id missing from input"
  exit 0
fi

SESSION_DIR="$CONTEXT_BASE/$SESSION_ID"

if [ ! -d "$SESSION_DIR" ]; then
  log "INFO: Session directory not found: $SESSION_DIR"
  exit 0
fi

# Count agent context files (exclude _summary.md, _config.json, .lock)
agent_count=0
total_size=0
for ctx_file in "$SESSION_DIR"/*.md; do
  [ -f "$ctx_file" ] || continue
  basename_file="$(basename "$ctx_file")"
  [ "$basename_file" = "_summary.md" ] && continue
  agent_count=$((agent_count + 1))
  file_size=$(wc -c < "$ctx_file" 2>/dev/null || echo 0)
  total_size=$((total_size + file_size))
done

# Add finalization metadata to _summary.md
SUMMARY_FILE="$SESSION_DIR/_summary.md"
if [ -f "$SUMMARY_FILE" ]; then
  {
    echo ""
    echo "---"
    echo "> Session finalized: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    echo "> Total agents: $agent_count"
    echo "> Total context size: ${total_size} bytes"
  } >> "$SUMMARY_FILE"
fi

log "Session finalized: session=$SESSION_ID agents=$agent_count size=${total_size}B"

exit 0
