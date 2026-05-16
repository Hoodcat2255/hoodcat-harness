# Blueprint: Agent Disagreement Handling Improvement

> 작성일: 2026-05-16
> 작성자: researcher (Task)
> 입력 이슈: `docs/issue-agent-disagreement-handling-20260516.md`
> 상태: Open (적용 대기)
> 범위: Main Agent / Orchestrator / Researcher (deepresearch 스킬 포함) / Coder·Committer (간접)

---

## 1. 요구사항

### 1.1 기능 요구사항 (FR)

| ID | 요구사항 | 출처 |
|----|---------|------|
| FR-1 | 사실 검증 시 1차 자료(법령·공고문·공식 API 응답)를 2차/일반론보다 우선 채택한다 | 제안 1 |
| FR-2 | 사용자의 의심/검증 요구 키워드 감지 시 `deepresearch`를 자동 호출하고 직전 답변을 "추정"으로 강등한다 | 제안 2 |
| FR-3 | 모든 사실 주장에 출처와 자신감 수준을 명시한다 (단정적 어조 금지) | 제안 3 |
| FR-4 | 사용자 반박 수신 직후 응답 전에 5문항 자기 점검을 통과해야 한다 | 제안 4 |
| FR-5 | 사용자 직관이 옳았던 사례를 구조화된 스키마로 누적 기록하고, 동일 도메인 후속 대화에서 사전 확률을 높인다 | 제안 5 |

### 1.2 비기능 요구사항 (NFR)

| ID | 요구사항 | 임계값 / 기준 |
|----|---------|---------------|
| NFR-1 | 키워드 트리거 정밀도(precision) — 단순 확인 질문에 deepresearch 오발동 비율 | 측정 후 30% 이하 유지 (초기 임계 임시) |
| NFR-2 | 한국어/영어 키워드 동시 커버 | 단일 정규식·키워드 리스트로 양 언어 포함 |
| NFR-3 | Epistemic Honesty 적용 후 평균 응답 길이 증가폭 | +30% 이내 (이상 시 표현 압축 규칙 추가) |
| NFR-4 | 1차 자료 접근 불가 도메인에서도 동작이 멈추지 않음 | "도달 불가" 명시 + 가용한 최고 등급 자료로 fallback |
| NFR-5 | 기존 `Factual Claim Verification` 섹션과 충돌 없이 통합 | 한 섹션 안에서 read once로 끝나는 흐름 유지 |
| NFR-6 | 메모리 200줄 제한 준수 (Memory Management 기존 규칙) | Lessons Learned는 별도 파일로 분리, MEMORY.md에는 인덱스만 |

### 1.3 합리적 가정 (명시적 기록)

- A1. 이슈 문서의 사례 4건은 모두 한국 청약 도메인이지만, 블루프린트가 만드는 규칙은 도메인 비특정으로 작성한다 (법률·세무·의료 등 1차 자료 존재 도메인 일반화).
- A2. "사용자 반박 키워드"는 정규식 기반 단순 매칭으로 시작한다 (의미 분석 없이). 오발동율은 운영 후 측정하여 조정.
- A3. 키워드 트리거는 Orchestrator 레벨에서 작동하며 Main Agent가 직접 deepresearch를 호출하지 않는다 (기존 디스패치 규칙 유지). Main Agent는 사용자 반박을 그대로 Orchestrator에 위임하면 Orchestrator가 트리거를 평가한다.
- A4. coder/committer/architect/security/reviewer/navigator 등 워커 에이전트는 본 이슈 범위가 아니므로 직접 수정하지 않는다. 단, 신규 규칙 파일은 전 에이전트가 참조 가능한 위치에 둔다.

---

## 2. 설계 — 다섯 개선안 매핑 및 정본 결정

### 2.1 최종 적용 위치 매핑 표

| 개선안 | 정본 위치 (Source of Truth) | 참조 위치 (Cross-Reference Only) | 작업 형태 |
|--------|-----------------------------|----------------------------------|----------|
| 1. Source Hierarchy | 신규 `.claude/rules/source-hierarchy.md` | (a) `orchestrator.md` Verification Rules에서 1줄 링크<br>(b) `researcher.md` Constraints에서 1줄 링크<br>(c) `deepresearch/SKILL.md` 프로세스 1단계에서 1줄 링크 | 신규 파일 + 3곳 링크 |
| 2. User Pushback Trigger | `orchestrator.md` (신규 절 `### Pushback Trigger` 추가, `## Execution Protocol` 하위) | — | 섹션 추가 |
| 3. Epistemic Honesty | 신규 `.claude/rules/epistemic-honesty.md` | (a) `orchestrator.md`에서 1줄 링크<br>(b) `researcher.md`에서 1줄 링크 | 신규 파일 + 2곳 링크 |
| 4. Self-Check on Pushback | `orchestrator.md` (신규 절 `### Self-Check on Pushback`, Pushback Trigger 바로 다음) | `researcher.md`에 동일 5문항 인라인 복제 (researcher는 단독 호출 시 트리거 이전에 자체 점검 필요) | 섹션 추가 + 1곳 복제 |
| 5. Lessons Learned 메모리 | 신규 `.claude/agent-memory/orchestrator/lessons-learned.md`<br>+ `.claude/agent-memory/orchestrator/MEMORY.md` 인덱스 | `.claude/agent-memory/researcher/MEMORY.md`에서 1줄 cross-link만 추가 (중복 저장 금지) | 신규 파일 2개 + 인덱스 |

