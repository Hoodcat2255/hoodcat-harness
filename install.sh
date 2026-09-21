#!/usr/bin/env bash
# hoodcat 개인 팩 설치: OMC(oh-my-claudecode)를 먼저 확인·설치한 뒤
# 개인 스킬·규칙·훅·스크립트를 전역(~/.claude, ~/.local/bin)에 설치한다.
#
# 사용법: ./install.sh [-n|--dry-run] [--skip-omc] [-h|--help]
#
# 설치 항목은 ~/.claude/.hoodcat-pack.json 매니페스트에 기록되고,
# uninstall.sh는 이 매니페스트에 적힌 항목만 제거한다.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

OMC_MARKETPLACE_URL="https://github.com/Yeachan-Heo/oh-my-claudecode"
OMC_PLUGIN="oh-my-claudecode@omc"
OMC_NPM_PKG="oh-my-claude-sisyphus@latest"
SKIP_OMC=false

usage() {
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        --skip-omc)   SKIP_OMC=true ;;
        -h|--help)    usage ;;
        *) die "알 수 없는 옵션: $1" ;;
    esac
    shift
done

# --- 1. OMC ---
# 공식 절차 (OMC README Quick Start): 마켓플레이스 추가 → 플러그인 설치 →
# npm CLI(oh-my-claude-sisyphus) → omc setup
install_omc() {
    require_cmd claude "Claude Code를 먼저 설치하세요."
    local changed=false

    if claude plugin list --json 2>/dev/null | jq -e --arg id "$OMC_PLUGIN" 'any(.[]; .id == $id)' &>/dev/null; then
        log_ok "OMC 플러그인 설치됨 (${OMC_PLUGIN})"
    else
        if ! claude plugin marketplace list 2>/dev/null | grep -q 'oh-my-claudecode'; then
            log_info "OMC 마켓플레이스 추가"
            run claude plugin marketplace add "$OMC_MARKETPLACE_URL"
        fi
        log_info "OMC 플러그인 설치 (user scope)"
        run claude plugin install "$OMC_PLUGIN" --scope user
        changed=true
    fi

    if command -v omc &>/dev/null; then
        log_ok "omc CLI 설치됨 ($(omc --version 2>/dev/null || echo '?'))"
    else
        require_cmd npm "Node.js(npm)가 필요합니다."
        log_info "omc CLI 설치 (npm i -g ${OMC_NPM_PKG})"
        run npm i -g "$OMC_NPM_PKG"
        changed=true
    fi

    if [[ "$changed" == true ]]; then
        log_info "omc setup 실행"
        run omc setup
    fi
}

# --- 2. 개인 팩 ---
# 설치된 경로·훅 명령을 모아 마지막에 매니페스트로 기록한다.
INSTALLED_PATHS=()
INSTALLED_HOOKS=()

manifest_has() {
    [[ -f "$MANIFEST_FILE" ]] && jq -e --arg p "$1" 'any(.paths[]?; . == $p)' "$MANIFEST_FILE" &>/dev/null
}

# place <src> <dst>: 내 소유가 아닌 기존 파일은 백업 후 덮어쓴다.
place() {
    local src="$1" dst="$2"
    if [[ -e "$dst" ]] && ! manifest_has "$dst"; then
        local backup="${BACKUP_ROOT}/$(date +%Y%m%d-%H%M%S)${dst#"$HOME"}"
        log_warn "기존 파일을 백업하고 덮어씁니다: ${dst} → ${backup}"
        run mkdir -p "$(dirname "$backup")"
        run mv "$dst" "$backup"
    fi
    run mkdir -p "$(dirname "$dst")"
    run rm -rf "$dst"
    run cp -R "$src" "$dst"
    INSTALLED_PATHS+=("$dst")
}

install_pack() {
    require_cmd jq "brew install jq"
    run mkdir -p "$CLAUDE_DIR"

    # 이전 설치 중 이번 버전에 없는 항목은 먼저 정리한다 (재설치 = 동기화).
    if [[ -f "$MANIFEST_FILE" ]]; then
        log_info "이전 설치 정리"
        run "${REPO_DIR}/uninstall.sh" --quiet $([[ "$DRY_RUN" == true ]] && echo --dry-run)
    fi

    local d f name
    for d in "${REPO_DIR}"/skills/*/; do
        name="$(basename "$d")"
        place "$d" "${CLAUDE_DIR}/skills/${name}"
        log_ok "스킬: ${name}"
    done

    for f in "${REPO_DIR}"/rules/*.md; do
        place "$f" "${CLAUDE_DIR}/${RULES_NS}/$(basename "$f")"
    done
    log_ok "규칙: ${CLAUDE_DIR}/${RULES_NS}/"

    backup_settings
    local event script matcher dst
    while IFS=$'\t' read -r event script matcher; do
        dst="${CLAUDE_DIR}/${HOOKS_NS}/${script}"
        place "${REPO_DIR}/hooks/${script}" "$dst"
        run chmod +x "$dst"
        settings_add_hook "$event" "$dst" "$matcher"
        INSTALLED_HOOKS+=("$dst")
        log_ok "훅: ${event} → ${script}"
    done < <(jq -r '.[] | [.event, .script, (.matcher // "")] | @tsv' "${REPO_DIR}/hooks/hooks.json")

    for f in "${REPO_DIR}"/scripts/*; do
        [[ -f "$f" ]] || continue
        place "$f" "${BIN_DIR}/$(basename "$f")"
        run chmod +x "${BIN_DIR}/$(basename "$f")"
        log_ok "스크립트: $(basename "$f")"
    done

    write_manifest
}

write_manifest() {
    local commit
    commit="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [[ "$DRY_RUN" == true ]]; then
        echo "  (dry-run) 매니페스트 기록: ${MANIFEST_FILE} (${#INSTALLED_PATHS[@]}개 경로, ${#INSTALLED_HOOKS[@]}개 훅)"
        return 0
    fi
    jq -n \
        --arg repo "$REPO_DIR" --arg commit "$commit" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --args '{repo: $repo, commit: $commit, installed_at: $at,
                 paths: ($ARGS.positional | map(select(startswith("P:")) | .[2:])),
                 hooks: ($ARGS.positional | map(select(startswith("H:")) | .[2:]))}' \
        ${INSTALLED_PATHS[@]+"${INSTALLED_PATHS[@]/#/P:}"} \
        ${INSTALLED_HOOKS[@]+"${INSTALLED_HOOKS[@]/#/H:}"} > "$MANIFEST_FILE"
    log_ok "매니페스트: ${MANIFEST_FILE}"
}

[[ "$DRY_RUN" == true ]] && log_warn "dry-run 모드: 실제 변경 없음"
if [[ "$SKIP_OMC" == true ]]; then
    log_info "OMC 단계 생략 (--skip-omc)"
else
    install_omc
fi
install_pack
log_ok "설치 완료. 새 Claude Code 세션부터 적용됩니다."
