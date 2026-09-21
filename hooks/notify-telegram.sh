#!/usr/bin/env bash
# SubagentStop Hook - notify-telegram.sh
# 서브에이전트가 끝나면 텔레그램으로 완료 알림을 보낸다.
# 입력(stdin JSON): cwd, agent_type, last_assistant_message (Claude Code hooks 문서 SubagentStop 절)
# 설정: HARNESS_TG_BOT_TOKEN, HARNESS_TG_CHAT_ID
#   ~/.claude/.env → <프로젝트>/.env 순으로 읽고, 뒤가 앞을 덮어쓴다. 없으면 조용히 종료.
# 안전성: 어떤 경우에도 exit 0 (세션을 막지 않는다).

set -uo pipefail

command -v jq &>/dev/null || exit 0
command -v curl &>/dev/null || exit 0

INPUT="$(cat)"
field() { jq -r --arg k "$1" '.[$k] // ""' <<<"$INPUT" 2>/dev/null; }

CWD="$(field cwd)"
AGENT_TYPE="$(field agent_type)"
LAST_MESSAGE="$(field last_assistant_message)"

# .env에서 HARNESS_TG_* 키만 읽는다 (다른 비밀값은 export하지 않는다).
load_tg_env() {
    local file="$1" key value
    [[ -f "$file" ]] || return 0
    while IFS='=' read -r key value || [[ -n "$key" ]]; do
        case "$key" in
            HARNESS_TG_BOT_TOKEN|HARNESS_TG_CHAT_ID)
                value="${value%\"}"; value="${value#\"}"
                export "$key=$value" ;;
        esac
    done < "$file"
}

load_tg_env "${CLAUDE_CONFIG_DIR:-$HOME/.claude}/.env"
[[ -n "$CWD" ]] && load_tg_env "${CWD}/.env"

[[ -n "${HARNESS_TG_BOT_TOKEN:-}" && -n "${HARNESS_TG_CHAT_ID:-}" ]] || exit 0

escape_html() {
    sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
}

# 텔레그램 HTML 모드에서 원시 마크다운이 보이지 않도록 흔한 문법만 걷어낸다.
strip_markdown() {
    sed -e 's/^#\{1,6\} //' \
        -e 's/\*\*\([^*]*\)\*\*/\1/g' \
        -e '/^```/d' \
        -e 's/`\([^`]*\)`/\1/g' \
        -e 's/^> //'
}

PROJECT_NAME="$(basename "${CWD:-unknown}")"
AGENT_NAME="${AGENT_TYPE:-subagent}"
COMPLETED_AT="$(TZ="Asia/Seoul" date +"%Y-%m-%d %H:%M KST")"

MESSAGE="⚙️ <b>$(escape_html <<<"$AGENT_NAME") 완료</b> | <code>$(escape_html <<<"$PROJECT_NAME")</code>

🕐 <i>${COMPLETED_AT}</i>"

if [[ -n "$LAST_MESSAGE" ]]; then
    SUMMARY="$(head -c 600 <<<"$LAST_MESSAGE" | strip_markdown | escape_html)"
    MESSAGE="${MESSAGE}

📝 <b>요약:</b>
${SUMMARY}"
fi

# 텔레그램 메시지 최대 4096자
(( ${#MESSAGE} > 4000 )) && MESSAGE="${MESSAGE:0:3997}..."

# 훅이 세션을 붙잡지 않도록 백그라운드로 보내고 바로 끝낸다.
(
    curl -s -X POST --connect-timeout 5 --max-time 5 \
        "https://api.telegram.org/bot${HARNESS_TG_BOT_TOKEN}/sendMessage" \
        --data-urlencode "chat_id=${HARNESS_TG_CHAT_ID}" \
        --data-urlencode "text=${MESSAGE}" \
        -d "parse_mode=HTML" >/dev/null 2>&1 || true
) &

exit 0
