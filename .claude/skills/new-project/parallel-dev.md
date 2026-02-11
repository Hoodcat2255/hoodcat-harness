# Phase 3a: 에이전트팀 병렬 개발

파일 소유권이 겹치지 않는 독립 태스크가 3개 이상이면 이 패턴을 사용한다.

## 프로세스

```
1. TeamCreate("dev-team")

2. tasks.md에서 의존성 없는 태스크 그룹 식별
   - 각 태스크의 대상 파일 목록을 명시하여 파일 충돌 방지

3. 각 독립 태스크에 대해:
   TaskCreate({
     subject: "태스크 제목",
     description: "상세 설명 + 소유할 파일 목록",
     activeForm: "구현 중..."
   })

4. 의존 태스크에 대해:
   TaskCreate({...})
   TaskUpdate({ addBlockedBy: ["선행 태스크 ID"] })

5. 독립 태스크 수만큼 팀원 스폰 (최대 5명):
   Task(team_name="dev-team", name="dev-N"):
     "태스크 N을 구현하라. 소유 파일: [파일 목록].
      다른 팀원의 파일은 절대 수정하지 마라.
      CLAUDE.md의 코딩 컨벤션을 준수하라.
      완료 후 TaskUpdate로 completed 처리하라."

6. 리드는 TaskList로 진행 상황을 모니터링
   - TaskCompleted 훅이 각 태스크 빌드/테스트 자동 검증
   - TeammateIdle 훅이 미완료 팀원에게 작업 재개 유도

7. 모든 태스크 완료 후:
   - 통합 빌드/테스트 실행
   - 리뷰 수행 (본문의 공통 리뷰 참조)
   - SendMessage(type="shutdown_request")로 팀원 종료
   - TeamDelete로 정리
```
