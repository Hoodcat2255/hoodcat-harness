# Blueprint: hoodcat-harness × Claude Code 2.1.111~2.1.142 통합

> 작성일: 2026-05-16
> 작성자: researcher (blueprint 스킬)
> 기반 리서치: `docs/research-claude-code-recent-updates-20260516.md`
> 대상 버전: Claude Code 2.1.111 ~ 2.1.142
> **정정일: 2026-05-16 (Phase 0 검증 결과 반영)** — 자세한 내용은 §0 참조.

---

## 0. Phase 0 정정 결과 (2026-05-16)

본 블루프린트 작성 직후 진행한 Phase 0 검증에서 다음 사실이 확정되었다. 이전 본문의 가설/추정 일부가 사실로 갱신되었고, 일부 항목은 정의가 변경되었다.

### 0.1 사용자 환경 확정사항

| 항목 | 가설 (이전) | 정정 (사실) | 검증 근거 |
|------|-------------|-------------|-----------|
| Claude Code 버전 | 미상 (≥2.1.139 가정) | **2.1.142 확정** (2.1.139+ 충족, 2.1.140+ 호환됨, /goal silent hang 무관) | `claude --version` 직접 확인 |
| `disableAllHooks` 사용 여부 | 미상 (마찰 가능성 우려) | **사용 안 함 확정** (7곳 settings 전수 검증, ABSENT) | 글로벌·프로젝트·worktree settings 모두 검토 |
| `allowManagedHooksOnly` 사용 여부 | 미상 | **사용 안 함 확정** (7곳 settings 전수 검증, ABSENT) | 동일 |
| `skipDangerousModePermissionPrompt` | (별도 키워드로 인식 못함) | 일부 settings에 최상위 키로 존재. 단, **CC가 인식하는 경로(`permissions` 하위)가 아니라 최상위라 무시될 가능성** | settings 직접 grep |

사용자가 떠올린 "끄는 설정"의 정체는 hooks 자체를 끄는 옵션이 아니라 `protected paths` 메커니즘 + 위 `skipDangerousModePermissionPrompt: true` 조합으로 추정된다. 어느 쪽이든 hooks 차단 우회 경로가 아니므로 본 블루프린트의 hooks-기반 위임 강제 가정은 그대로 유효하다.

### 0.2 결정사항 채택 결과

| # | 결정 | 채택 결과 |
|---|------|-----------|
| 1 | Phase 0 환경 검증 | **완료**. 위 0.1에 사실 반영 |
| 2 | 항목 2 구현 방식 | **(b) stderr 메시지 UX 개선만** 수행. `continueOnBlock` 도입 안 함 (PreToolUse에 적용 불가하다는 §2.2·§3.2 결론과 일치) |
| 3 | Phase 1 진행 동의 | **Yes**. 즉시 진행 |
| 4 | 항목 4 정의 | **재정의(b)**: 헤더/OTEL 직접 의존 → hook input의 `agent_transcript_path` 디렉토리 구조 추론 기반으로 변경. §0.3 참조 |

### 0.3 항목 4 재정의 (요약)

CHANGELOG의 "subagent header"는 API 헤더와 OTEL span attribute만을 명시하며, hook stdin payload에 `parent_agent_id`가 보장된다고 보기 어렵다. 따라서 항목 4의 구현 모델을 다음과 같이 재정의한다.

- 원래(추정): SubagentStop hook input의 `parent_agent_id` 필드 직접 추출.
- 재정의: SubagentStop hook input에 실제로 존재하는 `agent_transcript_path` 필드의 **디렉토리 패턴(`/subagents/<parent-session>/...`)에서 부모-자식 관계를 추론**.
- 추가 raw evidence (2026-05-16, hooks.log 81건 전수 검증):
  - `SubagentStop` payload에 `agent_transcript_path` 필드가 실재함을 확인.
  - 해당 경로의 `/subagents/` 구조에서 부모 세션 ID를 역추출 가능.
- 본 재정의로 Open Question Q3은 **해소됨**. 별도의 신규 데이터 모델(`_graph.json`)로 진행 가능. 단, 일정상 **Phase 2로 이동**한다 (Phase 1은 항목 2 UX와 항목 1 가이드에 집중).

### 0.4 신규 발견: 항목 2-bis (`enforce-delegation.sh`의 transcript_path 판별 버그)

Phase 0 검증 중에 `enforce-delegation.sh`가 서브에이전트와 Main Agent를 구분하기 위해 사용하는 `transcript_path` 판별 로직에서 버그가 발견되었다. 자세한 사항은 별도 워커가 워크트리에서 진단/패치 진행 중이며, 본 블루프린트에서는 Phase 1에 **항목 2-bis**로 추가한다.

- 영향: Main Agent의 직접 수정 차단이 일부 케이스에서 우회될 가능성, 또는 정상 서브에이전트가 잘못 차단될 가능성.
- 처리: 별도 워커가 fix 진행 중. Phase 1에 통합.

### 0.5 진행 순서 (정정 후)

- **Phase 1 (즉시 진행)**: 항목 2-bis (transcript_path 판별 버그 fix) + 항목 2 (메시지 UX 개선) + 항목 1 (`/goal` 가이드)
- **Phase 2**: 항목 4(b) (`agent_transcript_path` 디렉토리 패턴 추론), 항목 3 (`args` exec 폼), 항목 5 (`/ultrareview` 역할 분리)
- **Phase 3**: 검증·문서화 (변경 없음)

### 0.6 정정 후 핵심 메시지

- 사용자 환경 확정으로 R2 (silent hang) **해소**.
- Phase 1은 즉시 진행 가능.
- 항목 4는 데이터 모델을 변경하여 진행 가능하나 Phase 2로 이동.

---

## 1. 목표 및 범위

### 1.1 통합 목적

Claude Code 2.1.111 ~ 2.1.142 사이에 도입된 신규 기능 중 hoodcat-harness 멀티에이전트 시스템과 직접 시너지가 있는 5종을 반영하여 다음을 달성한다.

- 자율 종료 조건 활용으로 Orchestrator의 적응적 실행 강화 (`/goal`)
- 위임 강제 훅의 사용자 경험 개선 (`continueOnBlock`은 PreToolUse에 적용 불가, 메시지 UX 개선으로 재정의)
- 모든 훅의 인자 escape 안전성 강화 (`args: string[]` exec form)
- 호출 그래프 추적으로 공유 컨텍스트 시스템에 부모-자식 관계 가시화 (subagent 헤더)
- 클라우드 기반 멀티에이전트 리뷰와 로컬 `team-review`의 역할 분리 (`/ultrareview`)

### 1.2 반영 권장 5종

