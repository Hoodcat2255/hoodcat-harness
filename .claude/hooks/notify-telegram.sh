#!/usr/bin/env bash
# SubagentStop Hook - notify-telegram.sh
# Orchestrator 완료 시 텔레그램으로 풍부한 알림을 보낸다.
# 공유 컨텍스트 파일의 구조화된 Orchestrator Report를 파싱하여 메시지 구성.
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

# 완료 시각 (KST)
COMPLETED_AT=$(TZ="Asia/Seoul" date +"%Y-%m-%d %H:%M KST" 2>/dev/null || date +"%Y-%m-%d %H:%M %Z")

# =====================================================================
# 유틸리티 함수
# =====================================================================

# HTML 특수문자 이스케이프
# 이스케이프 대상: & < > (& 를 먼저 치환해야 &lt; 등의 & 가 재치환되지 않음)
escape_html() {
  local text="$1"
  echo "$text" | sed \
    -e 's/&/\&amp;/g' \
    -e 's/</\&lt;/g' \
    -e 's/>/\&gt;/g'
}

# 공유 컨텍스트 파일에서 마크다운 섹션 추출
# 사용법: extract_section "$content" "Plan"
# ### Plan 헤더 이후, 다음 ### 또는 ## 헤더 전까지의 내용을 반환
extract_section() {
  local content="$1"
  local section="$2"
  local in_section=false
  local result=""

  while IFS= read -r line; do
    if [ "$in_section" = true ]; then
      # 다음 섹션 헤더를 만나면 중단
      if [[ "$line" =~ ^###?\  ]] || [[ "$line" =~ ^##\  ]]; then
        break
      fi
      # 빈 줄이 아닌 내용만 수집
      if [ -n "$line" ]; then
        if [ -n "$result" ]; then
          result="${result}
${line}"
        else
          result="$line"
        fi
      fi
    fi
    # 대상 섹션 헤더 감지
    if [[ "$line" == "### ${section}" ]] || [[ "$line" == "### ${section} " ]]; then
      in_section=true
    fi
  done <<< "$content"

  echo "$result"
}

# 파일 목록에서 파일명만 추출 (backtick, 리스트 마커 제거)
# 입력: "- `src/file.ts` -- 설명" 또는 "- src/file.ts" 등
extract_filenames() {
  local text="$1"
  echo "$text" | sed \
    -e 's/^[[:space:]]*-[[:space:]]*//' \
    -e 's/`//g' \
    -e 's/[[:space:]]*--.*$//' \
    -e 's/[[:space:]]*—.*$//' \
    -e '/^$/d'
}

# 파일 목록의 줄 수 세기
count_lines() {
  local text="$1"
  if [ -z "$text" ]; then
    echo 0
  else
    echo "$text" | wc -l | tr -d '[:space:]'
  fi
}

# =====================================================================
# 공유 컨텍스트에서 구조화된 데이터 추출
# =====================================================================

CONTEXT_FILE="$PROJECT_DIR/.claude/shared-context/${SESSION_ID}/orchestrator-${AGENT_ID}.md"
IS_STRUCTURED=false
PLAN_SUMMARY=""
FILES_CHANGED=""
FILE_COUNT=0
REVIEW_VERDICTS=""
UNRESOLVED_ISSUES=""

if [ -f "$CONTEXT_FILE" ] && [ -s "$CONTEXT_FILE" ]; then
  CONTEXT_CONTENT=$(head -c 4000 "$CONTEXT_FILE" 2>/dev/null || echo "")
  log "Read context file ($(wc -c < "$CONTEXT_FILE") bytes)"

  # 구조화된 Orchestrator Report인지 확인
  if echo "$CONTEXT_CONTENT" | grep -q "^## Orchestrator Report" 2>/dev/null || \
     echo "$CONTEXT_CONTENT" | grep -q "^### Plan" 2>/dev/null; then
    IS_STRUCTURED=true
    log "Detected structured Orchestrator Report"

    # Plan 섹션에서 첫 줄 (작업 요약) 추출
    PLAN_RAW=$(extract_section "$CONTEXT_CONTENT" "Plan")
    if [ -n "$PLAN_RAW" ]; then
      # 첫 줄만 추출, 리스트 마커 제거
      PLAN_SUMMARY=$(echo "$PLAN_RAW" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
    fi

    # Files Changed 섹션
    FILES_RAW=$(extract_section "$CONTEXT_CONTENT" "Files Changed")
    if [ -n "$FILES_RAW" ]; then
      FILES_CHANGED=$(extract_filenames "$FILES_RAW")
      FILE_COUNT=$(count_lines "$FILES_CHANGED")
    fi

    # Review Verdicts 섹션
    REVIEW_RAW=$(extract_section "$CONTEXT_CONTENT" "Review Verdicts")
    if [ -n "$REVIEW_RAW" ]; then
      # 리스트 마커 제거, 첫 줄만
      REVIEW_VERDICTS=$(echo "$REVIEW_RAW" | head -1 | sed 's/^[[:space:]]*-[[:space:]]*//')
    fi

    # Unresolved Issues 섹션
    ISSUES_RAW=$(extract_section "$CONTEXT_CONTENT" "Unresolved Issues")
    if [ -n "$ISSUES_RAW" ]; then
      UNRESOLVED_ISSUES=$(echo "$ISSUES_RAW" | head -3 | sed 's/^[[:space:]]*-[[:space:]]*//')
    fi
  fi
fi

# =====================================================================
# 메시지 구성
# =====================================================================

# 상태 판단: 미해결 이슈가 있으면 경고, 없으면 성공
has_issues() {
  if [ -z "$UNRESOLVED_ISSUES" ]; then
    return 1
  fi
  # "없음", "None", "N/A" 등은 이슈 없음으로 처리
  local lower
  lower=$(echo "$UNRESOLVED_ISSUES" | tr '[:upper:]' '[:lower:]')
  case "$lower" in
    *"없음"*|*"none"*|*"n/a"*|*"no issue"*|*"no unresolved"*|*"해당 없음"*)
      return 1
      ;;
  esac
  return 0
}

if [ "$IS_STRUCTURED" = true ]; then
  # --- 구조화된 리치 메시지 (HTML) ---
  if has_issues; then
    STATUS_EMOJI=$'\xe2\x9a\xa0\xef\xb8\x8f'  # warning sign
  else
    STATUS_EMOJI=$'\xe2\x9c\x85'  # check mark
  fi

  ESCAPED_PROJECT=$(escape_html "$PROJECT_NAME")
  ESCAPED_TIME=$(escape_html "$COMPLETED_AT")

  # 헤더
  MESSAGE="${STATUS_EMOJI} <b>Orchestrator 완료</b> | <code>${ESCAPED_PROJECT}</code>"

  # 작업 요약
  if [ -n "$PLAN_SUMMARY" ]; then
    ESCAPED_PLAN=$(escape_html "$PLAN_SUMMARY")
    MESSAGE="${MESSAGE}

"$'\xf0\x9f\x93\x8b'" <b>작업:</b> ${ESCAPED_PLAN}"
  fi

  # 변경 파일
  if [ "$FILE_COUNT" -gt 0 ]; then
    MESSAGE="${MESSAGE}

"$'\xf0\x9f\x93\x81'" <b>변경 파일 (${FILE_COUNT}개):</b>"

    # 최대 10개까지 표시
    DISPLAY_COUNT=10
    SHOWN=0
    while IFS= read -r fname; do
      if [ "$SHOWN" -ge "$DISPLAY_COUNT" ]; then
        REMAINING=$((FILE_COUNT - DISPLAY_COUNT))
        MESSAGE="${MESSAGE}
  ...외 ${REMAINING}개"
        break
      fi
      ESCAPED_FNAME=$(escape_html "$fname")
      MESSAGE="${MESSAGE}
  <code>${ESCAPED_FNAME}</code>"
      SHOWN=$((SHOWN + 1))
    done <<< "$FILES_CHANGED"
  fi

  # 리뷰 결과
  if [ -n "$REVIEW_VERDICTS" ]; then
    ESCAPED_REVIEW=$(escape_html "$REVIEW_VERDICTS")
    MESSAGE="${MESSAGE}

"$'\xf0\x9f\x94\x8d'" <b>리뷰:</b> ${ESCAPED_REVIEW}"
  fi

  # 미해결 이슈
  if has_issues; then
    ESCAPED_ISSUES=$(escape_html "$UNRESOLVED_ISSUES")
    MESSAGE="${MESSAGE}

"$'\xe2\x9a\xa0\xef\xb8\x8f'" <b>미해결:</b> ${ESCAPED_ISSUES}"
  else
    MESSAGE="${MESSAGE}

"$'\xe2\x9c\x85'" <b>미해결:</b> 없음"
  fi

  # 시각
  MESSAGE="${MESSAGE}

"$'\xf0\x9f\x95\x90'" <i>${ESCAPED_TIME}</i>"

else
  # --- Fallback: 비구조화 메시지 (HTML) ---
  ESCAPED_PROJECT=$(escape_html "$PROJECT_NAME")
  ESCAPED_TIME=$(escape_html "$COMPLETED_AT")

  if [ -f "$CONTEXT_FILE" ] && [ -s "$CONTEXT_FILE" ]; then
    FALLBACK_SUMMARY=$(head -c 500 "$CONTEXT_FILE" 2>/dev/null || echo "")
    ESCAPED_SUMMARY=$(escape_html "$FALLBACK_SUMMARY")

    MESSAGE=$'\xe2\x9c\x85'" <b>Orchestrator 완료</b> | <code>${ESCAPED_PROJECT}</code>

"$'\xf0\x9f\x95\x90'" <i>${ESCAPED_TIME}</i>

"$'\xf0\x9f\x93\x9d'" <b>요약:</b>
${ESCAPED_SUMMARY}"
  else
    MESSAGE=$'\xe2\x9c\x85'" <b>Orchestrator 완료</b> | <code>${ESCAPED_PROJECT}</code>

"$'\xf0\x9f\x95\x90'" <i>${ESCAPED_TIME}</i>

작업이 완료되었습니다."
  fi
fi

# 메시지 길이 제한 (Telegram 최대 4096자)
if [ ${#MESSAGE} -gt 4000 ]; then
  MESSAGE="${MESSAGE:0:3997}..."
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
    -d "parse_mode=HTML" \
    > /dev/null 2>&1 || true

  log "Notification sent (or failed silently)"
) &

exit 0
