# Serena MCP 조사 결과

> 조사일: 2026-02-12

## 개요

Serena는 LLM을 완전한 코딩 에이전트로 변환하는 오픈소스 MCP 서버 툴킷이다. Language Server Protocol(LSP)을 활용하여 코드베이스에 대한 **시맨틱(의미론적) 이해** 기반의 검색 및 편집 기능을 제공하며, 텍스트 기반 검색에 의존하는 다른 도구들과 차별화된다. GitHub Stars 20,041개, Forks 1,353개(2026-02-12 기준), MIT 라이선스, Python으로 작성되었다.

핵심 가치: IDE가 제공하는 수준의 심볼 레벨 코드 탐색/편집 능력을 LLM 에이전트에 부여하여, 파일 전체를 읽거나 grep 검색을 수행하는 대신 정확한 심볼 단위 작업을 가능하게 한다. 이를 통해 토큰 소비를 최대 80%까지 절감할 수 있다.

---

## 상세 내용

### 1. 아키텍처 및 동작 원리

Serena의 핵심 아키텍처는 세 계층으로 구성된다:

1. **Language Server Protocol (LSP) 계층**: Solid-LSP 라이브러리(multilspy 확장)를 통해 각 언어의 Language Server와 통신한다. 이를 통해 심볼 정의, 참조, 타입 계층 등의 시맨틱 정보를 추출한다.
2. **도구(Tool) 계층**: LSP 정보를 기반으로 `find_symbol`, `replace_symbol_body`, `insert_after_symbol` 등의 고수준 도구를 제공한다. 도구 구현은 프레임워크 비의존적이다.
3. **MCP 서버 계층**: Model Context Protocol을 통해 LLM 클라이언트(Claude Code, Claude Desktop, Cursor, Codex 등)와 통신한다. stdio 또는 streamable-http 트랜스포트를 지원한다.

대안으로 JetBrains Plugin 백엔드를 사용할 수 있으며, 이 경우 JetBrains IDE의 코드 분석 엔진을 활용하여 LSP가 지원하지 않는 언어까지 커버할 수 있다.

### 2. 지원 언어

**30개 이상의 프로그래밍 언어** 지원:

- **직접 지원 (LSP)**: Python, TypeScript/JavaScript, Java, C/C++, Rust, Go, PHP
- **간접 지원**: Ruby, C#, Kotlin, Dart, Swift, Scala, Haskell, Elixir, Erlang, Clojure, Julia, R, MATLAB, Bash, PowerShell, Lua, Nix, Perl, Fortran, AL
- **설정 파일**: TOML, YAML, Markdown
- **부분 지원**: Groovy

JetBrains 백엔드 사용 시 JetBrains IDE가 지원하는 모든 언어/프레임워크로 확장 가능하다.

### 3. 전체 도구 목록 (45개)

#### 프로젝트 관리
| 도구 | 설명 |
|------|------|
| `activate_project` | 이름 또는 경로로 프로젝트 활성화 |
| `remove_project` | 설정에서 프로젝트 제거 |
| `get_current_config` | 에이전트 설정, 활성 프로젝트, 도구, 컨텍스트, 모드 표시 |
| `check_onboarding_performed` | 프로젝트 온보딩 완료 여부 확인 |
| `onboarding` | 프로젝트 구조 파악 및 필수 작업 식별 |

#### 파일 작업
| 도구 | 설명 |
|------|------|
| `create_text_file` | 프로젝트 디렉토리 내 파일 생성/덮어쓰기 |
| `read_file` | 프로젝트 디렉토리 내 파일 읽기 |
| `delete_lines` | 파일 내 특정 범위의 줄 삭제 |
| `insert_at_line` | 파일의 특정 줄에 콘텐츠 삽입 |
| `replace_lines` | 파일 내 특정 범위의 줄을 새 콘텐츠로 교체 |
| `replace_content` | 파일 내 콘텐츠 교체 (정규식 지원) |
| `list_dir` | 디렉토리의 파일/폴더 목록 조회 (재귀 가능) |
| `find_file` | 지정 경로에서 파일 검색 |

#### 시맨틱 코드 분석 및 탐색 (핵심)
| 도구 | 설명 |
|------|------|
| `find_symbol` | Language Server를 사용한 글로벌/로컬 심볼 검색 |
| `find_referencing_symbols` | 특정 심볼을 참조하는 심볼 검색 |
| `get_symbols_overview` | 파일의 최상위 심볼 개요 조회 |
| `rename_symbol` | Language Server 리팩토링으로 코드베이스 전체에서 심볼 이름 변경 |
| `replace_symbol_body` | Language Server를 사용하여 심볼의 전체 정의 교체 |
| `insert_before_symbol` | 심볼 정의 시작 전에 콘텐츠 삽입 |
| `insert_after_symbol` | 심볼 정의 끝 뒤에 콘텐츠 삽입 |
| `search_for_pattern` | 프로젝트 내 패턴 검색 |