| # | 항목 | 출시 | 우선순위 (정정 후) |
|---|------|------|--------------------|
| 1 | `/goal` 커맨드 활용 가이드 | 2.1.139 | Phase 1 |
| 2 | 훅 메시지 UX 개선 (continueOnBlock 분석 결과) | 2.1.139 | Phase 1 |
| 2-bis | `enforce-delegation.sh` transcript_path 판별 버그 fix (Phase 0 발견) | (해당 없음, 자체 버그) | Phase 1 |
| 3 | 훅 `args: string[]` exec 폼 마이그레이션 | 2.1.139 | Phase 2 |
| 4 | Subagent `agent_transcript_path` 디렉토리 패턴 추론 (정정: 헤더 직접 의존 폐기) | 2.1.139 | ~~Phase 1~~ → **Phase 2** |
| 5 | `/ultrareview` × `team-review` 역할 분리 | 2.1.111 | Phase 2 |

> 정정 표시 안내: 본 표는 §0 Phase 0 검증 결과를 반영한 것이다. 원안에서는 항목 4가 Phase 1이었으나 데이터 모델 재정의로 Phase 2로 이동했고, 신규 항목 2-bis가 추가되었다.

### 1.3 범위 외 (Out of Scope)

다음 항목은 본 블루프린트의 범위에 포함되지 않는다.

- 신규 슬래시 커맨드 자체 구현 (예: `/scroll-speed`, `/simplify`, `/batch` 같은 코어 기능 변경)
- `claude agents` 디스패치 플래그 활용 (2.1.142, 별도 블루프린트로 분리 권장)
- Fast mode 기본 모델 변경 대응 (사용자 환경 설정 영역, 하네스 영향 없음)
- Plugins 시스템과의 통합 (하네스는 plugin이 아닌 `.claude/` 직접 설치 방식)
- HTTP 훅, `--channels` MCP push 등 실험적 기능
- `/loop`, `/schedule`, `ScheduleWakeup` 스케줄러 통합 (`/goal`과 다른 축, 후속 블루프린트로 분리)

---

## 2. 현재 상태 vs 목표 상태

### 2.1 항목 1: `/goal` 커맨드 활용 가이드

| 측면 | 현재 (As-Is) | 목표 (To-Be) |
|------|--------------|--------------|
| 동작 | Orchestrator가 적응적 실행 프로토콜에 따라 부분 실패 시 추가 단계 삽입, 2회 실패 시 사용자에 보고 | `/goal`로 호출되면 완료 조건이 만족될 때까지 자율적으로 턴을 이어감. 진행 중 elapsed/turns/tokens 라이브 오버레이 |
| 호출 위치 | Main Agent가 `Task(orchestrator, ...)`로 fork | (선택) 사용자가 `/goal "조건"`으로 시작하면 Orchestrator가 자율 루프 안에서 동작 |
| 영향 파일 | `.claude/agents/orchestrator.md` | `.claude/agents/orchestrator.md` (자율 종료 조건 절 추가), `.claude/harness.md` (Main Agent 자기검증 체크리스트에 `/goal` 항목 추가) |
| 사용자 UX | 사용자가 매 단계 결과를 확인하고 후속 지시 | "테스트가 모두 통과할 때까지" 같은 완료 조건만 주면 Claude가 자율 진행. 라이브 오버레이로 진행 상황 시각화 |
| 위험 | - | `/goal`이 위임 시스템을 우회할 가능성 (R1 참조). 또한 `disableAllHooks`/`allowManagedHooksOnly` 환경에서는 2.1.140 이전까지 silent hang 발생했음 (raw evidence 확인됨) |

Raw evidence (CHANGELOG.md, 2.1.139):

> Added `/goal` command: set a completion condition and Claude keeps working across turns until it's met. Works in interactive, `-p`, and Remote Control. Shows live elapsed/turns/tokens as an overlay panel

### 2.2 항목 2: 훅 메시지 UX 개선 (continueOnBlock 분석 결과 반영)

| 측면 | 현재 (As-Is) | 목표 (To-Be) |
|------|--------------|--------------|
| 동작 | `enforce-delegation.sh`가 PreToolUse 단계에서 exit 2로 차단, stderr 메시지를 Claude에게 전달 | 차단 동작 유지. 단, 메시지에 위반된 도구/파일/대체 호출 경로를 더 구체적으로 명시하여 Main Agent의 자기교정 비용 감소 |
| `continueOnBlock` 도입 가능성 | N/A | **불가**: `continueOnBlock`은 raw evidence상 `PostToolUse` 전용이며 PreToolUse 차단에는 적용되지 않음. PreToolUse는 그대로 exit 2 유지. (R3 참조) |
| 영향 파일 | `.claude/hooks/enforce-delegation.sh` | `.claude/hooks/enforce-delegation.sh` (stderr 메시지 개선만), 새로운 PostToolUse 훅 도입은 본 Phase 범위 외 |
| 사용자 UX | "Main Agent는 코드를 직접 수정할 수 없습니다. Task(orchestrator, ...)로 위임하세요." | 위반 도구/파일/대체 경로/허용 조건 4가지를 한 메시지로 안내. 예: "Tool=Edit | File=path/to/x.ts | 대체: Task(orchestrator, ...) | 허용되는 경우: 서브에이전트에서만" |
| 위험 | - | 차단 자체를 약화시키지 않도록 stdin/stdout 동작은 그대로. exit 2 + stderr 패턴 유지 |

Raw evidence (CHANGELOG.md, 2.1.139):

> Added hook `continueOnBlock` config option for `PostToolUse` — set to `true` to feed the hook's rejection reason back to Claude and continue the turn

**확인됨**: `continueOnBlock`은 `PostToolUse` 전용이다. **추정 아님**, raw evidence에서 명시.
**확인됨**: 우리의 `enforce-delegation.sh`는 PreToolUse 훅이다 (코드의 `# PreToolUse Hook` 주석에서 확인).
**결론**: 항목 2는 "continueOnBlock 직접 적용"이 아니라 "메시지 UX 개선"으로 재정의된다.

### 2.3 항목 3: 훅 `args: string[]` exec 폼 마이그레이션

| 측면 | 현재 (As-Is) | 목표 (To-Be) |
|------|--------------|--------------|
| 동작 | 모든 훅이 `command: "bash <path>/script.sh"` 형식의 shell 폼으로 등록되어 있다고 추정됨 (`.claude/settings.json` 직접 확인 필요) | exec 폼으로 마이그레이션. `args: ["/abs/path/script.sh"]` 형태로 지정하여 셸 없이 직접 spawn |
| 영향 파일 | `.claude/settings.json` (훅 등록부), `harness.sh` (설치 스크립트의 훅 등록 로직) | 동일. settings.json의 각 hook 항목에 `args` 필드 추가, 또는 `command` 대체 |
| 사용자 UX | 경로에 공백/특수문자 있을 시 셸 escape 누락 위험 | 경로 escape 자동화. 따옴표 처리 불필요 |
| 호환성 | 기존 shell 폼 그대로 동작 | exec 폼은 Claude Code 2.1.139+ 필요. 구버전에선 인식 불가 가능성 (추정, 공식 문서 추가 확인 권장) |

