---
name: sync-docs
description: |
  Synchronizes harness documentation (CLAUDE.md, harness.md) and install script (harness.sh)
  with the actual state of .claude/ subdirectories (skills, agents, hooks).
  Detects mismatches between source files and docs, then auto-updates affected sections.
  Triggers on: "문서 동기화", "docs sync", "sync-docs", or after harness file changes.
argument-hint: "[--check-only] [변경 설명 (선택)]"
user-invocable: true
context: fork
agent: coder
---

# Sync Docs Skill

## 입력

$ARGUMENTS: (선택) --check-only 플래그 또는 변경 설명.
- `--check-only`: 실제 수정 없이 불일치만 보고
- 변경 설명이 있으면 해당 변경에 영향받는 섹션만 타겟팅

## 프로세스

### 1. 현재 상태 수집

`.claude/` 하위를 스캔하여 현재 상태를 파악한다:

**스킬 목록 수집:**
- Glob으로 `.claude/skills/*/SKILL.md` 검색
- 각 SKILL.md의 frontmatter에서 name, description, agent, user-invocable 추출
- 결과: 스킬 이름, 에이전트, 용도 요약 목록

**에이전트 목록 수집:**
- Glob으로 `.claude/agents/*.md` 검색
- 각 에이전트 파일의 frontmatter에서 name, description, model, tools 추출
- 결과: 에이전트 이름, 역할, 호출 방식 목록

**훅 목록 수집:**
- `.claude/settings.json`을 읽어 등록된 훅 이벤트와 matcher 파악
- Glob으로 `.claude/hooks/*.sh` 검색 (test-*.sh 제외)
- 각 훅 스크립트의 상단 주석에서 용도 추출
- 결과: 훅 이름, 이벤트, 용도 목록

### 2. 문서 현재 상태 파싱

대상 문서들을 읽고 관련 섹션을 파싱한다:

**CLAUDE.md 파싱 대상:**
- `## 디렉토리 구조` - 스킬/에이전트 개수
- `## 주요 스킬 (N개)` - 스킬 목록 전체
- `## 훅` - 훅 테이블

**harness.md 파싱 대상:**
- `### 워커 스킬 (N개)` - 스킬 테이블
- `### 에이전트 (N개)` - 에이전트 테이블
- `## 훅` 하위 섹션들

**orchestrator.md 파싱 대상:**
- `## Skill Catalog` - 스킬 카탈로그 테이블들

### 3. 불일치 감지

수집한 현재 상태와 문서 상태를 비교:

- 누락된 스킬 (소스에 있지만 문서에 없음)
- 삭제된 스킬 (문서에 있지만 소스에 없음)
- 개수 불일치 (헤더의 "(N개)"와 실제 개수)
- 누락된 에이전트
- 삭제된 에이전트
- 누락/삭제된 훅
- 훅 이벤트/matcher 불일치

--check-only이면 불일치 목록만 보고하고 종료.

### 4. 문서 업데이트

불일치가 있는 섹션을 업데이트한다:

**CLAUDE.md 업데이트:**
- `## 주요 스킬 (N개)` 헤더의 N을 실제 개수로 수정
- 누락된 스킬의 설명 섹션을 추가 (기존 스킬 형식 참조)
- 삭제된 스킬의 섹션 제거
- `## 훅` 테이블에 누락된 훅 추가/삭제된 훅 제거
- `## 디렉토리 구조`의 개수 업데이트

**harness.md 업데이트:**
- `### 워커 스킬 (N개)` 헤더와 테이블 동기화
- `### 에이전트 (N개)` 헤더와 테이블 동기화
- 훅 관련 섹션 동기화

**orchestrator.md 업데이트:**
- `## Skill Catalog`의 테이블에 누락된 스킬 추가
- 삭제된 스킬 행 제거

### 5. harness.sh 검증

harness.sh의 TEMPLATE_DIRS 배열을 확인:
- 현재: `(agents skills rules hooks)`
- `.claude/` 하위에 새 디렉토리가 있지만 TEMPLATE_DIRS에 없으면 경고
- 직접 수정하지 않고 "harness.sh의 TEMPLATE_DIRS에 X를 추가해야 합니다" 형태로 보고

## 출력

```markdown
## 문서 동기화 완료

### 감지된 불일치
- [불일치 항목 목록]

### 업데이트된 파일
- `CLAUDE.md` — [수정 내용 요약]
- `.claude/harness.md` — [수정 내용 요약]
- `.claude/agents/orchestrator.md` — [수정 내용 요약]

### harness.sh 주의사항
- [TEMPLATE_DIRS 관련 경고 (있는 경우)]

### 검증
- 스킬 목록: N개 (문서 = 소스)
- 에이전트 목록: N개 (문서 = 소스)
- 훅 목록: N개 (문서 = 소스)
```

## REVIEW 연동

sync-docs는 문서 파일만 수정하므로 자체 리뷰는 불필요.
Orchestrator가 전체 작업 흐름에서 리뷰 필요성을 판단한다.
