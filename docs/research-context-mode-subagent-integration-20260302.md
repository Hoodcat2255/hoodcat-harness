# Context Mode 서브에이전트 통합 조사 결과

> 조사일: 2026-03-02
> 대상: mksglu/claude-context-mode v0.9.16
> 출처: GitHub 저장소, 블로그 (mksg.lu/blog/context-mode), 소스 코드 분석

## 개요

Context Mode는 Claude Code의 MCP 서버로, 도구 출력을 샌드박스에서 처리하여 컨텍스트 윈도우 소비를 98% 줄이는 플러그인이다. Cloudflare의 Code Mode(도구 정의 압축)에서 영감을 받아 도구 출력 방향의 압축을 구현했다. 315KB의 raw 출력이 5.4KB로 압축되며, 세션 지속 시간이 ~30분에서 ~3시간으로 연장된다. hoodcat-harness의 멀티에이전트 아키텍처에 통합하면 서브에이전트들의 컨텍스트 효율성을 크게 개선할 수 있으나, PreToolUse 훅 충돌과 에이전트별 도구 권한 관리에 주의가 필요하다.

## 상세 내용

### 1. Context Mode 저장소 상세 분석

#### 기본 정보
- 저장소: https://github.com/mksglu/claude-context-mode
- 라이선스: MIT
- GitHub Stars: 1,418 (2026-03-02 기준)
- Forks: 59
- 최신 버전: v0.9.16 (2026-03-01)
- 생성일: 2026-02-23 (약 1주일 전)
- 오픈 이슈: 8개
- 의존성: @modelcontextprotocol/sdk, better-sqlite3, zod, picocolors, @clack/prompts

#### 설치 방법

**플러그인 설치 (권장)**:
```bash
/plugin marketplace add mksglu/claude-context-mode
/plugin install context-mode@claude-context-mode
```
플러그인 설치 시 MCP 서버 + PreToolUse 훅 + 슬래시 커맨드가 함께 설치된다.

**MCP 전용 설치** (훅/슬래시 커맨드 없이):
```bash
claude mcp add context-mode -- npx -y context-mode
```

**로컬 개발**:
```bash
claude --plugin-dir ./path/to/context-mode
```

#### MCP 서버 동작 방식

서버는 `@modelcontextprotocol/sdk`의 `McpServer`를 사용하며, stdio 트랜스포트로 통신한다. `CLAUDE_PROJECT_DIR` 환경변수를 프로젝트 루트로 사용한다.

핵심 컴포넌트:
- `PolyglotExecutor`: 11개 언어 런타임에서 코드를 샌드박스 실행 (JS, TS, Python, Shell, Ruby, Go, Rust, PHP, Perl, R, Elixir)
- `ContentStore`: SQLite FTS5 기반 지식 베이스 (BM25 랭킹, Porter 스테밍, 트라이그램 서브스트링, 퍼지 검색)
- 세션 통계 추적: 도구별 호출 수, 반환 바이트, 인덱싱 바이트, 샌드박스 바이트

#### 제공 도구 (6개)

| 도구 | 기능 | 컨텍스트 절감 |
|------|------|--------------|
| `execute` | 11개 언어로 샌드박스 코드 실행. stdout만 컨텍스트에 진입 | 56KB -> 299B |
| `execute_file` | 파일을 샌드박스에서 처리. raw 내용은 컨텍스트 밖 | 45KB -> 155B |
| `index` | 마크다운을 FTS5에 청킹+인덱싱 (BM25 랭킹) | 60KB -> 40B |
| `search` | 인덱싱된 콘텐츠를 다중 쿼리로 검색 | 온디맨드 검색 |
| `fetch_and_index` | URL 페치 -> 마크다운 변환 -> 인덱싱 | 60KB -> 40B |
| `batch_execute` | 다중 명령 + 다중 검색을 한 번에 실행 | 986KB -> 62KB |

#### PreToolUse 훅 동작 방식

Context Mode의 PreToolUse 훅(`hooks/pretooluse.sh` 또는 `hooks/pretooluse.mjs`)은 5개 도구를 가로챈다:

| 가로채는 도구 | 동작 |
|-------------|------|
| **Bash** | curl/wget 호출을 차단하고 `fetch_and_index` 사용을 안내. 인라인 HTTP (fetch, requests.get 등)도 차단. 기타 Bash 명령은 통과 |
| **WebFetch** | `permissionDecision: "deny"`로 완전 차단. `fetch_and_index` 사용 안내 |
| **Read** | 통과시키되 `additionalContext`로 "대용량 파일은 execute_file 사용" 넛지 |
| **Grep** | 통과시키되 `additionalContext`로 "대용량 결과는 execute 사용" 넛지 |
| **Task** | 서브에이전트 프롬프트에 context-mode 라우팅 블록 주입. Bash 서브에이전트는 `general-purpose`로 업그레이드 |

핵심 메커니즘:
- `updatedInput`으로 명령어 자체를 교체 (Bash curl/wget -> echo 안내 메시지)
- `permissionDecision: "deny"`로 도구 사용 거부 (WebFetch)
- `additionalContext`로 컨텍스트 힌트 주입 (Read, Grep)
- Task 가로채기 시 프롬프트에 ROUTING_BLOCK 추가 (500단어 이하 응답 강제)

#### 설정 파일 구조

`.mcp.json`:
```json
{
  "mcpServers": {
    "context-mode": {
      "command": "node",
      "args": ["${CLAUDE_PLUGIN_ROOT}/start.mjs"]
    }
  }
}
```

`hooks/hooks.json`:
```json
{
  "hooks": {
    "PreToolUse": [
      { "matcher": "Bash", "hooks": [{ "type": "command", "command": "node ${CLAUDE_PLUGIN_ROOT}/hooks/pretooluse.mjs" }] },
      { "matcher": "WebFetch", "hooks": [...] },
      { "matcher": "Read", "hooks": [...] },
      { "matcher": "Grep", "hooks": [...] },
      { "matcher": "Task", "hooks": [...] }
    ]
  }
}
```

#### 도구 출력 압축/요약 메커니즘

1. **샌드박스 격리**: 각 `execute` 호출은 독립 프로세스에서 실행. stdout만 컨텍스트에 진입.
2. **Smart Truncation**: 출력 초과 시 head 60% + tail 40% 보존 (에러 메시지 유실 방지)
3. **Intent-driven Filtering**: 5KB 초과 + intent 파라미터 제공 시, 전체 출력을 인덱싱하고 intent에 맞는 섹션만 반환
4. **Smart Snippets**: 검색 결과는 쿼리 용어 주변 윈도우를 추출 (임의 접두사가 아닌 관련 부분 반환)
5. **Progressive Throttling**: search 호출 1-3회는 정상, 4-8회는 축소, 9+회는 차단 -> batch_execute 유도

### 2. Claude Code 서브에이전트에서 MCP 서버 사용 가능 여부

#### MCP 서버 상속 구조

Claude Code의 fork 컨텍스트(서브에이전트)에서 MCP 서버 사용에 관한 핵심 사항:

1. **프로젝트 레벨 MCP 설정 (`~/.claude/settings.json` 또는 `.claude/settings.json`의 mcpServers)**:
   - 프로젝트 레벨에서 등록된 MCP 서버는 서브에이전트에서도 접근 가능하다.
   - 단, 서브에이전트의 `tools` 목록에 해당 MCP 도구가 명시적으로 포함되어야 한다.

2. **에이전트 `.md` 파일의 `mcpServers` 필드**:
   - hoodcat-harness의 `researcher.md`에서 이미 `mcpServers: [context7]` 패턴을 사용 중이다.
   - 이 필드로 에이전트별 MCP 서버 접근을 제어할 수 있다.

3. **플러그인 설치 방식과 서브에이전트**:
   - Context Mode가 플러그인으로 설치되면 `~/.claude/settings.json`에 등록된다 (전역).
   - 전역 설정의 MCP 서버는 모든 프로젝트의 모든 에이전트에서 접근 가능하다.
   - Context Mode의 PreToolUse 훅도 전역으로 등록되므로, 모든 프로젝트에 영향을 미친다.

4. **서브에이전트별 MCP 설정 분리**:
   - 에이전트 `.md`의 `mcpServers` 필드로 "이 에이전트는 이 MCP 서버를 사용한다"를 선언할 수 있다.
   - 하지만 특정 MCP 서버를 "차단"하는 메커니즘은 없다 (허용 목록 방식).
   - Context Mode를 전역 설치하면 모든 에이전트에서 접근 가능하고, 프로젝트 레벨 설치하면 해당 프로젝트의 모든 에이전트에서 접근 가능하다.