Raw evidence (CHANGELOG.md, 2.1.139):

> Added hook `args: string[]` field (exec form) that spawns the command directly without a shell, so path placeholders never need quoting

### 2.4 항목 4: Subagent 헤더 기반 호출 그래프 추적

| 측면 | 현재 (As-Is) | 목표 (To-Be) |
|------|--------------|--------------|
| 동작 | `shared-context-collect.sh`가 `${AGENT_TYPE}-${AGENT_ID}.md`로 파일명 생성. 부모-자식 관계는 기록되지 않음 | `parent_agent_id`를 헤더 또는 OTEL span attribute에서 받아 공유 컨텍스트에 기록. 호출 그래프 시각화 가능 |
| 영향 파일 | `.claude/hooks/shared-context-collect.sh`, `.claude/hooks/subagent-monitor.sh` | `shared-context-collect.sh`: SubagentStop input에서 `parent_agent_id`를 추출하여 파일 메타데이터 또는 별도 인덱스에 기록. `subagent-monitor.sh`: 로그에 parent 정보 포함 |
| 사용자 UX | 단일 평면 목록의 에이전트 결과 | 트리 구조의 호출 관계 (Orchestrator → coder, reviewer, security 등) |
| 신규성 | - | 현재 시스템에 부재한 신규 기능. 단순 reflection이 아닌 **신규 데이터 모델** 확장 |
| 불확실성 | - | **추정**: SubagentStop hook input JSON에 `parent_agent_id` 필드가 실제로 포함되는지 확인 필요. CHANGELOG에는 "API 헤더와 OTEL attribute"로만 명시됨. hook stdin payload 포맷은 별도 검증 필요 (Open Question Q3 참조) |

Raw evidence (CHANGELOG.md, 2.1.139):

> API requests from subagents now carry `x-claude-code-agent-id` / `x-claude-code-parent-agent-id` headers, and `claude_code.llm_request` OTEL spans include `agent_id` / `parent_agent_id` attributes

**정정 (2026-05-16, Phase 0 검증 결과)**:

- "추정"이었던 hook payload 의존은 폐기되었다. CHANGELOG의 헤더/OTEL은 API·observability 채널 한정이며 hook stdin에 동일 키가 보장되지 않는다.
- 대신 SubagentStop payload에 **실재**하는 `agent_transcript_path` 필드의 디렉토리 패턴(`/subagents/<parent-session>/...`)으로 부모를 추론한다.
- 추가 raw evidence: hooks.log 81건 전수 검증 (2026-05-16). 모든 SubagentStop 이벤트에서 `agent_transcript_path` 필드 실재 확인.
- 본 항목의 To-Be: `shared-context-collect.sh`/`subagent-monitor.sh`에서 `agent_transcript_path`를 파싱하여 부모 세션 ID를 추출하고 `_graph.json` 또는 frontmatter에 기록.
- 일정: 데이터 모델은 유효하나 Phase 1 우선순위에서 빠짐 → **Phase 2로 이동** (§0.3, §0.5).
- Open Question Q3은 본 정정으로 **해소**됨.

### 2.5 항목 5: `/ultrareview` × `team-review` 역할 분리

| 측면 | 현재 (As-Is) | 목표 (To-Be) |
|------|--------------|--------------|
| 동작 | `team-review` 스킬이 로컬에서 3명의 리뷰어(품질/보안/아키텍처)를 동시 스폰. 단일 리뷰 대비 약 3배 토큰 | `/ultrareview`는 클라우드 기반 multi-agent 분석/비평. `team-review`는 로컬 + harness 통합 리뷰. 두 기능의 사용 시점을 명확히 분리 |
| 영향 파일 | `.claude/skills/team-review/SKILL.md` | `team-review/SKILL.md`에 "`/ultrareview` 대비 사용 기준" 절 추가. `.claude/agents/orchestrator.md`의 Skill Catalog에 `/ultrareview`를 외부 도구로 명시 |
| 사용자 UX | `/team-review` 또는 Orchestrator가 자동 호출 | 사용자가 PR 단위 외부 리뷰가 필요할 때 `/ultrareview <PR#>`, 작업 중간 멀티렌즈 리뷰는 `team-review` |
| 비용 | 로컬 3개 인스턴스 (Claude Code 토큰 3x) | `/ultrareview`는 클라우드, 별도 과금 가능성 (추정, 공식 문서 추가 확인 권장) |
| 불확실성 | - | **추정**: `/ultrareview`의 출력 포맷, 호출 결과를 PR comment로 받는지 stdout으로 받는지 raw evidence에서 확인 안 됨. 추가 조사 필요 (Open Question Q1) |

Raw evidence (CHANGELOG.md, 2.1.111):

> Added `/ultrareview` for running comprehensive code review in the cloud using parallel multi-agent analysis and critique — invoke with no arguments to review your current branch, or `/ultrareview <PR#>` to fetch and review a specific GitHub PR

---

## 3. 아키텍처 영향 분석

### 3.1 `/goal` × 위임 강제 시스템

**핵심 질문**: `/goal`이 Orchestrator를 자율 루프로 돌릴 때, Main Agent에 forbidden된 도구를 Orchestrator는 사용 가능하므로 충돌이 없는가?

**분석**:

- `/goal`은 슬래시 커맨드 자체이며, 어느 컨텍스트에서 실행되는지에 따라 위임 시스템과의 관계가 달라진다.
- Case A: 사용자가 Main Agent 컨텍스트에서 `/goal "조건"` 호출 → 완료 조건이 만족될 때까지 Main Agent가 자율 루프 진입. 이 루프 안에서 Main Agent가 Edit/Write를 시도하면 `enforce-delegation.sh`가 차단. 차단 후 Main Agent가 위임 경로 (`Task(orchestrator)`)로 전환하면 자율 루프가 정상 동작.
- Case B: Orchestrator가 sub-agent 컨텍스트에서 `/goal` 호출 → 서브에이전트는 `enforce-delegation.sh` 통과 (transcript_path에 `/subagents/` 포함). 위임 시스템 우회 위험 없음.
- Case A에서 위험 요소는 자율 루프가 차단 메시지를 받고 자기교정 없이 동일 시도를 반복할 가능성. 이는 항목 2(메시지 UX 개선)와 연결된다 — 명확한 대체 경로 안내가 자기교정을 유도한다.

**결론**:

