#!/usr/bin/env bash
# SubagentStop Hook - Shared Context: collect agent results into shared context
# 1. Check for voluntary agent context file (primary mechanism)
# 2. Fall back to transcript parsing if no voluntary record exists (secondary)
# 3. Update _summary.md with flock for concurrent safety
# exit 0 guaranteed - never blocks subagent shutdown

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"
CONTEXT_BASE="$PROJECT_DIR/.claude/shared-context"
CONFIG_FILE="$PROJECT_DIR/.claude/shared-context-config.json"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] SHARED_CTX_COLLECT: $1" >> "$LOG_FILE"
}

# Capitalize first letter (bash 3.2 compatible; macOS default bash lacks ${var^})
capitalize_first() {
  local s="$1"
  [ -z "$s" ] && { echo ""; return 0; }
  local first rest
  first=$(printf '%s' "${s:0:1}" | tr '[:lower:]' '[:upper:]')
  rest="${s:1}"
  printf '%s%s' "$first" "$rest"
}

# stdin from hook input
INPUT=$(cat)

if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, skipping collection"
  exit 0
fi

SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || echo "")
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null || echo "")
# Future-proof: if a direct parent_agent_id field is ever introduced, use it.
PARENT_AGENT_ID_DIRECT=$(echo "$INPUT" | jq -r '.parent_agent_id // ""' 2>/dev/null || echo "")

if [ -z "$SESSION_ID" ]; then
  log "WARN: session_id missing, skipping"
  exit 0
fi

# --- Parent ID inference from agent_transcript_path directory pattern ---
# Claude Code does not currently expose a direct parent_agent_id field.
# transcript layout (observed):
#   .../{root_session_id}.jsonl                                                  (main agent)
#   .../{root_session_id}/subagents/{this_id}.jsonl                              (1st level fork)
#   .../{root_session_id}/subagents/{parent_id}/subagents/{this_id}.jsonl        (nested fork)
# Rule: parent transcript = dirname(parent_dir) + ".jsonl" when parent_dir ends with /subagents
# Parent id is then basename of grandparent_dir (regardless of nesting depth, since each
# level's transcript filename is the agent id).
infer_parent_id() {
  local agent_path="$1"
  [ -z "$agent_path" ] && return 0
  local parent_dir
  parent_dir=$(dirname "$agent_path")
  case "$parent_dir" in
    */subagents)
      local grandparent_dir
      grandparent_dir=$(dirname "$parent_dir")
      basename "$grandparent_dir"
      ;;
    *)
      # Not a forked subagent (root main session transcript) — no parent inferable
      echo ""
      ;;
  esac
}

# Expand ~ for parent inference (needed both for transcript fallback and parent calc)
TRANSCRIPT_PATH_EXPANDED="${TRANSCRIPT_PATH/#\~/$HOME}"

PARENT_INFERRED="false"
if [ -n "$PARENT_AGENT_ID_DIRECT" ]; then
  PARENT_ID="$PARENT_AGENT_ID_DIRECT"
else
  PARENT_ID="$(infer_parent_id "$TRANSCRIPT_PATH_EXPANDED")"
  if [ -n "$PARENT_ID" ]; then
    PARENT_INFERRED="true"
  fi
fi

CONTEXT_DIR="$CONTEXT_BASE/$SESSION_ID"

# Ensure directory exists
mkdir -p "$CONTEXT_DIR"

AGENT_CTX_FILE="$CONTEXT_DIR/${AGENT_TYPE}-${AGENT_ID}.md"
SUMMARY_FILE="$CONTEXT_DIR/_summary.md"
LOCK_FILE="$CONTEXT_DIR/.lock"

# Precompute capitalized form for headers (bash 3.2 safe)
AGENT_TYPE_CAP=$(capitalize_first "$AGENT_TYPE")

log "Collecting context: session=$SESSION_ID agent=$AGENT_TYPE id=$AGENT_ID"

# --- Step 0: Append to call-graph.jsonl (append-only, atomic per-line) ---
# Stores inferred parent -> child relationships for later analysis.
# Independent of _summary.md and transcript parsing; runs first so that even if
# downstream legacy logic errors out under set -e, the graph entry is preserved.
CALL_GRAPH_FILE="$CONTEXT_DIR/call-graph.jsonl"
if [ -n "$AGENT_ID" ] && command -v jq &>/dev/null; then
  GRAPH_LINE=$(jq -cn \
    --arg agent_id "$AGENT_ID" \
    --arg agent_type "$AGENT_TYPE" \
    --arg parent_id "$PARENT_ID" \
    --arg parent_inferred "$PARENT_INFERRED" \
    --arg transcript_path "$TRANSCRIPT_PATH" \
    --arg timestamp "$(date -u +"%Y-%m-%dT%H:%M:%SZ")" \
    '{
      agent_id: $agent_id,
      agent_type: $agent_type,
      parent_id: $parent_id,
      parent_inferred: ($parent_inferred == "true"),
      transcript_path: $transcript_path,
      timestamp: $timestamp
    }' 2>/dev/null || echo "")

  if [ -n "$GRAPH_LINE" ]; then
    if command -v flock &>/dev/null; then
      (
        flock -w 5 201 || { log "WARN: call-graph lock timeout, skipping graph line"; exit 0; }
        printf '%s\n' "$GRAPH_LINE" >> "$CALL_GRAPH_FILE"
      ) 201>"$CONTEXT_DIR/.call-graph.lock"
    else
      printf '%s\n' "$GRAPH_LINE" >> "$CALL_GRAPH_FILE"
    fi
    log "Call graph appended: agent=$AGENT_ID parent=${PARENT_ID:-<none>} inferred=$PARENT_INFERRED"
  fi
