#!/usr/bin/env bash
# hoodcat 개인 팩 설치: OMC(oh-my-claudecode)를 먼저 확인·설치한 뒤
# 개인 스킬·규칙·훅·스크립트를 전역(~/.claude, ~/.local/bin)에 설치하고,
# 전사 파이프라인(whisper/)을 ~/Projects/whisper에 동기화한다.
#
# 사용법: ./install.sh [-n|--dry-run] [--skip-omc] [--skip-whisper] [--skip-whisper-deps] [-h|--help]
#
# 설치 항목은 ~/.claude/.hoodcat-pack.json 매니페스트에 기록되고,
# uninstall.sh는 이 매니페스트에 적힌 항목만 제거한다 (전사 파이프라인 디렉토리는 남긴다).

set -euo pipefail

# ssh 원격 실행 같은 비로그인 셸에서는 Homebrew·사용자 bin이 PATH에 없어 uv·brew를 못 찾는다.
# 있는 디렉토리만 뒤에 덧붙여, 사용자가 정한 PATH 우선순위는 바꾸지 않는다.
# ~/.local/bin(uv 공식 설치 경로)을 먼저 둔다.
for _d in "${HOME}/.local/bin" /opt/homebrew/bin /usr/local/bin; do
    case ":${PATH}:" in
        *":${_d}:"*) ;;
        *) if [[ -d "$_d" ]]; then PATH="${PATH}:${_d}"; fi ;;
    esac
done
export PATH

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

OMC_MARKETPLACE_URL="https://github.com/Yeachan-Heo/oh-my-claudecode"
OMC_PLUGIN="oh-my-claudecode@omc"
OMC_NPM_PKG="oh-my-claude-sisyphus@latest"
SKIP_OMC=false
SKIP_WHISPER=false
SKIP_WHISPER_DEPS=false

usage() {
    sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        --skip-omc)   SKIP_OMC=true ;;
        --skip-whisper) SKIP_WHISPER=true ;;
        --skip-whisper-deps) SKIP_WHISPER_DEPS=true ;;
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
        localize_whisper_path "${CLAUDE_DIR}/skills/${name}/SKILL.md"
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
}

# 스킬 문서의 기본 파이프라인 경로를 HOODCAT_WHISPER_DIR로 바꾼다.
localize_whisper_path() {
    local f="$1" esc
    [[ "$WHISPER_DIR" != "$WHISPER_DEFAULT_DIR" && -f "$f" ]] || return 0
    grep -q '~/Projects/whisper' "$f" || return 0
    esc="$(printf '%s' "$WHISPER_DIR" | sed 's/[&|\\]/\\&/g')"
    run sh -c 'sed -e "s|cd ~/Projects/whisper |cd \"$1\" |g" -e "s|~/Projects/whisper|$1|g" "$2" > "$2.tmp" && mv "$2.tmp" "$2"' _ "$esc" "$f"
}

# --- 3. 전사 파이프라인 (youtube-digest·recording-notes 스킬) ---
# 코드만 동기화한다. 사용자 데이터(output/ 전사 결과, .venv, .omc, experiments/)와
# 설치본에서 생기는 개인 파일(.git, .claude, .env*, CLAUDE.md, AGENTS.md)은 건드리지 않는다.
WHISPER_INSTALLED=false

install_whisper_deps() {
    local os missing="" c
    os="$(uname -s)"
    for c in uv ffmpeg; do
        command -v "$c" &>/dev/null || missing="${missing} ${c}"
    done
    if [[ -n "$missing" ]]; then
        if [[ "$os" == Darwin ]] && command -v brew &>/dev/null; then
            log_info "brew install${missing}"
            # shellcheck disable=SC2086
            run brew install $missing || log_warn "brew install 실패:${missing}"
        else
            log_warn "전사 파이프라인에 필요한 명령이 없습니다:${missing}"
            log_warn "  uv: curl -LsSf https://astral.sh/uv/install.sh | sh / ffmpeg: sudo apt install ffmpeg"
        fi
    fi

    # macOS는 GUI 로그인 없이(SSH 등) 데스크톱 Chrome이 headless로도 뜨지 않아 PDF용으로 따로 둔다.
    if [[ "$os" == Darwin ]] && ! ls "$HOME"/.cache/chrome-headless-shell/chrome-headless-shell/*/*/chrome-headless-shell &>/dev/null; then
        if command -v npx &>/dev/null; then
            log_info "chrome-headless-shell 설치 (--pdf용)"
            run npx -y @puppeteer/browsers install chrome-headless-shell@stable --path "$HOME/.cache/chrome-headless-shell" \
                || log_warn "chrome-headless-shell 설치 실패. --pdf는 실패할 수 있습니다."
        else
            log_warn "npx가 없어 chrome-headless-shell을 설치하지 못했습니다. --pdf는 실패할 수 있습니다."
        fi
    fi
}

