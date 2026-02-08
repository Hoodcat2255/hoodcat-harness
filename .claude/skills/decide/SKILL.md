---
name: decide
description: |
  Performs evidence-based decision making by researching options, analyzing trade-offs,
  and providing clear recommendations with reasoning. Use when the user needs to choose
  between alternatives, evaluate options, or make informed decisions. Triggers on:
  "판단해줘", "결정해줘", "골라줘", "비교해줘", "추천해줘", "뭐가 나아",
  "어떤 걸 써야", "decide", or any request asking for comparison, recommendation,
  or decision support on technologies, tools, strategies, or approaches.
argument-hint: "[결정할 주제]"
user-invocable: true
context: fork
agent: general-purpose
allowed-tools: WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs, Read, Write, Glob, Grep, Bash
---

# Decide

**현재 연도: !`date +%Y`**

$ARGUMENTS에 대해 근거 기반 의사결정을 수행한다.

## 프로세스

### 1. 문제 구조화

판단 전에 먼저 정리:
- **결정 대상**: 무엇을 결정하는가?
- **후보군**: 비교할 선택지 목록 (명시되지 않았으면 조사로 식별)
- **핵심 기준**: 이 결정에서 중요한 평가 축 (성능, 비용, 학습곡선, 생태계, 유지보수 등)

### 2. 병렬 정보 수집

**단일 메시지에서 5-7개 검색을 병렬 실행**:

```
동시 실행:
├── WebSearch: "$ARGUMENTS comparison !`date +%Y`"
├── WebSearch: "$ARGUMENTS pros cons trade-offs"
├── WebSearch: "$ARGUMENTS real world experience review"
├── WebSearch: "$ARGUMENTS benchmark performance"
├── WebSearch: "$ARGUMENTS migration pitfalls lessons learned"
├── Bash: gh search repos "$ARGUMENTS" --sort stars --limit 5
├── Bash: gh search issues "$ARGUMENTS" --sort updated --limit 5
├── Context7: resolve-library-id (기술 주제인 경우)
└── Context7: query-docs (ID 확보 후, 최대 3회)
```

Bash는 gh 명령 전용. 다른 시스템 명령 금지.

### 3. 심화 조사

1차 결과에서 핵심 출처를 WebFetch로 상세 조회. 특히:
- 실사용 후기, 마이그레이션 경험담
- 벤치마크, 비교 글
- GitHub 이슈에서 드러나는 실제 문제점

### 4. 분석 및 판단

수집된 근거를 바탕으로:
1. **후보별 장단점** 정리
2. **평가 매트릭스** 작성 (기준 × 후보, 점수 또는 등급)
3. **트레이드오프** 명확히 서술 (A를 선택하면 X를 얻지만 Y를 잃는다)
4. **최종 권고** 제시 - 반드시 근거와 함께

### 5. 결과 출력

**간단한 판단** (선택지 2-3개, 명확한 기준): 대화로 직접 보고

**복잡한 판단** (선택지 4개+, 다차원 기준, 전략적 결정): 문서 저장 후 요약 보고

파일: `docs/decide-[주제]-!`date +%Y%m%d`.md`

```markdown
# [주제] 판단 결과

> 판단일: !`date +%Y-%m-%d`

## 결정 요약
**권고**: [최종 추천]
**확신도**: [높음/중간/낮음] - [이유]

## 후보 분석

### [후보 A]
- 장점: ...
- 단점: ...
- 적합한 경우: ...

### [후보 B]
- 장점: ...
- 단점: ...
- 적합한 경우: ...

## 평가 매트릭스

| 기준 | 후보 A | 후보 B | 후보 C |
|------|--------|--------|--------|
| [기준1] | ... | ... | ... |
| [기준2] | ... | ... | ... |

## 트레이드오프
[A를 선택하면 ~를 얻지만 ~를 잃는다]

## 최종 권고
[구체적 권고 + 근거 + 조건부 권고 (상황에 따라 다른 선택이 나을 경우)]

## 출처
- [출처 1](URL)
```

## 판단 원칙

- **"정답 없음"도 답이다**: 근거가 불충분하거나 상황 의존적이면 솔직히 말한다
- **조건부 권고 활용**: "A가 일반적으로 낫지만, ~한 경우에는 B가 적합"
- **확신도 명시**: 근거의 양과 질에 따라 확신도를 솔직히 표기한다

## 핸드오프 컨텍스트

이 스킬의 출력은 다른 스킬/에이전트에서 소비된다:
- **/design**: 기술 선택 결정을 설계 문서에 반영
- **/implement**: 결정된 기술/패턴으로 구현
- **architect 에이전트**: 결정의 아키텍처 적합성 평가 시 참조

## REVIEW 연동

의사결정 결과가 아키텍처에 영향을 주는 경우, /design이나 워크플로우가 architect 에이전트에게 리뷰를 요청한다. decide 자체는 리뷰 없이 완료된다.
