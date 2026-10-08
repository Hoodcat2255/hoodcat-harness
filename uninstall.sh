#!/usr/bin/env bash
# hoodcat 개인 팩 제거: install.sh가 매니페스트(~/.claude/.hoodcat-pack.json)에
# 기록한 스킬·규칙·훅·스크립트와 settings.json 훅 등록만 제거한다. OMC와
# 전사 파이프라인 디렉토리(전사 결과가 들어 있음)는 건드리지 않는다.
#
# 사용법: ./uninstall.sh [-n|--dry-run] [-q|--quiet] [-h|--help]

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

QUIET=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -n|--dry-run) DRY_RUN=true ;;
        -q|--quiet)   QUIET=true ;;
        -h|--help)    sed -n '2,5p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) die "알 수 없는 옵션: $1" ;;
    esac
    shift
done

say() { [[ "$QUIET" == true ]] || log_ok "$@"; }

require_cmd jq "brew install jq"

if [[ ! -f "$MANIFEST_FILE" ]]; then
    log_warn "매니페스트가 없습니다 (${MANIFEST_FILE}). 설치된 항목이 없습니다."
    exit 0
fi

backup_settings
while IFS= read -r cmd; do
    [[ -n "$cmd" ]] || continue
    settings_remove_hook "$cmd"
    say "훅 등록 해제: ${cmd}"
done < <(jq -r '.hooks[]?' "$MANIFEST_FILE")

while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    # 매니페스트가 오염돼도 설치 루트 밖은 지우지 않는다.
    case "$path" in
        "$CLAUDE_DIR"/*|"$BIN_DIR"/*) ;;
        *) log_warn "설치 루트 밖 경로라 건너뜁니다: ${path}"; continue ;;
    esac
    if [[ -e "$path" || -L "$path" ]]; then
        run rm -rf "$path"
        say "제거: ${path}"
    fi
done < <(jq -r '.paths[]?' "$MANIFEST_FILE")

# 비게 된 네임스페이스 디렉토리 정리
for ns in "$RULES_NS" "$HOOKS_NS"; do
    [[ -d "${CLAUDE_DIR}/${ns}" ]] && run rmdir "${CLAUDE_DIR}/${ns}" 2>/dev/null || true
done

whisper_dir="$(jq -r '.whisper_dir // empty' "$MANIFEST_FILE")"
[[ -n "$whisper_dir" ]] && say "전사 파이프라인은 남겨 둡니다 (전사 결과 포함): ${whisper_dir}"

run rm -f "$MANIFEST_FILE"
say "제거 완료. OMC는 그대로 유지됩니다."
