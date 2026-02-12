# hoodcat-harness 멀티에이전트 시스템 패턴 분석

> 조사일: 2026-02-13

## 개요

hoodcat-harness는 Claude Code의 Skills, Agents, Hooks API를 조합하여 구축한 멀티에이전트 오케스트레이션 시스템이다. 15개 스킬(워크플로우 5 + 워커 10), 8개 에이전트, 6개 훅 이벤트, 파일 기반 공유 컨텍스트를 통해 복잡한 개발 워크플로우(기획 -> 구현 -> 리뷰 -> 테스트 -> 커밋)를 자율적으로 실행한다. 본 문서는 이 시스템의 아키텍처 패턴, 데이터 흐름, 강점, 약점, 그리고 업계 유사 시스템과의 비교를 분석한다.

---

## 1. 아키텍처 패턴 분석

### 1.1 계층 구조 (3-Tier Architecture)

```
[사용자]
   |
   v
[메인 에이전트] ---- 순수 오케스트레이터 (스킬 디스패처)
   |
   v
[워크플로우 에이전트] ---- context: fork + agent: workflow
   |                        Skill() / Task() 호출로 하위 작업 조율
   v
[워커 에이전트 / 리뷰 에이전트] ---- context: fork + agent: coder/researcher/committer 등
```

**패턴 명칭**: Hierarchical Orchestration with Delegated Execution

- **Tier 1**: 메인 에이전트 -- 사용자 의도 해석, 적절한 스킬(슬래시 커맨드) 디스패치
- **Tier 2**: 워크플로우 에이전트 -- 다중 Phase 순차 실행, Skill/Task 도구로 하위 작업 조율, 에이전트팀 병렬 개발 가능
- **Tier 3**: 워커 에이전트 -- 단일 책임 작업 수행 (코딩, 테스트, 리서치, 리뷰 등)

이 계층은 Claude Code의 `context: fork` + `agent:` frontmatter를 통해 구현된다. 각 스킬이 fork되면 지정된 에이전트의 시스템 프롬프트와 도구 집합이 주입되고, 스킬 본문이 태스크 프롬프트가 된다.

### 1.2 격리 모델 (Full Fork Isolation)

모든 15개 스킬이 `context: fork`를 사용하여 메인 컨텍스트와 완전히 분리된다.

| 속성 | 설명 |
|------|------|
| 컨텍스트 윈도우 | 각 서브에이전트가 독립 컨텍스트 보유 |
| 도구 접근 | 에이전트 `.md`의 `tools:` 필드로 제한 |
| 대화 이력 | 부모 대화 상속 없음 |
| CLAUDE.md | 자동 주입됨 (비활성화 불가) |
| 종료 | 자율 완료 후 결과를 부모에게 반환 |

**장점**: 메인 컨텍스트 오염 방지, 역할별 도구 격리, 병렬 실행 가능
**단점**: 토큰 비용 1.5-2배, 중간 과정 실시간 확인 불가, 프로젝트 전체 컨텍스트 부재

### 1.3 역할 기반 에이전트 설계 (Role-Based Agent Design)

8개 에이전트가 명확한 역할 분리와 최소 권한 원칙(Principle of Least Privilege)을 따른다:

| 에이전트 | 모델 | 핵심 도구 | 역할 | Write/Edit |
|----------|------|-----------|------|------------|
| workflow | opus | Skill, Task, Team*, R/W/E, 빌드 도구 | 오케스트레이션 | O |
| researcher | opus | WebSearch, WebFetch, Context7, gh | 정보 수집/문서 작성 | Write만 |
| coder | opus | R/W/E, 빌드/테스트/감사 도구 | 코드 수정/실행 | O |
| committer | sonnet | Read, Glob, Grep, git | Git 커밋 | X |
| reviewer | opus | Read, Glob, Grep | 코드 품질 리뷰 | X |
| security | opus | Read, Glob, Grep, *audit | 보안 리뷰 | X |
| architect | opus | Read, Glob, Grep | 아키텍처 리뷰 | X |
| navigator | opus | Read, Glob, Grep | 코드베이스 탐색 | X |

