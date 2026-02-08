# Claude Code 좋은 스킬 작성법 조사 결과

> 조사일: 2026-02-08

## 개요

Claude Code 스킬은 SKILL.md 파일을 통해 Claude의 기능을 확장하는 모듈형 패키지이다. 좋은 스킬을 작성하려면 간결한 컨텍스트 관리, 효과적인 description 작성, 점진적 공개(Progressive Disclosure) 패턴, 적절한 자유도 설정, 그리고 반복적 테스트가 핵심이다. 이 문서는 Anthropic 공식 문서, 공식 스킬 저장소, 그리고 커뮤니티 모범 사례를 종합하여 정리한 것이다.

## 상세 내용

### 1. 스킬의 기본 구조

스킬은 디렉토리 안에 `SKILL.md` 파일을 필수로 포함하며, 선택적으로 스크립트, 레퍼런스, 에셋 파일을 함께 번들링할 수 있다.

```
skill-name/
├── SKILL.md              # 필수 - 메인 지시사항
├── references/            # 선택 - 필요 시 컨텍스트에 로딩되는 참고 문서
│   ├── schema.md
│   └── api_docs.md
├── scripts/               # 선택 - 실행 가능한 코드 (Python/Bash 등)
│   └── validate.py
└── assets/                # 선택 - 출력물에 사용되는 파일 (템플릿, 이미지 등)
    └── template.html
```

#### SKILL.md의 두 가지 구성요소

1. **YAML Frontmatter** (`---` 사이): Claude가 스킬을 언제 사용할지 결정하는 메타데이터
2. **Markdown Body**: 스킬이 트리거된 후 Claude가 따르는 지시사항

### 2. Frontmatter 작성법

#### 필수/권장 필드

| 필드 | 설명 | 규칙 |
|------|------|------|
| `name` | 스킬 식별자, `/slash-command`가 됨 | 소문자+숫자+하이픈만, 최대 64자 |
| `description` | 스킬의 기능과 트리거 조건 | 최대 1024자, 비어있으면 안 됨 |

#### 선택 필드

| 필드 | 설명 |
|------|------|
| `argument-hint` | 자동완성 시 표시할 인자 힌트 (예: `[issue-number]`) |
| `disable-model-invocation` | `true` 시 Claude가 자동 호출 불가, 사용자만 수동 호출 |
| `user-invocable` | `false` 시 `/` 메뉴에서 숨김, Claude만 호출 가능 |
| `allowed-tools` | 스킬 활성화 시 승인 없이 사용 가능한 도구 목록 |
| `context` | `fork` 설정 시 서브에이전트 컨텍스트에서 실행 |
| `agent` | `context: fork` 시 사용할 에이전트 타입 (Explore, Plan, general-purpose 등) |
| `model` | 스킬 활성화 시 사용할 모델 |
| `hooks` | 스킬 라이프사이클에 연결된 훅 |

#### name 작성 규칙

- **동명사(gerund) 형태 권장**: `processing-pdfs`, `analyzing-spreadsheets`, `testing-code`
- **수용 가능한 대안**: 명사구(`pdf-processing`), 동작 지향(`process-pdfs`)
- **피해야 할 것**: 모호한 이름(`helper`, `utils`), 너무 일반적인 이름(`documents`, `data`), 예약어 포함(`anthropic-*`, `claude-*`)

### 3. Description 작성법 (가장 중요)

Description은 스킬 발견(discovery)의 핵심 메커니즘이다. Claude는 100개 이상의 스킬 중에서 description을 기반으로 적합한 스킬을 선택한다.

#### 핵심 원칙

**1. 반드시 3인칭으로 작성**

Description은 시스템 프롬프트에 주입되므로, 시점 불일치가 발견 문제를 일으킨다.

```yaml
# 좋은 예
description: Processes Excel files and generates reports

# 나쁜 예
description: I can help you process Excel files
description: You can use this to process Excel files
```

**2. "무엇을 하는지"와 "언제 사용하는지" 모두 포함**

