#compdef harness
# zsh completion for harness
# 설치: install.sh가 자동으로 설치합니다.

_harness() {
    local -a commands=(
        'install:대상 디렉토리에 harness 설치'
        'update:설치된 harness를 최신 버전으로 업데이트'
        'delete:설치된 harness 삭제'
        'status:설치 상태 확인'
    )

    local -a options=(
        '(-f --force -y --yes)'{-f,--force,-y,--yes}'[확인 프롬프트 스킵]'
        '(-n --dry-run)'{-n,--dry-run}'[실제 변경 없이 표시만]'
        '(-v --verbose)'{-v,--verbose}'[상세 로그 출력]'
        '(-h --help)'{-h,--help}'[도움말 표시]'
    )

    _arguments -s \
        '1:command:->commands' \
        '2:directory:_directories' \
        $options

    case "$state" in
        commands)
            _describe 'command' commands
            ;;
    esac
}

_harness "$@"
