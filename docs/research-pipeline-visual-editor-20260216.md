# Pipeline Visual Editor 설계 분석

> 날짜: 2026-02-16
> 주제: 노드 기반 그래프 에디터로 Orchestrator 파이프라인을 시각적으로 작성하는 웹 UI

## 개요

현재 Orchestrator는 레시피(텍스트 기반 스킬 조합 패턴)를 참고하여 동적으로 워크플로우를 구성한다. 사용자의 아이디어는 이 레시피를 **노드 기반 그래프 UI**로 시각화하여, 스킬과 에이전트를 노드로 배치하고 연결선으로 파이프라인을 구성한 뒤, 파일로 저장하여 Orchestrator가 실행하는 것이다.

---

## 1. 기술 스택 및 구현 방식

### 1.1 노드 기반 그래프 에디터 라이브러리

| 라이브러리 | 장점 | 단점 | 적합도 |
|-----------|------|------|--------|
| **React Flow** | 가장 활발한 생태계, 문서 풍부, 커스텀 노드 쉬움, MIT | React 필수 | 최적 |
| rete.js | 프레임워크 무관, 비주얼 프로그래밍 특화 | 학습 곡선 높음, 커뮤니티 작음 | 보통 |
| Litegraph.js | 순수 Canvas, 의존성 없음 | UI 커스터마이징 어려움, React 통합 번거로움 | 낮음 |
| JointJS | 다이어그램 전문 | 상용 라이센스 필요 (Rappid) | 낮음 |
| Drawflow | 경량, 바닐라JS | 기능 제한, 복잡한 그래프 지원 약함 | 낮음 |

**추천: React Flow**

이유:
- 노드 커스터마이징이 자유로움 (React 컴포넌트 = 노드)
- 핸들(포트) 시스템이 내장되어 성공/실패 분기 표현에 적합
- 미니맵, 줌, 패닝, 선택, 정렬 등 편의 기능 내장
- npm 주간 다운로드 100만+, 유지보수 활발
- 파이프라인/워크플로우 에디터 레퍼런스가 많음

### 1.2 프론트엔드 기술 스택

```
React + TypeScript + React Flow + Zustand(상태관리) + Tailwind CSS
```

- **React + TypeScript**: React Flow가 React 기반이므로 자연스러운 선택. 타입 안전성으로 노드/엣지 데이터 구조 관리
- **Zustand**: 그래프 상태(노드, 엣지, 선택 상태)를 경량으로 관리. React Flow 공식 예제에서도 사용
- **Tailwind CSS**: 노드 UI를 빠르게 스타일링

### 1.3 실행 환경

**로컬 정적 서버 방식을 추천한다.**

| 방식 | 설명 | 장단점 |
|------|------|--------|
| **정적 HTML (SPA)** | Vite로 빌드 후 `dist/index.html` 하나로 배포 | 서버 불필요, 브라우저에서 바로 열림 |
| 로컬 dev 서버 | `npm run dev`로 Vite dev server 실행 | 개발 중에만 사용 |
| 별도 서버 | Express/FastAPI 등 백엔드 | 파일 저장/읽기에 유리하지만 과잉 |

**파일 저장/읽기 문제:**

정적 SPA에서는 파일시스템 직접 접근이 불가하므로:

- **저장**: File System Access API (`showSaveFilePicker`) 사용. Chromium 기반 브라우저에서 지원. 또는 다운로드 방식 (`Blob + URL.createObjectURL`)
- **불러오기**: `<input type="file">` 또는 File System Access API (`showOpenFilePicker`)
- **대안**: 간단한 로컬 서버 (Python `http.server` 수준)를 두고 REST API로 `.claude/pipelines/` 디렉토리를 읽기/쓰기

현실적인 MVP 접근:
1. SPA로 빌드하되, 파일 저장/불러오기는 다운로드/업로드 방식
2. 이후 필요하면 간단한 로컬 서버를 추가하여 `.claude/pipelines/` 디렉토리와 직접 연동

---

## 2. 노드 설계

### 2.1 노드 유형

두 종류의 노드를 명확히 구분한다:

#### 스킬 노드 (실행 단위)

스킬은 **실제로 실행되는 단위**다. 파이프라인의 핵심 구성 요소.

```
+----------------------------+
|  [code icon]  code         |  <- 헤더 (파란색 배경)
|----------------------------|
|  코드 작성/수정/진단/패치    |  <- 설명
|  agent: coder              |  <- 사용 에이전트
|----------------------------|
|  args: [           ]       |  <- 인자 입력 필드
|----------------------------|
|  (in) ●            ● (ok)  |  <- 입력/성공 포트
|                    ● (fail)|  <- 실패 포트
+----------------------------+
```