### 2.2 정본 1곳 + 참조 다곳 원칙의 근거

- Source Hierarchy를 세 파일에 본문으로 복제하면 향후 갱신 시 drift가 생긴다. 갱신 비용·일관성을 위해 `.claude/rules/`에 정본을 두고 각 에이전트는 1줄 링크만 둔다.
- `.claude/rules/` 자체가 이미 `antipatterns-*.md` 형태로 전 에이전트 공통 규칙을 보관하는 위치이므로 자연스럽게 들어맞는다.
- Self-Check만은 예외다 — 매 응답 직전에 즉시 참조해야 하는 체크리스트라 정본/참조 모델보다 "Orchestrator에 본문, Researcher에 복제"가 인지 비용이 낮다. 복제로 인한 drift는 5문항이 거의 변하지 않을 것이므로 허용한다.

### 2.3 개선안 간 의존·충돌 분석

#### 2.3.1 제안 2 (Pushback Trigger) ↔ 제안 4 (Self-Check) 관계

- 두 제안은 **트리거-실행 관계**다. 제안 2가 "언제 발동하나"를 정하고, 제안 4가 "발동 후 무엇을 점검하나"를 정한다.
- 통합 흐름: 사용자 반박 수신 → 제안 2 키워드 매칭 → 매칭 시 ① Self-Check 5문항 평가 ② No가 1개 이상이면 deepresearch 호출 / 모두 Yes면 직전 답변 유지하되 자신감 수준 명시.
- 중복 아님. 제안 2 없이 제안 4만 두면 "언제 점검하나" 기준이 모호. 제안 4 없이 제안 2만 두면 점검 없이 무조건 deepresearch 호출되어 비용 증가.
- 결론: 두 절을 `## Execution Protocol` 안에 인접 배치하고 단일 절차로 묶는다.

#### 2.3.2 제안 1 (Source Hierarchy) 위치 결정

- 세 후보 (orchestrator/researcher/deepresearch) 모두 의미상 적합하나, 본문 복제 시 drift 위험.
- 결정: `.claude/rules/source-hierarchy.md` 단일 정본. 세 파일에서 1줄 링크 (`@.claude/rules/source-hierarchy.md` 또는 자연 문장 참조).
- 이유: (a) drift 방지, (b) 향후 다른 에이전트(coder가 라이브러리 버전 확인 시 등)도 동일 규칙 참조 가능, (c) `.claude/rules/`의 기존 패턴 활용.

#### 2.3.3 제안 3 (Epistemic Honesty) 적용 범위

- 옵션 A: 전 에이전트 공통 (`.claude/rules/`에 두고 모두 참조)
- 옵션 B: orchestrator·researcher만 (사실 진술이 주된 에이전트)
- 결정: 옵션 A를 채택하되 본문 적용은 orchestrator·researcher에 우선 링크. coder/committer/reviewer 등은 사실 진술 비중이 낮아 명시적 참조 없이도 무방하나, 신규 파일은 누구나 참조 가능한 위치에 둔다.
- 이유: 추후 coder/security가 의존성 버전·취약점 보고 시에도 동일 규칙 적용이 자연스럽다. 정본을 `rules/`에 두면 확장 비용이 0이다.

#### 2.3.4 기존 `### Factual Claim Verification` 섹션 통합 방식

- 기존 섹션은 "주장에 raw output 첨부 + 추론/사실 분리 + 빈틈 인정 + 교차 검증" 4개 항목으로 구성됨.
- 본 이슈의 제안 1·4는 "주장 이전 단계의 자료 등급 결정"과 "사용자 반박 후 점검"에 초점.
- 결정: 기존 섹션은 그대로 유지. 제안 1은 `.claude/rules/source-hierarchy.md`로 분리하고 기존 섹션 끝에 1줄 cross-link 추가 ("자료 등급 판정은 `.claude/rules/source-hierarchy.md` 참조"). 제안 4는 별도 절(`### Self-Check on Pushback`)로 신설.
- 결과: `## Verification Rules` 안에 `### Factual Claim Verification` (기존) + 1줄 링크 / `### Self-Check on Pushback` (신규) 구조.

#### 2.3.5 제안 5 (Lessons Learned) ↔ subagent-hallucination.md 통합 여부

- 두 패턴 비교:
  - `subagent-hallucination.md`: 서브에이전트가 데이터를 **날조**하고 그 위에 인과 구성. (없는 사실을 만들어냄)
  - 본 이슈 사례: 학습된 일반론을 1차 자료보다 우선하여 **단정적 추측**. (있는 사실을 무시하고 일반론으로 단정)
- 두 패턴 모두 "사실 검증 우선" 계열이나 메커니즘이 다르다:
  - 환각 = supply-side 문제 (없는 정보를 만듦)
  - 추측 단정 = demand-side 문제 (있는 정보를 안 찾고 답함)