**설계 원칙**:
- 리뷰/탐색 에이전트(reviewer, security, architect, navigator)에는 Write/Edit 없음 -- 읽기 전용
- committer는 sonnet 모델 사용 -- 비용 최적화 (커밋 작업은 상대적으로 단순)
- coder만 빌드/테스트 실행 가능 -- 구현과 검증의 책임 집중
- researcher에 Edit 없음 -- 기존 파일 수정 방지, 새 문서만 생성

### 1.4 워크플로우 패턴 (DO/REVIEW Sequence)

모든 워크플로우 스킬(implement, bugfix, hotfix, improve, new-project)이 동일한 DO/REVIEW 패턴을 따른다:

```
Phase N: [DO 단계]
  -> Skill("worker", "작업 내용") 또는 직접 실행
  -> 결과 확인

Phase N+1: [REVIEW 단계]
  -> Task(reviewer/security/architect): "리뷰 요청"
  -> PASS/WARN -> 다음 Phase
  -> BLOCK -> 수정 후 재리뷰 (최대 2회)
  -> 2회 초과 BLOCK -> 사용자 보고
```

각 워크플로우의 Phase 구성:

| 워크플로우 | Phase 1 | Phase 2 | Phase 3 | Phase 4 | Phase 5 |
|-----------|---------|---------|---------|---------|---------|
| implement | 컨텍스트(navigator) | 코드 작성 | 린트/포맷 | 테스트(test) | 리뷰(reviewer+security) |
| bugfix | 진단+수정(fix) | 리뷰(reviewer) | 검증(test --regression) | - | - |
| hotfix | 심각도 평가(security) | 수정(fix) | 이중 리뷰(security+reviewer) | 검증(test+security-scan) | - |
| improve | 분석(navigator) | [기획(blueprint)] | 개발(implement) | 검증(test --regression) | - |
| new-project | 기획(blueprint) | [기술조사(deepresearch)] | 개발(implement) | QA(test/qa-swarm) | [배포(deploy)] |

### 1.5 에이전트팀 패턴 (Agent Teams)

2가지 에이전트팀 패턴이 사용된다:

**1. 멀티렌즈 리뷰 (team-review, 3팀원)**
```
workflow(리드)
  |-- quality-reviewer: 코드 품질
  |-- security-reviewer: 보안
  |-- arch-reviewer: 아키텍처
  (독립 리뷰 후 SendMessage로 상호 피드백 교환)
```

**2. 병렬 QA 스웜 (qa-swarm, 최대 4팀원)**
```
workflow(리드)
  |-- qa-tester: 단위/통합 테스트
  |-- qa-linter: 린트/정적 분석
  |-- qa-builder: 빌드 검증
  |-- qa-security: 보안 스캔
  (감지된 도구에 따라 동적 배정)
```

**3. 경쟁 가설 디버깅 (bugfix 내 복잡 버그, 최대 3팀원)**
```
workflow(리드)
  |-- debugger-1: 가설 1 조사
  |-- debugger-2: 가설 2 조사
  |-- debugger-3: 가설 3 조사
  (반증 발견 시 SendMessage 공유, 확증된 가설의 디버거가 수정)
```

---

## 2. 공유 컨텍스트 시스템 (Shared Context System)

### 2.1 동작 흐름

서브에이전트 간 작업 결과를 전달하는 파일 기반 시스템. Claude Code의 훅 API를 활용한다.

```
SessionStart
  |
  |-- shared-context-cleanup.sh
  |     TTL 만료 세션 정리 + 현재 세션 디렉토리 생성
  |
  v
SubagentStart (에이전트 A 시작)
  |
  |-- shared-context-inject.sh
  |     _summary.md 읽기 + 에이전트 타입별 필터링 + additionalContext 주입
  |     + 기록 경로 안내 (예: ".claude/shared-context/{session-id}/{agent-type}-{agent-id}.md")
  |
  v
에이전트 A 작업 수행
  |-- [자발적 기록] 에이전트가 작업 결과를 지정 경로에 Write
  |
  v
SubagentStop (에이전트 A 종료)
  |
  |-- subagent-monitor.sh (로깅)
  |-- shared-context-collect.sh
  |     1. 자발적 기록 파일 확인 (primary)
  |     2. 없으면 transcript 파싱으로 변경 파일 추출 (fallback)
  |     3. _summary.md에 flock 기반 안전 append
  |
  v
SubagentStart (에이전트 B 시작)
  |
  |-- shared-context-inject.sh
  |     에이전트 A의 결과가 포함된 _summary.md를 additionalContext로 주입
  |     + 에이전트 B의 기록 경로 안내
  |
  ...
  v
SessionEnd
  |
  |-- shared-context-finalize.sh
        메트릭 기록 (에이전트 수, 총 컨텍스트 크기)
```