```yaml
# 좋은 예 - PDF 스킬
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.

# 좋은 예 - Git 커밋 스킬
description: Generate descriptive commit messages by analyzing git diffs. Use when the user asks for help writing commit messages or reviewing staged changes.

# 나쁜 예
description: Helps with documents
description: Processes data
```

**3. "When to Use" 정보는 description에만 넣기**

Body에 "When to Use This Skill" 섹션을 넣어도 Claude가 볼 수 없다. Body는 스킬이 트리거된 후에만 로딩되기 때문이다.

**4. 구체적인 트리거 키워드 포함**

```yaml
description: |
  Use this skill whenever the user wants to do anything with PDF files.
  This includes reading or extracting text/tables from PDFs, combining
  or merging multiple PDFs into one, splitting PDFs apart, rotating pages,
  adding watermarks, creating new PDFs, filling PDF forms...
  If the user mentions a .pdf file or asks to produce one, use this skill.
```

### 4. Body(본문) 작성 베스트 프랙티스

#### 간결함이 핵심

컨텍스트 윈도우는 공유 자원이다. Claude는 이미 매우 똑똑하므로, Claude가 이미 알고 있는 내용은 포함하지 않는다.

```markdown
# 좋은 예 (~50 토큰)
## PDF 텍스트 추출

pdfplumber로 텍스트 추출:
```python
import pdfplumber
with pdfplumber.open("file.pdf") as pdf:
    text = pdf.pages[0].extract_text()
```

# 나쁜 예 (~150 토큰)
## PDF 텍스트 추출

PDF(Portable Document Format) 파일은 텍스트, 이미지 등을 포함하는
일반적인 파일 형식입니다. PDF에서 텍스트를 추출하려면 라이브러리가
필요합니다. 여러 라이브러리가 있지만 pdfplumber를 추천합니다...
```

**각 정보에 대해 자문하기:**
- "Claude가 정말 이 설명이 필요한가?"
- "이 문단이 토큰 비용을 정당화하는가?"
- "Claude가 이미 알고 있다고 가정할 수 있는가?"

#### 500줄 이하로 유지

SKILL.md 본문은 500줄 이하가 최적이다. 초과 시 별도 파일로 분리하여 Progressive Disclosure를 적용한다.

#### 적절한 자유도 설정

작업의 취약성(fragility)과 가변성에 맞게 지시 수준을 조절한다.

| 자유도 | 사용 시점 | 예시 |
|--------|----------|------|
| **높음** (텍스트 지시) | 여러 접근법이 유효, 맥락에 따라 판단 | 코드 리뷰 가이드 |
| **중간** (의사코드/파라미터) | 선호 패턴 존재, 약간의 변형 허용 | 리포트 생성 템플릿 |
| **낮음** (특정 스크립트) | 취약한 작업, 일관성 필수 | DB 마이그레이션 스크립트 |

비유: Claude가 길을 탐색하는 로봇이라면:
- **양쪽에 절벽이 있는 좁은 다리**: 정확한 가드레일 필요 (낮은 자유도)
- **위험 없는 넓은 들판**: 일반적 방향만 제시 (높은 자유도)

### 5. Progressive Disclosure (점진적 공개) 패턴

스킬의 정보 로딩은 3단계로 이루어진다:

1. **메타데이터** (name + description): 항상 컨텍스트에 존재 (~100단어)
2. **SKILL.md 본문**: 스킬이 트리거될 때 로딩 (<5000단어)
3. **번들 리소스**: 필요할 때만 Claude가 로딩 (무제한)

#### 패턴 1: 하이레벨 가이드 + 참조 파일

```markdown
# PDF Processing

## Quick start
[핵심 코드 예제]

## Advanced features
**Form filling**: See [FORMS.md](FORMS.md) for complete guide
**API reference**: See [REFERENCE.md](REFERENCE.md) for all methods
```

#### 패턴 2: 도메인별 분리

