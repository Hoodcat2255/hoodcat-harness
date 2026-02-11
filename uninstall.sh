#!/usr/bin/env bash
set -euo pipefail

# ~/.local/bin/harness 심링크 + 탭 완성을 제거한다.

LINK_PATH="${HOME}/.local/bin/harness"
BASH_COMP="${HOME}/.local/share/bash-completion/completions/harness"
ZSH_COMP="${HOME}/.zfunc/_harness"

removed=false

# --- 심링크 ---

if [[ -L "$LINK_PATH" ]]; then
    target="$(readlink "$LINK_PATH")"
    rm "$LINK_PATH"
    echo "심링크 제거: $LINK_PATH (→ $target)"
    removed=true
elif [[ -e "$LINK_PATH" ]]; then
    echo "[ERROR] $LINK_PATH 가 심링크가 아닙니다. 직접 확인하세요."
    exit 1
fi

# --- 탭 완성 ---

if [[ -f "$BASH_COMP" ]]; then
    rm "$BASH_COMP"
    echo "bash 완성 제거: $BASH_COMP"
    removed=true
fi

if [[ -f "$ZSH_COMP" ]]; then
    rm "$ZSH_COMP"
    echo "zsh 완성 제거: $ZSH_COMP"
    removed=true
fi

if ! $removed; then
    echo "설치되어 있지 않습니다."
fi
