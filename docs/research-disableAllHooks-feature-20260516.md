# disableAllHooks / allowManagedHooksOnly / .claude 디렉토리 권한 확인 기능 식별

> 조사일: 2026-05-16
> 조사자: researcher (deepresearch 스킬)

## 개요

사용자가 묘사한 "CC 최근 업데이트 이후로 .claude/ 디렉토리 내 파일 수정 시 매번 권한 확인을 요구하던 동작을 끄는 설정"의 정체는 **`disableAllHooks`도 `allowManagedHooksOnly`도 아니다**. 두 키는 **hook 실행 정책**을 다루는 설정이지, .claude 파일 편집 권한 prompt를 끄는 설정이 아니다.

사용자가 묘사한 동작에 정확히 대응하는 공식 메커니즘은 **`protected paths`** (공식 docs 섹션명)이며, .claude/, .git/, .vscode/, .idea/, .husky/, 그리고 .gitconfig 같은 특정 파일에 대한 쓰기를 모든 permission mode(bypassPermissions 제외)에서 강제로 prompt하는 빌트인 안전장치다.

**중요 결론: 이 protected paths 메커니즘을 끄는 단일 settings key는 공식 문서에 존재하지 않는다.** 끄려면 (a) `bypassPermissions` 모드 사용, (b) `--dangerously-skip-permissions` 플래그 사용 (v2.1.126부터 protected paths도 bypass됨), 또는 (c) `permissions.allow` 규칙으로 개별 경로를 명시적 allow 처리 — 이 세 가지 우회 경로만 있다.

## 결과

### 1. `disableAllHooks` 공식 정의

| 항목 | 값 |
|------|-----|
| 정의 | "Disable all hooks and any custom status line" |
| 동작 | true로 설정 시 모든 hooks와 커스텀 status line이 비활성화됨 |
| 도입 CC 버전 | **확인 불가** (CHANGELOG.md raw에 "Introduced disableAllHooks" 항목 없음. 2.1.140에서 `/goal`이 hang하던 버그 fix가 첫 실명 언급) |
| 출처 | https://code.claude.com/docs/en/settings (settings 표 row: `disableAllHooks`) |

raw 인용 (HTML→텍스트):
> `disableAllHooks` | Disable all [hooks](/docs/en/hooks) and any custom [status line](/docs/en/statusline) | `true`

관련 docs issue: anthropics/claude-code #27017 (closed) — "[DOCS] `disableAllHooks` documentation does not reflect managed policy precedence"

### 2. `allowManagedHooksOnly` 공식 정의

