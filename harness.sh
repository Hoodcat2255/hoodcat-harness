#!/usr/bin/env bash
set -euo pipefail

# harness.sh - hoodcat-harness 멀티에이전트 시스템 설치/관리 스크립트
# 사용법: ./harness.sh <command> <target-dir> [options]

_resolve_path() {
    local src="${BASH_SOURCE[0]}"
    while [[ -L "$src" ]]; do
        local dir
        dir="$(cd -P "$(dirname "$src")" && pwd -P)"
        src="$(readlink "$src")"
        [[ "$src" != /* ]] && src="$dir/$src"
    done
    cd -P "$(dirname "$src")" && pwd -P
}
readonly SCRIPT_DIR="$(_resolve_path)"
readonly SOURCE_CLAUDE_DIR="${SCRIPT_DIR}/.claude"
readonly META_FILE=".claude/.harness-meta.json"

# 복사 대상 디렉토리 (템플릿)
readonly TEMPLATE_DIRS=(agents skills rules hooks)

# .gitignore에 추가할 항목
readonly GITIGNORE_ENTRIES=(
    "# hoodcat-harness"
    ".claude/"
)

# 옵션 기본값
FORCE=false
DRY_RUN=false
VERBOSE=false

# 색상
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# --- 유틸리티 ---

log_info()  { echo -e "${GREEN}[INFO]${NC} $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }
log_debug() { $VERBOSE && echo -e "${BLUE}[DEBUG]${NC} $*" || true; }
die()       { log_error "$*"; exit 1; }

confirm() {
    if $FORCE; then return 0; fi
    local prompt="${1:-계속하시겠습니까?}"
    echo -en "${YELLOW}${prompt} [Y/n] ${NC}"
    read -r answer
    [[ ! "$answer" =~ ^[Nn]$ ]]
}

dry_run_guard() {
    if $DRY_RUN; then
        log_info "[DRY-RUN] $*"
        return 1
    fi
    return 0
}

get_source_commit() {
    if command -v git &>/dev/null && git -C "$SCRIPT_DIR" rev-parse HEAD &>/dev/null 2>&1; then
        git -C "$SCRIPT_DIR" rev-parse --short HEAD
    else
        echo "unknown"
    fi
}

get_timestamp() {
    # POSIX-compatible ISO 8601 format (macOS date lacks -Iseconds)
    date -u +"%Y-%m-%dT%H:%M:%S+00:00"
}

check_dependencies() {
    if ! command -v rsync &>/dev/null; then
        die "rsync가 필요합니다. 'sudo apt install rsync' 또는 'brew install rsync'로 설치하세요."
    fi
}

validate_target() {
    local target="$1"
    [[ -d "$target" ]] || die "대상 디렉토리가 존재하지 않습니다: $target"
    [[ -w "$target" ]] || die "대상 디렉토리에 쓰기 권한이 없습니다: $target"
}

# --- 핵심 함수 ---

copy_template_files() {
    local target="$1"
    local delete_flag="${2:-}"  # "--delete" for update

    for dir in "${TEMPLATE_DIRS[@]}"; do
        local src="${SOURCE_CLAUDE_DIR}/${dir}/"
        local dst="${target}/.claude/${dir}/"

        if [[ ! -d "$src" ]]; then
            log_debug "소스 디렉토리 없음, 스킵: $src"
            continue
        fi

        if dry_run_guard "rsync ${delete_flag} ${src} → ${dst}"; then
            mkdir -p "$dst"
            if [[ -n "$delete_flag" ]]; then
                rsync -a --delete "$src" "$dst"
            else
                rsync -a "$src" "$dst"
            fi
            log_debug "복사 완료: ${dir}/"
        fi
    done
}

init_runtime_dirs() {
    local target="$1"
    if dry_run_guard "런타임 디렉토리 생성"; then
        mkdir -p "${target}/.claude/log"
        log_debug "런타임 디렉토리 생성 완료"
    fi
}

merge_settings_json() {
    local src="$1"  # harness (우선)
    local dst="$2"  # 기존
    if ! command -v jq &>/dev/null; then
        return 1
    fi
    jq -s '.[0] * .[1]' "$dst" "$src"
}

unmerge_settings_json() {
    local target="$1"
    local dst="${target}/.claude/settings.json"
    local src="${SOURCE_CLAUDE_DIR}/settings.json"

    [[ -f "$dst" ]] || return 0

    if command -v jq &>/dev/null && [[ -f "$src" ]]; then
        # harness 소스의 top-level 키 목록을 동적으로 추출하여 제거
        local keys
        keys=$(jq -r 'keys[]' "$src" | paste -sd ',' -)
        local del_expr
        del_expr=$(jq -r '[keys[] | "del(.\(.))"] | join(" | ")' "$src")

        if dry_run_guard "settings.json에서 harness 키 제거"; then
            local result
            result=$(jq "${del_expr}" "$dst")
            if [[ "$result" == "{}" ]]; then
                rm -f "$dst"
                log_info "settings.json 삭제 완료 (harness 키만 있었음)"
            else
                echo "$result" > "$dst"
                log_info "settings.json에서 harness 키(${keys}) 제거 완료"
            fi
        fi
    else
        # jq가 없으면 프로젝트 루트에 백업 후 삭제
        if dry_run_guard "settings.json 백업 후 삭제 (jq 미설치)"; then
            local backup_name="settings.json.bak.$(date +%Y%m%d%H%M%S)"
            cp "$dst" "${target}/${backup_name}"
            rm -f "$dst"
            log_warn "settings.json을 프로젝트 루트에 백업했습니다: ${backup_name}"
            log_warn "jq가 있으면 harness 키만 선택적으로 제거할 수 있습니다."
        fi
    fi
}

copy_settings() {
    local target="$1"
    local mode="${2:-install}"  # install or update
    local src="${SOURCE_CLAUDE_DIR}/settings.json"
    local dst="${target}/.claude/settings.json"

    if [[ ! -f "$src" ]]; then
        log_warn "소스 settings.json이 없습니다."
        return
    fi

    if [[ "$mode" == "update" && -f "$dst" ]]; then
        if diff -q "$src" "$dst" &>/dev/null; then
            log_info "settings.json: 변경 없음"
            return
        fi

        echo ""
        log_warn "settings.json에 변경이 있습니다:"
        # macOS diff lacks --color; fall back to plain diff
        if diff --help 2>&1 | grep -q -- '--color'; then
            diff --color=auto "$src" "$dst" || true
        else
            diff "$src" "$dst" || true
        fi
        echo ""

        if confirm "settings.json을 덮어쓰시겠습니까?"; then
            if dry_run_guard "settings.json 업데이트"; then
                local merged
                if merged=$(merge_settings_json "$src" "$dst"); then
                    echo "$merged" > "$dst"
                    log_info "settings.json 머지 완료 (harness 설정 우선 적용)"
                else
                    log_warn "jq가 없어 머지 불가. 백업 후 덮어씁니다."
                    cp "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)"
                    cp "$src" "$dst"
                    log_info "settings.json 덮어쓰기 완료 (백업 생성됨)"
                fi
            fi
        else
            log_info "settings.json 보존"
        fi
    else
        if dry_run_guard "settings.json 복사"; then
            if [[ -f "$dst" ]]; then
                local merged
                if merged=$(merge_settings_json "$src" "$dst"); then
                    echo "$merged" > "$dst"
                    log_debug "settings.json 머지 완료 (기존 설정 보존)"
                else
                    log_warn "jq가 없어 머지 불가. 백업 후 덮어씁니다."
                    cp "$dst" "${dst}.bak.$(date +%Y%m%d%H%M%S)"
                    cp "$src" "$dst"
                    log_debug "settings.json 복사 완료 (백업 생성됨)"
                fi
            else
                cp "$src" "$dst"
                log_debug "settings.json 복사 완료"
            fi
        fi
    fi
}

copy_statusline() {
    local target="$1"
    local src="${SOURCE_CLAUDE_DIR}/statusline.sh"
    local dst="${target}/.claude/statusline.sh"

    if [[ ! -f "$src" ]]; then
        log_debug "소스 statusline.sh가 없습니다."
        return
    fi

    if dry_run_guard "statusline.sh 복사"; then
        cp "$src" "$dst"
        chmod +x "$dst"
        log_debug "statusline.sh 복사 및 실행 권한 설정 완료"
    fi
}

copy_harness_md() {
    local target="$1"
    local src="${SOURCE_CLAUDE_DIR}/harness.md"
    local dst="${target}/.claude/harness.md"

    if [[ ! -f "$src" ]]; then
        log_debug "소스 harness.md가 없습니다."
        return
    fi

    if dry_run_guard "harness.md 복사"; then
        cp "$src" "$dst"
        log_debug "harness.md 복사 완료"
    fi
}

copy_shared_context_config() {
    local target="$1"
    local src="${SOURCE_CLAUDE_DIR}/shared-context-config.json"
    local dst="${target}/.claude/shared-context-config.json"

    if [[ ! -f "$src" ]]; then
        log_debug "소스 shared-context-config.json이 없습니다."
        return
    fi

    if dry_run_guard "shared-context-config.json 복사"; then
        cp "$src" "$dst"
        log_debug "shared-context-config.json 복사 완료"
    fi
}

check_global_env() {
    local global_env="$HOME/.claude/.env"

    # ~/.claude/ 디렉토리가 없을 수 있으므로 생성
    mkdir -p "$HOME/.claude"

    # .env 파일이 없으면 빈 파일 생성
    if [[ ! -f "$global_env" ]]; then
        if dry_run_guard "~/.claude/.env 생성"; then
            touch "$global_env"
            log_info "~/.claude/.env 파일을 생성했습니다."
        fi
    fi

    # 기존 값 로드 (POSIX grep 호환)
    local current_token="" current_chat_id=""
    if [[ -f "$global_env" ]]; then
        current_token="$(grep '^HARNESS_TG_BOT_TOKEN=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_BOT_TOKEN=//' || true)"
        current_chat_id="$(grep '^HARNESS_TG_CHAT_ID=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_CHAT_ID=//' || true)"
    fi

    # placeholder 판별 함수
    _is_empty_or_placeholder() {
        local val="$1"
        [[ -z "$val" ]] && return 0
        [[ "$val" == "your_bot_token_here" ]] && return 0
        [[ "$val" == "your_chat_id_here" ]] && return 0
        return 1
    }

    local needs_token=false needs_chat_id=false
    _is_empty_or_placeholder "$current_token" && needs_token=true
    _is_empty_or_placeholder "$current_chat_id" && needs_chat_id=true

    # 이미 유효한 값이 설정되어 있으면 완료
    if ! $needs_token && ! $needs_chat_id; then
        log_info "전역 환경변수 확인: ~/.claude/.env (설정 완료)"
        return
    fi

    # FORCE 모드이면 프롬프트 스킵
    if $FORCE; then
        log_warn "텔레그램 알림 환경변수가 미설정 상태입니다. ~/.claude/.env를 직접 편집하세요."
        return
    fi

    # 비대화형 환경이면 프롬프트 스킵
    if [[ ! -t 0 ]]; then
        log_warn "비대화형 환경입니다. 텔레그램 알림 환경변수를 ~/.claude/.env에 직접 설정하세요."
        return
    fi

    # 대화형 프롬프트
    echo ""
    log_info "텔레그램 알림 설정 (빈 Enter로 스킵 가능)"
    echo ""

    # .env 파일에 변수를 설정하는 헬퍼 (macOS/Linux sed 호환)
    _set_env_var() {
        local var_name="$1" var_value="$2" env_file="$3"
        if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
            local tmp
            tmp="$(mktemp)"
            sed "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file" > "$tmp"
            mv "$tmp" "$env_file"
        else
            echo "${var_name}=${var_value}" >> "$env_file"
        fi
    }

    if $needs_token; then
        echo -e "  ${BLUE}Bot token은 Telegram @BotFather에서 발급받을 수 있습니다.${NC}"
        echo -n "  HARNESS_TG_BOT_TOKEN: "
        read -r input_token
        if [[ -n "$input_token" ]]; then
            if dry_run_guard "HARNESS_TG_BOT_TOKEN 설정"; then
                _set_env_var "HARNESS_TG_BOT_TOKEN" "$input_token" "$global_env"
                log_info "HARNESS_TG_BOT_TOKEN 설정 완료"
            fi
        else
            log_info "HARNESS_TG_BOT_TOKEN: 나중에 설정하겠습니다."
        fi
    fi

    if $needs_chat_id; then
        echo -e "  ${BLUE}Chat ID는 @userinfobot 또는 @getmyid_bot에서 확인할 수 있습니다.${NC}"
        echo -n "  HARNESS_TG_CHAT_ID: "
        read -r input_chat_id
        if [[ -n "$input_chat_id" ]]; then
            if dry_run_guard "HARNESS_TG_CHAT_ID 설정"; then
                _set_env_var "HARNESS_TG_CHAT_ID" "$input_chat_id" "$global_env"
                log_info "HARNESS_TG_CHAT_ID 설정 완료"
            fi
        else
            log_info "HARNESS_TG_CHAT_ID: 나중에 설정하겠습니다."
        fi
    fi

    echo ""
}

inject_harness_import() {
    local target="$1"
    local claude_md="${target}/CLAUDE.md"
    local import_line="@.claude/harness.md"

    # CLAUDE.md가 없으면 생성
    if [[ ! -f "$claude_md" ]]; then
        if dry_run_guard "CLAUDE.md 생성"; then
            local project_name
            project_name="$(basename "$target")"
            cat > "$claude_md" << EOF
${import_line}

# CLAUDE.md

This file provides guidance to Claude Code when working with code in this repository.

## 프로젝트 개요

${project_name} 프로젝트입니다.
EOF
            log_info "CLAUDE.md를 생성했습니다. 프로젝트에 맞게 수정하세요."
        fi
        return
    fi

    # 이미 최상단에 있으면 스킵
    if head -1 "$claude_md" | grep -qF "$import_line" 2>/dev/null; then
        log_debug "CLAUDE.md 최상단에 harness.md import가 이미 존재합니다."
        return
    fi

    # 하단에 기존 import가 있으면 제거 (마이그레이션)
    if grep -qF "$import_line" "$claude_md" 2>/dev/null; then
        if dry_run_guard "CLAUDE.md에서 기존 harness import를 최상단으로 이동"; then
            local tmp
            tmp="$(mktemp)"
            # 기존 import 블록 제거 (섹션 헤더 + import 줄 + 전후 빈 줄)
            sed '/^## hoodcat-harness 공통 지침$/d' "$claude_md" \
                | sed "/^${import_line//\//\\/}$/d" \
                | sed -e :a -e '/^\n*$/{$d;N;ba}' > "$tmp"
            # 최상단에 삽입
            local tmp2
            tmp2="$(mktemp)"
            {
                echo "$import_line"
                echo ""
                cat "$tmp"
            } > "$tmp2"
            mv "$tmp2" "$claude_md"
            rm -f "$tmp"
            log_info "CLAUDE.md에서 harness import를 최상단으로 이동했습니다."
        fi
        return
    fi

    # 신규 삽입
    if dry_run_guard "CLAUDE.md에 harness.md import 추가 (최상단)"; then
        local tmp
        tmp="$(mktemp)"
        {
            echo "$import_line"
            echo ""
            cat "$claude_md"
        } > "$tmp"
        mv "$tmp" "$claude_md"
        log_info "CLAUDE.md 최상단에 harness.md import를 추가했습니다."
    fi
}

remove_harness_import() {
    local target="$1"
    local claude_md="${target}/CLAUDE.md"
    local import_line="@.claude/harness.md"

    [[ -f "$claude_md" ]] || return 0

    if ! grep -qF "$import_line" "$claude_md" 2>/dev/null; then
        log_debug "CLAUDE.md에 harness import가 없습니다."
        return 0
    fi

    if dry_run_guard "CLAUDE.md에서 harness import 제거"; then
        local tmp
        tmp="$(mktemp)"
        # import 줄 제거
        grep -vF "$import_line" "$claude_md" > "$tmp"
        # 파일 시작 부분의 연속 빈 줄 정리
        sed '/./,$!d' "$tmp" > "${tmp}.2"
        # 연속 빈 줄을 하나로 압축
        cat -s "${tmp}.2" > "$claude_md"
        rm -f "$tmp" "${tmp}.2"
        log_info "CLAUDE.md에서 harness import를 제거했습니다."
    fi
}

write_harness_meta() {
    local target="$1"
    local mode="${2:-install}"
    local meta_path="${target}/${META_FILE}"
    local commit
    commit="$(get_source_commit)"
    local now
    now="$(get_timestamp)"

    if dry_run_guard ".harness-meta.json 작성"; then
        mkdir -p "$(dirname "$meta_path")"
        if [[ "$mode" == "update" && -f "$meta_path" ]]; then
            # installed_at 보존, updated_at + source 갱신
            local installed_at
            installed_at="$(grep -o '"installed_at": *"[^"]*"' "$meta_path" | head -1 | sed 's/.*: *"//;s/"$//')"
            cat > "$meta_path" << EOF
{
  "installed_at": "${installed_at}",
  "updated_at": "${now}",
  "source_commit": "${commit}",
  "source_path": "${SCRIPT_DIR}"
}
EOF
        else
            cat > "$meta_path" << EOF
{
  "installed_at": "${now}",
  "updated_at": "${now}",
  "source_commit": "${commit}",
  "source_path": "${SCRIPT_DIR}"
}
EOF
        fi
        log_debug ".harness-meta.json 기록 완료"
    fi
}

migrate_gitignore() {
    local target="$1"
    local gitignore="${target}/.gitignore"

    [[ -f "$gitignore" ]] || return 0

    # 레거시 항목이 있는지 확인
    if ! grep -qF "# hoodcat-harness runtime" "$gitignore" 2>/dev/null; then
        return 0
    fi

    if dry_run_guard ".gitignore 레거시 항목 정리"; then
        local tmp
        tmp="$(mktemp)"
        local in_block=false
        while IFS= read -r line; do
            if [[ "$line" == "# hoodcat-harness runtime" ]]; then
                in_block=true
                continue
            fi
            if $in_block; then
                if [[ "$line" == ".claude/"* ]] || \
                   [[ "$line" == ".claude" ]] || \
                   [[ -z "$line" ]]; then
                    continue
                fi
                in_block=false
            fi
            echo "$line" >> "$tmp"
        done < "$gitignore"
        mv "$tmp" "$gitignore"
        log_info ".gitignore 레거시 항목 정리 완료"
    fi
}

update_target_gitignore() {
    local target="$1"
    local gitignore="${target}/.gitignore"

    if dry_run_guard ".gitignore 업데이트"; then
        touch "$gitignore"
        local needs_newline=false
        # 파일 끝에 개행이 없으면 추가 필요
        if [[ -s "$gitignore" ]] && [[ "$(tail -c 1 "$gitignore" | wc -l)" -eq 0 ]]; then
            needs_newline=true
        fi

        local added=false
        for entry in "${GITIGNORE_ENTRIES[@]}"; do
            if ! grep -qxF "$entry" "$gitignore" 2>/dev/null; then
                if $needs_newline; then
                    echo "" >> "$gitignore"
                    needs_newline=false
                fi
                echo "$entry" >> "$gitignore"
                added=true
            fi
        done

        if $added; then
            log_info ".gitignore에 런타임 항목 추가 완료"
        else
            log_debug ".gitignore: 이미 모든 항목이 존재합니다"
        fi
    fi
}

setup_git() {
    local target="$1"
    local git_state="${2:-none}"  # none | clean | dirty | no-config

    if ! command -v git &>/dev/null; then
        log_debug "git이 설치되어 있지 않습니다. git 설정을 건너뜁니다."
        return
    fi

    if [[ "$git_state" == "none" ]]; then
        # 케이스 1: git repo가 아님 → git init
        log_info "git 저장소가 아닙니다."
        if confirm "git init을 실행하시겠습니까?"; then
            if dry_run_guard "git init"; then
                git -C "$target" init
                log_info "git init 완료"
            fi
        fi
        return
    fi

    if [[ "$git_state" == "dirty" ]]; then
        # 케이스 3: dirty → 경고만
        log_warn "설치 전 커밋되지 않은 변경사항이 있었습니다. git 작업을 건너뜁니다."
        log_warn "설치된 파일을 직접 커밋하세요: git add .gitignore CLAUDE.md"
        return
    fi

    if [[ "$git_state" == "no-config" ]]; then
        log_warn "git user.name/email이 설정되지 않았습니다. 커밋을 건너뜁니다."
        return
    fi

    # 케이스 2: clean → 브랜치 생성 + 커밋
    local branch="harness/install"
    if git -C "$target" show-ref --verify --quiet "refs/heads/${branch}" 2>/dev/null; then
        branch="harness/install-$(date +%Y%m%d%H%M%S)"
    fi

    if confirm "브랜치 '${branch}'를 생성하고 설치 파일을 커밋하시겠습니까?"; then
        if dry_run_guard "git branch + commit"; then
            git -C "$target" checkout -b "$branch"
            git -C "$target" add .gitignore CLAUDE.md
            git -C "$target" commit -m "feat: hoodcat-harness 멀티에이전트 시스템 설치"
            log_info "브랜치 '${branch}'에 커밋 완료"
        fi
    fi
}

clean_target_gitignore() {
    local target="$1"
    local gitignore="${target}/.gitignore"

    [[ -f "$gitignore" ]] || return 0

    if confirm ".gitignore에서 harness 관련 항목을 제거하시겠습니까?"; then
        if dry_run_guard ".gitignore 정리"; then
            local tmp
            tmp="$(mktemp)"
            local in_block=false
            while IFS= read -r line; do
                if [[ "$line" == "# hoodcat-harness"* ]]; then
                    in_block=true
                    continue
                fi
                if $in_block; then
                    # 빈 줄이거나 .claude/ 관련 항목이면 스킵
                    if [[ "$line" == ".claude/"* ]] || \
                       [[ "$line" == ".claude" ]] || \
                       [[ -z "$line" ]]; then
                        continue
                    fi
                    in_block=false
                fi
                echo "$line" >> "$tmp"
            done < "$gitignore"
            mv "$tmp" "$gitignore"
            log_info ".gitignore 정리 완료"
        fi
    fi
}

# --- 명령 구현 ---

cmd_config() {
    local global_env="$HOME/.claude/.env"

    echo ""
    log_info "=== 텔레그램 알림 환경변수 설정 ==="
    log_info "대상 파일: ${global_env}"
    echo ""

    # ~/.claude/ 디렉토리가 없을 수 있으므로 생성
    mkdir -p "$HOME/.claude"

    # .env 파일이 없으면 빈 파일 생성
    if [[ ! -f "$global_env" ]]; then
        if dry_run_guard "~/.claude/.env 생성"; then
            touch "$global_env"
            log_info "~/.claude/.env 파일을 생성했습니다."
        fi
    fi

    # 기존 값 로드
    local current_token="" current_chat_id=""
    if [[ -f "$global_env" ]]; then
        current_token="$(grep '^HARNESS_TG_BOT_TOKEN=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_BOT_TOKEN=//' || true)"
        current_chat_id="$(grep '^HARNESS_TG_CHAT_ID=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_CHAT_ID=//' || true)"
    fi

    # 현재 상태 표시
    echo "현재 설정:"
    if [[ -n "$current_token" && "$current_token" != "your_bot_token_here" ]]; then
        # 토큰 마스킹: 앞 8자만 표시
        local masked_token="${current_token:0:8}..."
        echo -e "  HARNESS_TG_BOT_TOKEN: ${GREEN}${masked_token}${NC}"
    else
        echo -e "  HARNESS_TG_BOT_TOKEN: ${YELLOW}(미설정)${NC}"
    fi
    if [[ -n "$current_chat_id" && "$current_chat_id" != "your_chat_id_here" ]]; then
        echo -e "  HARNESS_TG_CHAT_ID:   ${GREEN}${current_chat_id}${NC}"
    else
        echo -e "  HARNESS_TG_CHAT_ID:   ${YELLOW}(미설정)${NC}"
    fi
    echo ""

    # 비대화형 환경이면 프롬프트 스킵
    if [[ ! -t 0 ]]; then
        log_warn "비대화형 환경입니다. ~/.claude/.env를 직접 편집하세요."
        return
    fi

    # .env 파일에 변수를 설정하는 헬퍼 (macOS/Linux sed 호환)
    _set_env_var() {
        local var_name="$1" var_value="$2" env_file="$3"
        if grep -q "^${var_name}=" "$env_file" 2>/dev/null; then
            local tmp
            tmp="$(mktemp)"
            sed "s|^${var_name}=.*|${var_name}=${var_value}|" "$env_file" > "$tmp"
            mv "$tmp" "$env_file"
        else
            echo "${var_name}=${var_value}" >> "$env_file"
        fi
    }

    # Bot Token 설정
    log_info "텔레그램 알림 설정 (빈 Enter로 현재 값 유지)"
    echo ""
    echo -e "  ${BLUE}Bot token은 Telegram @BotFather에서 발급받을 수 있습니다.${NC}"
    echo -n "  HARNESS_TG_BOT_TOKEN: "
    read -r input_token
    if [[ -n "$input_token" ]]; then
        if dry_run_guard "HARNESS_TG_BOT_TOKEN 설정"; then
            _set_env_var "HARNESS_TG_BOT_TOKEN" "$input_token" "$global_env"
            log_info "HARNESS_TG_BOT_TOKEN 설정 완료"
        fi
    else
        log_info "HARNESS_TG_BOT_TOKEN: 변경 없음"
    fi

    # Chat ID 설정
    echo -e "  ${BLUE}Chat ID는 @userinfobot 또는 @getmyid_bot에서 확인할 수 있습니다.${NC}"
    echo -n "  HARNESS_TG_CHAT_ID: "
    read -r input_chat_id
    if [[ -n "$input_chat_id" ]]; then
        if dry_run_guard "HARNESS_TG_CHAT_ID 설정"; then
            _set_env_var "HARNESS_TG_CHAT_ID" "$input_chat_id" "$global_env"
            log_info "HARNESS_TG_CHAT_ID 설정 완료"
        fi
    else
        log_info "HARNESS_TG_CHAT_ID: 변경 없음"
    fi

    echo ""
    log_info "=== 설정 완료 ==="

    # 최종 상태 표시
    if [[ -f "$global_env" ]]; then
        local final_token final_chat_id
        final_token="$(grep '^HARNESS_TG_BOT_TOKEN=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_BOT_TOKEN=//' || true)"
        final_chat_id="$(grep '^HARNESS_TG_CHAT_ID=' "$global_env" 2>/dev/null | sed 's/^HARNESS_TG_CHAT_ID=//' || true)"

        local token_ok=false chat_ok=false
        [[ -n "$final_token" && "$final_token" != "your_bot_token_here" ]] && token_ok=true
        [[ -n "$final_chat_id" && "$final_chat_id" != "your_chat_id_here" ]] && chat_ok=true

        if $token_ok && $chat_ok; then
            echo -e "텔레그램 알림: ${GREEN}활성화 가능${NC}"
        else
            echo -e "텔레그램 알림: ${YELLOW}미완료${NC} (두 값 모두 설정 필요)"
        fi
    fi
}

cmd_install() {
    local target="$1"
    validate_target "$target"
    target="$(cd "$target" && pwd)"  # 절대 경로 변환

    # 이미 설치 확인
    if [[ -f "${target}/${META_FILE}" ]]; then
        die "이미 harness가 설치되어 있습니다. 업데이트하려면 'update' 명령을 사용하세요."
    fi

    # 기존 .claude/ 존재 확인
    if [[ -d "${target}/.claude" ]]; then
        log_warn "기존 .claude/ 디렉토리가 발견되었습니다."
        if confirm "기존 .claude/를 백업하고 계속하시겠습니까?"; then
            local backup="${target}/.claude.backup.$(date +%Y%m%d%H%M%S)"
            if dry_run_guard "기존 .claude/ → ${backup} 백업"; then
                mv "${target}/.claude" "$backup"
                log_info "백업 완료: $backup"
            fi
        else
            die "설치를 취소했습니다."
        fi
    fi

    # git 상태를 설치 전에 미리 확인 (설치 파일이 dirty를 만들기 전)
    local git_state="none"  # none | clean | dirty | no-config
    if command -v git &>/dev/null && git -C "$target" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        if ! git config user.name &>/dev/null || ! git config user.email &>/dev/null; then
            git_state="no-config"
        elif [[ -n "$(git -C "$target" status --porcelain 2>/dev/null)" ]]; then
            git_state="dirty"
        else
            git_state="clean"
        fi
    fi

    local commit
    commit="$(get_source_commit)"
    echo ""
    log_info "=== hoodcat-harness 설치 ==="
    log_info "소스: ${SCRIPT_DIR} (${commit})"
    log_info "대상: ${target}"
    echo ""

    if ! confirm "설치를 진행하시겠습니까?"; then
        die "설치를 취소했습니다."
    fi

    echo ""

    # 1. 템플릿 복사
    log_info "템플릿 파일 복사 중..."
    copy_template_files "$target"

    # 2. statusline 복사
    log_info "상태표시줄 스크립트 설치 중..."
    copy_statusline "$target"

    # 3. harness.md 복사
    log_info "공통 지침 파일 설치 중..."
    copy_harness_md "$target"

    # 3.5. shared-context-config.json 복사
    log_info "공유 컨텍스트 설정 파일 설치 중..."
    copy_shared_context_config "$target"

    # 4. 런타임 디렉토리 생성
    log_info "런타임 디렉토리 생성 중..."
    init_runtime_dirs "$target"

    # 5. settings.json 복사
    log_info "설정 파일 복사 중..."
    copy_settings "$target" "install"

    # 6. 전역 환경 변수 확인
    log_info "전역 환경 변수 확인 중..."
    check_global_env

    # 7. .gitignore 업데이트
    log_info ".gitignore 업데이트 중..."
    update_target_gitignore "$target"

    # 8. CLAUDE.md에 harness.md import 주입
    log_info "CLAUDE.md harness import 확인 중..."
    inject_harness_import "$target"

    # 9. .harness-meta.json 기록
    log_info "메타 정보 기록 중..."
    write_harness_meta "$target" "install"

    # 10. git 설정
    log_info "git 설정 확인 중..."
    setup_git "$target" "$git_state"

    echo ""
    log_info "=== 설치 완료 ==="
    echo ""
    echo "설치된 항목:"
    for dir in "${TEMPLATE_DIRS[@]}"; do
        if [[ -d "${target}/.claude/${dir}" ]]; then
            local count
            count="$(find "${target}/.claude/${dir}" -type f | wc -l)"
            echo "  .claude/${dir}/ (${count}개 파일)"
        fi
    done
    echo "  .claude/harness.md"
    echo "  .claude/statusline.sh"
    echo "  .claude/shared-context-config.json"
    echo "  .claude/settings.json"
    [[ -f "$HOME/.claude/.env" ]] && echo "  ~/.claude/.env (전역)"
    echo ""
    echo -e "${YELLOW}[참고]${NC} CLAUDE.md는 프로젝트별로 다르므로 복사하지 않았습니다."
    echo -e "${YELLOW}[참고]${NC} 대상 프로젝트에 맞는 CLAUDE.md를 직접 작성하세요."
    echo -e "${YELLOW}[참고]${NC} CLAUDE.md에 @.claude/harness.md가 없으면 자동으로 추가됩니다."
}

cmd_update() {
    local target="$1"
    validate_target "$target"
    target="$(cd "$target" && pwd)"

    # 설치 여부 확인
    if [[ ! -f "${target}/${META_FILE}" ]]; then
        die "harness가 설치되어 있지 않습니다. 먼저 'install' 명령을 사용하세요."
    fi

    local current_commit
    current_commit="$(get_source_commit)"
    local installed_commit
    installed_commit="$(grep -o '"source_commit": *"[^"]*"' "${target}/${META_FILE}" | sed 's/.*: *"//;s/"$//')"

    echo ""
    log_info "=== hoodcat-harness 업데이트 ==="
    log_info "소스: ${SCRIPT_DIR} (${current_commit})"
    log_info "대상: ${target}"
    log_info "설치된 버전: ${installed_commit}"
    echo ""

    # 변경 사항 diff 표시
    local has_changes=false
    for dir in "${TEMPLATE_DIRS[@]}"; do
        local src="${SOURCE_CLAUDE_DIR}/${dir}/"
        local dst="${target}/.claude/${dir}/"

        if [[ ! -d "$src" ]]; then continue; fi

        if [[ ! -d "$dst" ]]; then
            log_info "  + ${dir}/ (새로 추가)"
            has_changes=true
            continue
        fi

        local diff_output
        diff_output="$(diff -rq "$src" "$dst" 2>/dev/null || true)"
        if [[ -n "$diff_output" ]]; then
            has_changes=true
            echo "$diff_output" | while IFS= read -r line; do
                if [[ "$line" == *"Only in ${src}"* ]]; then
                    local file="${line#Only in */: }"
                    log_info "  + ${dir}/${file}"
                elif [[ "$line" == *"Only in ${dst}"* ]]; then
                    local file="${line#Only in */: }"
                    log_warn "  - ${dir}/${file} (삭제 예정)"
                elif [[ "$line" == *"differ"* ]]; then
                    local file
                    file="${line#Files }"
                    file="${file%% and *}"
                    file="${file#${src}}"
                    log_info "  ~ ${dir}/${file} (변경됨)"
                fi
            done
        fi
    done

    # standalone 파일 변경 감지
    local standalone_files=(harness.md statusline.sh settings.json shared-context-config.json)
    for file in "${standalone_files[@]}"; do
        local src="${SOURCE_CLAUDE_DIR}/${file}"
        local dst="${target}/.claude/${file}"

        if [[ -f "$src" && ! -f "$dst" ]]; then
            log_info "  + ${file} (새로 추가)"
            has_changes=true
        elif [[ -f "$src" && -f "$dst" ]]; then
            if ! diff -q "$src" "$dst" &>/dev/null; then
                log_info "  ~ ${file} (변경됨)"
                has_changes=true
            fi
        fi
    done

    if [[ "$current_commit" == "$installed_commit" ]] && ! $has_changes; then
        log_info "변경 사항이 없습니다."
        return 0
    fi

    echo ""
    if ! confirm "업데이트를 진행하시겠습니까?"; then
        die "업데이트를 취소했습니다."
    fi

    echo ""

    # 1. 템플릿 동기화 (--delete)
    log_info "템플릿 파일 동기화 중..."
    copy_template_files "$target" "--delete"

    # 2. statusline 업데이트
    log_info "상태표시줄 스크립트 업데이트 중..."
    copy_statusline "$target"

    # 3. harness.md 업데이트
    log_info "공통 지침 파일 업데이트 중..."
    copy_harness_md "$target"

    # 3.5. shared-context-config.json 복사
    log_info "공유 컨텍스트 설정 파일 업데이트 중..."
    copy_shared_context_config "$target"

    # 4. settings.json 업데이트
    log_info "설정 파일 확인 중..."
    copy_settings "$target" "update"

    # 5. 전역 환경 변수 확인
    log_info "전역 환경 변수 확인 중..."
    check_global_env

    # 6. 런타임 파일 보존 (memory, log)
    log_info "런타임 파일 보존 확인..."
    init_runtime_dirs "$target"  # 디렉토리가 없으면 생성

    # 7. .gitignore 업데이트 (레거시 항목 마이그레이션 포함)
    log_info ".gitignore 확인 중..."
    migrate_gitignore "$target"
    update_target_gitignore "$target"

    # 8. CLAUDE.md에 harness.md import 주입
    log_info "CLAUDE.md harness import 확인 중..."
    inject_harness_import "$target"

    # 9. .harness-meta.json 갱신
    log_info "메타 정보 갱신 중..."
    write_harness_meta "$target" "update"

    echo ""
    log_info "=== 업데이트 완료 (${installed_commit} → ${current_commit}) ==="
}

cmd_delete() {
    local target="$1"
    validate_target "$target"
    target="$(cd "$target" && pwd)"

    if [[ ! -f "${target}/${META_FILE}" ]]; then
        die "harness가 설치되어 있지 않습니다."
    fi

    echo ""
    log_info "=== hoodcat-harness 삭제 ==="
    log_info "대상: ${target}"
    echo ""

    # harness가 설치한 디렉토리 목록
    local harness_dirs=(agents skills rules hooks shared-context log)
    # harness가 설치한 파일 목록
    local harness_files=(harness.md statusline.sh .harness-meta.json shared-context-config.json .env.example)

    # 삭제 대상 표시
    echo "삭제될 항목:"
    for dir in "${harness_dirs[@]}"; do
        if [[ -d "${target}/.claude/${dir}" ]]; then
            echo "  .claude/${dir}/"
        fi
    done
    for file in "${harness_files[@]}"; do
        if [[ -f "${target}/.claude/${file}" ]]; then
            echo "  .claude/${file}"
        fi
    done
    if [[ -f "${target}/.claude/settings.json" ]]; then
        if command -v jq &>/dev/null; then
            echo "  .claude/settings.json (harness 키만 제거)"
        else
            echo "  .claude/settings.json (백업 후 삭제)"
        fi
    fi
    echo ""

    # CLAUDE.md import 제거 예고
    if [[ -f "${target}/CLAUDE.md" ]] && grep -qF "@.claude/harness.md" "${target}/CLAUDE.md" 2>/dev/null; then
        echo "추가 변경:"
        echo "  CLAUDE.md에서 @.claude/harness.md import 제거"
        echo ""
    fi

    # .claude/ 하위에 harness가 관리하지 않는 항목 감지
    local has_user_files=false
    if [[ -d "${target}/.claude" ]]; then
        while IFS= read -r item; do
            local basename
            basename="$(basename "$item")"
            local is_harness=false
            for dir in "${harness_dirs[@]}"; do
                [[ "$basename" == "$dir" ]] && is_harness=true && break
            done
            for file in "${harness_files[@]}"; do
                [[ "$basename" == "$file" ]] && is_harness=true && break
            done
            [[ "$basename" == "settings.json" ]] && is_harness=true
            if ! $is_harness; then
                if ! $has_user_files; then
                    log_info "보존될 항목 (.claude/ 내 사용자 파일):"
                    has_user_files=true
                fi
                echo "  .claude/${basename}"
            fi
        done < <(find "${target}/.claude" -mindepth 1 -maxdepth 1 2>/dev/null)
        if $has_user_files; then
            echo ""
        fi
    fi

    if ! confirm "harness를 삭제하시겠습니까?"; then
        die "삭제를 취소했습니다."
    fi

    echo ""

    # 1. 디렉토리 삭제
    for dir in "${harness_dirs[@]}"; do
        if [[ -d "${target}/.claude/${dir}" ]]; then
            if dry_run_guard ".claude/${dir}/ 삭제"; then
                rm -rf "${target}/.claude/${dir}"
                log_info ".claude/${dir}/ 삭제 완료"
            fi
        fi
    done

    # 2. 파일 삭제
    for file in "${harness_files[@]}"; do
        if [[ -f "${target}/.claude/${file}" ]]; then
            if dry_run_guard ".claude/${file} 삭제"; then
                rm -f "${target}/.claude/${file}"
                log_info ".claude/${file} 삭제 완료"
            fi
        fi
    done

    # 3. settings.json에서 harness 키 제거 (또는 백업 후 삭제)
    log_info "settings.json 정리 중..."
    unmerge_settings_json "$target"

    # 4. CLAUDE.md에서 harness import 제거
    log_info "CLAUDE.md 정리 중..."
    remove_harness_import "$target"

    # 5. .gitignore 정리
    clean_target_gitignore "$target"

    # 6. .claude/ 디렉토리가 비었으면 제거
    if [[ -d "${target}/.claude" ]]; then
        if [[ -z "$(ls -A "${target}/.claude" 2>/dev/null)" ]]; then
            if dry_run_guard "빈 .claude/ 디렉토리 삭제"; then
                rmdir "${target}/.claude"
                log_info "빈 .claude/ 디렉토리 삭제 완료"
            fi
        else
            log_info ".claude/ 디렉토리에 사용자 파일이 남아 있어 보존합니다."
        fi
    fi

    echo ""
    log_info "=== 삭제 완료 ==="
}

cmd_status() {
    local target="$1"
    validate_target "$target"
    target="$(cd "$target" && pwd)"

    echo ""
    log_info "=== hoodcat-harness 상태 ==="
    log_info "대상: ${target}"
    echo ""

    if [[ ! -f "${target}/${META_FILE}" ]]; then
        echo "상태: 미설치"
        return 0
    fi

    echo "상태: 설치됨"

    local installed_at updated_at source_commit source_path
    installed_at="$(grep -o '"installed_at": *"[^"]*"' "${target}/${META_FILE}" | sed 's/.*: *"//;s/"$//')"
    updated_at="$(grep -o '"updated_at": *"[^"]*"' "${target}/${META_FILE}" | sed 's/.*: *"//;s/"$//')"
    source_commit="$(grep -o '"source_commit": *"[^"]*"' "${target}/${META_FILE}" | sed 's/.*: *"//;s/"$//')"
    source_path="$(grep -o '"source_path": *"[^"]*"' "${target}/${META_FILE}" | sed 's/.*: *"//;s/"$//')"

    echo "설치 시각: ${installed_at}"
    echo "업데이트: ${updated_at}"
    echo "소스 커밋: ${source_commit}"
    echo "소스 경로: ${source_path}"
    echo ""

    # 소스와 현재 커밋 비교
    local current_commit
    current_commit="$(get_source_commit)"
    if [[ "$source_commit" == "$current_commit" ]]; then
        echo -e "버전: ${GREEN}최신${NC}"
    else
        echo -e "버전: ${YELLOW}업데이트 가능${NC} (${source_commit} → ${current_commit})"
    fi

    echo ""

    # 파일 통계
    echo "구성 요소:"
    for dir in "${TEMPLATE_DIRS[@]}"; do
        if [[ -d "${target}/.claude/${dir}" ]]; then
            local count
            count="$(find "${target}/.claude/${dir}" -type f | wc -l)"
            echo "  .claude/${dir}/ : ${count}개 파일"
        else
            echo "  .claude/${dir}/ : 없음"
        fi
    done

    # 런타임 상태
    echo ""
    echo "런타임:"
    if [[ -d "${target}/.claude/log" ]]; then
        local log_count
        log_count="$(find "${target}/.claude/log" -type f 2>/dev/null | wc -l)"
        echo "  log: ${log_count}개 파일"
    fi
}

cmd_mode() {
    local action="$1"
    local target="$2"

    case "$action" in
        on|off|status) ;;
        *)
            die "알 수 없는 mode 액션: ${action} (on, off, status 중 선택)"
            ;;
    esac

    validate_target "$target"
    target="$(cd "$target" && pwd)"

    # harness 설치 여부 확인
    if [[ ! -f "${target}/${META_FILE}" ]]; then
        die "harness가 설치되어 있지 않습니다: ${target}"
    fi

    local claude_md="${target}/CLAUDE.md"
    local settings_json="${target}/.claude/settings.json"
    local settings_hooks_backup="${target}/.claude/settings.hooks.json"
    local settings_full_backup="${target}/.claude/settings.json.harness"
    local meta_path="${target}/${META_FILE}"
    local import_line="@.claude/harness.md"
    local disabled_line="# @.claude/harness.md  # harness-mode: disabled"

    # 현재 모드 판별
    local current_mode="on"
    if [[ -f "$meta_path" ]]; then
        local meta_mode
        meta_mode="$(grep -o '"mode": *"[^"]*"' "$meta_path" 2>/dev/null | sed 's/.*: *"//;s/"$//' || true)"
        if [[ "$meta_mode" == "off" ]]; then
            current_mode="off"
        fi
    fi

    case "$action" in
        status)
            echo ""
            log_info "=== harness 모드 상태 ==="
            log_info "대상: ${target}"
            echo ""

            # 모드 표시
            if [[ "$current_mode" == "on" ]]; then
                echo -e "모드: ${GREEN}on${NC} (harness 활성화)"
            else
                echo -e "모드: ${YELLOW}off${NC} (harness 비활성화)"
            fi

            # CLAUDE.md import 상태
            if [[ -f "$claude_md" ]]; then
                if grep -qF "$disabled_line" "$claude_md" 2>/dev/null; then
                    echo -e "CLAUDE.md import: ${YELLOW}비활성화${NC}"
                elif grep -qF "$import_line" "$claude_md" 2>/dev/null; then
                    echo -e "CLAUDE.md import: ${GREEN}활성화${NC}"
                else
                    echo -e "CLAUDE.md import: ${RED}없음${NC}"
                fi
            else
                echo -e "CLAUDE.md: ${RED}파일 없음${NC}"
            fi

            # settings.json hooks 상태
            if [[ -f "$settings_json" ]]; then
                if command -v jq &>/dev/null; then
                    if jq -e '.hooks' "$settings_json" &>/dev/null; then
                        echo -e "settings.json hooks: ${GREEN}활성화${NC}"
                    else
                        echo -e "settings.json hooks: ${YELLOW}없음${NC}"
                    fi
                else
                    if grep -q '"hooks"' "$settings_json" 2>/dev/null; then
                        echo -e "settings.json hooks: ${GREEN}있음${NC}"
                    else
                        echo -e "settings.json hooks: ${YELLOW}없음${NC}"
                    fi
                fi
            else
                echo -e "settings.json: ${RED}파일 없음${NC}"
            fi

            # 백업 파일 존재 여부
            if [[ -f "$settings_hooks_backup" ]]; then
                echo -e "hooks 백업: ${BLUE}settings.hooks.json${NC}"
            fi
            if [[ -f "$settings_full_backup" ]]; then
                echo -e "settings 백업: ${BLUE}settings.json.harness${NC}"
            fi
            echo ""
            return 0
            ;;

        off)
            if [[ "$current_mode" == "off" ]]; then
                log_info "이미 harness가 비활성화된 상태입니다."
                return 0
            fi

            echo ""
            log_info "=== harness 비활성화 ==="
            log_info "대상: ${target}"
            echo ""

            # 1. CLAUDE.md @import 비활성화
            if [[ -f "$claude_md" ]]; then
                if grep -qF "$import_line" "$claude_md" 2>/dev/null && \
                   ! grep -qF "$disabled_line" "$claude_md" 2>/dev/null; then
                    if dry_run_guard "CLAUDE.md에서 harness import 비활성화"; then
                        local tmp
                        tmp="$(mktemp)"
                        sed "s|^${import_line}$|${disabled_line}|" "$claude_md" > "$tmp"
                        mv "$tmp" "$claude_md"
                        log_info "CLAUDE.md: harness import 비활성화 완료"
                    fi
                else
                    log_debug "CLAUDE.md: 이미 비활성화되었거나 import가 없습니다"
                fi
            fi

            # 2. settings.json hooks 백업 후 제거
            if [[ -f "$settings_json" ]]; then
                if command -v jq &>/dev/null; then
                    # jq로 hooks 키만 추출하여 백업
                    if jq -e '.hooks' "$settings_json" &>/dev/null; then
                        if dry_run_guard "settings.json에서 hooks 키 백업 및 제거"; then
                            jq '{hooks: .hooks}' "$settings_json" > "$settings_hooks_backup"
                            local result
                            result="$(jq 'del(.hooks)' "$settings_json")"
                            echo "$result" > "$settings_json"
                            log_info "settings.json: hooks 키를 settings.hooks.json에 백업 후 제거 완료"
                        fi
                    else
                        log_debug "settings.json: hooks 키가 없습니다"
                    fi
                else
                    # jq 없으면 전체 settings.json을 백업
                    if grep -q '"hooks"' "$settings_json" 2>/dev/null; then
                        if dry_run_guard "settings.json 전체 백업 후 최소 설정 생성"; then
                            cp "$settings_json" "$settings_full_backup"
                            echo '{}' > "$settings_json"
                            log_info "settings.json: settings.json.harness에 백업 후 빈 설정 생성"
                            log_warn "jq가 있으면 hooks만 선택적으로 제거할 수 있습니다"
                        fi
                    else
                        log_debug "settings.json: hooks 키가 없습니다"
                    fi
                fi
            fi

            # 3. .harness-meta.json에 mode: off 기록
            if dry_run_guard ".harness-meta.json에 mode: off 기록"; then
                if command -v jq &>/dev/null && [[ -f "$meta_path" ]]; then
                    local result
                    result="$(jq '. + {"mode": "off"}' "$meta_path")"
                    echo "$result" > "$meta_path"
                elif [[ -f "$meta_path" ]]; then
                    # jq 없이 sed로 처리
                    if grep -q '"mode"' "$meta_path" 2>/dev/null; then
                        local tmp
                        tmp="$(mktemp)"
                        sed 's/"mode": *"[^"]*"/"mode": "off"/' "$meta_path" > "$tmp"
                        mv "$tmp" "$meta_path"
                    else
                        # 마지막 } 앞에 mode 필드 삽입
                        local tmp
                        tmp="$(mktemp)"
                        sed 's/}$/,\n  "mode": "off"\n}/' "$meta_path" > "$tmp"
                        mv "$tmp" "$meta_path"
                    fi
                fi
                log_info ".harness-meta.json: mode=off 기록 완료"
            fi

            echo ""
            log_info "=== harness 비활성화 완료 ==="
            echo ""
            echo -e "${YELLOW}[참고]${NC} 모드 전환은 새 세션에서 반영됩니다. 실행 중인 세션에는 영향이 없습니다."
            ;;

        on)
            if [[ "$current_mode" == "on" ]]; then
                log_info "이미 harness가 활성화된 상태입니다."
                return 0
            fi

            echo ""
            log_info "=== harness 활성화 ==="
            log_info "대상: ${target}"
            echo ""

            # 1. CLAUDE.md @import 복원
            if [[ -f "$claude_md" ]]; then
                if grep -qF "$disabled_line" "$claude_md" 2>/dev/null; then
                    if dry_run_guard "CLAUDE.md에서 harness import 활성화"; then
                        local tmp
                        tmp="$(mktemp)"
                        sed "s|^${disabled_line}$|${import_line}|" "$claude_md" > "$tmp"
                        mv "$tmp" "$claude_md"
                        log_info "CLAUDE.md: harness import 활성화 완료"
                    fi
                else
                    log_debug "CLAUDE.md: 이미 활성화되었거나 disabled 마커가 없습니다"
                fi
            fi

            # 2. settings.json hooks 복원
            if [[ -f "$settings_hooks_backup" ]]; then
                if command -v jq &>/dev/null && [[ -f "$settings_json" ]]; then
                    if dry_run_guard "settings.json에 hooks 복원"; then
                        local result
                        result="$(jq -s '.[0] * .[1]' "$settings_json" "$settings_hooks_backup")"
                        echo "$result" > "$settings_json"
                        rm -f "$settings_hooks_backup"
                        log_info "settings.json: hooks 복원 완료 (settings.hooks.json 삭제)"
                    fi
                elif [[ -f "$settings_json" ]]; then
                    # jq 없으면 복원 불가 경고
                    log_warn "jq가 없어 hooks를 자동 복원할 수 없습니다"
                    log_warn "settings.hooks.json의 내용을 settings.json에 수동으로 머지하세요"
                fi
            elif [[ -f "$settings_full_backup" ]]; then
                if dry_run_guard "settings.json 전체 복원"; then
                    mv "$settings_full_backup" "$settings_json"
                    log_info "settings.json: settings.json.harness에서 복원 완료"
                fi
            else
                log_debug "hooks 백업 파일이 없습니다. settings.json을 그대로 유지합니다."
            fi

            # 3. .harness-meta.json에서 mode 필드 제거
            if dry_run_guard ".harness-meta.json에서 mode 필드 제거"; then
                if command -v jq &>/dev/null && [[ -f "$meta_path" ]]; then
                    local result
                    result="$(jq 'del(.mode)' "$meta_path")"
                    echo "$result" > "$meta_path"
                elif [[ -f "$meta_path" ]]; then
                    # jq 없이 sed로 mode 필드 제거
                    local tmp
                    tmp="$(mktemp)"
                    sed '/"mode": *"[^"]*"/d' "$meta_path" \
                        | sed ':a;N;$!ba;s/,\n}/\n}/g' > "$tmp"
                    mv "$tmp" "$meta_path"
                fi
                log_info ".harness-meta.json: mode 필드 제거 완료"
            fi

            echo ""
            log_info "=== harness 활성화 완료 ==="
            echo ""
            echo -e "${YELLOW}[참고]${NC} 모드 전환은 새 세션에서 반영됩니다. 실행 중인 세션에는 영향이 없습니다."
            ;;
    esac
}

cmd_completion() {
    local shell_type="${1:-}"

    if [[ -z "$shell_type" ]]; then
        log_error "셸 타입을 지정하세요: bash 또는 zsh"
        echo ""
        echo "사용법: harness completion <bash|zsh>"
        echo ""
        echo "설치 방법:"
        echo "  bash: eval \"\$(harness completion bash)\""
        echo "  zsh:  eval \"\$(harness completion zsh)\""
        exit 1
    fi

    case "$shell_type" in
        bash) _harness_completion_bash ;;
        zsh)  _harness_completion_zsh ;;
        *)
            die "지원하지 않는 셸 타입: ${shell_type} (bash 또는 zsh만 지원)"
            ;;
    esac
}

