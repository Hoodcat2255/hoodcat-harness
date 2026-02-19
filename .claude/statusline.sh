#!/bin/bash
# hoodcat-harness statusline - Claude Code 하단 상태표시줄
# stdin으로 JSON 세션 데이터 수신 → stdout으로 표시
input=$(cat)

MODEL=$(echo "$input" | jq -r '.model.display_name // "—"')
CWD=$(echo "$input" | jq -r '.workspace.current_dir // empty')
[ -z "$CWD" ] && CWD=$(pwd)
PCT=$(echo "$input" | jq -r '.context_window.used_percentage // 0' | cut -d. -f1)
AGENT=$(echo "$input" | jq -r '.agent.name // empty')

# 색상
GREEN='\033[32m'
YELLOW='\033[33m'
RED='\033[31m'
CYAN='\033[36m'
BLUE='\033[34m'
MAGENTA='\033[35m'
DIM='\033[2m'
RESET='\033[0m'

SEP="${DIM}│${RESET}"

# 컨텍스트 사용량 색상 (임계값 기반)
if [ "$PCT" -ge 90 ]; then CTX_COLOR="$RED"
elif [ "$PCT" -ge 70 ]; then CTX_COLOR="$YELLOW"
else CTX_COLOR="$GREEN"; fi

# 디렉토리 (마지막 폴더명)
DIR_NAME="${CWD##*/}"
DIR_COLOR="${RESET}"

# Git 정보
GIT_SECTION=""
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
    DIR_COLOR="${GREEN}"
    BRANCH=$(git -C "$CWD" branch --show-current 2>/dev/null)
    [ -z "$BRANCH" ] && BRANCH=$(git -C "$CWD" rev-parse --short HEAD 2>/dev/null)
    STAGED=$(git -C "$CWD" diff --cached --numstat 2>/dev/null | wc -l | tr -d ' ')
    MODIFIED=$(git -C "$CWD" diff --numstat 2>/dev/null | wc -l | tr -d ' ')
    UNTRACKED=$(git -C "$CWD" ls-files --others --exclude-standard 2>/dev/null | wc -l | tr -d ' ')

    STATUS=""
    [ "$STAGED" -gt 0 ]   && STATUS="${GREEN}+${STAGED}${RESET}"
    [ "$MODIFIED" -gt 0 ]  && STATUS="${STATUS:+$STATUS }${YELLOW}~${MODIFIED}${RESET}"
    [ "$UNTRACKED" -gt 0 ] && STATUS="${STATUS:+$STATUS }${RED}?${UNTRACKED}${RESET}"
    [ -z "$STATUS" ] && STATUS="${GREEN}clean${RESET}"

    # 브랜치 색상: untracked→빨강, modified→노랑, staged only→초록, clean→초록
    BRANCH_COLOR="$GREEN"
    [ "$STAGED" -gt 0 ]    && BRANCH_COLOR="$GREEN"
    [ "$MODIFIED" -gt 0 ]  && BRANCH_COLOR="$YELLOW"
    [ "$UNTRACKED" -gt 0 ] && BRANCH_COLOR="$RED"

    GIT_SECTION=" ${SEP} ${RESET}🌿 ${BRANCH_COLOR}${BRANCH}${RESET} ${STATUS}"
fi

# ── OAuth 사용량 (5분 캐시) ──
USAGE_SECTION=""
CACHE_FILE="/tmp/claude-usage-cache.json"
CACHE_TTL=300  # 5분

get_token() {
    # macOS: Keychain 우선, fallback to credentials file
    if [ "$(uname)" = "Darwin" ]; then
        local keychain_json
        keychain_json=$(security find-generic-password -s "Claude Code-credentials" -w 2>/dev/null)
        if [ -n "$keychain_json" ]; then
            echo "$keychain_json" | jq -r '.claudeAiOauth.accessToken // empty' 2>/dev/null
            return
        fi
    fi
    # Linux / fallback: credentials file
    local creds="$HOME/.claude/.credentials.json"
    [ -f "$creds" ] && jq -r '.claudeAiOauth.accessToken // empty' "$creds" 2>/dev/null
}

fetch_usage() {
    local token
    token=$(get_token)
    [ -z "$token" ] && return 1
    curl -s --max-time 3 "https://api.anthropic.com/api/oauth/usage" \
        -H "Authorization: Bearer $token" \
        -H "Content-Type: application/json" \
        -H "anthropic-beta: oauth-2025-04-20" \
        > "$CACHE_FILE" 2>/dev/null
}

usage_color() {
    local val=$1
    if [ "$val" -ge 80 ]; then echo "$RED"
    elif [ "$val" -ge 50 ]; then echo "$YELLOW"
    else echo "$GREEN"; fi
}

# 캐시 갱신 (백그라운드, TTL 초과 시)
need_refresh=true
if [ -f "$CACHE_FILE" ]; then
    if [ "$(uname)" = "Darwin" ]; then
        age=$(( $(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || echo 0) ))
    else
        age=$(( $(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0) ))
    fi
    [ "$age" -lt "$CACHE_TTL" ] && need_refresh=false
fi
if $need_refresh; then
    fetch_usage &
fi

# 캐시에서 읽기 (7일 사용량만)
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    U7D=$(jq -r '.seven_day.utilization // empty' "$CACHE_FILE" 2>/dev/null | cut -d. -f1)
    if [ -n "$U7D" ]; then
        C7D=$(usage_color "$U7D")
        USAGE_SECTION=" ${SEP} \033[1mW${RESET} ${C7D}${U7D}%${RESET}"
    fi
fi

# 에이전트팀 활성 여부
TEAM_SECTION=""
if [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" ]; then
    TEAM_SECTION=" ${SEP} 👥 ${GREEN}team${RESET}"
else
    TEAM_SECTION=" ${SEP} 👤 ${DIM}solo${RESET}"
fi

# harness 모드 표시
HARNESS_MODE="on"  # 기본값
META_DIR="${CLAUDE_PROJECT_DIR:-$CWD}"
META_FILE="$META_DIR/.claude/.harness-meta.json"
if [ -f "$META_FILE" ]; then
    if command -v jq > /dev/null 2>&1; then
        MODE_VAL=$(jq -r '.mode // empty' "$META_FILE" 2>/dev/null)
    else
        # jq 없으면 grep fallback
        MODE_VAL=$(grep -o '"mode"[[:space:]]*:[[:space:]]*"[^"]*"' "$META_FILE" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)"$/\1/')
    fi
    [ -n "$MODE_VAL" ] && HARNESS_MODE="$MODE_VAL"
fi

HARNESS_SECTION=""
if [ "$HARNESS_MODE" = "off" ]; then
    HARNESS_SECTION=" ${SEP} ${RED}⚡ OFF${RESET}"
fi

# 서브에이전트 실행 중
AGENT_SECTION=""
if [ -n "$AGENT" ]; then
    AGENT_SECTION=" 🏗️ ${MAGENTA}${AGENT}${RESET}"
fi

# 출력 (줄 클리어 후 표시 - 이전 텍스트 잔여 방지)
echo -ne '\033[2K\r'
echo -e "📁 ${DIR_COLOR}${DIR_NAME}${RESET}${GIT_SECTION} ${SEP} 📊 ${CTX_COLOR}${PCT}%${RESET}${USAGE_SECTION} ${SEP} 🤖 ${DIM}${MODEL}${RESET}${TEAM_SECTION}${HARNESS_SECTION}${AGENT_SECTION}"
