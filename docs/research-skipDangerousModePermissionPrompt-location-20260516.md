# `skipDangerousModePermissionPrompt` settings.json 위치 확정 조사

> 조사일: 2026-05-16
> 조사자: researcher (deepresearch 스킬)
> 대상 환경: Claude Code 2.1.142, `~/.claude/settings.json`

## 개요 (한 줄 결론)

**최상위(top-level)가 정답.** `permissions` 객체 하위는 **schema 위배**이며 실제 런타임에서 무시된다. 사용자가 입력한 "docs.claude.com/en/docs/settings 페이지가 `permissions.skipDangerousModePermissionPrompt`로 안내한다"는 전제는 docs raw HTML 검증 결과 **부정확**하다 — 공식 docs는 키 이름만 "Permission settings" 섹션 표의 row로 나열했을 뿐, `permissions.` prefix를 적은 적이 없다. 시각적 그룹화 때문에 nested로 추론되기 쉬운 것일 뿐이며, schema도 GitHub 이슈도 모두 top-level을 지지한다.

사용자 환경 `~/.claude/settings.json`의 현재 배치(`skipDangerousModePermissionPrompt: true`가 최상위)는 **올바른 위치**다. 마이그레이션 불필요.

## 상세 내용

### 1. 공식 JSON Schema (가장 권위 있는 출처)

출처: `https://json.schemastore.org/claude-code-settings.json`
스키마 self-description (raw):
- `title`: "Claude Code Settings"
- `description`: "Configuration settings for Claude Code. Learn more: https://code.claude.com/docs/en/settings"

이 schema는 공식 docs 페이지(code.claude.com/docs/en/settings) 자체를 참조용으로 명시한 공식 schema다.

**Top-level properties에 `skipDangerousModePermissionPrompt` 존재 확인.**

검증 코드 출력 (raw):
```
HAS_SKIP_TOP: True
PERM_KEYS: ['additionalDirectories', 'allow', 'ask', 'defaultMode', 'deny', 'disableAutoMode', 'disableBypassPermissionsMode']
PERM_HAS_SKIP: False
PERM_ADDITIONAL: False
TOP_ADDITIONAL: True
```

해석:
- `permissions` 객체의 properties는 정확히 7개. `skipDangerousModePermissionPrompt`는 그 안에 없음.
- `permissions.additionalProperties: False` — 정의되지 않은 키를 추가하면 schema 위배. 즉 `permissions.skipDangerousModePermissionPrompt`는 **schema 차원에서 invalid**.
- top-level의 `additionalProperties: True` — top-level 키 자체는 schema가 관대하지만, `skipDangerousModePermissionPrompt`는 명시적으로 top-level property로 등재됨.

Schema의 `skipDangerousModePermissionPrompt` 정의 raw:
```json
{
  "description": "Whether the user has accepted the bypass permissions mode dialog. Typically managed by the CLI rather than set by hand.",
  "type": "boolean"
}
```

핵심 메시지: "**Typically managed by the CLI rather than set by hand**" — 사용자가 직접 적기보다 CLI 다이얼로그에서 "Yes, I accept" 누르면 자동 기록되는 흐름이 정식.

### 2. 공식 docs 페이지 (`docs.claude.com/en/docs/claude-code/settings`)

페이지 크기: 2,140,033 bytes. `skipDangerousModePermissionPrompt` 문자열 총 3회 등장 (1회는 사용자에게 보이는 HTML table cell, 2회는 동일 콘텐츠의 _jsx 직렬화 백업 — 같은 정보).

**사용자에게 보이는 table row raw HTML 인용:**
```html
<tr>
  <td style="text-align:left"><code>skipDangerousModePermissionPrompt</code></td>
  <td style="text-align:left">
    Skip the confirmation prompt shown before entering bypass permissions mode
    via <code>--dangerously-skip-permissions</code> or
    <code>defaultMode: "bypassPermissions"</code>.
    Ignored when set in project settings (<code>.claude/settings.json</code>)
    to prevent untrusted repositories from auto-bypassing the prompt
  </td>
  <td style="text-align:left"><code>true</code></td>
</tr>
```