5. **Context Mode의 자체 서브에이전트 라우팅**:
   - Context Mode의 PreToolUse 훅이 Task 도구를 가로채서 서브에이전트 프롬프트에 context-mode 도구 사용 안내를 자동 주입한다.
   - Bash 서브에이전트는 자동으로 `general-purpose`로 업그레이드되어 MCP 도구 접근이 가능해진다.
   - 이 자동 라우팅은 hoodcat-harness의 에이전트 정의와 충돌할 수 있다.

### 3. hoodcat-harness 현재 구조와의 호환성

#### 에이전트별 도구 권한 현황

| 에이전트 | 현재 도구 | MCP 서버 | Context Mode 영향도 |
|---------|----------|---------|-------------------|
| **orchestrator** | Skill, Task, Read, Write, Glob, Grep, Bash(git/npm/...), TeamCreate 등 | 없음 | 높음 - Task 가로채기, Read/Grep 넛지 |
| **coder** | Read, Write, Edit, Glob, Grep, Task, Bash(git/npm/pytest/...) | 없음 | 높음 - Bash/Read/Grep 가로채기 |
| **researcher** | Read, Write, Glob, Grep, Bash(gh/git), Task, WebSearch, WebFetch | context7 | 매우 높음 - WebFetch 차단, Bash(gh) 가로채기 |
| **navigator** | Read, Glob, Grep | 없음 | 중간 - Read/Grep 넛지 |
| **reviewer** | Read, Glob, Grep | 없음 | 낮음 - Read/Grep 넛지만 |
| **security** | Read, Glob, Grep, Bash(npm audit/pip audit/...) | 없음 | 중간 - audit 명령 가로채기 가능성 |
| **architect** | Read, Glob, Grep | 없음 | 낮음 - Read/Grep 넛지만 |
| **committer** | Read, Glob, Grep, Bash(git) | 없음 | 낮음 - git 명령은 통과 |

#### PreToolUse 훅 충돌 분석

현재 hoodcat-harness의 PreToolUse 훅:
```json
{
  "PreToolUse": [
    {
      "matcher": "Edit|Write",
      "hooks": [{ "command": "enforce-delegation.sh" }]
    }
  ]
}
```

Context Mode가 추가하는 PreToolUse 훅:
```json
{
  "PreToolUse": [
    { "matcher": "Bash", "hooks": [...] },
    { "matcher": "WebFetch", "hooks": [...] },
    { "matcher": "Read", "hooks": [...] },
    { "matcher": "Grep", "hooks": [...] },
    { "matcher": "Task", "hooks": [...] }
  ]
}
```

**충돌 여부**: matcher가 겹치지 않으므로 직접적인 충돌은 없다. 두 훅 시스템은 공존 가능하다.

**그러나 주의할 간접 충돌**:
1. **Task 가로채기 충돌**: Context Mode가 Task 프롬프트에 ROUTING_BLOCK을 주입하는데, 이는 hoodcat-harness 에이전트 정의(.md 파일)의 지시와 충돌할 수 있다. 예를 들어 coder 에이전트의 도구 목록에 MCP 도구가 없는데, ROUTING_BLOCK이 "batch_execute를 사용하라"고 지시하면 혼란이 발생한다.
2. **Bash 차단 범위**: Context Mode는 curl/wget과 인라인 HTTP를 차단하지만, hoodcat-harness의 coder 에이전트는 API 테스트 등에서 이를 사용할 수 있다.
3. **WebFetch 완전 차단**: researcher 에이전트가 WebFetch를 도구로 가지고 있는데, Context Mode가 이를 deny 처리한다. 이는 researcher의 기능을 제한한다.
4. **Read/Grep 넛지 노이즈**: 매번 Read/Grep 사용 시 "execute_file을 쓰라"는 힌트가 주입되어 navigator, reviewer 등의 에이전트 행동에 영향을 줄 수 있다.

#### 에이전트별 도구 권한(allowedTools)과의 관계

hoodcat-harness 에이전트의 `tools` 필드는 허용 도구 목록을 정의한다. Context Mode MCP 도구(mcp__context-mode__execute 등)를 사용하려면:
- 에이전트 정의에 해당 MCP 도구가 포함되어야 하거나
- 에이전트 정의에 `mcpServers: [context-mode]`가 추가되어야 한다

