# /ultrareview vs /team-review 비교 조사

> 조사일: 2026-05-16
> 조사자: researcher (deepresearch skill)
> 목적: hoodcat-harness Phase 2 항목 5(외부 cloud 리뷰와 로컬 team-review 분기 전략) 진행 가능 여부 판단

## 개요

`/ultrareview`는 Claude Code 2.1.111에서 도입된 **클라우드 기반 멀티에이전트 코드 리뷰** 슬래시 커맨드다.
사용자 터미널이 아닌 "Claude Code on the web" 원격 샌드박스에서 여러 reviewer agent를 병렬로 띄워
독립적으로 발견·재현·검증한 버그만 보고한다. `/review`(로컬, single-pass)와 의도적으로 한 쌍을 이루며,
가격은 Pro/Max 1회성 무료 3회 + 이후 리뷰당 약 \$5~\$20 (extra usage 과금). 사용자의 로컬 `team-review`는
완전히 다른 카테고리(로컬 멀티렌즈, 토큰 plan 내 소모)다.
**결론: Phase 2 항목 5 진행 PASS (사실 충분, 일부 미공개 영역만 추정으로 표기).**

## 상세 내용

### 1. 공식 정의 (1차 사실)

CHANGELOG 2.1.111 entry (raw 원문):

```
- Added `/ultrareview` for running comprehensive code review in the cloud using
  parallel multi-agent analysis and critique — invoke with no arguments to review
  your current branch, or `/ultrareview <PR#>` to fetch and review a specific
  GitHub PR
```

출처: <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> (section 2.1.111)

공식 문서 (claude.com docs mirror) 핵심 정의:

> Ultrareview is a deep code review that runs on Claude Code on the web infrastructure.
> When you run `/ultrareview`, Claude Code launches a fleet of reviewer agents in a
> remote sandbox to find bugs in your branch or pull request.

출처: <https://code.claude.com/docs/en/ultrareview> (mirror: <https://github.com/oadank/openclaw-wiki-lancedb/blob/main/claude-code-docs/ultrareview.md>)

### 2. 입력 범위와 fetch 메커니즘

| 인자 | 동작 | 소스 |
|------|------|------|
| 없음 | 현재 브랜치 ↔ default branch 간 diff + uncommitted/staged 작업트리 포함을 번들링 후 원격 샌드박스 업로드 | docs |
| `<PR#>` | 원격 샌드박스가 GitHub에서 PR을 직접 clone (로컬 워킹트리 미사용). `github.com` remote 필수 | docs |
| `claude ultrareview origin/main` | base branch 지정 가능 (subcommand 한정으로 명시됨) | doc diff cc394fe |

raw 인용:

> Without arguments, ultrareview reviews the diff between your current branch and
> the default branch, including any uncommitted and staged changes in your working
> tree. Claude Code bundles the repository state and uploads it to a remote sandbox
> for the review.

> In PR mode, the remote sandbox clones the pull request directly from GitHub rather
> than bundling your local working tree. PR mode requires a `github.com` remote on
> the repository.

출처: ultrareview-official-doc

### 3. 멀티에이전트 구성 (공식 문구 그대로)

공식 문서는 단계 수·이름·역할을 **수치적으로 명시하지 않는다**. 다음 두 문장이 전부다:

> Claude Code launches a fleet of reviewer agents in a remote sandbox

> Higher signal: every reported finding is independently reproduced and verified,
> so the results focus on real bugs rather than style suggestions
> Broader coverage: many reviewer agents explore the change in parallel, which
> surfaces issues that a single-pass review can miss

따라서 사실은 두 가지뿐:
- **병렬 reviewer agent fleet** (수량 비공개)
- **independent reproduction + verification** 단계 존재 (critique 단계의 실체)

추정 (raw evidence 없음):
- "agent 수 = 3~5"이나 "stage = analysis → critique → triage" 같은 구조는 공식 출처에 없다.
  third-party 재현 시도(grandamenium/local-ultrareview 등)는 "3-stage Opus pipeline"으로
  설명하지만 이는 비공식 추정이다.

출처: ultrareview-official-doc; third-party repos <https://github.com/grandamenium/local-ultrareview>, <https://github.com/th9rain/ultrareview>

### 4. 출력 형식

**Interactive (slash command)**:
> A review typically takes 5 to 10 minutes. The review runs as a background task,
> so you can keep working in your session, start other commands, or close the
> terminal entirely.

> Use `/tasks` to see running and completed reviews, open the detail view for a
> review, or stop a review that is in progress. Stopping a review archives the
> cloud session, and partial findings are not returned. When the review finishes,
> the verified findings appear as a notification in your session. Each finding
> includes the file location and an explanation of the issue so you can ask Claude
> to fix it directly.

