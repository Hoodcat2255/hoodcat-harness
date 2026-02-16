# Main Agent 위임규칙 강제 방안 조사

> 조사일: 2026-02-16

## 개요

Main Agent의 절대 규칙 "슬래시 커맨드 외 모든 자연어 요청은 Orchestrator에 위임"이 실제로는 빈번히 위반된다. Claude Code 시스템에서 이 위반을 방지할 수 있는 모든 방법을 조사하고, 각 방법의 실현 가능성/효과성/부작용/구현 난이도를 분석한다.

---

## 위반 유형 분석

Main Agent가 위반하는 전형적인 패턴:

| 위반 유형 | 사용하는 도구 | 발생 조건 |
|-----------|-------------|----------|
| 소규모 코드 수정 | Edit, Write | "1-2줄이니 빨리 고치자" |
| 서버 상태 확인 | Bash | "간단한 명령 하나인데" |
| 반복 버그 수정 | Edit + Bash | "같은 패턴 반복이니 직접" |
| 파일 읽기/분석 | Read, Grep, Glob | "파일 하나만 읽으면 되니까" |
| 직접 응답 생성 | (도구 없음) | "단순 질문이니 바로 답변" |

핵심 문제: LLM은 "효율성" 편향이 있어, 프롬프트 지시를 무시하고 직접 처리하려는 경향이 있다. 특히 작업이 간단할수록 위임 오버헤드가 불합리해 보여 직접 처리한다.

---

## 방법 1: PreToolUse 훅으로 도구 사용 차단

### 메커니즘

`settings.json`에 PreToolUse 훅을 등록하여, Main Agent가 Edit/Write/Bash 등을 직접 사용할 때 차단한다.

```json
{
  "hooks": {
    "PreToolUse": [
      {
        "matcher": "Edit|Write|Bash",
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/enforce-delegation.sh",
            "timeout": 5
          }
        ]
      }
    ]
  }
}
```

### 핵심 기술 문제: Main Agent vs 서브에이전트 구분 불가

PreToolUse stdin JSON에는 `agent_type`이나 `is_main_agent` 같은 필드가 **존재하지 않는다**. 공통 필드는:

```json
{
  "session_id": "abc123",
  "transcript_path": "/path/to/transcript.txt",
  "cwd": "/current/working/dir",
  "permission_mode": "ask",
  "hook_event_name": "PreToolUse",
  "tool_name": "Edit",
  "tool_input": { ... }
}
```

서브에이전트(coder, researcher 등)도 Edit/Write/Bash를 사용하므로, **무차별 차단하면 모든 서브에이전트의 작업도 차단된다.**

### 우회 방안: transcript_path 기반 구분

서브에이전트의 transcript는 `{session-id}/subagents/agent-{id}.jsonl` 경로에 저장된다. Main Agent의 transcript는 직접 `{session-id}.jsonl`이다.

```bash
#!/bin/bash
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')

# transcript 경로에 "subagents"가 포함되면 서브에이전트
if echo "$TRANSCRIPT" | grep -q "/subagents/"; then
  exit 0  # 서브에이전트 -> 허용
fi

# Main Agent -> 차단
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')
echo "DELEGATION VIOLATION: Main Agent가 $TOOL_NAME을 직접 사용하려 합니다. Task(orchestrator, ...)로 위임하세요." >&2
exit 2  # 차단
```

### 실현 가능성: **중간**

- transcript_path에 "subagents" 포함 여부로 구분하는 것은 문서화된 공식 방법이 아님
- Claude Code 버전 업데이트로 경로 형식이 변경될 수 있음
- 하지만 현재 동작하는 것은 확인됨 (기존 shared-context 훅에서 활용 중)

### 효과성: **높음 (도구 수준에서 물리적 차단)**

- Edit/Write/Bash 호출 자체를 exit 2로 차단
- stderr 피드백이 Claude에게 전달되어 위임을 유도
- 프롬프트 무시와 무관하게 강제됨

### 부작용

- **Read/Grep/Glob까지 차단하면**: 서브에이전트 호출 전 컨텍스트 파악이 불가능해져 Orchestrator에게 불충분한 정보만 전달
- **Edit/Write/Bash만 차단하면**: 파일 읽기/분석 후 직접 응답하는 위반은 방지 못함
- **Skill 도구 호출도 차단 대상에서 제외해야**: Main Agent의 정당한 슬래시 커맨드 호출이 차단됨
- **오탐 위험**: transcript_path 패턴이 예상과 다르면 서브에이전트도 차단될 수 있음