현재 구조에서는 어떤 에이전트도 context-mode MCP 서버를 선언하지 않으므로, 플러그인 설치만으로는 서브에이전트에서 MCP 도구를 사용할 수 없을 수 있다. Context Mode의 Task 훅이 프롬프트에 도구 사용을 지시하더라도, 에이전트의 도구 권한에 MCP 도구가 없으면 실제 호출이 불가능하다.

### 4. 적용 시나리오 및 트레이드오프

#### 에이전트별 효과 분석

**가장 효과적인 에이전트들**:

1. **coder** (효과: 매우 높음)
   - 테스트 실행 출력 (npm test, pytest): 6KB -> 337B (95% 절감)
   - 빌드 출력 (next build): 6.4KB -> 405B (94% 절감)
   - git log/diff: 11.6KB -> 107B (99% 절감)
   - 의존성 감사: 대용량 감사 결과 요약
   - 주의: curl/wget 차단이 API 테스트에 영향

2. **researcher** (효과: 높음, 주의 필요)
   - WebFetch 출력 압축: 60KB -> 40B (fetch_and_index로 대체)
   - Context7 문서 압축: 5.9KB -> 261B (96% 절감)
   - GitHub 이슈/PR 목록: 58.9KB -> 1.1KB (98% 절감)
   - 주의: WebFetch 차단은 researcher의 기본 행동 변경 필요

3. **navigator** (효과: 중간)
   - 대용량 파일 읽기 시 execute_file로 처리 가능
   - Grep 결과가 큰 경우 execute로 대체 가능
   - 하지만 navigator는 파일 시그니처만 읽으므로 (head 50줄) 실제 절감 효과 제한적

**효과가 제한적인 에이전트들**:

4. **reviewer, architect, security** (효과: 낮음)
   - 주로 Read로 코드를 읽는데, 코드 리뷰 시에는 raw 내용이 필요
   - 압축하면 리뷰 품질이 떨어질 수 있음
   - security의 npm audit 등은 압축 효과 있을 수 있음

5. **committer** (효과: 거의 없음)
   - git 명령만 사용하며 출력 규모가 작음
   - sonnet 모델 사용으로 이미 비용 최적화됨

6. **orchestrator** (효과: 중간, 리스크 높음)
   - Task 가로채기가 orchestrator의 서브에이전트 위임 패턴과 충돌 가능
   - Read/Grep은 계획 수립용으로 정확한 내용이 필요

#### 전역 적용 vs 선택적 적용

**전략 A: 전역 플러그인 설치**
- 장점: 설치 간단, 모든 에이전트에 자동 적용
- 단점: 모든 프로젝트에 영향, 에이전트별 제어 불가, 훅 충돌 가능성

**전략 B: 프로젝트 레벨 MCP 설치 (권장하지 않음)**
- `.claude/settings.json`의 mcpServers에 추가
- 장점: 프로젝트별 선택 적용
- 단점: 여전히 모든 에이전트에 적용, harness.sh로 다른 프로젝트에 전파 시 번거로움

**전략 C: 선택적 에이전트 적용 (권장)**
- Context Mode를 MCP 전용으로 설치 (훅 없이)
- 필요한 에이전트의 .md 파일에만 `mcpServers: [context-mode]` 추가
- 해당 에이전트의 스킬 SKILL.md에서 context-mode 도구 사용 지침 추가
- Context Mode의 PreToolUse 훅은 사용하지 않음 (충돌 방지)

**전략 D: 하이브리드 (Context Mode 철학을 harness 방식으로 재구현)**
- Context Mode 자체를 설치하지 않고
- harness의 기존 훅 시스템에서 대용량 출력 감지 + 요약 로직을 구현
- 장점: 완전한 제어, 기존 아키텍처와 일관성
- 단점: 구현 비용 높음, FTS5/BM25 기능 직접 구현 필요

#### 압축하면 안 되는 도구 출력

다음 출력은 정확한 원본이 필요하므로 압축하면 안 된다:

1. **테스트 에러 메시지**: 정확한 에러 내용, 스택 트레이스, 실패 테스트명이 필요
   - Context Mode의 Smart Truncation이 tail 40%를 보존하므로 에러는 보존되지만, 중간 부분의 관련 정보가 유실될 수 있음

