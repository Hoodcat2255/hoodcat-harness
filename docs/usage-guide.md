# hoodcat-harness 사용 가이드

Claude Code 멀티에이전트 시스템 v3의 사용법을 설명합니다.

## 개요

이 프로젝트는 Claude Code의 커스텀 스킬과 에이전트를 조합하여 소프트웨어 개발 워크플로우를 자동화합니다. 스킬 15개와 에이전트 5개가 협력하여 기획부터 배포까지 진행합니다.

메인 에이전트는 순수한 오케스트레이터로, 사용자 의도를 파악하여 적절한 스킬을 디스패치합니다. 모든 스킬은 서브에이전트에서 격리 실행됩니다.

## 새 프로젝트에 적용하기

이 harness를 다른 프로젝트에서 사용하려면 `.claude/` 디렉토리를 복사합니다:

```bash
cp -r /path/to/hoodcat-harness/.claude /your/project/.claude
```

필요한 것:
- `jq` 설치 (품질 게이트 훅에 필요)
- Claude Code CLI

## 스킬 목록

### 워크플로우 스킬 (5개)

복잡한 작업을 여러 Phase로 나누어 서브에이전트에서 자율 실행합니다. `agent: workflow` 사용.

| 스킬 | 호출 | 용도 |
|------|------|------|
| `/new-project` | "새 프로젝트", "처음부터 만들어" | 기획→조사→개발→QA→배포 전체 흐름 |
| `/implement` | "구현해줘", "만들어줘", "코드 작성" | 단일 기능/태스크 구현 |
| `/bugfix` | "고쳐줘", "버그 고쳐", "에러 해결" | 버그 진단→수정→리뷰→검증 |
| `/improve` | "개선해줘", "업그레이드", "기능 추가" | 기존 기능 개선/확장 |
| `/hotfix` | "보안 수정", "긴급 수정", "취약점 패치" | 보안 취약점/긴급 이슈 수정 |

### 조사/기획 스킬 (3개)

| 스킬 | 호출 | 용도 |
|------|------|------|
| `/deepresearch` | "조사해줘", "찾아봐", "리서치" | 주제별 심층 자료조사 → `docs/research-*.md` 저장 |
| `/blueprint` | "계획 세워줘", "설계해줘" | 요구사항 정의, 아키텍처, 태스크 분해 → `docs/plans/` 저장 |
| `/decide` | "판단해줘", "비교해줘", "추천해줘" | 근거 기반 의사결정 → `docs/decide-*.md` 저장 |

### 유틸리티 스킬 (4개)

| 스킬 | 호출 | 용도 |
|------|------|------|
| `/test` | "테스트 작성", "테스트 돌려" | 테스트 작성/실행 (`--unit`, `--e2e`, `--regression`) |
| `/commit` | "커밋해줘", "커밋" | 변경사항 분석 후 Conventional Commits 형식 커밋 |
| `/deploy` | "배포 설정", "CI/CD 설정" | Dockerfile, CI/CD, 환경변수 문서 생성 |
| `/security-scan` | "보안 스캔", "취약점 검사" | 의존성 취약점 + 코드 보안 패턴 검사 |

### 팀 기반 스킬 (2개)

| 스킬 | 호출 | 용도 |
|------|------|------|
| `/team-review` | "멀티렌즈 리뷰", "팀 리뷰" | 3관점(품질/보안/아키텍처) 동시 리뷰 (비용: ~3배) |
| `/qa-swarm` | "QA 스웜", "전체 QA" | 병렬 QA (테스트/린트/빌드/보안 동시 실행, 비용: ~4배) |

### 내부 스킬 (1개)

| 스킬 | 용도 |
|------|------|
| `/fix` | 버그 진단+패치 (사용자 직접 호출 불가, `/bugfix`와 `/hotfix`가 내부적으로 호출) |

## 에이전트 목록

5개의 에이전트가 스킬 내부에서 자동으로 호출됩니다.