### 구현 난이도: **중간**

- 훅 스크립트 작성은 간단
- 경로 기반 구분 로직의 정확성 검증이 필요
- 테스트 환경에서 충분한 검증 필요

### 평가: ★★★★☆

가장 효과적인 방법이지만, Main Agent/서브에이전트 구분이 비공식 방법에 의존하는 리스크가 있다.

---

## 방법 2: Stop 훅으로 위반 사후 감지

### 메커니즘

Main Agent 응답 완료(Stop 이벤트) 시, transcript를 분석하여 Orchestrator 위임 없이 직접 처리한 경우를 감지한다.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/check-delegation.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/bin/bash
INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id')

# 최근 응답에서 Task(orchestrator, ...) 또는 Skill 호출이 있었는지 확인
# transcript를 분석하여 도구 사용만 있고 위임이 없었으면 경고
TRANSCRIPT_PATH=$(echo "$INPUT" | jq -r '.transcript_path // ""')

if [ -f "$TRANSCRIPT_PATH" ]; then
  # 마지막 턴에서 Task 도구 호출이 있었는지 확인
  LAST_TURN=$(tail -50 "$TRANSCRIPT_PATH")
  if echo "$LAST_TURN" | grep -q "orchestrator"; then
    exit 0  # 위임 있음
  fi
  # 슬래시 커맨드(Skill 호출)가 있었는지 확인
  if echo "$LAST_TURN" | grep -q '"Skill"'; then
    exit 0  # 슬래시 커맨드 처리
  fi

  echo "위임 없이 직접 처리했습니다. 자연어 요청은 Task(orchestrator, ...)로 위임하세요." >&2
  exit 2  # Stop은 exit 2로 차단 가능 -> Claude에게 재시도 유도
fi

exit 0
```

### 실현 가능성: **높음**

- Stop 훅은 exit 2로 차단 가능 (공식 스펙)
- transcript 분석으로 위임 여부 확인 가능

### 효과성: **중간**

- 사후 감지이므로 이미 처리된 작업을 되돌릴 수 없음
- 하지만 exit 2로 차단하면 Claude가 "이전 응답이 위반이므로 다시 시도"할 수 있음
- 반복 피드백으로 학습 효과 기대 가능

### 부작용

- 단순 인사/확인 응답도 위반으로 오탐할 수 있음
- transcript 분석 정확도에 의존
- 이미 수행된 파일 변경을 되돌리지 않음

### 구현 난이도: **높음**

- transcript JSONL 파싱이 복잡
- 오탐/미탐 튜닝에 시간 소요
- Stop + exit 2의 반복 루프 위험 (무한 재시도)

### 평가: ★★★☆☆

차단보다 감지/경고에 가까워서, 방법 1의 보완재로 적합하다.

---

## 방법 3: UserPromptSubmit 훅으로 요청 분류

### 메커니즘

사용자 프롬프트가 제출될 때 `/`로 시작하는지 확인하고, 자연어 요청이면 "위임 필수" 경고를 주입한다.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "$CLAUDE_PROJECT_DIR/.claude/hooks/classify-prompt.sh"
          }
        ]
      }
    ]
  }
}
```

```bash
#!/bin/bash
INPUT=$(cat)
PROMPT=$(echo "$INPUT" | jq -r '.user_prompt // ""')

# 슬래시 커맨드가 아닌 자연어 요청
if ! echo "$PROMPT" | grep -q '^/'; then
  # systemMessage로 경고 주입 가능 (단, UserPromptSubmit에서의 지원 여부 확인 필요)
  echo '{"systemMessage":"[DELEGATION RULE] 이 요청은 슬래시 커맨드가 아닙니다. 반드시 Task(orchestrator, ...)로 위임하세요. 직접 처리하지 마세요."}'
  exit 0
fi

exit 0
```

### 실현 가능성: **중간-높음**

- UserPromptSubmit은 exit 2로 프롬프트 자체를 차단할 수 있음
- systemMessage 출력으로 Claude에게 컨텍스트 주입 가능 (prompt 타입과 유사)

