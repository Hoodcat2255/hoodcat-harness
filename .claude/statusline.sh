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

# Git 정보
GIT_SECTION=""
if git -C "$CWD" rev-parse --git-dir > /dev/null 2>&1; then
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

    GIT_SECTION=" ${SEP} 🌿 ${CYAN}${BRANCH}${RESET} ${STATUS}"
fi

# 에이전트팀 활성 여부
TEAM_SECTION=""
if [ "$CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS" = "1" ]; then
    TEAM_SECTION=" ${SEP} 👥 ${GREEN}team${RESET}"
else
    TEAM_SECTION=" ${SEP} 👤 ${DIM}solo${RESET}"
fi

# 서브에이전트 실행 중
AGENT_SECTION=""
if [ -n "$AGENT" ]; then
    AGENT_SECTION=" 🏗️ ${MAGENTA}${AGENT}${RESET}"
fi

# 출력
printf '%b' "📁 ${BLUE}${DIR_NAME}${RESET}${GIT_SECTION} ${SEP} 📊 ${CTX_COLOR}${PCT}%%${RESET} ${SEP} 🤖 ${DIM}${MODEL}${RESET}${TEAM_SECTION}${AGENT_SECTION}\n"
