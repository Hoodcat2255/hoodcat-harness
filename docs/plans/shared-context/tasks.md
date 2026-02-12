# Shared Context System - Implementation Tasks

## 구현 순서 및 의존관계

```
T1 (저장소 구조) ─────────────────────────┐
                                          ├──→ T3 (SubagentStart Hook)
T2 (세션 관리 Hook) ──────────────────────┤
                                          ├──→ T4 (SubagentStop Hook)
                                          │
                                          └──→ T5 (에이전트 지침 업데이트)
                                                    │
                                                    └──→ T6 (settings.json 통합)
                                                              │
                                                              └──→ T7 (검증 및 문서화)
```

---

## T1: 공유 컨텍스트 저장소 구조 생성 [S]

**복잡도**: S (소)
**의존**: 없음
**산출물**: 디렉토리 구조, 설정 파일, .gitignore 업데이트

### 작업 내용

1. `.claude/shared-context/` 디렉토리 생성
2. `.gitignore`에 `.claude/shared-context/` 추가
3. 기본 설정 파일 `.claude/shared-context-config.json` 생성:
   ```json
   {
     "ttl_hours": 24,
     "max_summary_chars": 4000,
     "max_transcript_lines": 500,
     "filters": {
       "reviewer": ["navigation", "code_changes"],
       "security": ["navigation", "code_changes"],
       "architect": ["navigation", "code_changes"],
       "coder": ["navigation"],
       "committer": ["navigation", "code_changes"],
       "navigator": []
     }
   }
   ```

### 검증 기준

- [ ] `.claude/shared-context/` 디렉토리 존재
- [ ] `.gitignore`에 해당 경로 포함
- [ ] 설정 파일이 유효한 JSON

---

## T2: 세션 수명주기 Hook 작성 [S]

**복잡도**: S (소)
**의존**: T1
**산출물**: `shared-context-cleanup.sh`, `shared-context-finalize.sh`

### 작업 내용

1. `.claude/hooks/shared-context-cleanup.sh`:
   - SessionStart hook
   - TTL이 만료된 세션 디렉토리 삭제
   - 현재 세션의 디렉토리 생성: `.claude/shared-context/{session-id}/`
   - `_config.json` 초기화 (기본 설정 복사)

2. `.claude/hooks/shared-context-finalize.sh`:
   - SessionEnd hook
   - 현재 세션의 최종 `_summary.md` 생성 (또는 기존 것 유지)
   - 에이전트 수, 총 컨텍스트 크기 등 메트릭 로깅

### 스크립트 골격

```bash
#!/usr/bin/env bash
# shared-context-cleanup.sh - SessionStart: 만료 세션 정리, 현재 세션 초기화
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
PROJECT_DIR="$CLAUDE_PROJECT_DIR"
CONTEXT_DIR="$PROJECT_DIR/.claude/shared-context"
CONFIG_FILE="$PROJECT_DIR/.claude/shared-context-config.json"

# TTL 기반 정리
TTL_HOURS=$(jq -r '.ttl_hours // 24' "$CONFIG_FILE" 2>/dev/null || echo 24)
find "$CONTEXT_DIR" -maxdepth 1 -type d -mmin +$((TTL_HOURS * 60)) -exec rm -rf {} + 2>/dev/null || true

# 현재 세션 디렉토리 생성
mkdir -p "$CONTEXT_DIR/$SESSION_ID"

exit 0
```

### 검증 기준

- [ ] cleanup.sh가 TTL 만료 디렉토리를 삭제
- [ ] cleanup.sh가 현재 세션 디렉토리를 생성
- [ ] finalize.sh가 안전하게 종료 (exit 0)
- [ ] 에러 시에도 exit 0 보장

---

## T3: SubagentStart Hook 작성 [M]

**복잡도**: M (중)
**의존**: T1, T2
**산출물**: `shared-context-inject.sh`

### 작업 내용

1. `.claude/hooks/shared-context-inject.sh`:
   - `_summary.md` 읽기
   - 에이전트 타입별 필터링 (`_config.json`의 `filters`)
   - 크기 제한 적용 (`max_summary_chars`)
   - 공유 컨텍스트 디렉토리 경로를 포함한 기록 지침 추가
   - `additionalContext`로 JSON 출력

### 핵심 로직

