# 분야별 전문 에이전트 도입 타당성 조사 결과

> 조사일: 2026-10-03
> 대상: `/home/hoodcat/Projects/whisper` (transcribe.py + ytscribe/) 문서 생성·분석 단계
> 질문: "분야별로 에이전트가 있는 게 좋을 것 같아. 어때?"

## 개요

분야마다 **봐야 할 것이 다르다**는 직감은 맞다. 다만 이것을 "분야별 에이전트"(페르소나, 멀티에이전트, 서브에이전트)로 구현하는 것과, "분야별 체크리스트를 프롬프트에 끼워 넣는 것"은 다르다. 공개된 근거를 보면 품질 차이는 **페르소나가 아니라 분야별 지침의 내용과 외부 근거(도구)** 에서 나온다. 페르소나만 바꾸는 것은 사실 정확도에 효과가 없거나 오히려 약간 해롭다는 연구가 있다. 멀티에이전트·토론 구조는 토큰을 크게 늘리지만, 이 파이프라인처럼 문맥을 공유하는 직렬 작업에는 이득이 확인되지 않았다.

**결론 요약**
- **타당한가**: 분야별로 다르게 처리하는 방향은 타당하다. 하지만 "분야마다 에이전트를 따로 둔다"는 형태는 지금 단계에서 과하다.
- **어떤 형태로**: (a) 이미 있는 분류기(haiku)를 라우터로 쓰고, `ANALYSIS_PROMPT` = 공통 골격 + `DOMAIN_GUIDES[domain]` 주입. 분석 대상 분야를 정치·경제에서 사회·과학/건강·기술로 넓힌다. 그다음에 (c) 웹검색 팩트체크를 **옵트인 단계로 별도 분리**한다.
- **우선순위**: ① 분야별 지침 모듈 + 평가 세트 → ② 분류 개선(주·부 분야, health 추가) → ③ 옵트인 팩트체크(`--verify`) → (보류) 다관점 토론, Claude Code 서브에이전트.

---

## 1. 근거: 분야별 에이전트 vs 범용 프롬프트 + 분야 지침