fi

# --- Step 1: Check for voluntary agent context file ---
HAS_VOLUNTARY=false
if [ -f "$AGENT_CTX_FILE" ] && [ -s "$AGENT_CTX_FILE" ]; then
  HAS_VOLUNTARY=true
  log "Found voluntary context file: $AGENT_CTX_FILE ($(wc -c < "$AGENT_CTX_FILE") bytes)"
fi

# --- Step 2: Transcript parsing fallback ---
if [ "$HAS_VOLUNTARY" = false ]; then
  log "No voluntary context, attempting transcript parsing"

  MAX_LINES=$(jq -r '.max_transcript_lines // 500' "$CONFIG_FILE" 2>/dev/null || echo 500)

  # TRANSCRIPT_PATH_EXPANDED already computed above for parent inference

  if [ -n "$TRANSCRIPT_PATH_EXPANDED" ] && [ -f "$TRANSCRIPT_PATH_EXPANDED" ]; then
    # Extract file changes from transcript (Write/Edit tool calls)
    CHANGES=""
    CHANGES=$(tail -n "$MAX_LINES" "$TRANSCRIPT_PATH_EXPANDED" 2>/dev/null | \
      jq -r '
        select(.type == "tool_result") |
        select(.tool_name == "Write" or .tool_name == "Edit") |
        "- \(.tool_input.file_path // "unknown")"
      ' 2>/dev/null | sort -u || echo "")

    if [ -n "$CHANGES" ]; then
      # Create a minimal context file from transcript data
      {
        echo "## ${AGENT_TYPE_CAP} Report (auto-extracted)"
        echo ""
        echo "### Files Modified"
        echo "$CHANGES"
        echo ""
        echo "> Auto-extracted from transcript at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      } > "$AGENT_CTX_FILE"
      log "Created context from transcript: $(echo "$CHANGES" | wc -l) file(s)"
    else
      log "No file changes found in transcript"
      # Create minimal placeholder
      {
        echo "## ${AGENT_TYPE_CAP} Report (auto-extracted)"
        echo ""
        echo "### Summary"
        echo "- Agent completed with no detected file changes"
        echo ""
        echo "> Auto-extracted at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      } > "$AGENT_CTX_FILE"
    fi
  else
    log "Transcript not found or empty: $TRANSCRIPT_PATH_EXPANDED"
    # Create minimal record even without transcript
    {
      echo "## ${AGENT_TYPE_CAP} Report"
      echo ""
      echo "### Summary"
      echo "- Agent completed (no detailed context available)"
      echo ""
      echo "> Recorded at $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
    } > "$AGENT_CTX_FILE"
  fi
fi

# --- Step 3: Update _summary.md with flock ---
# Build the entry to append
ENTRY_CONTENT=""
if [ -f "$AGENT_CTX_FILE" ]; then
  # Read agent context, limit to reasonable size
  ENTRY_CONTENT=$(head -c 2000 "$AGENT_CTX_FILE" 2>/dev/null || echo "")
fi

if [ -z "$ENTRY_CONTENT" ]; then
  log "No content to add to summary"
  exit 0
fi

# Use flock for concurrent write safety
(
  if command -v flock &>/dev/null; then
    flock -w 5 200 || { log "WARN: Lock timeout, skipping summary update"; exit 0; }
  fi

  # Initialize summary if it doesn't exist
  if [ ! -f "$SUMMARY_FILE" ]; then
    {
      echo "# Shared Context Summary"
      echo "> Session: ${SESSION_ID}"
      echo "> Updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")"
      echo "> Entries: 0"
      echo ""
    } > "$SUMMARY_FILE"
  fi

  # Count current entries
  CURRENT_ENTRIES=$(grep -c '^\[' "$SUMMARY_FILE" 2>/dev/null || true)
  # Sanitize: grep -c may return empty string
  CURRENT_ENTRIES="${CURRENT_ENTRIES:-0}"
  NEW_ENTRIES=$((CURRENT_ENTRIES + 1))

  # Append the new entry with agent identifier
  {
    echo ""
    echo "### [${AGENT_TYPE}-${AGENT_ID}] $(date -u +"%H:%M:%SZ")"
    # Extract key lines from the agent context (skip markdown headers and empty lines for summary)
    while IFS= read -r line; do
      case "$line" in
        "## "*|"### "*) echo "$line" ;;
        "- "*) echo "[${AGENT_TYPE}] ${line}" ;;
        "> "*) ;; # skip metadata lines
        "") ;; # skip empty lines
        *) echo "[${AGENT_TYPE}] ${line}" ;;
      esac
    done <<< "$ENTRY_CONTENT"
    echo ""
  } >> "$SUMMARY_FILE"

  # Update timestamp and entry count in header
  if command -v sed &>/dev/null; then
    sed -i "s/^> Updated:.*/> Updated: $(date -u +"%Y-%m-%dT%H:%M:%SZ")/" "$SUMMARY_FILE" 2>/dev/null || true
    sed -i "s/^> Entries:.*/> Entries: ${NEW_ENTRIES}/" "$SUMMARY_FILE" 2>/dev/null || true
  fi

  log "Summary updated: entries=$NEW_ENTRIES"

) 200>"$LOCK_FILE"

log "Collection complete for agent=$AGENT_TYPE"

exit 0
