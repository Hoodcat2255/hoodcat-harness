# Claude Code 내장 LSP vs Serena MCP 판단 결과

> 판단일: 2026-02-12

## 결정 요약

**권고**: 현 시점에서 **Serena MCP를 주력으로 사용**하되, Claude Code LSP가 성숙해지면 **병행 또는 전환을 검토**한다.
**확신도**: 중간 - 두 기술 모두 활발히 발전 중이며, Claude Code LSP의 안정성이 빠르게 개선되고 있어 6개월 내 판단이 바뀔 수 있다.

---

## 후보 분석

### 후보 A: Claude Code 내장 LSP

2025년 12월 v2.0.74에서 도입된 플러그인 기반 LSP 통합이다. 표준 Language Server Protocol을 통해 go-to-definition, find-references, hover, diagnostics를 Claude Code에 제공한다.

**장점:**
- **네이티브 통합**: Anthropic 공식 지원. Claude Code 업데이트와 함께 자연스럽게 개선된다
- **설정 간편**: 플러그인 마켓플레이스에서 설치 (`/plugin install pyright@claude-code-lsps`)
- **속도**: LSP 활성화 시 코드베이스 탐색이 50ms로, 텍스트 검색 대비 45초에서 극적 개선
- **23개 언어 지원**: boostvolt/claude-code-lsps 마켓플레이스 기준 (Python, TypeScript, Go, Rust, Java, C#, Kotlin 등)
- **외부 의존성 최소**: MCP 서버 프로세스 불필요. 언어 서버 바이너리만 설치하면 된다
- **진단(Diagnostics)**: 편집 직후 실시간 오류/경고 감지 -- Serena에 없는 기능

**단점:**
- **미성숙**: 출시 2개월 차. "No LSP server available" 오류, 플러그인 인식 실패, 네이티브 바이너리 설치 시 미작동 등 다수의 버그 보고
- **공식 플러그인 결함**: claude-plugins-official 마켓플레이스의 LSP 플러그인이 README만 포함하고 실제 코드가 없는 문제가 보고됨
- **UI/UX 부재**: LSP 서버의 시작/실행/오류 상태를 확인할 UI가 없다
- **의미적 편집 미지원**: go-to-definition과 find-references는 제공하지만, 심볼 기반 편집(insert_after_symbol)은 불가
- **Jose Valim의 비판**: "대부분의 LSP API는 file:line:column을 전달해야 하므로 에이전트 사용에 어색하다. 단순히 'Foo#bar가 어디에 정의되어 있는지'를 물을 수 없다"

**적합한 경우:**
- 외부 MCP 서버 설정을 최소화하고 싶을 때
- 실시간 diagnostics(오류 감지)가 중요할 때
- 이미 Claude Code만 사용 중이고 추가 도구 설치를 원하지 않을 때

### 후보 B: Serena MCP

oraios/serena -- MCP 프로토콜을 통해 LSP 기반 시맨틱 코드 인텔리전스를 제공하는 오픈소스 코딩 에이전트 툴킷이다.

**장점:**
- **시맨틱 코드 조작**: `find_symbol`, `find_referencing_symbols`, `insert_after_symbol` 등 심볼 수준의 검색/편집 도구 제공. grep 기반 검색보다 정확하고 토큰 효율적
- **토큰 절약**: 전체 파일을 읽지 않고 필요한 심볼만 검색. 컨텍스트 부패(context rot) 감소. 유사 도구 대비 최대 27.5% 비용 절감, 97% 입력 토큰 감소 보고
- **30+ 언어 지원**: Claude Code LSP의 23개보다 넓은 범위
- **무료 오픈소스**: MIT 라이선스
- **성숙도**: 2024년부터 개발. Claude Code LSP 대비 더 오래 테스트됨
- **JetBrains 통합**: JetBrains IDE 플러그인을 통한 추가 통합 가능
- **`--context claude-code`**: Claude Code 전용 모드로 중복 도구를 비활성화하여 충돌 방지

**단점:**
- **외부 프로세스 관리**: MCP 서버를 별도로 실행/관리해야 한다. `uv` 패키지 매니저 필요
- **대화 길어지면 사용 감소**: Claude Code가 대화가 길어질수록 Serena 도구를 점차 사용하지 않게 되는 현상 보고 (Discussion #340)
- **설정 복잡도**: `--context claude-code` 플래그, `serena_config.yml`, `project.yml` 등 다층 설정 필요
- **diagnostics 미제공**: 실시간 오류/경고 감지는 Claude Code 내장 LSP만의 기능
- **일관성 없는 품질 보고**: 일부 사용자는 "게임 체인저"로 평가하지만, 다른 사용자는 "각 프롬프트마다 수많은 오류가 발생해 1-2시간 디버깅이 필요했다"고 보고
- **작은 프로젝트에서 불필요**: 파일이 적거나 단순한 프로젝트에서는 오버헤드만 추가

**적합한 경우:**
- 대규모 코드베이스에서 정밀한 심볼 기반 탐색/편집이 필요할 때
- 토큰 비용 최적화가 중요할 때 (특히 Opus 모델 사용 시)
- 기존 프로젝트의 리팩토링, 참조 추적이 핵심 작업일 때

---

## 평가 매트릭스

| 기준 | Claude Code LSP | Serena MCP | 비고 |
|------|:---:|:---:|------|
| **코드 탐색 정확도** | B+ | A | Serena는 심볼 수준, LSP는 file:line:column 기반 |
| **코드 편집 능력** | C | A | LSP는 읽기 전용 탐색, Serena는 심볼 기반 편집 가능 |
| **토큰 효율성** | B | A | Serena는 필요한 심볼만 반환, LSP는 전체 정보 반환 |
| **실시간 진단** | A | N/A | LSP만의 고유 강점 |
| **설정 간편성** | A- | C+ | LSP는 플러그인 설치, Serena는 MCP+uv+config |
| **안정성/성숙도** | C+ | B | LSP는 출시 2개월, 버그 다수. Serena는 상대적으로 안정 |
| **언어 지원 범위** | B+ (23개) | A (30+개) | Serena가 더 넓은 범위 |
| **유지보수 부담** | A | B- | LSP는 자동 업데이트, Serena는 별도 관리 |
| **대규모 코드베이스** | B | A | Serena의 심볼 기반 접근이 대규모에서 강점 |
| **소규모 프로젝트** | A | C | 소규모에서는 Serena 오버헤드가 불필요 |

---

## 트레이드오프

### Serena MCP를 선택하면
- **얻는 것**: 심볼 수준의 정밀한 코드 탐색/편집, 토큰 절약, 넓은 언어 지원, 대규모 코드베이스에서의 효율성
- **잃는 것**: 설정 간편성, 실시간 diagnostics, 대화 길어질 때의 일관된 도구 사용, Anthropic 공식 지원의 안정감

### Claude Code LSP를 선택하면
- **얻는 것**: 네이티브 통합의 안정감, 실시간 오류 감지, 간편한 설정, 자동 업데이트
- **잃는 것**: 심볼 기반 편집 기능, 토큰 효율성, 대규모 코드베이스에서의 정밀도

### 둘 다 사용하면
- **얻는 것**: 최대 기능 범위 (LSP diagnostics + Serena 심볼 편집)
- **잃는 것**: 도구 중복으로 인한 혼란 가능성 (반드시 `--context claude-code` 플래그 필요), 설정/유지보수 복잡도 증가, MCP 도구 개수 증가로 Claude의 도구 선택 정확도 저하 가능

---

## 최종 권고

### 주 권고: Serena MCP 사용

현 시점에서 Serena MCP가 더 실용적인 선택이다. 핵심 근거:

1. **심볼 기반 편집**: Claude Code LSP는 탐색(읽기)만 가능하지만, Serena는 심볼 기반 편집까지 지원한다. 에이전트 코딩에서 "찾기 + 편집"은 항상 함께 필요하다.
2. **토큰 효율성**: Opus 모델 사용 시 토큰 비용이 핵심 관심사이며, Serena의 심볼 단위 검색은 전체 파일 읽기 대비 극적인 토큰 절약을 제공한다.
3. **안정성**: Claude Code LSP는 아직 버그가 많고 공식 플러그인조차 불완전하다. Serena는 더 오래 테스트되어 상대적으로 안정적이다.

### 조건부 권고

- **소규모 프로젝트 (파일 50개 미만)**: 두 도구 모두 불필요할 수 있다. Claude Code의 기본 Grep/Read만으로 충분하다.
- **diagnostics가 핵심인 경우**: Claude Code LSP를 병행한다. Serena에는 없는 실시간 오류 감지가 필요하면 LSP 플러그인을 추가 설치한다.
- **6개월 후 재평가 권고**: Claude Code LSP가 v2.1+ 이후 빠르게 안정화되고 있다. 심볼 편집 기능이 추가되거나 안정성이 크게 개선되면 네이티브 LSP로 전환이 유리해질 수 있다.

### Serena MCP 사용 시 필수 설정

```json
{
  "mcpServers": {
    "serena": {
      "command": "uvx",
      "args": [
        "--from", "git+https://github.com/oraios/serena",
        "serena", "start-mcp-server",
        "--context", "claude-code"
      ]
    }
  }
}
```

`--context claude-code` 플래그는 **반드시** 포함해야 한다. 이 플래그 없이 사용하면 Claude Code 내장 도구와 중복되어 도구 충돌과 성능 저하가 발생한다.

---

## 출처

- [Claude Code LSP 공식 문서 - Plugins Reference](https://code.claude.com/docs/en/plugins-reference)
- [Serena GitHub Repository](https://github.com/oraios/serena)
- [Serena vs Claude Code built-in tools (GitHub Discussion #545)](https://github.com/oraios/serena/discussions/545)
- [Claude Code gets native LSP support (Hacker News)](https://news.ycombinator.com/item?id=46355165)
- [Serena plugin --context claude-code flag issue (#223)](https://github.com/anthropics/claude-plugins-official/issues/223)
- [Claude Code Not Using Serena As Much (Discussion #340)](https://github.com/oraios/serena/discussions/340)
- [boostvolt/claude-code-lsps - 23개 언어 LSP 마켓플레이스](https://github.com/boostvolt/claude-code-lsps)
- [Jose Valim on LSP limitations for agentic usage](https://x.com/josevalim/status/2002312493713015160)
- [Claude Code LSP 실사용기 (Medium)](https://medium.com/@joe.njenga/how-im-using-new-claude-code-lsp-to-code-fix-bugs-faster-language-server-protocol-cf744d228d02)
- [Claude Code + Serena 실사용 후기 (EveryDev)](https://www.everydev.ai/p/tool-claude-code-serena-is-the-first-time-ive-felt-like-ai-can-actually-do-the)
- [Serena MCP + Claude Code Setup Guide (SmartScope)](https://smartscope.blog/en/generative-ai/claude/serena-mcp-claude-code-beginners-guide/)
- [Claude Code LSP Bug Reports - #14803, #20050, #16214](https://github.com/anthropics/claude-code/issues/14803)
- [Serena Configuration Documentation](https://oraios.github.io/serena/02-usage/050_configuration.html)
- [Serena MCP Deep Dive (Skywork AI)](https://skywork.ai/skypage/en/Serena-MCP-Server-A-Deep-Dive-for-AI-Engineers/1970677982547734528)
