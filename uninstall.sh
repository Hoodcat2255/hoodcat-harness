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

# --- 탭 완성 (파일 기반 - 레거시) ---

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

# --- 탭 완성 (eval 기반) ---

marker="# hoodcat-harness completion"
for rc_file in "$HOME/.bashrc" "$HOME/.zshrc"; do
    if [[ -f "$rc_file" ]] && grep -qF "$marker" "$rc_file" 2>/dev/null; then
        tmp="$(mktemp)"
        skip_next=false
        while IFS= read -r line; do
            if [[ "$line" == "$marker" ]]; then
                skip_next=true
                continue
            fi
            if $skip_next; then
                skip_next=false
                if [[ "$line" == eval* ]]; then
                    continue
                fi
                echo "$line" >> "$tmp"
                continue
            fi
            echo "$line" >> "$tmp"
        done < "$rc_file"
        mv "$tmp" "$rc_file"
        echo "셸 자동완성 제거: ${rc_file}"
        removed=true
    fi
done

if ! $removed; then
    echo "설치되어 있지 않습니다."
fi
