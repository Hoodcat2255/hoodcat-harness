# harness.sh를 bin에 심볼릭 링크로 등록하는 방안 판단 결과

> 판단일: 2026-02-09

## 결정 요약

**권고**: **하라. ~/.local/bin 심볼릭 링크 방식으로 등록**
**확신도**: 높음 - 이미 반쯤 되어 있고, 구현 비용이 거의 없으며, 이점이 명확하다

## 결정 대상

`harness.sh`를 시스템 PATH에 등록하여 어디서든 `harness` 명령으로 실행 가능하게 하는 install 메커니즘을 추가할 것인가?

## 현재 상태 분석

현재 이미 다음과 같은 상태:

```
~/.local/bin/harness → /home/hoodcat/Projects/hoodcat-harness/harness.sh  (있음)
/home/hoodcat/Projects/my-harness/harness  (있음, PATH에서 먼저 잡힘)
```

**문제점**: `which harness`가 이전 프로젝트(`my-harness`)의 harness를 먼저 찾는다. `~/.local/bin/harness` 심볼릭 링크는 있지만, `my-harness` 디렉토리가 PATH에 직접 등록되어 있어 우선순위에서 밀린다.

## 후보 분석

### A. ~/.local/bin 심볼릭 링크 (권고)

```bash
ln -sfn "$PWD/harness.sh" ~/.local/bin/harness
```

- **장점**:
  - XDG 표준 준수 - `~/.local/bin`은 사용자별 실행파일의 표준 위치
  - sudo 불필요 - 사용자 권한으로 관리 가능
  - 소스 수정 즉시 반영 - 심볼릭 링크이므로 `harness.sh`를 수정하면 바로 적용
  - `harness.sh`의 `SCRIPT_DIR` 계산이 심볼릭 링크를 올바르게 추적 (`BASH_SOURCE[0]` + `cd "$(dirname ...)"` 패턴)
  - 이미 반쯤 설정되어 있음 (링크 존재, PATH 충돌만 해결하면 됨)
- **단점**:
  - `~/.local/bin`이 PATH에 있어야 함 (대부분의 현대 Linux 배포판에서 기본 포함)
  - my-harness와의 PATH 우선순위 충돌 해결 필요
- **적합한 경우**: 개인 개발 환경, 단일 사용자

### B. /usr/local/bin에 설치

```bash
sudo ln -sfn "$PWD/harness.sh" /usr/local/bin/harness
```

- **장점**:
  - 시스템 전역 접근 가능
  - PATH에 이미 확실히 포함됨
- **단점**:
  - sudo 필요 - 개인 스크립트에 과도한 권한
  - 멀티유저 환경이 아니므로 불필요
- **적합한 경우**: 시스템 전역 도구, 여러 사용자가 사용

### C. self-install 명령 추가

`harness.sh`에 `self-install` 서브커맨드를 추가:

```bash
./harness.sh self-install   # ~/.local/bin/harness 심볼릭 링크 생성
./harness.sh self-uninstall # 심볼릭 링크 제거
```

- **장점**:
  - 설치/삭제가 스크립트에 내장되어 일관성 있음
  - README나 도움말에서 바로 안내 가능
  - 업데이트 시에도 심볼릭 링크이므로 재설치 불필요
- **단점**:
  - harness.sh 코드가 약간 늘어남 (10-20줄 수준)
  - self-install이 한 번이면 끝이므로 서브커맨드까지 필요한가?
- **적합한 경우**: 다른 사람에게 배포하거나, 재설치 시나리오가 있을 때

### D. 하지 않기 (현 상태 유지)

- **장점**: 추가 작업 없음
- **단점**:
  - 매번 `./harness.sh` 또는 절대 경로 필요
  - my-harness와의 충돌 미해결
  - 다른 프로젝트 디렉토리에서 실행이 불편

## 평가 매트릭스

| 기준 | A. ~/.local/bin | B. /usr/local/bin | C. self-install | D. 미적용 |
|------|----------------|-------------------|----------------|----------|
| 구현 비용 | 1줄 | 1줄 + sudo | 15줄 | 0 |
| 편의성 | 높음 | 높음 | 높음 | 낮음 |
| 보안/권한 | 적절 | 과도 | 적절 | N/A |
| 배포 용이성 | 수동 | 수동 | 자동 | N/A |
| XDG 준수 | O | X | O | N/A |
| 실전 즉시 사용 | 즉시 | 즉시 | 즉시 | 불편 |

