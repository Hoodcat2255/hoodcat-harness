# harness.sh install 시 git init + 브랜치/커밋 자동화 판단 결과

> 판단일: 2026-02-09

## 결정 요약

**권고**: **부분 추가 (후보 B)** - git init까지만 자동화하고, 기존 repo에는 브랜치 생성 + 커밋까지 수행
**확신도**: 중간-높음 - 업계 관행과 실용성이 뒷받침하지만, 커밋 메시지/브랜치 네이밍 정책은 프로젝트마다 달라 과도한 자동화는 리스크가 있다

## 결정 대상

`harness.sh install` 실행 시 다음 git 작업을 자동으로 수행할 것인가?
1. 대상 디렉토리가 git repo가 아니면 `git init`
2. 이미 git repo이면 브랜치를 생성하여 harness 파일을 커밋

## 현재 상태 분석

현재 `harness.sh install`은:
- rsync로 파일 복사
- sisyphus.json 초기화
- 런타임 디렉토리 생성
- settings.local.json 복사
- .gitignore 업데이트
- .harness-meta.json 기록

**git 관련 작업은 전혀 없음**. 설치 후 사용자가 수동으로 `git add` / `git commit`을 해야 한다.

## 후보 분석

### A. 전체 자동화 (git init + 브랜치 + 커밋)

설치 스크립트가 모든 git 작업을 수행:
- git repo가 없으면: `git init` → `git add .claude/` → `git commit`
- git repo가 있으면: `git checkout -b harness/install-YYYYMMDD` → `git add .claude/` → `git commit`

- **장점**:
  - 원클릭 설치 경험 - 설치 즉시 버전 관리 시작
  - 기존 repo에서 롤백 가능 - 브랜치가 있으므로 `git checkout -` / `git branch -D`로 원복 가능
  - create-react-app 등 주요 scaffold 도구들이 이 패턴을 사용 (git init + initial commit)
- **단점**:
  - 커밋 메시지 스타일이 프로젝트 컨벤션과 맞지 않을 수 있음
  - 브랜치 네이밍 정책 충돌 가능 (예: `harness/install-20260209` vs 프로젝트의 `feature/` 접두사)
  - git config (user.name, user.email)가 설정 안 되어 있으면 커밋 실패
  - staging 영역에 이미 있는 변경사항과 혼재될 위험
  - `--force` 모드에서 사용자 동의 없이 git history가 변경됨
- **적합한 경우**: 새 프로젝트에 harness를 처음 설치하는 경우

### B. 조건부 자동화 (권고)

git repo 존재 여부에 따라 다르게 동작:
- git repo가 **없으면**: `git init`만 수행 (커밋은 안 함)
- git repo가 **있으면**: 브랜치 생성 → 파일 추가 → 커밋 (사용자 확인 후)
- git repo가 있고 **dirty 상태면**: 경고만 출력, git 작업 스킵

- **장점**:
  - 새 프로젝트: git init으로 버전 관리 기반을 깔아줌 (첫 커밋은 사용자가)
  - 기존 프로젝트: 브랜치에 격리되어 메인 브랜치를 건드리지 않음
  - dirty 상태 감지로 기존 작업 보호
  - 사용자 확인 단계가 있어 `--force`가 아닌 이상 안전
- **단점**:
  - 코드 복잡도 증가 (30-50줄 추가)
  - git 상태별 분기 로직 필요
- **적합한 경우**: 대부분의 사용 시나리오

### C. 자동화하지 않기 (현 상태 유지)

- **장점**:
  - 가장 단순 - 현 코드 변경 없음
  - git 정책 충돌 가능성 0
  - 사용자가 완전한 통제권을 가짐
- **단점**:
  - 설치 후 수동 git 작업 필요 (잊기 쉬움)
  - 기존 repo에서 롤백이 어려움 (어떤 파일이 harness 것인지 추적 어려움)
  - .gitignore에 추가된 항목도 커밋되지 않은 채 방치
- **적합한 경우**: 스크립트를 최소한으로 유지하고 싶을 때

## 평가 매트릭스

| 기준 | A. 전체 자동화 | B. 조건부 자동화 | C. 미적용 |
|------|--------------|----------------|----------|
| 사용자 편의성 | 높음 | 높음 | 낮음 |
| 안전성 (기존 repo 보호) | 중간 | 높음 | 높음 (건드리지 않으니까) |
| 롤백 용이성 | 높음 | 높음 | 낮음 |
| 구현 복잡도 | 40-60줄 | 30-50줄 | 0줄 |
| 엣지 케이스 리스크 | 높음 | 중간 | 없음 |
| 업계 관행 부합 | 높음 (CRA 패턴) | 높음 | 낮음 |
| git 정책 충돌 리스크 | 높음 | 낮음 | 없음 |

## 트레이드오프

- **A를 선택하면**: 최고의 UX를 얻지만, git config 미설정/dirty 상태/커밋 정책 충돌 등 엣지 케이스를 모두 처리해야 한다.
- **B를 선택하면**: 안전성과 편의성의 균형을 얻지만, 조건 분기 로직이 복잡해진다. 새 repo에서는 커밋 없이 init만 하므로 사용자가 첫 커밋을 직접 하는 약간의 불편이 있다.
- **C를 선택하면**: 코드 추가 없이 유지할 수 있지만, 설치 후 git 커밋을 잊으면 harness 파일이 추적되지 않는 상태로 방치된다.

## 최종 권고

### 주요 권고: 후보 B (조건부 자동화)

