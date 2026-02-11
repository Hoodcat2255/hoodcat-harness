# Claude 에이전트 & 스킬 Best Practices / Anti-Patterns 조사 결과

> 조사일: 2026-02-12

## 개요

Claude Code의 에이전트(Agent)와 스킬(Skill) 시스템에 대한 최신 best practices와 anti-patterns을 종합 조사했다. 공식 문서(Anthropic), 커뮤니티 실전 경험, 아키텍처 분석 자료를 기반으로 스킬 설계, CLAUDE.md 작성, 서브에이전트 활용, 멀티에이전트 팀 운영 전반의 권장사항과 회피패턴을 정리한다.

---

## 1. 스킬(Skill) 설계 Best Practices

### 1.1 간결성 원칙 (Concise is Key)

컨텍스트 윈도우는 공유 자원이다. 스킬의 모든 토큰이 대화 이력, 시스템 프롬프트, 다른 스킬 메타데이터와 경쟁한다.

- **SKILL.md는 500줄 이하**로 유지한다
- 상세 레퍼런스는 별도 파일로 분리하고 SKILL.md에서 참조만 한다
- Claude가 이미 아는 것은 설명하지 않는다. "PDF가 무엇인지" 같은 기본 설명은 불필요하다

```markdown
# 좋은 예 (~50 토큰)
## PDF 텍스트 추출
pdfplumber로 텍스트를 추출한다:
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()

# 나쁜 예 (~150 토큰)
## PDF 텍스트 추출
PDF(Portable Document Format)는 텍스트, 이미지 등을 포함하는 일반적인 파일 형식입니다.
텍스트를 추출하려면 라이브러리가 필요합니다. 여러 라이브러리 중 pdfplumber를 추천합니다...
```

### 1.2 Progressive Disclosure (점진적 공개)

스킬 아키텍처의 핵심 개념이다. 시작 시 메타데이터(name, description)만 로드하고, 실제 SKILL.md 전체는 스킬이 활성화될 때만 로드된다.

```
skill-name/
├── SKILL.md           # 개요 + 네비게이션 (필수, 500줄 이하)
├── reference.md       # 상세 API 문서 (필요 시 로드)
├── examples.md        # 사용 예제 (필요 시 로드)
└── scripts/
    └── helper.py      # 유틸리티 스크립트 (실행됨, 로드 안 됨)
```

**참조는 1레벨 깊이까지만 사용한다.** 중첩 참조(SKILL.md -> advanced.md -> details.md)는 Claude가 부분적으로만 읽을 수 있어 정보 손실이 발생한다.

### 1.3 Description 작성법

description은 스킬 발견(Discovery)의 핵심이다. Claude가 100개 이상의 스킬 중 적절한 것을 선택할 때 description을 기준으로 판단한다.

- **3인칭으로 작성한다** (시스템 프롬프트에 주입되므로 시점 일관성 필요)
- **무엇을 하는지 + 언제 사용하는지** 모두 포함한다
- 구체적인 키워드를 포함한다

```yaml
# 좋은 예
description: PDF 파일에서 텍스트와 테이블을 추출하고, 폼을 채우고, 문서를 병합한다.
  PDF 파일 작업이나 사용자가 PDF, 폼, 문서 추출을 언급할 때 사용한다.

# 나쁜 예
description: 문서를 처리한다
description: 데이터를 다룬다
```

### 1.4 자유도 조절 (Degrees of Freedom)

작업의 취약성과 변동성에 따라 지시의 구체성을 조절한다:

| 자유도 | 용도 | 예시 |
|--------|------|------|
| **높음** (텍스트 지침) | 여러 접근이 유효한 경우 | 코드 리뷰 프로세스 |
| **중간** (의사코드/파라미터) | 선호 패턴이 있지만 변형 허용 | 보고서 생성 템플릿 |
| **낮음** (구체적 스크립트) | 깨지기 쉽고 일관성이 중요한 작업 | DB 마이그레이션 |

### 1.5 네이밍 규칙