**중요한 사실:**
- docs는 키 이름을 **bare `skipDangerousModePermissionPrompt`**로만 표시한다. `permissions.` prefix는 등장하지 않는다.
- 이 row는 `disableBypassPermissionsMode`(역시 top-level 키, "Typically placed in managed settings"로 설명됨) row 바로 뒤에 등장한다. 둘 다 같은 "Permission settings" h3 섹션 표에 있을 뿐.
- 표가 "Permission settings" 섹션 아래에 있다는 점만 보고 "이 키들이 permissions 객체 내부"라고 추론하기 쉽다 — 이게 nesting 오해의 원인. 같은 표에 들어있는 `allow/ask/deny/defaultMode/additionalDirectories`는 실제로 permissions 객체 하위지만, `disableBypassPermissionsMode`와 `skipDangerousModePermissionPrompt`는 top-level이다. **표 그룹화 ≠ nesting**.

**docs 첫 등장일**: 2026-04-01 (issue #26233 reporter coygeek의 verification 코멘트 raw 인용):
> "Correction after a full re-verification on 2026-04-01: this issue is still only partially resolved, not resolved. The settings reference now documents `skipDangerousModePermissionPrompt`, but the permissions docs and CLI reference still do not explain the persisted warning-suppression behavior or how to restore the warning, so this should remain open."

즉 docs 추가는 2026-04-01이지만 도입 자체는 그 훨씬 이전(키는 v2.1.109 시점에 이미 작동했고 이슈 #26233은 2026-02-17 등록).

### 3. 공식 CHANGELOG.md

출처: `https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md` (310,137 bytes)

`grep -in -E 'skipDangerous'` 결과: **0건**. 키 이름 자체가 changelog에 한 번도 명시되지 않았다.

`bypass`/`--dangerously-skip` 관련 hit은 모두 flag/feature 이슈(예: line 392 "writes to `.claude/`, `.git/`, ..." 의 v2.1.126 변경, line 458의 `.claude/skills/` 등 제외). **키 도입 CC 버전은 공식 CHANGELOG에 표기되지 않음.** 다만 issue #26233(2026-02-17)에서 이미 키가 동작 중이었으므로 그 이전 도입이 확정.

### 4. GitHub Issues 교차 검증

#### Issue #48668 (OPEN, 2026-04-15, v2.1.109) — nesting 오류 사례 raw

제목: "permissions.skipDangerousModePermissionPrompt ignored in user settings (v2.1.109)"

reporter가 첨부한 settings.json raw:
```json
{
  "permissions": {
    "skipDangerousModePermissionPrompt": true
  }
}
```

reporter의 가설(틀린 가설): "Per the [settings docs](https://code.claude.com/docs/en/settings), this key is only supposed to be ignored in *project* settings, not user settings."

**실제 원인 (researcher 분석)**: reporter는 docs를 잘못 읽었다. docs는 키를 `permissions.X`로 안내한 적 없다. permissions 객체에 nested 배치하면 schema의 `additionalProperties: False` 규칙 위배로 런타임이 무시한다. 즉 user/project scope 문제가 아니라 키 위치 문제. 이 이슈가 OPEN 상태인 건 Anthropic이 nesting 오해를 명시적으로 답변하지 않았기 때문 — duplicates 봇만 무관한 후보 3개를 제시(#25503, #42696, #40328)했고, reporter는 thumb-down으로 거부.

#### Issue #50461 (CLOSED 2026-04-22 as dup of #41615) — top-level 정답 사례

제목: "Permission prompts still appear with --dangerously-skip-permissions + skipDangerousModePermissionPrompt: true"

reporter는 **top-level**에 정확히 배치:
> "Launch `claude --dangerously-skip-permissions` with `settings.json` containing `\"skipDangerousModePermissionPrompt\": true`."

여전히 일부 Bash 작업(`gh run rerun`, `git push --force-with-lease` 등) prompt 발생. **닫힘 사유는 키 위치 문제 아니라 #41615의 protected paths prompt 별개 버그와 중복.** 이게 결정적: top-level 배치가 정답이라는 걸 community/봇 둘 다 암묵적으로 동의했고, 이슈는 "별개 버그"로 분류됨.

CC 버전: 2.1.111 (reporter 환경).

#### Issue #26233 (CLOSED 2026-04-28, RESOLVED — docs 추가 확인) — 키 자동 기록 메커니즘 raw

reporter coygeek의 본문 raw:
> "When a user launches Claude Code with `--dangerously-skip-permissions` or sets `defaultMode` to `bypassPermissions`, Claude Code displays a one-time warning prompt asking the user to confirm they understand the risks. When the user accepts this prompt, **Claude Code automatically writes `\"skipDangerousModePermissionPrompt\": true` to the user-level `settings.json` (`~/.claude/settings.json`)**. On subsequent launches, this setting suppresses the warning prompt so the user is not asked again."

이 raw가 schema의 "Typically managed by the CLI rather than set by hand"와 정확히 일치하는 동작 설명이다. **자동 기록 위치는 user-level `~/.claude/settings.json`의 top-level**.

### 5. 둘 다 인식 여부 / deprecated alias 여부

조사 결과 **둘 다 인식되지 않는다**:
- `permissions.skipDangerousModePermissionPrompt`: schema의 `additionalProperties: False` 규칙에 의해 invalid. issue #48668은 정확히 이 케이스가 동작하지 않음을 보여줌.
- `skipDangerousModePermissionPrompt` (top-level): 정식 위치.

**deprecated alias 관계 없음.** CHANGELOG에 위치 이동 이력 없고, schema에 alias 정의도 없고, docs에도 alias 언급 없다. 한 자리만 정답이다.

### 6. 버전 의존성

- **v2.1.109** (issue #48668 재현 버전): top-level 인식 동작. nested 무시. → 사용자의 2.1.142도 동일하게 동작할 것으로 추정.
- **v2.1.111** (issue #50461): top-level 인식하나 `--dangerously-skip-permissions` 사용 시 일부 protected paths/Bash prompt가 여전히 떠서 별개 버그 #41615로 합쳐짐.
- **v2.1.126** (CHANGELOG line 392): `--dangerously-skip-permissions`가 protected paths(`.claude/`, `.git/`, `.vscode/`, shell config files) writes도 bypass하도록 확장. **`skipDangerousModePermissionPrompt`와 무관**하지만 사용자 체감에는 영향(prompt가 줄어드는 부수효과).
- **v2.1.142** (사용자 현재): 위 버전들의 누적 동작. 키 위치 동작은 v2.1.109 이후 변화 없는 것으로 추정 (공식 source에 위치 변경 changelog 없음).

**버전별 위치 이동은 발견되지 않음.** 키가 도입된 시점부터 줄곧 top-level.

### 7. 사용자 환경(CC 2.1.142, `~/.claude/settings.json` top-level 배치) 권장 조치

현재 사용자 `~/.claude/settings.json`:
```json
{
  "model": "opus[1m]",
  "skipDangerousModePermissionPrompt": true,
  "enabledPlugins": { "telegram@claude-plugins-official": true }
}
```

**판정**: 위치 정답. 마이그레이션 불필요.

만약 사용자가 "그래도 권한 prompt가 뜬다"고 느낀다면, 그건 이 키의 책임이 아닐 가능성이 높다. 이 키는 정확히 "bypass 모드 진입 시 1회성 'Yes, I accept' 다이얼로그를 다시 안 띄움" 역할만 한다. 매 도구 호출 prompt를 끄려면 다음이 필요:
- `defaultMode: "bypassPermissions"` (permissions 객체 내부) 또는 `--dangerously-skip-permissions` CLI flag로 bypass 모드 활성화. 이 키만으로는 prompt가 사라지지 않음.

**양쪽 다 두면 conflict 여부**: top-level과 `permissions` 내부에 같은 키를 동시에 두면, schema 검증기는 permissions 내부 키를 schema 위배로 경고하지만 런타임은 top-level만 읽고 nested는 무시한다 (issue #48668 동작 일치). conflict라기보다는 nested가 dead config다. 정리 권장이지만 동작 영향 없음.

### 8. `permissions` 객체 schema 전체 (참고)

permissions 객체에 들어가는 7개 키와 각 역할:
- `allow`: array of permission rules (allowed operations)
- `ask`: array of permission rules (always prompt)
- `deny`: array of permission rules (denied)
- `defaultMode`: enum `["acceptEdits", "bypassPermissions", "default", "delegate", "dontAsk", "plan", "auto"]`
- `additionalDirectories`: array of paths
- `disableAutoMode`: (auto mode 차단)
- `disableBypassPermissionsMode`: `"disable"` 값 (managed settings에서 bypass 자체 차단)

schema description raw:
```
Tool usage permissions configuration.
See https://code.claude.com/docs/en/permissions and
https://code.claude.com/docs/en/settings#permission-settings
See https://code.claude.com/docs/en/tools-reference for full list of tools available to Claude.
```

`skipDangerousModePermissionPrompt`가 이 목록에 없는 게 결정적 증거다.

## 미해결 / 불확실

1. **사용자가 docs에서 `permissions.skipDangerousModePermissionPrompt`라고 명시한 출처**: 검증 결과 공식 docs.claude.com/en/docs/claude-code/settings 페이지에는 그런 표기 없음. 사용자가 본 출처가 third-party 블로그, AI 답변, 또는 docs 다른 페이지일 가능성. 정확히 어디서 본 것인지 사용자에게 확인이 필요하다. 이 부분은 추가 조사 가치 없음 (공식 source 확정 완료).

2. **키 도입된 정확한 CC 버전**: 공식 CHANGELOG에 표기 없어 확정 불가. v2.1.109(issue #48668 재현)와 v2.1.107(issue #26233 본문이 작성된 2026-02-17 시점 당시 환경에서 키가 이미 동작) 사이로 추정되나 raw 인용 가능한 출처 없음.

3. **사용자 환경 2.1.142에서 실제 동작 확인**: 코드 변경 없음 + 사용자에 따로 검증 요청 없으므로 직접 재현 안 함. 필요시 별도 디버그.

## 최종 사용자 보고용 요약 (300단어 내외)

`skipDangerousModePermissionPrompt`는 **반드시 top-level**에 두는 게 정답입니다. 사용자 현재 `~/.claude/settings.json` 배치는 정확하니 옮길 필요 없습니다.

증거 chain:
1. 공식 JSON Schema (`json.schemastore.org/claude-code-settings.json`)가 이 키를 top-level properties로 정의합니다. `permissions` 객체의 properties는 정확히 7개(`allow, ask, deny, defaultMode, additionalDirectories, disableAutoMode, disableBypassPermissionsMode`)뿐이고 `additionalProperties: False`라 다른 키를 nested 배치하면 schema 위배입니다.
2. 공식 docs 페이지(`docs.claude.com/en/docs/claude-code/settings`)의 raw HTML을 확인한 결과 docs는 키 이름을 **bare `skipDangerousModePermissionPrompt`**로만 표시합니다. `permissions.` prefix는 등장하지 않습니다. "Permission settings" 섹션 표 안에 있다는 시각적 그룹화 때문에 nested로 보일 뿐, 같은 표의 `disableBypassPermissionsMode`도 top-level 키입니다. **표 그룹화는 nesting을 의미하지 않습니다.**
3. Issue #48668 (OPEN, 2026-04-15, v2.1.109)는 정확히 nested 배치한 사례로, 동작하지 않음을 확인했습니다.
4. Issue #50461 (CLOSED 2026-04-22)은 top-level 배치 사례로, 키 위치 문제 없이 별개 protected-paths 버그(#41615)로 분류됐습니다.

CHANGELOG.md에는 키 이름이 한 번도 등장하지 않습니다. 키 도입 시점은 v2.1.109 이전이지만 정확한 버전은 공식 source에 없습니다.

**키의 정확한 동작**: bypass 모드(`--dangerously-skip-permissions` 또는 `defaultMode: "bypassPermissions"`) 진입 시의 1회성 "Yes, I accept" 다이얼로그를 다시 안 띄우는 것뿐입니다. 매 도구 호출 prompt를 끄려면 bypass 모드 자체를 활성화해야 합니다. Project scope(`.claude/settings.json`)에 적으면 untrusted repo 자동 bypass 방지를 위해 무시되니, **user scope(`~/.claude/settings.json`) top-level**이 유일한 유효 위치입니다.

## 출처

- 공식 JSON Schema: https://json.schemastore.org/claude-code-settings.json
- 공식 docs 페이지: https://docs.claude.com/en/docs/claude-code/settings
- 공식 CHANGELOG.md: https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md
- Issue #48668 (nesting 오류 사례, OPEN): https://github.com/anthropics/claude-code/issues/48668
- Issue #50461 (top-level 정답 + 별개 버그 분리, CLOSED): https://github.com/anthropics/claude-code/issues/50461
- Issue #26233 (docs 누락 보고 → 2026-04-01 추가 확인, CLOSED): https://github.com/anthropics/claude-code/issues/26233
- Issue #41615 (#50461의 실제 책임 버그 — protected paths prompt, OPEN): https://github.com/anthropics/claude-code/issues/41615
