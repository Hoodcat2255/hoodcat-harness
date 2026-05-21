# Committer Agent - Invocation Examples

### Example 1: commit skill - Feature Commit

```markdown
Skill("commit", "로그인 엔드포인트에 rate limiting 미들웨어 추가 작업 커밋.")
```

Expected outcome:
- `git status` / `git diff` 로 변경 파일 확인 (Read-only)
- 관련 파일만 선택적 스테이징 (`git add src/routes/auth.ts src/middleware/rateLimit.ts`)
- 커밋 메시지 (Conventional Commits + 한국어):
  ```
  feat: 로그인 엔드포인트에 rate limiting 적용

  - POST /api/auth/login에 분당 10회 제한 추가
  - createRateLimiter() 팩토리로 auth 전용 설정 분리
  ```
- `.env`, `*.secret` 등 민감 파일 스테이징 제외 확인

### Example 2: commit skill - Bug Fix Commit

```markdown
Skill("commit", "processRefund() 음수 금액 버그 수정 커밋. 테스트 파일 포함.")
```

Expected outcome:
- 변경 파일: `src/services/payment.ts`, `src/services/__tests__/payment.test.ts`
- 선택적 스테이징 (두 파일만)
- 커밋 메시지:
  ```
  fix: 환불 금액 음수 저장 버그 수정

  - processRefund()에서 Math.abs()로 금액 절댓값 처리
  - 음수·0원·정상 금액 케이스 회귀 테스트 추가
  ```
- pre-commit 훅 실패 시 코드 수정 없이 실패 내용 보고

### Example 3: commit skill - Docs/Chore Commit

```markdown
Skill("commit", "ORM 선택 결정 문서와 .env.example 업데이트 커밋.")
```

Expected outcome:
- 변경 파일: `docs/decide-orm-selection-20260522.md`, `.env.example`
- 커밋 메시지:
  ```
  docs: ORM 선택 결정 문서 추가 및 환경 변수 예시 업데이트

  - Prisma 채택 근거 및 대안 비교표 기록
  - DATABASE_URL 예시 항목 .env.example에 추가
  ```
- `Co-Authored-By` 미포함