_harness_completion_bash() {
    cat << 'BASH_COMPLETION'
_harness_completions() {
    local cur prev commands options
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"

    commands="install update delete status mode config completion"
    options="-f --force -y --yes -n --dry-run -v --verbose -h --help"

    # 첫 번째 인자: 서브커맨드 또는 옵션
    if [[ ${COMP_CWORD} -eq 1 ]]; then
        COMPREPLY=( $(compgen -W "${commands} ${options}" -- "${cur}") )
        return 0
    fi

    # 서브커맨드 이후의 인자
    local cmd="${COMP_WORDS[1]}"
    case "${cmd}" in
        install|update|delete|status)
            # 두 번째 인자: 디렉토리 경로
            if [[ ${COMP_CWORD} -eq 2 && "${cur}" != -* ]]; then
                COMPREPLY=( $(compgen -d -- "${cur}") )
                return 0
            fi
            # 그 이후: 옵션
            COMPREPLY=( $(compgen -W "${options}" -- "${cur}") )
            ;;
        mode)
            # 두 번째 인자: on/off/status
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "on off status" -- "${cur}") )
                return 0
            fi
            # 세 번째 인자: 디렉토리 경로
            if [[ ${COMP_CWORD} -eq 3 && "${cur}" != -* ]]; then
                COMPREPLY=( $(compgen -d -- "${cur}") )
                return 0
            fi
            ;;
        completion)
            # 두 번째 인자: 셸 타입
            if [[ ${COMP_CWORD} -eq 2 ]]; then
                COMPREPLY=( $(compgen -W "bash zsh" -- "${cur}") )
                return 0
            fi
            ;;
        config)
            # config는 추가 인자 없음, 옵션만
            COMPREPLY=( $(compgen -W "${options}" -- "${cur}") )
            ;;
        *)
            COMPREPLY=( $(compgen -W "${commands} ${options}" -- "${cur}") )
            ;;
    esac
}