```
bigquery-skill/
├── SKILL.md (개요와 네비게이션)
└── reference/
    ├── finance.md (매출 지표)
    ├── sales.md (영업 데이터)
    └── product.md (사용 분석)
```

#### 패턴 3: 조건부 상세 정보

```markdown
## Document 수정

기본 편집: XML 직접 수정
**변경 추적이 필요하면**: See [REDLINING.md](REDLINING.md)
**OOXML 상세 정보**: See [OOXML.md](OOXML.md)
```

#### 핵심 규칙: 참조는 1단계 깊이만

Claude는 중첩 참조(파일 A -> 파일 B -> 파일 C)를 부분적으로만 읽을 수 있다. 모든 참조 파일은 SKILL.md에서 직접 연결해야 한다.

```markdown
# 나쁜 예 (너무 깊음)
SKILL.md -> advanced.md -> details.md

# 좋은 예 (1단계)
SKILL.md -> advanced.md
SKILL.md -> reference.md
SKILL.md -> examples.md
```

### 6. 효과적인 워크플로우 패턴

#### 체크리스트 패턴

복잡한 작업은 Claude가 복사하여 진행 상황을 추적할 수 있는 체크리스트를 제공한다:

```markdown
## 배포 워크플로우

진행 상황 추적:
- [ ] Step 1: 테스트 실행
- [ ] Step 2: 빌드
- [ ] Step 3: 배포
- [ ] Step 4: 검증
```

#### 피드백 루프 패턴

검증 -> 수정 -> 재검증 순환:

```markdown
1. 편집 수행
2. 즉시 검증: `python scripts/validate.py`
3. 실패 시: 오류 수정 후 다시 검증
4. 통과할 때까지 반복
5. 빌드 및 최종 테스트
```

#### 조건부 워크플로우 패턴

```markdown
1. 작업 유형 판단:
   **새로 생성?** -> "생성 워크플로우" 실행
   **기존 편집?** -> "편집 워크플로우" 실행
```

#### 템플릿 패턴

```markdown
## 리포트 구조
ALWAYS use this exact template:

# [분석 제목]
## 핵심 요약
## 주요 발견
## 권장 사항
```

#### 예시(Examples) 패턴

입출력 쌍을 제공하여 원하는 스타일과 상세 수준을 보여준다:

```markdown
## 커밋 메시지 형식

**Example 1:**
Input: JWT 토큰 기반 사용자 인증 추가
Output:
feat(auth): JWT 기반 인증 구현
```

### 7. 호출 제어 전략

| Frontmatter 설정 | 사용자 호출 | Claude 호출 | 컨텍스트 로딩 |
|------------------|-----------|------------|-------------|
| (기본값) | O | O | description 항상 로드, body는 호출 시 |
| `disable-model-invocation: true` | O | X | description 미로드, 수동 호출 시만 |
| `user-invocable: false` | X | O | description 항상 로드, 호출 시 body 로드 |

- **`disable-model-invocation: true`**: 부작용이 있는 워크플로우에 사용 (deploy, commit 등)
- **`user-invocable: false`**: 배경 지식용 스킬에 사용 (사용자가 직접 호출할 필요 없는 것)

### 8. 동적 컨텍스트 주입

`!`command`` 문법으로 셸 명령을 전처리하여 실시간 데이터를 주입할 수 있다:

```yaml
---
name: pr-summary
description: Summarize changes in a pull request
context: fork
agent: Explore
allowed-tools: Bash(gh *)
---

## PR 컨텍스트
- PR diff: !`gh pr diff`
- PR comments: !`gh pr view --comments`
- Changed files: !`gh pr diff --name-only`

## 작업
이 PR을 요약해주세요...
```

명령이 먼저 실행되고, 결과가 스킬 내용에 삽입된 후 Claude에게 전달된다.

### 9. 서브에이전트 실행 (context: fork)

`context: fork`를 설정하면 스킬이 격리된 서브에이전트에서 실행된다. 대화 기록에 접근할 수 없으며, 스킬 내용이 서브에이전트의 프롬프트가 된다.

