# Shared Context Protocol (공유 컨텍스트 프로토콜)

> 적용 범위: 모든 에이전트의 inter-agent 컨텍스트 전달.
> 정본 위치: 본 파일. 에이전트 파일에서는 cross-link + 자신의 보고 헤더(## <Agent> Report)만 유지한다.
> 관련 정본 파일: 대화 출력 서식 규칙은 `.claude/rules/response-format.md` 참조.

## 개요

에이전트 간 컨텍스트를 전달하는 표준 메커니즘이다. 이전 에이전트의 결과를 재활용해 중복 작업을 줄이고, 완료된 발견 사항을 다음 에이전트가 참고할 수 있도록 파일에 기록한다.

## 1. 인입 (컨텍스트 수신)

이전 에이전트의 작업 결과가 `additionalContext`로 주입되면 다음을 수행한다.

- 주입된 컨텍스트를 읽고 이미 완료된 작업을 파악한다.
- 중복 탐색·조사·검증을 생략한다.
- 발견된 파일 경로, 패턴, 결론을 그대로 활용한다.

## 2. 인출 (컨텍스트 기록)

작업 완료 시, 핵심 발견 사항을 공유 컨텍스트 파일에 기록한다.

- 기록 경로는 `additionalContext`에 포함되어 있다.
- 경로가 없으면 기록을 생략한다.
- 기록은 마크다운 형식으로 작성한다 (`.claude/rules/response-format.md`의 파일 기록 예외 적용).

## 3. 기록 형식 (에이전트별 보고 헤더 매핑)

각 에이전트는 자신의 보고 헤더와 표준 섹션을 사용한다. 섹션 상세는 각 에이전트 `.md` 파일에 유지한다.

- coder → `## Coder Report`
  섹션: Changed Files / Created Files / Build·Test Results / Issues

- reviewer → `## Reviewer Report`
  섹션: Verdict / Files Reviewed / Findings / Positive Patterns

- architect → `## Architect Report`
  섹션: Verdict / Architecture Patterns / Structural Assessment / Scalability Notes / Recommendations

- navigator → `## Navigator Report`
  섹션: Files Found / Patterns / Dependencies / Impact Scope

- researcher → `## Researcher Report`
  섹션: Research Summary / Key Sources / Findings / Recommendations

- committer → `## Committer Report`
  섹션: Commits Created / Files Committed / Notes

- security → `## Security Report`
  섹션: Verdict / Attack Surfaces / OWASP Categories / Vulnerabilities / Dependency Audit

- orchestrator → `## Orchestrator Report`
  섹션: Plan / Steps Executed / Files Changed / Review Verdicts / Unresolved Issues

## 4. 보고 형식 공통 구조 예시

```markdown
## <Agent> Report
### <섹션 1>
- [항목]
### <섹션 2>
- [항목]
```

## 적용 규칙

1. **인입 우선**: `additionalContext`가 있으면 반드시 읽고 중복 작업을 제거한다.
2. **인출 의무**: 작업 완료 후 경로가 지정되어 있으면 반드시 기록한다.
3. **절대 경로 사용**: 파일 목록은 모두 절대 경로로 기재한다.
4. **헤더는 에이전트별 정본 유지**: 섹션 상세는 각 에이전트 `.md` 파일에 있다. 본 파일은 메커니즘과 헤더 매핑만 정의한다.
5. **대화 출력과 구분**: 공유 컨텍스트 파일 기록은 파일 쓰기이므로 마크다운 사용. 대화 출력과 혼동하지 않는다.
