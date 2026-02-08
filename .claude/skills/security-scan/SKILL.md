---
name: security-scan
description: |
  Scans code and dependencies for security vulnerabilities.
  Runs dependency audits and code-level security pattern checks.
  Triggers on: "보안 스캔", "보안 검사", "취약점 검사", "security-scan",
  or any request to scan for vulnerabilities or security issues.
argument-hint: "<대상 디렉토리 또는 파일 (기본: 프로젝트 루트)>"
user-invocable: true
context: fork
allowed-tools: Read, Write, Glob, Grep, Bash, Task
---

# Security Scan Skill

## 입력

$ARGUMENTS: 스캔 대상 디렉토리 또는 파일. 비어있으면 프로젝트 루트 전체.

## 프로세스

### 1. 프로젝트 타입 감지

루트 설정 파일로 프로젝트 타입을 판별한다:

```
감지 순서:
- package.json → Node.js (npm audit)
- pyproject.toml / requirements.txt → Python (pip audit)
- Cargo.toml → Rust (cargo audit)
- go.mod → Go (govulncheck)
- pom.xml / build.gradle → Java (dependency-check)
```

### 2. 의존성 취약점 검사

프로젝트 타입에 맞는 audit 도구를 실행한다:

```bash
# Node.js
npm audit --json 2>/dev/null || npx audit-ci --config /dev/null

# Python
pip audit 2>/dev/null || python -m pip_audit

# Rust
cargo audit 2>/dev/null

# Go
govulncheck ./... 2>/dev/null
```

도구가 설치되지 않은 경우 사용자에게 알리고 건너뛴다.

### 3. 코드 레벨 보안 패턴 검사

Grep으로 일반적인 보안 안티패턴을 검색한다:

```
검색 패턴:
- 하드코딩된 시크릿: API_KEY, SECRET, PASSWORD, TOKEN + 할당문
- SQL 인젝션: 문자열 연결로 쿼리 구성 (f-string, template literal, +)
- eval/exec 사용: eval(, exec(, Function(
- 안전하지 않은 역직렬화: pickle.loads, yaml.load (Loader 없이)
- 경로 조작: 사용자 입력이 파일 경로에 직접 사용
- 안전하지 않은 랜덤: Math.random() (보안 목적 사용 시)
```

### 4. 인증/인가 로직 검토

인증 관련 코드가 있으면 패턴을 검사한다:

```
검색:
- 인증 미들웨어 적용 누락 (라우트에 auth 미들웨어 없음)
- 비밀번호 해싱 (bcrypt/argon2 사용 여부)
- JWT 검증 (만료 확인, 알고리즘 지정)
- CORS 설정 (와일드카드 * 사용 여부)
```

### 5. 결과 리포트 생성

`docs/security-scan-{date}.md` 파일에 결과를 저장한다.

## 출력

```markdown
## 보안 스캔 결과

**대상**: [스캔 대상]
**일시**: [날짜]

### 의존성 취약점
| 패키지 | 심각도 | CVE | 설명 |
|--------|--------|-----|------|
| [패키지명] | [Critical/High/Medium/Low] | [CVE-ID] | [설명] |

또는: "취약점 없음" / "audit 도구 미설치"

### 코드 레벨 보안 이슈
| 위치 | 유형 | 심각도 | 설명 |
|------|------|--------|------|
| [path:line] | [유형] | [심각도] | [설명] |

또는: "이슈 없음"

### 인증/인가
[검토 결과 또는 "인증 관련 코드 없음"]

### 권장 조치
1. [조치 1]
2. [조치 2]
```

## REVIEW 연동

스캔 결과에 High/Critical 이슈가 있으면 security 에이전트에게 상세 평가를 요청한다:

```
Task(security): "보안 스캔에서 발견된 이슈를 평가하라: [이슈 목록]. 실제 위험인지, 오탐인지 판단하라."
```