- **동명사형(gerund)** 권장: `processing-pdfs`, `analyzing-spreadsheets`
- 소문자, 숫자, 하이픈만 사용 (최대 64자)
- `helper`, `utils`, `tools` 같은 모호한 이름 회피
- `anthropic`, `claude` 같은 예약어 사용 금지

### 1.6 호출 제어 (Invocation Control)

| frontmatter 설정 | 사용자 호출 | Claude 자동 호출 | 용도 |
|-------------------|-------------|-------------------|------|
| (기본값) | O | O | 일반 스킬 |
| `disable-model-invocation: true` | O | X | 부작용 있는 작업 (deploy, commit) |
| `user-invocable: false` | X | O | 배경 지식 스킬 |

### 1.7 피드백 루프 패턴

복잡한 작업에는 검증 루프를 포함한다:

```
1. 작업 수행
2. 검증 스크립트 실행
3. 실패 시 → 수정 후 2번으로 복귀
4. 성공 시에만 다음 단계 진행
```

### 1.8 스크립트 활용

스킬에 번들된 스크립트는 Claude가 생성한 코드보다 신뢰성이 높고, 토큰을 절약하며, 일관성을 보장한다. 스크립트의 코드 자체는 컨텍스트 윈도우에 로드되지 않고 출력만 소비된다.

- 에러를 직접 처리한다 (Claude에게 떠넘기지 않는다)
- "매직 넘버"를 피하고 모든 상수에 이유를 문서화한다
- 실행인지 참조인지 명확히 구분한다

---

## 2. 스킬 Anti-Patterns

### 2.1 과도한 컨텍스트 소비

- SKILL.md에 방대한 내용을 직접 포함하는 것 (reference/ 분리 필요)
- 불필요한 설명 추가 (Claude가 이미 아는 내용)
- 깊은 중첩 참조 (1레벨까지만)

### 2.2 잘못된 자유도

- 깨지기 쉬운 작업에 높은 자유도 부여 (DB 마이그레이션을 "알아서 하라"고 지시)
- 단순한 작업에 낮은 자유도 부여 (코드 리뷰에 정확한 스크립트 강제)

### 2.3 선택지 과다 제시

```markdown
# 나쁜 예: 선택 마비
pypdf, pdfplumber, PyMuPDF, pdf2image 중 선택해서 사용하세요...

# 좋은 예: 기본값 제공 + 탈출구
pdfplumber로 텍스트를 추출한다. 스캔된 PDF의 경우 pdf2image + pytesseract를 대신 사용한다.
```

### 2.4 시간 종속 정보

```markdown
# 나쁜 예
2025년 8월 이전이면 구 API를, 이후면 신 API를 사용하세요.

# 좋은 예
## 현재 방식
v2 API 엔드포인트 사용: api.example.com/v2/messages
## 이전 방식 (참고용)
v1 API는 2025-08에 폐기되었다.
```

### 2.5 Windows 경로 사용

항상 forward slash(`/`)를 사용한다. `scripts\helper.py`는 Unix에서 에러를 발생시킨다.

### 2.6 도구를 설치되어 있다고 가정

```markdown
# 나쁜 예
pdf 라이브러리로 파일을 처리한다.

# 좋은 예
필요 패키지 설치: pip install pypdf
```

---

## 3. CLAUDE.md 작성 Best Practices

### 3.1 핵심 원칙

CLAUDE.md는 매 세션마다 로드되는 유일한 파일이다. 이것이 "가장 레버리지가 높은 지점"이며, 잘못된 한 줄이 연구, 계획, 코드 전체에 연쇄적으로 영향을 미친다.

- **150-200개 지시**를 Frontier 모델이 합리적으로 따를 수 있다 (시스템 프롬프트의 ~50개 포함)
- **300줄 이하**, 이상적으로는 **60줄 이하**
- 각 줄에 대해 자문한다: "이것을 삭제하면 Claude가 실수할까?" 아니라면 삭제한다

### 3.2 포함해야 할 것

