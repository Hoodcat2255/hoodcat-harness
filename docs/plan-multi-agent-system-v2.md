# 멀티에이전트 시스템 v2 - 구축 계획서

> 작성일: 2026-02-08
> 프로젝트: hoodcat-harness
> 상태: 계획 단계

---

## 1. 설계 원칙

### DO/REVIEW 패턴

모든 워크플로우는 하나의 패턴으로 구성된다:

```
DO (스킬)  →  REVIEW (에이전트)  →  PROCEED / REDO
```

- **DO**: 프로세스 실행. 누가 해도 같은 결과. → 스킬로 구현
- **REVIEW**: 관점 기반 평가. 전문가마다 다른 의견. → 에이전트로 구현
- **DECIDE**: 진행/재작업 판단. 워크플로우 스킬이 제어

### 에이전트 존재 기준

에이전트는 "같은 코드를 보고 다른 문제를 찾는" 경우에만 존재해야 한다.
프로세스를 실행하는 역할(테스트 작성, 코드 작성, 배포)은 스킬로 충분하다.

---

## 2. 에이전트 설계 (4개)

### 2.1 architect

| 항목 | 내용 |
|------|------|
| 관점 | 구조, 확장성, 기술 스택 적합성 |
| 질문 | "이 설계가 10배 트래픽에도 버티나?" |
| 모델 | opus |
| 도구 | Read, Glob, Grep (읽기 전용) |
| 호출 시점 | /plan 리뷰, /deepresearch 결과 평가, 설계 변경 시 |

### 2.2 reviewer

| 항목 | 내용 |
|------|------|
| 관점 | 코드 품질, 유지보수성, 패턴 준수 |
| 질문 | "6개월 뒤에 이 코드 이해할 수 있나?" |
| 모델 | sonnet |
| 도구 | Read, Glob, Grep (읽기 전용) |
| 호출 시점 | /implement 결과 리뷰, /fix 결과 리뷰 |

### 2.3 security

| 항목 | 내용 |
|------|------|
| 관점 | 보안 취약점, OWASP Top 10, 인증/인가 |
| 질문 | "이걸 어떻게 악용할 수 있나?" |
| 모델 | sonnet |
| 도구 | Read, Glob, Grep, Bash (읽기 + 보안 스캔 도구) |
| 호출 시점 | 인증/보안 관련 코드 변경, 배포 전, 보안 이슈 평가 |

### 2.4 navigator

| 항목 | 내용 |
|------|------|
| 관점 | 코드베이스 구조 탐색 (유틸리티) |
| 용도 | 관련 파일 찾기, 영향 범위 파악, 코드 구조 이해 |
| 모델 | haiku |
| 도구 | Read, Glob, Grep (읽기 전용) |
| 호출 시점 | 모든 워크플로우 시작 시 (기존 코드 파악) |

---

## 3. 스킬 설계 (10개)

### 3.1 기획/조사 스킬

#### /plan

```
입력: 아이디어 또는 기능 설명
출력: 요구사항 정의 + 설계 문서 + 태스크 목록
IT 단계: 기획 → 요구사항 분석 → 설계

프로세스:
1. 요구사항 정리 (기능/비기능)
2. 기술 스택 결정 (필요시 /deepresearch 호출)
3. 아키텍처 설계 (ERD, API 명세, 컴포넌트 구조)
4. 태스크 분해 (구현 단위로)
5. docs/plans/{project-name}/ 에 산출물 저장

산출물:
- requirements.md (요구사항)
- architecture.md (아키텍처 설계)
- api-spec.md (API 명세)
- tasks.md (구현 태스크 목록)
```

#### /deepresearch (기존 유지)

```
입력: 주제 또는 URL
출력: 조사 보고서
IT 단계: 기술조사 (Spike)
```

#### /decide (기존 유지)

```
입력: 선택지 또는 의사결정 사항
출력: 근거 기반 판단
IT 단계: 의사결정 시점마다
```

### 3.2 개발 스킬

#### /implement

```
입력: 태스크 설명 (또는 /plan의 tasks.md 참조)
출력: 구현된 코드 + 린트 통과

프로세스:
1. navigator로 관련 코드 탐색
2. 브랜치 생성 (선택)
3. 코드 작성 (Edit/Write)
4. 린트/포맷 실행
5. 기본 테스트 작성 (해당되면)

컨텍스트:
- 프로젝트의 CLAUDE.md에서 코딩 컨벤션 참조
- 기존 코드 패턴을 따름
```

#### /test

