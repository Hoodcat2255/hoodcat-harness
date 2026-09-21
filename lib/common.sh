#!/usr/bin/env bash
# install.sh / uninstall.sh 공용 헬퍼. 직접 실행하지 않고 source한다.

# --- 경로 ---
# CLAUDE_CONFIG_DIR를 존중한다 (테스트에서 임시 디렉토리로 바꿔 쓴다).
CLAUDE_DIR="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
BIN_DIR="${HOODCAT_BIN_DIR:-$HOME/.local/bin}"
SETTINGS_FILE="${CLAUDE_DIR}/settings.json"
MANIFEST_FILE="${CLAUDE_DIR}/.hoodcat-pack.json"
BACKUP_ROOT="${CLAUDE_DIR}/.hoodcat-pack-backup"

# 이 저장소가 소유하는 네임스페이스 (rules·hooks는 하위 디렉토리로 격리)
RULES_NS="rules/hoodcat"
HOOKS_NS="hooks/hoodcat"

DRY_RUN=false

# --- 로그 ---
if [[ -t 1 ]]; then
    RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[0;33m'; BLUE=$'\033[0;34m'; NC=$'\033[0m'
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; NC=""
fi

log_info()  { echo "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo "${GREEN}[ OK ]${NC} $*"; }
log_warn()  { echo "${YELLOW}[WARN]${NC} $*" >&2; }
die()       { echo "${RED}[FAIL]${NC} $*" >&2; exit 1; }

# 변경 작업은 모두 run으로 감싼다. dry-run이면 출력만 한다.
run() {
    if [[ "$DRY_RUN" == true ]]; then
        echo "  (dry-run) $*"
    else
        "$@"
    fi
}

require_cmd() {
    command -v "$1" &>/dev/null || die "'$1' 명령이 필요합니다. $2"
}

# --- settings.json 훅 등록/해제 (jq) ---

# settings_add_hook <event> <command> [matcher]
# 같은 command가 이미 등록돼 있으면 추가하지 않는다.
settings_add_hook() {
    local event="$1" cmd="$2" matcher="${3:-}"
    [[ -f "$SETTINGS_FILE" ]] || run sh -c "echo '{}' > \"$SETTINGS_FILE\""
    [[ "$DRY_RUN" == true ]] && { echo "  (dry-run) settings.json hooks.${event} += ${cmd}"; return 0; }

    local tmp
    tmp="$(mktemp)"
    jq --arg ev "$event" --arg cmd "$cmd" --arg m "$matcher" '
        .hooks //= {}
        | .hooks[$ev] //= []
        | if any(.hooks[$ev][]?.hooks[]?; .command == $cmd) then .
          else .hooks[$ev] += [
              ({hooks: [{type: "command", command: $cmd}]}
               + (if $m == "" then {} else {matcher: $m} end))
          ] end
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
}

# settings_remove_hook <command>
# 모든 이벤트에서 해당 command를 제거하고, 비게 된 항목·이벤트·hooks 키를 정리한다.
settings_remove_hook() {
    local cmd="$1"
    [[ -f "$SETTINGS_FILE" ]] || return 0
    [[ "$DRY_RUN" == true ]] && { echo "  (dry-run) settings.json에서 훅 제거: ${cmd}"; return 0; }

    local tmp
    tmp="$(mktemp)"
    jq --arg cmd "$cmd" '
        if .hooks then
            .hooks |= (
                with_entries(
                    .value |= (map(.hooks |= map(select(.command != $cmd)))
                               | map(select((.hooks | length) > 0)))
                )
                | with_entries(select((.value | length) > 0))
            )
            | if (.hooks | length) == 0 then del(.hooks) else . end
        else . end
    ' "$SETTINGS_FILE" > "$tmp" && mv "$tmp" "$SETTINGS_FILE"
}

backup_settings() {
    [[ -f "$SETTINGS_FILE" ]] || return 0
    run cp "$SETTINGS_FILE" "${SETTINGS_FILE}.hoodcat-bak"
}