```yaml
---
name: deep-research
description: Research a topic thoroughly
context: fork
agent: Explore
---

$ARGUMENTS에 대해 철저히 조사:
1. Glob과 Grep으로 관련 파일 찾기
2. 코드 읽고 분석
3. 구체적 파일 참조와 함께 결과 요약
```

**주의**: `context: fork`는 명시적 지시사항이 있는 스킬에서만 의미가 있다. "이 API 규칙을 따르라" 같은 가이드라인만 있으면, 서브에이전트가 지침은 받지만 실행할 작업이 없어 의미 없는 결과를 반환한다.

### 10. 반복적 개선 프로세스

Anthropic이 권장하는 스킬 개발 프로세스:

1. **스킬 없이 작업 수행**: Claude A와 일반 프롬프팅으로 문제 해결. 반복적으로 제공하는 컨텍스트를 관찰
2. **재사용 패턴 식별**: 향후 유사 작업에 유용한 컨텍스트 파악
3. **Claude A에게 스킬 생성 요청**: "방금 사용한 패턴을 캡처하는 스킬 만들어줘"
4. **간결함 검토**: 불필요한 설명 제거
5. **정보 아키텍처 개선**: "테이블 스키마를 별도 참조 파일로 분리해"
6. **Claude B로 테스트**: 새 인스턴스에서 스킬 로드 후 유사 작업 수행
7. **관찰 기반 반복**: Claude B가 어려워하면 Claude A에게 개선 의뢰

#### 평가(Evaluation) 먼저 만들기

문서화보다 평가를 먼저 작성하여 실제 문제를 해결하는지 확인한다:

1. 스킬 없이 대표 작업 실행 -> 실패/부족 기록
2. 이 격차를 테스트하는 3개 시나리오 작성
3. 기준선 측정
4. 최소한의 지시로 격차 해결
5. 반복

### 11. 피해야 할 안티패턴

