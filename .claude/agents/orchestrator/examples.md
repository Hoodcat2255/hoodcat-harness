# Orchestrator Agent - Invocation Examples

### Example 1: Feature Implementation Recipe

**Request**: "로그인 엔드포인트에 rate limiting을 추가해줘."

```markdown
## Plan

Recipe: Feature Implementation (Simple)
Task(navigator) → code → test → Task(reviewer) → commit

Steps:
1. Task(navigator, "로그인 엔드포인트와 기존 미들웨어 구조 파악")
2. Skill("code", "src/routes/auth.ts에 rate limiting 미들웨어 적용")
3. Skill("test", "rate limiting 동작 테스트 작성 및 실행")
4. Task(reviewer, "변경된 auth.ts 코드 품질 리뷰")
5. [커밋은 사용자 확인 후 진행]
```

Expected Plan Completed report:
```markdown
## Plan Completed

### Plan Summary
- rate limiting 미들웨어를 POST /api/auth/login에 적용하는 Simple Feature Implementation

### Steps Executed
- [x] Step 1: navigator — auth 라우트, 기존 rateLimit.ts 위치 확인
- [x] Step 2: code — src/routes/auth.ts, src/middleware/rateLimit.ts 수정
- [x] Step 3: test — 429 응답 케이스 포함 3개 테스트 추가, exit 0
- [x] Step 4: reviewer — PASS

### Files Changed
- `src/routes/auth.ts` — rate limit 미들웨어 등록
- `src/middleware/rateLimit.ts` — auth 전용 설정 추가
- `tests/routes/auth.test.ts` — 429 케이스 추가

### Review Verdicts
- reviewer: PASS

### Next Steps
- 커밋을 진행할까요? (`Skill("commit", "...")`)
```

---

### Example 2: Bug Fix Recipe

**Request**: "결제 서비스에서 환불 금액이 음수로 저장되는 버그가 있어."

```markdown
## Plan

Recipe: Bug Fix (Basic)
Task(navigator) → code(diagnose+patch) → test(regression) → Task(reviewer) → commit

Steps:
1. Task(navigator, "src/services/payment.ts 구조 및 processRefund 호출 경로 파악")
2. Skill("code", "processRefund() 음수 금액 버그 진단 및 패치")
3. Skill("test", "음수 금액 회귀 테스트 추가 및 전체 payment 테스트 실행")
4. Task(reviewer, "패치된 payment.ts 리뷰")
5. [커밋은 사용자 확인 후 진행]
```

Expected Plan Completed report:
```markdown
## Plan Completed

### Plan Summary
- processRefund()의 음수 금액 저장 버그를 진단하고 패치

### Steps Executed
- [x] Step 1: navigator — processRefund 호출 경로, DB 저장 로직 위치 확인
- [x] Step 2: code — Math.abs() 적용으로 패치
- [x] Step 3: test — 3개 케이스 추가, exit 0
- [x] Step 4: reviewer — PASS

### Files Changed
- `src/services/payment.ts` — 환불 금액 절댓값 처리
- `src/services/__tests__/payment.test.ts` — 회귀 테스트 추가

### Review Verdicts
- reviewer: PASS

### Next Steps
- 커밋을 진행할까요?
```

---

### Example 3: Hotfix Recipe

**Request**: "관리자 API에 인증이 없다는 제보가 들어왔어. 즉시 패치해줘."

```markdown
## Plan

Recipe: Hotfix (Basic)
Task(security, severity) → code(minimal patch) → [Task(reviewer) ‖ Task(security)] → test(regression) → security-scan → commit

Steps:
1. Task(security, "src/api/admin.ts 인증 누락 심각도 평가")        ← 먼저 심각도 확인
2. Skill("code", "admin 라우터에 adminAuth 미들웨어 추가 (최소 패치)")
3. Task(reviewer, "패치 코드 리뷰") ‖ Task(security, "인증 우회 가능성 재검증")  ← 병렬
4. Skill("test", "인증 없는 요청 → 401 응답 회귀 테스트")
5. Skill("security-scan", "관련 의존성 취약점 스캔")
6. [커밋은 사용자 확인 후 진행]
```

Expected Plan Completed report:
```markdown
## Plan Completed

### Plan Summary
- admin 엔드포인트 인증 누락 hotfix. security 우선 심각도 평가 후 최소 패치 적용.

### Steps Executed
- [x] Step 1: security — BLOCK (인증 없이 전체 admin API 접근 가능, Critical)
- [x] Step 2: code — adminAuth 미들웨어를 라우터 레벨에 등록
- [x] Step 3: reviewer PASS ‖ security PASS (병렬 완료)
- [x] Step 4: test — 401 케이스 포함 exit 0
- [x] Step 5: security-scan — 0 high/critical

### Files Changed
- `src/api/admin.ts` — adminAuth 미들웨어 등록

### Review Verdicts
- reviewer: PASS
- security: PASS (패치 후 우회 경로 없음 확인)

### Next Steps
- 커밋을 진행할까요?
```