표시 정보:
- **이름**: 스킬 식별자 (code, test, blueprint 등)
- **설명**: 스킬의 용도 요약 (description의 첫 줄)
- **에이전트**: 실행에 사용되는 에이전트
- **인자 필드**: 실행 시 전달할 arguments (텍스트 입력)
- **포트**: 입력(in), 성공(ok), 실패(fail)

11개 스킬을 모두 노드로 제공:
code, test, blueprint, commit, deploy, security-scan, deepresearch, decide, scaffold, team-review, qa-swarm

#### 에이전트 노드 (리뷰/탐색용)

에이전트는 `Task()`로 호출되는 **리뷰/탐색 전용** 노드다. 스킬과 구분하기 위해 다른 색상/형태를 사용한다.

```
+----------------------------+
|  [agent icon]  reviewer    |  <- 헤더 (녹색 배경)
|----------------------------|
|  코드 품질 리뷰              |  <- 설명
|  model: opus               |  <- 모델
|----------------------------|
|  prompt: [           ]     |  <- 프롬프트 입력
|----------------------------|
|  (in) ●            ● (ok)  |
|                    ● (fail)|
+----------------------------+
```

파이프라인에서 직접 사용되는 에이전트 4개:
navigator, reviewer, security, architect

(coder, committer, researcher, orchestrator는 스킬의 실행 주체이므로 별도 노드로 표시하지 않음)

### 2.2 제어 흐름 노드

스킬/에이전트 외에 흐름 제어를 위한 특수 노드가 필요하다:

#### Start / End 노드

```
  (Start) ●──────●  (End)
```

모든 파이프라인의 진입점과 종료점.

#### 병렬 게이트 (Fork / Join)

```
         ● (out 1)
(in) ●───● (out 2)     Fork: 입력을 여러 경로로 동시 분기
         ● (out 3)

(in 1) ●
(in 2) ●───● (out)     Join: 모든 입력이 완료되면 진행
(in 3) ●
```

#### 조건 분기 (Condition)

```
+----------------------------+
|  [if icon]  Condition      |
|----------------------------|
|  조건: [exit_code == 0   ] |
|----------------------------|
|  (in) ●       ● (true)    |
|               ● (false)   |
+----------------------------+
```

일반적으로 이전 노드의 성공/실패 포트로 분기를 처리하므로, Condition 노드는 MVP에서는 생략 가능하다. 성공/실패 포트만으로 대부분의 분기를 표현할 수 있다.

#### 반복 (Retry)

```
+----------------------------+
|  [retry icon]  Retry       |
|----------------------------|
|  max: [3]  delay: [1s]     |
|----------------------------|
|  (in) ●            ● (ok) |
|  (retry-in) ●      ● (fail after max) |
+----------------------------+
```

Retry 노드는 자식 노드(또는 서브그래프)를 감싸는 형태. 실패 시 retry-in 포트로 루프백.

**간소화 대안**: Retry를 별도 노드로 두지 않고, 각 스킬 노드에 `retry: N` 속성을 추가하는 방식도 가능. MVP에서는 이 방식이 더 간단하다.

### 2.3 포트(핸들) 설계

| 포트 이름 | 위치 | 의미 |
|----------|------|------|
| `in` | 좌측 | 이 노드로의 입력 (이전 단계에서 연결) |
| `ok` | 우측 상단 | 성공 시 다음 단계로 |
| `fail` | 우측 하단 | 실패 시 분기 (에러 핸들링, retry 등) |

색상 코딩:
- `in`: 회색 (중립)
- `ok`: 녹색 (성공)
- `fail`: 빨간색 (실패)

### 2.4 병렬 실행 표현

Fork 노드에서 여러 출력을 내보내고, Join 노드에서 모든 입력을 대기한다.

```
                    ┌──→ [reviewer]  ──┐
[code] ──→ [Fork] ──┤                  ├──→ [Join] ──→ [commit]
                    └──→ [security] ──┘
```

### 2.5 반복(Retry) 표현

MVP에서는 노드 속성으로 처리:

```
각 스킬 노드의 설정 패널:
- retry_count: 0 (기본값, 재시도 없음)
- retry_count: 2 (최대 2회 재시도)
```

fail 포트가 연결되어 있으면 retry 대신 fail 경로로 진행. fail 포트가 연결되지 않았고 retry_count > 0이면 자동 재시도.

---

## 3. 파이프라인 파일 포맷

### 3.1 포맷 선택: JSON

