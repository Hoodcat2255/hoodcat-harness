# 오케스트레이터 위임율 개선

claude-dashboard 실데이터 분석 결과, 오케스트레이터가 스킬/에이전트 위임 없이 직접 코드를 수정하는 비율이 98.7%임.
(18개 인스턴스, Skill 7회 vs 직접 도구 537회, 리뷰 에이전트 스폰 0회)

## 원인

- orchestrator.md에 Edit/Write 도구 권한이 있어서 직접 수정 가능
- "delegate, don't code" 지시가 있지만 도구가 있으면 직접 실행하는 경향
- 소규모 프로젝트에서 위임 오버헤드를 회피

## 할 일

- [x] orchestrator.md에서 Edit 도구 제거 (소스코드 직접 수정 불가하게)
- [x] Write는 .md 파일만 허용하도록 프롬프트에 명시
- [x] 소스코드 수정 금지 규칙 추가 (FORBIDDEN: Edit on .py/.html/.js/.ts/.css + 40개 확장자)
- [x] 필수 위임 규칙 추가 (REQUIRED: Skill("code"), Skill("test"), Skill("commit"))
- [x] 리뷰 에이전트 활용 규칙 추가 (3+ 파일 변경 또는 보안 관련 시 Task(reviewer) 의무)
- [ ] 변경 후 실제 세션에서 위임율 개선 여부 검증