complete -F _harness_completions harness
complete -F _harness_completions harness.sh
BASH_COMPLETION
}

_harness_completion_zsh() {
    cat << 'ZSH_COMPLETION'
#compdef harness harness.sh

_harness() {
    local -a commands options

    commands=(
        'install:대상 디렉토리에 harness 설치'
        'update:설치된 harness를 최신 버전으로 업데이트'
        'delete:설치된 harness 삭제'
        'status:설치 상태 확인'
        'mode:harness 모드 전환 (on/off/status)'
        'config:텔레그램 알림 환경변수 대화형 설정'
        'completion:셸 자동완성 스크립트 출력'
    )

    options=(
        '-f[확인 프롬프트 스킵]'
        '--force[확인 프롬프트 스킵]'
        '-y[확인 프롬프트 스킵]'
        '--yes[확인 프롬프트 스킵]'
        '-n[실제 변경 없이 표시만]'
        '--dry-run[실제 변경 없이 표시만]'
        '-v[상세 로그 출력]'
        '--verbose[상세 로그 출력]'
        '-h[도움말 표시]'
        '--help[도움말 표시]'
    )

    _arguments -C \
        '1:command:->command' \
        '2:argument:->argument' \
        '3:third:->third' \
        '*:options:->options'

    case "${state}" in
        command)
            _describe 'command' commands
            _values 'options' ${options[@]}
            ;;
        argument)
            case "${words[2]}" in
                install|update|delete|status)
                    _directories
                    ;;
                mode)
                    local -a mode_actions
                    mode_actions=('on:harness 활성화' 'off:harness 비활성화' 'status:현재 모드 상태 확인')
                    _describe 'action' mode_actions
                    ;;
                completion)
                    local -a shells
                    shells=('bash:Bash 셸 자동완성' 'zsh:Zsh 셸 자동완성')
                    _describe 'shell' shells
                    ;;
            esac
            ;;
        third)
            case "${words[2]}" in
                mode)
                    _directories
                    ;;
            esac
            ;;
        options)
            _values 'options' ${options[@]}
            ;;
    esac
}

