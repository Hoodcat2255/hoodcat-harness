# hoodcat-harness 프로젝트 셸 함수
#
# 설치: 아래 줄을 ~/.zshrc 또는 ~/.bashrc에 추가
#   source /path/to/hoodcat-harness/shell-functions.sh
#
# 함수:
#   newproj <name>  - 새 프로젝트 생성 + git init + harness 설치 + cd
#   goproj <name>   - 기존 프로젝트로 이동
#
# 환경변수:
#   HARNESS_PROJECTS_DIR  - 프로젝트 디렉토리 (기본값: ~/Projects)
#   HARNESS_SOURCE_DIR    - harness 소스 디렉토리 (설치 시 자동 설정)

# --- 설정 ---

# 프로젝트 디렉토리: 사용자 오버라이드 또는 기본값
HARNESS_PROJECTS_DIR="${HARNESS_PROJECTS_DIR:-${HOME}/Projects}"

# harness 소스 디렉토리: 사용자 오버라이드 또는 자동 감지
if [[ -z "${HARNESS_SOURCE_DIR:-}" ]]; then
    # 이 스크립트의 위치에서 자동 감지 (bash/zsh 호환)
    if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
        HARNESS_SOURCE_DIR="$(command cd "$(command dirname "${BASH_SOURCE[0]}")" && command pwd -P)"
    elif [[ -n "${(%):-%x}" ]]; then
        # zsh: %x는 스크립트 경로를 반환
        HARNESS_SOURCE_DIR="$(command cd "$(command dirname "${(%):-%x}")" && command pwd -P)"
    else
        HARNESS_SOURCE_DIR=""
    fi
fi

# --- 함수 ---

newproj() {
    local name="$1"

    if [[ -z "${name:-}" ]]; then
        echo "Usage: newproj <project-name>" >&2
        return 1
    fi

    local project_dir="${HARNESS_PROJECTS_DIR}/${name}"

    # 프로젝트 베이스 디렉토리가 없으면 생성
    if [[ ! -d "$HARNESS_PROJECTS_DIR" ]]; then
        command mkdir -p "$HARNESS_PROJECTS_DIR"
    fi

    if [[ -d "$project_dir" ]]; then
        echo "[ERROR] Directory already exists: ${project_dir}" >&2
        return 1
    fi

    command mkdir -p "$project_dir"
    cd "$project_dir" || return 1

    command git init

    # harness가 사용 가능하면 설치
    if [[ -n "${HARNESS_SOURCE_DIR:-}" && -f "${HARNESS_SOURCE_DIR}/harness.sh" ]]; then
        "${HARNESS_SOURCE_DIR}/harness.sh" install . --force
    fi

    echo "Project created: ${project_dir}"
}

goproj() {
    local name="${1:-}"

    # 인자 없이 호출: 프로젝트 디렉토리로 이동
    if [[ -z "$name" ]]; then
        if [[ ! -d "$HARNESS_PROJECTS_DIR" ]]; then
            echo "[ERROR] Projects directory does not exist: ${HARNESS_PROJECTS_DIR}" >&2
            return 1
        fi
        cd "$HARNESS_PROJECTS_DIR" || return 1
        return 0
    fi

    local project_dir="${HARNESS_PROJECTS_DIR}/${name}"

    if [[ ! -d "$project_dir" ]]; then
        echo "[ERROR] Project not found: ${project_dir}" >&2
        return 1
    fi

    cd "$project_dir" || return 1
}

# --- 탭 완성 ---

# 헬퍼: $HARNESS_PROJECTS_DIR 하위 디렉토리 이름 나열
_harness_list_projects() {
    if [[ -d "$HARNESS_PROJECTS_DIR" ]]; then
        for d in "${HARNESS_PROJECTS_DIR}"/*/; do
            [[ -d "$d" ]] && command basename "$d"
        done
    fi
}

if [[ -n "${ZSH_VERSION:-}" ]]; then
    # --- Zsh 완성 ---

    _harness_project_completion() {
        local projects=()
        local name
        while IFS= read -r name; do
            [[ -n "$name" ]] && projects+=("$name")
        done < <(_harness_list_projects)

        if (( ${#projects[@]} > 0 )); then
            compadd -a projects
        fi
    }

    # compdef는 비대화형 셸이나 compinit 이전에는 사용 불가할 수 있음
    (( ${+functions[compdef]} )) && compdef _harness_project_completion newproj goproj || true

elif [[ -n "${BASH_VERSION:-}" ]]; then
    # --- Bash 완성 ---

    _harness_project_completion_bash() {
        local cur="${COMP_WORDS[COMP_CWORD]}"
        local projects
        projects="$(_harness_list_projects)"
        COMPREPLY=( $(compgen -W "$projects" -- "$cur") )
    }

    complete -F _harness_project_completion_bash newproj
    complete -F _harness_project_completion_bash goproj
fi
