---
name: scaffold
description: |
  Scaffolds new skills and agents following established hoodcat-harness patterns.
  Reads existing files at runtime to ensure generated code matches current conventions.
  Triggers on: "스캐폴드", "스킬 생성", "에이전트 생성", "scaffold",
  or any request to create a new skill, agent, or skill+agent pair.
argument-hint: "<type> <name> [agent:<type>] [tools:[...]] [model:<model>] -- <description>"
user-invocable: true
context: fork
agent: coder
---

# Scaffold Skill

## 입력

$ARGUMENTS: 생성할 유형과 이름, 옵션, 설명.

### 형식

```
<type> <name> [options] -- <description>
```

### 지원 유형

| type | 생성물 | 필수 인자 |
|------|--------|----------|
| `worker` | 워커 스킬 SKILL.md | name, agent, description |
| `agent` | 에이전트 .md | name, tools, description |
| `pair` | 에이전트 + 스킬 쌍 | name, tools, description |

### 옵션

- `agent:<type>` - 스킬이 사용할 에이전트 (worker/pair에서 사용, 기본값: coder)
- `tools:[Tool1,Tool2,...]` - 에이전트 도구 목록 (agent/pair에서 필수)
- `model:<model>` - 에이전트 모델 (기본값: opus)
- `--user-invocable` / `--internal` - 사용자 직접 호출 가능 여부 (기본값: user-invocable)

### 예시

```
worker lint-check agent:coder -- 프로젝트 린터 실행
agent analyzer tools:[Read,Glob,Grep] -- 코드 분석 전문 에이전트
pair formatter tools:[Read,Write,Edit,Bash(npx *)] -- 코드 포맷팅 스킬과 에이전트
```

자연어 입력도 허용한다. 의도를 파악하여 적절한 유형으로 매핑한다.

## 프로세스

### 1. 입력 파싱 및 검증

$ARGUMENTS에서 type, name, agent, tools, model, description을 추출한다.

검증 항목:
- name이 기존 스킬/에이전트와 중복되지 않는지 확인 (Glob으로 `.claude/skills/*/SKILL.md`와 `.claude/agents/*.md` 검색)
- worker/pair일 때 agent가 `.claude/agents/`에 존재하는지 확인
- agent/pair일 때 tools가 지정되었는지 확인

중복이나 누락이 있으면 사용자에게 보고하고 중단한다.

### 2. 참조 예제 읽기

생성 유형에 맞는 기존 파일을 Read로 읽어 최신 패턴을 파악한다:

| 유형 | 참조 파일 |
|------|----------|
| worker | `.claude/skills/code/SKILL.md` + `.claude/skills/test/SKILL.md` |
| agent | `.claude/agents/coder.md` + `.claude/agents/reviewer.md` |
| pair | worker 참조 + agent 참조 모두 |

참조 파일에서 파악할 것:
- frontmatter 필드와 형식
- 본문 섹션 구조와 순서
- Shared Context Protocol / Memory Management 정형 텍스트
- 마크다운 스타일 (헤딩 레벨, 코드 블록 사용 패턴)

### 3. 스킬 파일 생성 (worker/workflow/pair)

`.claude/skills/{name}/SKILL.md`를 생성한다.

#### frontmatter

```yaml
---
name: {name}
description: |
  {description}
  {트리거 힌트 - 한글/영어 키워드 포함}
argument-hint: "{적절한 인자 힌트}"
user-invocable: {true/false}
context: fork
agent: {agent}
---
```

#### 워커 스킬 본문 구조

```markdown
# {Name} Skill

## 입력

$ARGUMENTS: {입력 설명}

## 프로세스

### 1. {첫 번째 단계}
{설명}

### 2. {두 번째 단계}
{설명}

...

## 출력

```markdown
## {출력 제목}

### {섹션 1}
- {항목}

### {섹션 2}
- {항목}
```

## REVIEW 연동

{리뷰 방식 설명 - 내부 스킬이면 "호출 워크플로우가 담당", 독립 스킬이면 자체 리뷰 로직}
```

### 4. 에이전트 파일 생성 (agent/pair)

`.claude/agents/{name}.md`를 생성한다.

#### frontmatter

```yaml
---
name: {name}
description: |
  {description}
  {언제 호출되는지, 언제 호출되지 않는지}
tools:
  - {Tool1}
  - {Tool2}
  ...
model: {model}
memory: project
---
```

#### 에이전트 본문 구조

```markdown
# {Name} Agent

## Purpose

You are a {role description} running inside a forked sub-agent context.
Your job is to {핵심 책임 요약}.

## Capabilities

- **{카테고리 1}**: {설명}
- **{카테고리 2}**: {설명}

## Constraints

- {제약 사항 1}
- {제약 사항 2}

## Shared Context Protocol

이전 에이전트의 작업 결과가 additionalContext로 주입되면, 이를 참고하여 중복 작업을 줄인다.

작업 완료 시, 핵심 발견 사항을 지정된 공유 컨텍스트 파일에 기록한다.
additionalContext에 기록 경로가 포함되어 있다.

기록 형식:
```markdown
## {Name} Report
### {섹션 1}
- [{항목 설명}]
### {섹션 2}
- [{항목 설명}]
```

## Memory Management

**작업 시작 전**: MEMORY.md와 주제별 파일을 읽고, 이전 작업 이력과 축적된 지식을 참고한다.

**작업 완료 후**: MEMORY.md를 갱신한다 (200줄 이내 유지):
- `## TODO` - {에이전트 역할에 맞는 TODO 설명}
- `## In Progress` - 현재 진행 중인 작업 (중단된 경우)
- `## Done` - 완료된 작업 요약 (오래된 항목은 정리)

축적된 패턴은 주제별 파일에 분리 기록한다.
```

### 5. shared-context-config.json 업데이트 (agent/pair만)

`.claude/shared-context-config.json`의 `filters`에 새 에이전트 타입의 항목을 추가한다.

기본 필터 값:
- 읽기 전용 에이전트 (Grep/Glob/Read만): `["navigation"]`
- 읽기/쓰기 에이전트: `["navigation", "code_changes"]`
- 탐색 전용 에이전트: `[]`

Read로 현재 파일을 읽고, Edit으로 filters 객체에 새 항목을 추가한다.

### 6. 검증

`@checklists.md`의 체크리스트로 생성된 파일을 검증한다.

생성된 각 파일을 Read로 다시 읽어 체크리스트 항목을 확인:
- frontmatter 필수 필드 존재 여부
- 본문 필수 섹션 존재 여부
- Shared Context Protocol / Memory Management 포함 여부 (에이전트)
- `context: fork` 설정 여부 (스킬)

누락 항목이 있으면 즉시 수정한다.

## 출력

```markdown
## Scaffold 완료

### 생성된 파일
- `.claude/skills/{name}/SKILL.md` - {유형} 스킬
- `.claude/agents/{name}.md` - 에이전트 (agent/pair만)

### 검증 결과
- frontmatter: OK
- 본문 섹션: OK
- Shared Context Protocol: OK (에이전트)
- Memory Management: OK (에이전트)

### 다음 단계
- 생성된 파일을 열어 `{placeholder}` 부분을 프로젝트에 맞게 수정
- 필요 시 프로세스 단계를 추가/수정
- `/commit`으로 커밋
```
