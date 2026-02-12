# Scaffold 검증 체크리스트

생성된 파일의 필수 요소를 검증하는 체크리스트.
각 항목을 Read로 확인하고, 누락 시 즉시 수정한다.

## 스킬 frontmatter 체크리스트

- [ ] `name` 필드 존재
- [ ] `description` 필드 존재 (멀티라인 `|` 사용)
- [ ] `argument-hint` 필드 존재
- [ ] `user-invocable` 필드 존재 (true 또는 false)
- [ ] `context: fork` 설정됨
- [ ] `agent` 필드 존재 (worker: 지정된 에이전트, workflow: `workflow`)

## 워커 스킬 본문 체크리스트

- [ ] `# {Name} Skill` 제목
- [ ] `## 입력` 섹션 (`$ARGUMENTS:` 포함)
- [ ] `## 프로세스` 섹션 (번호 매겨진 `### N.` 하위 단계)
- [ ] `## 출력` 섹션 (마크다운 템플릿 포함)
- [ ] `## REVIEW 연동` 섹션

## 워크플로우 스킬 본문 체크리스트

- [ ] `# {Name} Skill` 제목
- [ ] `## 입력` 섹션 (`$ARGUMENTS:` 포함)
- [ ] `## DO/REVIEW 시퀀스` 섹션
- [ ] `### Phase N:` 하위 단계 (최소 2개)
- [ ] 각 Phase에 `DO:` 또는 `REVIEW:` 패턴 포함
- [ ] `## 종료 조건` 섹션 (번호 매겨진 조건 목록)
- [ ] `## 완료 보고` 섹션 (마크다운 템플릿 포함)

## 에이전트 체크리스트

### frontmatter

- [ ] `name` 필드 존재
- [ ] `description` 필드 존재 (멀티라인 `|` 사용)
- [ ] `tools` 필드 존재 (리스트 형식)
- [ ] `model` 필드 존재
- [ ] `memory: project` 설정됨

### 본문 필수 섹션

- [ ] `# {Name} Agent` 제목
- [ ] `## Purpose` 섹션 ("You are a..." 문장 포함)
- [ ] `## Capabilities` 섹션 (볼드 카테고리 목록)
- [ ] `## Shared Context Protocol` 섹션 (정형 텍스트 포함):
  - [ ] additionalContext 참조 문구
  - [ ] 공유 컨텍스트 파일 기록 문구
  - [ ] 기록 형식 마크다운 코드 블록
- [ ] `## Memory Management` 섹션 (정형 텍스트 포함):
  - [ ] "작업 시작 전" 문구 (MEMORY.md 읽기)
  - [ ] "작업 완료 후" 문구 (MEMORY.md 갱신, 200줄 이내)
  - [ ] TODO / In Progress / Done 항목

## shared-context-config.json 체크리스트 (agent/pair만)

- [ ] `filters`에 새 에이전트 이름의 키가 추가됨
- [ ] 필터 값이 에이전트 역할에 맞게 설정됨
- [ ] JSON 형식이 유효함
