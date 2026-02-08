# Claude Code 메모리 필드 조사 결과

> 조사일: 2026-02-06

## 개요

Claude Code의 메모리 시스템은 `CLAUDE.md` 파일을 통해 세션 간 지속적인 컨텍스트를 유지하는 기능입니다. 계층적 구조로 관리되며, 프로젝트별 설정부터 조직 전체 정책까지 다양한 수준에서 Claude의 동작을 커스터마이즈할 수 있습니다. 모든 메모리 파일은 Claude Code 실행 시 자동으로 컨텍스트에 로드됩니다.

## 상세 내용

### 메모리 계층 구조

Claude Code는 5가지 메모리 위치를 계층적으로 관리합니다. 상위 계층이 우선 적용되며 먼저 로드됩니다.

| 유형 | 파일 위치 | 용도 | 공유 범위 |
|------|-----------|------|----------|
| **Managed Policy** | OS별 시스템 디렉토리 | 조직 전체 코딩 표준, 보안 정책 | 조직 전체 |
| **Project Memory** | `CLAUDE.md` (프로젝트 루트) | 프로젝트 아키텍처, 공통 워크플로우 | 팀 (소스 컨트롤) |
| **Project Rules** | `.claude/rules/*.md` | 모듈화된 주제별 지침 | 팀 (소스 컨트롤) |
| **User Memory** | `~/.claude/CLAUDE.md` | 개인 환경설정, 코딩 스타일 | 개인 전용 |
| **Project Memory (Local)** | `CLAUDE.local.md` | 개인 프로젝트별 설정 | 개인 전용 (.gitignore 자동 추가) |

### OS별 Managed Policy 위치

| 운영체제 | 경로 |
|----------|------|
| macOS | `/Library/Application Support/ClaudeCode/CLAUDE.md` |
| Linux/WSL | `/etc/claude-code/CLAUDE.md` |
| Windows | `C:\Program Files\ClaudeCode\CLAUDE.md` |

### 메모리 파일 구조

#### 기본 구조

```markdown
# 프로젝트 이름

## 프로젝트 개요
간단한 프로젝트 설명 (1-2문장)

## 기술 스택
- Frontend: React, TypeScript
- Backend: Node.js, Express
- Database: PostgreSQL

## 코드 스타일
- 2칸 들여쓰기 사용
- ES 모듈 사용
- named export 선호

## 주요 명령어
- `npm run dev` - 개발 서버 실행
- `npm test` - 테스트 실행
- `npm run build` - 프로덕션 빌드
```

#### YAML Frontmatter 활용 (조건부 규칙)

```markdown
---
paths:
  - "**/*.tsx"
  - "**/*.ts"
---

# TypeScript 규칙

- strict 모드 사용
- any 타입 지양
- 인터페이스 네이밍: I 접두사 사용하지 않음
```

### 파일 임포트 기능

CLAUDE.md 파일은 `@path/to/import` 구문으로 다른 파일을 임포트할 수 있습니다.

```markdown
# 프로젝트 메모리

@docs/architecture.md
@docs/api-guidelines.md
@.claude/rules/testing.md
```

- 최대 5단계 깊이까지 재귀적 임포트 가능
- 상세 문서는 외부 파일로 분리하여 메인 CLAUDE.md를 간결하게 유지

### 메모리 조회 방식

Claude Code는 현재 작업 디렉토리에서 시작하여 루트 디렉토리까지 재귀적으로 `CLAUDE.md` 및 `CLAUDE.local.md` 파일을 탐색합니다. 하위 디렉토리의 파일은 해당 파일에 접근할 때 자동으로 발견됩니다.

### 관련 슬래시 명령어

| 명령어 | 설명 |
|--------|------|
| `/memory` | 로드된 메모리 파일 확인 및 편집 |
| `/init` | 프로젝트 구조 기반 CLAUDE.md 자동 생성 |
| `/compact` | 대화 기록 압축하여 컨텍스트 최적화 |

### 설정 파일 위치 (참고)

메모리 파일 외에 Claude Code는 다양한 설정 파일을 사용합니다:

