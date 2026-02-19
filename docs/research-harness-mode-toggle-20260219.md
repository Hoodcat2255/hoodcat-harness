# Harness 모드 전환 기능 조사

> 날짜: 2026-02-19
> 목적: harness 모드와 일반 모드를 동적으로 전환하는 메커니즘 조사

## 1. 현재 Harness 활성화 메커니즘 분석

harness가 설치된 프로젝트에서 Claude Code의 동작을 변경하는 요소는 크게 4가지이다.

### 1.1. CLAUDE.md의 @import (프롬프트 레벨)

```
# 대상 프로젝트의 CLAUDE.md 최상단
@.claude/harness.md
```

- Claude Code는 세션 시작 시 CLAUDE.md를 읽고, `@` import를 재귀적으로 해석한다.
- `harness.md`에는 Main Agent의 역할 정의, 위임 규칙, FORBIDDEN/ALLOWED 행위 목록이 포함되어 있다.
- **이것이 harness 동작의 핵심**. 이 import가 없으면 Claude는 일반 모드로 동작한다.

### 1.2. .claude/settings.json (훅 & 상태표시줄)

```json
{
  "statusLine": { ... },
  "hooks": {
    "PreToolUse": [{ "matcher": "Edit|Write", "hooks": [{ "command": "enforce-delegation.sh" }] }],
    "SessionStart": [...],
    "SubagentStart": [...],
    "SubagentStop": [...],
    "SessionEnd": [...],
    "TaskCompleted": [...],
    "TeammateIdle": [...]
  }
}
```

- 9개 훅이 7개 이벤트에 연결되어 있다.
- `enforce-delegation.sh`: Main Agent의 Edit/Write를 물리적으로 차단 (exit 2)
- `shared-context-*.sh`: 에이전트 간 컨텍스트 공유
- `task-quality-gate.sh`: 태스크 완료 시 빌드/테스트 검증
- `notify-telegram.sh`: 텔레그램 알림
- `teammate-idle-check.sh`: 팀원 유휴 감지

### 1.3. .claude/skills/ (12개 스킬)

- 스킬 파일은 Claude Code가 `/` 명령어로 호출할 수 있는 기능을 정의한다.
- harness 없이도 Claude는 기본 도구(Edit, Write, Bash 등)를 직접 사용하므로, 스킬이 없다고 기능이 줄지 않는다.
- 스킬은 "추가 기능"이므로 비활성화의 영향이 적다.

### 1.4. .claude/agents/ (8개 에이전트)

- Task()로 호출되는 에이전트 정의.
- harness.md의 위임 규칙이 없으면 Main Agent가 에이전트를 호출하지 않으므로 실질적으로 비활성화된다.

### 활성화 의존 관계

```
CLAUDE.md @import harness.md  <-- 핵심 (프롬프트 레벨 규칙)
    |
    +-- harness.md가 Main Agent 동작을 결정
    +-- skills/ 와 agents/ 는 harness.md에 의해 참조

settings.json hooks  <-- 물리적 강제 (도구 차단, 자동화)
    |
    +-- enforce-delegation.sh가 Edit/Write를 차단
    +-- 기타 훅이 자동화 기능 제공
```

## 2. 모드 전환 접근법 분석

### 접근법 A: CLAUDE.md @import 주석 토글

**방법**: CLAUDE.md의 `@.claude/harness.md` 줄을 주석 처리하거나 제거/복원한다.

```bash
# 비활성화
sed -i 's/^@\.claude\/harness\.md$/# @.claude\/harness.md (disabled)/' CLAUDE.md

# 활성화
sed -i 's/^# @\.claude\/harness\.md (disabled)$/@.claude\/harness.md/' CLAUDE.md
```

| 장점 | 단점 |
|------|------|
| 가장 직접적이고 확실한 방법 | CLAUDE.md를 수정하므로 git diff가 발생 |
| harness.md 전체가 비활성화됨 | 이미 실행 중인 세션에는 즉시 반영되지 않음 (새 세션에서만) |
| settings.json 훅은 여전히 동작함 | settings.json 훅이 독립적으로 남아있어 불완전한 비활성화 |

**문제점**: 이 방법만으로는 `enforce-delegation.sh` 훅이 여전히 Edit/Write를 차단한다. settings.json도 함께 처리해야 한다.

### 접근법 B: settings.json의 hooks 전체 토글

**방법**: settings.json을 비활성화 버전으로 교체하거나, hooks 섹션을 비운다.

```bash
# 비활성화: 훅 섹션 제거한 settings.json으로 교체
mv .claude/settings.json .claude/settings.json.harness
echo '{}' > .claude/settings.json

# 활성화: 원본 복원
mv .claude/settings.json.harness .claude/settings.json
```

| 장점 | 단점 |
|------|------|
| 훅이 완전히 비활성화됨 | 프롬프트 규칙(harness.md)은 여전히 활성 |
| statusline도 비활성화 가능 | 사용자 커스텀 설정(statusline 등)도 함께 사라짐 |
| 새 세션에서 즉시 반영 | 파일 교체 방식이라 사용자가 직접 관리해야 함 |

