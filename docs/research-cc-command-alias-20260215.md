# cc 명령어의 유래, alias 위험성, Claude Code alias 관행 조사 결과

> 조사일: 2026-02-15

## 개요

`cc`는 Unix/Linux에서 C 컴파일러를 호출하는 표준 명령어로, 1970년대 Unix 초기부터 존재해온 역사적인 명령어이다. 현대 Linux 시스템에서는 대부분 GCC(GNU Compiler Collection)의 심볼릭 링크로 존재한다. Claude Code 사용자들이 `alias cc='claude'`를 설정할 경우 C 컴파일러 기능을 사용할 수 없게 되므로 주의가 필요하다. 커뮤니티에서 권장하는 Claude Code alias는 `c`이다.

## 상세 내용

### 1. Unix/Linux에서 cc 명령어의 역사와 역할

#### 역사적 배경

`cc`는 "C Compiler"의 약자로, 1970년대 초기 Unix 시스템에서 Dennis Ritchie가 C 언어를 개발한 이후 기본 C 컴파일러 호출 명령어로 사용되어 왔다. 초기 Unix에서는 AT&T의 독점 C 컴파일러가 `cc`라는 이름으로 제공되었다.

- **1970년대**: Unix V5/V6에서 `cc`는 PDP-11용 C 컴파일러를 호출하는 명령어
- **1980년대**: 각 Unix 벤더(Sun, HP, IBM, DEC)가 자체 C 컴파일러를 `cc`로 제공
- **1987년**: GCC(GNU C Compiler) 등장. 자유 소프트웨어 운동의 일환으로 Richard Stallman이 개발
- **1990년대~현재**: Linux 배포판에서 GCC가 표준 컴파일러가 되면서 `cc`는 `gcc`의 심볼릭 링크로 전환

#### POSIX 표준에서의 위치

POSIX 표준(IEEE Std 1003.1)은 `c99` 명령어를 C 컴파일러의 표준 인터페이스로 정의한다. `cc`는 POSIX 표준에 명시적으로 정의되지 않았지만, 사실상의 표준(de facto standard)으로 거의 모든 Unix 계열 시스템에 존재한다.

#### 현대 시스템에서의 구현

현재 시스템(Ubuntu 24.04)에서의 `cc` 심볼릭 체인:

```
/usr/bin/cc -> /etc/alternatives/cc -> /usr/bin/gcc -> gcc-13
```

- `cc`는 Debian/Ubuntu의 `update-alternatives` 시스템을 통해 관리됨
- alternatives 시스템 덕분에 gcc, clang 등 여러 컴파일러 중 하나를 `cc`로 연결 가능
- `c89`, `c99` 등 표준 버전별 명령어도 alternatives로 관리됨

#### cc를 사용하는 주요 소프트웨어

많은 빌드 시스템이 C 컴파일러를 찾을 때 `cc`를 기본값으로 사용한다:

| 빌드 시스템 | cc 사용 방식 |
|------------|-------------|
| **GNU Autotools** | `./configure`가 `CC` 환경변수 미설정 시 `cc`를 먼저 탐색 |
| **CMake** | `CC` 환경변수 미설정 시 `cc`를 기본 C 컴파일러로 사용 |
| **Make** | 내장 규칙에서 `CC = cc`가 기본값 |
| **Go** | CGO가 활성화된 경우 `CC` 환경변수 또는 `cc`를 사용 |
| **Python** | C 확장 빌드 시 `cc`를 기본 컴파일러로 탐색 |
| **Node.js (node-gyp)** | 네이티브 애드온 빌드 시 `cc`를 사용 |
| **Rust** | `cc` crate가 링커/컴파일러 탐색 시 `cc`를 먼저 검색 |

### 2. cc를 alias로 덮어쓸 때의 위험성

#### 직접적인 위험

1. **C/C++ 컴파일 불가**: `alias cc='claude'`를 설정하면 셸에서 `cc` 명령 호출 시 claude가 실행됨. C 소스코드를 직접 컴파일할 수 없게 됨.

2. **빌드 시스템 장애 (제한적)**: 셸 alias는 일반적으로 비대화형(non-interactive) 셸에서는 확장되지 않는다. 따라서:
   - `make`, `cmake`, `./configure` 등이 **서브프로세스로** `cc`를 호출할 때는 alias가 적용되지 않음 (이들은 `/usr/bin/cc`를 직접 호출)
   - 그러나 **셸 스크립트에서 `cc`를 직접 호출**하는 경우 `shopt -s expand_aliases`가 설정되어 있으면 alias가 적용될 수 있음

3. **디버깅 혼란**: `cc` 명령이 예상과 다르게 동작하여, 다른 도구나 스크립트의 문제를 진단할 때 혼란을 야기할 수 있음

#### 실제 영향도 분석

| 시나리오 | 영향 | 위험도 |
|---------|------|--------|
| 대화형 셸에서 `cc foo.c` 실행 | Claude Code가 실행됨 | 높음 |
| Makefile에서 `$(CC)` 사용 | 영향 없음 (Make가 직접 실행) | 없음 |
| `./configure` 실행 | 영향 없음 (비대화형 서브프로세스) | 없음 |
| `go build` (CGO 사용) | 영향 없음 (Go가 직접 실행) | 없음 |
| 셸 함수 내에서 `cc` 호출 | alias 확장됨 | 중간 |
| SSH 원격 명령 | 기본적으로 영향 없음 (비대화형) | 없음 |

