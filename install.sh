#!/usr/bin/env bash
set -euo pipefail

# ~/.local/bin/harness 심링크 + 탭 완성을 설치한다.
# 설치 후 어디서든 `harness <command> [dir]` 로 실행 가능.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
HARNESS_SH="${SCRIPT_DIR}/harness.sh"
BIN_DIR="${HOME}/.local/bin"
LINK_PATH="${BIN_DIR}/harness"

# --- 심링크 ---

if [[ ! -f "$HARNESS_SH" ]]; then
    echo "[ERROR] harness.sh를 찾을 수 없습니다: $HARNESS_SH"
    exit 1
fi

mkdir -p "$BIN_DIR"

if [[ -L "$LINK_PATH" ]]; then
    existing="$(readlink "$LINK_PATH")"
    if [[ "$existing" == "$HARNESS_SH" ]]; then
        echo "심링크 이미 존재: $LINK_PATH → $HARNESS_SH"
    else
        echo "기존 심링크가 다른 대상을 가리킵니다: $LINK_PATH → $existing"
        echo -n "덮어쓰시겠습니까? [Y/n] "
        read -r answer
        [[ "$answer" =~ ^[Nn]$ ]] && exit 1
        rm "$LINK_PATH"
        ln -s "$HARNESS_SH" "$LINK_PATH"
        echo "심링크 갱신: $LINK_PATH → $HARNESS_SH"
    fi
elif [[ -e "$LINK_PATH" ]]; then
    echo "[ERROR] $LINK_PATH 가 이미 존재하며 심링크가 아닙니다. 직접 확인하세요."
    exit 1
else
    ln -s "$HARNESS_SH" "$LINK_PATH"
    echo "심링크 생성: $LINK_PATH → $HARNESS_SH"
fi

# --- 탭 완성 (eval 방식: harness.sh completion 서브커맨드 활용) ---

install_completion() {
    local shell_name shell_rc eval_line marker

    # 비대화형 환경이면 스킵
    if [[ ! -t 0 ]]; then
        return
    fi

    # 셸 감지
    shell_name="$(basename "${SHELL:-}")"
    case "$shell_name" in
        bash) shell_rc="$HOME/.bashrc" ;;
        zsh)  shell_rc="$HOME/.zshrc" ;;
        *)
            echo "[WARN] 지원하지 않는 셸입니다 (${shell_name}). 자동완성을 수동으로 설치하세요."
            return
            ;;
    esac

    marker="# hoodcat-harness completion"
    eval_line="eval \"\$(${HARNESS_SH} completion ${shell_name})\""

    # 이미 설치되어 있으면 스킵
    if [[ -f "$shell_rc" ]] && grep -qF "$marker" "$shell_rc" 2>/dev/null; then
        echo "셸 자동완성: 이미 ${shell_rc}에 설치되어 있습니다."
        return
    fi

    # 확인
    echo -n "셸 자동완성을 ${shell_rc}에 추가하시겠습니까? [Y/n] "
    read -r answer
    [[ "$answer" =~ ^[Nn]$ ]] && return

    # 파일 끝에 개행이 없으면 추가
    if [[ -f "$shell_rc" && -s "$shell_rc" ]] && [[ "$(tail -c 1 "$shell_rc" | wc -l)" -eq 0 ]]; then
        echo "" >> "$shell_rc"
    fi
    {
        echo ""
        echo "$marker"
        echo "$eval_line"
    } >> "$shell_rc"
    echo "셸 자동완성을 ${shell_rc}에 추가했습니다."
    echo "적용하려면: source ${shell_rc}"
}

install_completion

# --- PATH 확인 ---

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    echo ""
    echo "[참고] $BIN_DIR 가 PATH에 없습니다. 셸 설정에 추가하세요:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "완료. 새 셸을 열거나 'source ~/.bashrc' / 'source ~/.zshrc' 를 실행하세요."
