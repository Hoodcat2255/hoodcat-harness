# Claude Code 로컬 파일과 Git 처리 방식 조사 결과

> 조사일: 2026-02-06

## 개요

Claude Code는 로컬 설정 파일과 Git 버전 관리를 명확하게 분리하여 처리합니다. **Claude Code가 자동으로 `.local` 파일들을 `.gitignore`에 추가**하여 개인 설정이 저장소에 커밋되지 않도록 관리합니다. 이는 팀 공유 설정과 개인 설정을 효과적으로 분리하기 위한 설계입니다.

## 상세 내용

### 파일 유형별 Git 처리 방식

| 파일 유형 | 경로 | Git 추적 | 관리 주체 |
|-----------|------|----------|-----------|
| 프로젝트 공유 설정 | `.claude/settings.json` | O (커밋됨) | 사용자/팀 |
| 프로젝트 로컬 설정 | `.claude/settings.local.json` | X (무시됨) | **Claude Code 자동** |
| 프로젝트 CLAUDE.md | `./CLAUDE.md` | O (커밋됨) | 사용자/팀 |
| 로컬 CLAUDE.md | `./CLAUDE.local.md` | X (무시됨) | **Claude Code 자동** |
| 사용자 전역 설정 | `~/.claude/settings.json` | 해당없음 | 사용자 |
| 사용자 전역 CLAUDE.md | `~/.claude/CLAUDE.md` | 해당없음 | 사용자 |

### Claude Code가 자동으로 처리하는 것

1. **`.claude/settings.local.json` 생성 시**: Claude Code가 자동으로 git이 이 파일을 무시하도록 설정
2. **`.claude/*.local.md` 파일들**: 자동으로 `.gitignore`에 추가되어 버전 관리에서 제외
3. **`.claude/*.local.json` 파일들**: 마찬가지로 자동으로 무시됨

### 권장 .gitignore 패턴

Claude Code 플러그인 개발 문서에서 권장하는 패턴:

```gitignore
.claude/*.local.md
.claude/*.local.json
```

### 디렉토리 구조 예시

```
project-root/
├── CLAUDE.md                      # Git 추적됨 (팀 공유)
├── CLAUDE.local.md                # Git 무시됨 (개인용)
└── .claude/
    ├── settings.json              # Git 추적됨 (팀 공유)
    ├── settings.local.json        # Git 무시됨 (개인용, Claude Code 자동 처리)
    ├── commands/                  # 커스텀 명령어
    ├── rules/                     # 규칙 파일들
    └── skills/                    # 스킬 정의

~/.claude/                         # 전역 설정 (Git 저장소와 무관)
├── CLAUDE.md                      # 모든 프로젝트에 적용
├── settings.json                  # 전역 사용자 설정
├── commands/                      # 전역 커스텀 명령어
├── rules/                         # 전역 규칙
├── projects/                      # 프로젝트별 세션 기록
│   └── -path-to-project/
│       └── {session-id}.jsonl
└── file-history/                  # 파일 변경 히스토리
    └── {content-hash}/
```

### 설정 우선순위 (낮은 것 → 높은 것)

1. **User (전역)**: `~/.claude/settings.json` - 기본값
2. **Project (공유)**: `.claude/settings.json` - 팀 정책
3. **Project (로컬)**: `.claude/settings.local.json` - 개인 재정의

> 예: 사용자 설정에서 허용된 권한이 프로젝트 설정에서 거부되면, 프로젝트 설정이 우선 적용됩니다.

### 용도별 사용 가이드

| 용도 | 사용할 파일 |
|------|-------------|
| 팀 전체 코딩 표준 | `.claude/settings.json` |
| 조직 정책 (예: `.env` 읽기 금지) | `.claude/settings.json` |
| 개인 워크플로우 개선 | `~/.claude/settings.json` |
| 머신별 설정 (경로 등) | `.claude/settings.local.json` |
| 프로젝트 컨텍스트 (팀 공유) | `./CLAUDE.md` |
| 개인 프로젝트 메모 | `./CLAUDE.local.md` |

## 코드 예제

### 팀 공유 설정 (`.claude/settings.json`)

```json
{
  "$schema": "https://json.schemastore.org/claude-code-settings.json",
  "permissions": {
    "allow": [
      "Bash(npm run lint)",
      "Bash(npm run test *)"
    ],
    "deny": [
      "Read(./.env)",
      "Read(./.env.*)",
      "Read(./secrets/**)"
    ]
  }
}
```

### 개인 로컬 설정 (`.claude/settings.local.json`)

```json
{
  "permissions": {
    "allow": [
      "Bash(npm run dev)"
    ]
  }
}
```

## 주요 포인트

- **Claude Code가 자동 처리**: `.local` 접미사가 붙은 파일들은 Claude Code가 자동으로 git ignore 처리
- **명시적 분리**: 팀 공유 설정(`settings.json`)과 개인 설정(`settings.local.json`)이 명확히 분리됨
- **계층적 우선순위**: 더 구체적인 설정이 일반적인 설정을 재정의
- **세션 데이터 보존**: `~/.claude/projects/`에 세션별 JSONL 파일로 저장되어 크래시 복구 가능
- **파일 히스토리**: `~/.claude/file-history/`에 편집 전 파일 상태가 해시로 저장되어 롤백 가능

## 결론

| 질문 | 답변 |
|------|------|
| `.local` 파일의 gitignore 처리는 누가? | **Claude Code가 자동으로** |
| 일반 설정 파일은? | **사용자/팀이 직접 관리** |
| `~/.claude/` 디렉토리는? | **Git 저장소와 무관** (사용자 홈 디렉토리) |

## 출처

- [Claude Code Settings - 공식 문서](https://code.claude.com/docs/en/settings)
- [Claude Code Memory 관리 - 공식 문서](https://code.claude.com/docs/en/memory)
- [Claude Code GitHub Repository](https://github.com/anthropics/claude-code)
- [How Claude Code Manages Local Storage - Milvus Blog](https://milvus.io/blog/why-claude-code-feels-so-stable-a-developers-deep-dive-into-its-local-storage-design.md)
- [Keeping CLAUDE.md out of shared Git repos](https://andyjakubowski.com/engineering/keeping-claude-md-out-of-shared-git-repos)
- [Claude Code Settings Guide - eesel.ai](https://www.eesel.ai/blog/settings-json-claude-code)