2. **빌드 에러**: 컴파일러 에러 메시지, 라인 번호, 파일 경로가 정확해야 함
   - execute로 실행 시 분석 코드를 작성해야 하므로 디버깅 오버헤드

3. **코드 리뷰 대상 파일**: reviewer/security/architect가 읽는 소스 코드
   - 압축하면 코드의 맥락이 손실되어 리뷰 품질 저하

4. **git diff 출력**: coder가 패치를 이해하려면 정확한 diff가 필요
   - 요약된 diff는 변경 사항을 놓칠 수 있음

5. **보안 감사 결과**: npm audit, pip audit의 CVE 세부 정보
   - 요약하면 심각도와 영향 범위를 정확히 판단하기 어려움

6. **설정 파일**: package.json, tsconfig.json 등 정확한 구조가 필요한 파일
   - 압축하면 설정 키-값을 놓칠 수 있음

#### 성능/비용 트레이드오프

**비용 절감 측면**:
- 입력 토큰 절감: 컨텍스트에 들어가는 데이터가 96-98% 줄어 입력 토큰 비용 절감
- 세션 수명 연장: 30분 -> 3시간으로 세션 지속, 재시작 비용 감소
- coder 에이전트가 가장 큰 혜택 (테스트/빌드 출력이 가장 큰 컨텍스트 소비원)

**추가 비용 측면**:
- MCP 서버 프로세스 (Node.js) 상시 실행 오버헤드
- SQLite FTS5 인덱싱 오버헤드 (대부분 <20ms로 미미)
- 간접 호출 증가: Bash 대신 execute 사용 시 추가 도구 호출
- 정보 손실로 인한 재시도: 압축이 너무 공격적이면 재질문 필요

**정보 손실 리스크 관리**:
- Context Mode는 `index + search` 패턴으로 원본 데이터에 재접근 가능 (FTS5에 보존)
- Smart Snippets로 관련 부분만 추출 가능
- 그러나 "모르는 것을 모르는" 상황 리스크: 요약에서 빠진 정보의 존재를 인지하지 못함

### 5. 통합 구현 방안

#### 단계별 접근 (권장)

**1단계: MCP 전용 설치 + coder 에이전트만 적용**
```bash
# MCP 서버만 설치 (훅 없이)
claude mcp add context-mode -- npx -y context-mode
```

coder.md에 추가:
```yaml
mcpServers:
  - context-mode
```

code 스킬의 SKILL.md에서 context-mode 도구 사용 지침 추가 (테스트/빌드 출력용).

**2단계: researcher 에이전트 적용**

researcher.md에 `mcpServers: [context7, context-mode]` 추가.
deepresearch 스킬에서 fetch_and_index 활용 지침 추가.
WebFetch 대신 fetch_and_index 사용하도록 스킬 프롬프트 수정.

**3단계: 효과 측정 + 확장 판단**

/context-mode:stats 또는 자체 모니터링으로 컨텍스트 절감 효과 측정.
문제 없으면 navigator, security 에이전트로 확장.
reviewer, architect는 코드 리뷰 품질 저하 리스크로 적용하지 않음.

#### PreToolUse 훅 충돌 회피 방안

Context Mode의 PreToolUse 훅을 사용하지 않고 (플러그인이 아닌 MCP 전용 설치), 대신 harness의 스킬 SKILL.md 프롬프트에서 context-mode 도구 사용을 안내하는 방식이 가장 안전하다.

만약 PreToolUse 훅도 사용하고 싶다면:
1. Context Mode 훅이 서브에이전트 여부를 판별하는 로직이 없으므로, Main Agent에서도 동작한다.
2. hoodcat-harness의 enforce-delegation.sh는 Edit|Write만 매칭하므로 직접 충돌은 없다.
3. 하지만 Context Mode의 Task 훅이 orchestrator의 서브에이전트 위임 프롬프트를 수정하므로, harness의 Shared Context 주입 (`shared-context-inject.sh`가 SubagentStart에서 동작)과 별도 레이어에서 동작한다. 두 시스템이 서브에이전트 프롬프트를 동시에 수정하는 구조가 된다.

#### harness.sh 통합 고려사항

