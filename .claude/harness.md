# hoodcat-harness 공통 지침

이 문서는 hoodcat-harness 멀티에이전트 시스템이 설치된 모든 프로젝트에 적용되는 공통 지침이다.

## 스킬 아키텍처

모든 스킬은 `context: fork`로 서브에이전트에서 격리 실행된다.
메인 에이전트는 순수한 오케스트레이터로, 사용자 의도를 파악하여 적절한 스킬을 디스패치한다.

### 워크플로우 스킬
서브에이전트에서 다중 Phase를 자율 실행하며, 워커 스킬과 에이전트를 조율한다.
`agent: workflow` 사용.
- bugfix, hotfix, implement, improve, new-project

### 워커 스킬
단일 책임의 독립 작업을 수행한다.
- fix, test, blueprint, commit, deploy, security-scan, deepresearch, decide, team-review, qa-swarm

### 에이전트 (8개)
- **workflow**: 워크플로우 + 팀 오케스트레이션. Skill/Task/팀 도구.
- **researcher**: 리서치/기획 워커. WebSearch/Context7/문서 작성.
- **coder**: 코딩 워커. 파일 읽기/쓰기 + 빌드/테스트/감사 명령.
- **committer**: Git 워커. 읽기 전용 + git 명령만. sonnet.
- **reviewer**: 코드 품질 리뷰. 유지보수성, 패턴 일관성 평가.
- **security**: 보안 리뷰. OWASP Top 10, 인증/인가 평가.
- **architect**: 아키텍처 리뷰. 구조 적합성, 확장성 평가.
- **navigator**: 코드베이스 탐색. 파일 매핑, 영향 범위 파악.

## Git Worktree 규칙

개발 작업은 반드시 `git worktree`를 사용한다.

- 멀티 세션이 같은 working directory를 공유하면 파일 충돌이 발생한다
- 에이전트팀 병렬 개발 시 팀원들이 같은 파일을 동시에 수정하면 덮어쓰기가 발생한다
- worktree로 세션/팀원별 독립 작업 디렉토리를 확보하여 충돌을 원천 차단한다

```bash
# 피처 브랜치용 worktree 생성
git worktree add ../project-feature-x feature-x

# 작업 완료 후 정리
git worktree remove ../project-feature-x
```

적용 대상:
- `/implement`, `/bugfix`, `/hotfix`, `/improve` 등 코드를 수정하는 워크플로우
- `/new-project`의 에이전트팀 병렬 개발 Phase
- 동일 프로젝트에서 Claude Code 세션을 여러 개 띄울 때

## 스킬 실행 모델

모든 스킬은 `context: fork`로 서브에이전트에서 실행된다.
서브에이전트는 자체 컨텍스트에서 완료까지 자율 실행되므로, 별도의 강제속행 메커니즘이 불필요하다.

### 검증 규칙
- 빌드/테스트 결과는 **실제 명령어의 exit code**로만 판단한다
- 텍스트 보고("통과했습니다")를 신뢰하지 않는다
- `.claude/hooks/verify-build-test.sh`로 프로젝트별 빌드/테스트 자동 실행 가능

### 품질 게이트 훅
- `.claude/hooks/task-quality-gate.sh` (TaskCompleted): 구현 태스크 완료 시 빌드/테스트 자동 검증. exit 2로 완료 차단 가능.
- `.claude/hooks/teammate-idle-check.sh` (TeammateIdle): 미완료 태스크가 있는 팀원이 유휴 상태가 되면 작업 재개 유도.

### 공유 컨텍스트 시스템

서브에이전트 간 작업 결과를 공유하는 파일 기반 시스템. 중복 탐색을 줄이고 후속 에이전트에 이전 작업 결과를 자동 전달한다.

**동작 원리:**
1. **SubagentStart** (`shared-context-inject.sh`): 이전 에이전트의 작업 요약을 `additionalContext`로 주입
2. **에이전트 자발적 기록**: 에이전트가 작업 결과를 `.claude/shared-context/{session-id}/{agent-type}-{agent-id}.md`에 직접 기록
3. **SubagentStop** (`shared-context-collect.sh`): 자발적 기록이 없으면 transcript에서 자동 추출, `_summary.md` 업데이트
4. **SessionStart** (`shared-context-cleanup.sh`): TTL 만료 세션 정리
5. **SessionEnd** (`shared-context-finalize.sh`): 세션 메트릭 기록

**설정:** `.claude/shared-context-config.json`
- `ttl_hours`: 세션 데이터 유지 시간 (기본 24시간)
- `max_summary_chars`: 주입할 컨텍스트 최대 크기 (기본 4000자)
- `filters`: 에이전트 타입별 컨텍스트 필터링 규칙

**검증:** `bash .claude/hooks/test-shared-context.sh`로 통합 테스트 실행 가능.

### 에이전트팀 활용 기준
- **/new-project Phase 3**: 독립 태스크 3개 이상이면 에이전트팀 병렬 개발, 2개 이하면 순차 개발
- **/bugfix**: 복잡 버그 감지 시 경쟁 가설 디버깅 (에이전트팀), 단순 버그는 기존 /fix
- **/team-review**: 대규모/고위험 변경에만 사용, 단순 변경은 서브에이전트 리뷰
- **/qa-swarm**: 테스트 스위트가 다양한 프로젝트에만 사용, 소규모는 /test

## 에이전트 & 스킬 Best Practices / Anti-Patterns

@docs/research-claude-agent-skill-best-practices-antipatterns-20260212.md

## 스킬 작성 규칙

스킬 파일은 `.claude/skills/<skill-name>/SKILL.md` 경로에 생성합니다.

필수 frontmatter 필드:
- `name`: 스킬 식별자
- `description`: 스킬 용도 및 트리거 조건
- `context: fork` - 모든 스킬에 필수

선택적 필드:
- `agent` - 사용할 에이전트 유형. 도구 권한은 에이전트가 관리한다.