### 효과성: **낮음-중간**

- 경고를 주입해도 프롬프트 지시와 동일한 효력 -> LLM이 무시할 수 있음
- 프롬프트를 차단(exit 2)하면 사용자 경험이 나빠짐 (정당한 요청도 차단)
- 결국 "더 강한 프롬프트"에 불과

### 부작용

- 모든 자연어 입력에 경고가 주입되어 컨텍스트 낭비
- 사용자가 직접 타이핑하는 자연어 질문도 차단/경고 대상

### 구현 난이도: **낮음**

- 스크립트가 단순

### 평가: ★★☆☆☆

프롬프트 강화의 변형으로, 근본적인 해결책이 되지 못한다.

---

## 방법 4: settings.json permissions.deny 활용

### 메커니즘

settings.json의 `permissions.deny`로 특정 도구를 완전 차단한다.

```json
{
  "permissions": {
    "deny": [
      "Edit",
      "Write"
    ],
    "allow": [
      "Read",
      "Glob",
      "Grep",
      "Skill",
      "Task"
    ]
  }
}
```

### 핵심 문제: 전역 적용

permissions는 **세션 전체에 적용**된다. Main Agent뿐 아니라 모든 서브에이전트에게도 동일하게 적용되므로, Edit/Write를 deny하면 coder 에이전트도 코드를 수정할 수 없게 된다.

### 실현 가능성: **높음** (설정만 하면 됨)

### 효과성: **역효과**

- 서브에이전트의 정당한 도구 사용까지 차단
- 전체 워크플로우가 멈춤

### 부작용: **치명적**

- coder가 Edit/Write 불가
- 사실상 모든 코드 변경 작업이 불가능

### 구현 난이도: **매우 낮음**

### 평가: ★☆☆☆☆

**사용 불가.** 에이전트별 권한 분리가 없으므로 무차별 적용.

---

## 방법 5: CLAUDE.md 프롬프트 강화

### 메커니즘

현재 harness.md의 위임 규칙을 더 강력한 프롬프트 패턴으로 강화한다.

### 현재 지시의 한계 분석

```markdown
# 현재 (harness.md)
Main Agent는 코드를 쓰지 않고, 테스트를 실행하지 않고, 직접 분석하거나 판단하지 않는다.
**슬래시 커맨드(`/`로 시작하는 요청)만 해당 스킬로 직접 호출하고, 그 외 모든 자연어 요청은 무조건 Orchestrator에게 위임한다.**
이 규칙에 예외는 없다.
```

위반 원인 분석:
1. **규칙이 본문 중간에 위치**: 시스템 프롬프트에서 위치가 중요 -- 최상단 또는 최하단이 더 효과적
2. **긍정적 지시 부족**: "하지 마라"보다 "반드시 ~하라"가 더 효과적
3. **구체적 도구 목록 미명시**: 어떤 도구를 쓰면 안 되는지 명시하지 않음
4. **자기 검증 루프 없음**: "도구를 호출하기 전에 확인하라"는 지시가 없음
5. **컨텍스트 희석**: harness.md가 매우 길어서 핵심 규칙이 묻힘

### 강화 패턴

```markdown
# ABSOLUTE RULE - DELEGATION (이 규칙은 다른 모든 지시보다 우선한다)

## 자기 검증 체크리스트 (모든 응답 전에 실행)

1. 이 요청이 `/`로 시작하는 슬래시 커맨드인가?
   - YES -> 해당 스킬을 Skill()로 직접 호출
   - NO -> 반드시 Task(orchestrator, "$USER_REQUEST")로 위임. 예외 없음.

2. 나는 지금 다음 도구를 직접 사용하려 하는가?
   - Edit, Write, Bash, Read, Grep, Glob -> FORBIDDEN (Skill/Task 위임만 허용)

## FORBIDDEN 행위 (절대 하지 않을 것)
- Edit 도구 직접 사용
- Write 도구로 코드 파일 수정
- Bash로 서버 상태 확인, 빌드, 테스트 실행
- Read/Grep/Glob로 파일 읽고 직접 분석/응답
- 도구 없이 코드 설명, 버그 진단, 아키텍처 분석

## REQUIRED 행위 (반드시 할 것)
- 모든 자연어 요청 -> Task(orchestrator, "$USER_REQUEST")
- 응답에는 Orchestrator의 결과를 전달하는 것만 허용
```