### 2.2 핵심 메커니즘

| 구성요소 | 역할 | 파일/경로 |
|----------|------|-----------|
| 세션 디렉토리 | 세션별 격리된 컨텍스트 저장소 | `.claude/shared-context/{session-id}/` |
| 에이전트 컨텍스트 파일 | 개별 에이전트의 작업 결과 | `{agent-type}-{agent-id}.md` |
| 요약 파일 | 모든 에이전트 결과의 누적 요약 | `_summary.md` |
| 설정 파일 | TTL, 크기 제한, 필터 규칙 | `.claude/shared-context-config.json` |
| 잠금 파일 | flock 기반 동시 쓰기 보호 | `.lock` |

### 2.3 에이전트 타입별 필터링

inject 훅이 에이전트 타입에 따라 관련 컨텍스트만 선별 주입한다:

```json
{
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

- `navigation`: 파일 탐색 결과, 의존성 관계, 영향 범위
- `code_changes`: 파일 변경/생성/삭제, 커밋, 빌드/테스트 결과
- navigator는 필터 없음(빈 배열) -- 선입견 없이 독립 탐색

### 2.4 이중 안전망 (Dual Safety Net)

**1차: 에이전트 자발적 기록** -- 에이전트 프롬프트에 "Shared Context Protocol" 섹션이 포함되어 있고, SubagentStart 훅이 기록 경로를 주입한다. 에이전트가 스스로 구조화된 보고서를 작성한다.

**2차: transcript 자동 추출** -- 자발적 기록이 없으면 collect 훅이 transcript JSONL에서 Write/Edit 도구 호출을 파싱하여 변경 파일 목록을 자동 추출한다.

이 이중 메커니즘은 "에이전트가 기록을 잊어도 최소한의 컨텍스트가 전달되도록" 보장한다.

---

## 3. 훅 시스템 분석

### 3.1 훅 이벤트 매핑

| 훅 이벤트 | 스크립트 | 역할 | exit code |
|-----------|---------|------|-----------|
| SessionStart | shared-context-cleanup.sh | TTL 정리 + 세션 초기화 | 항상 0 |
| SubagentStart | shared-context-inject.sh | 공유 컨텍스트 주입 | 항상 0 |
| SubagentStop | subagent-monitor.sh | 로깅 | 항상 0 |
| SubagentStop | shared-context-collect.sh | 컨텍스트 수집 + 요약 갱신 | 항상 0 |
| SessionEnd | shared-context-finalize.sh | 메트릭 기록 | 항상 0 |
| TaskCompleted | task-quality-gate.sh | 빌드/테스트 자동 검증 | 0(통과) / 2(차단) |
| TeammateIdle | teammate-idle-check.sh | 유휴 팀원 작업 재개 유도 | 0(허용) / 2(피드백) |

### 3.2 훅 설계 원칙

1. **절대 차단 금지 (공유 컨텍스트 훅)**: cleanup/inject/collect/finalize 훅은 모두 `exit 0`을 보장한다. 공유 컨텍스트 실패가 워크플로우를 중단시키지 않는다.

2. **선택적 차단 (품질 게이트 훅)**: TaskCompleted, TeammateIdle만 `exit 2`로 차단/피드백을 보낼 수 있다.

3. **jq 미설치 대비**: 모든 훅이 `jq` 미설치 시 안전하게 통과한다.

4. **동시성 안전**: flock을 사용하여 `_summary.md` 동시 쓰기를 보호한다.

### 3.3 품질 게이트 패턴

```
TaskCompleted 훅
  |
  |-- 태스크 subject에 "구현/implement/개발/develop/코드/code/build/빌드" 키워드 감지?
  |     |
  |     |-- Yes: verify-build-test.sh 실행
  |     |     |-- exit 0: 완료 허용
  |     |     |-- exit != 0: exit 2 (완료 차단 + 에러 메시지 피드백)
  |     |
  |     |-- No: exit 0 (비구현 태스크는 검증 건너뜀)
