# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## 프로젝트 개요

이 저장소는 Claude Code의 커스텀 스킬과 기능 문서를 관리하는 프로젝트입니다.

## 디렉토리 구조

- `.claude/skills/` - 커스텀 Claude Code 스킬 정의 (SKILL.md 파일)
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

## 스킬 작성 규칙

스킬 파일은 `.claude/skills/<skill-name>/SKILL.md` 경로에 생성합니다.

필수 frontmatter 필드:
- `name`: 스킬 식별자
- `description`: 스킬 용도 및 트리거 조건

선택적 필드:
- `context: fork` - 서브에이전트에서 실행
- `agent` - 사용할 에이전트 유형
- `allowed-tools` - 허용할 도구 목록

## 논스탑 작업규칙 (Sisyphus)

워크플로우 스킬(implement, new-project, bugfix, improve, hotfix)은 Stop Hook 기반 강제속행 메커니즘(Sisyphus)으로 모든 Phase를 완료할 때까지 멈추지 않는다.

### 동작 방식
- Phase 0에서 `.claude/flags/sisyphus.json`의 `active`를 `true`로 설정
- 각 Phase 시작 시 `phase` 필드를 업데이트
- Stop Hook(`.claude/hooks/sisyphus-gate.sh`)이 종료를 차단하고 다음 Phase로 진행하도록 유도
- 모든 Phase 완료 후 `active`를 `false`로 설정하여 종료 허용

### 검증 규칙
- 빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다
- 텍스트 보고("통과했습니다")를 신뢰하지 않는다
- `.claude/hooks/verify-build-test.sh`로 프로젝트별 빌드/테스트 자동 실행 가능

### 에이전트팀 품질 게이트 훅
- `.claude/hooks/task-quality-gate.sh` (TaskCompleted): 구현 태스크 완료 시 빌드/테스트 자동 검증. exit 2로 완료 차단 가능.
- `.claude/hooks/teammate-idle-check.sh` (TeammateIdle): 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도.

### 에이전트팀 활용 기준
- **/new-project Phase 3**: 독립 태스크 3개 이상이면 에이전트팀 병렬 개발, 2개 이하면 순차 개발
- **/bugfix**: 복잡 버그 감지 시 경쟁 가설 디버깅 (에이전트팀), 단순 버그는 기존 /fix
- **/team-review**: 대규모/고위험 변경에만 사용, 단순 변경은 서브에이전트 리뷰
- **/qa-swarm**: 테스트 스위트가 다양한 프로젝트에만 사용, 소규모는 /test

### 안전장치

| 장치 | 설명 |
|------|------|
| maxIterations | Stop 이벤트 최대 횟수 (기본 15, new-project는 20) |
| safety-stopped | maxIterations 도달 시 자동 비활성화 후 종료 허용 |
| jq 미설치 | fallback으로 종료 허용 |
| flags 파일 없음 | 종료 허용 |
| active=false 기본값 | 일반 작업에 영향 없음 |

### 수동 비활성화

워크플로우를 강제 중단해야 하는 경우:
```bash
jq '.active=false | .phase="manual-stopped"' .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

## 문서 작성 규칙

리서치 결과는 `docs/` 디렉토리에 마크다운으로 저장:
- 파일명: `docs/research-[주제]-YYYYMMDD.md`
- 필수 섹션: 개요, 상세 내용, 주요 포인트, 출처