```bash
#!/usr/bin/env bash
# shared-context-inject.sh - SubagentStart: 공유 컨텍스트 주입
set -euo pipefail

INPUT=$(cat)
SESSION_ID=$(echo "$INPUT" | jq -r '.session_id // ""')
AGENT_TYPE=$(echo "$INPUT" | jq -r '.agent_type // ""')
AGENT_ID=$(echo "$INPUT" | jq -r '.agent_id // ""')
PROJECT_DIR="$CLAUDE_PROJECT_DIR"

CONTEXT_DIR="$PROJECT_DIR/.claude/shared-context/$SESSION_ID"
SUMMARY_FILE="$CONTEXT_DIR/_summary.md"
CONFIG_FILE="$PROJECT_DIR/.claude/shared-context-config.json"

# 공유 컨텍스트가 없으면 기록 지침만 출력
if [ ! -f "$SUMMARY_FILE" ]; then
  WRITE_INSTRUCTION="작업 완료 시, 핵심 발견 사항을 다음 파일에 기록하세요: $CONTEXT_DIR/${AGENT_TYPE}-${AGENT_ID}.md"
  jq -n --arg ctx "$WRITE_INSTRUCTION" '{
    hookSpecificOutput: {
      hookEventName: "SubagentStart",
      additionalContext: $ctx
    }
  }'
  exit 0
fi

# 요약 읽기 + 필터링 + 크기 제한
MAX_CHARS=$(jq -r '.max_summary_chars // 4000' "$CONFIG_FILE" 2>/dev/null || echo 4000)
SUMMARY=$(head -c "$MAX_CHARS" "$SUMMARY_FILE")

# 기록 지침 추가
WRITE_INSTRUCTION="\n\n---\n작업 완료 시, 핵심 발견 사항을 다음 파일에 기록하세요: $CONTEXT_DIR/${AGENT_TYPE}-${AGENT_ID}.md"
FULL_CONTEXT="${SUMMARY}${WRITE_INSTRUCTION}"

jq -n --arg ctx "$FULL_CONTEXT" '{
  hookSpecificOutput: {
    hookEventName: "SubagentStart",
    additionalContext: $ctx
  }
}'

exit 0
```

### 검증 기준

- [ ] 공유 컨텍스트가 없으면 기록 지침만 주입
- [ ] 공유 컨텍스트가 있으면 요약 + 기록 지침 주입
- [ ] 크기 제한이 적용됨
- [ ] 유효한 JSON 출력
- [ ] 에러 시 exit 0 (빈 출력)

---

## T4: SubagentStop Hook 작성 [L]

**복잡도**: L (대)
**의존**: T1, T2
**산출물**: `shared-context-collect.sh`

### 작업 내용

1. `.claude/hooks/shared-context-collect.sh`:
   - 에이전트 자발적 기록 파일 확인
   - 자발적 기록이 없으면 transcript에서 핵심 정보 추출 (보완)
   - `_summary.md` 업데이트 (flock 잠금)
   - 기존 `subagent-monitor.sh` 로깅과 병행

### Transcript 파싱 로직

```bash
# transcript에서 Write/Edit 도구 호출 추출
extract_file_changes() {
  local transcript="$1"
  local max_lines="$2"

  tail -n "$max_lines" "$transcript" | \
    jq -r 'select(.type == "tool_result" and .tool_name == ("Write","Edit")) |
      "- \(.tool_input.file_path // "unknown"): \(.tool_response.success // "unknown")"' \
    2>/dev/null || echo "- (transcript 파싱 실패)"
}
```

### _summary.md 업데이트 로직

```bash
update_summary() {
  local context_dir="$1"
  local summary_file="$context_dir/_summary.md"
  local lock_file="$context_dir/.lock"

  (
    flock -w 5 200 || { echo "Lock timeout" >&2; return; }

    # 기존 요약 읽기 (없으면 헤더 생성)
    if [ ! -f "$summary_file" ]; then
      echo "# Shared Context Summary" > "$summary_file"
      echo "> Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)" >> "$summary_file"
      echo "" >> "$summary_file"
    fi

    # 새 엔트리 추가
    cat "$new_entry_file" >> "$summary_file"

    # 타임스탬프 업데이트
    sed -i "s/^> Updated:.*/> Updated: $(date -u +%Y-%m-%dT%H:%M:%SZ)/" "$summary_file"

  ) 200>"$lock_file"
}
```

### 검증 기준

- [ ] 에이전트 자발적 기록이 있으면 그것을 사용
- [ ] 자발적 기록이 없으면 transcript에서 추출
- [ ] transcript 파싱 실패 시 안전하게 무시
- [ ] _summary.md가 flock으로 안전하게 업데이트
- [ ] 기존 subagent-monitor.sh와 충돌 없음
- [ ] exit 0 보장

---

## T5: 에이전트 정의 업데이트 [M]