_harness "$@"
ZSH_COMPLETION
}

# --- 메인 ---

usage() {
    cat << 'EOF'
사용법: harness <command> [dir] [options]

명령:
  install    [dir]              대상 디렉토리에 harness 설치 (기본: 현재 디렉토리)
  update     [dir]              설치된 harness를 최신 버전으로 업데이트
  delete     [dir]              설치된 harness 삭제
  status     [dir]              설치 상태 확인
  mode       <on|off|status> [dir]  harness 모드 전환 (새 세션에서 반영)
  config                        텔레그램 알림 환경변수 대화형 설정 (~/.claude/.env)
  completion <bash|zsh>         셸 자동완성 스크립트 출력

옵션:
  -f, --force, -y   확인 프롬프트 스킵
  -n, --dry-run    실제 변경 없이 표시만
  -v, --verbose    상세 로그 출력
  -h, --help       도움말 표시

자동완성 설치:
  eval "$(harness completion bash)"   # bash
  eval "$(harness completion zsh)"    # zsh
EOF
}

main() {
    local command=""
    local target=""

    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|update|delete|status|config|completion|mode)
                if [[ -z "$command" ]]; then
                    command="$1"
                else
                    # command 이미 설정됨 - 위치 인자로 처리
                    if [[ -z "$target" ]]; then
                        target="$1"
                    elif [[ -z "${extra_arg:-}" ]]; then
                        extra_arg="$1"
                    else
                        die "인자가 너무 많습니다: $1"
                    fi
                fi
                shift
                ;;
            -f|--force|-y|--yes)
                FORCE=true
                shift
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            -*)
                die "알 수 없는 옵션: $1"
                ;;
            *)
                if [[ -z "$target" ]]; then
                    target="$1"
                elif [[ -z "${extra_arg:-}" ]]; then
                    extra_arg="$1"
                else
                    die "인자가 너무 많습니다: $1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "$command" ]] || { usage; exit 1; }

    # config, completion 명령은 대상 프로젝트 없이 독립 실행
    if [[ "$command" == "config" ]]; then
        cmd_config
        return
    fi

    if [[ "$command" == "completion" ]]; then
        cmd_completion "$target"
        return
    fi

    if [[ "$command" == "mode" ]]; then
        # harness mode <on|off|status> [dir]
        # target에는 action(on/off/status)이 들어가고, extra_arg에 실제 dir이 들어감
        local action="${target:-status}"
        local mode_target="${extra_arg:-.}"
        cmd_mode "$action" "$mode_target"
        return
    fi

    [[ -n "$target" ]]  || target="."

    check_dependencies

    # 소스 디렉토리 확인
    [[ -d "$SOURCE_CLAUDE_DIR" ]] || die "소스 .claude/ 디렉토리를 찾을 수 없습니다: $SOURCE_CLAUDE_DIR"

    case "$command" in
        install) cmd_install "$target" ;;
        update)  cmd_update  "$target" ;;
        delete)  cmd_delete  "$target" ;;
        status)  cmd_status  "$target" ;;
        mode)    cmd_mode "${extra_arg:-status}" "$target" ;;
    esac
}

main "$@"
