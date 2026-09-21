# hoodcat-harness

[oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)(OMC) 위에 얹어 쓰는 개인용 Claude Code 확장 팩이다. 스킬·규칙·훅·스크립트를 **전역**(`~/.claude`, `~/.local/bin`)에 설치하고, 제거할 때는 설치한 것만 정확히 지운다.

> 2026-09-21 이전의 이 저장소는 프로젝트마다 에이전트 7개·스킬 12개를 복사해 넣는 멀티에이전트 하네스였다. 그 체계는 철회했고 OMC로 대체했다. 옛 구조는 git 히스토리와 `docs/`에 남아 있다.

## 요구 사항

| 의존성 | 용도 |
|--------|------|
| [Claude Code](https://claude.com/claude-code) | `claude plugin` 명령으로 OMC 설치 |
| `jq` | 매니페스트·settings.json 편집 (필수) |
| Node.js / `npm` | OMC CLI(`oh-my-claude-sisyphus`) 설치 |
| `curl` | 텔레그램 알림 훅 |

## 설치

```bash
git clone git@github.com:Hoodcat2255/hoodcat-harness.git
cd hoodcat-harness
./install.sh            # OMC 확인·설치 → 개인 팩 설치
./install.sh --dry-run  # 바뀔 내용만 출력
./install.sh --skip-omc # OMC 단계 생략
```

`install.sh`는 두 단계로 동작한다.

1. **OMC** — OMC README의 Quick Start 절차를 따른다. 이미 설치돼 있으면 건너뛴다.
   - `claude plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode`
   - `claude plugin install oh-my-claudecode@omc --scope user`
   - `npm i -g oh-my-claude-sisyphus@latest` (`omc` CLI)
   - 위 단계 중 하나라도 새로 설치했으면 `omc setup`
2. **개인 팩** — 아래 항목을 복사하고 `~/.claude/.hoodcat-pack.json` 매니페스트에 기록한다.

다시 실행하면 이전 설치를 먼저 지우고 현재 저장소 상태로 맞춘다. 이 팩이 설치하지 않은 파일과 경로가 겹치면 `~/.claude/.hoodcat-pack-backup/<시각>/`에 백업하고 덮어쓴다. `settings.json`은 수정 전에 `settings.json.hoodcat-bak`으로 복사된다.

## 설치되는 항목

| 저장소 | 설치 위치 | 내용 |
|--------|-----------|------|
| `skills/deepresearch/` | `~/.claude/skills/deepresearch/` | 도메인 적응형 심층 조사. 한국 규제 도메인은 Tier 1(법령·공고문) 우선, 재검증 모드, `docs/research-*.md` 저장 |
| `rules/*.md` | `~/.claude/rules/hoodcat/` | 자료 등급(Tier 1~4), 인식적 정직(자신감 라벨·반박 시 Self-Check), 안티패턴 3종. 모든 세션에 자동 적용 |
| `hooks/notify-telegram.sh` | `~/.claude/hooks/hoodcat/` | SubagentStop 시 텔레그램 알림. `hooks/hooks.json`에 선언된 이벤트로 `settings.json`에 등록 |
| `scripts/*` | `~/.local/bin/` | 개인 CLI 스크립트 (현재 없음) |

경로는 `CLAUDE_CONFIG_DIR`, `HOODCAT_BIN_DIR` 환경변수로 바꿀 수 있다.

### 텔레그램 알림 설정

`~/.claude/.env`(전역) 또는 프로젝트 루트 `.env`(우선)에 적는다. 없으면 훅은 아무것도 하지 않는다. 템플릿은 `.env.example`.

```
HARNESS_TG_BOT_TOKEN=...
HARNESS_TG_CHAT_ID=...
```

## 제거

```bash
./uninstall.sh            # 매니페스트에 적힌 스킬·규칙·훅·스크립트와 훅 등록만 제거
./uninstall.sh --dry-run
```

OMC는 제거하지 않는다. 필요하면 `claude plugin uninstall oh-my-claudecode@omc`와 `npm rm -g oh-my-claude-sisyphus`를 직접 실행한다.

## 새 항목 추가

- 스킬: `skills/<이름>/SKILL.md`. `agent`를 생략하면 `general-purpose`로 실행된다. OMC 스킬·에이전트와 역할이 겹치면 만들지 않는다.
- 규칙: `rules/<이름>.md`.
- 훅: `hooks/<스크립트>.sh`를 만들고 `hooks/hooks.json`에 `{"event": "...", "script": "...", "matcher": "..."}`를 추가한다.
- 스크립트: `scripts/<이름>`에 실행 파일을 둔다.

추가한 뒤 `./install.sh --skip-omc`로 다시 설치하면 반영된다.

## 테스트

```bash
bash tests/test-install.sh          # 임시 디렉토리에서 설치·재설치·제거·충돌 백업 검증
bash tests/test-notify-telegram.sh  # 가짜 curl로 알림 메시지 검증
```

## 디렉토리 구조

```
install.sh / uninstall.sh   설치·제거
lib/common.sh               경로, 로그, dry-run, settings.json 훅 편집
skills/ rules/ hooks/ scripts/   설치 대상
tests/                      테스트
docs/                       조사·결정 기록 (옛 하네스 시절 포함)
```