### 접근법 C: 환경변수 기반 조건부 분기

**방법**: 모든 훅 스크립트에 환경변수 체크를 추가하고, harness.md에도 조건부 지침을 넣는다.

```bash
# 모든 훅 스크립트 최상단에 추가
if [ "${HARNESS_MODE:-on}" = "off" ]; then
  exit 0  # 훅 비활성화
fi
```

```bash
# 비활성화
export HARNESS_MODE=off

# 활성화
export HARNESS_MODE=on  # 또는 unset
```

| 장점 | 단점 |
|------|------|
| 파일 수정 없이 환경변수로 제어 | harness.md의 프롬프트 규칙은 환경변수로 조건부 적용 불가 |
| 훅 단위로 세밀한 제어 가능 | Claude Code의 CLAUDE.md 파싱은 조건부 로딩을 지원하지 않음 |
| `.claude/.env`에 설정 가능 | 훅만 비활성화되고 프롬프트 규칙은 유지되어 불완전 |

**근본적 한계**: Claude Code의 `@import`는 무조건적이다. 환경변수나 조건부 로딩을 지원하지 않으므로, harness.md의 프롬프트 규칙("Main Agent는 직접 코드를 수정하면 안 된다")은 환경변수로 비활성화할 수 없다.

### 접근법 D: harness.sh에 `mode` 서브커맨드 추가 (A + B 통합)

**방법**: `harness.sh mode on|off` 명령을 만들어 CLAUDE.md import와 settings.json을 함께 토글한다.

```bash
harness mode off /path/to/project   # harness 비활성화
harness mode on /path/to/project    # harness 활성화
harness mode status /path/to/project # 현재 상태 확인
```

내부 동작:
1. CLAUDE.md에서 `@.claude/harness.md` 줄을 주석 처리/복원
2. `.claude/settings.json`을 `.claude/settings.json.harness`로 이동/복원
3. `.harness-meta.json`에 `"mode": "off"` 기록

| 장점 | 단점 |
|------|------|
| 원커맨드로 완전한 전환 | 새 세션에서만 반영 (실행 중 세션 영향 없음) |
| CLAUDE.md + settings.json을 동시에 처리 | skills/ 와 agents/ 파일은 디스크에 남아 있음 (무해) |
| 상태 추적 가능 (.harness-meta.json) | git diff 발생 (CLAUDE.md 변경) |
| 기존 `harness.sh` 인프라 활용 | 구현 복잡도가 적절 |
| `harness.sh status`에 모드 표시 가능 | |

### 접근법 E: .claude/ 디렉토리 자체를 이동/심볼릭 링크

**방법**: `.claude/` 디렉토리를 임시 이름으로 이동하거나, 심볼릭 링크로 전환한다.

```bash
# 비활성화
mv .claude .claude.disabled

# 활성화
mv .claude.disabled .claude
```

| 장점 | 단점 |
|------|------|
| 가장 단순하고 완전한 비활성화 | agent-memory, log 등 런타임 데이터도 사라짐 |
| 모든 harness 요소가 즉시 사라짐 | 실행 중 세션에 영향 (파일을 찾지 못함) |
| | CLAUDE.md의 @import가 깨짐 (파일 없음 에러) |
| | 너무 과격한 접근 |

### 접근법 F: 두 벌의 settings.json 파일 관리

**방법**: `settings.harness.json`과 `settings.plain.json`을 두고 `settings.json`에 심볼릭 링크.

```bash
# 비활성화
ln -sf settings.plain.json .claude/settings.json

# 활성화
ln -sf settings.harness.json .claude/settings.json
```

| 장점 | 단점 |
|------|------|
| settings 전환이 깔끔함 | CLAUDE.md import를 별도로 처리해야 함 |
| 사용자 커스텀 설정 보존 가능 | 두 파일을 동기화해야 하는 관리 부담 |
| | 접근법 D의 하위 구성 요소로 사용 가능 |

## 3. 비교 요약

| 접근법 | 완전성 | 구현 난이도 | 사용 편의성 | 파일 수정 | 권장 |
|--------|--------|------------|------------|----------|------|
| A: @import 주석 | 부분적 (훅 유지) | 낮음 | 중간 | CLAUDE.md | X |
| B: settings.json 교체 | 부분적 (프롬프트 유지) | 낮음 | 중간 | settings.json | X |
| C: 환경변수 | 부분적 (프롬프트 불가) | 중간 | 높음 | 훅 스크립트 | X |
| **D: harness.sh mode** | **완전** | **중간** | **높음** | CLAUDE.md + settings | **O** |
| E: .claude/ 이동 | 과도 | 낮음 | 낮음 | 디렉토리 | X |
| F: 심볼릭 링크 | 부분적 | 중간 | 중간 | settings.json | X |

## 4. 추천: 접근법 D (harness.sh mode 서브커맨드)

### 추천 이유