install_whisper() {
    require_cmd rsync "brew install rsync / sudo apt install rsync"
    # --delete로 동기화하므로 whisper 사본이 아닌 기존 디렉토리는 건드리지 않는다.
    if [[ -d "$WHISPER_DIR" && ! -f "${WHISPER_DIR}/transcribe.py" ]] && [[ -n "$(ls -A "$WHISPER_DIR")" ]]; then
        log_warn "전사 파이프라인 경로에 다른 파일이 있어 건너뜁니다: ${WHISPER_DIR} (스킬은 이 경로를 가리킵니다. HOODCAT_WHISPER_DIR로 바꿀 수 있음)"
        return 0
    fi
    [[ "$SKIP_WHISPER_DEPS" == true ]] || install_whisper_deps

    run mkdir -p "$WHISPER_DIR"
    run rsync -a --delete \
        --exclude /output --exclude /.venv --exclude /.omc --exclude /experiments \
        --exclude /.git --exclude /.claude --exclude '/.env*' --exclude /CLAUDE.md --exclude /AGENTS.md \
        --exclude __pycache__ --exclude .pytest_cache \
        "${REPO_DIR}/whisper/" "${WHISPER_DIR}/"
    WHISPER_INSTALLED=true
    log_ok "전사 파이프라인: ${WHISPER_DIR}"

    if [[ "$SKIP_WHISPER_DEPS" == true ]]; then
        return 0
    elif command -v uv &>/dev/null; then
        log_info "uv sync (${WHISPER_DIR})"
        run uv --directory "$WHISPER_DIR" sync \
            || log_warn "uv sync 실패. ${WHISPER_DIR}에서 uv sync를 다시 실행하세요."
    else
        log_warn "uv가 없어 의존성을 설치하지 못했습니다. uv 설치 후 ${WHISPER_DIR}에서 uv sync를 실행하세요."
    fi
}

write_manifest() {
    local commit whisper=""
    [[ "$WHISPER_INSTALLED" == true ]] && whisper="$WHISPER_DIR"
    commit="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
    if [[ "$DRY_RUN" == true ]]; then
        echo "  (dry-run) 매니페스트 기록: ${MANIFEST_FILE} (${#INSTALLED_PATHS[@]}개 경로, ${#INSTALLED_HOOKS[@]}개 훅)"
        return 0
    fi
    jq -n \
        --arg repo "$REPO_DIR" --arg commit "$commit" --arg at "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
        --arg whisper "$whisper" \
        --args '{repo: $repo, commit: $commit, installed_at: $at,
                 paths: ($ARGS.positional | map(select(startswith("P:")) | .[2:])),
                 hooks: ($ARGS.positional | map(select(startswith("H:")) | .[2:]))}
                + (if $whisper == "" then {} else {whisper_dir: $whisper} end)' \
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
# 파이프라인 단계가 중간에 실패해도 설치한 스킬·훅이 매니페스트에 남도록 먼저 기록한다.
write_manifest
if [[ "$SKIP_WHISPER" == true ]]; then
    log_info "전사 파이프라인 단계 생략 (--skip-whisper)"
else
    install_whisper
    [[ "$WHISPER_INSTALLED" == true ]] && write_manifest
fi
log_ok "설치 완료. 새 Claude Code 세션부터 적용됩니다."