- 결정: **분리 유지**. 두 파일을 독립으로 두고 cross-link만 추가.
  - `.claude/agent-memory/orchestrator/lessons-learned.md` (신규, 본 이슈 사례 4건)
  - `~/.claude/projects/.../memory/subagent-hallucination.md` (기존, 환각 패턴)
- 두 파일 모두 `MEMORY.md`(orchestrator)의 "## Lessons Learned" 또는 "## Done" 섹션에서 인덱스로 참조.
- 이유: 통합 시 한 파일이 "에이전트 실패 패턴 모음"이 되어 비대해지고, 패턴이 섞이면 미래 에이전트가 어느 메커니즘이 적용되는지 판단하기 어렵다. 분리하면 두 파일이 각자 일관된 교훈을 제공한다.

#### 2.3.6 시드 데이터 위치 결정 (orchestrator vs researcher)

- 후보 1: `.claude/agent-memory/researcher/lessons-learned.md`
- 후보 2: `.claude/agent-memory/orchestrator/lessons-learned.md`
- 결정: **후보 2 (orchestrator)** 채택.
- 이유:
  - 사용자 반박 트리거는 Orchestrator가 평가하고 deepresearch를 호출한다. 따라서 "사용자 직관이 옳았던 사례"의 사전 확률을 활용해야 할 주체가 Orchestrator다.
  - researcher는 fork 컨텍스트에서 단발성 조사 수행이 주된 역할이라 "이전 사례 기반 사전 확률 조정"이 자연스럽지 않다.
  - researcher의 MEMORY.md는 이미 16KB로 컨텍스트 포화 위험. 추가 데이터 누적은 orchestrator 쪽이 안전.
  - researcher MEMORY.md에는 cross-link만 추가하여, researcher가 도메인 조사 중 동일 도메인 사례를 인지하도록 한다.

---

## 3. 신규 파일 사양

### 3.1 `.claude/rules/source-hierarchy.md` (신규)

목적: 1차 자료 우선 원칙 정본.

섹션 구조:
- 개요 (1문단): 자료 등급별 우선순위 원칙
- Tier 정의 4단계 (Tier 1~4): 이슈 문서 제안 1과 동일. 단 각 Tier에 도메인별 예시 추가 (법령/세무/의료/주거/금융 등)
- 적용 규칙: 상위 등급 미확인 시 하위 등급으로 단정 금지. 1차 자료 도달 불가 시 fallback 표현법 명시.
- 도메인 트리거 리스트: Tier 1 확인이 강제되는 도메인 (법률, 청약·주거, 세무, 의료, 약품, 금융 규제 등). 도메인 매칭 시 deepresearch를 통해 1차 자료 직접 인용 의무.
- Tier 1 도달 불가 시 동작 (NFR-4 대응): "Tier 1 미확인" 명시 + 최고 가용 등급으로 답변하되 자신감 수준 명시.

### 3.2 `.claude/rules/epistemic-honesty.md` (신규)

목적: 단정적 표현 회피·자신감 수준 명시 정본.

섹션 구조:
- 개요: 출처 없는 단정 금지 원칙
- 표현 규칙: "X는 Y이다" 단정형 회피, "공고문 N페이지에 따르면 Y", "법령 제N조에 따르면 Y" 형태 사용.
- 자신감 라벨 3단계: `확실` (Tier 1 확인) / `추정` (Tier 3/4 또는 학습 데이터) / `모름` (조사 필요)
- 비유 사용 제약: 검증된 모델에만 비유 허용. 추측 단계 비유 금지.
- 출력 길이 압축 가이드 (NFR-3 대응): 자신감 라벨은 1회 명시 후 동일 단락 안에서 반복 금지. 출처 인용은 첫 등장 시만 전체, 이후 약식.
- 적용 범위: 사실 진술이 포함된 모든 에이전트 응답.

### 3.3 `.claude/agent-memory/orchestrator/MEMORY.md` (신규)

목적: orchestrator 에이전트의 영속 메모리 인덱스. 기존 빈 디렉토리에 신규 생성.

초기 구조 (200줄 제한):
- `## Lessons Learned` — 핵심 패턴 모음 (인덱스만)
  - `- [사용자 직관 우선 사례](lessons-learned.md) — 1차 자료 우선·반박 미수용 패턴`
  - `- [서브에이전트 환각](~/.claude/projects/.../memory/subagent-hallucination.md) — 데이터 날조 패턴` (cross-link)
- `## Done` — 빈 섹션 (시드 단계)
- `## TODO` — 빈 섹션

### 3.4 `.claude/agent-memory/orchestrator/lessons-learned.md` (신규)

목적: 사용자 직관이 옳았던 사례 누적 저장소. 본 이슈의 사례 4건을 시드로 채움.

스키마 (사례 1건당):
```yaml
case_id: integer
date: YYYY-MM-DD
domain: string (예: korean-housing-subscription, korean-tax, k8s-rbac)
domain_tags: [string, ...] (예: [housing, subscription, korea, 2024-policy-change])
user_claim: string (사용자 주장 1~2문장)
initial_agent_response: string (에이전트 1차 답변 요약)
push_count: integer (사용자가 몇 회 push해야 deepresearch가 호출됐는지)
final_correct_answer: string (deepresearch 결과 정답)
primary_source: string (1차 자료 출처 — 법령 조항, 공고문 페이지 등)
root_cause: string (학습 데이터 일반론 우선 / 최근 제도 변경 미반영 / 비유 추측 / 등)
lesson: string (다음번 동일 도메인 진입 시 사전에 deepresearch 호출하도록 하는 휴리스틱)
```

