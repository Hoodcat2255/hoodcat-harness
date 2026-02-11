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

# --- 탭 완성 ---

install_bash_completion() {
    local comp_dir="${HOME}/.local/share/bash-completion/completions"
    local src="${SCRIPT_DIR}/completions/harness.bash"
    [[ -f "$src" ]] || return 0
    mkdir -p "$comp_dir"
    cp "$src" "${comp_dir}/harness"
    echo "bash 완성 설치: ${comp_dir}/harness"
}

install_zsh_completion() {
    local src="${SCRIPT_DIR}/completions/harness.zsh"
    [[ -f "$src" ]] || return 0

    # fpath에서 사용자 completions 디렉토리 탐색
    local comp_dir="${HOME}/.zfunc"
    mkdir -p "$comp_dir"
    cp "$src" "${comp_dir}/_harness"
    echo "zsh 완성 설치: ${comp_dir}/_harness"

    # fpath 안내
    if ! grep -q '\.zfunc' "${HOME}/.zshrc" 2>/dev/null; then
        echo ""
        echo "[참고] ~/.zshrc에 다음을 추가하세요:"
        echo "  fpath=(~/.zfunc \$fpath)"
        echo "  autoload -Uz compinit && compinit"
    fi
}

# 현재 셸에 맞는 completion 설치
current_shell="$(basename "${SHELL:-bash}")"
case "$current_shell" in
    zsh)  install_zsh_completion ;;
    bash) install_bash_completion ;;
    *)    install_bash_completion ;;  # 기본은 bash
esac

# --- PATH 확인 ---

if ! echo "$PATH" | tr ':' '\n' | grep -qx "$BIN_DIR"; then
    echo ""
    echo "[참고] $BIN_DIR 가 PATH에 없습니다. 셸 설정에 추가하세요:"
    echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
fi

echo ""
echo "완료. 새 셸을 열거나 'source ~/.bashrc' / 'source ~/.zshrc' 를 실행하세요."
