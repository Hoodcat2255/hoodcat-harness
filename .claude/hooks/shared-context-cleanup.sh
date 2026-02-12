#!/usr/bin/env bash
# SessionStart Hook - Shared Context: TTL-expired session cleanup + current session init
# exit 0 guaranteed - never blocks session startup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"
CONTEXT_BASE="$PROJECT_DIR/.claude/shared-context"
CONFIG_FILE="$PROJECT_DIR/.claude/shared-context-config.json"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] SHARED_CTX_CLEANUP: $1" >> "$LOG_FILE"
}

# stdin from hook input
INPUT=$(cat)

# jq required for JSON parsing
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, skipping cleanup"
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  log "WARN: session_id missing from input"
  exit 0
fi

log "Session start: session=$SESSION_ID"

# Ensure base directory exists
mkdir -p "$CONTEXT_BASE"

# TTL-based cleanup of expired session directories
TTL_HOURS=$(jq -r '.ttl_hours // 24' "$CONFIG_FILE" 2>/dev/null || echo 24)
TTL_MINUTES=$((TTL_HOURS * 60))

# Find and remove expired session directories (only direct subdirectories)
if [ -d "$CONTEXT_BASE" ]; then
  expired_count=0
  for session_dir in "$CONTEXT_BASE"/*/; do
    [ -d "$session_dir" ] || continue
    # Use find to check modification time of the directory itself
    if find "$session_dir" -maxdepth 0 -type d -mmin +"$TTL_MINUTES" 2>/dev/null | grep -q .; then
      rm -rf "$session_dir"
      expired_count=$((expired_count + 1))
    fi
  done
  if [ "$expired_count" -gt 0 ]; then
    log "Cleaned up $expired_count expired session(s) (TTL=${TTL_HOURS}h)"
  fi
fi

# Create current session directory
SESSION_DIR="$CONTEXT_BASE/$SESSION_ID"
mkdir -p "$SESSION_DIR"

log "Session directory created: $SESSION_DIR"

exit 0
