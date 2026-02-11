# hoodcat-harness

Claude Code용 멀티에이전트 시스템. 8개 에이전트와 15개 스킬을 프로젝트에 설치하여 Claude Code의 기능을 확장한다.

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

## 설치되는 항목

`harness install`은 대상 프로젝트의 `.claude/` 디렉토리에 다음을 복사한다:

### 에이전트 (8개)

| 에이전트 | 역할 |
|----------|------|
| `workflow` | 워크플로우 오케스트레이션. 다중 Phase 자율 실행 |
| `researcher` | 리서치/기획. 웹 검색, Context7, 문서 작성 |
| `coder` | 코딩. 파일 읽기/쓰기, 빌드, 테스트 |
| `committer` | Git 작업. 변경 분석, 커밋 생성 (sonnet) |
| `reviewer` | 코드 품질 리뷰. 유지보수성, 패턴 일관성 |
| `security` | 보안 리뷰. OWASP Top 10, 인증/인가 |
| `architect` | 아키텍처 리뷰. 구조 적합성, 확장성 |
| `navigator` | 코드베이스 탐색. 파일 매핑, 영향 범위 파악 |

### 스킬 (15개)

**워크플로우** (다단계 자율 실행, `agent: workflow`):

| 스킬 | 트리거 | 설명 |
|------|--------|------|
| `/bugfix` | 버그 수정 요청 | 진단 → 수정 → 리뷰 → 회귀 테스트 |
| `/hotfix` | 긴급/보안 수정 | 보안 평가 → 수정 → 이중 리뷰 |
| `/implement` | 기능 구현 요청 | 탐색 → 구현 → 리뷰 → 테스트 |
| `/improve` | 기존 기능 개선 | 영향 분석 → 개선 → 회귀 테스트 |
| `/new-project` | 새 프로젝트 생성 | 기획 → 리서치 → 구현 → 검증 |

**워커** (단일 작업 실행):

| 스킬 | 트리거 | 설명 |
|------|--------|------|
| `/fix` | (내부용) | 버그 패치 + 테스트. bugfix/hotfix에서 호출 |
| `/test` | 테스트 요청 | 테스트 작성 및 실행 |
| `/blueprint` | 설계/기획 요청 | 요구사항 분석, 아키텍처 설계 |
| `/commit` | 커밋 요청 | 변경 분석, 커밋 메시지 생성 |
| `/deploy` | 배포 요청 | 배포 실행 |
| `/security-scan` | 보안 스캔 요청 | 의존성 감사 + 코드 보안 패턴 검사 |
| `/deepresearch` | 조사/리서치 요청 | 웹 검색 + Context7 기반 심층 조사 |
| `/decide` | 의사결정 요청 | 옵션 비교, 트레이드오프 분석, 권고 |
| `/team-review` | 멀티렌즈 리뷰 | 3인 동시 독립 리뷰 (에이전트팀) |
| `/qa-swarm` | 종합 QA | 병렬 테스트/린트/보안 스캔 (에이전트팀) |

### 기타

| 항목 | 설명 |
|------|------|
| `.claude/rules/` | 언어별 anti-pattern 규칙 (general, python, typescript) |
| `.claude/hooks/` | 품질 게이트 훅 4개 |
| `.claude/settings.local.json` | 훅 등록 + 상태표시줄 설정 |
| `.claude/statusline.sh` | 모델, 컨텍스트, git 상태 표시 |

`CLAUDE.md`는 프로젝트마다 다르므로 복사하지 않는다. 대상 프로젝트에 맞게 직접 작성해야 한다.

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
│   ├── skills/             # 스킬 정의 (15개)
│   ├── rules/              # 코드 규칙
│   ├── hooks/              # 품질 게이트 훅
│   ├── settings.local.json # 훅/상태표시줄 설정
│   └── statusline.sh       # 상태표시줄
├── docs/                   # 리서치 결과 및 계획 문서
└── CLAUDE.md               # 프로젝트 지침 (이 저장소용)
```