### 실현 가능성: **높음**

### 효과성: **중간**

- 프롬프트 강화는 위반율을 줄이지만 완전히 방지하지 못함
- 자기 검증 체크리스트 패턴은 효과가 있다고 알려져 있음
- 하지만 컨텍스트가 길어지면 ("긴 대화 후반") 규칙 준수율이 떨어짐
- 특히 "효율성 편향"이 강한 소규모 작업에서 위반 가능성이 높음

### 부작용

- 프롬프트 길이 증가 -> 토큰 비용 증가
- 과도한 제약이 사용자 경험을 해칠 수 있음
- 정당한 도구 사용(예: Read로 컨텍스트 파악 후 위임)도 금지됨

### 구현 난이도: **매우 낮음**

### 평가: ★★★☆☆

기본적으로 적용해야 하지만, 단독으로는 부족하다. 방법 1과 결합해야 효과적.

---

## 방법 6: Stop 훅 + prompt 타입으로 LLM 기반 위반 감지

### 메커니즘

Stop 훅에서 `prompt` 타입을 사용하여, LLM이 직접 위반 여부를 판단한다.

```json
{
  "hooks": {
    "Stop": [
      {
        "hooks": [
          {
            "type": "prompt",
            "prompt": "이 응답이 Task(orchestrator, ...) 위임 없이 직접 코드를 수정하거나, 파일을 분석하거나, 기술적 질문에 직접 답변했는지 판단하세요. 슬래시 커맨드 호출은 정당합니다. 위반이면 'VIOLATION'으로, 아니면 'OK'로 답하세요.",
            "timeout": 30
          }
        ]
      }
    ]
  }
}
```

### 실현 가능성: **높음**

- prompt 타입 훅은 Stop 이벤트에서 공식 지원됨
- LLM이 컨텍스트를 이해하고 판단

### 효과성: **중간-높음**

- bash 스크립트보다 정교한 판단 가능
- "단순 질문에 직접 답변" 같은 미묘한 위반도 감지 가능
- 하지만 LLM 판단도 오류 가능

### 부작용

- 매 응답마다 추가 LLM 호출 -> 비용 및 지연
- 오탐 시 무한 재시도 루프 위험

### 구현 난이도: **낮음**

### 평가: ★★★☆☆

비용 대비 효과가 의문이지만, 방법 1의 보완재로 의미가 있다.

---

## 방법 7: 에이전트 도구 권한 제한 (Main Agent 자체를 에이전트로)

### 메커니즘

Main Agent를 커스텀 에이전트로 정의하고, tools 필드로 허용 도구를 제한한다.

### 근본적 한계

Main Agent는 Claude Code의 최상위 대화 컨텍스트이며, `.claude/agents/` 에이전트와는 다르다. Main Agent를 에이전트 파일로 정의하는 공식 메커니즘은 없다.

서브에이전트의 tools 필드:
```yaml
---
name: navigator
tools:
  - Read
  - Glob
  - Grep
  - Bash
---
```

이것은 **서브에이전트에만 적용**된다. Main Agent에는 tools 필드를 적용할 방법이 없다.

### 실현 가능성: **불가**

### 평가: ★☆☆☆☆

현재 Claude Code 아키텍처에서 Main Agent의 도구 권한을 제한하는 공식 방법이 없다.

---

## 방법 8: 메모리 시스템 활용 (자기 교정)

### 메커니즘

자동 메모리(auto memory)에 위반 패턴을 기록하여 Claude가 스스로 학습하도록 유도한다.

```
~/.claude/projects/-home-hoodcat-Projects-{project}/memory/MEMORY.md

## 위반 기록
- [날짜] Main Agent가 Edit 도구를 직접 사용하여 파일 수정 (위반)
- [날짜] Read + 직접 응답으로 위임 규칙 위반
-> 이런 패턴이 발생하면 반드시 Task(orchestrator, ...) 사용
```

### 실현 가능성: **높음**

- 프로젝트 메모리에 기록하면 매 세션 시작 시 로드됨

### 효과성: **낮음**

- 메모리는 참고 자료일 뿐, 강제력이 없음
- 프롬프트 지시와 동일한 한계 (LLM이 무시할 수 있음)
- 위반이 발생할 때마다 수동으로 기록해야 함