핵심:
- **background task**로 실행. 터미널 차단 없음. 종료해도 됨.
- `/tasks`로 진행/완료 조회, 상세 보기, 중지
- 완료 시 **세션 내 notification + finding 목록 (file location + explanation)**
- **GitHub PR comment로 자동 게시되지는 않는다** (공식 문서에 그런 동작 기술 없음). 결과는 Claude Code UI 안.
- 중지 시 부분 결과 미반환 (cloud session archive)

**Non-interactive (`claude ultrareview` subcommand, doc diff cc394fe)**:
- stdout: 포맷된 findings (또는 `--json`이면 raw `bugs.json`)
- stderr: progress + live session URL
- exit code: 0 (완료, finding 유무 무관), 1 (실패/timeout)
- 기본 timeout 30분, `--timeout <minutes>`로 조정

출처: ultrareview-official-doc, ultrareview-doc-diff (cc394fe)

### 5. 비용/플랜 모델 (공식 표 그대로)

|          | `/review`                      | `/ultrareview`                                                |
| -------- | ------------------------------ | ------------------------------------------------------------- |
| Runs     | locally in your session        | remotely in a cloud sandbox                                   |
| Depth    | single-pass review             | multi-agent fleet with independent verification               |
| Duration | seconds to a few minutes       | roughly 5 to 10 minutes                                       |
| Cost     | counts toward normal usage     | free runs, then roughly \$5 to \$20 per review as extra usage |
| Best for | quick feedback while iterating | pre-merge confidence on substantial changes                   |

추가 raw 인용:

> Pro and Max subscribers receive three free ultrareview runs to try the feature.
> These three runs are a one-time allotment per account, do not refresh, and
> expire on May 5, 2026. After you use all three, or after the free run period
> ends, each review is billed to extra usage and typically costs \$5 to \$20
> depending on the size of the change. A run counts once the remote session starts,
> so a review that you stop early or that fails to complete still uses a free run.
> For a paid review, extra usage is billed only for the portion that ran.

> Because ultrareview always bills as extra usage outside the free runs, your
> account or organization must have extra usage enabled before you can launch a
> paid review. If extra usage is not enabled, Claude Code blocks the launch and
> links you to the billing settings where you can turn it on. You can also run
> `/extra-usage` to check or change your current setting.

핵심:
- 무료 한도: 계정당 3회 (영구 1회성, 2026-05-05 만료)
- 이후: 리뷰당 ~\$5~\$20 (변경 크기 의존), **extra usage 활성화 필수**
- 무료 회차도 "원격 세션 시작 시점에" 1회 차감 (중지/실패도 카운트)
- 유료 회차는 "실제 실행한 부분"만 과금

출처: ultrareview-official-doc

### 6. 실패/제한 케이스