**핵심**: 셸 alias는 대화형 셸에서만 기본 확장되므로, 빌드 시스템에 미치는 영향은 제한적이다. 그러나 C/C++ 개발자이거나 네이티브 확장을 자주 빌드하는 경우, 대화형 셸에서 `cc`를 직접 쓰려 할 때 문제가 된다.

#### Claude Code 이슈 사례

`anthropics/claude-code` 리포지토리의 이슈 #20746 "[BUG] Token usage missing from Models stats when Claude Code is launched via shell alias"는 셸 alias로 Claude Code를 실행할 때 토큰 사용량 통계가 누락되는 버그를 보고했다. 이는 alias를 통한 실행이 일부 기능에 영향을 줄 수 있음을 시사한다.

### 3. Claude Code 사용자들이 흔히 쓰는 alias

#### 커뮤니티 권장 alias

`everything-claude-code` 프로젝트(Anthropic 해커톤 우승작, GitHub 고평가 리소스)에서 권장하는 alias:

```bash
alias c='claude'
```

이 외에도 관련 alias들이 함께 설정되는 패턴:

```bash
alias c='claude'      # Claude Code 실행
alias gb='github'     # GitHub CLI
alias co='code'       # VS Code
alias q='cd ~/Desktop/projects'  # 프로젝트 디렉토리 이동
```

#### alias 선택 시 고려사항

| alias | 장점 | 단점 | 충돌 가능성 |
|-------|------|------|------------|
| `c` | 가장 짧음, 입력이 빠름 | 일부 시스템에서 `c` 명령이 존재할 수 있음 | 낮음 (대부분의 시스템에서 `c`는 미사용) |
| `cc` | "Claude Code"의 약자로 직관적 | **C 컴파일러와 충돌** | **높음** |
| `cl` | 짧고 기억하기 쉬움 | Windows에서 MSVC 컴파일러(`cl.exe`)와 혼동 | 낮음 (Linux에서) |
| `claude` | 이미 기본 명령어명 | alias 필요 없음 | 없음 |
| `cld` | 고유하고 충돌 없음 | 직관성 다소 떨어짐 | 매우 낮음 |

#### Claude Code의 /alias 기능 요청

`anthropics/claude-code` 이슈 #14576에서 `/alias` 커맨드 기능 요청이 있었다. Claude Code 내부에서 커맨드 alias를 설정하는 기능으로, 셸 alias와는 별개의 기능이다. 현재(2026-02-15) 이 기능은 `enhancement` 라벨이 붙어 있으며 `stale` 상태이다.

## 코드 예제

### 안전한 Claude Code alias 설정

```bash
# ~/.bashrc 또는 ~/.zshrc에 추가

# 권장: 'c'를 Claude Code alias로 사용
alias c='claude'

# 'cc'는 사용하지 않는 것을 권장 (C 컴파일러와 충돌)
# alias cc='claude'  # 비권장!

# Claude Code를 특정 모드로 실행하는 alias 예시
alias ch='claude --headless'      # 헤드리스 모드
alias cp='claude --print'         # 출력 전용 모드 (주의: cp와 충돌!)
alias ccode='claude'              # 충돌 없는 긴 alias
```

### cc alias를 써도 안전한 경우 확인

```bash
# cc가 현재 시스템에서 어디를 가리키는지 확인
which cc
ls -la $(which cc)

# cc를 직접 사용하는 빌드 도구가 있는지 확인
# (비대화형 셸에서는 alias가 적용되지 않으므로 빌드 시스템 자체는 안전)
make -p | grep "^CC ="

# 만약 cc alias를 쓰더라도 원래 cc에 접근하려면:
\cc foo.c         # 백슬래시로 alias 우회
command cc foo.c  # command 내장 명령으로 alias 우회
/usr/bin/cc foo.c # 절대경로로 직접 호출
```

## 주요 포인트

- **cc는 1970년대부터 존재한 Unix의 핵심 명령어**이다. C Compiler의 약자로, 현대 Linux에서는 대부분 GCC의 심볼릭 링크로 존재한다.
- **cc를 alias로 덮어쓰면 대화형 셸에서 C 컴파일이 불가능**해진다. 다만 빌드 시스템(Make, CMake 등)은 비대화형 서브프로세스에서 cc를 호출하므로 alias의 영향을 받지 않는다.
- **Claude Code 커뮤니티에서 권장하는 alias는 `c`** (한 글자)이다. `cc`는 C 컴파일러와 충돌하므로 권장하지 않는다.
- **셸 alias를 통한 Claude Code 실행은 일부 기능에 영향**을 줄 수 있다 (토큰 통계 누락 버그 사례 - 이슈 #20746).
- **alias 충돌을 피하면서 cc에 접근하는 방법**은 `\cc`, `command cc`, `/usr/bin/cc` 등이 있으나, 혼란을 방지하려면 애초에 `c`를 사용하는 것이 가장 안전하다.

## 출처

- [Everything Claude Code - The Longform Guide (alias 권장 패턴)](https://github.com/affaan-m/everything-claude-code/blob/main/the-longform-guide.md)
- [anthropics/claude-code #20746 - Shell alias로 실행 시 토큰 통계 누락 버그](https://github.com/anthropics/claude-code/issues/20746)
- [anthropics/claude-code #14576 - /alias 커맨드 기능 요청](https://github.com/anthropics/claude-code/issues/14576)
- [GCC Manual - GNU Compiler Collection](https://gcc.gnu.org/onlinedocs/)
- [POSIX.1-2017 - c99 유틸리티 명세](https://pubs.opengroup.org/onlinepubs/9699919799/utilities/c99.html)
- [Debian Alternatives System](https://wiki.debian.org/DebianAlternatives)