```
입력: 테스트 대상 (파일, 모듈, 또는 전체)
출력: 테스트 코드 + 실행 결과

프로세스:
1. navigator로 테스트 대상 코드 파악
2. 테스트 프레임워크 감지 (jest, pytest, go test 등)
3. 단위 테스트 작성
4. 테스트 실행 및 결과 보고
5. 커버리지 확인 (가능한 경우)

옵션:
- --unit: 단위 테스트만
- --e2e: E2E 테스트
- --regression: 회귀 테스트 (변경된 파일 관련만)
```

#### /fix

```
입력: 버그 설명 또는 에러 메시지
출력: 패치된 코드 + 회귀 테스트

프로세스:
1. navigator로 관련 코드 찾기
2. 버그 재현 시도 (가능한 경우)
3. 원인 진단
4. 패치 작성
5. 회귀 테스트 작성/실행
6. 수정 사항 요약 보고
```

### 3.3 운영 스킬

#### /security-scan

```
입력: 대상 디렉토리 또는 파일
출력: 취약점 리포트

프로세스:
1. 의존성 취약점 검사 (npm audit, pip audit 등)
2. 코드 레벨 보안 패턴 검사 (하드코딩된 시크릿, SQL 인젝션 등)
3. 인증/인가 로직 검토
4. 결과 리포트 생성
```

#### /deploy

```
입력: 배포 대상 환경
출력: 배포 설정 파일 (Dockerfile, CI/CD 등)

프로세스:
1. 프로젝트 타입 감지
2. Dockerfile 생성/수정
3. CI/CD 파이프라인 설정 (GitHub Actions 등)
4. 환경 변수 목록 정리
5. 배포 가이드 문서 생성
```

#### /commit (기존 유지 가능)

```
입력: 없음 (현재 변경사항 자동 감지)
출력: git commit

프로세스:
1. git status/diff 확인
2. 변경 내역 분석
3. Conventional Commit 메시지 생성
4. 커밋 실행
```

---

## 4. 워크플로우 정의 (4개 entry point)

### 4.1 /new-project - 신규 개발

```
/new-project <설명>

[기획]
  DO: /plan
  REVIEW: architect → "구조가 적합한가?"
  REDO 조건: architect가 구조적 문제 지적 시

[기술조사] (필요시)
  DO: /deepresearch
  REVIEW: architect → "이 기술 선택이 맞나?"

[개발]
  DO: /implement (태스크별 순차 또는 독립 태스크 병렬)
  REVIEW: reviewer → "코드 품질"
  REVIEW: security → "보안 문제" (인증/데이터 관련 시)

[QA]
  DO: /test
  AUTO: 통과하면 자동 진행, 실패하면 /fix → 재테스트

[배포]
  DO: /deploy
  REVIEW: security → "배포 설정 안전한가?"
```

### 4.2 /improve - 기능 개선

```
/improve <설명>

[분석]
  DO: navigator → 영향 범위 파악
  판단: 큰 변경이면 /plan, 작은 변경이면 바로 /implement

[개발]
  DO: /implement
  REVIEW: reviewer

[검증]
  DO: /test --regression
  AUTO: 통과하면 자동 진행
```

### 4.3 /bugfix - 버그 수정

```
/bugfix <버그 설명>

[진단]
  DO: navigator → 관련 코드 찾기
  DO: /fix → 원인 진단 + 패치

[검증]
  REVIEW: reviewer → "수정이 적절한가?"
  DO: /test --regression
  AUTO: 통과하면 자동 진행
```

### 4.4 /hotfix - 보안/긴급 수정

```
/hotfix <이슈 설명>

[평가]
  REVIEW: security → 심각도 판단

[수정]
  DO: navigator → 취약 코드 찾기
  DO: /fix → 패치

[검증]
  REVIEW: security + reviewer → "패치가 완전한가?"
  DO: /test + /security-scan
  AUTO: 통과하면 자동 진행
```

---

## 5. 디렉토리 구조

```
.claude/
├── agents/                    # 에이전트 정의 (4개)
│   ├── architect.md
│   ├── reviewer.md
│   ├── security.md
│   └── navigator.md
│
├── skills/                    # 스킬 정의
│   ├── plan/SKILL.md
│   ├── deepresearch/SKILL.md  # 기존
│   ├── decide/SKILL.md        # 기존
│   ├── implement/SKILL.md
│   ├── test/SKILL.md
│   ├── fix/SKILL.md
│   ├── security-scan/SKILL.md
│   ├── deploy/SKILL.md
│   ├── commit/SKILL.md
│   ├── new-project/SKILL.md   # 워크플로우 오케스트레이터
│   ├── improve/SKILL.md
│   ├── bugfix/SKILL.md
│   └── hotfix/SKILL.md
│
├── memory/
│   └── MEMORY.md              # 프로젝트 메모리
│
└── rules/                     # 프로젝트 규칙
    └── (필요시 추가)
```

---

## 6. 구현 순서

### Phase 1: 핵심 에이전트 (1일)