## 트레이드오프

- **A(~/.local/bin)를 선택하면**: 1줄로 끝나는 최소 비용으로 어디서든 `harness` 실행이 가능해지지만, 설치 과정이 수동이며 문서로만 안내해야 한다.
- **C(self-install)를 선택하면**: 깔끔한 UX를 얻지만, 이 기능은 평생 한두 번 쓸 코드에 10-20줄을 투자하는 것이다.
- **D(미적용)를 선택하면**: 아무 것도 안 해도 되지만, 다른 프로젝트에서 작업할 때마다 절대 경로를 기억해야 한다.

## 최종 권고

### 주요 권고: A + C 조합

**1단계 (즉시)**: my-harness PATH 충돌을 해결하고 ~/.local/bin 심볼릭 링크가 동작하게 한다.

현재 문제는 `my-harness` 디렉토리가 PATH에 직접 등록되어 있어 `~/.local/bin/harness`보다 우선순위가 높다는 것이다. 해결 방법:
- `my-harness`의 PATH 등록을 제거하거나
- `~/.local/bin`이 PATH에서 먼저 오도록 순서를 조정

**2단계 (선택)**: `harness.sh`에 `self-install` 커맨드를 추가한다.

```bash
cmd_self_install() {
    local bin_dir="${HOME}/.local/bin"
    local link_path="${bin_dir}/harness"
    local script_path="${SCRIPT_DIR}/harness.sh"

    mkdir -p "$bin_dir"
    ln -sfn "$script_path" "$link_path"
    log_info "심볼릭 링크 생성: ${link_path} → ${script_path}"

    if ! echo "$PATH" | tr ':' '\n' | grep -q "^${bin_dir}$"; then
        log_warn "${bin_dir}이 PATH에 없습니다. shell 설정에 추가하세요:"
        echo "  export PATH=\"\$HOME/.local/bin:\$PATH\""
    fi
}
```

### SCRIPT_DIR 심볼릭 링크 호환성 확인

`harness.sh` 7행의 `SCRIPT_DIR` 계산 방식:
```bash
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
```

이 방식은 `${BASH_SOURCE[0]}`가 심볼릭 링크일 때 **링크가 있는 디렉토리**(`~/.local/bin`)를 반환한다. 이 경우 `SOURCE_CLAUDE_DIR`이 `~/.local/bin/.claude`를 찾게 되어 **실패한다**.

**수정 필요**: 심볼릭 링크를 해석(resolve)하여 실제 스크립트 경로를 얻어야 한다.

```bash
readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
```

`readlink -f`는 심볼릭 링크를 끝까지 추적하여 실제 파일 경로를 반환한다. 이 수정이 없으면 `~/.local/bin/harness` 심볼릭 링크로 실행 시 소스 디렉토리를 찾지 못한다.

### 조건부 권고

- **지금 당장은 A만으로 충분**: `readlink -f` 수정 1줄 + 심볼릭 링크 1줄이면 끝
- **나중에 배포 시나리오가 생기면**: C(self-install) 추가
- **my-harness를 완전히 폐기할 계획이라면**: PATH에서 my-harness 제거가 가장 깔끔

## 즉시 실행 액션

```bash
# 1. harness.sh의 SCRIPT_DIR을 심볼릭 링크 호환으로 수정
# 기존: readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# 수정: readonly SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

# 2. 심볼릭 링크 확인 (이미 있음)
ls -la ~/.local/bin/harness

# 3. PATH 우선순위 확인 후 my-harness 충돌 해결
```

## 출처

- [XDG Base Directory - ~/.local/bin 표준](https://gist.github.com/roalcantara/107ba66dfa3b9d023ac9329e639bc58c)
- [Beginner's Guide to /usr/local/bin](https://dev.to/hbalenda/beginner-s-guide-to-usr-local-bin-4fe2)
- [GNU Stow로 dotfiles 관리하기](https://systemcrafters.net/managing-your-dotfiles/using-gnu-stow/)
- [심볼릭 링크로 프로젝트 관리하기 - DEV Community](https://dev.to/rijultp/organize-your-projects-better-with-symlinks-and-save-time-5gh5)
- [Fedora - ~/.local/bin PATH 논의](https://discussion.fedoraproject.org/t/home-local-bin-in-shell-path-but-not-in-global-profile/156095)
- [Arch Linux - symlink to /usr/local/bin](https://bbs.archlinux.org/viewtopic.php?id=232450)