| 포함 | 제외 |
|------|------|
| Claude가 추측할 수 없는 Bash 명령 | Claude가 코드를 읽으면 알 수 있는 것 |
| 기본값과 다른 코드 스타일 규칙 | Claude가 이미 아는 표준 언어 규칙 |
| 테스트 실행 방법, 선호 테스트 러너 | 상세 API 문서 (링크로 대체) |
| 브랜치 네이밍, PR 규칙 | 자주 변경되는 정보 |
| 프로젝트 고유 아키텍처 결정 | 긴 설명이나 튜토리얼 |
| 개발 환경 특이사항 (필수 env vars) | 파일별 코드베이스 설명 |
| 흔한 실수/비직관적 동작 | "깨끗한 코드를 작성하라" 같은 자명한 것 |

### 3.3 Anti-Patterns

1. **과도한 CLAUDE.md**: 너무 길면 Claude가 절반을 무시한다. 중요한 규칙이 노이즈에 묻힌다.
2. **린터 역할 시키기**: 코드 스타일은 ESLint/Biome 같은 결정론적 도구에 맡긴다. LLM은 비싸고 느리다.
3. **자동 생성 의존**: `/init`으로 생성 후 수동 검토 없이 사용. 각 줄을 의도적으로 작성해야 한다.
4. **명령어 나열**: 모든 가능한 명령이나 구현 세부사항을 나열. LLM은 기존 패턴에서 학습한다.
5. **포인터 대신 복사**: 코드 스니펫을 직접 포함하면 금방 구식이 된다. 경로 참조를 사용한다.

### 3.4 Progressive Disclosure 전략

```
agent_docs/
  ├── building_the_project.md
  ├── running_tests.md
  ├── code_conventions.md
  ├── service_architecture.md
  └── database_schema.md
```

CLAUDE.md에서는 간략한 설명과 함께 이 파일들을 참조한다.

---

## 4. 서브에이전트(Subagent) Best Practices

### 4.1 서브에이전트의 진짜 목적

핵심 통찰: **서브에이전트는 정보 수집기(information collector)이지 구현자(implementer)가 아니다.**

Claude Code 핵심 엔지니어의 발언: "서브에이전트는 정보를 찾고 메인 대화 스레드에 작은 요약을 제공할 때 가장 잘 작동한다."

서브에이전트의 올바른 용도:
- 메인 컨텍스트의 파일 읽기 오버헤드 감소
- 원본 데이터 대신 압축된 요약 반환
- 메인 에이전트의 컨텍스트 윈도우 보존

### 4.2 Explore-Planning-Execute 워크플로우

1. **Explore**: 에이전트가 문서/로그를 읽고, 코드베이스를 분석하고, 결과를 요약한다
2. **Planning**: 탐색 보고서를 받아 상세 구현 계획을 수립한다 (진행 전 항상 검증)
3. **Execute**: 메인 에이전트가 구현하고, 검증용 에이전트(코드 리뷰어, 테스터)를 호출한다

### 4.3 전문화된 에이전트 팀 구성 권장

- **Planner-Researcher**: 코드베이스 이해, 솔루션 연구, 상세 계획 작성
- **Debugger**: CI 로그 분석, DB 쿼리, 문제 진단
- **Tester**: 테스트 스위트 실행, 실패 분석, 수정 권장
- **Code-Reviewer**: 품질 점검, 보안 감사, 성능 리뷰
- **Docs-Manager**: 문서 표준 유지, 업데이트

**이 중 어느 것도 직접 구현을 담당하지 않는다.**

### 4.4 서브에이전트 Anti-Patterns

1. **구현 위임**: 서브에이전트를 전문 개발자처럼 사용. 프로젝트 전체 컨텍스트가 없어 경계 버그 발생.
2. **모든 도구 허용**: 모든 에이전트에 모든 도구를 부여하면 역할 이탈, 중복 작업, 컨텍스트 오염 발생.
3. **더 빠른 결과 기대**: 서브에이전트는 종종 메인 에이전트보다 느리고 토큰 소비가 많다.
4. **암묵적 자동 선택 의존**: Claude가 적절한 에이전트를 자동 선택하리라 기대. 명시적 지정이 필요하다.
5. **컨텍스트 손실 무시**: 에이전트 출력을 거부하면 새 인스턴스가 생성되어 축적된 지식이 사라진다.
6. **과도한 에이전트 수**: 10-15개 이상의 에이전트는 200K 토큰 예산을 빠르게 소모하고 1시간 이상 소요될 수 있다.
7. **에이전트 목록 과다**: 긴 에이전트 목록은 관련성 신호를 희석시킨다.
8. **피상적 출력 방치**: "looks good" 같은 최소 응답을 후속 프롬프트 없이 수용.

