# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

이 저장소는 Claude Code의 커스텀 스킬과 기능 문서를 관리하는 프로젝트입니다.

## 디렉토리 구조

- `.claude/skills/` - 커스텀 Claude Code 스킬 정의 (SKILL.md 파일)
- `.claude/agents/` - 커스텀 에이전트 정의
- `.claude/hooks/` - Claude Code 훅 스크립트 (품질 게이트, 공유 컨텍스트 등)
- `.claude/shared-context/` - 에이전트 간 공유 컨텍스트 저장소 (런타임 생성, .gitignore)
- `docs/` - 기능 문서 및 리서치 결과 저장

## 아키텍처 (2-tier, Planner-Driven)

Main Agent는 순수 디스패처로, 단순 요청은 워커 스킬을 직접 호출하고, 복합 요청은 Planner에게 위임합니다.
Planner는 요구를 분석하여 스킬을 동적으로 조합하고 이행합니다.

## 주요 스킬

### code
코드 작성/수정/진단/패치 통합 스킬입니다.
- 호출: `/code <작업 지시>`
- Planner가 모든 코드 변경 작업에 사용

### test
테스트 작성 및 실행 스킬입니다.
- 호출: `/test <테스트 대상>`

### blueprint
프로젝트 설계 및 기획 스킬입니다.
- 호출: `/blueprint <기획 대상>`

### deepresearch
웹 검색과 Context7을 활용한 심층 자료조사 스킬입니다.
- 호출: `/deepresearch [주제]`
- 결과는 `docs/research-[주제]-YYYYMMDD.md` 형식으로 저장됨

### scaffold
기존 패턴을 런타임에 참조하여 새 스킬/에이전트 파일을 자동 생성합니다.
- 호출: `/scaffold <type> <name> [options] -- <description>`
- 지원 유형: worker, workflow, agent, pair (에이전트+스킬 쌍)

### team-review (에이전트팀 기반)
멀티렌즈 코드 리뷰 스킬입니다.
- 호출: `/team-review [대상 파일 또는 변경 설명]`
- 대규모/고위험 변경에만 사용
- 비용: 단일 리뷰 대비 약 3배 토큰

### qa-swarm (에이전트팀 기반)
병렬 QA 스웜 스킬입니다.
- 호출: `/qa-swarm [프로젝트 경로]`
- 비용: 단일 테스트 대비 최대 4배 토큰

## hoodcat-harness 공통 지침

@.claude/harness.md

## 문서 작성 규칙

리서치 결과는 `docs/` 디렉토리에 마크다운으로 저장:
- 파일명: `docs/research-[주제]-YYYYMMDD.md`
- 필수 섹션: 개요, 상세 내용, 주요 포인트, 출처
