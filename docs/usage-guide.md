# hoodcat-harness 사용 가이드

Claude Code 멀티에이전트 시스템 v2의 사용법을 설명합니다.

## 개요

이 프로젝트는 Claude Code의 커스텀 스킬과 에이전트를 조합하여 소프트웨어 개발 워크플로우를 자동화합니다. 스킬 13개와 에이전트 4개가 협력하여 기획부터 배포까지 논스탑으로 진행합니다.

## 새 프로젝트에 적용하기

이 harness를 다른 프로젝트에서 사용하려면 `.claude/` 디렉토리를 복사합니다:

```bash
cp -r /path/to/hoodcat-harness/.claude /your/project/.claude
```

필요한 것:
- `jq` 설치 (Sisyphus 강제속행에 필요)
- Claude Code CLI

## 스킬 목록

### 워크플로우 스킬 (5개)

복잡한 작업을 여러 Phase로 나누어 논스탑 실행합니다. Sisyphus 메커니즘으로 중간에 멈추지 않습니다.

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

### 내부 스킬 (1개)

| 스킬 | 용도 |
|------|------|
| `/fix` | 버그 진단+패치 (사용자 직접 호출 불가, `/bugfix`와 `/hotfix`가 내부적으로 호출) |

## 에이전트 목록

4개의 전문 에이전트가 스킬 내부에서 자동으로 호출됩니다.

| 에이전트 | 역할 | 호출 시점 |
|----------|------|----------|
| **navigator** | 코드베이스 탐색, 파일 매핑, 영향 범위 파악 | `/implement`, `/fix` 시작 시 |
| **architect** | 아키텍처 리뷰 (구조, 확장성, 기술 스택) | `/blueprint` 산출물 리뷰, 큰 변경 시 |
| **reviewer** | 코드 품질 리뷰 (가독성, 일관성, 에러 처리) | `/implement`, `/fix` 완료 후 |
| **security** | 보안 리뷰 (OWASP Top 10, 인증, 입력 검증) | `/hotfix`, 인증/보안 코드 변경 시 |

에이전트는 PASS / WARN / BLOCK 판정을 내립니다:
- **PASS**: 이상 없음, 다음 Phase로 진행
- **WARN**: 경고 사항 있지만 진행 가능
- **BLOCK**: 수정 필요, 최대 2회 재시도 후에도 BLOCK이면 사용자에게 판단 요청

## 워크플로우 흐름도

### `/new-project` (가장 큰 워크플로우)

```
Phase 0: Sisyphus 활성화
    │
Phase 1: 기획
    │   /blueprint → architect 리뷰
    │
Phase 2: 기술조사 (필요시)
    │   /deepresearch → architect 리뷰
    │
Phase 3: 개발
    │   tasks.md의 각 태스크:
    │     /implement → reviewer 리뷰 (± security 리뷰)
    │
Phase 4: QA
    │   /test → 실패 시 /fix → 재테스트
    │
Phase 5: 배포 (선택)
    │   /deploy → security 리뷰
    │
Sisyphus 비활성화 → 완료 보고
```

### `/implement` (단일 기능 구현)

```
Phase 0: Sisyphus 활성화
    │
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
Sisyphus 비활성화 → 완료 보고
```

### `/bugfix` (버그 수정)

```
Phase 0: Sisyphus 활성화
    │
Phase 1: 진단 + 수정
    │   /fix (navigator → 원인 진단 → 패치)
    │
Phase 2: 리뷰
    │   reviewer
    │
Phase 3: 검증
    │   /test --regression
    │
Sisyphus 비활성화 → 완료 보고
```

### `/hotfix` (긴급 보안 수정)

```
Phase 0: Sisyphus 활성화
    │
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
Sisyphus 비활성화 → 완료 보고
```

### `/improve` (기능 개선)

```
Phase 0: Sisyphus 활성화
    │
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
Sisyphus 비활성화 → 완료 보고
```

## Sisyphus 강제속행 메커니즘

워크플로우 스킬은 모든 Phase를 완료할 때까지 자동으로 진행됩니다.

### 동작 원리
1. 워크플로우 시작 시 `.claude/flags/sisyphus.json`의 `active`를 `true`로 설정
2. Claude Code가 중간에 멈추려 하면 Stop Hook이 차단하고 다음 Phase로 유도
3. 모든 Phase 완료 후 `active`를 `false`로 설정하여 정상 종료

### 안전장치
- **maxIterations**: 기본 15회 (new-project는 20회), 도달 시 강제 종료
- **수동 비활성화**: 워크플로우를 즉시 중단해야 할 때

```bash
jq '.active=false | .phase="manual-stopped"' \
  .claude/flags/sisyphus.json > /tmp/sisyphus.tmp && \
  mv /tmp/sisyphus.tmp .claude/flags/sisyphus.json
```

### 검증 규칙
- 빌드/테스트 결과는 실제 명령어의 exit code로만 판단
- 에이전트의 텍스트 보고("통과했습니다")를 신뢰하지 않음

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

# 보안 스캔
/security-scan

# 커밋
/commit
```

## 디렉토리 구조

```
.claude/
├── agents/                    # 에이전트 정의 (4개)
│   ├── architect.md
│   ├── navigator.md
│   ├── reviewer.md
│   └── security.md
├── skills/                    # 스킬 정의 (13개)
│   ├── bugfix/SKILL.md
│   ├── commit/SKILL.md
│   ├── decide/SKILL.md
│   ├── deploy/SKILL.md
│   ├── blueprint/SKILL.md
│   ├── deepresearch/SKILL.md
│   ├── fix/SKILL.md
│   ├── hotfix/SKILL.md
│   ├── implement/SKILL.md
│   ├── improve/SKILL.md
│   ├── new-project/SKILL.md
│   ├── security-scan/SKILL.md
│   └── test/SKILL.md
├── hooks/                     # Stop Hook 스크립트
│   ├── sisyphus-gate.sh       # 강제속행 게이트
│   ├── subagent-monitor.sh    # 서브에이전트 로깅
│   └── verify-build-test.sh   # 빌드/테스트 검증
├── flags/
│   └── sisyphus.json          # 논스탑 상태 플래그
├── rules/                     # 안티패턴 규칙
│   ├── antipatterns-python.md
│   ├── antipatterns-typescript.md
│   └── antipatterns-general.md
└── settings.local.json        # Hook 설정 (gitignored)
```