| 포맷 | 장점 | 단점 |
|------|------|------|
| **JSON** | JS에서 네이티브 파싱, React Flow 상태와 1:1 매핑 | 사람이 읽기 약간 불편 |
| YAML | 사람이 읽기 편함 | JS에서 별도 파서 필요, 들여쓰기 실수 |
| Markdown | 사람이 읽기 최적 | 그래프 구조 표현 부적합, 파싱 복잡 |
| TOML | 설정에 적합 | 중첩 구조 표현 불편 |

**JSON을 추천한다.**

이유:
- React Flow의 노드/엣지 상태가 이미 JSON 구조
- Orchestrator가 별도 라이브러리 없이 파싱 가능
- 그래프 구조(노드 + 엣지)를 자연스럽게 표현
- `.claude/pipelines/*.json`으로 저장

사람의 가독성은 UI가 담당한다. 파일을 직접 편집할 필요가 없으므로 JSON의 가독성 단점은 문제가 아니다.

### 3.2 파일 구조

```json
{
  "name": "feature-implementation",
  "description": "기능 구현 기본 파이프라인",
  "version": "1.0",
  "created": "2026-02-16T10:00:00Z",
  "modified": "2026-02-16T10:00:00Z",

  "nodes": [
    {
      "id": "start-1",
      "type": "start",
      "position": { "x": 0, "y": 200 }
    },
    {
      "id": "nav-1",
      "type": "agent",
      "data": {
        "agent": "navigator",
        "prompt": "대상 코드베이스 탐색"
      },
      "config": {
        "retry_count": 0
      },
      "position": { "x": 200, "y": 200 }
    },
    {
      "id": "code-1",
      "type": "skill",
      "data": {
        "skill": "code",
        "args": "구현 스펙에 따라 코드 작성"
      },
      "config": {
        "retry_count": 1
      },
      "position": { "x": 400, "y": 200 }
    },
    {
      "id": "test-1",
      "type": "skill",
      "data": {
        "skill": "test",
        "args": "--regression"
      },
      "config": {
        "retry_count": 2
      },
      "position": { "x": 600, "y": 200 }
    },
    {
      "id": "fork-1",
      "type": "fork",
      "position": { "x": 800, "y": 200 }
    },
    {
      "id": "review-1",
      "type": "agent",
      "data": {
        "agent": "reviewer",
        "prompt": "코드 품질 리뷰"
      },
      "position": { "x": 1000, "y": 100 }
    },
    {
      "id": "sec-1",
      "type": "agent",
      "data": {
        "agent": "security",
        "prompt": "보안 리뷰"
      },
      "position": { "x": 1000, "y": 300 }
    },
    {
      "id": "join-1",
      "type": "join",
      "position": { "x": 1200, "y": 200 }
    },
    {
      "id": "commit-1",
      "type": "skill",
      "data": {
        "skill": "commit",
        "args": ""
      },
      "position": { "x": 1400, "y": 200 }
    },
    {
      "id": "end-1",
      "type": "end",
      "position": { "x": 1600, "y": 200 }
    }
  ],

  "edges": [
    { "id": "e1", "source": "start-1", "target": "nav-1", "sourceHandle": "ok" },
    { "id": "e2", "source": "nav-1", "target": "code-1", "sourceHandle": "ok" },
    { "id": "e3", "source": "code-1", "target": "test-1", "sourceHandle": "ok" },
    { "id": "e4", "source": "test-1", "target": "fork-1", "sourceHandle": "ok" },
    { "id": "e5", "source": "fork-1", "target": "review-1", "sourceHandle": "out-0" },
    { "id": "e6", "source": "fork-1", "target": "sec-1", "sourceHandle": "out-1" },
    { "id": "e7", "source": "review-1", "target": "join-1", "sourceHandle": "ok" },
    { "id": "e8", "source": "sec-1", "target": "join-1", "sourceHandle": "ok" },
    { "id": "e9", "source": "join-1", "target": "commit-1", "sourceHandle": "ok" },
    { "id": "e10", "source": "commit-1", "target": "end-1", "sourceHandle": "ok" },
    { "id": "e11", "source": "test-1", "target": "code-1", "sourceHandle": "fail", "label": "fix & retry" }
  ],

  "variables": {
    "worktree_path": "",
    "branch_name": ""
  }
}
```

### 3.3 핵심 설계 결정

- **position**: UI 레이아웃용. Orchestrator는 무시한다. 하지만 UI에서 복원할 때 필요하므로 저장.
- **config.retry_count**: 노드 단위 재시도. Orchestrator가 실행 시 참조.
- **variables**: 파이프라인 전역 변수. 런타임에 Orchestrator가 채움.
- **edges의 sourceHandle**: ok/fail/out-N 등으로 분기 경로를 표현.