다음 로직을 `cmd_install()` 끝부분에 추가한다:

```
설치 완료 후:
├── git repo가 아닌 경우:
│   ├── "git init을 실행하시겠습니까?" (confirm)
│   ├── git init
│   └── "첫 커밋은 직접 해주세요" 안내
├── git repo이고 clean 상태:
│   ├── "harness/install 브랜치를 만들어 커밋하시겠습니까?" (confirm)
│   ├── git checkout -b harness/install-YYYYMMDD
│   ├── git add .claude/ .gitignore
│   └── git commit -m "feat: hoodcat-harness 설치"
├── git repo이고 dirty 상태:
│   └── 경고: "커밋되지 않은 변경이 있습니다. git 작업을 건너뜁니다."
└── --force 모드:
    └── 동일 로직이지만 confirm 없이 진행 (dirty면 스킵 유지)
```

### 핵심 안전장치

1. **dirty 감지 필수**: `git status --porcelain`이 비어있지 않으면 git 작업을 절대 수행하지 않는다
2. **git config 확인**: `user.name`/`user.email`이 없으면 커밋을 시도하지 않고 안내 메시지 출력
3. **confirm 기본**: `--force`가 아니면 항상 사용자 확인을 거친다
4. **브랜치 이름 충돌**: 동일 이름 브랜치가 있으면 타임스탬프로 구분 (`harness/install-20260209-143022`)
5. **update 명령에도 적용**: update 시에는 `harness/update-YYYYMMDD` 브랜치에 변경사항 커밋

### `cmd_install()`에 추가할 함수 개요

```bash
setup_git_tracking() {
    local target="$1"

    # git 존재 확인
    if ! command -v git &>/dev/null; then
        log_warn "git이 설치되어 있지 않습니다. git 설정을 건너뜁니다."
        return 0
    fi

    if ! git -C "$target" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then
        # Case 1: git repo가 아닌 경우
        if confirm "git 저장소를 초기화하시겠습니까?"; then
            if dry_run_guard "git init"; then
                git -C "$target" init
                log_info "git 저장소 초기화 완료"
                echo -e "${YELLOW}[참고]${NC} 첫 커밋은 직접 수행해주세요: git add . && git commit -m 'Initial commit'"
            fi
        fi
        return 0
    fi

    # Case 2/3: 이미 git repo인 경우
    local status
    status="$(git -C "$target" status --porcelain)"
    if [[ -n "$status" ]]; then
        # Dirty 상태
        log_warn "커밋되지 않은 변경사항이 있습니다. git 작업을 건너뜁니다."
        log_warn "설치된 파일을 수동으로 커밋해주세요."
        return 0
    fi

    # git config 확인
    if ! git -C "$target" config user.name &>/dev/null || \
       ! git -C "$target" config user.email &>/dev/null; then
        log_warn "git user.name/user.email이 설정되지 않았습니다. 커밋을 건너뜁니다."
        return 0
    fi

    # Clean 상태 - 브랜치 생성 및 커밋 제안
    if confirm "harness 설치를 별도 브랜치에 커밋하시겠습니까?"; then
        local branch="harness/install-$(date +%Y%m%d)"
        # 브랜치 이름 충돌 처리
        if git -C "$target" show-ref --verify --quiet "refs/heads/${branch}"; then
            branch="harness/install-$(date +%Y%m%d-%H%M%S)"
        fi

        if dry_run_guard "git checkout -b ${branch} && commit"; then
            local original_branch
            original_branch="$(git -C "$target" branch --show-current)"

            git -C "$target" checkout -b "$branch"
            git -C "$target" add .claude/ .gitignore
            git -C "$target" commit -m "feat: hoodcat-harness 설치"

            log_info "브랜치 '${branch}'에 커밋 완료"
            echo -e "${YELLOW}[참고]${NC} 원래 브랜치로 돌아가려면: git checkout ${original_branch}"
            echo -e "${YELLOW}[참고]${NC} 메인에 병합하려면: git checkout ${original_branch} && git merge ${branch}"
        fi
    fi
}
```

### 조건부 권고

- **팀 프로젝트에 배포하는 경우**: `--no-git` 옵션을 추가하여 git 작업을 완전히 건너뛸 수 있게 한다
- **CI/CD에서 사용하는 경우**: `--force` + `--no-git` 조합으로 파일 복사만 수행
- **새 프로젝트에만 사용하는 경우**: A(전체 자동화)로 단순화해도 무방하나, 확장성을 위해 B를 유지하는 것이 낫다

## 출처

- [create-react-app git init 자동화 토론](https://github.com/facebook/create-react-app/issues/1244) - CRA가 git init + initial commit을 자동으로 수행하는 패턴
- [Yeoman generator-git-init](https://github.com/iamstarkov/generator-git-init) - scaffold 도구의 git init 자동화 플러그인 패턴
- [Git init 공식 문서](https://git-scm.com/docs/git-init) - 기존 repo에서 재실행 시 동작
- [dotfiles.github.io](https://dotfiles.github.io/tutorials/) - dotfiles 설치 스크립트 패턴
- [Atlassian - dotfiles bare repo 패턴](https://www.atlassian.com/git/tutorials/dotfiles) - bare repo 기반 설정 관리
- [Atlassian - 브랜치 안전 패턴](https://www.atlassian.com/git/tutorials/using-branches) - 수정 전 브랜치 생성 안전 패턴
- [git-rollback-branch](https://github.com/angstwad/git-rollback-branch) - 브랜치 기반 롤백 개념
