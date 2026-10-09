# hoodcat-harness

[oh-my-claudecode](https://github.com/Yeachan-Heo/oh-my-claudecode)(OMC) 위에 얹어 쓰는 개인용 Claude Code 확장 팩이다. 스킬·규칙·훅·스크립트를 **전역**(`~/.claude`, `~/.local/bin`)에 설치하고, 제거할 때는 설치한 것만 정확히 지운다.

> 2026-09-21 이전의 이 저장소는 프로젝트마다 에이전트 7개·스킬 12개를 복사해 넣는 멀티에이전트 하네스였다. 그 체계는 철회했고 OMC로 대체했다. 옛 구조는 git 히스토리와 `docs/`에 남아 있다.

## 요구 사항

| 의존성 | 용도 |
|--------|------|
| [Claude Code](https://claude.com/claude-code) | `claude plugin` 명령으로 OMC 설치 |
| `jq` | 매니페스트·settings.json 편집 (필수) |
| Node.js / `npm` | OMC CLI(`oh-my-claude-sisyphus`) 설치 |
| `rsync` | 전사 파이프라인 동기화 |
| `uv`, `ffmpeg` | 전사 파이프라인 실행. 없으면 macOS는 `brew`로 자동 설치, 그 외 OS는 설치 명령을 안내 |

## 설치

```bash
git clone git@github.com:Hoodcat2255/hoodcat-harness.git
cd hoodcat-harness
./install.sh            # OMC 확인·설치 → 개인 팩 설치
./install.sh --dry-run  # 바뀔 내용만 출력
./install.sh --skip-omc # OMC 단계 생략
./install.sh --skip-whisper       # 전사 파이프라인 단계 생략 (스킬만 설치)
./install.sh --skip-whisper-deps  # 코드 동기화만 하고 의존성 설치·uv sync는 생략
```

`install.sh`는 세 단계로 동작한다.

1. **OMC** — OMC README의 Quick Start 절차를 따른다. 이미 설치돼 있으면 건너뛴다.
   - `claude plugin marketplace add https://github.com/Yeachan-Heo/oh-my-claudecode`
   - `claude plugin install oh-my-claudecode@omc --scope user`
   - `npm i -g oh-my-claude-sisyphus@latest` (`omc` CLI)
   - 위 단계 중 하나라도 새로 설치했으면 `omc setup`
2. **개인 팩** — 아래 항목을 복사하고 `~/.claude/.hoodcat-pack.json` 매니페스트에 기록한다.

3. **전사 파이프라인** — `whisper/`를 `~/Projects/whisper`(`HOODCAT_WHISPER_DIR`로 변경)에 동기화하고 `uv sync`를 실행한다. youtube-digest·recording-notes 스킬이 이 경로를 쓴다.
   - 대상의 `output/`(전사 결과), `.venv/`, `.omc/`, `experiments/`는 보존하고, 저장소에서 사라진 코드 파일은 지운다.
   - 대상 디렉토리에 `transcribe.py` 없이 다른 파일이 있으면 whisper 사본이 아니라고 보고 건너뛴다.
   - 의존성: `uv`·`ffmpeg`가 없으면 macOS는 `brew install`, 그 외 OS는 경고와 설치 명령만 출력한다. macOS는 `--pdf`용으로 `chrome-headless-shell`을 `npx @puppeteer/browsers`로 `~/.cache/chrome-headless-shell`에 설치한다 (GUI 로그인 없이는 데스크톱 Chrome이 headless로도 뜨지 않는다).
   - 전사 엔진은 Linux(NVIDIA)에서 faster-whisper(CUDA), Apple Silicon에서 mlx-whisper를 자동 선택한다. 자세한 내용은 `whisper/README.md`.

다시 실행하면 이전 설치를 먼저 지우고 현재 저장소 상태로 맞춘다. 이 팩이 설치하지 않은 파일과 경로가 겹치면 `~/.claude/.hoodcat-pack-backup/<시각>/`에 백업하고 덮어쓴다. `settings.json`은 수정 전에 `settings.json.hoodcat-bak`으로 복사된다.

## 설치되는 항목

| 저장소 | 설치 위치 | 내용 |
|--------|-----------|------|
| `skills/deepresearch/` | `~/.claude/skills/deepresearch/` | 도메인 적응형 심층 조사. 한국 규제 도메인은 Tier 1(법령·공고문) 우선, 재검증 모드, `docs/research-*.md` 저장 |
| `rules/*.md` | `~/.claude/rules/hoodcat/` | 자료 등급(Tier 1~4), 인식적 정직(자신감 라벨·반박 시 Self-Check), 안티패턴 3종. 모든 세션에 자동 적용 |
| `hooks/dr-prefix.sh` | `~/.claude/hooks/hoodcat/` | UserPromptSubmit. 프롬프트가 `dr:`로 시작하면 deepresearch 스킬 호출 지시를 주입. `hooks/hooks.json`에 선언된 이벤트로 `settings.json`에 등록 |
| `skills/youtube-digest/` | `~/.claude/skills/youtube-digest/` | 유튜브 영상(또는 영상 파일)을 요약·정리·학습 노트로. 전사 파이프라인 사용 |
| `skills/recording-notes/` | `~/.claude/skills/recording-notes/` | 회의·인터뷰·통화·음성메모 녹음을 회의록·노트로. 개인정보 마스킹. 전사 파이프라인 사용 |
| `scripts/*` | `~/.local/bin/` | 개인 CLI 스크립트 (현재 없음) |
| `whisper/` | `~/Projects/whisper/` | 전사 파이프라인 (yt-dlp → OCR → Whisper → Claude 교정 → 문서). 매니페스트에는 경로만 기록하고 제거 대상이 아니다 |

경로는 `CLAUDE_CONFIG_DIR`, `HOODCAT_BIN_DIR`, `HOODCAT_WHISPER_DIR` 환경변수로 바꿀 수 있다. `HOODCAT_WHISPER_DIR`를 바꾸면 설치되는 두 스킬 문서의 경로도 그 값으로 치환된다.

### `dr:` 접두어

프롬프트를 `dr:`로 시작하면(대소문자 무관, 전각 콜론 `：`도 인식) 나머지를 주제로 `deepresearch` 스킬을 호출한다.

```
dr: 2026년 청약 제도 변경
dr: 재검증: <의심받은 주장>
```

훅은 호출 지시를 주입할 뿐이고 실제 호출은 모델이 한다. 호출을 보장하려면 `/deepresearch <주제>`를 쓴다.

## 제거

```bash
./uninstall.sh            # 매니페스트에 적힌 스킬·규칙·훅·스크립트와 훅 등록만 제거
./uninstall.sh --dry-run
```

OMC와 전사 파이프라인 디렉토리(`~/Projects/whisper`, 전사 결과 포함)는 제거하지 않는다. 필요하면 파이프라인 디렉토리는 직접 지운다. OMC는 `claude plugin uninstall oh-my-claudecode@omc`와 `npm rm -g oh-my-claude-sisyphus`를 직접 실행한다.

## 새 항목 추가

- 스킬: `skills/<이름>/SKILL.md`. `agent`를 생략하면 `general-purpose`로 실행된다. OMC 스킬·에이전트와 역할이 겹치면 만들지 않는다.
- 규칙: `rules/<이름>.md`.
- 훅: `hooks/<스크립트>.sh`를 만들고 `hooks/hooks.json`에 `{"event": "...", "script": "...", "matcher": "..."}`를 추가한다.
- 스크립트: `scripts/<이름>`에 실행 파일을 둔다.
- 전사 파이프라인: `whisper/`에서 직접 고친다 (`cd whisper && uv run pytest -q`). 설치된 `~/Projects/whisper`에서 고친 내용은 다음 설치 때 덮어써진다.

추가한 뒤 `./install.sh --skip-omc`로 다시 설치하면 반영된다.

## 테스트

```bash
bash tests/test-install.sh          # 임시 디렉토리에서 설치·재설치·제거·충돌 백업·전사 파이프라인 동기화 검증
(cd whisper && uv run pytest -q)    # 전사 파이프라인 단위 테스트
(cd whisper && uv run ruff check ytscribe transcribe.py tests && uv run pyright ytscribe transcribe.py)   # 린트·타입 검사 (버전은 dev 그룹에 고정)
bash tests/test-dr-prefix.sh        # dr: 접두어 매칭 규칙 (LC_ALL=C·UTF-8 로캘)
```

## 디렉토리 구조

```
install.sh / uninstall.sh   설치·제거
lib/common.sh               경로, 로그, dry-run, settings.json 훅 편집
skills/ rules/ hooks/ scripts/   설치 대상
whisper/                    전사 파이프라인 (~/Projects/whisper로 동기화)
tests/                      테스트
docs/                       조사·결정 기록 (옛 하네스 시절 포함)
```