| 에이전트 | 역할 | 호출 시점 |
|----------|------|----------|
| **workflow** | 워크플로우 오케스트레이션 (Skill/Task/팀 도구) | 워크플로우 스킬 실행 시 자동 |
| **navigator** | 코드베이스 탐색, 파일 매핑, 영향 범위 파악 | `/implement`, `/fix` 시작 시 |
| **architect** | 아키텍처 리뷰 (구조, 확장성, 기술 스택) | `/blueprint` 산출물 리뷰, 큰 변경 시 |
| **reviewer** | 코드 품질 리뷰 (가독성, 일관성, 에러 처리) | `/implement`, `/fix` 완료 후 |
| **security** | 보안 리뷰 (OWASP Top 10, 인증, 입력 검증) | `/hotfix`, 인증/보안 코드 변경 시 |

에이전트는 PASS / WARN / BLOCK 판정을 내립니다:
- **PASS**: 이상 없음, 다음 Phase로 진행
- **WARN**: 경고 사항 있지만 진행 가능
- **BLOCK**: 수정 필요, 최대 2회 재시도 후에도 BLOCK이면 사용자에게 판단 요청

## 아키텍처

### 실행 모델

```
[사용자 입력]
     │
     ▼
[메인 에이전트: 오케스트레이터]
     │  - 사용자 의도 파악
     │  - Skill() 호출로 디스패치
     │  - 결과 요약/보고
     │
     ├── Skill("bugfix")      → fork (agent: workflow)
     ├── Skill("implement")   → fork (agent: workflow)
     ├── Skill("blueprint")   → fork (기본 에이전트)
     ├── Skill("test")        → fork (기본 에이전트)
     ├── Skill("deepresearch")→ fork (agent: general-purpose)
     └── ...
```

모든 스킬은 `context: fork`로 서브에이전트에서 격리 실행됩니다.
서브에이전트는 자체 컨텍스트에서 완료까지 자율 실행되므로, 별도의 강제속행 메커니즘이 불필요합니다.

### 에이전트 계층

```
레벨 0: 메인 에이전트 (오케스트레이터)
    │
    ├── 레벨 1: 워크플로우 스킬 (agent: workflow)
    │       └── 레벨 2: 워커 스킬 + 리뷰 에이전트
    │
    └── 레벨 1: 워커 스킬 (직접 호출 시)
            └── 레벨 2: 리뷰 에이전트
```

## 워크플로우 흐름도

### `/new-project` (가장 큰 워크플로우)

```
Phase 1: 기획
    │   /blueprint → architect 리뷰
    │
Phase 2: 기술조사 (필요시)
    │   /deepresearch → architect 리뷰
    │
Phase 3: 개발
    │   독립 태스크 3개+ → 에이전트팀 병렬 개발
    │   독립 태스크 2개- → /implement 순차 실행
    │   → reviewer 리뷰 (± security 리뷰)
    │
Phase 4: QA
    │   /test → 실패 시 /fix → 재테스트
    │
Phase 5: 배포 (선택)
    │   /deploy → security 리뷰
    │
완료 보고
```

### `/implement` (단일 기능 구현)

```
Phase 1: 컨텍스트 파악
    │   navigator → 관련 파일 매핑
    │
Phase 2: 브랜치 생성 (선택)
    │
Phase 3: 코드 작성
    │
Phase 4: 린트/포맷
    │
Phase 5: 테스트
    │   /test → 실패 시 /fix → 재테스트
    │
Phase 6: 리뷰
    │   reviewer (± security)
    │
완료 보고
```

### `/bugfix` (버그 수정)

```
Phase 1: 진단 + 수정
    │   단순 버그 → /fix
    │   복잡 버그 → 에이전트팀 경쟁 가설 디버깅
    │
Phase 2: 리뷰
    │   reviewer
    │
Phase 3: 검증
    │   /test --regression
    │
완료 보고
```

### `/hotfix` (긴급 보안 수정)

```
Phase 1: 심각도 평가
    │   security 에이전트 → Critical/High → 진행
    │                      → Medium/Low → /bugfix 전환 제안
    │
Phase 2: 수정
    │   /fix
    │
Phase 3: 이중 리뷰
    │   security + reviewer (병렬)
    │
Phase 4: 검증
    │   /test --regression (± /security-scan)
    │
완료 보고
```

### `/improve` (기능 개선)

```
Phase 1: 분석
    │   navigator → 영향 범위 파악
    │   큰 변경? → Phase 1.5 기획
    │   작은 변경? → Phase 2로 직행
    │
Phase 1.5: 기획 (큰 변경만)
    │   /blueprint → architect 리뷰
    │
Phase 2: 개발
    │   /implement → reviewer 리뷰
    │
Phase 3: 검증
    │   /test --regression
    │
완료 보고
```