| 안티패턴 | 문제점 | 해결책 |
|---------|--------|--------|
| Windows 경로 (`\`) | Unix에서 오류 발생 | 항상 `/` 사용 |
| 너무 많은 옵션 제시 | Claude가 혼란 | 기본값 제공 + 대안 1개 |
| 시간 민감한 정보 | 금방 구식이 됨 | "Old patterns" 섹션 사용 |
| 비일관적 용어 | 이해도 저하 | 하나의 용어로 통일 |
| 깊은 중첩 참조 | 불완전한 읽기 | 1단계 깊이만 |
| 장황한 설명 | 토큰 낭비 | Claude가 아는 것은 생략 |
| Body에 "When to Use" | 트리거 전에 보이지 않음 | description에만 작성 |
| 매직 넘버 | 디버깅 어려움 | 모든 값에 이유 문서화 |

### 12. 기존 deepresearch 스킬 개선 포인트 분석

현재 이 프로젝트의 `deepresearch` 스킬을 분석한 결과:

**잘 된 점:**
- description에 다양한 트리거 키워드 포함
- `context: fork`와 `allowed-tools` 적절히 활용
- `argument-hint` 제공
- 동적 컨텍스트 주입(`!`date``) 활용

**개선 가능한 점:**
- Description이 1인칭/2인칭이 아닌 것은 좋지만, 3인칭 문체로 더 명확히 할 수 있음 (예: "Performs thorough deep research...")
- Body에 "조사 원칙" 같은 일반 가이드라인이 있는데, Claude가 이미 알 수 있는 내용일 수 있음
- "사용법" 섹션은 body에 있어도 트리거 후에만 보이므로 큰 도움이 되지 않음
- 참조 파일 분리를 통해 body를 더 간결하게 만들 수 있음

## 코드 예제

### 좋은 스킬의 완전한 예시

```yaml
---
name: code-review
description: Performs thorough code reviews with focus on security, performance, and maintainability. Use when reviewing pull requests, analyzing code quality, or when the user asks to review code changes.
disable-model-invocation: true
allowed-tools: Read, Grep, Glob
---

# Code Review

## Process

1. Read changed files
2. Analyze for:
   - Security vulnerabilities
   - Performance issues
   - Code style consistency
   - Edge cases

3. Generate review with this format:

```markdown
## Review: [file/PR name]

### Critical Issues
- [issue with line reference]

### Suggestions
- [improvement with example]

### Positive Notes
- [what's done well]
```

For security patterns, see [references/security-checklist.md](references/security-checklist.md)
```

### 효과적인 description 예시 모음

```yaml
# PDF 처리 - 구체적 트리거와 기능 나열
description: Extract text and tables from PDF files, fill forms, merge documents. Use when working with PDF files or when the user mentions PDFs, forms, or document extraction.

# 프론트엔드 디자인 - 대상과 차별점 명시
description: Create distinctive, production-grade frontend interfaces with high design quality. Use this skill when the user asks to build web components, pages, artifacts, posters, or applications.

# 스킬 생성 - 메타 스킬의 트리거 조건
description: Guide for creating effective skills. This skill should be used when users want to create a new skill (or update an existing skill) that extends Claude's capabilities.
```

## 주요 포인트

- **Description이 가장 중요하다**: Body가 아닌 description이 스킬 트리거를 결정한다. 3인칭으로, 기능과 트리거 조건을 모두 포함해야 한다
- **간결함이 핵심이다**: Claude는 이미 똑똑하다. 토큰은 공유 자원이므로, Claude가 모르는 것만 포함한다
- **Progressive Disclosure를 활용한다**: 메타데이터(항상) -> SKILL.md(트리거 시) -> 참조 파일(필요 시)의 3단계 로딩
- **자유도를 작업에 맞춘다**: 취약한 작업은 구체적 스크립트, 유연한 작업은 텍스트 지시
- **평가 먼저, 문서화 나중에**: 실제 문제를 해결하는지 테스트로 확인한 후 스킬을 확장한다
- **반복적으로 개선한다**: Claude A(설계) + Claude B(테스트) 패턴으로 관찰 기반 개선
- **참조 파일은 1단계만**: 깊은 중첩 참조는 불완전한 읽기를 유발한다
- **피드백 루프를 포함한다**: 검증 -> 수정 -> 재검증 순환으로 품질 보장

## 출처

- [Extend Claude with skills - Claude Code 공식 문서](https://code.claude.com/docs/en/skills)
- [Skill authoring best practices - Claude Platform 문서](https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices)
- [Anthropic 공식 스킬 저장소 (skill-creator)](https://github.com/anthropics/skills/blob/main/skills/skill-creator/SKILL.md)
- [Claude Agent Skills: A First Principles Deep Dive](https://leehanchung.github.io/blogs/2025/10/26/claude-skills-deep-dive/)
- [Inside Claude Code Skills: Structure, prompts, invocation](https://mikhail.io/2025/10/claude-code-skills/)
- [Claude Code Customization Guide](https://alexop.dev/posts/claude-code-customization-guide-claudemd-skills-subagents/)
- [Understanding Claude Code: Skills vs Commands vs Subagents vs Plugins](https://www.youngleaders.tech/p/claude-skills-commands-subagents-plugins)
- [How I Taught My AI Coding Assistant to Think Like Me](https://medium.com/@krupeshraut/how-i-taught-my-ai-coding-assistant-to-think-like-me-a-guide-to-claude-code-skills-b8d78ed41822)
- [Claude Code Skills: Complete Guide to Slash Commands](https://claude-world.com/articles/skills-guide/)
- [awesome-claude-skills (ComposioHQ)](https://github.com/ComposioHQ/awesome-claude-skills)
- [awesome-claude-code (hesreallyhim)](https://github.com/hesreallyhim/awesome-claude-code)
- [VoltAgent/awesome-agent-skills](https://github.com/VoltAgent/awesome-agent-skills)
