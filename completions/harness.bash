# bash completion for harness
# 설치: install.sh가 자동으로 설치합니다.

_harness() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="install update delete status"

    case "$COMP_CWORD" in
        1)
            # 첫 번째 인자: 명령어 또는 옵션
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force --dry-run --verbose --help" -- "$cur") )
            else
                COMPREPLY=( $(compgen -W "$commands" -- "$cur") )
            fi
            ;;
        *)
            # 두 번째 이후: 디렉토리 완성 또는 옵션
            if [[ "$cur" == -* ]]; then
                COMPREPLY=( $(compgen -W "--force --dry-run --verbose -f -n -v -y" -- "$cur") )
            else
                COMPREPLY=( $(compgen -d -- "$cur") )
                # 디렉토리 뒤에 / 붙이기
                local i
                for i in "${!COMPREPLY[@]}"; do
                    COMPREPLY[$i]="${COMPREPLY[$i]}/"
                done
                compopt -o nospace 2>/dev/null
            fi
            ;;
    esac
}

complete -F _harness harness
