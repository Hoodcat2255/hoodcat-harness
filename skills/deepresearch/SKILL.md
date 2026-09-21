---
name: deepresearch
description: |
  Performs thorough deep research on any topic using web search, Context7 docs, and GitHub CLI.
  Domain-adaptive: for Korean regulated domains (법령·청약·세무·의료·금융) it reaches Tier 1
  primary sources (official .go.kr sites, 공고문, 법령 원문) first; supports a focused
  re-verification mode for disputed claims (pushback). Saves structured results to docs/.
  Use when the user asks to research, investigate, or gather comprehensive information.
  Triggers on: "조사해줘", "찾아줘", "알아봐", "리서치", "deepresearch", "dr:" (a prefix at
  the very start of the prompt; the rest is the topic), or any request
  for in-depth information gathering about a technology, concept, regulation, or trend.
argument-hint: "[주제] (또는 '재검증: <의심받은 주장>')"
user-invocable: true
context: fork
---

# Deep Research

**현재 연도: !`date +%Y`** · **오늘: !`date +%Y-%m-%d`**

## 프로세스

### 0. 모드 & 도메인 판정

먼저 모드와 도메인을 판정한다.

모드:
- **일반 조사**: 주제 전반을 폭넓게 조사 (기본)
- **재검증 (pushback)**: $ARGUMENTS가 특정 주장의 재확인을 요구하거나("재검증:", "직전 답변 X 확인", "근거 확인"), 호출자가 사용자 반박("정말?", "확실해?", "근거는?") 맥락으로 넘긴 경우 → step 4의 정조준 경로를 따른다.

도메인:
- **한국 규제 도메인**: 법률·청약·세무·의료·금융 등 `~/.claude/rules/hoodcat/source-hierarchy.md`의 1차 자료 도달 강제 도메인 → 1-A
- **소프트웨어/기술**: 라이브러리·프레임워크·API·언어 → 1-B
- **일반**: 그 외 → 1-C

판정이 모호하면 규제 도메인 가능성을 우선 고려한다(Tier 1 미달 시 단정 금지 원칙).

### 1. 도메인 적응형 병렬 정보 수집

**단일 메시지에서 5-7개 검색을 병렬 실행**한다. 도메인에 따라 쿼리 구성을 달리한다.

> 자료 등급 우선순위는 `~/.claude/rules/hoodcat/source-hierarchy.md`를 따른다. Tier 1 후보(법령 원문, 공식 공고문, 공식 API 응답, 1차 출판물)를 먼저 식별한다.

#### 1-A. 한국 규제 도메인 (Tier 1 우선, 한국어)

공식 1차 자료 직접 도달을 최우선으로 한다. gh/Context7는 쓰지 않는다.

```
동시 실행:
├── WebSearch: "<주제> site:go.kr"            (공식 .go.kr 우선)
├── WebSearch: "<주제> 공고문 OR 고시 OR 시행령 !`date +%Y`"
├── WebSearch: "<주제> 개정 OR 시행일 OR 시행 !`date +%Y`"
├── WebSearch: "<주제> 자격 OR 기준 OR 요건"   (도메인 맞춤 한국어)
└── WebFetch: 위 검색으로 resolve한 공식 사이트 직접 조회
      법률      → 국가법령정보센터(law.go.kr) 해당 법령·조항
      청약·주거 → 청약홈, 마이홈포털, 국토교통부 공고
      세무      → 국세청 홈택스·세법, 기획재정부
      의료·약품 → 식약처 의약품안전나라
      금융 규제 → 금융감독원 전자공시, 한국은행
```

정확한 현행 공식 URL은 첫 WebSearch로 resolve한 뒤 WebFetch한다(URL 하드코딩 단정 금지).

#### 1-B. 소프트웨어/기술

```
동시 실행:
├── WebSearch: "$ARGUMENTS comprehensive guide !`date +%Y`"
├── WebSearch: "$ARGUMENTS best practices patterns"
├── WebSearch: "$ARGUMENTS vs alternatives comparison"
├── WebSearch: "$ARGUMENTS common mistakes pitfalls"
├── Bash: gh search repos "$ARGUMENTS" --sort stars --limit 5
├── Bash: gh search issues "$ARGUMENTS" --sort updated --limit 5
├── Context7: resolve-library-id
└── Context7: query-docs (ID 확보 후, 최대 3회)
```

#### 1-C. 일반

```
동시 실행:
├── WebSearch: "<주제> 정리 OR 설명 !`date +%Y`"   (한국어)
├── WebSearch: "$ARGUMENTS overview !`date +%Y`"   (영어)
├── WebSearch: "<주제> 비교 OR 장단점"
├── WebSearch: "$ARGUMENTS limitations OR pitfalls"
└── WebSearch: "<주제> 최신 동향 !`date +%Y`"
```

gh/Context7는 기술 하위주제가 명확할 때만 추가한다.

### 2. 심화 조사

1차 결과의 핵심 출처를 WebFetch로 상세 조회한다.

- 규제 도메인: 공식 사이트·법령 원문·공고문 PDF를 직접 정독한다. Tier 1 자료가 확보되지 않으면 결과에 "Tier 1 미확인"을 명시하고 자신감 라벨을 `추정`으로 강등한다(`~/.claude/rules/hoodcat/source-hierarchy.md` "Tier 1 도달 불가 시 동작").
- 소프트웨어: 유용한 GitHub 레포가 있으면 `gh api repos/{owner}/{repo}/readme`, `gh release list -R {owner}/{repo} --limit 3`, `gh issue view {number} -R {owner}/{repo}`.

