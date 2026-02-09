# harness 설치/업데이트를 원격 저장소 기준으로 전환하는 방안 판단

> 판단일: 2026-02-09

## 결정 요약

**권고**: **아직 전환하지 마라. 현재의 로컬 clone + rsync 방식을 유지하되, `harness update`에 `git pull` 자동 실행을 추가하는 것만으로 충분하다.**
**확신도**: 높음 - 현재 사용 패턴(개인 1인, private repo, 단일 머신)에서 원격 기반 전면 전환의 이점이 비용을 정당화하지 못한다.

## 결정 대상

현재 `harness.sh`는 **로컬에 clone된 hoodcat-harness 저장소**를 소스로 사용하여 대상 프로젝트에 rsync로 파일을 복사한다. 이를 **원격 GitHub 저장소에서 직접 fetch/clone하여 설치/업데이트**하는 방식으로 전환해야 하는가?

## 현재 상태 분석

```
워크플로우:
1. ~/Projects/hoodcat-harness (로컬 clone, 개발용)
2. harness.sh install ~/Projects/target-project
   → rsync로 .claude/{agents,skills,rules,hooks}/ 복사
3. harness.sh update ~/Projects/target-project
   → rsync --delete로 동기화, meta.json으로 버전 추적

제약:
- 저장소: PRIVATE (git@github.com:Hoodcat2255/hoodcat-harness.git)
- 사용자: 1인 (본인)
- 머신: 1대
- SSH 키: 이미 설정됨
```

## 후보 분석

### A. 현행 유지 (로컬 clone + rsync)

```
git pull (수동) → harness update <dir>
```

- **장점**:
  - 이미 동작하는 코드가 있음 (harness.sh 723줄, 완성도 높음)
  - 오프라인에서도 동작
  - 네트워크 오류에 영향받지 않음
  - git 상태를 사용자가 직접 통제 (어떤 커밋을 배포할지 선택 가능)
  - rsync의 검증된 파일 동기화 신뢰성
- **단점**:
  - 업데이트 시 2단계 필요: `cd hoodcat-harness && git pull` → `harness update <dir>`
  - 소스를 pull하는 것을 잊을 수 있음
- **적합한 경우**: 현재 상황 (1인, 1머신, 개발 중인 도구)

### B. harness update에 git pull 통합

```
harness update <dir>
  → 내부적으로 git -C $SCRIPT_DIR pull --ff-only
  → 이후 기존 rsync 로직 실행
```

- **장점**:
  - 1단계로 축소: `harness update <dir>` 한 번이면 최신 소스 반영
  - 기존 코드 변경 최소화 (cmd_update에 5-10줄 추가)
  - `--ff-only`로 안전한 pull만 허용 (충돌 시 중단)
  - 오프라인 시 graceful degradation (pull 실패해도 로컬 버전으로 진행 가능)
  - SCRIPT_DIR이 git repo 내부이므로 remote 정보 자동 참조
- **단점**:
  - 로컬에 uncommitted 변경이 있으면 pull 실패 가능
  - 네트워크 의존성 추가 (선택적이지만)
- **적합한 경우**: 현재 상황에서 편의성만 개선하고 싶을 때

### C. 완전한 원격 설치 (curl pipe bash / git clone 방식)

```
# 신규 설치
curl -fsSL https://raw.githubusercontent.com/.../install.sh | bash -s -- <dir>

# 또는
harness install --remote <dir>
  → git clone → rsync → cleanup
```

- **장점**:
  - 새 머신에서 로컬 clone 없이 바로 설치 가능
  - dotfiles 도구들(chezmoi, yadm)이 채택한 검증된 패턴
  - 배포가 깔끔함
- **단점**:
  - **PRIVATE 저장소**: curl + raw URL 접근 불가. SSH 키 또는 PAT 필요
  - curl pipe bash는 보안 우려 (특히 private repo에서는 PAT 노출 위험)
  - 설치 후 업데이트를 위해 clone된 소스가 어딘가에 필요 → 결국 로컬 clone과 동일
  - 단일 명령 설치를 위해 상당한 코드 추가 필요 (임시 디렉토리 관리, cleanup, 에러 처리)
  - 1인 사용에 과도한 엔지니어링
- **적합한 경우**: public repo, 팀 배포, 멀티 머신 환경

### D. Git submodule 방식

```
cd ~/Projects/target-project
git submodule add git@github.com:Hoodcat2255/hoodcat-harness.git .harness
# .claude/ 로 symlink
```

- **장점**:
  - 버전이 대상 프로젝트의 git history에 추적됨
  - `git submodule update --remote`로 업데이트
  - 정확한 버전 pinning 가능
- **단점**:
  - `.claude/` 디렉토리가 symlink이면 Claude Code가 인식하는지 검증 필요
  - submodule은 UX가 나쁨 (clone 시 --recursive, checkout 시 추가 명령)
  - 모든 대상 프로젝트가 git repo여야 함
  - harness 자체의 git history/docs/megaman 등 불필요한 파일까지 포함됨
- **적합한 경우**: 팀 프로젝트에서 harness 버전을 엄격히 관리해야 할 때

### E. chezmoi/yadm 등 전용 도구 활용

- **장점**:
  - 검증된 도구, 크로스 플랫폼, 템플릿 지원
  - 원격 설치가 기본 기능
- **단점**:
  - 용도가 다름: dotfiles 관리 도구 vs 프로젝트별 .claude/ 설정 배포
  - `.claude/` 구조가 $HOME이 아닌 각 프로젝트 루트에 배포되어야 함 → 일반적인 dotfiles 패턴과 불일치
  - 새 외부 의존성 추가
  - 학습 비용 대비 이점 불명확
