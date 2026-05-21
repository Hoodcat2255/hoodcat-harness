# Coder Agent - Invocation Examples

### Example 1: code skill - Bug Fix

```markdown
Skill("code", "src/services/payment.ts의 processRefund()에서 환불 금액이 음수로 저장되는 버그 수정. 금액 계산 전 절댓값 처리 추가.")
```

Expected outcome:
- `src/services/payment.ts` 수정: 환불 금액에 `Math.abs()` 적용
- 빌드 exit code 0 확인
- 변경 범위 최소화 (processRefund 함수 내부만)

### Example 2: test skill - Regression Test

```markdown
Skill("test", "src/services/payment.ts의 processRefund() 수정에 대한 회귀 테스트 작성 및 실행. 음수 금액, 0원, 정상 금액 케이스 포함.")
```

Expected outcome:
- `src/services/__tests__/payment.test.ts` 신규 케이스 추가
- `npm test src/services/__tests__/payment.test.ts` exit code 0 확인
- 테스트 결과 요약 보고 (passed/failed 수)

### Example 3: security-scan skill - Dependency Audit

```markdown
Skill("security-scan", "프로젝트 전체 npm 의존성 취약점 스캔. severity high 이상 항목 목록화.")
```

Expected outcome:
- `npm audit --json` 실행 후 high/critical 항목 추출
- 취약 패키지명, 버전, CVE ID, 권고 조치 목록
- 즉시 패치 가능한 항목과 수동 대응 필요 항목 분류