**복잡도**: M (중)
**의존**: T1
**산출물**: 수정된 에이전트 정의 파일 8개

### 작업 내용

8개 에이전트 정의(`.claude/agents/*.md`)에 Shared Context Protocol 섹션 추가.

모든 에이전트에 공통 지침:

```markdown
## Shared Context Protocol

이전 에이전트의 작업 결과가 additionalContext로 주입되면, 이를 참고하여 중복 작업을 줄인다.

작업 완료 시, 핵심 발견 사항을 지정된 공유 컨텍스트 파일에 기록한다.
additionalContext에 기록 경로가 포함되어 있다.

기록 형식:
## {Agent Type} Report
### Findings
- [발견 사항 목록]
### Files
- [관련 파일 목록]
### Issues
- [발견된 이슈 목록]
```

에이전트 타입별 커스터마이즈:
- **navigator**: 탐색한 파일 목록, 코드 패턴, 의존성 관계
- **coder**: 변경/생성한 파일, 핵심 변경 내용
- **reviewer/security/architect**: 리뷰 결과 (PASS/WARN/BLOCK), 주요 지적 사항
- **committer**: 커밋 해시, 변경 요약
- **researcher**: 조사 결과 요약, 핵심 출처
- **workflow**: 워크플로우 Phase 진행 상황

### 검증 기준

- [ ] 8개 에이전트 정의에 Shared Context Protocol 섹션 추가
- [ ] 에이전트 타입별 기록 형식 커스터마이즈
- [ ] 기존 에이전트 기능에 영향 없음

---

## T6: settings.json 통합 [S]

**복잡도**: S (소)
**의존**: T2, T3, T4
**산출물**: 수정된 `.claude/settings.local.json`

### 작업 내용

기존 `.claude/settings.local.json`에 새 hooks 등록:

```json
{
  "hooks": {
    "SessionStart": [
      {
        "matcher": "startup",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-cleanup.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "SubagentStart": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-inject.sh"
          }
        ]
      }
    ],
    "SubagentStop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/subagent-monitor.sh"
          }
        ]
      },
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-collect.sh"
          }
        ]
      }
    ],
    "SessionEnd": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/shared-context-finalize.sh",
            "timeout": 5
          }
        ]
      }
    ],
    "TaskCompleted": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/task-quality-gate.sh"
          }
        ]
      }
    ],
    "TeammateIdle": [
      {
        "matcher": "",
        "hooks": [
          {
            "type": "command",
            "command": "\"$CLAUDE_PROJECT_DIR\"/.claude/hooks/teammate-idle-check.sh"
          }
        ]
      }
    ]
  }
}
```

### 검증 기준

- [ ] 기존 hooks (subagent-monitor, task-quality-gate, teammate-idle-check) 보존
- [ ] 새 hooks 등록 (shared-context-cleanup, inject, collect, finalize)
- [ ] 유효한 JSON

---

## T7: 검증 및 문서화 [M]

**복잡도**: M (중)
**의존**: T6
**산출물**: 테스트 스크립트, harness.md 업데이트

### 작업 내용

1. **통합 테스트 스크립트** `.claude/hooks/test-shared-context.sh`:
   - mock 입력으로 각 hook을 독립 실행하여 검증
   - cleanup → inject (빈 상태) → collect → inject (있는 상태) 시나리오
   - 동시 쓰기 테스트 (flock 검증)

2. **harness.md 업데이트**:
   - Shared Context System 섹션 추가
   - 사용법, 설정, 문제 해결 가이드

3. **CLAUDE.md 업데이트**:
   - 프로젝트 개요에 공유 컨텍스트 시스템 언급

### 검증 기준

- [ ] 테스트 스크립트가 모든 hook을 독립 실행 가능
- [ ] 모든 hook이 exit 0으로 종료
- [ ] 문서에 설정 방법, 문제 해결 가이드 포함

---

## 요약

| Task | 이름 | 복잡도 | 의존 |
|------|------|--------|------|
| T1 | 저장소 구조 생성 | S | - |
| T2 | 세션 수명주기 Hook | S | T1 |
| T3 | SubagentStart Hook | M | T1, T2 |
| T4 | SubagentStop Hook | L | T1, T2 |
| T5 | 에이전트 정의 업데이트 | M | T1 |
| T6 | settings.json 통합 | S | T2, T3, T4 |
| T7 | 검증 및 문서화 | M | T6 |

**총 7개 태스크**: S 3개, M 3개, L 1개

**구현 순서**: T1 -> (T2, T5 병렬) -> (T3, T4 병렬) -> T6 -> T7