1. **완전한 전환**: CLAUDE.md @import와 settings.json hooks를 동시에 토글하여 프롬프트 규칙과 물리적 강제를 모두 비활성화한다.
2. **원커맨드 UX**: `harness mode off .` 한 번으로 전환 완료.
3. **기존 인프라 활용**: `harness.sh`에 서브커맨드만 추가하면 되므로 새 파일/의존성이 없다.
4. **상태 추적**: `.harness-meta.json`에 모드 상태를 기록하여 `harness status`에서 확인 가능.
5. **안전성**: skills/와 agents/ 파일은 디스크에 그대로 유지. import가 없으면 참조되지 않으므로 무해.
6. **복원 보장**: 원본 settings.json을 `.harness` 접미사로 백업하므로 데이터 손실 없음.

### 구현 설계

```bash
cmd_mode() {
    local target="$1"
    local action="$2"  # on | off | status

    case "$action" in
        off)
            # 1. CLAUDE.md에서 @import 비활성화
            #    "@.claude/harness.md" → "# @.claude/harness.md  # harness-mode: disabled"

            # 2. settings.json → settings.json.harness 이동
            #    빈 settings.json (또는 statusLine만 남긴 버전) 생성

            # 3. .harness-meta.json에 "mode": "off" 기록
            ;;
        on)
            # 1. CLAUDE.md에서 @import 활성화
            #    "# @.claude/harness.md  # harness-mode: disabled" → "@.claude/harness.md"

            # 2. settings.json.harness → settings.json 복원

            # 3. .harness-meta.json에서 "mode" 키 제거 또는 "on" 설정
            ;;
        status)
            # .harness-meta.json의 mode 값 표시
            # settings.json 존재 여부 확인
            # CLAUDE.md import 상태 확인
            ;;
    esac
}
```

### 모드 전환 시 보존/비활성화 대상

| 요소 | off 시 | on 시 |
|------|--------|-------|
| CLAUDE.md @import | 주석 처리 | 복원 |
| settings.json hooks | 제거 (백업) | 복원 |
| settings.json statusLine | 유지 가능 (선택) | 복원 |
| .claude/skills/ | 디스크에 유지 (무해) | 그대로 |
| .claude/agents/ | 디스크에 유지 (무해) | 그대로 |
| .claude/rules/ | 디스크에 유지 (유지해도 유용) | 그대로 |
| .claude/agent-memory/ | 디스크에 유지 | 그대로 |
| .harness-meta.json | mode: off 기록 | mode: on 또는 키 삭제 |

### 환경변수 가드 (보조)

접근법 C를 보조적으로 활용하여, 훅 스크립트에 `HARNESS_MODE` 체크를 추가할 수 있다. 이렇게 하면 `harness mode off`를 실행하지 않아도 환경변수만으로 훅을 우회할 수 있다.

```bash
# 모든 훅 스크립트 최상단 (선택적 보강)
if [ "${HARNESS_MODE:-}" = "off" ]; then
  exit 0
fi
```

이 보조 메커니즘의 장점:
- 파일 수정 없이 임시로 훅만 비활성화 가능
- `HARNESS_MODE=off claude` 로 특정 세션에서만 비활성화
- 다만 프롬프트 규칙은 여전히 활성이므로 완전한 비활성화는 아님

### 주의사항

1. **실행 중 세션**: 모드 전환은 새 세션에서만 완전히 반영된다. CLAUDE.md는 세션 시작 시 한 번만 로딩되기 때문이다.
2. **git diff**: CLAUDE.md가 변경되므로 git status에 나타난다. `.gitignore`에 있지 않으므로 커밋 대상이 될 수 있다. 그러나 settings.json은 `.claude/` 하위이므로 이미 gitignore 대상이다.
3. **update 시 복원**: `harness update` 실행 시 모드가 off이면 자동으로 on으로 전환하거나, off 상태를 유지할지 정책이 필요하다.
4. **completion**: `harness.sh` 자동완성에 `mode` 서브커맨드를 추가해야 한다.

## 5. 대안적 고려: "Lite 모드"

완전한 off 대신 "lite 모드"도 고려할 수 있다.

- **Full 모드** (기본): 모든 harness 기능 활성화
- **Lite 모드**: 위임 규칙 + enforce-delegation 훅 비활성화, 스킬/에이전트는 유지
  - Main Agent가 직접 코드를 수정할 수 있지만, `/code`, `/test` 등 스킬은 여전히 사용 가능
  - 텔레그램 알림, 공유 컨텍스트 등 자동화는 유지
- **Off 모드**: 모든 harness 기능 비활성화

이 3단계 모드는 추후 확장으로 고려할 수 있다.

## 6. 결론

`harness.sh mode on|off|status` 서브커맨드를 구현하는 것이 가장 현실적이고 완전한 방법이다. CLAUDE.md의 @import 토글과 settings.json의 백업/복원을 하나의 명령으로 처리하며, 기존 `harness.sh` 인프라를 그대로 활용한다.