---

## 5. 에이전트 팀(Agent Teams) Best Practices

### 5.1 적합한 사용 사례

에이전트 팀은 병렬 탐색이 실제 가치를 더하는 작업에 가장 효과적이다:

- **연구와 리뷰**: 여러 팀원이 문제의 다른 측면을 동시에 조사
- **새 모듈/기능**: 각 팀원이 간섭 없이 별도 부분 담당
- **경쟁 가설 디버깅**: 여러 이론을 병렬로 검증하고 수렴
- **크로스 레이어 조정**: 프론트엔드, 백엔드, 테스트 각각 별도 팀원 담당

### 5.2 팀 운영 핵심 원칙

1. **팀원에게 충분한 컨텍스트 제공**: 팀원은 리더의 대화 이력을 상속받지 않는다. 스폰 프롬프트에 태스크별 세부사항을 포함해야 한다.
2. **적절한 태스크 크기**: 너무 작으면 조정 오버헤드가 이점을 초과. 너무 크면 낭비 위험 증가. 명확한 산출물이 있는 자족적 단위가 적당.
3. **팀원당 5-6개 태스크**: 모든 팀원을 생산적으로 유지하고 재배분 가능.
4. **파일 충돌 방지**: 두 팀원이 같은 파일을 편집하면 덮어쓰기 발생. 각 팀원이 다른 파일 세트를 소유하도록 분배.
5. **모니터링과 조타**: 무감독 실행은 낭비 위험 증가. 진행 상황을 확인하고 재방향 설정.

### 5.3 vs 서브에이전트 선택 기준

| 항목 | 서브에이전트 | 에이전트 팀 |
|------|-------------|-------------|
| **컨텍스트** | 자체 윈도우, 결과를 호출자에게 반환 | 자체 윈도우, 완전 독립 |
| **통신** | 메인 에이전트에만 결과 보고 | 팀원 간 직접 메시지 교환 |
| **조정** | 메인 에이전트가 모든 작업 관리 | 공유 태스크 리스트, 자기 조정 |
| **최적 용도** | 결과만 중요한 집중 작업 | 토론과 협업이 필요한 복잡한 작업 |
| **토큰 비용** | 낮음 | 높음 (각 팀원이 별도 Claude 인스턴스) |

### 5.4 에이전트 팀 Anti-Patterns

1. **순차적 작업에 팀 사용**: 의존성이 많은 순차 작업은 단일 세션이 더 효과적.
2. **리더가 직접 구현**: 리더가 위임 대신 직접 코딩. Delegate 모드로 방지.
3. **팀원 완료 전 진행**: 리더가 팀원 완료 전에 작업 종료 판단.
4. **동일 파일 동시 편집**: 파일 충돌로 변경 사항 덮어쓰기.
5. **컨텍스트 부족한 스폰**: 팀원에게 배경 정보 없이 태스크만 전달.

---

## 6. 컨텍스트 관리 Best Practices

### 6.1 핵심 제약

Claude Code의 모든 best practice는 하나의 제약에 기반한다: **컨텍스트 윈도우가 빠르게 채워지고, 채워질수록 성능이 저하된다.**

### 6.2 실전 관리법

- **`/clear`**: 무관한 작업 간에 컨텍스트 리셋
- **2번 수정 후 실패 시**: `/clear` 후 학습한 내용을 포함한 더 나은 초기 프롬프트로 재시작
- **서브에이전트 활용**: 탐색은 서브에이전트에 위임하여 메인 컨텍스트를 보호
- **`/compact <지시>`**: 사용자 정의 요약 (예: "API 변경 사항과 테스트 명령을 반드시 보존")
- **연속 세션**: `claude --continue`로 컨텍스트를 이어가되, 세션을 `--resume`으로 관리