1. `architect.md` - 아키텍처 관점 에이전트
2. `reviewer.md` - 코드 품질 관점 에이전트
3. `security.md` - 보안 관점 에이전트
4. `navigator.md` - 코드베이스 탐색 에이전트

### Phase 2: 핵심 스킬 (2-3일)

5. `/plan` - 기획 스킬
6. `/implement` - 개발 스킬
7. `/test` - 테스트 스킬
8. `/fix` - 버그 수정 스킬
9. `/commit` - 커밋 스킬

### Phase 3: 워크플로우 오케스트레이터 (2-3일)

10. `/new-project` - 신규 개발 워크플로우
11. `/improve` - 기능 개선 워크플로우
12. `/bugfix` - 버그 수정 워크플로우
13. `/hotfix` - 긴급 수정 워크플로우

### Phase 4: 보조 스킬 (1-2일)

14. `/security-scan` - 보안 스캔 스킬
15. `/deploy` - 배포 스킬
16. `/deepresearch` - 기존 유지/개선
17. `/decide` - 기존 유지/개선

### Phase 5: 검증 (1-2일)

18. 테스트 프로젝트 선정 (소규모 API 서버 등)
19. 4가지 워크플로우 각각 한 사이클 실행
20. 에이전트별 리뷰 품질 평가
21. 병목/개선점 기록

---

## 7. 스킬/에이전트 구현 규칙

### 에이전트 파일 형식

```yaml
---
name: agent-name
description: |
  Claude가 언제 이 에이전트를 호출할지 결정하는 설명.
  3인칭으로 작성.
tools:
  - Read
  - Glob
  - Grep
model: opus|sonnet|haiku
---

# 에이전트 역할

## 관점
이 에이전트가 코드/설계를 볼 때 집중하는 측면.

## 리뷰 프로토콜
1. 무엇을 확인하는가
2. 어떤 기준으로 판단하는가
3. 출력 형식 (통과/지적사항/차단)

## 리뷰 출력 형식
- PASS: 문제 없음
- WARN: 개선 권장 (진행 가능)
- BLOCK: 수정 필요 (진행 불가)
```

### 스킬 파일 형식

```yaml
---
name: skill-name
description: |
  자동 호출 조건 설명.
argument-hint: "<인자>"
user-invocable: true
context: fork
allowed-tools:
  - 필요한 도구 목록
---

# 스킬 프로세스

## 입력
무엇을 받는가.

## 프로세스
1. 단계 1
2. 단계 2
...

## 출력
무엇을 생성하는가.

## REVIEW 연동
어떤 에이전트에게 리뷰를 요청하는가.
```

### 워크플로우 스킬 형식

```yaml
---
name: workflow-name
description: |
  워크플로우 트리거 조건.
argument-hint: "<설명>"
user-invocable: true
context: fork
allowed-tools:
  - Task
  - Skill
  - Read
  - Write
---

# 워크플로우

## 트리거 조건
언제 이 워크플로우를 사용하는가.

## DO/REVIEW 시퀀스
1. DO: /skill-name → REVIEW: agent-name
2. DO: /skill-name → AUTO (테스트 통과 시)
...

## 종료 조건
언제 워크플로우가 완료되는가.
```

---

## 8. my-harness에서 가져올 것 / 버릴 것

### 가져올 것
- deepresearch, decide 스킬 (이미 hoodcat-harness에 있음)
- 변경 추적 훅 개념 (track-change.sh → 간소화)
- 메모리 시스템 기본 구조 (Decisions, Preferences, Learnings)
- compact 복구 개념 (checkpoint)

### 버릴 것
- 20개 에이전트 체계 → 4개로 축소
- 파일 기반 메시지 큐 → 불필요 (Task 호출로 대체)
- 회의 프로토콜 (Standup/Sync/Decision/Retro) → REVIEW 단계로 통합
- Tier 기반 스킬 체계 → 단순한 DO/REVIEW로 대체
- 논스탑(ultrawork) 모드 → 워크플로우별 자동 진행으로 대체
- 대시보드 → 우선순위 낮음, 필요 시 나중에 추가

---

## 9. 성공 기준

### Phase 5 검증 시 확인할 것

1. **에이전트 차별성**: architect, reviewer, security가 같은 코드에서 실제로 다른 지적을 하는가?
2. **스킬 완결성**: 각 스킬이 입력→출력을 독립적으로 완료하는가?
3. **워크플로우 연결**: DO→REVIEW→PROCEED 체인이 자연스럽게 흐르는가?
4. **컨텍스트 효율**: 20개 에이전트 대비 컨텍스트 소비가 줄었는가?
5. **4가지 시나리오 커버**: 신규/개선/버그/보안이 각각 적절한 깊이로 처리되는가?