- **적합한 경우**: $HOME 기반 dotfiles 관리가 주 목적일 때

## 평가 매트릭스

| 기준 | A. 현행 | B. pull 통합 | C. 원격 설치 | D. submodule | E. 전용 도구 |
|------|---------|-------------|-------------|-------------|-------------|
| 구현 비용 | 0 | 낮음 (5-10줄) | 높음 (100줄+) | 중간 (50줄) | 높음 (도구 학습) |
| 편의성 | 보통 | 높음 | 높음 | 낮음 | 높음 |
| private repo 호환 | O | O | 제한적 | O | O |
| 오프라인 동작 | O | O (fallback) | X | 부분적 | 부분적 |
| 멀티 머신 확장 | 낮음 | 낮음 | 높음 | 중간 | 높음 |
| 기존 코드 유지 | 100% | 95%+ | 50% 리팩터링 | 별도 구조 | 완전 교체 |
| 버전 통제력 | 높음 | 높음 | 중간 | 높음 | 중간 |
| 안정성/신뢰성 | 높음 | 높음 | 중간 | 중간 | 높음 |

## 트레이드오프

- **B(pull 통합)를 선택하면**: 최소 비용으로 "update 한 번이면 끝" UX를 얻지만, 로컬 clone 의존은 그대로다. 1인 사용에서는 이것으로 충분하다.
- **C(원격 설치)를 선택하면**: 새 머신 셋업이 1줄로 가능해지지만, private repo 인증 처리와 상당한 코드 추가가 필요하다. 현재 1머신 환경에서 이 이점을 누릴 기회가 없다.
- **D(submodule)를 선택하면**: 버전 추적이 엄밀해지지만, submodule의 나쁜 UX와 Claude Code의 symlink 호환성 불확실성이 리스크다.
- **E(전용 도구)를 선택하면**: 검증된 도구의 안정성을 얻지만, 프로젝트별 `.claude/` 배포라는 비표준 사용 패턴에 끼워 맞추는 비용이 크다.

## 최종 권고

### 주요 권고: B (harness update에 git pull 통합)

**이유**:
1. 현재의 문제는 "업데이트가 2단계"라는 것뿐이다. 이것은 5-10줄로 해결된다.
2. private repo이므로 원격 curl 설치는 인증 처리가 복잡해진다.
3. 1인/1머신에서 완전한 원격 설치 인프라는 과도한 엔지니어링이다.
4. 기존 harness.sh의 검증된 코드(rsync, meta 추적, diff 표시)를 100% 유지할 수 있다.

**구현 예시**:

```bash
# cmd_update() 시작 부분에 추가
sync_source_repo() {
    if ! command -v git &>/dev/null; then return 0; fi
    if ! git -C "$SCRIPT_DIR" rev-parse --is-inside-work-tree &>/dev/null 2>&1; then return 0; fi

    log_info "소스 저장소 동기화 중..."
    if git -C "$SCRIPT_DIR" pull --ff-only 2>/dev/null; then
        log_info "소스 저장소 최신화 완료"
    else
        log_warn "소스 저장소 pull 실패 (로컬 변경 또는 네트워크 오류). 현재 버전으로 계속합니다."
    fi
}
```

### 조건부 권고 (미래)

상황이 바뀌면 재평가:

| 상황 변화 | 권고 전환 |
|-----------|----------|
| 2번째 머신이 생김 | B를 유지하되, 새 머신에서 `git clone` + `harness self-install` 문서화 |
| 팀원이 생김 | C(원격 설치) 또는 repo를 public으로 전환 검토 |
| 프로젝트 10개+ 관리 | `harness update-all` 명령 추가 검토 |
| harness가 안정화됨 (변경 빈도 감소) | 현행 유지로도 충분 |

### "정답 없음" 케이스

원격 설치가 **절대 안 되는 것은 아니다**. SSH 키가 설정된 환경에서는 `git clone git@github.com:...`으로 private repo도 clone 가능하다. 다만 현재 상황에서 그 방향으로 투자하는 것이 시간 대비 효율이 낮다는 판단이다.

## 출처

- [dotfiles.github.io - 튜토리얼](https://dotfiles.github.io/tutorials/)
- [chezmoi - 왜 chezmoi를 쓰는가](https://www.chezmoi.io/why-use-chezmoi/)
- [chezmoi 비교 테이블](https://www.chezmoi.io/comparison-table/)
- [Atlassian - Bare Git Repository로 dotfiles 관리](https://www.atlassian.com/git/tutorials/dotfiles)
- [Git Submodules 가이드](https://git-scm.com/book/en/v2/Git-Tools-Submodules)
- [Git Submodules: 패키지 매니저가 안 될 때](https://cleancoders.com/blog/2026-01-16-git-submodules-for-when-a-package-manager-wont-cut-it)
- [gitignore + symlinks: 가벼운 submodule 대안](https://razzi.abuissa.net/2023/10/11/gitignore-and-symlinks/)
- [GitHub 커뮤니티 - git cloning vs copying](https://github.com/orgs/community/discussions/53148)
- [curl pipe bash 보안 문제 5가지 대응법 - Chef](https://www.chef.io/blog/5-ways-to-deal-with-the-install-sh-curl-pipe-bash-problem)
- [dotfiles 도구 비교 - BigGo News](https://biggo.com/news/202412191324_dotfile-management-tools-comparison)