```

```
TeammateIdle 훅
  |
  |-- 해당 팀원에게 할당된 in_progress 태스크 있는가?
  |     |
  |     |-- Yes: exit 2 (피드백: "N개 태스크 남아있음, 완료하세요")
  |     |-- No: exit 0 (유휴 허용)
```

---

## 4. 데이터 흐름 분석

### 4.1 /implement 워크플로우 전체 흐름

```
사용자: "/implement 사용자 인증 기능"
  |
  v
메인 에이전트: Skill("implement", "사용자 인증 기능")
  |
  v
[fork] workflow 에이전트 시작
  |-- SubagentStart 훅 -> 공유 컨텍스트 주입 (이전 작업 결과)
  |
  |-- Phase 1: Task(navigator)
  |     |-- [fork] navigator 시작
  |     |     |-- SubagentStart 훅 -> 공유 컨텍스트 주입
  |     |     |-- 파일 탐색: Glob, Grep, Read
  |     |     |-- 자발적 기록: Navigator Report
  |     |     |-- 결과 반환
  |     |-- SubagentStop 훅 -> 컨텍스트 수집
  |
  |-- Phase 2: 코드 작성 (workflow 에이전트가 직접)
  |     |-- Edit/Write로 코드 수정/생성
  |
  |-- Phase 3: 린트/포맷 (workflow 에이전트가 직접)
  |
  |-- Phase 4: Skill("test", "사용자 인증 기능")
  |     |-- [fork] coder 에이전트 시작
  |     |     |-- SubagentStart 훅 -> navigator 결과 포함 컨텍스트 주입
  |     |     |-- Task(navigator)로 테스트 대상 탐색
  |     |     |-- 테스트 작성 + 실행
  |     |     |-- 결과 반환
  |     |-- SubagentStop 훅 -> 컨텍스트 수집
  |
  |-- Phase 5a: Task(reviewer, background): 코드 품질 리뷰
  |-- Phase 5b: Task(security, background): 보안 리뷰  (인증 코드이므로)
  |     |-- [fork] 두 에이전트 병렬 실행
  |     |-- 각각 SubagentStart/SubagentStop 훅 동작
  |     |-- 각각 PASS/WARN/BLOCK 반환
  |
  |-- 완료 보고 작성
  |-- 자발적 기록: Workflow Report
  |
  v
SubagentStop 훅 -> 컨텍스트 수집
메인 에이전트에 결과 반환
```

### 4.2 정보 전달 경로

```
[navigator 결과]
     |
     |-- (1) 직접 반환: Task() 결과로 부모(workflow)에게 전달
     |-- (2) 공유 컨텍스트: _summary.md에 기록 -> 후속 에이전트(coder, reviewer 등)에 주입
     |
     v
[coder가 받는 컨텍스트]
     = 자신의 에이전트 프롬프트 (coder.md)
     + 스킬 프롬프트 (test/SKILL.md)
     + CLAUDE.md
     + additionalContext (이전 에이전트 결과 요약)
