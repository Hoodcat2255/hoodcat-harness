# 구현 태스크: 스킬 아키텍처 v3

## 태스크 목록

### Task 1: workflow 에이전트 생성 [S]
**파일**: `.claude/agents/workflow.md`
**의존성**: 없음

신규 에이전트 정의 파일 생성:
- 워크플로우 오케스트레이션 전용 지침
- Skill(), Task() 호출 패턴 정의
- Phase 진행/BLOCK 판단 규칙
- 팀 도구 사용 지침
- model: opus, memory: local
- tools: Skill, Task, Read, Write, Edit, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete

---

### Task 2: 워크플로우 스킬 5개 fork 전환 [M]
**파일**: `.claude/skills/{bugfix,hotfix,implement,improve,new-project}/SKILL.md`
**의존성**: Task 1

각 워크플로우 스킬에 대해:
1. frontmatter에 `context: fork` 추가
2. frontmatter에 `agent: workflow` 추가
3. frontmatter에 `allowed-tools` 추가
   - bugfix, new-project: Skill, Task, Read, Write, Edit, Glob, Grep, Bash + Team 도구
   - hotfix, implement, improve: Skill, Task, Read, Write, Edit, Glob, Grep, Bash
4. Sisyphus Phase 0 섹션 제거
5. Sisyphus 비활성화 섹션 제거
6. 모든 `jq '.phase=...' .claude/flags/sisyphus.json` 명령 제거
7. Phase 구조는 유지하되, 파일 시스템 플래그 대신 순차 실행으로 변경

---

### Task 3: Sisyphus 아티팩트 제거 [S]
**파일**: `.claude/hooks/sisyphus-gate.sh`, `.claude/flags/sisyphus.json`
**의존성**: Task 2

1. `.claude/hooks/sisyphus-gate.sh` 삭제
2. `.claude/flags/sisyphus.json` 삭제
3. settings.json에서 sisyphus-gate.sh 참조 제거 (있으면)

---

### Task 4: CLAUDE.md 업데이트 [S]
**파일**: `CLAUDE.md`
**의존성**: Task 2, Task 3

1. "스킬 아키텍처" 섹션 재작성
   - 워크플로우/워커 2계층 → 전체 fork 단일 계층
   - workflow 에이전트 설명 추가
2. "논스탑 작업규칙 (Sisyphus)" 섹션 전체 제거
3. "스킬 실행 모델" 섹션 신규 작성
4. "에이전트팀 활용 기준" 섹션은 유지 (팀 스킬에서 여전히 유효)
5. "안전장치" 테이블에서 Sisyphus 관련 항목 제거
6. "수동 비활성화" 섹션 제거

---

### Task 5: 메모리 파일 업데이트 [S]
**파일**: MEMORY.md
**의존성**: Task 4

1. 스킬 아키텍처 v3 전환 완료 기록
2. Sisyphus 제거 기록
3. workflow 에이전트 추가 기록

---

## 구현 순서

```
Task 1 (workflow 에이전트)
    │
    ▼
Task 2 (워크플로우 스킬 fork 전환)
    │
    ▼
Task 3 (Sisyphus 제거) ──┐
                         │
Task 4 (CLAUDE.md)  ◄───┘
    │
    ▼
Task 5 (메모리 업데이트)
```

## 복잡도 총합

- S(소): 3개 (Task 1, 3, 4, 5)
- M(중): 1개 (Task 2)
- 총 5개 태스크