### 3.5 시드 데이터 4건 (lessons-learned.md 초기 콘텐츠)

| case_id | domain | 핵심 교훈 |
|---------|--------|----------|
| 1 | korean-housing-subscription | 2024-03 시행 부부 동시 청약 특례. 청약 제도 답변 전 deepresearch 의무 (학습 데이터에 미반영). |
| 2 | korean-housing-subscription | "후접수 추첨 박스" 비유는 사실과 불일치. 추첨/접수 절차 비유 사용 금지, 1차 자료 인용으로 대체. |
| 3 | korean-housing-subscription | 부부 동시 청약 특례는 민간/공공 구분 없이 적용. 블로그 일반론 단정 금지. |
| 4 | korean-housing-subscription | 트랙 분산이 항상 안전한 것 아님. 사용자의 도메인 직관(가점 기반 단일 트랙 집중)이 일반론적 위험분산보다 우선할 수 있음. |

추가 메타 교훈 (시드 4건 종합):
- **도메인 트리거**: `korean-housing-subscription` 도메인은 매번 deepresearch 선행. 학습 데이터 일반론 사용 금지.
- **시점 의식**: "2024-XX 시행" 같은 최근 제도 변경 가능성을 항상 가정 (학습 데이터 cutoff 이후).

---

## 4. 기존 파일 변경 사양

### 4.1 `.claude/agents/orchestrator.md`

변경 내용:

| 위치 | 변경 형태 | 내용 |
|------|----------|------|
| `## Verification Rules` 끝 (L443 직전) | 1줄 추가 | `- 자료 등급은 .claude/rules/source-hierarchy.md를 따른다 (Tier 1 우선)` |
| `### Factual Claim Verification` (L445~L452) | 변경 없음 | 기존 4항목 유지 |
| `## Verification Rules` 새 절 (Factual Claim Verification 다음) | 신규 추가 | `### Self-Check on Pushback` — 5문항 체크리스트 + 1개 이상 No 시 deepresearch 호출 규칙 |
| `## Execution Protocol` → `### Adaptive Execution` 다음 | 신규 추가 | `### Pushback Trigger` — 키워드 리스트(한/영) + 매칭 시 동작 (Self-Check → deepresearch 호출) |
| `## Memory Management` (L476) | 1~2줄 추가 | 메모리 파일 목록에 `lessons-learned.md` 안내. 작업 시작 시 도메인 매칭 확인 의무 명시 |

#### 4.1.1 `### Pushback Trigger` 신규 절 (요지)

- 키워드 매칭은 정규식 기반.
- 한국어 키워드: `정말`, `확실`, `진짜`, `맞아`, `다시 확인`, `다시 조사`, `근거`, `공고문`, `원문`, `1차 자료`
- 영어 키워드: `really`, `sure`, `verify`, `confirm`, `source`, `evidence`, `primary source`, `original`
- 매칭 시 절차: (1) Self-Check 5문항 평가 → (2) No 1개 이상이면 deepresearch 호출 + 직전 답변을 "추정"으로 강등 알림 → (3) 모두 Yes면 직전 답변 유지하되 자신감 수준 명시.
- 같은 주장 2회 연속 반복도 매칭 조건 (직전 답변이 틀렸을 가능성).
- 오발동 완화: 사용자가 "맞아요, 그렇게 진행해줘" 같은 긍정 확인일 때는 트리거 안 됨 — 직전 턴이 질문/제안이고 사용자 응답이 동의면 제외. 휴리스틱 1: 직전 Orchestrator 출력이 "Y인가요?" 같은 질문 형식이면 사용자 응답의 "정말"은 트리거 안 함.

#### 4.1.2 `### Self-Check on Pushback` 신규 절 (요지)

5문항 (이슈 문서 제안 4와 동일):
1. 인용 근거 등급은? (Tier 1 vs Tier 3/4)
2. 본 도메인의 원본 문서를 직접 확인했는가?
3. 사용자 주장이 맞을 가능성을 검토했는가?
4. 최근 제도/사양 변경 가능성을 검토했는가?
5. 단정적 어조가 실제 근거 수준에 비례하는가?

판정 규칙: No가 1개라도 있으면 답변 보류 → deepresearch 호출.

#### 4.1.3 `## Memory Management` 변경 (요지)

추가 문구:
- 작업 시작 시 `.claude/agent-memory/orchestrator/lessons-learned.md`를 읽고, 사용자 요청 도메인이 기록된 도메인과 일치하면 **사전에 deepresearch 호출**한다 (사용자 반박을 기다리지 않음).
- 사용자 직관이 옳았던 새 사례 발생 시 `lessons-learned.md`에 schema에 맞춰 추가한다.

### 4.2 `.claude/agents/researcher.md`

변경 내용:

| 위치 | 변경 형태 | 내용 |
|------|----------|------|
| `## Constraints` 끝 | 1줄 추가 | `- 자료 등급 판정은 .claude/rules/source-hierarchy.md를 따른다 (Tier 1 우선)` |
| `## Constraints` 끝 | 1줄 추가 | `- 출력 표현은 .claude/rules/epistemic-honesty.md를 따른다 (자신감 라벨 명시)` |
| `## Output Standards` 끝 | 1~2줄 추가 | 사실 주장에는 Tier 등급과 자신감 라벨을 함께 표기한다 |
| 신규 절 `## Self-Check on Pushback` (Constraints 다음) | 신규 추가 | Orchestrator의 5문항 체크리스트 복제 (drift 위험 낮음, 단독 호출 시 자체 점검 필요) |

researcher.md는 대화 출력 마크다운 금지 규칙이 있으므로, 자신감 라벨은 보고서 본문(`.md` 산출물)에는 적용하고 Orchestrator/사용자에게 보고하는 대화 텍스트에는 자연 문장으로 풀어 표기 (`라벨: 확실` 대신 "1차 자료 확인됨").

### 4.3 `.claude/skills/deepresearch/SKILL.md`

변경 내용:

| 위치 | 변경 형태 | 내용 |
|------|----------|------|
| `## 프로세스` → `### 1. 병렬 정보 수집` 도입부 | 1줄 추가 | `- 자료 등급 우선순위는 .claude/rules/source-hierarchy.md를 따른다. Tier 1 후보를 먼저 식별한다.` |
| `### 2. 심화 조사` 끝 | 1줄 추가 | 도메인이 법령/세무/의료/주거/금융 등 1차 자료 존재 도메인이면, 공식 정부/기관 사이트 직접 확인을 추가로 수행한다 |
| `### 3. 결과 저장` 템플릿 | 1줄 추가 | "출처" 섹션에 각 출처의 Tier 라벨 표기 (예: `- (Tier 1) [공고문 PDF](URL)`) |

### 4.4 `.claude/agent-memory/researcher/MEMORY.md`

변경 내용 (기존 16KB 파일에 cross-link만 추가, 본문 데이터 추가 금지):

| 위치 | 변경 형태 | 내용 |
|------|----------|------|
| 적절한 섹션 (예: 새 `## Cross-References` 절) | 1~2줄 추가 | `- 사용자 직관이 옳았던 사례 누적: .claude/agent-memory/orchestrator/lessons-learned.md` |

---

## 5. Phase 분할 및 우선순위

### 5.1 Phase 분할 기준

- **Phase 1 = 즉시 효과·낮은 부작용**: 동작 변경이 명시적이며, 적용 즉시 사용자 경험이 개선되고 회귀 위험이 낮은 항목.
- **Phase 2 = 효과 측정 후 적용**: 오발동·표현 장황화 등 부작용 모니터링이 필요한 항목, 또는 Phase 1 결과에 따라 임계값 조정이 필요한 항목.

### 5.2 Phase 1 (즉시 적용)

| 순서 | 작업 | 산출물 |
|------|------|--------|
| 1 | `.claude/rules/source-hierarchy.md` 신규 작성 | 신규 파일 1개 |
| 2 | `.claude/agent-memory/orchestrator/MEMORY.md` 신규 작성 + `lessons-learned.md` 신규 작성 (시드 4건) | 신규 파일 2개 |
| 3 | `.claude/agents/orchestrator.md` 변경: Verification Rules 1줄 + Self-Check on Pushback 절 + Memory Management 도메인 매칭 규칙 | 변경 파일 1개 |
| 4 | `.claude/agents/researcher.md` 변경: Constraints 1줄 + Self-Check on Pushback 절 | 변경 파일 1개 |
| 5 | `.claude/skills/deepresearch/SKILL.md` 변경: Source Hierarchy 참조 + 출처 Tier 라벨 | 변경 파일 1개 |
| 6 | `.claude/agent-memory/researcher/MEMORY.md` cross-link 1줄 추가 | 변경 파일 1개 |
| 7 | `/sync-docs` 실행으로 CLAUDE.md/harness.md/orchestrator.md 동기화 | 자동 산출물 |

Phase 1 결과:
- 사용자 반박 트리거는 **미적용** (Pushback Trigger 절 신설은 Phase 2)
- 적용 즉시 효과: (a) 사용자가 명시적으로 "조사해줘"라고 하지 않아도 `lessons-learned.md`에 기록된 도메인에서는 orchestrator가 사전 deepresearch 호출, (b) 응답에 Tier 라벨과 자신감 수준 명시, (c) Self-Check 5문항이 모든 응답 흐름에 결합.

### 5.3 Phase 2 (효과 측정 후 적용)

| 순서 | 작업 | 산출물 |
|------|------|--------|
| 1 | `.claude/rules/epistemic-honesty.md` 신규 작성 | 신규 파일 1개 |
| 2 | `.claude/agents/orchestrator.md` 변경: Pushback Trigger 절 신설 (Phase 1의 Self-Check를 트리거에 연결) | 변경 파일 1개 |
| 3 | `.claude/agents/researcher.md` 변경: epistemic-honesty 링크 추가 | 변경 파일 1개 |
| 4 | 키워드 리스트 1차 튜닝 (오발동 측정 후 임계 조정) | 변경 파일 1개 |
| 5 | `/sync-docs` 재실행 | 자동 산출물 |