```

---

## 5. 강점 분석

### 5.1 구조적 강점

**1. 일관된 격리 모델**
- 모든 스킬이 `context: fork`로 통일되어 있다
- v2에서 v3 전환 시 Sisyphus 강제속행 메커니즘을 완전 제거하여 복잡도를 크게 줄였다
- 에이전트의 tools 필드로 도구 권한을 일원화하여 관리 지점이 하나다

**2. 최소 권한 원칙의 실천**
- 리뷰 에이전트 4종(reviewer, security, architect, navigator)은 읽기 전용
- committer는 Write/Edit 없음 -- pre-commit 실패 시 보고만 하고 코드를 건드리지 않음
- researcher에 Edit 없음 -- 기존 파일 변경 방지

**3. 다층 안전장치**
- DO/REVIEW 시퀀스 내 BLOCK 재시도 (최대 2회)
- exit code 기반 빌드/테스트 검증 규칙 ("텍스트 보고 신뢰 금지")
- TaskCompleted 훅의 자동 검증 게이트
- TeammateIdle 훅의 유휴 팀원 재활성화
- 공유 컨텍스트의 이중 안전망 (자발적 기록 + transcript 자동 추출)

**4. 실용적인 비용 관리**
- committer에 sonnet 사용 (비용 최적화)
- 에이전트팀은 명확한 기준(독립 태스크 3개 이상, 복잡 버그, 대규모 변경)에서만 사용
- 비용 주의 문구가 team-review, qa-swarm 스킬에 명시

### 5.2 공유 컨텍스트의 독창성

Claude Code의 공식 API에는 서브에이전트 간 직접 컨텍스트 전달 메커니즘이 없다 (Issue #5812 참조). hoodcat-harness는 이 한계를 훅 + 파일 시스템 조합으로 우회한다:

- SubagentStart의 `additionalContext` 반환으로 이전 결과 주입
- 에이전트 프롬프트 내 "Shared Context Protocol" 섹션으로 자발적 기록 유도
- 에이전트 타입별 필터링으로 불필요한 컨텍스트 노이즈 감소
- flock 기반 동시 쓰기 보호로 병렬 에이전트 안전 지원
- TTL 기반 자동 정리로 디스크 관리

이는 planning-with-teams (OthmanAdi)의 "공유 계획 파일" 접근과 유사하지만, hoodcat-harness가 더 자동화되어 있다 (훅 기반 vs 수동 파일 읽기/쓰기).

---

## 6. 약점 및 개선 가능 영역

### 6.1 공유 컨텍스트 필터링의 취약성

inject 훅의 필터링이 grep 기반 키워드 매칭으로 구현되어 있다:

```bash
case "$category" in
  navigation)
    if echo "$line" | grep -qi 'navigat\|file.*found\|pattern\|depend\|impact\|explore'; then
      include=true
    fi
    ;;