### 부작용

- 메모리 파일 비대화
- 위반 기록이 쌓이면 오히려 "자주 위반하는 것이 정상"이라는 잘못된 학습 가능

### 구현 난이도: **매우 낮음**

### 평가: ★★☆☆☆

보조적 수단으로만 의미가 있다.

---

## 방법 9: PostToolUse 훅으로 위반 시 롤백

### 메커니즘

PostToolUse에서 Main Agent의 도구 사용을 감지하면, 변경 사항을 git으로 롤백한다.

```bash
#!/bin/bash
INPUT=$(cat)
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path // ""')
TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name')

# 서브에이전트면 통과
if echo "$TRANSCRIPT" | grep -q "/subagents/"; then
  exit 0
fi

# Main Agent의 Edit/Write 사용 감지
if [ "$TOOL_NAME" = "Edit" ] || [ "$TOOL_NAME" = "Write" ]; then
  # git으로 변경 사항 롤백
  git -C "$CLAUDE_PROJECT_DIR" checkout -- .
  echo "Main Agent의 직접 수정이 롤백되었습니다. Task(orchestrator, ...)로 위임하세요." >&2
  exit 2
fi

exit 0
```

### 실현 가능성: **중간**

- PostToolUse는 exit 2로 피드백 전달 가능 (차단은 아님)
- git checkout으로 롤백 가능

### 효과성: **중간**

- 변경을 되돌리므로 결과적으로 위반이 무효화됨
- 하지만 PostToolUse는 이미 도구가 실행된 후이므로 예방이 아닌 치료

### 부작용

- git checkout이 워킹 디렉토리의 다른 변경까지 롤백할 수 있음
- 서브에이전트와의 경합 조건 위험
- git 상태가 복잡한 경우 예상치 못한 결과

### 구현 난이도: **높음** (안전한 롤백 로직이 복잡)

### 평가: ★★☆☆☆

위험하고 복잡하다. 방법 1(PreToolUse 차단)이 더 깔끔하다.

---

## 방법 10: UserPromptSubmit에서 자동 위임 변환

### 메커니즘

사용자의 자연어 요청을 UserPromptSubmit 훅에서 가로채어, 자동으로 "Task(orchestrator, ...)" 형태로 변환한다.

### 한계

UserPromptSubmit 훅은 프롬프트를 **수정하여 전달하는 기능이 없다**. exit 2로 차단하거나, systemMessage를 주입할 수 있을 뿐이다. 프롬프트 자체를 변환하는 것은 불가능.

### 실현 가능성: **불가**

### 평가: ★☆☆☆☆

---

## 종합 비교

| 방법 | 실현 가능성 | 효과성 | 부작용 | 구현 난이도 | 총평 |
|------|-----------|--------|--------|-----------|------|
| 1. PreToolUse 차단 | 중간 | **높음** | 중간 | 중간 | ★★★★☆ |
| 2. Stop 사후 감지 | 높음 | 중간 | 낮음 | 높음 | ★★★☆☆ |
| 3. UserPromptSubmit 경고 | 중간-높음 | 낮음-중간 | 낮음 | 낮음 | ★★☆☆☆ |
| 4. permissions.deny | 높음 | **역효과** | **치명적** | 매우 낮음 | ★☆☆☆☆ |
| 5. CLAUDE.md 강화 | 높음 | 중간 | 낮음 | 매우 낮음 | ★★★☆☆ |
| 6. Stop+prompt LLM 감지 | 높음 | 중간-높음 | 중간(비용) | 낮음 | ★★★☆☆ |
| 7. 에이전트 도구 제한 | **불가** | - | - | - | ★☆☆☆☆ |
| 8. 메모리 자기 교정 | 높음 | 낮음 | 낮음 | 매우 낮음 | ★★☆☆☆ |
| 9. PostToolUse 롤백 | 중간 | 중간 | **높음** | 높음 | ★★☆☆☆ |
| 10. 자동 위임 변환 | **불가** | - | - | - | ★☆☆☆☆ |

---

## 최종 권장안: 3층 방어 (Defense in Depth)

단일 방법으로는 완벽한 방지가 불가능하다. 다음 3층을 결합하여 위반율을 최소화한다.