- `/goal` × Main Agent: 위임 훅이 자동으로 차단하므로 위임 우회 불가. 단, 자기교정 효율을 높이려면 stderr 메시지가 충분히 구체적이어야 한다.
- `/goal` × Orchestrator (sub-agent): 충돌 없음. Orchestrator가 가진 도구 권한 내에서 자율 작업.
- `/goal`의 자율 종료 조건은 Orchestrator의 적응적 실행 프로토콜과 자연스럽게 결합 가능. 예: "리뷰어가 모두 PASS를 반환할 때까지" 같은 조건.

**완화**:

- Orchestrator의 자기검증 체크리스트(`orchestrator.md`)에 "`/goal` 자율 루프 중에도 FORBIDDEN 규칙은 그대로 적용된다" 명시.
- `disableAllHooks`/`allowManagedHooksOnly` 환경에서 2.1.140 이전 버전의 `/goal` silent hang 이슈를 선결조건으로 명시. *(정정 2026-05-16: 사용자 환경에서는 두 설정 모두 부재 + 2.1.142이므로 본 환경에서는 해소. 외부 배포 가이드용으로 절은 유지)*

### 3.2 `continueOnBlock` × `enforce-delegation.sh`

**핵심 질문**: 현재 훅이 exit code 2로 차단하는데, `continueOnBlock: true`를 도입하면 차단을 "경고만"으로 바꿀 수 있는가? 그게 위임 강제의 의도와 부합하는가?

**분석**:

- `continueOnBlock`은 raw evidence에서 명확히 `PostToolUse` 전용이라고 명시됨.
- `enforce-delegation.sh`는 PreToolUse 훅. **PreToolUse에는 `continueOnBlock` 적용 불가**.
- 만약 적용 가능했다 하더라도 차단 의도(위임 강제)와는 부합하지 않음. `continueOnBlock`은 PostToolUse에서 "이미 실행된 도구의 거부 사유를 모델에 피드백"하는 용도이며, 차단을 약화시키는 게 아니라 정보를 더 풍부하게 만드는 것.
- PreToolUse에서 차단을 약화시키려면 exit 0 + stderr 안내 패턴이 필요한데, 이는 위임 강제의 본질을 무력화함.

**결론**:

- 차단은 그대로 유지 (exit 2).
- `continueOnBlock` 직접 사용은 불가능. 대신 stderr 메시지 UX 개선으로 동일 효과(Main Agent의 자기교정 효율 향상)를 노린다.
- 추후 PostToolUse 훅으로 위임 정책 위반의 후행 감지를 구현하면 그때 `continueOnBlock`을 도입할 수 있음. 본 블루프린트의 Phase 2 이후로 위임.

**완화**:

- 본 Phase에서는 메시지 UX 개선만 수행.
- Phase 2 이후에 PostToolUse 훅 도입 시 별도 블루프린트로 분리.

### 3.3 `args: string[]` 도입 × 기존 훅 호환성

**핵심 질문**: 현재 hooks는 `command: "bash script.sh"` 형식. exec 폼으로 마이그레이션 시 호환성 영향은?

**분석**:

- exec 폼은 셸을 거치지 않고 직접 spawn하므로 셸 확장(`*`, `~`, 환경변수 등)이 동작하지 않는다.
- 현재 훅 스크립트들 (`enforce-delegation.sh`, `shared-context-collect.sh` 등)은 자체 내부에서 `${HOME}`, `$PROJECT_DIR` 같은 환경변수를 처리하므로 exec 폼 호환성은 좋다.
- 단, harness.sh의 훅 등록 로직이 `~/.claude/settings.json` 또는 프로젝트별 `.claude/settings.json`에 어떤 형식으로 hook을 등록하는지 확인 필요.
- 마이그레이션 단위: `.claude/settings.json`의 각 hook entry에서 `command: "bash /abs/path/x.sh"` → `command: "/abs/path/x.sh"`, `args: []` (인자 없는 경우) 또는 `args: ["인자1", "인자2"]`.
- 호환성 위험: 사용자가 2.1.139 미만 버전을 쓰고 있으면 `args` 필드가 무시될 수 있음 (정확한 동작은 추가 조사 필요). 마이그레이션 후 구버전 사용자가 영향받을 수 있다.

**결론**:

- 단계적 마이그레이션 권장. 각 훅마다 개별 검증.
- harness.sh install 시 CC 버전 체크 추가하여 2.1.139 미만에서는 shell 폼 유지.
- 본 블루프린트의 Phase 2 항목.

### 3.4 Subagent 헤더 × 공유 컨텍스트 시스템

**핵심 질문**: 현재 `shared-context-collect.sh`는 SubagentStop 이벤트에서 파일명을 `{agent-type}-{agent-id}.md`로 생성한다. 헤더에 parent agent ID가 노출되면 호출 그래프(부모-자식 관계) 추적이 가능한가?

**분석**:

- 현재 `shared-context-collect.sh`는 `jq -r '.agent_id // ""'`와 `jq -r '.agent_type // ""'`로 SubagentStop hook input의 필드를 추출.
- CHANGELOG의 raw evidence는 API 요청 헤더와 OTEL span attribute에 대한 것이며, **SubagentStop hook input payload에 `parent_agent_id`가 포함되는지는 raw evidence에서 확인 불가**. Open Question Q3.
- 만약 hook input에 `parent_agent_id`가 포함되어 있다면: 단순히 `jq -r '.parent_agent_id'` 추가만으로 추출 가능.
- 만약 hook input에 없다면: OTEL collector나 자체 로깅에서 별도로 수집해야 함.
- 현재 시스템은 **호출 그래프 정보가 부재**한 상태. 이 항목은 단순 reflection이 아닌 **신규 기능 추가**로 분류해야 한다.

**예상 데이터 모델 확장**:

```
# 현재
.claude/shared-context/{session-id}/{agent-type}-{agent-id}.md  # 평면 목록

# 목표
.claude/shared-context/{session-id}/{agent-type}-{agent-id}.md  # 동일
.claude/shared-context/{session-id}/_graph.json                  # 신규: 부모-자식 관계
# 또는
# 각 agent context 파일의 frontmatter에 parent_agent_id 추가
```

**결론**:

- 신규 기능으로 명시적으로 분류.
- Phase 1에서는 데이터 수집만 우선 (parent_agent_id 추출 시도, 빈 값이면 빈 상태로 기록).
- 호출 그래프 시각화는 후속 작업으로 분리.

**완화**:

- Hook input payload에 실제로 parent_agent_id가 있는지 검증하는 디버그 모드를 먼저 추가.
- 검증 후 데이터 모델 결정.

### 3.5 `/ultrareview` × `team-review`

**핵심 질문**: `/ultrareview`는 공식 Anthropic 슬래시 커맨드. 우리의 `team-review`와 역할 중복은?