#### JetBrains 전용
| 도구 | 설명 |
|------|------|
| `jet_brains_find_symbol` | JetBrains 백엔드로 심볼 검색 |
| `jet_brains_find_referencing_symbols` | JetBrains 백엔드로 참조 심볼 검색 |
| `jet_brains_get_symbols_overview` | JetBrains 백엔드로 파일 심볼 개요 조회 |
| `jet_brains_type_hierarchy` | JetBrains 백엔드로 타입 계층(상위/하위 타입) 조회 |

#### 메모리 관리
| 도구 | 설명 |
|------|------|
| `write_memory` | 프로젝트별 메모리 저장소에 정보 기록 |
| `read_memory` | 메모리 저장소에서 정보 읽기 |
| `list_memories` | 저장된 메모리 목록 조회 |
| `delete_memory` | 메모리 삭제 |
| `edit_memory` | 기존 메모리 편집 |

#### 실행 및 시스템
| 도구 | 설명 |
|------|------|
| `execute_shell_command` | 셸 명령 실행 (주의: 위험할 수 있음) |
| `restart_language_server` | Language Server 재시작 (Serena 외부 편집 후 필요) |
| `open_dashboard` | 웹 대시보드 열기 |

#### 워크플로우 및 추론
| 도구 | 설명 |
|------|------|
| `switch_modes` | 모드 활성화/전환 |
| `initial_instructions` | Serena 도구 사용 가이드 제공 |
| `prepare_for_new_conversation` | 새 대화 준비 안내 |
| `summarize_changes` | 코드베이스 변경 사항 요약 안내 |
| `think_about_collected_information` | 수집 정보 평가용 추론 도구 |
| `think_about_task_adherence` | 태스크 준수 확인용 추론 도구 |
| `think_about_whether_you_are_done` | 완료 확인용 추론 도구 |

### 4. 설정 및 구성

#### 설정 파일 구조

```
~/.serena/
  serena_config.yml          # 글로벌 설정 (모든 클라이언트/프로젝트 공통)

<project>/.serena/
  project.yml                # 프로젝트별 설정
```

#### 컨텍스트 옵션 (--context)

| 컨텍스트 | 대상 클라이언트 | 설명 |
|-----------|----------------|------|
| `ide-assistant` | Claude Code, Cursor | IDE 통합 워크플로우 최적화 |
| `desktop-app` | Claude Desktop | 데스크톱 앱 전용 |
| `codex` | Codex CLI | Codex CLI 전용 |
| `ide` | JetBrains | JetBrains IDE 전용 |

컨텍스트에 따라 활성화되는 도구 세트와 프롬프트 전략이 자동 조정된다.

#### Claude Code 연동 설정

```bash
# 프로젝트 루트에서 실행 (권장)
claude mcp add serena -- \
  uvx --from git+https://github.com/oraios/serena \
  serena start-mcp-server --context ide-assistant --project "$(pwd)"
```

또는 `.claude/mcp.json`에 직접 설정:

```json
{
  "mcpServers": {
    "serena": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/oraios/serena",
        "serena",
        "start-mcp-server",
        "--context",
        "ide-assistant",
        "--project-from-cwd"
      ]
    }
  }
}
```

#### 주요 실행 옵션

```bash
# 기본 stdio 트랜스포트
uvx --from git+https://github.com/oraios/serena serena start-mcp-server

# HTTP 트랜스포트 (원격 접근용)
uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --transport streamable-http --port 9121

# 계획 모드 + 온보딩 건너뛰기
uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --mode planning --mode no-onboarding

# JetBrains 백엔드 사용
uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --language-backend JetBrains

# 도구 타임아웃 조정
uvx --from git+https://github.com/oraios/serena serena start-mcp-server \
  --tool-timeout 60.0
```

### 5. 경쟁 도구 비교

#### vs 구독형 도구 (Cursor, Windsurf, VSCode Copilot)

| 항목 | Serena | Cursor/Windsurf |
|------|--------|-----------------|
| 비용 | 무료 (오픈소스) | 월 구독료 |
| 코드 이해 | LSP 기반 시맨틱 분석 | 텍스트 기반 검색 중심 |
| IDE 종속 | 없음 (LLM 에그노스틱) | 특정 IDE에 종속 |
| 커스터마이징 | 소스 코드 수정 가능 | 제한적 |

#### vs API 기반 에이전트 (Claude Code, Cline, Aider)