### 6.3 Anti-Patterns

1. **Kitchen Sink 세션**: 한 작업 중 무관한 질문 후 원래 작업 복귀. 불필요 정보로 컨텍스트 오염.
2. **반복 수정**: 실패한 접근이 컨텍스트에 누적되어 성능 저하.
3. **무한 탐색**: 범위 없는 "조사" 요청으로 수백 파일 읽기. 범위를 좁히거나 서브에이전트를 사용.
4. **신뢰-검증 격차**: 그럴듯해 보이지만 엣지 케이스를 처리하지 못하는 구현을 수용.

---

## 7. 검증과 품질 보증

### 7.1 자기 검증 기준 제공

Claude의 성능을 극적으로 향상시키는 단일 최고 레버리지 행동: **테스트, 스크린샷, 예상 출력을 제공하여 Claude가 스스로 확인할 수 있게 한다.**

```
# 나쁜 예
이메일 유효성 검증 함수를 구현해

# 좋은 예
validateEmail 함수를 작성해. 테스트 케이스: user@example.com은 true,
invalid는 false, user@.com은 false. 구현 후 테스트를 실행해.
```

### 7.2 빌드/테스트 검증 규칙

- 빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다
- "통과했습니다" 같은 텍스트 보고를 신뢰하지 않는다
- Hook을 통한 자동 검증을 설정한다

### 7.3 Evaluation-Driven Development

스킬 개발 시 문서화 전에 평가(Evaluation)를 먼저 만든다:

1. **갭 식별**: 스킬 없이 대표 태스크 실행 후 구체적 실패 문서화
2. **평가 생성**: 갭을 테스트하는 3개 시나리오 구축
3. **베이스라인 측정**: 스킬 없이 Claude 성능 측정
4. **최소 지침 작성**: 갭을 해결할 최소 내용만 작성
5. **반복**: 평가 실행, 베이스라인과 비교, 개선

---

## 8. 고급 패턴

### 8.1 동적 컨텍스트 주입

`!`command`` 구문으로 셸 명령을 전처리하여 Claude에게 실제 데이터를 전달한다:

```yaml
---
name: pr-summary
description: PR 변경 사항 요약
context: fork
agent: Explore
---
## PR 컨텍스트
- PR diff: !`gh pr diff`
- PR 코멘트: !`gh pr view --comments`
- 변경 파일: !`gh pr diff --name-only`
```

### 8.2 서브에이전트에서 스킬 실행

`context: fork`를 사용하면 스킬이 격리된 서브에이전트에서 실행된다. 스킬 내용이 서브에이전트의 프롬프트가 된다.

주의: `context: fork`는 **명시적 지시가 있는 스킬에서만** 의미가 있다. "이 API 규칙을 따르라" 같은 가이드라인만 있으면 서브에이전트가 아무런 의미 있는 출력 없이 반환된다.

### 8.3 Hook 기반 품질 게이트

- **TaskCompleted**: 구현 태스크 완료 시 빌드/테스트 자동 검증. exit 2로 완료 차단.
- **TeammateIdle**: 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도.

### 8.4 Writer/Reviewer 패턴

별도 세션에서 작성과 리뷰를 분리하여 편향 방지:

| 세션 A (Writer) | 세션 B (Reviewer) |
|-----------------|-------------------|
| rate limiter 구현 | src/middleware/rateLimiter.ts 리뷰 |
| 리뷰 피드백 반영 | - |

### 8.5 스킬 도구 권한 스코핑

와일드카드를 사용한 세분화된 권한 경계:

```yaml
allowed-tools: Bash(git *), Read, Grep, Glob
```

모든 도구를 허용하는 대신 필요한 도구만 명시적으로 허용한다.

---

## 코드 예제

### 효과적인 워커 스킬 구조