---

## 4. 기존 시스템과의 연동

### 4.1 스킬/에이전트 자동 로드

웹 UI가 `.claude/skills/*/SKILL.md`와 `.claude/agents/*.md`를 읽어야 한다.

**접근 방식 A: 빌드 타임 추출 (추천)**

빌드 스크립트(또는 npm 스크립트)가 스킬/에이전트 파일을 스캔하여 메타데이터 JSON을 생성한다:

```bash
# 빌드 시 실행
node scripts/extract-metadata.js
# 결과: src/data/skills.json, src/data/agents.json
```

`skills.json` 예시:
```json
[
  {
    "name": "code",
    "description": "코드 작성/수정/진단/패치",
    "agent": "coder",
    "userInvocable": true,
    "argumentHint": "<작업 지시>"
  },
  ...
]
```

장점: SPA에서 추가 서버 없이 메타데이터 사용 가능.
단점: 스킬/에이전트 변경 시 다시 빌드해야 함.

**접근 방식 B: 런타임 로드 (로컬 서버 필요)**

간단한 API 서버가 `.claude/` 디렉토리를 스캔하여 메타데이터를 반환한다:

```
GET /api/skills → 스킬 목록 + 메타데이터
GET /api/agents → 에이전트 목록 + 메타데이터
GET /api/pipelines → 저장된 파이프라인 목록
POST /api/pipelines → 새 파이프라인 저장
```

장점: 스킬/에이전트 변경이 실시간 반영.
단점: 서버 프로세스 필요.

**추천: 접근 방식 A (빌드 타임) + 수동 리프레시 버튼**

MVP에서는 빌드 타임 추출이 단순하다. 스킬/에이전트가 자주 변경되지 않으므로 충분하다. 변경 시 `npm run build`로 재빌드하면 반영된다.

### 4.2 스킬/에이전트 변경 시 자동 반영

빌드 타임 방식에서는 자동 반영이 불가능하지만, 개발 중에는 Vite의 watch 모드가 `scripts/extract-metadata.js`를 트리거할 수 있다.

프로덕션에서는:
- 스킬/에이전트 추가/변경 후 `npm run build` 실행
- 또는 `harness.sh`에 빌드 단계 추가

### 4.3 Orchestrator가 파이프라인 파일을 읽는 방식

Orchestrator의 실행 흐름을 수정한다:

```
현재: 사용자 요청 → Orchestrator가 레시피 참조하여 동적 계획 수립 → 실행
변경: 사용자 요청 + 파이프라인 지정 → Orchestrator가 파이프라인 파일 로드 → 그래프 순회하며 실행
```

구체적으로:
1. 사용자가 "pipeline: feature-implementation" 또는 이에 상응하는 지시를 하면
2. Orchestrator가 `.claude/pipelines/feature-implementation.json`을 Read로 읽음
3. JSON을 파싱하여 그래프 구조(노드 + 엣지)를 이해
4. 토폴로지 순서대로 노드를 실행:
   - `skill` 타입 → `Skill(data.skill, data.args)`
   - `agent` 타입 → `Task(data.agent, data.prompt)`
   - `fork` 타입 → 병렬 실행 시작
   - `join` 타입 → 병렬 실행 대기
5. 각 노드의 ok/fail 결과에 따라 다음 엣지를 선택
6. retry_count > 0이면 실패 시 재시도

**Orchestrator 프롬프트에 추가해야 할 것:**

파이프라인 실행 프로토콜 섹션을 orchestrator.md에 추가한다. 파이프라인 JSON의 구조와 실행 규칙을 명시한다.

**주의사항:**

- Orchestrator는 LLM이므로 JSON을 "파싱"한다기보다 "읽고 이해"한다
- 복잡한 그래프(10+ 노드)에서 실행 순서를 정확히 따를 수 있는지 검증 필요
- 토폴로지 정렬은 LLM이 하기보다, 실행 전에 전처리(스크립트)로 순서를 결정해두는 것이 안전

### 4.4 동적 파이프라인 vs 정적 파이프라인

현재 Orchestrator의 강점은 **동적 적응**이다. 파이프라인은 정적 워크플로우이므로 이 강점을 잃을 수 있다.

공존 방식:
- **파이프라인 미지정**: 기존처럼 동적 레시피 기반 실행
- **파이프라인 지정**: 파이프라인 파일의 그래프를 충실히 따라 실행
- **파이프라인 + override**: 파이프라인을 기본 골격으로 하되, 사용자의 추가 지시에 따라 일부 노드를 건너뛰거나 추가 가능

---

## 5. 실현 가능성 평가

### 5.1 MVP 핵심 기능