**분석**:

- raw evidence: `/ultrareview`는 "comprehensive code review in the cloud using parallel multi-agent analysis and critique". 무인자 호출 시 현재 브랜치 리뷰, `<PR#>` 인자 시 GitHub PR 가져와서 리뷰.
- `team-review`는 로컬에서 3개 인스턴스 (품질/보안/아키텍처)를 스폰하여 SendMessage로 상호 피드백.
- 두 기능의 차이:
  - 실행 위치: 클라우드 vs 로컬
  - 트리거: 사용자 슬래시 명령 vs Orchestrator 자동 호출 또는 사용자 슬래시 (`/team-review`)
  - 입력: PR 단위 또는 현재 브랜치 vs 임의의 파일 목록
  - 상호 피드백: `/ultrareview`는 raw evidence에서 "parallel multi-agent analysis and critique"로 critique 단계 명시. `team-review`는 SendMessage 기반 명시적 상호 피드백
  - 비용 모델: 클라우드 (별도 과금 가능성) vs 로컬 토큰 3배

**역할 분리 제안**:

| 시나리오 | 권장 도구 |
|----------|-----------|
| PR 머지 전 외부 리뷰 (CI 통합 가능) | `/ultrareview <PR#>` |
| 작업 중간 멀티렌즈 리뷰 (대규모 변경) | `Skill("team-review")` |
| 작업 중간 단일 리뷰 (1-2 파일) | `Task(reviewer)` |
| Orchestrator의 자동 리뷰 단계 | 기존대로 `Task(reviewer)` / `team-review` |
| 사용자가 명시적으로 PR을 외부 리뷰 받고 싶을 때 | `/ultrareview` |

**결론**:

- `team-review`는 유지. 단, SKILL.md에 "외부 리뷰가 필요하면 `/ultrareview`를 고려" 절 추가.
- Orchestrator는 `/ultrareview`를 자체 호출하지 않음 (Anthropic 공식 슬래시 커맨드는 사용자가 직접 호출). 단, Skill Catalog 문서에 외부 도구로 명시.

**추가 조사 필요** (Open Question Q1):

- `/ultrareview`의 정확한 출력 형식 (stdout? PR comment? 별도 UI?)
- 클라우드 과금 모델 (별도 비용? Pro/Max 플랜 포함?)
- 실패 시 동작 (네트워크 오류, GitHub 인증 등)

---

## 4. 작업 분해 (WBS)

### 항목 1: `/goal` 커맨드 활용 가이드

- **변경 파일**:
  - `.claude/agents/orchestrator.md` — Execution Protocol 절에 "자율 종료 조건" 하위 절 추가. `/goal`이 위임 시스템과 어떻게 결합하는지 명시.
  - `.claude/harness.md` — Main Agent 자기검증 체크리스트에 "`/goal` 자율 루프 중에도 FORBIDDEN 규칙 그대로 적용" 추가.
  - `docs/` — (선택) `docs/goal-command-usage.md` 사용 예시 문서.
- **의존 관계**: 항목 2(메시지 UX 개선)와 결합하면 효과 극대화. 의존성은 없지만 동시 진행 권장.
- **예상 난이도**: Low
- **예상 작업량**: 문서 약 60줄 추가, 코드 변경 없음

### 항목 2: 훅 메시지 UX 개선

- **변경 파일**:
  - `.claude/hooks/enforce-delegation.sh` — stderr 메시지를 다음 4가지 정보를 모두 포함하도록 개선:
    - 위반 도구 (`Tool=Edit` 또는 `Tool=Write`)
    - 위반 대상 파일 경로 (Write의 경우)
    - 대체 호출 경로 (`Task(orchestrator, ...)`)
    - 허용되는 조건 (서브에이전트에서만)
- **의존 관계**: 항목 1과 시너지. 독립 변경 가능.
- **예상 난이도**: Low
- **예상 작업량**: 셸 스크립트 약 10-15줄 변경

### 항목 3: 훅 `args: string[]` exec 폼 마이그레이션

- **변경 파일**:
  - `.claude/settings.json` (또는 `harness.sh`가 등록하는 hook entry) — 모든 hook에 대해 `command` → `args` 폼으로 마이그레이션.
  - `harness.sh` — install/update 시 CC 버전 체크 추가하여 2.1.139+에서만 exec 폼 사용.
- **의존 관계**: 항목 5는 별개. 항목 1, 2와도 독립적.
- **예상 난이도**: Medium (호환성 영향 검증 필요)
- **예상 작업량**: settings.json 수정 + harness.sh 수정 약 30-50줄. 각 훅 단위 동작 검증 시간 별도 필요.

### 항목 4: Subagent 헤더 기반 호출 그래프 추적

- **변경 파일**:
  - `.claude/hooks/shared-context-collect.sh` — SubagentStop input에서 `parent_agent_id` 추출 시도. 빈 값이면 기록 생략.
  - `.claude/hooks/subagent-monitor.sh` — 로그에 `parent_agent_id` 정보 포함.
  - `.claude/shared-context/{session-id}/_graph.json` (신규, 런타임 생성) — 부모-자식 관계 인덱스.
- **의존 관계**: 신규 데이터 모델. 다른 항목과 독립.
- **예상 난이도**: Medium (hook input payload 포맷 사전 검증 필요)
- **예상 작업량**: 셸 스크립트 약 20-40줄 추가. 검증 단계 별도.

### 항목 5: `/ultrareview` × `team-review` 역할 분리

- **변경 파일**:
  - `.claude/skills/team-review/SKILL.md` — "외부 리뷰 도구 (`/ultrareview`)와의 관계" 절 추가.
  - `.claude/agents/orchestrator.md` — Skill Catalog의 Review Agents 절에 `/ultrareview`를 외부 도구로 언급.
  - `CLAUDE.md` — team-review 절에 사용 시점 가이드 추가.
- **의존 관계**: 다른 항목과 독립. 단, Open Question Q1 해소 후 진행 권장.
- **예상 난이도**: Low (단, 사전 조사 필요)
- **예상 작업량**: 문서 약 40줄 추가, 코드 변경 없음.

---

## 5. 단계별 롤아웃 계획

### Phase 0: 선결 조건 확인

| 작업 | 방법 |
|------|------|
| 사용자 CC 버전 확인 | `claude --version` |
| `disableAllHooks` / `allowManagedHooksOnly` 사용 여부 확인 | `~/.claude/settings.json`, 프로젝트 `.claude/settings.json` 검토 |
| 사용자 동의: 전체 / 부분 진행 | 직접 질의 |
| `/ultrareview` 클라우드 과금 모델 확인 | 공식 문서 또는 실제 호출 |
| Subagent SubagentStop hook input payload에 `parent_agent_id` 포함 여부 확인 | 한 번의 디버그 호출로 hook input dump |

