#!/usr/bin/env bash
# SubagentStart Hook - Shared Context: inject shared context into subagent via additionalContext
# Reads _summary.md, applies agent-type filtering and size limits,
# outputs JSON with additionalContext containing shared context + write instructions.
# exit 0 guaranteed - never blocks subagent startup

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"
CONTEXT_BASE="$PROJECT_DIR/.claude/shared-context"
CONFIG_FILE="$PROJECT_DIR/.claude/shared-context-config.json"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] SHARED_CTX_INJECT: $1" >> "$LOG_FILE"
}

# Safe exit: output nothing and exit 0
safe_exit() {
  log "Safe exit: $1"
  exit 0
}

# stdin from hook input
INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  safe_exit "jq not installed"
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  safe_exit "session_id missing"
fi

CONTEXT_DIR="$CONTEXT_BASE/$SESSION_ID"
SUMMARY_FILE="$CONTEXT_DIR/_summary.md"

# Build the write instruction for the agent
AGENT_CTX_FILE="${AGENT_TYPE}-${AGENT_ID}.md"
WRITE_INSTRUCTION="[Shared Context] 작업 완료 시, 핵심 발견 사항을 다음 파일에 기록하세요: .claude/shared-context/${SESSION_ID}/${AGENT_CTX_FILE}"

# Ensure session directory exists (may not exist if SessionStart hook didn't fire)
mkdir -p "$CONTEXT_DIR"

# If no summary file exists, output write instruction only
if [ ! -f "$SUMMARY_FILE" ]; then
  log "No summary found for session=$SESSION_ID, injecting write instruction only"
  jq -n --arg ctx "$WRITE_INSTRUCTION" '{
    hookSpecificOutput: {
      hookEventName: "SubagentStart",
      additionalContext: $ctx
    }
  }'
  exit 0
fi

# Read config
MAX_CHARS=$(jq -r '.max_summary_chars // 4000' "$CONFIG_FILE" 2>/dev/null || echo 4000)

# Read summary with size limit
SUMMARY=$(head -c "$MAX_CHARS" "$SUMMARY_FILE" 2>/dev/null || echo "")

if [ -z "$SUMMARY" ]; then
  log "Empty summary for session=$SESSION_ID, injecting write instruction only"
  jq -n --arg ctx "$WRITE_INSTRUCTION" '{
    hookSpecificOutput: {
      hookEventName: "SubagentStart",
      additionalContext: $ctx
    }
  }'
  exit 0
fi

# Apply agent-type filtering
# Read the filter categories this agent type should receive
FILTER_CATEGORIES=$(jq -r --arg agent "$AGENT_TYPE" '.filters[$agent] // [] | .[]' "$CONFIG_FILE" 2>/dev/null || echo "")

if [ -n "$FILTER_CATEGORIES" ] && [ -n "$AGENT_TYPE" ]; then
  # Filter summary sections based on categories
  FILTERED_SUMMARY=""
  HEADER_ADDED=false

  while IFS= read -r line; do
    # Always include header lines (starting with # or >)
    if echo "$line" | grep -q '^#\|^>' ; then
      if [ "$HEADER_ADDED" = false ]; then
        FILTERED_SUMMARY="$line"
        HEADER_ADDED=true
      else
        FILTERED_SUMMARY="${FILTERED_SUMMARY}
${line}"
      fi
      continue
    fi

    # Check if line matches any allowed category
    include=false
    for category in $FILTER_CATEGORIES; do
      case "$category" in
        navigation)
          if echo "$line" | grep -qi 'navigat\|file.*found\|pattern\|depend\|impact\|explore'; then
            include=true
          fi
          ;;
        code_changes)
          if echo "$line" | grep -qi 'change\|modif\|creat\|delet\|edit\|write\|commit\|build\|test'; then
            include=true
          fi
          ;;
        review)
          if echo "$line" | grep -qi 'review\|verdict\|pass\|warn\|block\|finding'; then
            include=true
          fi
          ;;
      esac
      if [ "$include" = true ]; then break; fi
    done

    # Include lines that match or are part of section headers
    if [ "$include" = true ] || [ -z "$line" ]; then
      FILTERED_SUMMARY="${FILTERED_SUMMARY}
${line}"
    fi
  done <<< "$SUMMARY"

  # Use filtered summary if it has content, otherwise use full summary
  if [ -n "$FILTERED_SUMMARY" ]; then
    SUMMARY="$FILTERED_SUMMARY"
  fi
fi

# Build full context: summary + write instruction
FULL_CONTEXT="## Shared Context (이전 에이전트 작업 결과)

${SUMMARY}

---
${WRITE_INSTRUCTION}"

log "Injecting shared context for session=$SESSION_ID agent=$AGENT_TYPE (${#FULL_CONTEXT} chars)"

# Output JSON with additionalContext
jq -n --arg ctx "$FULL_CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: $ctx
  }
}'

exit 0
