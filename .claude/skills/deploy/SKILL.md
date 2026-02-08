---
name: deploy
description: |
  Generates deployment configuration files (Dockerfile, CI/CD, env docs).
  Use when the user wants to set up deployment for a project.
  Triggers on: "배포 설정", "배포해줘", "deploy", "CI/CD 설정",
  or any request to create deployment configs, Dockerfiles, or CI pipelines.
argument-hint: "<배포 환경: docker, github-actions, vercel 등>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Edit, Glob, Grep, Bash, Task
---

# Deploy Skill

## 입력

$ARGUMENTS: 배포 대상 환경. 예: docker, github-actions, vercel, fly.io, aws 등.
비어있으면 프로젝트 타입에 따라 자동 선택.

## 프로세스

### 1. 프로젝트 타입 감지

navigator 에이전트로 프로젝트 구조를 파악한다:

```
Task(navigator): "배포 설정에 필요한 프로젝트 정보를 탐색하라: 언어, 프레임워크, 빌드 도구, 기존 배포 설정"
```

파악할 것:
- 언어/프레임워크 (package.json, Cargo.toml, pyproject.toml 등)
- 빌드 명령어 (build script, Makefile 등)
- 진입점 (main, index, app 파일)
- 기존 배포 설정 (Dockerfile, .github/workflows, vercel.json 등)

### 2. 배포 설정 파일 생성

$ARGUMENTS 또는 자동 감지된 환경에 맞춰 설정 파일을 생성한다:

#### Docker
```
생성 파일:
- Dockerfile (멀티스테이지 빌드, 프로덕션 최적화)
- .dockerignore (node_modules, .git, .env 등)
- docker-compose.yml (로컬 개발용, 선택)
```

#### GitHub Actions
```
생성 파일:
- .github/workflows/ci.yml (빌드 + 테스트)
- .github/workflows/deploy.yml (배포, 선택)
```

#### 기타 (Vercel, Fly.io 등)
```
해당 플랫폼의 설정 파일 생성
```

### 3. 환경 변수 정리

프로젝트에서 사용하는 환경 변수를 수집하고 정리한다:

```
검색: process.env, os.environ, env::var, os.Getenv 등
```

생성 파일:
- `.env.example` (비밀값 제외, 키와 설명만)

### 4. 배포 가이드 생성

`docs/deploy-guide.md`에 배포 방법을 문서화한다.

## 출력

```markdown
## 배포 설정 완료

### 생성된 파일
- `Dockerfile` - [설명]
- `.github/workflows/ci.yml` - [설명]
- `.env.example` - 환경 변수 N개 정리
- `docs/deploy-guide.md` - 배포 가이드

### 환경 변수
| 변수명 | 필수 | 설명 |
|--------|------|------|
| [NAME] | [Y/N] | [설명] |

### 다음 단계
1. [첫 번째 할 일]
2. [두 번째 할 일]
```

## REVIEW 연동

배포 설정 생성 후, security 에이전트에게 리뷰를 요청한다:

```
Task(security): "배포 설정 파일을 리뷰하라. 시크릿 노출, 불필요한 포트, 과도한 권한이 없는지 확인하라."
```

- PASS/WARN → 완료
- BLOCK → 수정 후 재리뷰