```

이 패턴은:
- 한국어 콘텐츠를 필터링하지 못한다 ("파일을 찾았다" vs "file found")
- 오탐/누락 가능성이 높다 (예: "navigation" 단어가 코드 변경 설명에 포함)
- 마크다운 구조(##, ###)를 인식하지 못하고 줄 단위로만 판단한다

**개선 제안**: 에이전트 보고서 형식을 활용한 섹션 기반 필터링. 예를 들어 "### Files Found" 섹션 전체를 navigation으로 분류.

### 6.2 SubagentStop 훅의 에이전트 식별 한계

GitHub Issue #7881에서 보고된 대로, 동일 세션 내 서브에이전트들이 같은 session_id를 공유한다. hoodcat-harness는 `agent_type` + `agent_id` 조합으로 식별하지만, Claude Code가 이 필드를 항상 정확하게 제공하는지는 훅 입력 스키마의 안정성에 의존한다.

### 6.3 context: fork 미작동 버그 (Issue #16803)

Claude Code의 알려진 버그로, `context: fork`가 무시되고 스킬이 메인 컨텍스트에서 인라인 실행될 수 있다. 이 경우:
- 스킬 body가 사용자 메시지로 주입되고 agent 필드가 무시된다
- 도구 제한이 적용되지 않는다
- 공유 컨텍스트 훅이 기대대로 동작하지 않을 수 있다

현재 OPEN 상태이며 근본 해결은 Claude Code 팀에 의존한다.

### 6.4 서브에이전트의 구현 위임 패턴

best practices 문서에서 "서브에이전트는 정보 수집기이지 구현자가 아니다"라고 명시하지만, 실제로 coder 에이전트가 코드 수정(Write/Edit)을 담당하고, workflow 에이전트도 직접 코드를 작성한다. 이는 공식 권장과 상충하지만, `context: fork`로 격리된 환경에서 독립 실행되므로 실질적 위험은 관리 가능하다.

다만, 프로젝트 전체 컨텍스트가 없는 서브에이전트의 코드 수정은 경계 버그 위험이 있으며, 이를 DO/REVIEW 시퀀스와 navigator의 사전 탐색으로 완화하고 있다.

### 6.5 CLAUDE.md 자동 주입 비활성화 불가 (Issue #24773)

CLAUDE.md가 모든 서브에이전트에 자동 주입되어 컨텍스트 윈도우를 소비한다. hoodcat-harness의 CLAUDE.md는 `@harness.md`와 `@best-practices.md`를 참조하여 상당한 크기이며, 이것이 모든 서브에이전트의 컨텍스트에 포함된다.

### 6.6 Task 도구의 cwd 미지원 (Issue #12748)

서브에이전트의 작업 디렉토리를 프로그래밍적으로 지정할 수 없다. worktree 기반 병렬 개발 시 프롬프트에 절대 경로를 명시해야 하며, 에이전트가 이를 올바르게 따르지 않을 수 있다.

### 6.7 에이전트 보고서 형식의 표준화 부족

각 에이전트의 Shared Context Protocol 섹션이 서로 다른 형식을 사용한다 (Navigator Report, Coder Report, Reviewer Report 등). 이는 의도된 것이지만, collect 훅의 파싱과 inject 훅의 필터링이 이 다양성을 제대로 처리하지 못한다.

---

## 7. 유사 시스템 비교

### 7.1 hoodcat-harness vs planning-with-teams

| 항목 | hoodcat-harness | planning-with-teams |
|------|----------------|---------------------|
| 컨텍스트 공유 | 훅 기반 자동 주입/수집 | 수동 파일 읽기/쓰기 (team_plan.md 등) |
| 에이전트 격리 | context: fork + 역할별 도구 제한 | 에이전트팀 기본 격리 |
| 워크플로우 정의 | SKILL.md에 Phase 시퀀스 명시 | 팀 계획 파일에 태스크 분배 |
| 품질 게이트 | TaskCompleted 훅으로 자동 검증 | 3-Strike Protocol (수동) |
| 오류 복구 | BLOCK 재시도 + transcript 폴백 | 에러 로깅 + 수동 개입 |
| 비용 관리 | 에이전트별 모델 분리 (sonnet/opus) | 단일 모델 |

### 7.2 hoodcat-harness vs claude-code-hooks-mastery

| 항목 | hoodcat-harness | hooks-mastery |
|------|----------------|---------------|
| 목적 | 프로덕션 멀티에이전트 시스템 | 훅 학습/데모 |
| 훅 활용 범위 | 공유 컨텍스트 + 품질 게이트 + 팀 관리 | 관찰성 + 검증 |
| 에이전트 정의 | 8개 전문화된 에이전트 | Meta-Agent 패턴 |
| 스킬 체계 | 15개 (워크플로우 + 워커) | 데모 스킬 |

### 7.3 hoodcat-harness vs ccswarm (nwiizo)

| 항목 | hoodcat-harness | ccswarm |
|------|----------------|---------|
| worktree 사용 | 프롬프트 규칙 + 에이전트 자율 생성 | CLI 도구로 자동 생성/관리 |
| 에이전트 격리 | 도구 권한 제한 | 물리적 디렉토리 격리 |
| 통신 방식 | 공유 컨텍스트 파일 + 훅 | 파일 기반 |
| 오케스트레이션 | SKILL.md 내 Phase 시퀀스 | 외부 오케스트레이터 |

---

## 8. 아키텍처 다이어그램

### 8.1 전체 시스템 구조

```
                    +------------------+
                    |    사용자 (CLI)    |
                    +--------+---------+
                             |
                             v
                    +------------------+
                    |   메인 에이전트    |
                    | (순수 오케스트레이터)|
                    +--------+---------+
                             |
              +--------------+--------------+
              |              |              |
              v              v              v
    [워크플로우 스킬]  [워커 스킬]     [워커 스킬]
    (fork+workflow)  (fork+coder)   (fork+researcher)
              |
    +---------+---------+
    |         |         |
    v         v         v
  Skill()  Task()  TeamCreate()
  (워커)  (리뷰어)  (에이전트팀)