| 파일 | 위치 | 용도 |
|------|------|------|
| 사용자 설정 | `~/.claude/settings.json` | 개인 전역 설정 |
| 프로젝트 설정 | `.claude/settings.json` | 프로젝트별 설정 |
| 로컬 프로젝트 설정 | `.claude/settings.local.json` | 개인 프로젝트 설정 |
| 전역 상태 | `~/.claude.json` | Claude Code 전역 상태 |
| MCP 서버 | `.mcp.json` | MCP 서버 설정 |

## 코드 예제

### 실용적인 CLAUDE.md 예제

```markdown
# E-commerce API 프로젝트

Next.js 14 + Prisma + PostgreSQL 기반 이커머스 백엔드 API

## 기술 스택
- Framework: Next.js 14 (App Router)
- ORM: Prisma
- Database: PostgreSQL
- Auth: NextAuth.js
- Testing: Jest + React Testing Library

## 코드 규칙
- 2칸 들여쓰기
- 세미콜론 사용
- single quote 사용
- trailing comma 사용

## 명령어
- `pnpm dev` - 개발 서버 (포트 3000)
- `pnpm test` - 테스트 실행
- `pnpm test:watch` - 테스트 워치 모드
- `pnpm db:migrate` - DB 마이그레이션
- `pnpm db:seed` - 시드 데이터 입력

## 주의사항
- API 라우트는 `/app/api/` 디렉토리에 위치
- 모든 DB 작업은 Prisma 클라이언트 사용
- 환경변수는 `.env.local` 참조 (커밋 금지)

## 디렉토리 구조
- `/app` - Next.js App Router 페이지/API
- `/lib` - 유틸리티 함수
- `/prisma` - 스키마 및 마이그레이션
- `/components` - React 컴포넌트
```

### .claude/rules/ 디렉토리 구조 예제

```
.claude/
├── CLAUDE.md          # 메인 프로젝트 지침
├── settings.json      # 프로젝트 설정
└── rules/
    ├── code-style.md  # 코딩 스타일 규칙
    ├── testing.md     # 테스트 작성 가이드
    ├── security.md    # 보안 관련 규칙
    └── api-design.md  # API 설계 원칙
```

## 주요 포인트

- **구체적으로 작성**: "코드를 깔끔하게 작성" 대신 "2칸 들여쓰기 사용"처럼 명확하게
- **500줄 이하 유지**: CLAUDE.md는 모든 세션에 로드되므로 간결하게 유지
- **모듈화 활용**: 상세 내용은 `.claude/rules/` 또는 `docs/`로 분리
- **계층 구조 활용**: 공유할 내용은 `CLAUDE.md`, 개인 설정은 `CLAUDE.local.md`
- **임포트 활용**: `@path/to/file` 구문으로 외부 문서 참조
- **자동 생성 활용**: `/init` 명령으로 프로젝트 기반 초기 파일 생성
- **정기적 정리**: 오래된 정보 제거하여 컨텍스트 효율성 유지

## 세션 지속성 관련 명령어

| 명령어 | 설명 |
|--------|------|
| `claude --continue` | 가장 최근 대화 이어서 진행 |
| `claude --resume` | 특정 세션 선택하여 재개 |
| `/compact` | 대화 기록 압축 (백그라운드 자동 실행) |

## 출처

- [Manage Claude's memory - Claude Code Docs](https://code.claude.com/docs/en/memory)
- [The Complete Guide to CLAUDE.md - Builder.io](https://www.builder.io/blog/claude-md-guide)
- [Using CLAUDE.MD files - Claude Blog](https://claude.com/blog/using-claude-md-files)
- [Claude Code Best Practices: Memory Management](https://cuong.io/blog/2025/06/15-claude-code-best-practices-memory-management)
- [Creating the Perfect CLAUDE.md - Dometrain](https://dometrain.com/blog/creating-the-perfect-claudemd-for-claude-code/)
- [Stop Repeating Yourself: Give Claude Code a Memory](https://www.producttalk.org/give-claude-code-a-memory/)
- [Claude Code - Setting up CLAUDE.md Files Tutorial](https://claudecode.io/tutorials/claude-md-setup)
- [How to Use Claude-mem for Memory Persistence](https://apidog.com/blog/how-to-use-claude-mem/)
- [GitHub - centminmod/my-claude-code-setup](https://github.com/centminmod/my-claude-code-setup)
- [GitHub - ArthurClune/claude-md-examples](https://github.com/ArthurClune/claude-md-examples)
