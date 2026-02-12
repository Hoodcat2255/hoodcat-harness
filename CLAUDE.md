# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

이 저장소는 Claude Code의 커스텀 스킬과 기능 문서를 관리하는 프로젝트입니다.

## 디렉토리 구조

- `.claude/skills/` - 커스텀 Claude Code 스킬 정의 (SKILL.md 파일)
- `.claude/agents/` - 커스텀 에이전트 정의
- `docs/` - 기능 문서 및 리서치 결과 저장

## 주요 스킬

### deepresearch
웹 검색과 Context7을 활용한 심층 자료조사 스킬입니다.
- 호출: `/deepresearch [주제]`
- 결과는 `docs/research-[주제]-YYYYMMDD.md` 형식으로 저장됨
- 5-7개의 병렬 검색을 통해 포괄적인 정보 수집

### team-review (에이전트팀 기반)
멀티렌즈 코드 리뷰 스킬입니다. 3명의 리뷰어(코드 품질, 보안, 아키텍처)가 동시에 독립 리뷰 후 상호 피드백을 교환합니다.
- 호출: `/team-review [대상 파일 또는 변경 설명]`
- 대규모/고위험 변경에만 사용 (단순 변경은 기존 서브에이전트 리뷰 사용)
- 비용: 단일 리뷰 대비 약 3배 토큰

### qa-swarm (에이전트팀 기반)
병렬 QA 스웜 스킬입니다. 테스트, 린트, 빌드, 보안 스캔을 동시에 실행합니다.
- 호출: `/qa-swarm [프로젝트 경로]`
- 프로젝트의 테스트 스위트가 다양할 때 사용
- 비용: 단일 테스트 대비 최대 4배 토큰

## hoodcat-harness 공통 지침

@.claude/harness.md

## 문서 작성 규칙

리서치 결과는 `docs/` 디렉토리에 마크다운으로 저장:
- 파일명: `docs/research-[주제]-YYYYMMDD.md`
- 필수 섹션: 개요, 상세 내용, 주요 포인트, 출처
