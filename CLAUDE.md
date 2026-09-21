# CLAUDE.md

## 프로젝트 개요

oh-my-claudecode(OMC) 위에 얹는 개인용 Claude Code 확장 팩. 스킬·규칙·훅·스크립트를 전역(`~/.claude`, `~/.local/bin`)에 설치·제거하는 `install.sh`/`uninstall.sh`와 그 설치 대상 파일을 관리한다. 사용법과 구조는 `README.md` 참조.

2026-09-21에 프로젝트별 멀티에이전트 하네스(에이전트 7개, 스킬 12개, dispatch, 공유 컨텍스트)를 철회하고 이 구조로 바꿨다. `docs/`의 옛 문서는 그 시절 기록이다.

## 작업 규칙

- 설치 대상은 `skills/`, `rules/`, `hooks/`(+ `hooks/hooks.json`), `scripts/`뿐이다. 여기에 넣은 파일은 모두 전역에 설치되므로 개인용이 아닌 것은 넣지 않는다.
- 자체 에이전트는 만들지 않는다. 에이전트가 필요하면 OMC 에이전트를 쓴다. OMC와 역할이 겹치는 스킬도 만들지 않는다.
- 설치 도구는 매니페스트(`~/.claude/.hoodcat-pack.json`)에 적힌 항목만 지운다. 사용자·OMC 파일을 건드리는 변경은 하지 않는다.
- 규칙과 훅은 `rules/hoodcat/`, `hooks/hoodcat/` 네임스페이스에 설치된다. 파일 안에서 다른 규칙을 참조할 때는 설치 후 경로(`~/.claude/rules/hoodcat/...`)나 같은 폴더 상대 이름을 쓴다.
- 스크립트는 macOS 기본 `/bin/bash` 3.2에서 동작해야 한다 (연관 배열, `${var,,}`, 빈 배열 `"${a[@]}"` + `set -u` 금지).
- 훅은 어떤 경우에도 `exit 0`으로 끝나 세션을 막지 않는다.

## 검증

셸 스크립트를 바꾼 뒤에는 반드시 실행한다. 판단은 exit code로 한다.

```bash
/bin/bash tests/test-install.sh
/bin/bash tests/test-notify-telegram.sh
```

## 문서 작성 규칙

리서치 결과는 `docs/research-[주제]-YYYYMMDD.md` (필수 섹션: 개요, 상세 내용, 주요 포인트, 출처).