| 케이스 | 동작 | 출처 |
|--------|------|------|
| API key only (Claude.ai 미인증) | 실행 차단. `/login` 요구 | docs |
| Amazon Bedrock / Google Cloud Vertex AI / Microsoft Foundry 경유 | 사용 불가 | docs |
| Zero Data Retention 활성화 조직 | 사용 불가 | docs |
| extra usage 비활성화 | 유료 회차 launch 차단 + billing settings 링크 | docs |
| PR 모드인데 `github.com` remote 없음 | 사용 불가 (조건만 명시, 에러 메시지는 미문서화) | docs |
| 네트워크/원격 세션 오류 | subcommand는 exit 1 | doc diff |
| 30분 timeout 초과 | subcommand는 exit 1 | doc diff |
| 사용자 중지 | 세션 archive, partial findings 미반환, 무료 회차는 차감됨 | docs |
| 크래시 (실 운영 사례) | 다수 보고됨 (Issue #55547, #55290, #54705, #55324, #58999) — 부분 finding 미보존이 일관된 경험 | github issues |

운영 안정성: 공식 issues 5건 이상이 "Ultrareview crash/stopped/failed" 패턴이다. 도입(2.1.111) 직후
체감 안정성이 완성형은 아니다. raw 인용:

- "[BUG] Ultrareview crash" #55547
- "[BUG] Ultrareview Stopped" #55290
- "ultrareview crashed before producing findings" #58999
- "[BUG] /ultrareview failed TWICE" #54705, #55324

CHANGELOG 후속 버전에 ultrareview 직접 수정 entry는 검색 시점에 명시적 식별 안 됨 (Refine with
Ultraplan 관련 fix는 별건).

출처: ultrareview-official-doc, GitHub issues anthropics/claude-code

### 7. 호출 컨텍스트 (Main Agent vs 서브에이전트 vs -p)

| 모드 | 사용 가능 여부 | 메커니즘 |
|------|----------------|----------|
| Interactive Main Agent | ✅ | `/ultrareview [PR#]` 슬래시 커맨드 |
| Non-interactive (`-p` 또는 CI) | ✅ | `claude ultrareview [PR#|base-branch]` **subcommand**. blocking, stdout 파싱 가능 |
| 서브에이전트 (Task 안에서) | ⚠ 추정 (raw evidence 없음) | 슬래시 커맨드는 Main Agent 전용 라우팅이 일반적. 서브에이전트는 `claude ultrareview` 서브커맨드를 Bash로 실행해야 할 가능성이 높다. 공식 문서에서 "subagent 안에서 /ultrareview 호출"을 다루는 문구는 발견되지 않음. |

핵심:
- **CI/script 통합 경로는 `claude ultrareview` subcommand로 공식 지원**. 이게 `-p` 등가물.
- subcommand 호출 자체가 "billing/terms prompt에 대한 consent"로 간주된다고 명시되어 있어, 자동화 시 비용 책임이 명확해진다.

출처: ultrareview-doc-diff (cc394fe), ultrareview-official-doc

### 8. 우리 team-review와의 차별 비교

`.claude/skills/team-review/`는 hoodcat-harness 내부 스킬로, 로컬에서 reviewer/security/architect 에이전트를 병렬 호출하는 멀티렌즈 리뷰다(harness.md 참조). 직접 비교:

| 항목 | `/ultrareview` (Anthropic) | `/team-review` (hoodcat-harness) |
|------|---------------------------|-----------------------------------|
| 실행 위치 | Claude Code on the web 원격 샌드박스 | 로컬 Claude Code 세션 (현재 머신) |
| 멀티에이전트 | fleet of reviewer agents (수 비공개) + independent verification(critique) | reviewer + security + architect 3종 (코드 변경 시 architect, 보안 민감 시 security 추가) |
| 입력 | current branch vs default branch diff + working tree, 또는 `<PR#>` (GitHub clone), 또는 base branch (subcommand) | 대상 파일/변경 설명을 Orchestrator에 인자로 전달 (PR fetch 자체는 별도 단계) |
| 출력 위치 | Claude Code UI notification + `/tasks` 상세, 또는 stdout(JSON 가능, stderr는 progress) | Main Agent 응답 (Orchestrator 결과 회수). 파일 저장은 없음(skill 정의상) |
| GitHub PR comment 자동 게시 | ❌ (공식 문서에 그런 동작 없음) | ❌ |
| 동기성 | background (5~10분), 세션 종료해도 OK; subcommand는 blocking | foreground (대화 차단), 단일 응답으로 회수 |
| 비용 | Pro/Max 1회성 free 3회 → 이후 \$5~\$20/run (extra usage) | 단일 리뷰 대비 약 3배 토큰 (harness.md 명시), plan 내 토큰 소모 |
| 검증 깊이 | 별도 verifier agent가 finding 재현/검증 → "real bugs only" 강조 | 렌즈별 독립 의견 (자체 verification 단계는 명시 없음) |
| 사용 가능 백엔드 | Claude.ai 직접 인증 한정 (Bedrock/Vertex/Foundry 불가, ZDR 조직 불가) | 어떤 백엔드든 Claude Code가 도는 환경이면 동작 |
| CI/non-interactive | `claude ultrareview` subcommand 제공 (exit code, --json, --timeout) | Orchestrator 경유 → CI 통합 시 Claude Code SDK 별도 호출 필요 |
| 실패 시 행동 | crash/stop 시 partial finding 미반환, 무료 회차는 차감 | Orchestrator 응답 안에서 부분 결과 회수 가능 |

### 9. 호환·역할 분리 권고

두 도구는 대체재가 아니라 **시점-기반 보완재**다:
- **iteration 중**: `/team-review` (반복적, 토큰 plan 내, 즉시 피드백). harness가 이미 채택.
- **pre-merge confidence**: `/ultrareview` (변경 크고 위험 높은 PR에 대한 외부 verification 레이어).
  과금이 \$ 단위이므로 회수당 결정점이 명확해야 함.

기존 harness.md 가이드("`/team-review`: 대규모/고위험 변경에만 사용, 단순 변경은 Task(reviewer)")의 위쪽 한 단계에
`/ultrareview`를 두는 그림이 가장 자연스럽다.

## 코드 예제

CI/script 통합 예시 (raw doc diff 인용):

```bash
claude ultrareview
claude ultrareview 1234
claude ultrareview origin/main
```

JSON payload 추출:

```bash
claude ultrareview --json --timeout 20 > bugs.json
# stdout: bugs.json
# stderr: progress + live session URL
# exit 0: 완료 (finding 유무 무관)
# exit 1: launch 실패 / remote error / timeout
```

## 주요 포인트

- `/ultrareview`(2.1.111)는 클라우드 원격 샌드박스에서 reviewer agent fleet + independent verification으로 실행되는 별도 과금 제품이다. 무료 3회 후 \$5~\$20/리뷰.
- 입력: 인자 없음 = current vs default branch + uncommitted; `<PR#>` = GitHub 직접 clone(github.com remote 필수); subcommand는 base branch 인자도 받음.
- 출력: interactive는 background task → `/tasks`에서 조회/중지, 완료 시 세션 notification. non-interactive `claude ultrareview`는 stdout(formatted 또는 `--json`), exit 0/1, stderr에 progress.
- 백엔드 제약: Claude.ai 인증 필수, Bedrock/Vertex/Foundry/ZDR 조직 불가, extra usage 활성화 필수.
- 멀티에이전트 구체 구조(에이전트 수, stage 이름)는 **공식 비공개**. "fleet + critique" 두 사실만 raw 인용 가능.
- harness `/team-review`와는 시점/비용/백엔드/검증깊이가 다른 보완재. pre-merge 게이트로 한 단계 위에 둘 만하다.
- 운영 안정성: 다수의 crash 이슈가 오픈 상태(#55547, #55290, #54705, #55324, #58999). 자동화에 사용 시 실패 핸들링과 재시도 한도 필요.
- 서브에이전트 안에서 `/ultrareview` 슬래시 자체를 호출 가능한지는 공식 문서에 명시 없음. **`claude ultrareview` subcommand를 Bash로 호출**하는 경로가 사실상의 자동화 인터페이스.

## 사실 vs 추정 분리

**사실 (raw 인용 보유)**:
- 도입 버전 (2.1.111), CHANGELOG 정의 문구
- 입력 규칙 3종, 백엔드 제약, 인증 요구
- 비용 표 (\$5~\$20, free 3회, 2026-05-05 만료)
- subcommand 동작 (stdout/stderr/exit/--json/--timeout 30분)
- background task + `/tasks` 흐름, 중지 시 partial 미반환
- crash 이슈 다수 존재

**추정 (공식 raw 미발견)**:
- agent 수와 단계 이름 (third-party 재현물의 "3-stage" 등은 비공식 가설)
- 서브에이전트(Task 컨텍스트) 안에서 슬래시 커맨드로 `/ultrareview` 호출 가부 — subcommand 우회가 안전
- "impact loop" 같은 별칭의 공식성 (현재까지 발견된 raw 0건; 별건 `/goal` 또는 `/loop`로 추정. 이전 리서치에서 확인됨)

## Phase 2 항목 5 진행 판정

**PASS** — 정책 결정에 필요한 사실 (시점/비용/입력/출력/실패 처리/백엔드 제약/CI 인터페이스)이 모두 raw 인용 가능 수준으로 확보됨.

조건부 후속(블루프린트 작성 단계에서 한 번 더 검증):
- 서브에이전트 안에서의 슬래시 호출 가부 → 실제 호출 테스트 1회로 확인 (또는 subcommand 강제 정책으로 우회).
- 멀티에이전트 내부 구조 → 정책 결정에 본질적이지 않음(우리는 결과만 소비). 블루프린트 본문은 "fleet + verification" 표현으로 충분.

## 출처

공식
- CHANGELOG: <https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md> (2.1.111 entry)
- docs (mirror): <https://code.claude.com/docs/en/ultrareview> via <https://github.com/oadank/openclaw-wiki-lancedb/blob/58161355b598ea50eea7de19755214017339800f/claude-code-docs/ultrareview.md>
- docs diff (subcommand 추가 변경): <https://github.com/fornewid/claude-code-docs-changelog/blob/69fab5682314d5b7a08c5e5f9f07f1e819a29b9a/pages/diffs/cc394fe_ultrareview.txt>
- release notes index: <https://docs.claude.com/en/release-notes/claude-code>

운영 안정성 (anthropics/claude-code Issues)
- <https://github.com/anthropics/claude-code/issues/55547> [BUG] Ultrareview crash
- <https://github.com/anthropics/claude-code/issues/55290> [BUG] Ultrareview Stopped
- <https://github.com/anthropics/claude-code/issues/58999> ultrareview crashed before producing findings
- <https://github.com/anthropics/claude-code/issues/55324> [BUG] /ultrareview failed TWICE
- <https://github.com/anthropics/claude-code/issues/54705> [BUG] /ultrareview failed TWICE

써드파티 (비공식, 참고용)
- <https://github.com/grandamenium/local-ultrareview> — "Local /ultrareview skill — 3-stage Opus pipeline" (재현 시도, 단계 수는 비공식 추정)
- <https://github.com/th9rain/ultrareview> — "Recreate Claude Code–style multi-agent ultrareview"
- <https://github.com/scarr7981/ultrareview-mcp> — MCP로 외부 LLM에 자기 작업 리뷰 의뢰

내부 비교 대상
- `.claude/harness.md` (team-review 정의)
- `.claude/skills/team-review/SKILL.md` (구현)
