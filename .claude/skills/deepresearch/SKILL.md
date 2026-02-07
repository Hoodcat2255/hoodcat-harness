---
name: deepresearch
description: |
  웹 검색과 Context7을 활용한 철저한 심층 자료조사 스킬. 다음 상황에서 사용:
  - "~에 대해 철저하게 조사해줘", "~를 찾아줘", "~에 대해 알아봐"
  - 라이브러리/프레임워크 문서 조회가 필요할 때
  - 최신 정보와 공식 문서를 종합해야 할 때
  - "deepresearch", "철저하게", "조사", "리서치", "문서화" 키워드가 포함될 때
argument-hint: "[주제]"
context: fork
agent: general-purpose
allowed-tools: WebSearch, WebFetch, mcp__context7__resolve-library-id, mcp__context7__query-docs, Read, Write, Glob, Grep, Bash
---

# 철저한 자료조사 스킬

항상 철저하게 심층 조사를 수행하여 포괄적이고 정확한 정보를 제공합니다.

## 조사 프로세스

### 1단계: 주제 분석
- 핵심 키워드 추출
- 관련 라이브러리/프레임워크 식별

### 2단계: 병렬 정보 수집 (5-7개 동시 실행)

**현재 연도: !`date +%Y`**

**모든 검색은 단일 메시지에서 병렬로 실행**

```
동시 실행:
├── WebSearch: "[주제] comprehensive guide !`date +%Y`"
├── WebSearch: "[주제] best practices patterns"
├── WebSearch: "[주제] advanced tutorial"
├── WebSearch: "[주제] vs alternatives comparison"
├── WebSearch: "[주제] common mistakes pitfalls"
├── GitHub: gh search issues "[주제]" --sort updated (관련 이슈/토론 검색)
├── GitHub: gh search repos "[주제]" --sort stars (관련 레포 탐색)
├── Context7: resolve-library-id (기술 주제인 경우)
└── Context7: query-docs (ID 확보 후, 최대 3회)
```

**GitHub CLI 활용 (Bash를 통해 실행)**

gh 명령은 GitHub 관련 정보 수집에만 사용한다:
- `gh search issues "[주제]" --sort updated --limit 5` - 관련 이슈/토론 검색
- `gh search repos "[주제]" --sort stars --limit 5` - 관련 레포 탐색
- `gh api repos/{owner}/{repo}/readme` - 레포 README 조회
- `gh issue view {number} -R {owner}/{repo}` - 특정 이슈 상세 조회
- `gh pr view {number} -R {owner}/{repo}` - PR 토론/리뷰 조회
- `gh release list -R {owner}/{repo} --limit 3` - 최신 릴리즈 확인

Bash는 gh 명령 실행 용도로만 사용하며, 다른 시스템 명령에는 사용하지 않는다.

### 3단계: 정보 종합
- 주제별 분류
- 중복 제거
- 신뢰도 검증

### 4단계: 결과 정리 및 저장

**조사 결과는 `docs/` 디렉토리에 마크다운 파일로 저장**

파일명 규칙: `docs/research-[주제]-!`date +%Y%m%d`.md`

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

## 사용법

```
/deepresearch React Server Components
/deepresearch Claude Code hooks
/deepresearch Kubernetes networking
```

## 조사 원칙

1. **철저함**: 빠짐없이 모든 관점에서 조사
2. **정확성**: 공식 문서와 신뢰할 수 있는 출처 우선
3. **최신성**: 검색 시 현재 연도 포함
4. **다양성**: 여러 출처에서 정보 종합
5. **출처 명시**: 모든 정보의 출처 기록
6. **실용성**: 코드 예제와 실제 사용 사례 포함
7. **문서화**: 조사 결과는 반드시 `docs/` 디렉토리에 저장
