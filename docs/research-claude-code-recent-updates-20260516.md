# Claude Code 최근 업데이트 조사 결과

> 조사일: 2026-05-16
> 조사 범위: 사용자가 들었다는 "goal/impact loop" 정체 식별 + 최근 1~2개월 (2026-03 ~ 2026-05) 주요 업데이트
> 출처: 공식 CHANGELOG.md (https://github.com/anthropics/claude-code/blob/main/CHANGELOG.md), 공식 release notes (https://docs.claude.com/en/release-notes/claude-code)

## 개요

사용자가 들었다는 "goal" 또는 "impact loop" 기능의 정체는 **`/goal` 슬래시 커맨드**일 가능성이 가장 높다. 2.1.139 버전에서 추가됐고, "완료 조건(completion condition)을 설정하면 Claude가 그것을 만족할 때까지 턴을 계속 이어가는" 자율 루프 기능이다. 발음/번역 과정에서 "impact loop"으로 잘못 기억됐을 가능성이 높지만, "goal loop"이라는 정식 명칭은 changelog에 존재하지 않는다.

별도로 "루프(loop)"라는 명칭이 들어간 기능으로는 `/loop` 커맨드(2.1.71)가 따로 존재한다. 이는 주어진 인터벌(예: `5m`)마다 프롬프트나 슬래시 커맨드를 반복 실행하는 스케줄러로, `/goal`의 자율 종료 루프와는 성격이 다르다.

## 핵심 식별: goal/impact loop의 정체

- 기능 이름: `/goal` 커맨드
- 한줄 설명: 완료 조건을 지정하면 Claude가 그 조건이 충족될 때까지 여러 턴에 걸쳐 작업을 계속 진행하는 자율 작업 루프. 진행 중 elapsed/turns/tokens가 오버레이 패널로 라이브 표시된다.
- 출시 버전: 2.1.139
- 출처: GitHub CHANGELOG.md (raw evidence 아래)
- 작동 환경: interactive, `-p` (print/headless), Remote Control 모두 지원

Raw evidence (CHANGELOG.md 인용):

> ## 2.1.139
> - Added agent view (Research Preview): a single list of every Claude Code session — running, blocked on you, or done. Run `claude agents` to get started. See https://code.claude.com/docs/en/agent-view
> - Added `/goal` command: set a completion condition and Claude keeps working across turns until it's met. Works in interactive, `-p`, and Remote Control. Shows live elapsed/turns/tokens as an overlay panel

추가 단서로 2.1.140에서 `/goal`의 버그 픽스("Fixed `/goal` silently hanging when `disableAllHooks` or `allowManagedHooksOnly` is set")가 등장하므로 실제 출시된 기능임이 교차 확인된다.

"impact loop"이라는 정확한 이름은 공식 changelog와 release notes 어디에도 등장하지 않는다 (검색 결과 0건). 추측: 사용자가 들은 "goal" → 한국어 발음 변형 또는 영문 청취 오인으로 "impact"으로 기억된 정황으로 보인다. 또는 영문 커뮤니티에서 별칭으로 부르는 사례가 있을 수 있으나 공식 명칭이 아님.

## 최근 Claude Code 주요 업데이트 (2.1.71 ~ 2.1.142 발췌)

CHANGELOG에는 정확한 출시 날짜가 표기돼 있지 않다 (버전 번호만 기재). 따라서 "출시일"은 "확인 불가"로 표기하고, 버전 번호로만 기재한다. 2.1.142가 changelog의 최상단 (가장 최근)이며, 사용자 환경이 2026-05-16임을 감안하면 이 범위가 지난 1~2개월에 해당할 가능성이 높지만 단정할 수 없다.

| 버전 | 기능 | 한줄 설명 |
|------|------|----------|
| 2.1.142 | `claude agents` 디스패치 플래그 확장 | `--add-dir`, `--settings`, `--mcp-config`, `--plugin-dir`, `--permission-mode`, `--model`, `--effort`, `--dangerously-skip-permissions` 추가 |
| 2.1.142 | Fast mode = Opus 4.7 | Fast 모드 기본 모델이 Opus 4.6에서 4.7로 변경. `CLAUDE_CODE_OPUS_4_6_FAST_MODE_OVERRIDE=1`로 4.6 고정 가능 |
| 2.1.139 | `/goal` 커맨드 | 완료 조건 만족까지 자율 작업 루프 (사용자 질문의 정답) |
| 2.1.139 | Agent view (Research Preview) | `claude agents` 실행 시 모든 Claude Code 세션을 단일 목록으로 표시 (running/blocked/done) |
| 2.1.139 | `/scroll-speed` | 마우스 휠 스크롤 속도 튜닝, 라이브 미리보기 |
| 2.1.139 | 훅 `args: string[]` exec 폼 | 쉘 없이 직접 spawn하여 경로 따옴표 처리 불필요 |
| 2.1.139 | 훅 `continueOnBlock` | `PostToolUse`에서 거부 사유를 모델에 피드백하고 턴 계속 |
| 2.1.139 | Subagent 헤더 | API 요청에 `x-claude-code-agent-id` / `x-claude-code-parent-agent-id` 헤더 추가, OTEL span에도 attribute 추가 |
| 2.1.111 | Opus 4.7 xhigh + Auto mode | `xhigh` effort 레벨 (high와 max 사이) 추가, Max 구독자 Auto mode 지원, `/effort` 인터랙티브 슬라이더 |
| 2.1.111 | `/less-permission-prompts` 스킬 | 트랜스크립트를 스캔해 read-only Bash/MCP 호출에 대한 권한 allowlist 제안 |
| 2.1.111 | `/ultrareview` | 클라우드에서 멀티에이전트 병렬 코드리뷰. `<PR#>` 인자로 GitHub PR 리뷰 가능 |
| 2.1.71 | `/loop` 커맨드 | 인터벌(예: `5m`)마다 프롬프트/슬래시 커맨드 반복 실행하는 스케줄러 |
| 2.1.71 | Cron 스케줄링 도구 | 세션 내 반복 프롬프트를 위한 cron 도구 |
| 2.1.72 | `ExitWorktree` 도구 + `CLAUDE_CODE_DISABLE_CRON` 환경변수 | EnterWorktree 세션 종료, cron 작업 중단 |
| 2.1.63 | `/simplify`, `/batch` 번들 슬래시 커맨드 + HTTP 훅 | HTTP 훅으로 JSON POST/응답, 워크트리 간 프로젝트 설정 공유 |

추가 변경 사항 (간략):
- `--channels` (research preview): MCP 서버가 세션으로 메시지 푸시 가능
- `/web-setup`: GitHub App 연결 교체 시 경고
- Sonnet 4.5 → 4.6 자동 마이그레이션 (Pro/Max/Team Premium)
- `disableSkillShellExecution` 설정: 스킬/슬래시 커맨드 내 inline shell 실행 차단
- `effort` frontmatter: 스킬/슬래시 커맨드별 effort 레벨 override
- Plugins root-level `SKILL.md` 자동 surfacing (2.1.142)

## 환경 단서와의 일치 여부

사용자 환경에 노출된 기능들이 모두 changelog에서 확인된다:
- `/loop`: 2.1.71에서 추가됨 (확인)
- `/schedule`: changelog의 "remote agents / routines / cron" 맥락에서 등장 (정확한 출시 버전은 검색 결과로 단정 불가, "추가 조사 필요")
- `ScheduleWakeup`: `/loop`이 "scheduling redundant wakeups"라는 표현으로 2.1.140 버그픽스에 등장. `/loop`/`/schedule`의 내부 도구로 추정 (확정 어려움)
- `/simplify`: 2.1.63 (확인)
- `/fewer-permission-prompts`: 정식 명칭은 `/less-permission-prompts`. 2.1.111에서 추가됨

## 확인 불가 / 추가 조사 필요 항목

- "impact loop"이라는 정확한 이름의 기능: 공식 source에서 확인 불가. 추정컨대 `/goal`의 별칭 또는 청취 오인.
- 각 버전의 정확한 캘린더 출시일: CHANGELOG.md에 날짜가 표기되어 있지 않아 확정 불가. release notes 공식 페이지에서도 동일.
- `/schedule` 커맨드의 정식 출시 버전: 다수 changelog 항목에 등장하지만 "Added /schedule"이라는 도입 라인을 본 검색에서 특정하지 못함.
- `ScheduleWakeup` 도구의 정식 사양/문서: changelog 외 공식 문서 페이지 미확인.

## 출처

- Anthropic 공식 release notes 페이지: https://docs.claude.com/en/release-notes/claude-code
- GitHub raw CHANGELOG.md: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- Agent view 안내: https://code.claude.com/docs/en/agent-view (changelog에서 인용)
- Fast mode 문서: https://code.claude.com/docs/en/fast-mode (2.1.36 changelog에서 인용)

조사 방법: context-mode MCP의 `fetch_and_index`로 GitHub raw CHANGELOG.md 전체 (209 sections, 약 298KB)를 인덱싱한 뒤 FTS5 BM25 검색으로 핵심 키워드를 추출. 모든 인용은 raw output에서 직접 발췌.