## 검증 규칙

- 빌드/테스트 결과는 실제 명령어의 exit code로만 판단
- 에이전트의 텍스트 보고("통과했습니다")를 신뢰하지 않음
- `.claude/hooks/verify-build-test.sh`로 프로젝트별 빌드/테스트 자동 실행 가능

## 사용 예시

```
# 새 프로젝트 생성
/new-project "Python CLI로 RSS 피드를 수집하는 도구"

# 기능 구현
/implement "사용자 인증 미들웨어 추가"

# 버그 수정
/bugfix "로그인 시 비밀번호 검증이 안 되는 문제"

# 기능 개선
/improve "검색 기능에 퍼지 매칭 추가"

# 보안 긴급 수정
/hotfix "SQL 인젝션 취약점 발견"

# 리서치
/deepresearch "WebSocket vs SSE 실시간 통신 비교"

# 의사결정
/decide "상태관리 라이브러리: Redux vs Zustand vs Jotai"

# 멀티렌즈 리뷰 (대규모 변경에만)
/team-review "인증 모듈 전면 리팩토링"

# 병렬 QA (다양한 테스트 스위트가 있는 프로젝트)
/qa-swarm "./my-project"

# 보안 스캔
/security-scan

# 커밋
/commit
```

## 디렉토리 구조

```
.claude/
├── agents/                    # 에이전트 정의 (5개)
│   ├── workflow.md            # 워크플로우 오케스트레이터
│   ├── architect.md           # 아키텍처 리뷰
│   ├── navigator.md           # 코드베이스 탐색
│   ├── reviewer.md            # 코드 품질 리뷰
│   └── security.md            # 보안 리뷰
├── skills/                    # 스킬 정의 (15개, 전부 context: fork)
│   ├── bugfix/SKILL.md        # 워크플로우 (agent: workflow)
│   ├── hotfix/SKILL.md        # 워크플로우 (agent: workflow)
│   ├── implement/SKILL.md     # 워크플로우 (agent: workflow)
│   ├── improve/SKILL.md       # 워크플로우 (agent: workflow)
│   ├── new-project/SKILL.md   # 워크플로우 (agent: workflow)
│   ├── fix/SKILL.md           # 워커
│   ├── test/SKILL.md          # 워커
│   ├── blueprint/SKILL.md     # 워커
│   ├── commit/SKILL.md        # 워커
│   ├── deploy/SKILL.md        # 워커
│   ├── security-scan/SKILL.md # 워커
│   ├── deepresearch/SKILL.md  # 워커 (agent: general-purpose)
│   ├── decide/SKILL.md        # 워커 (agent: general-purpose)
│   ├── team-review/SKILL.md   # 워커 (팀 기반)
│   └── qa-swarm/SKILL.md      # 워커 (팀 기반)
├── hooks/                     # 훅 스크립트
│   ├── subagent-monitor.sh    # 서브에이전트 종료 로깅
│   ├── verify-build-test.sh   # 빌드/테스트 검증 유틸
│   ├── task-quality-gate.sh   # 에이전트팀 태스크 완료 검증
│   └── teammate-idle-check.sh # 팀원 유휴 상태 검사
├── rules/                     # 안티패턴 규칙
│   ├── antipatterns-python.md
│   ├── antipatterns-typescript.md
│   └── antipatterns-general.md
└── settings.local.json        # Hook 설정 (gitignored)
```

## 버전 히스토리

### v3 (2026-02-12) - 전체 Fork 전환
- 모든 스킬에 `context: fork` 적용
- 메인 에이전트를 순수 오케스트레이터로 전환
- `workflow` 에이전트 신규 추가
- Sisyphus 강제속행 메커니즘 제거

### v2 (2026-02-08~11) - 멀티에이전트 시스템 구축
- 에이전트 4개 + 스킬 13개 체계 구축
- DO/REVIEW 패턴 도입
- Sisyphus 강제속행 메커니즘 구현
- 에이전트팀 기반 스킬 (team-review, qa-swarm) 추가
- 스킬 아키텍처 재구조화 (워크플로우/워커 분리)
