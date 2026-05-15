#!/usr/bin/env bash
# PreToolUse Hook - Main Agent의 Edit/Write 도구 직접 사용 차단
#
# 서브에이전트 판별 신호 (하나라도 만족하면 ALLOW):
#   1. .agent_transcript_path 가 비어있지 않음 (현재 Claude Code의 권위 있는 신호)
#   2. .transcript_path 에 "/subagents/" 포함 (레거시 폴백)
#   3. .agent_id 와 .agent_type 이 모두 비어있지 않음 (안전망)
#
# exit 0 = 허용, exit 2 = 차단 (stderr가 Claude에게 피드백)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] ENFORCE_DELEGATION: $1" >> "$LOG_FILE"
}

# 구조화된 차단 메시지를 stderr로 출력 (4줄 포맷)
#   $1: 도구 이름 (Edit / Write)
#   $2: 파일 경로 (없으면 "none")
emit_block_message() {
  local tool="$1"
  local file_path="${2:-none}"
  [ -z "$file_path" ] && file_path="none"
  {
    echo "[delegation-block] Tool=$tool File=$file_path"
    echo "Reason: Main Agent cannot modify source/code/config files directly."
    echo "Action: Task(orchestrator, \"<your request>\") 로 위임하세요."
    echo "Allowed: 서브에이전트는 차단되지 않음. .md 파일(.claude/, docs/ 하위)은 Write 허용."
  } >&2
}

# stdin에서 hook 입력 읽기
input=$(cat)

# jq 미설치 시 안전하게 허용 (fail-open)
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, allowing tool use"
  exit 0
fi

# 공통 필드 추출 (jq 1회 호출당 안전 fallback)
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")
agent_transcript_path=$(echo "$input" | jq -r '.agent_transcript_path // ""' 2>/dev/null || echo "")
agent_id=$(echo "$input" | jq -r '.agent_id // ""' 2>/dev/null || echo "")
agent_type=$(echo "$input" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# 서브에이전트 판별: 신호별 사유를 반환 (빈 문자열이면 Main Agent)
detect_subagent_signal() {
  # 신호 1: agent_transcript_path (가장 권위 있는 현재 스키마)
  if [ -n "$agent_transcript_path" ]; then
    echo "agent_transcript_path"
    return
  fi
  # 신호 2: transcript_path 에 /subagents/ 포함 (레거시 폴백)
  if echo "$transcript_path" | grep -q '/subagents/'; then
    echo "transcript_path_subagents"
    return
  fi
  # 신호 3: agent_id + agent_type 동시 존재 (안전망)
  if [ -n "$agent_id" ] && [ -n "$agent_type" ]; then
    echo "agent_id_and_type"
    return
  fi
  echo ""
}

subagent_signal=$(detect_subagent_signal)

if [ -n "$subagent_signal" ]; then
  log "ALLOW: Subagent $tool_name (via $subagent_signal)"
  exit 0
fi

# 여기까지 왔으면 Main Agent로 판단됨.
# 안전망: 입력에 서브에이전트 의심 필드가 흔적이라도 있으면 전체 input을 dump하여
# PreToolUse payload의 실제 키 구조를 라이브 운영에서 확정할 수 있게 한다.
if [ -n "$agent_id" ] || [ -n "$agent_transcript_path" ] || [ -n "$agent_type" ]; then
  # input JSON을 한 줄로 압축 (개행 제거)하여 grep 가능한 단일 라인으로 기록
  compact_input=$(echo "$input" | jq -c '.' 2>/dev/null || echo "$input" | tr -d '\n')
  log "[ENFORCE_DELEGATION_DEBUG] suspicious_main_agent input=$compact_input"
fi

# Edit 도구: 무조건 차단
if [ "$tool_name" = "Edit" ]; then
  edit_file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")
  log "BLOCK: Main Agent $tool_name attempt on ${edit_file_path:-<none>}"
  emit_block_message "Edit" "$edit_file_path"
  exit 2
fi

# Write 도구: 소스 코드 확장자이면 차단
if [ "$tool_name" = "Write" ]; then
  file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null || echo "")

  # 확장자 추출
  extension="${file_path##*.}"

  # 파일에 확장자가 없는 경우 (파일명에 .이 없음) 허용
  if [ "$extension" = "$file_path" ]; then
    log "ALLOW: Main Agent Write on file without extension: $file_path"
    exit 0
  fi

  # .md 파일은 허용 (문서 작성용)
  if [ "$extension" = "md" ]; then
    log "ALLOW: Main Agent Write on .md file: $file_path"
    exit 0
  fi

  # 차단 대상 확장자 목록
  blocked_extensions="py js ts tsx jsx css scss html sh bash json yaml yml toml ini cfg conf xml sql go rs java c cpp h hpp rb php swift kt vue svelte astro"

  for ext in $blocked_extensions; do
    if [ "$extension" = "$ext" ]; then
      log "BLOCK: Main Agent $tool_name attempt on $file_path"
      emit_block_message "Write" "$file_path"
      exit 2
    fi
  done

  # 목록에 없는 확장자는 허용
  log "ALLOW: Main Agent Write on non-blocked extension: $file_path"
  exit 0
fi

# 그 외 도구: 허용
exit 0