harness.sh로 다른 프로젝트에 설치할 때:
- MCP 전용 설치는 `claude mcp add` 명령이 필요하므로 harness.sh에 포함 가능
- 에이전트 .md 파일의 mcpServers 설정은 harness.sh가 에이전트 파일을 복사하므로 자동 전파
- Node.js 18+ 필수이므로 사전 확인 로직 필요

## 코드 예제

### MCP 전용 설치 (프로젝트별)

```bash
# .claude/settings.json에 추가되는 MCP 설정
claude mcp add context-mode -- npx -y context-mode
```

### 에이전트 .md 파일 수정 예시 (coder.md)

```yaml
---
name: coder
tools:
  - Read
  - Write
  - Edit
  - Glob
  - Grep
  - Task
  - Bash(git *)
  - Bash(npm *)
  # ... 기존 도구들 ...
mcpServers:
  - context-mode    # 추가
model: opus
memory: project
---
```

### 스킬 프롬프트에서 context-mode 활용 지침 예시

```markdown
## 대용량 출력 처리

테스트/빌드 명령 실행 시:
- `npm test`, `pytest`, `cargo test` 등의 출력이 20줄을 초과할 것으로 예상되면
  `mcp__context-mode__execute(language: "shell", code: "npm test 2>&1")` 사용
- 대용량 파일 분석 시: `mcp__context-mode__execute_file(path, language, code)` 사용
- 정확한 에러 메시지가 필요하면: 일반 Bash로 실행하고 Read로 확인

단, 다음은 항상 일반 도구 사용:
- git add, git commit, git push (파일 변경 작업)
- 20줄 이하의 확실히 작은 출력
- 코드 편집 대상 파일 읽기 (Read 사용)
```

## 주요 포인트

- Context Mode는 MCP 서버 + PreToolUse 훅 + 슬래시 커맨드의 세 컴포넌트로 구성된다. hoodcat-harness 통합 시 MCP 서버만 설치하고 훅은 사용하지 않는 것이 가장 안전하다.

- 에이전트별 도구 권한(`tools` 필드)과 MCP 서버 접근(`mcpServers` 필드)을 분리 관리할 수 있으므로, coder와 researcher에만 선택적으로 적용하는 것이 권장된다.

- PreToolUse 훅 충돌은 matcher가 다르므로 기술적으로는 없으나, Context Mode의 Task 가로채기가 orchestrator의 서브에이전트 위임 패턴에 간섭할 수 있다. ROUTING_BLOCK이 하드코딩된 500단어 제한과 특정 워크플로우를 강제하므로, harness의 유연한 에이전트 아키텍처와 맞지 않을 수 있다.

- 가장 큰 컨텍스트 절감 효과는 coder 에이전트의 테스트/빌드 출력에서 발생한다 (95-99% 절감). reviewer/architect/security 에이전트에는 적용하지 않는 것이 좋다 (코드 원본이 필요).

- Context Mode의 FTS5 지식 베이스는 세션 내에서 공유되므로, 한 서브에이전트가 인덱싱한 내용을 다른 서브에이전트가 search로 검색할 수 있다. 이는 hoodcat-harness의 공유 컨텍스트 시스템과 보완적인 역할을 할 수 있다.

## 출처

- [claude-context-mode GitHub 저장소](https://github.com/mksglu/claude-context-mode) - README, 소스 코드, 이슈
- [Context Mode 블로그 글](https://mksg.lu/blog/context-mode) - 개념 설명, 벤치마크
- [Cloudflare Code Mode](https://blog.cloudflare.com/code-mode-mcp/) - 영감을 준 원본 프로젝트
- [Context Mode BENCHMARK.md](https://github.com/mksglu/claude-context-mode/blob/main/BENCHMARK.md) - 21개 시나리오 벤치마크
- [Issue #22: Sandbox와 가상 환경 호환성](https://github.com/mksglu/claude-context-mode/issues/22)
- [Issue #23: search OR 시맨틱스 문제](https://github.com/mksglu/claude-context-mode/issues/23)
- hoodcat-harness 에이전트 정의: `/Users/hoodcat/Projects/hoodcat-harness/.claude/agents/*.md`
- hoodcat-harness 훅: `/Users/hoodcat/Projects/hoodcat-harness/.claude/hooks/enforce-delegation.sh`
- hoodcat-harness 설정: `/Users/hoodcat/Projects/hoodcat-harness/.claude/settings.json`