### 1층: CLAUDE.md 프롬프트 강화 (방법 5)

**비용: 낮음 / 효과: 위반율 50-70% 감소 (추정)**

harness.md 최상단에 "자기 검증 체크리스트" 패턴을 추가한다:

```markdown
# CRITICAL: DELEGATION RULE (이 규칙이 다른 모든 지시보다 우선한다)

## 모든 응답 전 자기 검증
1. 이 요청이 `/`로 시작하는가? -> YES: 해당 스킬 호출 / NO: Task(orchestrator, ...)
2. 나는 Edit/Write/Bash를 직접 쓰려는가? -> FORBIDDEN. 즉시 중단하고 위임.
3. 나는 Read/Grep으로 파일을 읽고 직접 답변하려는가? -> FORBIDDEN. 위임.
```

이것을 harness.md 최상단(첫 번째 섹션)에 배치한다.

### 2층: PreToolUse 훅으로 Edit/Write 차단 (방법 1)

**비용: 중간 / 효과: 물리적으로 코드 수정 차단**

Main Agent의 Edit/Write 사용을 transcript_path 기반으로 감지하고 차단한다. Read/Grep/Glob/Bash는 차단하지 않는다 (서브에이전트 호출 시 컨텍스트 파악용으로 필요할 수 있으므로).

차단 대상:
- `Edit` (항상 차단 -- Main Agent는 코드를 수정하면 안 됨)
- `Write` (소스 코드 확장자일 때만 차단)

비차단 대상:
- `Read`, `Grep`, `Glob` (읽기 전용은 허용 -- 컨텍스트 파악 후 위임 유도)
- `Bash` (완전 차단 시 서브에이전트도 영향 -- 선택적)
- `Skill`, `Task` (정당한 위임 수단)

### 3층: Stop 훅으로 위반 감지 및 경고 (방법 2 또는 6)

**비용: 낮음 / 효과: 사후 교정**

Main Agent 응답 완료 시, Task/Skill 호출 없이 직접 응답한 경우를 감지하여 피드백한다. command 타입으로 구현하되, 오탐을 줄이기 위해 "슬래시 커맨드도 Task/Skill 호출도 없는 응답"만 대상으로 한다.

### 구현 우선순위

1. **즉시**: CLAUDE.md 프롬프트 강화 (1층) -- 코드 변경 없음, 텍스트 수정만
2. **다음**: PreToolUse 훅 구현 (2층) -- 가장 효과적인 물리적 차단
3. **선택**: Stop 훅 구현 (3층) -- 2층으로 잡지 못하는 "도구 없이 직접 답변" 위반 감지

### 수용해야 할 한계

1. **"도구 없이 직접 답변"은 훅으로 차단 불가**: Read/Grep 없이 기존 컨텍스트만으로 직접 응답하는 위반은 PreToolUse로 잡을 수 없다. Stop 훅으로 사후 감지만 가능.

2. **Main Agent/서브에이전트 구분은 비공식**: transcript_path 기반 구분이 향후 Claude Code 업데이트로 깨질 수 있다.

3. **100% 방지는 불가능**: LLM의 본질적 한계로, 프롬프트 지시 위반을 완벽히 방지하는 것은 불가능하다. 위반율을 최소화하는 것이 목표.

4. **Read/Grep 허용의 트레이드오프**: Main Agent의 Read/Grep 사용을 허용하면 "파일 읽고 직접 분석" 위반이 가능하지만, 차단하면 Orchestrator에게 충분한 컨텍스트를 전달할 수 없다. 현실적으로 허용이 더 낫다.

---

## 부록: Claude Code 훅 스펙 요약

본 조사에서 참조한 훅 스펙의 상세 내용은 별도 문서에 정리되어 있다:
- `/home/hoodcat/Projects/hoodcat-harness/docs/research-claude-code-hooks-spec-20260216.md`

## 출처

- Claude Code 공식 문서 - Hooks: https://code.claude.com/docs/en/hooks
- Claude Code 공식 GitHub - Hook Development SKILL.md
- 기존 프로젝트 훅 스크립트 분석 (`.claude/hooks/`)
- 기존 프로젝트 설정 분석 (`.claude/settings.json`)
- Claude Code 프롬프트 주입 관계 조사 (`docs/research-agent-skill-prompt-injection-20260212.md`)