MVP에서 반드시 필요한 것:

1. **캔버스**: React Flow 기반 드래그 앤 드롭 캔버스
2. **노드 팔레트**: 11개 스킬 + 4개 에이전트(navigator, reviewer, security, architect) 목록을 사이드바에 표시, 드래그로 캔버스에 배치
3. **엣지 연결**: 노드의 포트(ok/fail)를 마우스로 드래그하여 연결
4. **노드 설정**: 노드 클릭 시 인자(args/prompt) 입력 패널
5. **저장/불러오기**: JSON으로 직렬화하여 다운로드/업로드
6. **Start/End 노드**: 파이프라인의 시작과 끝 표시

### 5.2 MVP 이후 확장

- Fork/Join 노드 (병렬 실행)
- 노드별 retry_count 설정
- `.claude/pipelines/` 디렉토리 직접 읽기/쓰기 (로컬 서버)
- 파이프라인 실행 상태 실시간 표시 (실행 중인 노드 하이라이트)
- 파이프라인 템플릿 (현재 레시피를 사전 정의된 파이프라인으로 제공)
- 스킬/에이전트 메타데이터 런타임 자동 로드
- 파이프라인 유효성 검증 (순환 참조, 연결 안 된 노드 경고)

### 5.3 핵심 리스크

| 리스크 | 설명 | 완화 방안 |
|--------|------|----------|
| LLM의 그래프 실행 정확도 | Orchestrator가 JSON 그래프를 100% 정확히 순회할 수 있는가 | 토폴로지 정렬을 전처리로 하여 실행 순서 리스트로 제공 |
| 동적 적응 상실 | 정적 파이프라인이 Orchestrator의 강점을 무력화 | 파이프라인은 "골격", 세부는 Orchestrator가 적응 |
| 파일 I/O | SPA에서 로컬 파일시스템 접근 제한 | File System Access API 또는 다운로드/업로드 |
| 유지보수 | 스킬/에이전트 변경 시 UI 메타데이터 동기화 | 빌드 타임 추출 스크립트 자동화 |

### 5.4 배포 형태

기존 claude-dashboard(`~/Projects/claude-dashboard`)와 같은 방식:
- 독립 레포 (예: `~/Projects/pipeline-editor`)
- Vite로 빌드, `dist/` 디렉토리에 정적 파일 생성
- Docker로 배포하거나 로컬에서 `npx serve dist/`로 실행
- 또는 claude-dashboard에 탭/페이지로 통합

### 5.5 프로젝트 구조 (참고)

```
pipeline-editor/
  src/
    components/
      Canvas.tsx          # React Flow 캔버스
      NodePalette.tsx     # 사이드바 노드 목록
      SkillNode.tsx       # 스킬 커스텀 노드 컴포넌트
      AgentNode.tsx       # 에이전트 커스텀 노드 컴포넌트
      ControlNode.tsx     # Start/End/Fork/Join 노드
      NodeConfigPanel.tsx # 노드 설정 사이드 패널
    data/
      skills.json         # 빌드 타임 추출된 스킬 메타데이터
      agents.json         # 빌드 타임 추출된 에이전트 메타데이터
    store/
      pipelineStore.ts    # Zustand 상태 관리
    utils/
      serializer.ts       # JSON 직렬화/역직렬화
      validator.ts        # 파이프라인 유효성 검증
    App.tsx
    main.tsx
  scripts/
    extract-metadata.js   # SKILL.md/agent.md에서 메타데이터 추출
  public/
  package.json
  vite.config.ts
```

---

## 6. 주요 포인트 요약

1. **기술 스택**: React + TypeScript + React Flow + Zustand + Tailwind CSS
2. **노드**: 스킬 노드(11개, 파란색) + 에이전트 노드(4개, 녹색) + 제어 노드(Start/End/Fork/Join)
3. **포트**: in(입력), ok(성공), fail(실패) - 성공/실패로 분기, retry는 노드 속성으로
4. **파일 포맷**: JSON (.claude/pipelines/*.json)
5. **메타데이터 로드**: 빌드 타임에 SKILL.md/agent.md에서 추출
6. **Orchestrator 연동**: 파이프라인 JSON을 Read로 읽고 그래프를 순회하며 Skill()/Task() 호출
7. **MVP 범위**: 캔버스 + 노드 팔레트 + 엣지 연결 + 노드 설정 + 저장/불러오기
8. **기존 시스템과 공존**: 파이프라인 미지정 시 기존 동적 레시피 유지

## 출처

- React Flow: https://reactflow.dev/
- File System Access API: https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API
- Zustand: https://github.com/pmndrs/zustand