Phase 2 결과:
- 사용자 반박 키워드 → deepresearch 자동 호출
- 모든 에이전트 출력에 일관된 단정 회피·자신감 라벨

### 5.4 Phase 분할 기준의 근거

- Phase 1은 **출력 형식 변화만**으로도 즉시 회귀 위험이 거의 0이다 (Tier 라벨/자신감 라벨은 추가일 뿐 기존 출력을 제거하지 않음).
- Phase 1의 `lessons-learned.md` 기반 사전 deepresearch는 도메인 매칭 시에만 발동하여 폭발적 비용 증가 없음.
- Phase 2의 키워드 트리거는 정밀도(precision) 측정이 필요한 항목 — "정말?"이 단순 확인 질문에도 발동하면 비용 폭증. Phase 1로 베이스라인 측정 후 Phase 2 적용이 안전.
- Epistemic Honesty의 본문 압축 규칙(NFR-3 대응)도 Phase 1의 실측 응답 길이 데이터를 보고 조정해야 하므로 Phase 2.

### 5.5 다섯 개선안의 우선순위 결정 (각 1문장)

1. **Source Hierarchy** — Phase 1 최우선. 신규 정본 파일로 분리하여 drift를 차단하고 즉시 세 곳에 1줄 링크로 적용한다.
2. **User Pushback Trigger** — Phase 2. 정밀도 측정·키워드 튜닝이 필요하므로 베이스라인 확보 후 적용한다.
3. **Epistemic Honesty** — Phase 2. 응답 길이 영향(NFR-3)을 측정한 후 본문 압축 규칙과 함께 도입한다.
4. **Self-Check on Pushback** — Phase 1 (Trigger 없이 도입). 5문항 자체는 안전한 점검 절차이므로 Phase 1에 단독 적용, Phase 2에서 Trigger와 연결한다.
5. **Lessons Learned 메모리** — Phase 1. 시드 4건이 즉시 효과(도메인 사전 deepresearch)를 만들고 회귀 위험 없음.

---

## 6. 검증 방법

### 6.1 적용 후 동작 관찰 항목