### Phase 1: Top 3 (항목 1, 2, 4)

| Phase | 항목 | 예상 작업량 | 차단/위험 |
|-------|------|------------|----------|
| 1.1 | 항목 1: `/goal` 활용 가이드 | 문서 60줄 | 없음 |
| 1.2 | 항목 2: 훅 메시지 UX 개선 | 셸 15줄 | 메시지 포맷이 Claude의 자기교정에 충분히 구조화돼야 함 |
| 1.3 | 항목 4: Subagent 헤더 기반 호출 그래프 (데이터 수집만) | 셸 20-40줄 + 검증 | Hook input에 `parent_agent_id`가 실제로 있는지 사전 검증 필수 |

### Phase 2: 나머지 2종 (항목 3, 5)

| Phase | 항목 | 예상 작업량 | 차단/위험 |
|-------|------|------------|----------|
| 2.1 | 항목 5: `/ultrareview` 역할 분리 | 문서 40줄 | Open Question Q1 해소 필요 |
| 2.2 | 항목 3: `args` exec 폼 마이그레이션 | settings.json + harness.sh 30-50줄 | 구버전 사용자 호환성, 각 훅 단위 검증 |

### Phase 3: 검증 및 문서화

| Phase | 작업 |
|-------|------|
| 3.1 | 위임 강제 회귀 테스트 (Main Agent의 Edit/Write 차단 동작 확인) |
| 3.2 | `/goal` 자율 루프 동작 검증 (간단한 완료 조건으로 실행) |
| 3.3 | 호출 그래프 데이터 수집 검증 (Orchestrator → coder 호출 시 그래프 파일 확인) |
| 3.4 | `Skill("sync-docs")` 호출하여 CLAUDE.md, harness.md, orchestrator.md 동기화 |
| 3.5 | 변경 사항 커밋 (Phase별 또는 일괄) |

---

## 6. 검증 계획

### 6.1 위임 강제 훅 회귀 테스트

목표: 메시지 UX 개선이 차단 동작을 약화시키지 않았는지 확인.

| 시나리오 | 기대 동작 |
|----------|----------|
| Main Agent가 `Edit` 호출 | exit 2, stderr에 위반 도구/대체 경로 포함 |
| Main Agent가 `Write`로 `.py` 파일 작성 | exit 2, stderr에 파일 경로 포함 |
| Main Agent가 `Write`로 `.md` 파일 작성 (docs/ 하위) | exit 0 |
| 서브에이전트(transcript_path에 `/subagents/` 포함)가 `Edit` 호출 | exit 0 |

검증 방법: hook을 직접 호출 (`echo '{...}' \| .claude/hooks/enforce-delegation.sh`) 또는 실제 시나리오 재현.

### 6.2 `/goal` 자율 루프 동작 확인

목표: `/goal`이 위임 시스템과 정상 결합하는지.

시나리오:

1. 사용자가 Main Agent에서 `/goal "테스트가 모두 통과할 때까지 수정"` 호출.
2. Main Agent가 자율 루프 진입, `Task(orchestrator)`로 위임.
3. Orchestrator가 `Skill("code")` → `Skill("test")` 반복하며 완료 조건 만족 시까지 진행.
4. 라이브 오버레이로 elapsed/turns/tokens 확인.
5. 완료 조건 만족 후 자연 종료.

차단 케이스:

- 만약 Main Agent가 자율 루프 중 Edit를 시도하면 `enforce-delegation.sh`가 차단. 메시지 UX 개선 덕분에 Main Agent가 즉시 `Task(orchestrator)`로 전환.
- `disableAllHooks` 환경에선 2.1.140+ 필요 (silent hang 방지).

### 6.3 메시지 UX 개선 확인

목표: 새 stderr 메시지가 Claude의 자기교정에 유용한지.

검증:

- 새 메시지를 받은 Main Agent가 한 번의 시도로 올바른 위임 경로를 선택하는지 (재차단 발생 여부).
- 로그(`.claude/log/hooks.log`)에서 BLOCK 빈도 감소 확인.

### 6.4 호출 그래프 데이터 수집 확인

목표: Subagent 헤더가 hook input에 실제로 전달되는지.

시나리오:

1. Orchestrator를 fork (예: `Task(orchestrator, "테스트 요청")`).
2. Orchestrator가 다시 `Task(reviewer)` 호출.
3. reviewer SubagentStop 시 hook input의 `parent_agent_id`가 Orchestrator의 agent_id와 일치하는지 확인.
4. `_graph.json` 또는 agent context 파일에 부모-자식 관계가 기록되는지 확인.

검증 실패 시 (Open Question Q3 미해결): 빈 값으로 기록되고 후속 작업으로 분리.

### 6.5 `args` exec 폼 마이그레이션 검증

목표: 각 훅이 exec 폼에서도 동일하게 동작하는지.

각 훅별 단위 테스트:

- `enforce-delegation.sh`: 위 6.1 시나리오 재현
- `shared-context-inject.sh`: SubagentStart 시 additionalContext 주입 확인
- `shared-context-collect.sh`: SubagentStop 시 파일 생성 확인
- `subagent-monitor.sh`: 로그 출력 확인
- `task-quality-gate.sh`: TaskCompleted 시 동작 확인
- `notify-telegram.sh`: SubagentStop 시 텔레그램 알림 확인
- 기타 훅 동일

### 6.6 `/ultrareview` 역할 분리 검증

목표: 문서가 사용자에게 명확한 가이드를 제공하는지.

검증:

- `team-review/SKILL.md`를 읽은 사용자가 `/ultrareview` 사용 시점을 정확히 인식하는지.
- Orchestrator가 `/ultrareview`를 자체 호출하지 않는지 (Skill Catalog에 외부 도구로만 명시됨).

---

## 7. 리스크 및 완화

### R1: `/goal` 자율 루프 × 위임 시스템 마찰

- **설명**: Main Agent가 `/goal`을 직접 사용하면 자율 루프 안에서 위임 우회 시도 반복 가능. 차단은 동작하나 luxury(자율 종료 조건의 진척)가 막힘.
- **영향**: 자율 루프가 무한 반복하면서 토큰/시간 낭비.
- **완화**:
  - 항목 2(메시지 UX 개선)로 자기교정 효율 향상.
  - `harness.md`의 Main Agent 자기검증 체크리스트에 "`/goal` 자율 루프 중에도 FORBIDDEN 규칙은 그대로" 명시.
  - Orchestrator가 `/goal` 활용 시 자율 종료 조건을 구체적으로 정의하여 무한 반복 가능성 차단.
  - 사용자에게 `/goal` 사용 가이드 문서 제공 (Orchestrator 컨텍스트에서 사용 권장).

