---
name: deepresearch
description: |
  Performs thorough deep research on any topic using web search, Context7 docs, and GitHub CLI.
  Saves structured results to docs/ directory. Use when the user asks to research, investigate,
  or gather comprehensive information on a topic. Triggers on: "조사해줘", "찾아줘", "알아봐",
  "리서치", "deepresearch", or any request for in-depth information gathering about a technology,
  library, framework, concept, or trend.
argument-hint: "[주제]"
user-invocable: true
context: fork
agent: general-purpose
allowed-tools: WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs, Read, Write, Glob, Grep, Bash
---

# Deep Research

**현재 연도: !`date +%Y`**

## 프로세스

### 1. 병렬 정보 수집

$ARGUMENTS에 대해 **단일 메시지에서 5-7개 검색을 병렬 실행**한다:

```
동시 실행:
├── WebSearch: "$ARGUMENTS comprehensive guide !`date +%Y`"
├── WebSearch: "$ARGUMENTS best practices patterns"
├── WebSearch: "$ARGUMENTS advanced tutorial"
├── WebSearch: "$ARGUMENTS vs alternatives comparison"
├── WebSearch: "$ARGUMENTS common mistakes pitfalls"
├── Bash: gh search repos "$ARGUMENTS" --sort stars --limit 5
├── Bash: gh search issues "$ARGUMENTS" --sort updated --limit 5
├── Context7: resolve-library-id (기술 주제인 경우)
└── Context7: query-docs (ID 확보 후, 최대 3회)
```

### 2. 심화 조사

1차 결과에서 발견한 핵심 출처를 WebFetch로 상세 조회한다. 유용한 GitHub 레포가 있으면:
- `gh api repos/{owner}/{repo}/readme` - README 조회
- `gh release list -R {owner}/{repo} --limit 3` - 최신 릴리즈 확인
- `gh issue view {number} -R {owner}/{repo}` - 주요 이슈 상세 조회

Bash는 gh 명령 전용. 다른 시스템 명령 금지.

### 3. 결과 저장

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

## 출처
- [출처 1](URL)
- [출처 2](URL)
```

조사 완료 후 사용자에게 핵심 5가지를 요약하여 보고한다.

## 핸드오프 컨텍스트

이 스킬의 출력은 다른 스킬/에이전트에서 소비된다:
- **/plan**: 기술 선택의 근거 자료로 활용
- **/decide**: 의사결정에 필요한 기초 조사 자료로 활용
- **architect 에이전트**: 기술 스택 적합성 평가 시 참조

## REVIEW 연동

조사 결과가 아키텍처/기술 선택에 영향을 주는 경우, /plan이나 워크플로우가 architect 에이전트에게 리뷰를 요청한다. deepresearch 자체는 리뷰 없이 완료된다.
