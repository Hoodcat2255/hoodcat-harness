#!/usr/bin/env bash
# SubagentStop Monitor - 서브에이전트 종료 이벤트를 로깅한다.
# 차단하지 않음 - 서브에이전트는 자연스럽게 종료된다.
# 추가: agent_transcript_path 디렉토리 패턴에서 parent_id를 추론하여 로깅에 포함.
# === OMC 호환 매핑 (Phase 4) ===
# OMC 전환 시: OMC trace_* 도구 또는 SubagentStop 훅 + state_write로 대체.
# 호출: mcp__plugin_oh-my-claudecode_t__trace_summary / trace_timeline 으로 서브에이전트 종료 이벤트 분석.
# 매핑 신뢰도: 중간 (call-graph 기록 동등성 검증 필요).
# 자세한 사항: docs/migration-omc-mapping-20260522.md 3절.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"

mkdir -p "$LOG_DIR"

HOOK_INPUT=$(cat)

# Parent ID inference (same algorithm as shared-context-collect.sh).
# transcript layout:
#   .../{root_id}.jsonl                                            (main)
#   .../{root_id}/subagents/{this_id}.jsonl                        (level 1)
#   .../{root_id}/subagents/{parent_id}/subagents/{this_id}.jsonl  (nested)
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
      echo ""
      ;;
  esac
}

AGENT_TYPE=""
AGENT_ID=""
TRANSCRIPT_PATH=""
PARENT_ID=""
PARENT_INFERRED="false"
PARENT_AGENT_ID_DIRECT=""

if command -v jq &>/dev/null; then
  AGENT_TYPE=$(echo "$HOOK_INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
  AGENT_ID=$(echo "$HOOK_INPUT" | jq -r '.agent_id // ""' 2>/dev/null || echo "")
  TRANSCRIPT_PATH=$(echo "$HOOK_INPUT" | jq -r '.agent_transcript_path // ""' 2>/dev/null || echo "")
  PARENT_AGENT_ID_DIRECT=$(echo "$HOOK_INPUT" | jq -r '.parent_agent_id // ""' 2>/dev/null || echo "")

  TRANSCRIPT_PATH_EXPANDED="${TRANSCRIPT_PATH/#\~/$HOME}"

  if [ -n "$PARENT_AGENT_ID_DIRECT" ]; then
    PARENT_ID="$PARENT_AGENT_ID_DIRECT"
  else
    PARENT_ID="$(infer_parent_id "$TRANSCRIPT_PATH_EXPANDED")"
    if [ -n "$PARENT_ID" ]; then
      PARENT_INFERRED="true"
    fi
  fi
fi

PARENT_FIELD="parent_id=${PARENT_ID:--} parent_inferred=${PARENT_INFERRED}"

echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] SUBAGENT_STOP: ${PARENT_FIELD} input=$HOOK_INPUT" >> "$LOG_FILE"

exit 0