### R2: Claude Code 2.1.139+ 호환성 — **사용자 환경에서 해소 (2026-05-16 정정)**

- **설명**: 항목 1, 2 (메시지 UX 개선), 4 일부는 2.1.139+ 기능에 의존.
- **영향**: 구버전 사용자에게 일부 기능이 동작 안 함. silent hang (2.1.140 미만의 `/goal`) 가능성.
- **정정 (2026-05-16)**:
  - 사용자 환경은 **2.1.142**로 2.1.139+ 요구사항 충족, 2.1.140+ 호환되어 `/goal` silent hang 무관 (§0.1).
  - 사용자 환경의 7곳 settings 모두에서 `disableAllHooks` / `allowManagedHooksOnly` **부재 확정** → silent hang 트리거 조건 자체가 부재 → R2는 **사용자 환경에서 해소됨**.
  - 본 R2는 향후 harness를 다른 사용자에게 배포할 때 다시 활성화될 수 있으므로 완화 항목은 그대로 유지한다.
- **완화** (외부 배포 시 적용):
  - `harness.sh install` / `update`에 CC 버전 체크 추가. 2.1.139 미만이면 경고 또는 일부 항목 스킵.
  - `disableAllHooks` / `allowManagedHooksOnly` 사용자에게 `/goal` 사용 전 2.1.140+ 권장.
  - 문서에 최소 요구 버전 명시.

### R3: 차단 누락 위험 (continueOnBlock 도입 시)

- **설명**: 항목 2에서 `continueOnBlock` 직접 적용은 불가능하다고 판단됐으나, 향후 Phase에서 도입 시 차단을 약화시켜 위임 우회 가능성 증가.
- **영향**: Main Agent가 코드를 직접 수정하는 사례 증가.
- **완화**:
  - 본 Phase에서는 `continueOnBlock` 도입 안 함.
  - PostToolUse 훅으로 위임 정책의 후행 감지를 도입할 때 별도 블루프린트로 분리.
  - PreToolUse는 항상 exit 2 + stderr 차단 유지.

### R4: `args: string[]` 마이그레이션 시 스크립트 호환성

- **설명**: exec 폼은 셸 확장을 사용하지 않음. 기존 셸 폼에 의존하던 동작이 깨질 수 있음.
- **영향**: 일부 훅이 무동작 또는 잘못 동작.
- **완화**:
  - 단계적 마이그레이션. 한 번에 하나의 훅만 변경.
  - 각 훅별 단위 테스트 (6.5).
  - 셸 확장에 의존하던 로직은 스크립트 내부로 이전.
  - 구버전 (2.1.139 미만) 사용자에게는 shell 폼 유지.

### R5: Hook input payload에 `parent_agent_id` 미포함 (Open Question Q3)

- **설명**: CHANGELOG는 API 헤더와 OTEL attribute만 명시. SubagentStop hook input에 실제로 필드가 있는지 미확인.
- **영향**: 항목 4의 호출 그래프 추적 자체가 불가능할 수 있음.
- **완화**:
  - Phase 0에서 hook input dump를 한 번 실행하여 실제 payload 확인.
  - 부재 시: OTEL collector 또는 별도 수집 메커니즘 검토 (별도 블루프린트로 분리).
  - 본 블루프린트에서는 Phase 1의 항목 4를 "데이터 수집 시도 + 빈 값 graceful handling"으로 한정.

---

## 8. 선결 조건 (Prerequisites)

이 블루프린트를 이행하기 전에 다음을 확인 또는 합의한다.

### 8.1 환경 확인

> **정정 결과 (2026-05-16)**: 본 절의 확인 항목 중 사용자 환경에 대한 점은 이미 검증 완료되었다. 아래는 검증 결과 포함 형태로 갱신한다.

- ~~사용자의 Claude Code 버전이 2.1.139+인지 확인 (`claude --version`).~~ → **확정: 2.1.142** (2.1.139+ 충족, 2.1.140+ 호환됨, /goal silent hang 무관).
- ~~항목 1 (`/goal` 가이드)는 2.1.140+ 권장 (silent hang 버그픽스 적용).~~ → 2.1.142로 만족됨.
- ~~사용자가 `disableAllHooks` 또는 `allowManagedHooksOnly`를 사용하는지 확인.~~ → **확정: 사용 안 함** (7곳 settings 전수 검증, 2026-05-16). `/goal` × hooks의 마찰 부재.
- `jq` 설치 여부 확인 (모든 훅이 jq 의존). — (별도 미검증, 다음 차례에서 점검)
- `~/.claude/settings.json`과 프로젝트 `.claude/settings.json`의 hook 등록 방식 확인 (shell 폼 vs exec 폼). — 항목 3 진행 전 점검.

추가 메모:
- 사용자가 떠올렸던 "끄는 설정"의 정체는 `protected paths` + `skipDangerousModePermissionPrompt: true` 조합으로 추정. 사용자 환경에서는 후자가 최상위 키에 있어 CC가 인식하지 못할 가능성이 있으나, **어느 쪽이든 hooks 차단을 우회하지 않으므로** 본 블루프린트의 위임 강제 가정에는 영향 없음.

### 8.2 사용자 동의

- Phase 1 (Top 3)부터 시작할지 또는 특정 항목만 먼저 진행할지 합의.
- 항목 5 (`/ultrareview` 역할 분리)는 Open Question Q1 해소 전 대기 권장.
- 항목 3 (`args` 마이그레이션)은 호환성 영향이 있어 별도 동의 권장.

### 8.3 데이터 검증

- ~~항목 4 진행 전 SubagentStop hook input payload 한 번 dump하여 `parent_agent_id` 포함 여부 확인 (Open Question Q3).~~
- **정정 (2026-05-16)**: 검증 완료. hook payload에는 `parent_agent_id`가 보장되지 않지만 `agent_transcript_path` 필드가 실재함을 hooks.log 81건 전수 확인. 항목 4의 데이터 모델을 `agent_transcript_path` 디렉토리 패턴 추론으로 재정의 (§0.3, §2.4 정정 노트, §9 Q3 해소).

---

## 9. 미해결 질문 (Open Questions)

### Q1: `/ultrareview`의 정확한 동작

- 출력 형식 (stdout, PR comment, 별도 UI)?
- 클라우드 과금 모델 (별도 비용? Pro/Max 플랜 포함?)?
- 실패 시 동작 (네트워크 오류, GitHub 인증 실패 등)?
- 항목 5 진행 전 추가 조사 권장.

### Q2: `continueOnBlock`의 정확한 stdin/stdout 동작

- raw evidence: "set to `true` to feed the hook's rejection reason back to Claude and continue the turn".
- 정확히 hook의 어느 출력 (stdout, stderr)이 모델에 피드백되는지?
- exit code 2 + stderr 외에 어떤 신호로 reject를 표현하는지?
- 본 블루프린트에서는 직접 적용하지 않으므로 즉각 차단은 아니나, 후속 Phase 진행 시 필수 확인.