| 검증 항목 | 측정 방법 | 임계 |
|----------|---------|------|
| V1. 도메인 매칭 사전 deepresearch | `korean-housing-subscription` 도메인 키워드 포함 요청 시 첫 응답 전 deepresearch 호출 여부를 transcript 로그로 확인 | 100% 발동 |
| V2. Tier 라벨 표기 | researcher/deepresearch 산출물 docs/*.md 파일에 각 출처에 Tier 라벨 명시 여부 grep | 신규 산출물 100% 적용 |
| V3. 자신감 라벨 표기 | orchestrator/researcher 사실 진술에 `확실`/`추정`/`모름` 라벨 명시 여부 | 신규 응답 80% 이상 |
| V4. Self-Check 5문항 실행 | 사용자 반박 수신 후 응답 전 Self-Check 5문항 평가가 기록되는지 (shared-context 또는 transcript) | 사용자 반박 응답 100% |
| V5. 키워드 트리거 정밀도 (Phase 2) | "정말?"/"확실?" 등 키워드가 포함된 사용자 메시지 중 실제로 의심·검증 의도인 비율 | 70% 이상 (오발동 30% 이하) |
| V6. lessons-learned 누적 | 사용자 직관이 옳았던 신규 사례 발생 시 lessons-learned.md에 추가 기록 | 발생 사례 80% 이상 자동 기록 |

### 6.2 회귀 방지 채널

- **차후 사례 기록**: 동일 패턴(사용자 직관 우선) 재발 시 `lessons-learned.md`에 case_id 증가시키며 추가.
- **메타 모니터링**: 월 1회 `lessons-learned.md`의 case 수 증감을 확인. 감소 추세이면 시스템이 작동 중, 증가 추세이면 규칙 강화 필요.
- **Phase 2 키워드 튜닝**: 오발동 사례 발생 시 shared-context에 기록하여 키워드 리스트에서 제거/추가.

### 6.3 동작 테스트 시나리오

#### 6.3.1 시나리오 1: 사용자 반박 자동 트리거 (Phase 2 검증)

- 입력: 청약 도메인 질문 → 에이전트 답변 → 사용자 "정말?"
- 기대: Self-Check 5문항 평가 → No 1개 이상 → deepresearch 자동 호출 → 직전 답변 강등 + 정정.

#### 6.3.2 시나리오 2: 도메인 사전 deepresearch (Phase 1 검증)

- 입력: 청약 도메인 첫 질문 (반박 없음)
- 기대: Orchestrator가 `lessons-learned.md` 도메인 매칭 → 사용자 반박 없이 사전 deepresearch 호출 → Tier 1 자료 직접 인용.

#### 6.3.3 시나리오 3: 오발동 (Phase 2 검증)

- 입력: 에이전트가 "X를 진행할까요?" → 사용자 "정말 그렇게 해줘"
- 기대: 직전 출력이 질문 형식이고 사용자 응답이 동의이므로 트리거 안 됨 (휴리스틱 1 작동).

#### 6.3.4 시나리오 4: 1차 자료 도달 불가 (NFR-4 검증)

- 입력: 비공개 사내 문서가 1차 자료인 도메인 질문
- 기대: "Tier 1 도달 불가" 명시 + 최고 가용 등급으로 답변 + 자신감 라벨 `추정`.

---

## 7. 위험·부작용 분석 및 완화

| 위험 | 시나리오 | 완화책 |
|------|---------|--------|
| R1. 키워드 과민 발동 | "정말 좋네"같은 감탄·동의에도 deepresearch 호출되어 비용 증가 | (a) 휴리스틱 1: 직전 Orchestrator 출력이 질문이면 트리거 제외 (b) 키워드 단독 등장이 아니라 의심 맥락(직전 에이전트 단정 + 사용자 짧은 의문문)에서만 발동 (c) Phase 2 적용 후 오발동 사례 shared-context 기록 → 키워드 리스트 튜닝 |
| R2. 한국어/영어 키워드 누락 | 영어로 진행되는 대화에서 트리거 안 됨 | 정규식에 한·영 키워드 동시 포함. 표현 변형도 포함 (`정말?`, `정말이야`, `정말이지`, `really?`, `for real?`) |
| R3. Epistemic Honesty로 응답 장황화 | 라벨·출처 표기로 응답 길이 +50%+ 증가 | (a) `epistemic-honesty.md`에 압축 규칙 명시 (라벨 1회 + 출처 첫 등장만 전체) (b) Phase 1 측정 후 임계 초과 시 Phase 2에서 규칙 강화 (c) 짧은 1줄 응답에는 라벨 생략 허용 |
| R4. 1차 자료 도달 불가 도메인 | 사내 문서·유료 자료가 1차 자료인 경우 동작 정지 | `source-hierarchy.md`에 명시: Tier 1 도달 불가 시 "Tier 1 미확인" 명시 + 가용 최고 등급으로 fallback + 자신감 라벨 `추정` |
| R5. lessons-learned.md 무한 비대화 | 사례 누적으로 파일 크기 폭증 | (a) MEMORY.md는 200줄 제한 그대로 (인덱스만) (b) lessons-learned.md는 도메인별 분할 권고 (예: `lessons-learned-housing.md`, `lessons-learned-tax.md`) — Phase 1에서는 단일 파일로 시작, 사례 20건 도달 시 분할 |
| R6. Self-Check 5문항을 매 응답 수행으로 인한 응답 지연 | 사용자 반박이 아닌 일반 응답에서도 점검 부담 | Self-Check는 **사용자 반박 수신 시에만** 발동 (Phase 1에서도 전 응답 점검 아님). 일반 응답은 `### Factual Claim Verification`(기존) 규칙으로 충분 |
| R7. orchestrator.md 길이 폭증 (현재 510줄) | 신규 절 추가로 컨텍스트 부담 | 신규 절은 정본을 `.claude/rules/`에 두고 본문은 1줄 링크 + 핵심 절차 5~10줄만 유지. orchestrator.md는 +50줄 이내 목표 |
| R8. researcher.md의 자신감 라벨이 대화 출력 마크다운 금지 규칙과 충돌 | researcher 응답에 `**확실**` 등 마크다운 금지 | researcher.md 대화 출력은 자연 문장(`1차 자료 확인됨`)으로, `.md` 산출물은 라벨 표기. 두 출력 채널 분리 |
| R9. subagent-hallucination.md와 lessons-learned.md 경계 모호 | 어느 파일에 기록할지 판단 어려움 | (a) 환각(없는 사실 만듦) = subagent-hallucination.md (b) 단정적 추측(있는 사실 무시) = lessons-learned.md. orchestrator.md Memory Management 절에 분류 기준 1문장 명시 |
| R10. CLAUDE.md/harness.md sync drift | 신규 파일·규칙이 상위 문서에 반영 안 됨 | Phase 1·2 각 끝에 `Skill("sync-docs")` 자동 호출 (orchestrator의 기존 규칙 P-8) |

---

## 8. Task Breakdown

### 8.1 Phase 1 Tasks

| Task ID | 작업 | 파일 | 복잡도 | 의존 |
|---------|------|------|--------|------|
| T1-1 | source-hierarchy.md 신규 작성 (Tier 4단계 + 도메인 리스트 + fallback 규칙) | `.claude/rules/source-hierarchy.md` (신규) | S | — |
| T1-2 | orchestrator MEMORY.md 신규 작성 (인덱스 구조) | `.claude/agent-memory/orchestrator/MEMORY.md` (신규) | S | — |
| T1-3 | lessons-learned.md 신규 작성 (스키마 + 시드 4건) | `.claude/agent-memory/orchestrator/lessons-learned.md` (신규) | M | — |
| T1-4 | orchestrator.md 변경 (Verification 1줄 링크 + Self-Check on Pushback 절 + Memory Management 도메인 매칭 규칙) | `.claude/agents/orchestrator.md` (변경) | M | T1-1, T1-3 |
| T1-5 | researcher.md 변경 (Constraints 1줄 + Self-Check 5문항 절) | `.claude/agents/researcher.md` (변경) | S | T1-1 |
| T1-6 | deepresearch SKILL.md 변경 (Source Hierarchy 참조 + 출처 Tier 라벨) | `.claude/skills/deepresearch/SKILL.md` (변경) | S | T1-1 |
| T1-7 | researcher MEMORY.md cross-link 1줄 추가 | `.claude/agent-memory/researcher/MEMORY.md` (변경) | S | T1-3 |
| T1-8 | `/sync-docs` 실행 (CLAUDE.md / harness.md / orchestrator.md 인덱스 동기화) | 자동 | S | T1-1~T1-7 |

총 Phase 1: 8개 태스크 (S 6 + M 2)

### 8.2 Phase 2 Tasks

| Task ID | 작업 | 파일 | 복잡도 | 의존 |
|---------|------|------|--------|------|
| T2-1 | epistemic-honesty.md 신규 작성 (표현 규칙 + 자신감 라벨 + 압축 가이드) | `.claude/rules/epistemic-honesty.md` (신규) | M | Phase 1 측정 |
| T2-2 | orchestrator.md 변경 (Pushback Trigger 절 신설 — 키워드 매칭 + Self-Check 연결) | `.claude/agents/orchestrator.md` (변경) | M | T2-1 |
| T2-3 | researcher.md 변경 (epistemic-honesty 링크 + Output Standards에 자신감 라벨 의무) | `.claude/agents/researcher.md` (변경) | S | T2-1 |
| T2-4 | 키워드 리스트 1차 튜닝 (오발동 측정 결과 반영) | `.claude/agents/orchestrator.md` (변경) | S | T2-2 운영 데이터 |
| T2-5 | `/sync-docs` 재실행 | 자동 | S | T2-1~T2-4 |

총 Phase 2: 5개 태스크 (S 3 + M 2)

### 8.3 후속 검증 Tasks (Phase 1·2 종료 후)

| Task ID | 작업 | 복잡도 |
|---------|------|--------|
| TV-1 | V1~V4 측정 (Phase 1 완료 직후) | M |
| TV-2 | V5 측정 (Phase 2 완료 후 1~2주 모니터링) | M |
| TV-3 | lessons-learned.md 도메인별 분할 판정 (사례 20건 도달 시) | S |

---

## 9. 핵심 결정 사항 요약

본 블루프린트의 3대 결정:

1. **정본 1곳 + 참조 다곳 원칙**: Source Hierarchy와 Epistemic Honesty는 `.claude/rules/`에 정본을 두고 orchestrator/researcher/deepresearch에서 1줄 링크로 참조한다. Self-Check만 예외로 orchestrator에 본문, researcher에 복제 (5문항이 변하지 않을 것이므로 drift 위험 낮음).

2. **시드 데이터는 orchestrator 메모리에 저장**: `lessons-learned.md`는 `.claude/agent-memory/orchestrator/`에 둔다. 트리거 평가·deepresearch 호출 주체가 Orchestrator이고 researcher MEMORY.md는 이미 16KB로 포화 상태. `subagent-hallucination.md`와는 메커니즘이 다르므로(환각 vs 단정적 추측) 통합하지 않고 cross-link만 둔다.

3. **Phase 분할 기준 = 부작용 측정 필요성**: 출력 형식 변화만 있는 항목(Tier 라벨, 시드 메모리, Self-Check 5문항)은 Phase 1에 즉시 적용. 정밀도 측정·임계 튜닝이 필요한 항목(키워드 트리거, 압축 규칙)은 Phase 2로 분리하여 베이스라인 확보 후 도입.

---

## 10. 산출물 위치

- 본 블루프린트: `/Users/hoodcat/Projects/hoodcat-harness/docs/blueprint-agent-disagreement-handling-improvement-20260516.md`

Phase 1 산출물 (적용 시점에 생성):
- `.claude/rules/source-hierarchy.md` (신규)
- `.claude/agent-memory/orchestrator/MEMORY.md` (신규)
- `.claude/agent-memory/orchestrator/lessons-learned.md` (신규)
- `.claude/agents/orchestrator.md` (변경)
- `.claude/agents/researcher.md` (변경)
- `.claude/skills/deepresearch/SKILL.md` (변경)
- `.claude/agent-memory/researcher/MEMORY.md` (변경 — 1줄 cross-link)

Phase 2 산출물 (적용 시점에 생성):
- `.claude/rules/epistemic-honesty.md` (신규)
- `.claude/agents/orchestrator.md` (재변경 — Pushback Trigger 절 추가)
- `.claude/agents/researcher.md` (재변경 — epistemic-honesty 링크)

---

## 11. 후속 작업

- [ ] 사용자 검토 및 Phase 1 적용 승인
- [ ] Phase 1 PR 작성 (`Task(orchestrator, "본 블루프린트의 Phase 1을 적용해줘")`)
- [ ] Phase 1 적용 후 1~2주 모니터링 (V1~V4)
- [ ] Phase 2 적용 승인 (Phase 1 베이스라인 측정 후)
- [ ] Phase 2 PR 작성
- [ ] Phase 2 적용 후 1~2주 모니터링 (V5)
- [ ] lessons-learned.md 시드 4건 외 추가 사례 누적 기록 채널 운영
