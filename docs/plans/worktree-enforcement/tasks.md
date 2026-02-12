# Git Worktree 강제 사용 - 구현 태스크

## 태스크 목록

### T1: workflow 에이전트에 Worktree 관리 섹션 추가 [S]
**파일**: `.claude/agents/workflow.md`
**의존성**: 없음
**설명**: workflow 에이전트 정의에 Worktree Management 섹션을 추가한다.
- Worktree 생성 규칙 (경로, 브랜치 명명)
- 절대 경로 규칙
- 정리 규칙
- 의존성 설치 가이드 (프로젝트 타입별)

### T2: implement 스킬에 worktree Phase 추가 [M]
**파일**: `.claude/skills/implement/SKILL.md`
**의존성**: T1
**설명**:
- Phase 0 (Worktree 준비) 추가: Phase 1 이전에 worktree 생성
- Phase 2 (브랜치 생성) 제거: worktree 생성 시 브랜치가 함께 생성되므로 불필요
- Phase 3~6의 모든 경로 참조를 WORKTREE_DIR 기반으로 수정
- 최종 Phase (Worktree 정리) 추가
- 완료 보고에 worktree/브랜치 정보 추가

### T3: bugfix 스킬에 worktree Phase 추가 [M]
**파일**: `.claude/skills/bugfix/SKILL.md`
**의존성**: T1
**설명**:
- Phase 0 (Worktree 준비) 추가
- 단순 버그 경로: Skill("fix") 호출 시 WORKTREE_DIR 경로 전달
- 복잡 버그 경로 (에이전트팀): 가설별 worktree 생성 추가
  - 각 디버거 팀원에게 별도 worktree 경로 할당
  - 리드가 worktree 생성/정리 담당
- 최종 Phase (Worktree 정리) 추가

### T4: hotfix 스킬에 worktree Phase 추가 [S]
**파일**: `.claude/skills/hotfix/SKILL.md`
**의존성**: T1
**설명**:
- Phase 0 (Worktree 준비) 추가 (hotfix/ 브랜치)
- Phase 2~4의 경로 참조를 WORKTREE_DIR 기반으로 수정
- 최종 Phase (Worktree 정리) 추가
- 긴급성 고려: 정리 전 사용자에게 병합 완료 여부 확인 메시지 추가

### T5: improve 스킬에 worktree Phase 추가 [S]
**파일**: `.claude/skills/improve/SKILL.md`
**의존성**: T1
**설명**:
- Phase 0 (Worktree 준비) 추가
- Phase 1~3의 경로 참조를 WORKTREE_DIR 기반으로 수정
- Phase 1.5 기획도 WORKTREE_DIR 내에서 수행
- 최종 Phase (Worktree 정리) 추가

### T6: new-project 스킬에 worktree Phase 추가 [M]
**파일**: `.claude/skills/new-project/SKILL.md`
**의존성**: T1
**설명**:
- Phase 0 (Worktree 준비) 추가
- Phase 3a (병렬 개발) 시 T7의 패턴 참조
- Phase 3b (순차 개발)도 WORKTREE_DIR 내에서 수행
- 최종 Phase (Worktree 정리) 추가
- 새 프로젝트의 경우 git init이 필요할 수 있으므로 분기 처리 추가:
  - 기존 repo가 있으면 worktree 생성
  - 새 repo면 별도 디렉토리에서 git init

### T7: parallel-dev.md에 팀원별 worktree 패턴 추가 [M]
**파일**: `.claude/skills/new-project/parallel-dev.md`
**의존성**: T1
**설명**:
- 리드가 팀원 수만큼 worktree를 사전 생성하는 단계 추가
- 팀원 스폰 프롬프트에 worktree 절대 경로 포함
- 팀원 종료 후 리드가 worktree 정리하는 단계 추가
- 통합 빌드/테스트 전에 브랜치 병합 또는 변경 확인 단계 추가

### T8: coder 에이전트에 Worktree 작업 지침 추가 [S]
**파일**: `.claude/agents/coder.md`
**의존성**: 없음
**설명**:
- Worktree 환경에서의 작업 지침 섹션 추가
- 절대 경로 사용 강조
- Bash 명령 실행 시 `cd "$WORKTREE_DIR" && command` 패턴 명시
- 의존성 설치 인식 (새 worktree에는 node_modules 등이 없을 수 있음)

### T9: committer 에이전트에 Worktree 호환성 추가 [S]
**파일**: `.claude/agents/committer.md`
**의존성**: 없음
**설명**:
- Worktree 내에서의 git 동작 설명 추가
- 절대 경로 사용 강조
- worktree 브랜치 인식 관련 지침 추가

### T10: harness.md의 Git Worktree 규칙 업데이트 [S]
**파일**: `.claude/harness.md`
**의존성**: T1~T9 완료 후
**설명**:
- 기존 "Git Worktree 규칙" 섹션을 업데이트하여 구현 완료를 반영
- worktree 경로 규칙, 브랜치 명명 규칙 구체화
- 고아 worktree 정리 방법 (`git worktree prune`) 추가
- 에이전트팀 병렬 개발 시 worktree 사용 패턴 참조 추가

## 구현 순서

```
Phase 1 (독립, 병렬 가능):
  T1: workflow 에이전트 수정     [S]
  T8: coder 에이전트 수정        [S]
  T9: committer 에이전트 수정    [S]

Phase 2 (T1 완료 후, 병렬 가능):
  T2: implement 스킬 수정        [M]
  T3: bugfix 스킬 수정           [M]
  T4: hotfix 스킬 수정           [S]
  T5: improve 스킬 수정          [S]
  T6: new-project 스킬 수정      [M]
  T7: parallel-dev.md 수정       [M]

Phase 3 (모든 태스크 완료 후):
  T10: harness.md 업데이트       [S]
```

## 복잡도 요약

- S (소): 6개 (T1, T4, T5, T8, T9, T10)
- M (중): 4개 (T2, T3, T6, T7)
- L (대): 0개
- **총 10개 태스크**