| 근거 | 내용 | 시사점 |
|---|---|---|
| (Tier 1) Anthropic, *Building effective agents* | "find the simplest solution possible, and only increasing complexity when needed"<br>"Routing classifies an input and directs it to a specialized followup task… building more specialized prompts"<br>"consider adding complexity *only* when it demonstrably improves outcomes" | 지금 구조(분류 → 형식별 프롬프트)가 이미 **Routing 패턴**이다. 분야별 처리는 라우팅 대상에 "분야별 지침"을 하나 더하는 것으로 충분하다. |
| (Tier 1) Anthropic, *How we built our multi-agent research system* | 멀티에이전트는 채팅 대비 약 15배 토큰. 연구형(병렬 탐색) 작업에서 단일 에이전트보다 90.2% 우수. 반면 "domains that require all agents to share the same context or involve many dependencies between agents are not a good fit". 평가는 "about 20 queries", LLM judge는 "single LLM call… scores 0.0–1.0 and a pass-fail grade"가 가장 일관적. | 영상 분석은 같은 전사문이라는 **하나의 문맥을 공유하는 작업**이다. 병렬로 탐색할 하위 과제가 거의 없다. 멀티에이전트가 효과를 내는 곳은 팩트체크처럼 **독립 주장 여러 개를 웹에서 확인하는 단계**뿐이다. |
| (Tier 1) Zheng et al., *When "A Helpful Assistant" Is Not Really Helpful*, EMNLP Findings 2024 ([arXiv 2311.10054](https://arxiv.org/abs/2311.10054)) | 162개 역할, 4개 모델 계열, 2,410개 사실 질문. 시스템 프롬프트에 페르소나를 넣어도 성능이 오르지 않았다("no or small negative effects"). 효과는 "largely random"이었다. | "당신은 경제 전문가입니다" 같은 **페르소나 문장만으로는 품질을 기대할 수 없다**. |
| (Tier 1) Anthropic 프롬프트 가이드 *Prompting best practices* ("Give Claude a role") | "Setting a role in the system prompt focuses Claude's behavior and tone for your use case." | 역할 설정이 바꾸는 것은 **초점과 어조**다. 사실 정확도가 아니다. 위 연구와 합치면, 역할 문장은 비용이 거의 없으니 한 줄 넣되 실제 품질은 체크리스트 내용에 기대야 한다. |
| (Tier 1) *Stop Overvaluing Multi-Agent Debate* ([arXiv 2502.08788](https://arxiv.org/abs/2502.08788)) | "MAD often fail to outperform simple single-agent baselines such as Chain-of-Thought and Self-Consistency, even when consuming significantly more inference-time computation." | (d) 다관점 토론은 비용 대비 근거가 약하다. |
| (Tier 1) Anthropic 가이드, Subagent orchestration | 최신 모델은 서브에이전트를 과도하게 쓰는 경향이 있다("may spawn them in situations where a simpler, direct approach would suffice"). | 도구를 열어 두면 비용이 예측 불가능해진다. 파이프라인은 Python이 순서를 정하는 지금 방식이 낫다. |

**판단** (추정, 근거 수준 Tier 1 연구 + 본 프로젝트 맥락 추론): 품질에 영향을 주는 요소는 ① 분야별로 무엇을 점검할지 정한 체크리스트, ② 출력 구조, ③ 외부 근거(웹·통계), 이 세 가지다. 에이전트를 분리하는 것 자체는 품질 요소가 아니다. 분리는 ③의 도구 권한을 단계별로 나눌 때만 의미가 있다.

---

## 2. 구현 형태 비교

| 옵션 | 내용 | 추가 비용·지연 | 환각 위험 | 유지보수 | 판정 |
|---|---|---|---|---|---|
| **(a) 분야별 프롬프트 모듈** | `classify` 결과로 `DOMAIN_GUIDES[domain]`를 `ANALYSIS_PROMPT`에 주입. 분석 대상 분야 확대. | **추가 호출 없음** (지금 분석 호출 1회 그대로, 프롬프트만 수백 토큰 늘어남) | 지금과 같음. 체크리스트가 "출처 없는 수치", "인과·상관 구분"을 명시해 오히려 줄어들 수 있음(추정) | 낮음. 사전(dict) 하나, 테스트 쉬움 | **1순위** |
| (b) Claude Code 서브에이전트 (`.claude/agents/*.md`, 스킬이 호출) | youtube-digest 스킬이 분야별 서브에이전트에 분석을 맡김 | 대화 세션 컨텍스트에 의존. 모델·토큰을 통제하기 어려움 | 세션의 넓은 권한·훅이 섞일 수 있음. 지금 `run_claude`가 `--setting-sources ""`로 일부러 막아 둔 부분 | 파이프라인(Python)과 스킬 두 곳에 로직이 흩어짐. CLI 단독 실행으로 재현할 수 없음 | **비권장** |
| **(c) 웹검색 팩트체크 에이전트** | 분석 후 '확인 필요' 항목을 구조화된 주장 목록으로 뽑아, `WebSearch`/`WebFetch`를 허용한 별도 호출로 검증 | 검색 $10/1,000회(API 기준, 회당 약 $0.01) + **가져온 페이지 토큰**(이쪽이 더 큼). 지연 수 분 | 근거 없는 답이 줄어듦. 대신 **프롬프트 인젝션 공격면이 생김**(4절) | 중간. 권한·예산·출처 검증 코드 필요 | **3순위, 옵트인** |
| (d) 다관점 토론 (정치: 진영별 에이전트 + 종합) | 관점마다 1회 호출, 종합 1회 | 분석 비용 N+1배 | 토론이 정확도를 꾸준히 높인다는 근거 약함. 다수 압력으로 의견이 한쪽으로 쏠리는 현상 보고 | 높음 | **보류**. (a) 안에서 "입장별 가장 강한 논거를 같은 분량으로" 지시로 대체 |

참고: 지금 `run_claude`는 도구를 하나도 주지 않는다(`--tools ""`). 따라서 Agent 도구(서브에이전트)도 쓰지 않는다. (b)를 하려면 도구를 열어야 하므로 지금의 격리 설계와 충돌한다.

---

## 3. 분야별로 실제로 달라져야 하는 것 (체크리스트)

공통 골격(쟁점·이해관계자 / 비판적 검토 / 전망 / 확인 필요)은 유지한다. 분야마다 **"비판적 검토"와 "확인 필요"의 점검 항목**, 그리고 **전망 섹션을 둘지 말지**만 바꾼다.

### 정치 (politics)
- 발언 인용: 영상이 원문을 보여 줬는지, 요약·편집 인용인지 구분한다. 발언 일시·자리(국회 회의, 기자회견, SNS)를 적는다.
- 법안·정책 단계: 발의 / 상임위 / 본회의 / 공포 / 시행 중 어디인지. 단계가 다르면 "결정됐다"는 표현은 과장이다.
- 균형: 주요 입장마다 **가장 강한 논거**를 같은 분량으로 쓴다. 한쪽 입장만 나왔으면 "반대 측 입장 미제시"라고 적는다.
- 여론조사: 조사기관·표본·오차범위·조사기간이 제시됐는지 본다.
- 금지: 인신공격, 특정 진영 지지.

### 경제 (economy)
- 수치: 기준 시점, 단위, 명목·실질, 전년 대비(YoY)·전월 대비(MoM)·연율 중 무엇인지, 계절조정 여부. 서로 다른 기준을 섞어 비교했는지(현행 테스트에서 이미 잡아낸 "비교기준 혼용").
- 인과와 상관: "A 때문에 B" 주장에 메커니즘과 반례가 있는지 본다.
- 외삽: 최근 추세를 그대로 연장했는지(이미 잡아낸 "단순 외삽").
- 이해관계: 화자가 상품 판매, 포지션 보유, 광고 중인지.
- 금지: 매수·매도 권유처럼 쓰지 않는다. 전망은 조건부 시나리오로만 쓴다.

### 사회 (society)
- 일화와 통계: 개별 사례를 일반화했는지 본다.
- 통계 출처: 정부 통계, 설문, 단체 자체 조사 중 무엇인지.
- 당사자 관점이 빠졌는지 본다.

### 과학 (science) / 건강·의료 (health, 신설 권장)
- 근거 수준: 메타분석·RCT, 관찰연구, 동물·세포 실험, 전문가 의견, 일화 중 어디인지 표시한다.
- 연구 설계: 표본 크기, 대조군 유무, 상대위험과 절대위험, 동료 심사 전 논문(프리프린트)인지.
- "연구에 따르면"만 있고 논문이 특정되지 않으면 "출처 미특정"으로 적는다.
- 학계 합의와 소수설을 구분한다.
- **의료 금지 규칙**: 복용량, 치료 선택, 진단을 권하지 않는다. "의료 결정은 전문가와 상의"를 고정 문구로 넣는다.
- 전망 섹션은 빼거나 "후속 연구에서 확인할 점"으로 바꾼다.

### 기술 (tech)
- 버전·날짜: 제품·라이브러리 버전, 영상 시점. 기술은 바뀌는 속도가 빨라 "업로드 이후 바뀌었을 수 있음"이 특히 중요하다.
- 벤치마크 조건: 하드웨어, 설정, 비교 대상이 공정한지, 제조사 자료인지.
- 협찬·제휴 링크 여부(설명란 확인).
- 전망 섹션은 "로드맵·출시 일정 신호"로 줄인다.

### 교육 (education) — 분석 섹션 대신 학습 보강
- 의견 분석은 맞지 않는다. 대신 `notes` 형식에서 다음을 점검한다: 정의가 정확한지, 흔한 오개념, 전제 지식, 영상에서 틀리게 설명한 부분(전사 근거가 있을 때만).

### 문화·라이프스타일 (culture/lifestyle/other)
- 분석 섹션 생략(지금과 같음). 리뷰라면 협찬 여부만 점검한다.

---

## 4. claude CLI(-p)에서 도구·서브에이전트 사용과 권한 제한 (공식 문서 기준)

(Tier 1) Claude Code CLI reference, Permissions, Tools reference, Security 문서, 2026-10-03 확인.

| 항목 | 공식 문서 내용 | 이 프로젝트 적용 |
|---|---|---|
| 도구 집합 제한 | `--tools`: "Restrict which built-in tools Claude can use. Use `\"\"` to disable all… or tool names". MCP 도구에는 적용되지 않음 → `--disallowedTools "mcp__*"` | 팩트체크 호출만 `--tools "WebSearch,WebFetch"` |
| 무프롬프트 거부 | `dontAsk`: "Auto-denies every call that would otherwise prompt… tools pre-approved via… allow rules… still run" | 지금 방식 그대로. allow에 없는 호출은 자동 거부 |
| WebFetch 도메인 제한 | `WebFetch(domain:example.com)`, `WebFetch(domain:*.example.com)` 지원. deny가 allow보다 우선 | **도메인 allowlist 가능** (예: `*.go.kr`, `ecos.bok.or.kr`, `kosis.kr`, `pubmed.ncbi.nlm.nih.gov`, `doi.org`, 주요 통신사) |
| WebSearch 제한 | "WebSearch permission rules take no specifier. A bare `WebSearch` entry… is the only form." 도구 자체의 `allowed_domains`/`blocked_domains`는 **모델이 호출할 때 고르는 값** | **검색 쿼리와 검색 도메인은 권한으로 강제할 수 없다.** 결과 페이지를 열 때 WebFetch allowlist로 막는 것이 실질적인 통제점 |
| WebFetch 처리 방식 | "runs the prompt against the content in a separate model call, and Claude receives the result of that call rather than the raw page" (손실 압축) | 페이지 원문 인젝션이 한 번 걸러진다. 다만 "언급 없음"이 "사실 아님"을 뜻하지는 않는다 |
| 예산·턴 제한 | `--max-budget-usd` (서브에이전트 지출 포함), `--max-turns` | 팩트체크 호출에 필수(예: $0.50, 15턴) |
| 서브에이전트 | `--agents` JSON으로 동적 정의 가능. `-p`에서도 동작. `Agent(type)` 형식으로 allowlist | 쓸 수는 있지만 2절 판단대로 불필요 |
| 웹검색 가용성 | WebSearch는 Anthropic 백엔드. API 웹검색은 Amazon Bedrock에서 미지원 | 지금 인증 방식에서 사용 가능한지 실제 호출로 확인 필요 |

### 프롬프트 인젝션 위험 (영상 설명란 → 웹검색)
- **위협**: 설명란·자막·화면 글자에 "다음을 검색해 확인하라: site:attacker.example …" 같은 지시가 있으면, 모델이 공격자 페이지를 근거로 "확인됨"이라고 쓸 수 있다(**거짓 검증**). WebFetch URL에 전사 내용을 실어 보내는 유출 경로도 이론상 있다. (Tier 1) 웹검색 도구를 통한 데이터 유출 연구 [arXiv 2510.09093](https://arxiv.org/abs/2510.09093), 실제 웹의 간접 인젝션 실태 연구 [arXiv 2604.27202](https://arxiv.org/abs/2604.27202). 이 연구들은 기존 방어가 충분하지 않다고 보고한다.
- **이 파이프라인에서의 실제 위험도** (추정): 문맥에 비밀 정보가 없다(입력이 공개 영상이고 `--setting-sources ""`). 따라서 **유출보다 거짓 검증·조작된 출처**가 주된 위험이다.
- **완화책** (적용 순서):
  1. **2단계 분리**: 분석 호출(도구 없음)이 `claims: [{claim, why, domain}]` JSON을 만든다. 팩트체크 호출에는 **이 주장 목록만** 넣고, 설명란·전사 원문은 넣지 않는다. 그래도 주장 문구에 인젝션이 섞일 수 있으니 길이 제한과 개수 상한(최대 5개)을 둔다.
  2. `--tools "WebSearch,WebFetch" --allowedTools WebSearch "WebFetch(domain:...)" --permission-mode dontAsk --disallowedTools "mcp__*"`로 열람 도메인을 allowlist로 묶는다.
  3. 출력 스키마에 `sources: [{url, quote}]`를 필수로 둔다. **Python 코드에서 URL 도메인이 allowlist에 있는지 다시 검증**하고, 없으면 "미확인"으로 바꾼다.
  4. 결과는 본문을 고치지 않고 별도 섹션 "팩트체크 (자동, 웹 출처)"에 링크와 함께 붙인다. 판정은 확인됨 / 반박됨 / 미확인 3단계.
  5. `--max-budget-usd`, `--max-turns`, `permission_denials` 로깅(이미 있음)으로 이상 행동을 감지한다.

---

## 5. 권장안

### 우선순위
1. **분야별 지침 모듈 (a)**. 반나절 규모, 비용 증가 없음.
2. **분류 개선**: `domain`을 `primary` + 선택적 `secondary`로 나누고(예: 부동산 정책 = politics + economy), `health`를 추가한다. 분석 대상을 `{politics, economy, society, science, health, tech}`로 넓힌다. education은 notes 보강으로 따로 처리한다.
3. **평가 세트 구축**과 A/B 비교(아래). 2번 효과를 확인한 뒤 다음으로 넘어간다.
4. **옵트인 팩트체크 (c)**: `--verify` 플래그로 켠다. 기본값은 끈다. 분야별 allowlist 도메인을 둔다.
5. 보류: (d) 다관점 토론, (b) 서브에이전트. 1~4의 평가에서 "균형 부족"이 반복될 때만 (d)를 실험한다.

### 코드 스케치 (ytscribe/llm.py)

```python
# 분야별 점검 항목. 페르소나보다 "무엇을 확인할지"가 품질을 결정한다.
DOMAIN_GUIDES = {
    "politics": """\
- 인용 발언은 원문 제시 여부·일시·자리를 구분한다. 편집된 인용이면 표시한다.
- 법안·정책은 발의/상임위/본회의/공포/시행 중 현재 단계를 밝히고, 단계를 넘어선 단정은 지적한다.
- 주요 입장마다 가장 강한 논거를 같은 분량으로 쓴다. 빠진 입장은 '미제시'로 적는다.
- 여론조사는 기관·표본·오차범위·기간 제시 여부를 본다.""",
    "economy": """\
- 수치마다 기준 시점·단위·명목/실질·YoY/MoM·계절조정을 확인하고, 다른 기준끼리 비교했으면 지적한다.
- 인과 주장은 메커니즘과 반례가 있는지 보고, 상관을 인과로 말하면 지적한다.
- 최근 추세의 단순 외삽, 화자의 이해관계(판매·보유·광고)를 점검한다.""",
    "science": """\
- 근거 수준(메타분석·RCT/관찰/동물·세포/의견/일화)과 표본·대조군·동료 심사 여부를 표시한다.
- 출처 논문이 특정되지 않으면 '출처 미특정'으로 적는다. 학계 합의와 소수설을 구분한다.""",
    "health": """\
- science 항목을 모두 적용하고, 상대위험과 절대위험을 구분한다.
- 복용량·치료 선택·진단을 권하지 않는다. 마지막에 '의료 결정은 전문가와 상의하세요'를 쓴다.""",
    # society, tech ...
}
# 분야별로 전망 섹션을 바꾼다 (health/science는 '후속 연구에서 확인할 점').

def analysis_prompt(domains: list[str]) -> str:
    guides = "\n".join(DOMAIN_GUIDES[d] for d in domains if d in DOMAIN_GUIDES)
    return ANALYSIS_PROMPT + "\n\n분야별 점검 항목:\n" + guides
```

캐시 키(`load_or`)에 프롬프트 문자열이 들어가므로, 지침을 바꾸면 분석만 자동으로 다시 생성된다.

### 팩트체크 호출 스케치 (옵트인)

```python
# 도구는 웹 두 개만, 열람 도메인은 allowlist, 예산 상한. run_claude에 tools/allowed/budget 인자를 추가하는 형태.
cmd += ["--tools", "WebSearch,WebFetch",
        "--allowedTools", "WebSearch", *[f"WebFetch(domain:{d})" for d in VERIFY_DOMAINS[domain]],
        "--disallowedTools", "mcp__*",
        "--max-turns", "15", "--max-budget-usd", "0.5"]
# 결과 sources[].url 도메인을 Python에서 다시 allowlist 검증 → 실패 시 verdict='미확인'
```

### 평가 방법
- **세트**: 분야별 3~4개씩, 약 20개 영상(Anthropic이 권장한 "about 20 queries" 규모). 정치(보도, 대담), 경제(해설, 지표 발표), 사회, 과학, 건강, 기술(리뷰, 벤치마크), 교육. 분야가 섞인 영상 2~3개, 인젝션 문구를 심은 설명란 테스트 1개를 포함한다.
- **비교**: A = 지금 프롬프트, B = 분야 지침 주입. 같은 전사문·문서를 입력으로 분석 단계만 다시 실행한다(캐시를 쓰니 저렴하다).
- **루브릭** (LLM judge 1회 호출, 항목별 0~1 점수와 pass/fail, 사람이 표본 확인):
  1. 근거 없는 사실 단정(전사·일반지식 표시 없이 새 사실) — 0건이어야 pass
  2. 분야 체크리스트 커버리지(해당 항목 중 몇 개를 실제로 점검했나)
  3. 균형(정치: 입장별 분량·논거 강도)
  4. '확인 필요' 항목의 구체성(검색 가능한 주장인가)
  5. 금지 규칙 위반(투자·의료 조언)
  6. 비용·지연(`total_cost_usd`, 소요 시간)
- **채택 기준** (제안): B가 2·4번에서 개선되고 1·5번이 나빠지지 않으면 채택. 팩트체크는 "확인됨" 판정의 출처를 사람이 검사해 정확도 90% 이상일 때 기본값 전환을 검토한다.

---

## 주요 포인트
- 품질은 페르소나가 아니라 **분야별 점검 항목과 외부 근거**에서 나온다. 페르소나 효과는 연구상 0에 가깝거나 무작위다.
- 지금 파이프라인은 이미 Anthropic이 말하는 **Routing** 구조다. 분야별 지침을 라우팅 대상에 추가하는 것이 가장 싸고 효과적인 첫 단계다.
- 멀티에이전트·토론은 문맥을 공유하는 이 작업에 맞지 않는다. 독립 주장을 웹으로 확인하는 **팩트체크 단계에서만** 도구 분리가 의미 있다.
- 팩트체크를 열면 인젝션 공격면이 생긴다. **WebSearch는 권한으로 쿼리·도메인을 막을 수 없다.** WebFetch 도메인 allowlist, 입력 분리, 코드 단의 출처 재검증으로 방어한다.
- 개선 효과는 약 20개 영상 A/B와 루브릭으로 검증한 뒤 다음 단계로 간다.

## 출처
- (Tier 1) [Anthropic — Building effective agents](https://www.anthropic.com/engineering/building-effective-agents) — 확인 2026-10-03
- (Tier 1) [Anthropic — How we built our multi-agent research system](https://www.anthropic.com/engineering/built-multi-agent-research-system) — 확인 2026-10-03
- (Tier 1) [Zheng et al., When "A Helpful Assistant" Is Not Really Helpful (EMNLP Findings 2024)](https://aclanthology.org/2024.findings-emnlp.888/) / [arXiv 2311.10054](https://arxiv.org/abs/2311.10054)
- (Tier 1) [Stop Overvaluing Multi-Agent Debate (arXiv 2502.08788)](https://arxiv.org/abs/2502.08788)
- (Tier 1) [Claude prompting best practices — Give Claude a role / Subagent orchestration](https://platform.claude.com/docs/en/build-with-claude/prompt-engineering/claude-prompting-best-practices) — 확인 2026-10-03
- (Tier 1) [Claude Code CLI reference](https://code.claude.com/docs/en/cli-reference) — `--tools`, `--allowedTools`, `--disallowedTools`, `--agents`, `--max-budget-usd`, `--max-turns`
- (Tier 1) [Claude Code Permissions](https://code.claude.com/docs/en/permissions) — `WebFetch(domain:…)`, `dontAsk`, deny 우선
- (Tier 1) [Claude Code Tools reference](https://code.claude.com/docs/en/tools-reference) — WebSearch/WebFetch 동작, WebSearch 규칙에 지정자 없음
- (Tier 1) [Claude Code Security](https://code.claude.com/docs/en/security) — 프롬프트 인젝션 방어, WebFetch 요약 처리
- (Tier 1) [Claude API Web search tool](https://platform.claude.com/docs/en/agents-and-tools/tool-use/web-search-tool) — $10/1,000 searches, `max_uses`, 도메인 필터
- (Tier 1) [Exploiting Web Search Tools of AI Agents for Data Exfiltration (arXiv 2510.09093)](https://arxiv.org/abs/2510.09093)
- (Tier 1) [Indirect Prompt Injection in the Wild (arXiv 2604.27202)](https://arxiv.org/abs/2604.27202)
- 프로젝트 코드: `ytscribe/llm.py` (`run_claude`, `CLASSIFY_SCHEMA`, `ANALYSIS_PROMPT`), `transcribe.py` (`want_analysis`, `step_analysis`)

자신감: 공식 문서 기반의 CLI 권한·도구 동작은 **확실**. 분야별 지침이 이 파이프라인에서 낼 품질 개선 폭은 **추정**(평가 세트로 검증 필요). 지금 인증 방식에서 WebSearch를 쓸 수 있는지는 **모름**(실제 호출로 확인 필요).