| 항목 | 값 |
|------|-----|
| 정의 | (Managed settings only) Only managed hooks, SDK hooks, and hooks from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project, and all other plugin hooks are blocked. |
| 동작 | managed-settings.json에서만 설정 가능. true면 user/project hooks 차단. v2.1.101부터 force-enabled marketplace plugin 예외 추가. |
| 도입 CC 버전 | **2025-10-29 이전** (issue #10544에서 collaborator ant-kurt가 "New setting `allowManagedHooksOnly` can be defined in enterprise settings"이라고 도입 알림. CC v2.1.x 시리즈 초기. 정확한 마이너 버전은 CHANGELOG.md에 항목 없음) |
| 출처 | https://code.claude.com/docs/en/settings (#hook-configuration), https://github.com/anthropics/claude-code/issues/10544 |

raw 인용 (docs/settings):
> "Behavior when `allowManagedHooksOnly` is `true`:
> - Managed hooks and SDK hooks are loaded
> - Hooks from plugins force-enabled in managed settings `enabledPlugins` are loaded. This lets administrators distribute vetted hooks through an organization marketplace while blocking everything else.
> - User hooks, project hooks, and all other plugin hooks are blocked"

raw 인용 (issue #10544, ant-kurt):
> "New setting `allowManagedHooksOnly` can be defined in enterprise settings. This will disable user and project-level hooks, but allow enterprise and SDK hooks."

### 3. 사용자가 떠올린 기능 식별 — Protected Paths

| 항목 | 값 |
|------|-----|
| 정확한 메커니즘 명칭 | `protected paths` (공식 docs 섹션명, slug: `#protected-paths`) |
| 설정 키 이름 | **단일 toggle 키 없음 (확신도 H)** |
| 묘사와 일치하는 기능 | .claude/, .git/, .vscode/, .idea/, .husky/ 디렉토리와 .gitconfig, .bashrc 등 셸 설정 파일, .mcp.json, .claude.json에 대한 쓰기를 default/acceptEdits/plan 모드에서 항상 prompt함 |
| 도입 CC 버전 | **확인 불가 (정확한 도입 시점)**. CHANGELOG 흔적: 2.1.90 ".husky added to protected directories (acceptEdits mode)", 2.1.126 "--dangerously-skip-permissions now bypasses prompts for writes to .claude/, .git/, .vscode/, shell config files, and other previously-protected paths". 즉 mechanism은 2.1.90 이전부터 존재, 점진적으로 경로 추가 + 2.1.126에서 bypass 동작 변경 |
| 끄는 단일 키 | **공식 출처에 존재하지 않음**. 우회 방법 3종만 존재 |
| 출처 | https://code.claude.com/docs/en/permission-modes#protected-paths |

raw 인용 (docs/permission-modes#protected-paths):
> "Writes to a small set of paths are never auto-approved, in every mode except bypassPermissions. This prevents accidental corruption of repository state and Claude's own configuration. In default, acceptEdits, and plan these writes prompt; in auto they route to the classifier; in dontAsk they are denied; in bypassPermissions they are allowed.
>
> Protected directories: .git, .vscode, .idea, .husky, .claude (except for .claude/commands, .claude/agents, .claude/skills, and .claude/worktrees where Claude routinely creates content)
>
> Protected files: .gitconfig, .gitmodules, .bashrc, .bash_profile, .zshrc, .zprofile, .profile, .ripgreprc, .mcp.json, .claude.json"

raw 인용 (CHANGELOG 2.1.126):
> "`--dangerously-skip-permissions` now bypasses prompts for writes to `.claude/`, `.git/`, `.vscode/`, shell config files, and other previously-protected paths (catastrophic removal commands still prompt as a safety net)"

raw 인용 (CHANGELOG 2.1.90):
> "Added `.husky` to protected directories (acceptEdits mode)"

#### Protected Paths를 끄는/우회하는 방법 (공식)

| 방법 | 설명 | 출처 |
|------|------|------|
| `--dangerously-skip-permissions` CLI 플래그 | v2.1.126부터 protected paths writes도 bypass | CHANGELOG 2.1.126, docs/permission-modes#skip-all-checks-with-bypasspermissions-mode |
| `permissions.defaultMode: "bypassPermissions"` | 위와 동일. settings.json에서 영구 설정 | docs/permission-modes |
| `permissions.allow` 규칙 (예: `"Edit(./.claude/**)"`) | 개별 경로를 명시적 allow. 단, deny 규칙이 있으면 deny 우선 | docs/permissions#manage-permissions |

protected paths 자체를 끄는 `disableProtectedPaths`나 `skipProtectedPaths` 같은 단일 boolean 키는 **공식 settings.json 표에 존재하지 않는다** (직접 raw HTML grep으로 확인). 가장 가까운 사례는 .claude 내부의 `commands/agents/skills/worktrees` 하위 디렉토리가 protected에서 자동 예외 처리되는 것뿐이다.

### 4. 사용자가 헷갈렸을 가능성 분석

| 사용자 묘사 | disableAllHooks | allowManagedHooksOnly | protected paths |
|-------------|-----------------|------------------------|-----------------|
| ".claude/ 파일 수정 시 권한 확인" | ❌ hook 비활성화. 파일 prompt와 무관 | ❌ managed/SDK 외 hook 차단. prompt와 무관 | ✅ 정확히 일치 |
| "최근 추가된 동작" | ❌ 도입 시점 불명, 신규 아님 | ❌ 2025-10 이전 도입 | △ mechanism은 오래됨, 단 2.1.126에서 bypass 동작 변경됨 |
| "끄는 설정" | △ hook만 끔 | △ hook만 끔 | ❌ 단일 toggle 키 부재 |

**가장 가능성 높은 시나리오:** 사용자가 hoodcat-harness 설치 후 .claude/ 하위 파일(특히 settings.json, .mcp.json 등 protected files 목록과 겹치는 파일)을 수정하려 할 때마다 prompt가 떴고, 이를 "끄는 설정"이 있다고 기억했지만 그 정체는 **단일 키가 아니라 `bypassPermissions` 모드 또는 `--dangerously-skip-permissions` 플래그**다. CHANGELOG 2.1.126 항목을 들었거나 봤다면 "최근 변경"이라는 인상이 강화됐을 가능성도 있다.

`disableAllHooks`/`allowManagedHooksOnly`는 이름 때문에 혼동될 수 있지만, 실제로는 hooks(PreToolUse 등 사용자 정의 콜백) 실행을 제어하는 키이며 파일 편집 permission prompt와는 완전히 별개 계층이다.

### 5. 출처 raw 인용 (영문 원문)

1. **docs/settings - disableAllHooks 정의** (HTML row, decoded)
   > `disableAllHooks` | Disable all hooks and any custom status line | `true`

2. **docs/settings - allowManagedHooksOnly 정의**
   > `allowManagedHooksOnly` | (Managed settings only) Only managed hooks, SDK hooks, and hooks from plugins force-enabled in managed settings `enabledPlugins` are loaded. User, project, and all other plugin hooks are blocked. | `true`

3. **docs/permission-modes#protected-paths - 전체 단락**
   > "Writes to a small set of paths are never auto-approved, in every mode except bypassPermissions. This prevents accidental corruption of repository state and Claude's own configuration. In default, acceptEdits, and plan these writes prompt; in auto they route to the classifier; in dontAsk they are denied; in bypassPermissions they are allowed."

4. **CHANGELOG 2.1.126** (관련 동작 변경 시점)
   > "`--dangerously-skip-permissions` now bypasses prompts for writes to `.claude/`, `.git/`, `.vscode/`, shell config files, and other previously-protected paths (catastrophic removal commands still prompt as a safety net)"

5. **CHANGELOG 2.1.140** (두 키의 부작용 fix)
   > "Fixed `/goal` silently hanging when `disableAllHooks` or `allowManagedHooksOnly` is set — now shows a clear message instead of an indicator that never resolves"

## 주요 포인트

- `disableAllHooks` = hooks 전체 + 커스텀 status line 비활성화. 파일 편집 권한과 무관
- `allowManagedHooksOnly` = managed/SDK hooks 외 user/project hooks 차단 (managed-settings.json 전용). 파일 편집 권한과 무관
- 사용자가 묘사한 ".claude/ 매번 권한 확인" 동작은 공식 명칭 **`protected paths`** 메커니즘
- protected paths를 끄는 단일 boolean 키는 **공식 문서에 존재하지 않음**
- 우회: `bypassPermissions` 모드 또는 `--dangerously-skip-permissions` (v2.1.126부터 protected paths 포함)
- 두 키와 protected paths는 모두 별개 계층이지만 v2.1.140에서 `/goal`이 두 hook 키와 충돌해 hang하던 버그가 수정된 적 있어 함께 언급되는 경우 존재

## 출처

- https://code.claude.com/docs/en/settings (disableAllHooks, allowManagedHooksOnly 정의)
- https://code.claude.com/docs/en/permission-modes#protected-paths (protected paths 정의 + 동작)
- https://code.claude.com/docs/en/permissions (permission 규칙)
- https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md (2.1.90, 2.1.126, 2.1.140 항목)
- https://github.com/anthropics/claude-code/issues/10544 (allowManagedHooksOnly 도입 알림, ant-kurt collaborator)
- https://github.com/anthropics/claude-code/issues/27017 (disableAllHooks docs 이슈)
- https://github.com/anthropics/claude-code/issues/46387 (allowManagedHooksOnly v2.1.101 plugin 예외 docs 갱신)
- https://github.com/anthropics/claude-code/issues/51123 (allowManagedHooksOnly ANTHROPIC_BASE_URL 우회 보안 이슈)
