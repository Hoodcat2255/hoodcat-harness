# hoodcat-harness

Claude Code용 멀티에이전트 시스템. 8개 에이전트와 11개 스킬을 프로젝트에 설치하여 Claude Code의 기능을 확장한다.

## 요구 사항

| 의존성 | 용도 | 필수 |
|---------|------|------|
| [Claude Code](https://claude.ai/code) | 에이전트/스킬 실행 환경 | O |
| `rsync` | 파일 동기화 (`harness install/update`) | O |
| `git` | 브랜치 생성, 커밋 | 권장 |
| `jq` | 훅에서 JSON 파싱 (미설치 시 훅이 graceful skip) | 권장 |

macOS와 Linux 모두 지원한다.

## 설치

```bash
# 1. 저장소 클론
git clone git@github.com:Hoodcat2255/hoodcat-harness.git
cd hoodcat-harness

# 2. harness CLI를 PATH에 등록 (심링크 + 탭 완성)
./install.sh

# 3. 대상 프로젝트에 에이전트 시스템 설치
harness install ~/Projects/my-project
```

`install.sh`는 다음을 설치한다:
- `~/.local/bin/harness` — `harness.sh`로의 심링크
- bash 완성 (`~/.local/share/bash-completion/completions/harness`)
- zsh 완성 (`~/.zfunc/_harness`)

## 사용법

```bash
harness install [dir]    # 대상 디렉토리에 설치 (기본: 현재 디렉토리)
harness update  [dir]    # 최신 버전으로 업데이트
harness status  [dir]    # 설치 상태 확인
harness delete  [dir]    # 설치된 harness 삭제
```

### 옵션

| 옵션 | 설명 |
|------|------|
| `-f`, `--force`, `-y` | 확인 프롬프트 스킵 |
| `-n`, `--dry-run` | 실제 변경 없이 표시만 |
| `-v`, `--verbose` | 상세 로그 출력 |

### 예시

```bash
# 현재 디렉토리에 설치
cd ~/Projects/my-app
harness install

# 경로 지정 + 자동 확인
harness install ~/Projects/my-app -f

# 변경 사항 미리보기
harness update ~/Projects/my-app --dry-run

# 상태 확인
harness status ~/Projects/my-app
```

## 아키텍처

2-tier, Orchestrator-Driven 아키텍처를 사용한다.

```
Tier 1: Main Agent (순수 디스패처)
  ├─ 슬래시 커맨드 → 해당 스킬 직접 호출
  └─ 그 외 모든 요청 → Orchestrator에게 위임

Tier 2: Orchestrator + 워커 스킬 + 리뷰 에이전트
```

Main Agent는 코드를 직접 읽거나 분석하지 않는다. 슬래시 커맨드만 해당 스킬로 직접 호출하고, 그 외 모든 자연어 요청은 Orchestrator에게 위임한다. Orchestrator는 요구를 분석하여 스킬 카탈로그에서 스킬을 선택하고, 순차/병렬로 조합하여 계획을 이행한다.

## 설치되는 항목

`harness install`은 대상 프로젝트의 `.claude/` 디렉토리에 다음을 복사한다:

### 에이전트 (8개)

| 에이전트 | 역할 |
|----------|------|
| `orchestrator` | 동적 계획 + 이행. 요구 분석, 스킬 조합, 적응적 실행 |
| `coder` | 코딩. 파일 읽기/쓰기, 빌드, 테스트 |
| `committer` | Git 작업. 변경 분석, 커밋 생성 (sonnet) |
| `researcher` | 리서치/기획. 웹 검색, Context7, 문서 작성 |
| `reviewer` | 코드 품질 리뷰. 유지보수성, 패턴 일관성 |
| `security` | 보안 리뷰. OWASP Top 10, 인증/인가 |
| `architect` | 아키텍처 리뷰. 구조 적합성, 확장성 |
| `navigator` | 코드베이스 탐색. 파일 매핑, 영향 범위 파악 |

### 스킬 (11개)

모든 스킬은 `context: fork`로 서브에이전트에서 격리 실행된다.

| 스킬 | Agent | 설명 |
|------|-------|------|
| `/code` | coder | 코드 작성, 수정, 진단, 패치 |
| `/test` | coder | 테스트 작성 및 실행 |
| `/blueprint` | researcher | 요구사항 분석, 아키텍처 설계, 태스크 분해 |
| `/commit` | committer | 변경 분석, 커밋 메시지 생성 |
| `/deploy` | coder | 배포 설정 (Dockerfile, CI/CD) |
| `/security-scan` | coder | 의존성 감사 + 코드 보안 패턴 검사 |
| `/deepresearch` | researcher | 웹 검색 + Context7 기반 심층 조사 |
| `/decide` | researcher | 옵션 비교, 트레이드오프 분석, 권고 |
| `/scaffold` | coder | 새 스킬/에이전트 파일 자동 생성 |
| `/team-review` | coder | 3관점 동시 리뷰: 품질/보안/아키텍처 (에이전트팀) |
| `/qa-swarm` | coder | 병렬 QA: 테스트/린트/보안 동시 실행 (에이전트팀) |

### 훅 (9개)

| 훅 | 이벤트 | 설명 |
|----|--------|------|
| `verify-build-test.sh` | (유틸리티) | 프로젝트별 빌드/테스트 검증 스크립트 |
| `task-quality-gate.sh` | TaskCompleted | 에이전트팀 태스크 완료 시 빌드/테스트 자동 검증 |
| `teammate-idle-check.sh` | TeammateIdle | 미완료 태스크가 있는 팀원 유휴 시 작업 재개 유도 |
| `subagent-monitor.sh` | SubagentStop | 서브에이전트 종료 로깅 |
| `shared-context-inject.sh` | SubagentStart | 이전 에이전트 작업 요약을 컨텍스트로 주입 |
| `shared-context-collect.sh` | SubagentStop | 에이전트 작업 결과 자동 수집 |
| `shared-context-cleanup.sh` | SessionStart | TTL 만료된 공유 컨텍스트 세션 정리 |
| `shared-context-finalize.sh` | SessionEnd | 세션 메트릭 기록 |
| `test-shared-context.sh` | (테스트) | 공유 컨텍스트 시스템 동작 검증용 |

### 기타

| 항목 | 설명 |
|------|------|
| `.claude/rules/` | 언어별 anti-pattern 규칙 (general, python, typescript) |
| `.claude/harness.md` | 공통 지침 파일 (모든 프로젝트에 적용) |
| `.claude/shared-context-config.json` | 공유 컨텍스트 시스템 설정 (TTL, 필터 등) |
| `.claude/settings.local.json` | 훅 등록 + 상태표시줄 설정 |
| `.claude/statusline.sh` | 모델, 컨텍스트, git 상태 표시 |

`CLAUDE.md`는 프로젝트에 없으면 자동 생성하며, 최상단에 `@.claude/harness.md` import를 주입한다. 이미 존재하면 import만 최상단으로 이동시킨다.

## 제거

```bash
# 대상 프로젝트에서 harness 제거
harness delete ~/Projects/my-app

# harness CLI 자체 제거 (심링크 + 탭 완성)
./uninstall.sh
```

## 디렉토리 구조

```
hoodcat-harness/
├── harness.sh              # 메인 CLI
├── install.sh              # CLI 설치 (심링크 + 탭 완성)
├── uninstall.sh            # CLI 제거
├── completions/
│   ├── harness.bash        # bash 탭 완성
│   └── harness.zsh         # zsh 탭 완성
├── .claude/
│   ├── agents/             # 에이전트 정의 (8개)
│   ├── skills/             # 스킬 정의 (11개)
│   ├── rules/              # 코드 규칙
│   ├── hooks/              # 훅 스크립트 (9개)
│   ├── agent-memory/       # 에이전트별 영속 메모리
│   ├── shared-context-config.json  # 공유 컨텍스트 설정
│   ├── harness.md          # 공통 지침
│   ├── settings.local.json # 훅/상태표시줄 설정
│   └── statusline.sh       # 상태표시줄
├── docs/                   # 리서치 결과 및 계획 문서
└── CLAUDE.md               # 프로젝트 지침 (이 저장소용)
```
