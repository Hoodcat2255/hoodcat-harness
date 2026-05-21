# Researcher Agent - Invocation Examples

### Example 1: deepresearch skill - Technology Research

```markdown
Skill("deepresearch", "Node.js 환경에서 JWT 무효화 전략 조사. Redis 기반 블랙리스트, refresh token rotation, 단기 만료 패턴 비교. 2025년 기준 최신 Best Practice 포함.")
```

Expected outcome:
- WebSearch + Context7(jsonwebtoken, ioredis 문서) 조합 조사
- `docs/research-jwt-invalidation-20260522.md` 산출
  - 각 전략의 트레이드오프 비교표
  - 권장 구현 패턴 코드 예시
  - 출처 URL + Tier 라벨 (`(Tier 1) RFC 7519`, `(Tier 2) auth0 공식 가이드`)
  - 자신감 라벨: `확실` / `추정` 구분

### Example 2: blueprint skill - Feature Planning

```markdown
Skill("blueprint", "사용자 알림 시스템 신규 구현 기획. 이메일·슬랙·인앱 채널, 템플릿 관리, 발송 이력 저장 요구사항 포함.")
```

Expected outcome:
- `gh` CLI로 기존 이슈·PR에서 관련 논의 확인
- Task(navigator)로 현재 코드베이스 구조 파악
- `docs/blueprint-notification-system-20260522.md` 산출
  - 아키텍처 다이어그램 (텍스트 형식)
  - 구현 단계별 분류 (Phase 1/2/3)
  - 기술 선택 근거와 대안 목록

### Example 3: decide skill - Technology Comparison

```markdown
Skill("decide", "ORM 선택: Prisma vs TypeORM vs Drizzle. PostgreSQL + TypeScript 환경, 마이그레이션 관리·타입 안전성·성능 기준으로 비교.")
```

Expected outcome:
- 각 라이브러리 Context7 공식 문서 조회
- GitHub stars/이슈 트렌드 `gh` CLI 확인
- `docs/decide-orm-selection-20260522.md` 산출
  - 평가 기준별 점수 비교표
  - 최종 권고안 + 근거 요약
  - 출처 Tier 라벨 포함 (`(Tier 1) Prisma 공식 docs`, `(Tier 2) 공식 GitHub 이슈`)