Bash는 gh 명령 전용. 다른 시스템 명령 금지.

### 3. 개정·최신성 체크 (규제 / 빠른 변경 도메인)

청약·세무처럼 제도/사양이 자주 바뀌는 도메인(또는 최근 1년 내 개정이 잦은 도메인)에서는 다음을 명시적으로 확인한다.

- 해당 법령·공고·사양의 **최근 개정일·시행일**을 1차 자료에서 확인한다.
- 학습 데이터 시점 이후 변경 가능성을 점검한다(`~/.claude/rules/hoodcat/epistemic-honesty.md` Self-Check 4번).
- 현행과 과거 버전이 다르면 **현행 기준**을 채택하고 변경 이력을 함께 기록한다.
- 시행 예정(미시행) 사항은 "시행 예정"으로 별도 표기한다.

### 4. 재검증 모드 (pushback 정조준)

모드가 재검증이면 광범위 survey 대신 **의심받은 단일 주장**에 집중한다.

1. 재검증 대상 주장을 한 문장으로 특정한다(불명확하면 호출자에게 확인).
2. 그 주장을 직접 뒷받침/반박하는 **Tier 1 자료만** 조회한다(1-A 경로 우선).
3. 결과를 직전 주장과 대조한다:
   - 다르면 명확히 정정한다(모호한 표현 금지).
   - 같으면 자신감 수준을 명시하며 유지한다.
4. 출력에 "직전 주장 / 1차 자료 결과 / 일치 여부 / 정정 내용"을 포함한다.

### 5. 결과 저장

파일: `docs/research-[주제]-!`date +%Y%m%d`.md`

```markdown
# [주제] 조사 결과

> 조사일: !`date +%Y-%m-%d`

## 개요
[핵심 요약 - 3-5문장]

## 상세 내용

### [섹션 1]
[내용]

### [섹션 2]
[내용]

## 코드 예제 (해당 시)
[코드 블록]

## 주요 포인트
- [포인트 1]
- [포인트 2]
- [포인트 3]

## 개정·시행 정보 (규제 도메인 해당 시)
- 현행 기준일: [최근 개정일·시행일]
- 변경 이력 / 시행 예정: [있으면 기재]

## 출처

각 출처에 Tier 라벨을 명시한다 (정의는 `~/.claude/rules/hoodcat/source-hierarchy.md` 참조). 가능하면 확인일을 함께 적는다:

- (Tier 1) [출처 1 — 공고문/법령/공식 API](URL) — 확인 !`date +%Y-%m-%d`
- (Tier 2) [출처 2 — 공식 FAQ/보도자료](URL)
- (Tier 3) [출처 3 — 언론사 기사](URL)
- (Tier 4) [출처 4 — 일반 블로그](URL)
```

유의미한 출처가 3개 미만이면 검색 키워드를 변형하여 추가 검색한다.

조사 완료 후 사용자에게 핵심 5가지를 요약하여 보고한다. 규제 도메인은 Tier 라벨·자신감 라벨(`확실`/`추정`/`모름`)을 동반하고, Tier 1 미확보 시 그 사실을 명시한다.

## 대용량 웹 콘텐츠 처리 (Context Mode)

context-mode MCP 서버가 활성화되어 있으면, 대용량 웹 페이지에 대해 fetch_and_index를 활용한다.

### fetch_and_index 사용

문서 페이지나 블로그 글이 길 것으로 예상될 때 (5KB 이상):
- `mcp__context-mode__fetch_and_index(url: "https://example.com/docs/guide")`
- 페이지를 마크다운으로 변환하고 FTS5에 인덱싱한다
- 이후 `mcp__context-mode__search(queries: ["relevant keyword"])` 로 필요한 부분만 검색

긴 공고문 PDF·법령 페이지(규제 도메인)도 fetch_and_index로 인덱싱한 뒤 자격·일정·요건 등 필요한 항목만 search하면 컨텍스트를 절약한다.

### WebFetch와의 사용 구분

- **짧은 페이지** (API 응답, 짧은 블로그 글): WebFetch 그대로 사용
- **긴 문서 페이지** (프레임워크 가이드, API 레퍼런스, 모집공고·법령 원문): fetch_and_index 사용
- **GitHub README/이슈**: gh CLI로 직접 조회 (변경 없음)

### 인덱싱된 콘텐츠 재활용

fetch_and_index로 인덱싱한 내용은 세션 내 FTS5 DB에 보존된다. 같은 세션의 다른 에이전트도 search로 검색할 수 있으므로, 한번 인덱싱하면 중복 페치를 피할 수 있다.

## OMC 연계

이 스킬은 OMC 위에서 동작하는 개인 스킬이다. OMC 에이전트와 역할이 겹치지 않도록 다음처럼 쓴다.

- 이 스킬: 도메인 적응형 조사, 한국 규제 도메인 Tier 1 강제, 재검증(pushback), `docs/` 저장
- `oh-my-claudecode:document-specialist`: 라이브러리·SDK 공식 문서 단건 조회
- `/oh-my-claudecode:external-context`: 여러 관점 병렬 웹 조사
- 조사 결과가 아키텍처·기술 선택에 영향을 주면 호출자가 `oh-my-claudecode:architect`에 검토를 맡긴다. 이 스킬은 리뷰 없이 끝난다.
