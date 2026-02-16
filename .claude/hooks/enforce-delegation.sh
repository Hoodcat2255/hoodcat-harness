#!/usr/bin/env bash
# PreToolUse Hook - Main Agent의 Edit/Write 도구 직접 사용 차단
# 서브에이전트(transcript_path에 /subagents/ 포함)는 허용
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

# stdin에서 hook 입력 읽기
input=$(cat)

# jq 미설치 시 안전하게 허용
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, allowing tool use"
  exit 0
fi

# transcript_path 추출
transcript_path=$(echo "$input" | jq -r '.transcript_path // ""' 2>/dev/null || echo "")

# 서브에이전트 판별: transcript_path에 "/subagents/"가 포함되면 서브에이전트
if echo "$transcript_path" | grep -q '/subagents/'; then
  tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")
  log "ALLOW: Subagent $tool_name (transcript contains /subagents/)"
  exit 0
fi

# Main Agent인 경우: tool_name 확인
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null || echo "")

# Edit 도구: 무조건 차단
if [ "$tool_name" = "Edit" ]; then
  log "BLOCK: Main Agent $tool_name attempt"
  echo "Main Agent는 코드를 직접 수정할 수 없습니다. Task(orchestrator, ...)로 위임하세요." >&2
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
      echo "Main Agent는 코드/설정 파일을 직접 수정할 수 없습니다. Task(orchestrator, ...)로 위임하세요." >&2
      exit 2
    fi
  done

  # 목록에 없는 확장자는 허용
  log "ALLOW: Main Agent Write on non-blocked extension: $file_path"
  exit 0
fi

# 그 외 도구: 허용
exit 0