```

### 8.2 공유 컨텍스트 데이터 흐름

```
.claude/shared-context/{session-id}/
    |
    |-- navigator-abc123.md     <- navigator가 자발적 기록
    |-- coder-def456.md         <- coder가 자발적 기록 (또는 transcript 추출)
    |-- reviewer-ghi789.md      <- reviewer가 자발적 기록
    |-- _summary.md             <- collect 훅이 자동 누적
    |-- .lock                   <- flock 동시성 보호
    |
    [inject 훅]
    _summary.md --[필터링]--> additionalContext --[주입]--> 후속 에이전트
```

---

## 주요 포인트

1. **3-Tier Hierarchical Orchestration**: 메인(디스패처) -> 워크플로우(오케스트레이터) -> 워커(실행자) 구조로, 각 계층이 명확한 책임을 갖는다. 모든 15개 스킬의 `context: fork` 통일은 v2 대비 큰 단순화이다.

2. **훅 기반 공유 컨텍스트는 Claude Code의 공식 API 한계를 우회하는 독창적 패턴**: SubagentStart의 additionalContext + 에이전트 자발적 기록 + transcript 폴백의 3중 메커니즘으로, 에이전트 간 정보 단절 문제를 해결한다. 다만 키워드 기반 필터링의 정확도에 개선 여지가 있다.

3. **최소 권한 원칙의 체계적 적용**: 리뷰 에이전트 4종 읽기 전용, committer Write/Edit 금지, researcher Edit 금지 등 역할별 도구 접근이 설계 수준에서 제한된다. committer의 sonnet 모델 사용은 비용과 역할 복잡도를 동시에 최적화한다.

4. **DO/REVIEW 시퀀스 + 품질 게이트 훅의 이중 검증**: 워크플로우 수준의 BLOCK/재시도 패턴과, 훅 수준의 exit code 기반 자동 검증이 결합되어 코드 품질 게이트가 다층적이다. exit code 강제("텍스트 보고 불신")는 LLM의 환각 위험을 직접적으로 완화한다.

5. **현실적 한계 인식**: context: fork 미작동 버그(#16803), CLAUDE.md 주입 비활성화 불가(#24773), Task cwd 미지원(#12748), SubagentStop 식별 한계(#7881) 등 Claude Code 플랫폼 제약에 의존하는 부분이 있으며, 이들은 업스트림 수정을 기다려야 한다.

---

## 출처

- [Claude Code Skills 공식 문서](https://code.claude.com/docs/en/skills)
- [Claude Code Sub-agents 공식 문서](https://code.claude.com/docs/en/sub-agents)
- [Claude Code Hooks Reference](https://code.claude.com/docs/en/hooks)
- [Claude Code Agent Teams](https://code.claude.com/docs/en/agent-teams)
- [Feature Request: Allow Hooks to Bridge Context Between Sub-Agents -- Issue #5812](https://github.com/anthropics/claude-code/issues/5812)
- [SubagentStop hook cannot identify which specific subagent -- Issue #7881](https://github.com/anthropics/claude-code/issues/7881)
- [context: fork 미작동 버그 -- Issue #16803](https://github.com/anthropics/claude-code/issues/16803)
- [CLAUDE.md 주입 비활성화 요청 -- Issue #24773](https://github.com/anthropics/claude-code/issues/24773)
- [Task cwd Feature Request -- Issue #12748](https://github.com/anthropics/claude-code/issues/12748)
- [planning-with-teams -- OthmanAdi](https://github.com/OthmanAdi/planning-with-teams)
- [claude-code-hooks-mastery -- disler](https://github.com/disler/claude-code-hooks-mastery)
- [ccswarm -- nwiizo](https://github.com/nwiizo/ccswarm)
- [Claude Code multiple agent systems: Complete 2026 guide -- eesel.ai](https://www.eesel.ai/blog/claude-code-multiple-agent-systems-complete-2026-guide)
- [From Tasks to Swarms: Agent Teams in Claude Code -- alexop.dev](https://alexop.dev/posts/from-tasks-to-swarms-agent-teams-in-claude-code/)
- [Context Engineering for Coding Agents -- Martin Fowler](https://martinfowler.com/articles/exploring-gen-ai/context-engineering-coding-agents.html)
- [Best practices for Claude Code subagents -- PubNub](https://www.pubnub.com/blog/best-practices-for-claude-code-sub-agents/)
- [Skill authoring best practices -- Claude API Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
