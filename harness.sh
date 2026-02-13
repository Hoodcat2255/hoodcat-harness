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
    "# hoodcat-harness runtime"
    ".claude/log/"
    ".claude/shared-context/"
    ".claude/.harness-meta.json"
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

copy_settings() {
    local target="$1"
    local mode="${2:-install}"  # install or update
    local src="${SOURCE_CLAUDE_DIR}/settings.local.json"
    local dst="${target}/.claude/settings.local.json"

    if [[ ! -f "$src" ]]; then
        log_warn "소스 settings.local.json이 없습니다."
        return
    fi

    if [[ "$mode" == "update" && -f "$dst" ]]; then
        if diff -q "$src" "$dst" &>/dev/null; then
            log_info "settings.local.json: 변경 없음"
            return
        fi

        echo ""
        log_warn "settings.local.json에 변경이 있습니다:"
        # macOS diff lacks --color; fall back to plain diff
        if diff --help 2>&1 | grep -q -- '--color'; then
            diff --color=auto "$src" "$dst" || true
        else
            diff "$src" "$dst" || true
        fi
        echo ""

        if confirm "settings.local.json을 덮어쓰시겠습니까?"; then
            if dry_run_guard "settings.local.json 덮어쓰기"; then
                cp "$src" "$dst"
                log_info "settings.local.json 업데이트 완료"
            fi
        else
            log_info "settings.local.json 보존"
        fi
    else
        if dry_run_guard "settings.local.json 복사"; then
            cp "$src" "$dst"
            log_debug "settings.local.json 복사 완료"
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

inject_harness_import() {
    local target="$1"
    local claude_md="${target}/CLAUDE.md"
    local import_line="@.claude/harness.md"

    # CLAUDE.md가 없으면 스킵
    if [[ ! -f "$claude_md" ]]; then
        log_debug "대상 CLAUDE.md가 없습니다. import 주입을 건너뜁니다."
        return
    fi

    # 이미 import가 있으면 스킵
    if grep -qF "$import_line" "$claude_md" 2>/dev/null; then
        log_debug "CLAUDE.md에 harness.md import가 이미 존재합니다."
        return
    fi

    if dry_run_guard "CLAUDE.md에 harness.md import 추가"; then
        # 파일 끝에 개행 보장 후 import 섹션 추가
        if [[ -s "$claude_md" ]] && [[ "$(tail -c 1 "$claude_md" | wc -l)" -eq 0 ]]; then
            echo "" >> "$claude_md"
        fi
        {
            echo ""
            echo "## hoodcat-harness 공통 지침"
            echo ""
            echo "$import_line"
        } >> "$claude_md"
        log_info "CLAUDE.md에 harness.md import를 추가했습니다."
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
        log_warn "설치된 파일을 직접 커밋하세요: git add .claude/ .gitignore"
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
            git -C "$target" add .claude/ .gitignore
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
                if [[ "$line" == "# hoodcat-harness runtime" ]]; then
                    in_block=true
                    continue
                fi
                if $in_block; then
                    # 빈 줄이거나 harness 관련 항목이면 스킵
                    if [[ "$line" == ".claude/log/" ]] || \
                       [[ "$line" == ".claude/shared-context/" ]] || \
                       [[ "$line" == ".claude/.harness-meta.json" ]] || \
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

    # 4. 런타임 디렉토리 생성
    log_info "런타임 디렉토리 생성 중..."
    init_runtime_dirs "$target"

    # 5. settings.local.json 복사
    log_info "설정 파일 복사 중..."
    copy_settings "$target" "install"

    # 6. .gitignore 업데이트
    log_info ".gitignore 업데이트 중..."
    update_target_gitignore "$target"

    # 7. CLAUDE.md에 harness.md import 주입
    log_info "CLAUDE.md harness import 확인 중..."
    inject_harness_import "$target"

    # 8. .harness-meta.json 기록
    log_info "메타 정보 기록 중..."
    write_harness_meta "$target" "install"

    # 9. git 설정
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
    echo "  .claude/settings.local.json"
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
    local standalone_files=(harness.md statusline.sh settings.local.json)
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

    # 4. settings.local.json 업데이트
    log_info "설정 파일 확인 중..."
    copy_settings "$target" "update"

    # 5. 런타임 파일 보존 (memory, log)
    log_info "런타임 파일 보존 확인..."
    init_runtime_dirs "$target"  # 디렉토리가 없으면 생성

    # 6. CLAUDE.md에 harness.md import 주입
    log_info "CLAUDE.md harness import 확인 중..."
    inject_harness_import "$target"

    # 7. .harness-meta.json 갱신
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
    log_info "대상: ${target}/.claude/"
    echo ""

    # 삭제 대상 표시
    echo "삭제될 항목:"
    for dir in "${TEMPLATE_DIRS[@]}"; do
        if [[ -d "${target}/.claude/${dir}" ]]; then
            echo "  .claude/${dir}/"
        fi
    done
    [[ -f "${target}/.claude/harness.md" ]] && echo "  .claude/harness.md"
    [[ -f "${target}/.claude/statusline.sh" ]] && echo "  .claude/statusline.sh"
    [[ -f "${target}/.claude/settings.local.json" ]] && echo "  .claude/settings.local.json"
    [[ -f "${target}/.claude/.harness-meta.json" ]] && echo "  .claude/.harness-meta.json"
    echo ""

    # 런타임 데이터 경고
    local has_runtime=false
    if [[ -d "${target}/.claude/log" ]] && [[ -n "$(ls -A "${target}/.claude/log" 2>/dev/null)" ]]; then
        log_warn "로그 데이터가 존재합니다: .claude/log/"
        has_runtime=true
    fi

    if $has_runtime; then
        echo ""
        log_warn "런타임 데이터도 함께 삭제됩니다!"
    fi

    echo ""
    if ! confirm "정말로 .claude/ 전체를 삭제하시겠습니까?"; then
        die "삭제를 취소했습니다."
    fi

    if dry_run_guard ".claude/ 삭제"; then
        rm -rf "${target}/.claude"
        log_info ".claude/ 삭제 완료"
    fi

    # .gitignore 정리
    clean_target_gitignore "$target"

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

# --- 메인 ---

usage() {
    cat << 'EOF'
사용법: harness <command> [dir] [options]

명령:
  install [dir]    대상 디렉토리에 harness 설치 (기본: 현재 디렉토리)
  update  [dir]    설치된 harness를 최신 버전으로 업데이트
  delete  [dir]    설치된 harness 삭제
  status  [dir]    설치 상태 확인

옵션:
  -f, --force, -y   확인 프롬프트 스킵
  -n, --dry-run    실제 변경 없이 표시만
  -v, --verbose    상세 로그 출력
  -h, --help       도움말 표시
EOF
}

main() {
    local command=""
    local target=""

    # 인자 파싱
    while [[ $# -gt 0 ]]; do
        case "$1" in
            install|update|delete|status)
                command="$1"
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
                else
                    die "인자가 너무 많습니다: $1"
                fi
                shift
                ;;
        esac
    done

    [[ -n "$command" ]] || { usage; exit 1; }
    [[ -n "$target" ]]  || target="."

    check_dependencies

    # 소스 디렉토리 확인
    [[ -d "$SOURCE_CLAUDE_DIR" ]] || die "소스 .claude/ 디렉토리를 찾을 수 없습니다: $SOURCE_CLAUDE_DIR"

    case "$command" in
        install) cmd_install "$target" ;;
        update)  cmd_update  "$target" ;;
        delete)  cmd_delete  "$target" ;;
        status)  cmd_status  "$target" ;;
    esac
}

main "$@"