| 항목 | Serena | Claude Code (단독) |
|------|--------|--------------------|
| 코드 탐색 | 심볼 레벨 (LSP) | 텍스트 레벨 (Grep/Glob) |
| 토큰 효율 | 필요한 심볼만 추출 (최대 80% 절감) | 파일 전체 읽기 |
| 리팩토링 | `rename_symbol`로 코드베이스 전체 반영 | 수동 find & replace |
| 설정 복잡도 | Language Server 설치 필요 | 즉시 사용 가능 |

**핵심 차이점**: Serena는 Claude Code를 대체하는 것이 아니라 **보완**하는 도구다. Claude Code의 MCP 클라이언트로 Serena를 연결하면 기존 도구(Read, Grep, Glob 등)에 시맨틱 도구가 추가된다.

#### vs 다른 MCP 서버 (DesktopCommander, codemcp, MCP Language Server)

| 항목 | Serena | DesktopCommander/codemcp | MCP Language Server |
|------|--------|--------------------------|---------------------|
| 코드 분석 | LSP 기반 시맨틱 | 순수 텍스트 기반 | LSP 프록시 |
| 편집 기능 | 심볼 수준 편집 | 텍스트 수준 편집 | 제한적 |
| 메모리 | 프로젝트별 메모리 저장소 | 없음 | 없음 |
| 온보딩 | 자동 프로젝트 분석 | 없음 | 없음 |
| 설정 복잡도 | 중간 | 낮음 | 낮음 |

### 6. Best Practices

1. **read_only: true로 시작**: 처음에는 읽기 전용으로 시작하고, 도구의 범위를 이해한 후 쓰기 도구를 점진적으로 활성화한다.
2. **적절한 컨텍스트 선택**: 클라이언트에 맞는 `--context` 옵션을 사용한다. 잘못된 컨텍스트는 불필요한 도구 노출이나 프롬프트 불일치를 초래한다.
3. **프로젝트 자동 활성화**: 주로 같은 프로젝트를 작업한다면 `--project <path>` 옵션으로 시작 시 자동 활성화를 설정한다.
4. **Serena 설정으로 도구 제어**: 클라이언트 UI에서 도구를 비활성화하는 대신 Serena의 YAML 설정을 통해 제어한다. Serena의 프롬프트가 활성 도구에 따라 자동 조정되기 때문이다.
5. **웹 대시보드 활용**: 기본적으로 활성화되는 웹 대시보드를 통해 서버 작업, 로그, 설정을 모니터링한다.
6. **execute_shell_command 주의**: 이 도구는 강력하지만 위험하다. 프로덕션 환경에서는 비활성화를 고려한다.

### 7. 알려진 이슈 및 트러블슈팅

#### Windows 관련
- npm 명령이 exit status 127을 반환하며 TypeScript Language Server 초기화 실패
- `uv`/`uvx` PATH 문제: 전체 경로를 명시적으로 지정하여 해결
- 프로젝트 레벨 `mcp.json`이 적용되지 않는 경우 Cursor 설정 UI에서 직접 등록