### Q3: Subagent 헤더의 정확한 포맷 (hook input) — **해소됨 (2026-05-16)**

- raw evidence: "API requests from subagents now carry `x-claude-code-agent-id` / `x-claude-code-parent-agent-id` headers, and `claude_code.llm_request` OTEL spans include `agent_id` / `parent_agent_id` attributes".
- API 헤더와 OTEL은 명시되지만 hook input JSON 페이로드는 미명시.
- ~~항목 4 진행 전 한 번의 디버그 호출로 확인 필수.~~
- **정정 (2026-05-16)**: hook payload에는 `parent_agent_id`가 보장되지 않으나, 대신 **`agent_transcript_path` 필드가 실재**함을 hooks.log 81건 전수 검증으로 확인. 해당 경로의 `/subagents/<parent-session>/` 디렉토리 구조에서 부모 세션을 추론할 수 있어 항목 4 구현 가능. §0.3, §2.4 정정 노트 참조.

### Q4: `args` exec 폼의 구버전 동작

- 2.1.139 미만에서 `args` 필드가 어떻게 처리되는지? 무시? 오류?
- 안전한 마이그레이션 전략을 위해 추가 조사 권장.

### Q5: 부분 적용 시나리오의 위험

- 항목 1만 적용하고 항목 2 미적용 시 자율 루프의 자기교정 효율 저하 가능. 시너지를 위해 Phase 1은 일괄 적용 권장.

---

## 10. 참고: 추정과 사실 분리 표시

본 블루프린트에서 다음은 직전 리서치(`research-claude-code-recent-updates-20260516.md`)의 raw evidence로 확인된 사실이다:

- 확인됨: `/goal` 2.1.139 도입, 완료 조건까지 자율 작업, elapsed/turns/tokens 라이브 오버레이
- 확인됨: `continueOnBlock`은 `PostToolUse` 전용
- 확인됨: `args: string[]`은 셸 없이 직접 spawn하여 escape 불필요
- 확인됨: Subagent API 헤더 `x-claude-code-agent-id` / `x-claude-code-parent-agent-id` + OTEL `agent_id` / `parent_agent_id`
- 확인됨: `/ultrareview` 2.1.111 도입, 클라우드 multi-agent, `<PR#>` 인자 또는 무인자
- 확인됨: 2.1.140의 `/goal silently hanging when disableAllHooks or allowManagedHooksOnly is set` 버그픽스

본 블루프린트에서 다음은 **추정** 또는 **추가 조사 필요**:

- ~~추정: Hook input payload (SubagentStop)에 `parent_agent_id` 필드가 포함될 가능성 (Open Question Q3)~~ → **정정 (2026-05-16)**: 검증 결과 hook payload에는 `parent_agent_id`가 직접 노출되지 않음. 대신 `agent_transcript_path` 필드가 실재하며 그 디렉토리 패턴으로 부모 추론 가능. Q3 해소.
- 추정: `args` 필드가 구버전에서 무시될 가능성 (Q4)
- 추정: `/ultrareview`가 클라우드 별도 과금일 가능성 (Q1)
- 추정: 현재 모든 훅이 shell 폼으로 등록되어 있음 (`.claude/settings.json` 직접 확인 필요)

본 블루프린트에서 다음은 추가로 **정정된 사실** (Phase 0 검증, 2026-05-16):

- 확인됨: 사용자 CC 버전 2.1.142 (직접 `claude --version` 결과).
- 확인됨: 사용자 환경 7곳 settings 모두에서 `disableAllHooks`, `allowManagedHooksOnly` 부재. → R2의 silent hang 트리거 조건 없음.
- 확인됨: SubagentStop payload에 `agent_transcript_path` 필드 실재 (hooks.log 81건 전수 검증).
- 신규 발견됨: `enforce-delegation.sh`의 transcript_path 판별 로직 버그 → Phase 1 항목 2-bis로 추가.

---

## 11. 다음 단계 (정정 후, 2026-05-16)

### 11.1 결정사항 채택 결과 요약

| # | 결정 항목 | 채택 결과 |
|---|-----------|-----------|
| 1 | Phase 0 환경 검증 | **완료**. 사용자 환경 확정 결과를 본문에 반영함 (§0.1, §8.1, R2) |
| 2 | 항목 2 구현 방식 | **(b) stderr 메시지 UX 개선만**. `continueOnBlock` 도입 안 함 |
| 3 | Phase 1 진행 동의 | **Yes**. 즉시 진행 |
| 4 | 항목 4 정의 | **재정의(b)**: `agent_transcript_path` 디렉토리 패턴 추론으로 변경. 1회 hook input dump 검증으로 `agent_transcript_path` 필드 실재 확인됨. **Phase 2로 이동** |

### 11.2 진행 순서 (정정 후)

**Phase 1 (즉시 진행)** — Orchestrator가 다음 순서로 진행:

1. `Skill("code", "항목 2-bis: enforce-delegation.sh transcript_path 판별 버그 fix")` *(Phase 0 발견, 신규)*
2. `Skill("code", "항목 2: enforce-delegation.sh stderr 메시지 UX 개선 (continueOnBlock 미도입)")`
3. `Skill("code", "항목 1: orchestrator.md, harness.md에 /goal 가이드 추가")`
4. `Skill("sync-docs")` 호출
5. `Task(reviewer)` 호출 (Phase 1 변경 전체)
6. 사용자 확인 후 `Skill("commit")`

**Phase 2** — Open Question Q1 해소 후 진행:

1. `Skill("code", "항목 4(b): shared-context-collect.sh에 agent_transcript_path 디렉토리 패턴 파싱 추가, _graph.json 또는 frontmatter에 부모-자식 관계 기록")`
2. `Skill("code", "항목 3: 훅 args: string[] exec 폼 마이그레이션 (CC 버전 체크 포함)")`
3. `Skill("code", "항목 5: team-review/SKILL.md, orchestrator.md, CLAUDE.md에 /ultrareview 역할 분리 가이드 추가")`

**Phase 3** — 검증·문서화 (§6).

### 11.3 정정 후 핵심 메시지

- R2 (silent hang)은 사용자 환경에서 **해소**됨.
- Phase 1은 즉시 진행 가능하며, 신규로 항목 2-bis가 우선 처리되어야 한다.
- 항목 4는 데이터 모델이 명확해져 구현 가능하나 일정상 Phase 2로 이동.

---

> 본 블루프린트는 설계 문서이며 코드 변경을 포함하지 않는다. 실제 변경은 `Skill("code", ...)`를 통해 Orchestrator가 수행한다.