```yaml
---
name: fix-issue
description: GitHub 이슈를 분석하고 수정한다. gh CLI를 사용하여 이슈 세부사항을
  확인하고, 코드베이스를 탐색하여 원인을 파악한 후, 수정을 구현하고 테스트한다.
context: fork
disable-model-invocation: true
allowed-tools: Read, Grep, Glob, Bash(git *), Bash(gh *), Edit
---

GitHub 이슈 $ARGUMENTS를 코딩 표준에 따라 수정한다.

1. `gh issue view $ARGUMENTS`로 이슈 세부사항 확인
2. 문제 이해 및 관련 코드 탐색
3. 수정 구현
4. 테스트 작성 및 실행
5. 린트/타입체크 통과 확인
6. 커밋 생성
```

### 효과적인 에이전트 정의

```markdown
---
name: security-reviewer
description: 보안 취약점을 검토한다
tools: Read, Grep, Glob, Bash
model: opus
---
보안 엔지니어로서 다음을 검토한다:
- 인젝션 취약점 (SQL, XSS, 커맨드 인젝션)
- 인증/인가 결함
- 코드 내 시크릿/자격증명
- 안전하지 않은 데이터 처리

구체적인 라인 참조와 수정 제안을 포함한다.
```

---

## 주요 포인트

1. **컨텍스트 윈도우가 가장 중요한 자원**이다. 모든 설계 결정은 컨텍스트 효율성을 중심으로 이루어져야 한다. SKILL.md 500줄, CLAUDE.md 300줄 이하를 유지하고, Progressive Disclosure를 적극 활용한다.

2. **서브에이전트는 정보 수집기이지 구현자가 아니다.** 구현을 서브에이전트에 위임하면 프로젝트 전체 컨텍스트 부재로 경계 버그가 발생한다. Explore-Planning-Execute 워크플로우를 따른다.

3. **검증 가능한 성공 기준을 항상 제공한다.** 테스트, 스크린샷, exit code 기반 판단이 Claude의 성능을 극적으로 향상시킨다. 텍스트 보고를 신뢰하지 않는다.

4. **에이전트 팀은 병렬 탐색에 최적이며, 순차 작업에는 부적합하다.** 파일 충돌을 방지하고, 팀원에게 충분한 컨텍스트를 제공하며, 적절한 태스크 크기를 유지한다. 토큰 비용이 높으므로 진정한 병렬 가치가 있을 때만 사용한다.

5. **CLAUDE.md는 가장 레버리지가 높은 설정 지점**이다. 짧고 보편적인 지시만 포함하고, Claude가 이미 아는 것은 제외하며, 린터의 역할을 시키지 않는다. 정기적으로 가지치기하고 Claude의 행동 변화를 관찰하여 반복 개선한다.

---

## 출처

- [Extend Claude with skills - Claude Code Docs](https://code.claude.com/docs/en/skills)
- [Best Practices for Claude Code - Claude Code Docs](https://code.claude.com/docs/en/best-practices)
- [Skill authoring best practices - Claude API Docs](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Orchestrate teams of Claude Code sessions - Claude Code Docs](https://code.claude.com/docs/en/agent-teams)
- [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Common Sub-Agent Anti-Patterns and Pitfalls - Steve Kinney](https://stevekinney.com/courses/ai-development/subagent-anti-patterns)
- [Claude Code Subagents: Common Mistakes & Best Practices - ClaudeKit](https://claudekit.cc/blog/vc-04-subagents-from-basic-to-deep-dive-i-misunderstood)
- [Writing a good CLAUDE.md - HumanLayer Blog](https://www.humanlayer.dev/blog/writing-a-good-claude-md)
- [GitHub - anthropics/skills](https://github.com/anthropics/skills)
- [GitHub - VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills)
- [Claude Code Customization Guide - alexop.dev](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)
- [Claude Code multiple agent systems: Complete 2026 guide - eesel.ai](https://www.eesel.ai/blog/claude-code-multiple-agent-systems-complete-2026-guide)
- [Claude Skills and CLAUDE.md: a practical 2026 guide for teams - gend.co](https://www.gend.co/blog/claude-skills-claude-md-guide)
- [Create custom subagents - Claude Code Docs](https://docs.anthropic.com/en/docs/claude-code/sub-agents)
- [Equipping agents for the real world with Agent Skills - Anthropic](https://www.anthropic.com/engineering/equipping-agents-for-the-real-world-with-agent-skills)
