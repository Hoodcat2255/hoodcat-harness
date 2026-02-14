#!/usr/bin/env bash
# SubagentStop Hook - notify-telegram.sh
# Orchestrator 완료 시 텔레그램으로 알림을 보낸다.
# 안전성: 어떤 상황에서도 exit 0으로 종료한다.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
LOG_DIR="$PROJECT_DIR/.claude/log"
LOG_FILE="$LOG_DIR/hooks.log"

mkdir -p "$LOG_DIR"

log() {
  echo "[$(date -u +"%Y-%m-%dT%H:%M:%S+00:00")] TELEGRAM_NOTIFY: $1" >> "$LOG_FILE"
}

# stdin에서 JSON 읽기
INPUT=$(cat)

# jq 미설치 시 안전한 종료
if ! command -v jq &>/dev/null; then
  log "WARN: jq not installed, skipping notification"
  exit 0
fi

# curl 미설치 시 안전한 종료
if ! command -v curl &>/dev/null; then
  log "WARN: curl not installed, skipping notification"
  exit 0
fi

# JSON 파싱
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""' 2>/dev/null || echo "")
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""' 2>/dev/null || echo "")
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""' 2>/dev/null || echo "")

# orchestrator만 알림 대상
if [ "$AGENT_TYPE" != "orchestrator" ]; then
  exit 0
fi

log "Orchestrator completed: session=$SESSION_ID id=$AGENT_ID"

# .env 파일 로드 (전역 ~/.claude/.env > 프로젝트별 .env 순서, 후자가 덮어씀)
load_env() {
  local env_file="$1"
  if [ -f "$env_file" ]; then
    # 주석과 빈 줄을 제외하고 export
    while IFS= read -r line || [ -n "$line" ]; do
      # 빈 줄, 주석 건너뛰기
      [[ -z "$line" || "$line" =~ ^[[:space:]]*# ]] && continue
      # 변수만 export (KEY=VALUE 형식)
      if [[ "$line" =~ ^[A-Za-z_][A-Za-z0-9_]*= ]]; then
        export "$line"
      fi
    done < "$env_file"
    log "Loaded env from: $env_file"
  fi
}

load_env "$HOME/.claude/.env"
load_env "$PROJECT_DIR/.env"

# 환경 변수 확인 - 없으면 조용히 종료
if [ -z "${HARNESS_TG_BOT_TOKEN:-}" ] || [ -z "${HARNESS_TG_CHAT_ID:-}" ]; then
  log "INFO: HARNESS_TG_BOT_TOKEN or HARNESS_TG_CHAT_ID not set, skipping"
  exit 0
fi

# 프로젝트 이름 추출
PROJECT_NAME=$(basename "$PROJECT_DIR")

# 완료 시각
COMPLETED_AT=$(date +"%Y-%m-%d %H:%M:%S %Z")

# 공유 컨텍스트에서 요약 추출
SUMMARY=""
CONTEXT_FILE="$PROJECT_DIR/.claude/shared-context/${SESSION_ID}/orchestrator-${AGENT_ID}.md"
if [ -f "$CONTEXT_FILE" ] && [ -s "$CONTEXT_FILE" ]; then
  # 첫 500자까지만 추출 (텔레그램 메시지 길이 제한 고려)
  SUMMARY=$(head -c 500 "$CONTEXT_FILE" 2>/dev/null || echo "")
  log "Extracted summary from context file ($(wc -c < "$CONTEXT_FILE") bytes)"
fi

# MarkdownV2 특수문자 이스케이프
# 이스케이프 대상: _ * [ ] ( ) ~ ` > # + - = | { } . !
escape_markdownv2() {
  local text="$1"
  # sed로 특수문자 앞에 백슬래시 추가
  # 주의: backslash를 가장 먼저 처리해야 이중 이스케이프 방지
  echo "$text" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/_/\\_/g' \
    -e 's/\*/\\*/g' \
    -e 's/\[/\\[/g' \
    -e 's/\]/\\]/g' \
    -e 's/(/\\(/g' \
    -e 's/)/\\)/g' \
    -e 's/~/\\~/g' \
    -e 's/`/\\`/g' \
    -e 's/>/\\>/g' \
    -e 's/#/\\#/g' \
    -e 's/+/\\+/g' \
    -e 's/\-/\\-/g' \
    -e 's/=/\\=/g' \
    -e 's/|/\\|/g' \
    -e 's/{/\\{/g' \
    -e 's/}/\\}/g' \
    -e 's/\./\\./g' \
    -e 's/!/\\!/g'
}

# 메시지 구성
if [ -n "$SUMMARY" ]; then
  ESCAPED_PROJECT=$(escape_markdownv2 "$PROJECT_NAME")
  ESCAPED_TIME=$(escape_markdownv2 "$COMPLETED_AT")
  ESCAPED_SUMMARY=$(escape_markdownv2 "$SUMMARY")

  MESSAGE="*Orchestrator 완료*

*프로젝트:* ${ESCAPED_PROJECT}
*시각:* ${ESCAPED_TIME}

*요약:*
${ESCAPED_SUMMARY}"
else
  ESCAPED_PROJECT=$(escape_markdownv2 "$PROJECT_NAME")
  ESCAPED_TIME=$(escape_markdownv2 "$COMPLETED_AT")

  MESSAGE="*Orchestrator 완료*

*프로젝트:* ${ESCAPED_PROJECT}
*시각:* ${ESCAPED_TIME}

작업이 완료되었습니다\\."
fi

# 메시지 길이 제한 (Telegram 최대 4096자)
if [ ${#MESSAGE} -gt 4000 ]; then
  MESSAGE="${MESSAGE:0:3997}\\.\\.\\."
fi

log "Sending notification to Telegram (chat_id=${HARNESS_TG_CHAT_ID})"

# 백그라운드로 curl 실행 후 즉시 종료
(
  curl -s -X POST \
    --connect-timeout 5 \
    --max-time 5 \
    "https://api.telegram.org/bot${HARNESS_TG_BOT_TOKEN}/sendMessage" \
    -d "chat_id=${HARNESS_TG_CHAT_ID}" \
    -d "text=${MESSAGE}" \
    -d "parse_mode=MarkdownV2" \
    > /dev/null 2>&1 || true

  log "Notification sent (or failed silently)"
) &

exit 0