#### 연결 문제
- Codex에서 "MCP client failed to start: request timed out" 오류 발생 가능 (Issue #617)
- LSP 반복 초기화로 인한 MCP 도구 타임아웃 (Issue #634)
- 클라이언트 업데이트/설정 변경/프로젝트 전환 시 연결 끊김 가능

#### 설정 혼동
- `mcp-config.json` 대신 클라이언트별 위치에 설정 파일을 배치해야 함
- `.serenarc.json` (구형)이 아닌 `~/.serena/serena_config.yml` (YAML) 사용
- `web_dashboard: false` 설정 없이 설치가 실패하는 경우가 있음

#### 트러블슈팅 방법
1. `uvx --from git+https://github.com/oraios/serena serena start-mcp-server --help`로 수동 시작 테스트
2. `mcp.log` 또는 `mcp-server-*.log`에서 에러 상세 확인
3. MCP Inspector(공식 디버그 도구)로 서버 연결 테스트
4. Language Server가 응답하지 않으면 `restart_language_server` 도구 호출

### 8. 릴리즈 현황

| 버전 | 날짜 | 비고 |
|------|------|------|
| v0.1.4 | 2025-08-15 | 최신 안정 릴리즈 |
| v0.1.3 | 2025-07-21 | - |
| 2025-05-19 | 2025-05-19 | Pre-release |

v1.0이 준비 중이며, JetBrains Plugin, 30+ 언어 지원, Codex 통합이 추가되었다. 공식 태그 릴리즈보다 main 브랜치의 `git+https://github.com/oraios/serena`에서 직접 설치하는 것이 일반적이다.

---

## 코드 예제

### Claude Code에서 Serena 추가

```bash
# 프로젝트 루트에서 실행
claude mcp add serena -- \
  uvx --from git+https://github.com/oraios/serena \
  serena start-mcp-server --context ide-assistant --project "$(pwd)"
```

### .claude/mcp.json 설정 예시

```json
{
  "mcpServers": {
    "serena": {
      "command": "uvx",
      "args": [
        "--from",
        "git+https://github.com/oraios/serena",
        "serena",
        "start-mcp-server",
        "--context",
        "ide-assistant",
        "--project-from-cwd"
      ]
    }
  }
}
```

### Codex CLI 설정 (~/.codex/config.toml)

```toml
[mcp_servers.serena]
command = "uvx"
args = ["--from", "git+https://github.com/oraios/serena", "serena",
        "start-mcp-server", "--context", "codex"]
```

### 시맨틱 도구 활용 흐름 예시

```
# 전통적 접근 (Claude Code 단독)
1. Read: src/auth/handler.ts (파일 전체 읽기 - 500줄)
2. Grep: "validateToken" 패턴 검색
3. Read: 참조 파일들 추가 읽기

# Serena 활용 접근
1. find_symbol: "validateToken" (정확한 위치 + 시그니처만)
2. find_referencing_symbols: "validateToken" (참조하는 모든 심볼)
3. replace_symbol_body: 함수 본문만 교체
→ 토큰 소비 대폭 절감
```

---

## 주요 포인트

1. **시맨틱 코드 이해가 핵심 차별점**: LSP를 통해 텍스트 검색이 아닌 심볼 레벨의 코드 이해를 제공한다. `find_symbol`, `find_referencing_symbols`, `rename_symbol` 등은 IDE가 제공하는 수준의 정확도를 LLM에 부여한다.

2. **Claude Code의 대체가 아닌 보완 도구**: Serena는 MCP 서버로서 Claude Code의 기존 도구에 시맨틱 기능을 추가한다. 기존 Read/Grep/Glob과 함께 사용할 때 가장 효과적이다.

3. **토큰 효율 최대 80% 절감**: 파일 전체를 읽는 대신 필요한 심볼만 추출하므로, 대규모 코드베이스에서 특히 유리하다. 단, 소규모 단일 파일 작업이나 그린필드 프로젝트에서는 이점이 적다.

4. **45개 도구, 4개 컨텍스트**: 프로젝트 관리, 파일 작업, 시맨틱 분석, JetBrains 통합, 메모리 관리, 추론 도구까지 포괄적인 도구 세트를 제공하며, 클라이언트별 컨텍스트로 도구 세트가 자동 조정된다.

5. **오픈소스 + 무료 사용 가능**: MIT 라이선스이며, Claude Desktop 무료 티어에서도 MCP 서버로 사용 가능하다. GitHub Stars 20,000+ 로 활발한 커뮤니티를 갖추고 있으며, v1.0 릴리즈가 준비 중이다.

---

## 출처

- [GitHub - oraios/serena](https://github.com/oraios/serena) - 공식 레포지토리
- [Serena Documentation - Tools List](https://oraios.github.io/serena/01-about/035_tools.html) - 전체 도구 목록
- [Serena Documentation - Configuration](https://oraios.github.io/serena/02-usage/050_configuration.html) - 설정 가이드
- [Serena Documentation - Comparison](https://oraios.github.io/serena/01-about/040_comparison-to-other-agents.html) - 경쟁 도구 비교
- [Serena Documentation - Client Setup](https://oraios.github.io/serena/02-usage/030_clients.html) - 클라이언트 연동
- [SmartScope - Serena MCP Setup Guide (2026)](https://smartscope.blog/en/generative-ai/claude/serena-mcp-implementation-guide/) - 종합 설정 가이드
- [SmartScope - Serena MCP Free Coding Agent](https://smartscope.blog/en/generative-ai/claude/serena-mcp-coding-agent/) - 기능 소개
- [ClaudeLog - Serena MCP](https://claudelog.com/claude-code-mcps/serena/) - Claude Code 통합 가이드
- [Serena MCP Alternatives](https://www.gopher.security/mcp-security/serena-mcp-alternatives) - 대안 비교
- [Context7 vs Serena MCP](https://medium.com/@bbangjoa/context7-vs-serena-mcp-strengths-weaknesses-and-which-one-id-recommend-f3142424435d) - Context7과 비교
- [Apidog - How to Set Up Serena MCP Server](https://apidog.com/blog/serena-mcp-server/) - 설정 튜토리얼
- [VibeTools - Serena MCP Complete Guide](https://vibetools.net/posts/serena-mcp-complete-guide) - 상세 사용 가이드
- [Serena MCP on MCP Servers](https://mcpservers.org/servers/oraios/serena) - MCP 서버 디렉토리
