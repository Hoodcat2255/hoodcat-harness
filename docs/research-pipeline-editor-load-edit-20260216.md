# Pipeline Editor: 파일 불러오기/편집/저장 기능 설계

> 날짜: 2026-02-16
> 주제: 기존 파이프라인 JSON 파일을 불러와서 편집하고 다시 저장하는 기능의 UX, 기술 설계
> 관련 문서:
> - `docs/research-pipeline-visual-editor-20260216.md` (비주얼 에디터 초기 설계)
> - `docs/research-pipeline-json-schema-20260216.md` (JSON 스키마 정식 설계)

---

## 1. 현재 설계 상태와 갭 분석

### 1.1 완료된 설계

| 항목 | 상태 | 문서 |
|------|------|------|
| 기술 스택 (React Flow + Zustand + Tailwind) | 완료 | visual-editor |
| 노드 8종 + 포트 설계 | 완료 | json-schema |
| JSON 스키마 (nodes, edges, variables, validation) | 완료 | json-schema |
| React Flow 1:1 매핑 | 완료 | json-schema 6장 |
| Orchestrator 실행 시맨틱 | 완료 | json-schema 4장 |
| 새 파이프라인 생성 + 다운로드 | 설계만 | visual-editor 1.3장 |

### 1.2 미설계 영역 (이 문서에서 다룸)

| 항목 | 현재 상태 | 필요한 것 |
|------|----------|----------|
| 파이프라인 파일 목록 탐색 | 미설계 | 파일 목록 UI + 데이터 소스 |
| JSON -> React Flow 역직렬화 | 매핑 규칙만 정의 | 구체적 변환 로직 + 에러 처리 |
| 편집 상태 관리 (undo/redo, dirty state) | 미설계 | Zustand 스토어 확장 |
| 편집 후 재저장 | 다운로드만 언급 | 덮어쓰기/새파일/클립보드 |
| 파이프라인 메타데이터 편집 | 미설계 | name, description, tags, variables, validation 편집 UI |
| 스키마 버전 호환성 | 미설계 | 구버전 파일 마이그레이션 |

---

## 2. 전체 UX 흐름

### 2.1 진입점 설계

에디터를 열었을 때의 랜딩 화면.

```
+------------------------------------------------------------------+
|  Pipeline Editor                                    [설정]       |
|------------------------------------------------------------------|
|                                                                   |
|   +-------------------------------------------+                  |
|   |          최근 파이프라인                      |                  |
|   |  +--------------------------------------+  |                  |
|   |  | feature-implementation     2분 전   [열기]|                  |
|   |  | bugfix-with-diagnosis     1시간 전  [열기]|                  |
|   |  | security-hotfix           어제      [열기]|                  |
|   |  +--------------------------------------+  |                  |
|   +-------------------------------------------+                  |
|                                                                   |
|   [+ 새 파이프라인 만들기]                                         |
|   [파일에서 불러오기...]                                           |
|   [클립보드에서 불러오기]                                          |
|                                                                   |
+------------------------------------------------------------------+
```

**3가지 진입 경로:**

1. **최근 파이프라인 목록에서 선택** - 이전에 편집/저장한 파이프라인 빠른 접근
2. **새 파이프라인 만들기** - 빈 캔버스 (Start + End 노드만)
3. **파일에서 불러오기** - 로컬 파일 시스템에서 JSON 파일 선택
4. **클립보드에서 불러오기** - JSON 텍스트를 붙여넣기

### 2.2 불러오기 흐름 (Load Flow)

```
[사용자가 파일 선택]
    |
    v
[JSON 파싱]  -- 실패 --> [에러 다이얼로그: "유효한 JSON이 아닙니다"]
    |
    (성공)
    v
[스키마 검증]  -- 경고 --> [경고 다이얼로그: "version 1.0이 아닙니다. 변환을 시도합니다"]
    |
    (통과/변환 성공)
    v
[JSON -> React Flow 변환 (역직렬화)]
    |
    v
[캔버스에 렌더링]
    |
    v
[fitView() 호출 - 모든 노드가 보이도록 줌 조정]
    |
    v
[메타데이터 패널에 name, description, tags 표시]
    |
    v
[편집 가능 상태 (dirty = false)]
```

### 2.3 편집 흐름 (Edit Flow)

```
[캔버스 편집 모드]
    |
    +-- 노드 추가: 사이드바 팔레트에서 드래그 앤 드롭 -> dirty = true
    +-- 노드 삭제: 선택 후 Delete 키 또는 우클릭 메뉴 -> dirty = true
    +-- 노드 이동: 드래그 -> dirty = true (position 변경)
    +-- 노드 설정: 클릭 -> 설정 패널에서 args/prompt/retry 편집 -> dirty = true
    +-- 엣지 추가: 포트에서 드래그하여 다른 노드 포트에 연결 -> dirty = true
    +-- 엣지 삭제: 엣지 선택 후 Delete -> dirty = true
    +-- 엣지 재연결: 기존 엣지를 드래그하여 다른 포트로 이동 -> dirty = true
    +-- 메타데이터 편집: name/description/tags/variables/validation 변경 -> dirty = true
    |
    +-- Undo: Ctrl+Z -> 이전 상태 복원
    +-- Redo: Ctrl+Shift+Z -> 다시 적용
    |
    v
[저장 트리거]
```

### 2.4 저장 흐름 (Save Flow)

```
[사용자가 저장 클릭] (Ctrl+S 또는 저장 버튼)
    |
    v
[React Flow -> JSON 직렬화]
    |
    v
[modified 타임스탬프 갱신]
    |
    v
[유효성 검증] -- 경고 --> [경고 목록 표시 + "저장하시겠습니까?" 확인]
    |
    (통과)
    v
[저장 방식 선택]
    |
    +-- [기존 파일 덮어쓰기] (원본 파일명으로 다운로드)
    +-- [다른 이름으로 저장] (새 파일명 입력 -> 다운로드)
    +-- [클립보드에 복사] (JSON 텍스트를 클립보드에)
    |
    v
[dirty = false]
[최근 파이프라인 목록 갱신 (localStorage)]
```

### 2.5 이탈 방지

```
[사용자가 브라우저 탭을 닫으려 함 / 다른 파이프라인을 열려 함]
    |
    v
[dirty == true?]
    |
    (예) --> "저장하지 않은 변경사항이 있습니다. 저장하시겠습니까?"
    |         [저장] [저장하지 않고 나가기] [취소]
    |
    (아니오) --> 바로 진행
```

---

## 3. 기술 구현 설계

### 3.1 파일 불러오기 방식

SPA에서 로컬 파일을 불러오는 3가지 방식을 모두 지원한다.

#### 방식 A: File Input (모든 브라우저)

```typescript
// FileLoader.tsx
const handleFileUpload = (e: React.ChangeEvent<HTMLInputElement>) => {
  const file = e.target.files?.[0];
  if (!file) return;

  const reader = new FileReader();
  reader.onload = (event) => {
    const json = event.target?.result as string;
    loadPipeline(json, file.name);
  };
  reader.readAsText(file);
};
```

- 장점: 100% 브라우저 호환
- 단점: 매번 파일 탐색기를 열어야 함

#### 방식 B: File System Access API (Chromium 기반)

```typescript
// FileLoader.tsx
const handleOpenFile = async () => {
  try {
    const [fileHandle] = await window.showOpenFilePicker({
      types: [{
        description: 'Pipeline JSON',
        accept: { 'application/json': ['.json'] }
      }],
      startIn: 'documents'  // .claude/pipelines/ 경로를 기억
    });

    const file = await fileHandle.getFile();
    const json = await file.text();
    loadPipeline(json, file.name);

    // 파일 핸들을 저장하여 나중에 같은 파일에 덮어쓰기 가능
    setCurrentFileHandle(fileHandle);
  } catch (err) {
    if (err.name !== 'AbortError') console.error(err);
  }
};
```

- 장점: 파일 핸들을 유지하여 덮어쓰기 저장 가능, 디렉토리 접근 가능
- 단점: Chromium 기반 브라우저만 지원 (Chrome, Edge, Arc)
- **추천**: 가능한 환경에서는 이 방식을 기본으로 사용

#### 방식 C: Drag & Drop

```typescript
// Canvas.tsx (또는 전체 앱 영역)
const handleDrop = (e: React.DragEvent) => {
  e.preventDefault();
  const file = e.dataTransfer.files[0];
  if (file?.type === 'application/json' || file?.name.endsWith('.json')) {
    const reader = new FileReader();
    reader.onload = (event) => {
      loadPipeline(event.target?.result as string, file.name);
    };
    reader.readAsText(file);
  }
};
```

- 장점: 직관적, 추가 UI 불필요
- 용도: 파일 탐색기에서 JSON 파일을 에디터 창으로 드래그

#### 방식 D: 클립보드 붙여넣기

```typescript
const handlePasteFromClipboard = async () => {
  try {
    const text = await navigator.clipboard.readText();
    loadPipeline(text, 'clipboard-pipeline.json');
  } catch (err) {
    // 권한 거부 시 textarea 입력으로 폴백
    setShowPasteDialog(true);
  }
};
```

- 용도: 다른 사람이 공유한 파이프라인 JSON을 빠르게 로드

#### 기능 감지 및 폴백

```typescript
const hasFileSystemAccess = 'showOpenFilePicker' in window;

// UI에서 조건부 렌더링
{hasFileSystemAccess ? (
  <button onClick={handleOpenFile}>파일 열기</button>
) : (
  <label>
    파일 선택
    <input type="file" accept=".json" onChange={handleFileUpload} hidden />
  </label>
)}
```

### 3.2 JSON -> React Flow 역직렬화 (Deserializer)

기존 스키마 문서(json-schema 6장)에서 1:1 매핑 규칙이 정의되어 있다. 구체적인 변환 로직을 설계한다.

#### 핵심 변환 함수

```typescript
// utils/deserializer.ts

interface PipelineJSON {
  name: string;
  description?: string;
  version: string;
  created?: string;
  modified?: string;
  tags?: string[];
  variables?: Record<string, string>;
  validation?: ValidationConfig;
  nodes: PipelineNode[];
  edges: PipelineEdge[];
}

interface DeserializeResult {
  nodes: ReactFlowNode[];
  edges: ReactFlowEdge[];
  metadata: PipelineMetadata;
  warnings: string[];
}

function deserializePipeline(json: PipelineJSON): DeserializeResult {
  const warnings: string[] = [];

  // 1. 스키마 버전 확인
  if (json.version !== '1.0') {
    warnings.push(`스키마 버전 ${json.version}은 지원되지 않습니다. 변환을 시도합니다.`);
  }

  // 2. 노드 변환
  const nodes: ReactFlowNode[] = json.nodes.map(node => {
    const rfNode: ReactFlowNode = {
      id: node.id,
      type: node.type,  // 커스텀 노드 유형으로 등록되어 있어야 함
      position: node.position ?? { x: 0, y: 0 },
      data: {
        ...node.data,
        label: node.label ?? node.data?.skill ?? node.data?.agent ?? node.type,
      },
    };

    // position이 없는 경우 자동 배치
    if (!node.position) {
      warnings.push(`노드 "${node.id}"에 position이 없습니다. 자동 배치됩니다.`);
    }

    return rfNode;
  });

  // 3. 엣지 변환
  const edges: ReactFlowEdge[] = json.edges.map(edge => ({
    id: edge.id,
    source: edge.source,
    target: edge.target,
    sourceHandle: edge.sourceHandle,
    targetHandle: edge.targetHandle ?? 'in',
    label: edge.label,
    animated: edge.animated ?? false,
    style: edge.style,
    // 커스텀 데이터 보존
    data: {
      maxTraversals: edge.maxTraversals,
    },
  }));

  // 4. 메타데이터 추출
  const metadata: PipelineMetadata = {
    name: json.name,
    description: json.description ?? '',
    version: json.version,
    created: json.created ?? new Date().toISOString(),
    modified: json.modified ?? new Date().toISOString(),
    tags: json.tags ?? [],
    variables: json.variables ?? {},
    validation: json.validation ?? { criteria: [], on_failure: 'report' },
  };

  // 5. 무결성 검증
  const nodeIds = new Set(nodes.map(n => n.id));
  edges.forEach(edge => {
    if (!nodeIds.has(edge.source)) {
      warnings.push(`엣지 "${edge.id}"의 source "${edge.source}"가 존재하지 않습니다.`);
    }
    if (!nodeIds.has(edge.target)) {
      warnings.push(`엣지 "${edge.id}"의 target "${edge.target}"가 존재하지 않습니다.`);
    }
  });

  return { nodes, edges, metadata, warnings };
}
```

#### 자동 레이아웃 (position 누락 시)

position이 없는 노드가 있을 경우 dagre 라이브러리로 자동 배치한다.

```typescript
// utils/autoLayout.ts
import dagre from 'dagre';

function autoLayout(
  nodes: ReactFlowNode[],
  edges: ReactFlowEdge[],
  direction: 'LR' | 'TB' = 'LR'  // 좌->우 (기본) 또는 상->하
): ReactFlowNode[] {
  const g = new dagre.graphlib.Graph();
  g.setDefaultEdgeLabel(() => ({}));
  g.setGraph({
    rankdir: direction,
    nodesep: 80,   // 수직 간격
    ranksep: 200,  // 수평 간격
  });

  nodes.forEach(node => {
    g.setNode(node.id, { width: 280, height: 120 });
  });

  edges.forEach(edge => {
    g.setEdge(edge.source, edge.target);
  });

  dagre.layout(g);

  return nodes.map(node => {
    const pos = g.node(node.id);
    return {
      ...node,
      position: { x: pos.x - 140, y: pos.y - 60 },
    };
  });
}
```

#### 스키마 검증 함수

```typescript
// utils/validator.ts

interface ValidationResult {
  valid: boolean;
  errors: string[];
  warnings: string[];
}

function validatePipeline(json: unknown): ValidationResult {
  const errors: string[] = [];
  const warnings: string[] = [];

  // 필수 필드 검증
  if (!json || typeof json !== 'object') {
    return { valid: false, errors: ['유효한 JSON 객체가 아닙니다'], warnings: [] };
  }

  const p = json as Record<string, unknown>;

  if (!p.name) errors.push('name 필드가 필요합니다');
  if (!p.version) errors.push('version 필드가 필요합니다');
  if (!Array.isArray(p.nodes)) errors.push('nodes 배열이 필요합니다');
  if (!Array.isArray(p.edges)) errors.push('edges 배열이 필요합니다');

  if (errors.length > 0) return { valid: false, errors, warnings };

  const nodes = p.nodes as Array<Record<string, unknown>>;
  const edges = p.edges as Array<Record<string, unknown>>;

  // Start/End 노드 존재 확인
  const hasStart = nodes.some(n => n.type === 'start');
  const hasEnd = nodes.some(n => n.type === 'end');
  if (!hasStart) errors.push('start 노드가 필요합니다');
  if (!hasEnd) errors.push('end 노드가 필요합니다');

  // 노드 ID 중복 검사
  const ids = nodes.map(n => n.id as string);
  const duplicates = ids.filter((id, i) => ids.indexOf(id) !== i);
  if (duplicates.length > 0) {
    errors.push(`노드 ID 중복: ${duplicates.join(', ')}`);
  }

  // 고립 노드 검사 (start/end 제외)
  const nodeIds = new Set(ids);
  const connectedNodes = new Set<string>();
  edges.forEach(e => {
    connectedNodes.add(e.source as string);
    connectedNodes.add(e.target as string);
  });
  nodes.forEach(n => {
    if (n.type !== 'start' && n.type !== 'end' && !connectedNodes.has(n.id as string)) {
      warnings.push(`노드 "${n.id}"이 어떤 엣지에도 연결되어 있지 않습니다`);
    }
  });

  // Fork/Join 쌍 검사
  const forks = nodes.filter(n => n.type === 'fork');
  const joins = nodes.filter(n => n.type === 'join');
  if (forks.length !== joins.length) {
    warnings.push(`Fork(${forks.length})와 Join(${joins.length}) 수가 일치하지 않습니다`);
  }

  // 순환 참조 검사 (루프백 엣지 제외)
  // - maxTraversals가 있는 엣지는 의도된 루프이므로 제외
  // - Loop 노드와 연결된 엣지도 제외
  // - 나머지 엣지에서 순환이 발견되면 경고

  return {
    valid: errors.length === 0,
    errors,
    warnings
  };
}
```

### 3.3 편집 상태 관리 (Zustand Store 확장)

기존 visual-editor 설계의 `pipelineStore.ts`를 확장한다.

```typescript
// store/pipelineStore.ts
import { create } from 'zustand';
import { temporal } from 'zundo';  // undo/redo 미들웨어

interface PipelineMetadata {
  name: string;
  description: string;
  version: string;
  created: string;
  modified: string;
  tags: string[];
  variables: Record<string, string>;
  validation: ValidationConfig;
}

interface PipelineState {
  // --- React Flow 상태 ---
  nodes: ReactFlowNode[];
  edges: ReactFlowEdge[];

  // --- 메타데이터 ---
  metadata: PipelineMetadata;

  // --- 편집 상태 ---
  dirty: boolean;
  currentFileName: string | null;      // 현재 열린 파일명 (null이면 새 파이프라인)
  currentFileHandle: FileSystemFileHandle | null;  // File System Access API 핸들

  // --- 최근 파일 ---
  recentFiles: RecentFile[];  // localStorage에 저장

  // --- 액션 ---
  // 불러오기
  loadFromJSON: (json: string, fileName?: string) => DeserializeResult;
  loadFromFileHandle: (handle: FileSystemFileHandle) => Promise<DeserializeResult>;

  // React Flow 이벤트 핸들러 (이미 존재, dirty 플래그 추가)
  onNodesChange: (changes: NodeChange[]) => void;
  onEdgesChange: (changes: EdgeChange[]) => void;
  onConnect: (connection: Connection) => void;

  // 노드 조작
  addNode: (type: string, position: XYPosition, data?: Record<string, unknown>) => void;
  removeNode: (id: string) => void;
  updateNodeData: (id: string, data: Partial<NodeData>) => void;

  // 엣지 조작
  removeEdge: (id: string) => void;
  reconnectEdge: (id: string, newSource: string, newSourceHandle: string) => void;

  // 메타데이터 편집
  updateMetadata: (partial: Partial<PipelineMetadata>) => void;

  // 직렬화 (저장)
  serializeToJSON: () => string;

  // 저장
  saveToFile: () => Promise<void>;        // File System Access API로 덮어쓰기
  saveAsNewFile: () => Promise<void>;     // 새 파일로 저장
  downloadAsFile: () => void;             // 다운로드로 저장
  copyToClipboard: () => Promise<void>;   // 클립보드에 복사

  // 상태 관리
  markClean: () => void;
  reset: () => void;  // 새 파이프라인으로 초기화

  // 최근 파일
  addRecentFile: (file: RecentFile) => void;
  removeRecentFile: (name: string) => void;
}

interface RecentFile {
  name: string;
  fileName: string;
  lastModified: string;
  // File System Access API의 핸들은 직렬화 불가하므로 저장하지 않음
  // 대신 IndexedDB에 핸들을 별도 저장하는 것은 향후 확장
}

// zundo (temporal middleware)로 undo/redo 지원
const usePipelineStore = create<PipelineState>()(
  temporal(
    (set, get) => ({
      nodes: [],
      edges: [],
      metadata: defaultMetadata(),
      dirty: false,
      currentFileName: null,
      currentFileHandle: null,
      recentFiles: loadRecentFiles(),  // localStorage에서 로드

      loadFromJSON: (json, fileName) => {
        const parsed = JSON.parse(json);
        const result = deserializePipeline(parsed);

        let { nodes, edges } = result;

        // position 없는 노드가 있으면 자동 배치
        const needsLayout = nodes.some(n => n.position.x === 0 && n.position.y === 0);
        if (needsLayout) {
          nodes = autoLayout(nodes, edges);
        }

        set({
          nodes,
          edges,
          metadata: result.metadata,
          dirty: false,
          currentFileName: fileName ?? null,
        });

        // 최근 파일에 추가
        if (fileName) {
          get().addRecentFile({
            name: result.metadata.name,
            fileName,
            lastModified: result.metadata.modified,
          });
        }

        return result;
      },

      // ... (나머지 구현)

      onNodesChange: (changes) => {
        set(state => ({
          nodes: applyNodeChanges(changes, state.nodes),
          dirty: true,
        }));
      },

      serializeToJSON: () => {
        const state = get();
        const pipeline: PipelineJSON = {
          ...state.metadata,
          modified: new Date().toISOString(),
          nodes: state.nodes.map(n => ({
            id: n.id,
            type: n.type,
            label: n.data.label,
            position: n.position,
            data: extractNodeData(n),  // React Flow 내부 필드 제거, 스키마 필드만 추출
          })),
          edges: state.edges.map(e => ({
            id: e.id,
            source: e.source,
            target: e.target,
            sourceHandle: e.sourceHandle,
            targetHandle: e.targetHandle,
            label: e.label as string | undefined,
            animated: e.animated,
            style: e.style,
            maxTraversals: e.data?.maxTraversals,
          })),
        };
        return JSON.stringify(pipeline, null, 2);
      },
    }),
    {
      // zundo 옵션: undo/redo 관리
      limit: 100,           // 최대 100단계 undo
      partialize: (state) => ({
        nodes: state.nodes,
        edges: state.edges,
        metadata: state.metadata,
      }),
    }
  )
);
```

#### Undo/Redo 통합

```typescript
// zundo의 temporal 미들웨어가 제공하는 API
const { undo, redo, clear: clearHistory } = useStoreWithUndo.temporal.getState();

// 키보드 단축키
useEffect(() => {
  const handler = (e: KeyboardEvent) => {
    if (e.ctrlKey && e.key === 'z' && !e.shiftKey) {
      e.preventDefault();
      undo();
    }
    if (e.ctrlKey && e.key === 'z' && e.shiftKey) {
      e.preventDefault();
      redo();
    }
    if (e.ctrlKey && e.key === 's') {
      e.preventDefault();
      handleSave();
    }
  };
  window.addEventListener('keydown', handler);
  return () => window.removeEventListener('keydown', handler);
}, []);
```

### 3.4 저장 방식 상세 설계

#### 저장 옵션 우선순위

```
1. File System Access API (덮어쓰기) - 가장 원활한 UX
2. File System Access API (다른 이름으로 저장)
3. Blob 다운로드 - 모든 브라우저 지원
4. 클립보드 복사 - 공유/전달용
```

#### File System Access API 저장

```typescript
// 기존 파일에 덮어쓰기
async function saveToExistingFile(
  handle: FileSystemFileHandle,
  json: string
): Promise<void> {
  const writable = await handle.createWritable();
  await writable.write(json);
  await writable.close();
}

// 새 파일로 저장
async function saveAsNewFile(json: string, suggestedName: string): Promise<FileSystemFileHandle> {
  const handle = await window.showSaveFilePicker({
    suggestedName: `${suggestedName}.json`,
    types: [{
      description: 'Pipeline JSON',
      accept: { 'application/json': ['.json'] }
    }],
  });
  await saveToExistingFile(handle, json);
  return handle;
}
```

#### Blob 다운로드 (폴백)

```typescript
function downloadAsFile(json: string, fileName: string): void {
  const blob = new Blob([json], { type: 'application/json' });
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = fileName;
  a.click();
  URL.revokeObjectURL(url);
}
```

#### 클립보드 복사

```typescript
async function copyToClipboard(json: string): Promise<void> {
  await navigator.clipboard.writeText(json);
  // 토스트 알림: "파이프라인 JSON이 클립보드에 복사되었습니다"
}
```

#### 저장 UI 흐름

```
[저장 버튼 클릭] 또는 [Ctrl+S]
    |
    v
[currentFileHandle 있음?]
    |
    (있음) --> File System Access API로 덮어쓰기 --> 완료
    |
    (없음) --> [저장 옵션 다이얼로그]
                |
                +-- "이 파일로 저장" (File System Access API 지원 시)
                |   -> showSaveFilePicker -> 핸들 저장 -> 완료
                |
                +-- "다운로드"
                |   -> Blob 다운로드 -> 완료
                |
                +-- "클립보드에 복사"
                    -> clipboard.writeText -> 완료
```

### 3.5 React Flow -> JSON 직렬화 (Serializer)

역직렬화의 반대 과정. React Flow 내부 필드를 정리하여 스키마 규격 JSON을 생성한다.

```typescript
// utils/serializer.ts

function serializePipeline(
  nodes: ReactFlowNode[],
  edges: ReactFlowEdge[],
  metadata: PipelineMetadata
): PipelineJSON {
  return {
    name: metadata.name,
    description: metadata.description,
    version: metadata.version,
    created: metadata.created,
    modified: new Date().toISOString(),
    tags: metadata.tags,
    variables: metadata.variables,
    validation: metadata.validation,

    nodes: nodes.map(node => {
      const pNode: PipelineNode = {
        id: node.id,
        type: node.type as NodeType,
        position: {
          x: Math.round(node.position.x),  // 소수점 제거
          y: Math.round(node.position.y),
        },
      };

      // label이 기본값이 아닌 경우만 저장
      if (node.data.label && node.data.label !== node.type) {
        pNode.label = node.data.label;
      }

      // 노드 유형별 data 추출
      pNode.data = extractDataByType(node);

      return pNode;
    }),

    edges: edges.map(edge => {
      const pEdge: PipelineEdge = {
        id: edge.id,
        source: edge.source,
        target: edge.target,
        sourceHandle: edge.sourceHandle!,
      };

      // 선택적 필드
      if (edge.targetHandle && edge.targetHandle !== 'in') {
        pEdge.targetHandle = edge.targetHandle;
      }
      if (edge.label) pEdge.label = edge.label as string;
      if (edge.animated) pEdge.animated = true;
      if (edge.style) pEdge.style = edge.style;
      if (edge.data?.maxTraversals) {
        pEdge.maxTraversals = edge.data.maxTraversals;
      }

      return pEdge;
    }),
  };
}

function extractDataByType(node: ReactFlowNode): NodeData {
  const { label, ...rest } = node.data;

  switch (node.type) {
    case 'start':
      return {};
    case 'end':
      return { status: rest.status ?? 'conditional' };
    case 'skill':
      return {
        skill: rest.skill,
        args: rest.args ?? '',
        ...(rest.retry ? { retry: rest.retry } : {}),
      };
    case 'agent':
      return {
        agent: rest.agent,
        prompt: rest.prompt ?? '',
        ...(rest.retry ? { retry: rest.retry } : {}),
      };
    case 'fork':
      return { branches: rest.branches ?? 2 };
    case 'join':
      return {
        wait_policy: rest.wait_policy ?? 'all',
        fail_policy: rest.fail_policy ?? 'any_fail',
        ...(rest.wait_count ? { wait_count: rest.wait_count } : {}),
      };
    case 'condition':
      return {
        conditions: rest.conditions ?? [],
        default_port: rest.default_port ?? 'default',
        ...(rest.evaluate_from ? { evaluate_from: rest.evaluate_from } : {}),
      };
    case 'loop':
      return {
        max_iterations: rest.max_iterations ?? 3,
        exit_condition: rest.exit_condition ?? 'body_ok',
        ...(rest.loop_back_to ? { loop_back_to: rest.loop_back_to } : {}),
      };
    default:
      return rest;
  }
}
```

---

## 4. 파이프라인 목록 관리 UI

### 4.1 데이터 소스

SPA 환경에서 파이프라인 목록을 관리하는 3가지 접근.

#### 접근 1: localStorage 기반 최근 파일 (MVP)

```typescript
interface RecentFile {
  name: string;          // 파이프라인 이름
  fileName: string;      // 파일명 (xxx.json)
  description: string;   // 설명
  lastModified: string;  // ISO 날짜
  tags: string[];        // 태그
  nodeCount: number;     // 노드 수 (미리보기용)
}

// localStorage에 저장
const STORAGE_KEY = 'pipeline-editor-recent';

function saveRecentFiles(files: RecentFile[]): void {
  // 최대 20개 유지
  const trimmed = files.slice(0, 20);
  localStorage.setItem(STORAGE_KEY, JSON.stringify(trimmed));
}

function loadRecentFiles(): RecentFile[] {
  const raw = localStorage.getItem(STORAGE_KEY);
  return raw ? JSON.parse(raw) : [];
}
```

- 장점: 서버 불필요, 즉시 구현 가능
- 단점: 실제 파일 존재 여부를 알 수 없음. 파일 내용은 저장하지 않음 (메타데이터만).
- 사용 흐름: 파일을 열 때마다 메타데이터를 최근 파일 목록에 추가. 다시 열려면 파일 선택이 필요.

#### 접근 2: IndexedDB 기반 파이프라인 캐시

```typescript
// IndexedDB에 파이프라인 JSON 전체를 캐시
// 파일을 열 때마다 IndexedDB에도 저장
// 최근 파일 목록에서 선택하면 IndexedDB에서 직접 로드

// 장점: 파일을 다시 선택하지 않아도 로드 가능
// 단점: 로컬 파일과 동기화 문제 (외부에서 파일 수정 시 불일치)
```

#### 접근 3: File System Access API 디렉토리 (고급)

```typescript
// .claude/pipelines/ 디렉토리를 통째로 열어 파일 목록 표시
const handleOpenDirectory = async () => {
  const dirHandle = await window.showDirectoryPicker({
    startIn: 'documents',
    mode: 'readwrite'
  });

  const files: RecentFile[] = [];
  for await (const [name, handle] of dirHandle.entries()) {
    if (handle.kind === 'file' && name.endsWith('.json')) {
      const file = await handle.getFile();
      const json = JSON.parse(await file.text());
      files.push({
        name: json.name,
        fileName: name,
        description: json.description ?? '',
        lastModified: json.modified ?? file.lastModified,
        tags: json.tags ?? [],
        nodeCount: json.nodes?.length ?? 0,
      });
    }
  }

  return files;
};
```

- 장점: `.claude/pipelines/` 디렉토리를 직접 탐색. 실시간 목록.
- 단점: Chromium 전용. 처음 한 번 디렉토리 권한 허용 필요.
- **추천**: File System Access API 지원 시 이 방식 사용. 미지원 시 접근 1로 폴백.

### 4.2 목록 UI 설계

```
+-------------------------------------------------------+
|  파이프라인 목록                          [디렉토리 설정]|
|-------------------------------------------------------|
|  검색: [________________________] [태그 필터 v]         |
|-------------------------------------------------------|
|  이름                    태그        수정일     노드수  |
|  ---------------------------------------------------- |
|  feature-implementation  feature    2분 전      10    |
|  bugfix-with-diagnosis   bugfix     1시간 전     8    |
|  security-hotfix         hotfix     어제         16    |
|  ---------------------------------------------------- |
|  [+ 새 파이프라인]  [파일에서 열기]                      |
+-------------------------------------------------------+
```

**목록 항목 클릭 시:**
- File System Access API 디렉토리가 설정되어 있으면 -> 바로 로드
- IndexedDB에 캐시되어 있으면 -> 캐시에서 로드
- 둘 다 없으면 -> "파일을 다시 선택해주세요" + 파일 선택 다이얼로그

**태그 필터:**
- 태그별로 필터링 (feature, bugfix, hotfix, refactor 등)
- 스키마의 `tags` 필드를 활용

### 4.3 에디터 헤더 바

파이프라인을 열었을 때의 헤더.

```
+----------------------------------------------------------------------+
|  [< 목록]  feature-implementation  *           [실행취소][다시실행]      |
|            기능 구현 표준 파이프라인              [저장 v][유효성 검증]   |
|----------------------------------------------------------------------|
|  [사이드바]              [캔버스 영역]                [설정 패널]        |
```

- `*` 표시: dirty state (저장하지 않은 변경이 있음)
- `[저장 v]`: 드롭다운 - "저장", "다른 이름으로 저장", "다운로드", "클립보드에 복사"
- `[< 목록]`: 파이프라인 목록으로 돌아가기 (dirty 시 이탈 방지 다이얼로그)

---

## 5. 메타데이터 편집 UI

파이프라인의 name, description, tags, variables, validation을 편집하는 패널.

### 5.1 기본 정보 탭

```
+-------------------------------------------+
|  기본 정보                                  |
|-------------------------------------------|
|  이름:     [feature-implementation    ]    |
|  설명:     [기능 구현 표준 파이프라인    ]    |
|  태그:     [feature] [standard] [+추가]    |
|  생성일:   2026-02-16 (읽기 전용)          |
|  수정일:   2026-02-16 (자동 갱신)          |
+-------------------------------------------+
```

### 5.2 변수 탭

```
+-------------------------------------------+
|  변수 (Variables)                           |
|-------------------------------------------|
|  worktree_path   [              ]  [삭제]  |
|  branch_name     [              ]  [삭제]  |
|  user_request    [              ]  [삭제]  |
|  [+ 변수 추가]                              |
|-------------------------------------------|
|  설명: 노드의 args/prompt에서              |
|  ${변수명}으로 참조할 수 있습니다            |
+-------------------------------------------+
```

### 5.3 검증 탭

```
+-------------------------------------------+
|  e2e 검증 (Validation)                      |
|-------------------------------------------|
|  실패 시 동작: [report v]                    |
|                                            |
|  검증 항목:                                  |
|  +---------------------------------------+ |
|  | all_nodes_completed                   | |
|  | check: all_nodes_ok                   | |
|  | severity: error                       | |
|  +---------------------------------------+ |
|  +---------------------------------------+ |
|  | tests_pass                            | |
|  | check: exit_code_zero                 | |
|  | target: test-1                        | |
|  | severity: error                       | |
|  +---------------------------------------+ |
|  [+ 검증 항목 추가]                          |
+-------------------------------------------+
```

---

## 6. 버전 관리 및 히스토리

### 6.1 현 단계에서 필요한 것

| 기능 | 필요도 | 이유 |
|------|--------|------|
| Undo/Redo (세션 내) | 필수 | 편집 실수 즉시 복구. UX 기본 |
| Dirty State | 필수 | 저장 안 된 변경 이탈 방지 |
| 파일 수준 버전 관리 | 불필요 | `.claude/pipelines/`가 git으로 관리되므로 git이 버전 관리를 담당 |
| 에디터 내 버전 히스토리 | 불필요 | 과잉 기능. git log로 충분 |
| 자동 저장 | 선택적 | IndexedDB에 자동 저장하여 브라우저 충돌 시 복구. MVP 이후 |

### 6.2 자동 저장 (MVP 이후)

```typescript
// 30초마다 IndexedDB에 자동 저장
useEffect(() => {
  if (!dirty) return;

  const timer = setInterval(() => {
    const json = serializeToJSON();
    saveToIndexedDB('autosave', json);
  }, 30_000);

  return () => clearInterval(timer);
}, [dirty]);

// 앱 시작 시 자동 저장본 확인
useEffect(() => {
  const autosave = loadFromIndexedDB('autosave');
  if (autosave) {
    setShowRecoveryDialog(true);
    // "이전 세션의 저장되지 않은 변경을 복구하시겠습니까?"
  }
}, []);
```

### 6.3 Git 연동 참고

파이프라인 파일이 `.claude/pipelines/` 안에 저장되는데, 현재 `.claude/` 디렉토리는 `.gitignore`에 추가되어 있다. 파이프라인을 git으로 버전 관리하려면 두 가지 선택지가 있다:

1. **`.claude/pipelines/`를 gitignore에서 제외**: `.gitignore`에 `!.claude/pipelines/` 추가
2. **파이프라인 디렉토리를 `.claude/` 밖으로 이동**: 예: `pipelines/*.json`

이 결정은 에디터 설계와 별개이며, 프로젝트 운영 정책에 따라 선택한다.

---

## 7. 기존 스키마 변경/추가 필요 사항

현재 `docs/research-pipeline-json-schema-20260216.md`의 스키마를 분석한 결과, 편집 기능을 위해 추가로 필요한 변경은 다음과 같다.

### 7.1 스키마 변경 불필요 항목

| 항목 | 이유 |
|------|------|
| nodes/edges 구조 | React Flow와 1:1 매핑이 이미 완벽 |
| position 필드 | 이미 정의됨. 역직렬화 시 그대로 사용 |
| 메타데이터 (name, description, tags) | 이미 정의됨 |
| variables | 이미 정의됨 |
| validation | 이미 정의됨 |

### 7.2 스키마 추가 고려 사항 (선택적)

| 항목 | 추가 필드 | 용도 | 필요도 |
|------|----------|------|--------|
| 에디터 상태 보존 | `editorState.viewport` | 줌/패닝 위치 복원 | 낮음 (편의) |
| 에디터 상태 보존 | `editorState.selectedNodes` | 선택 상태 복원 | 불필요 |
| 파일 원본 추적 | `sourceFile` | 어떤 파일에서 로드했는지 | 불필요 (localStorage가 관리) |
| 스키마 검증 URL | `$schema` | JSON 스키마 자동 검증 | 낮음 (향후) |

#### editorState 제안 (선택적)

```json
{
  "editorState": {
    "viewport": {
      "x": -200,
      "y": -100,
      "zoom": 0.75
    }
  }
}
```

- 사용자가 복잡한 파이프라인을 특정 줌 레벨/위치에서 작업하다가 저장하면, 다시 열 때 같은 뷰로 복원
- **Orchestrator는 무시**. 순수 UI 편의 기능.
- MVP에서는 생략하고, `fitView()`로 자동 줌 조정하는 것으로 충분

### 7.3 결론

**기존 스키마에 변경이 필요하지 않다.** 현재 스키마는 편집 기능을 충분히 지원한다. `editorState` 같은 UI 편의 필드는 향후 필요 시 추가하면 되며, Orchestrator 실행에는 영향을 주지 않는다.

---

## 8. 프로젝트 구조 업데이트

기존 visual-editor 설계의 프로젝트 구조를 편집 기능을 반영하여 업데이트.

```
pipeline-editor/
  src/
    components/
      Canvas.tsx              # React Flow 캔버스
      NodePalette.tsx         # 사이드바 노드 목록
      SkillNode.tsx           # 스킬 커스텀 노드 컴포넌트
      AgentNode.tsx           # 에이전트 커스텀 노드 컴포넌트
      ControlNode.tsx         # Start/End/Fork/Join/Condition/Loop 노드
      NodeConfigPanel.tsx     # 노드 설정 사이드 패널
      MetadataPanel.tsx       # [신규] 파이프라인 메타데이터 편집 패널
      PipelineList.tsx        # [신규] 파이프라인 목록 (랜딩 화면)
      EditorHeader.tsx        # [신규] 에디터 헤더 바 (파일명, 저장 버튼 등)
      SaveDialog.tsx          # [신규] 저장 옵션 다이얼로그
      LoadWarningDialog.tsx   # [신규] 불러오기 경고/에러 다이얼로그
      UnsavedChangesDialog.tsx # [신규] 이탈 방지 다이얼로그
    data/
      skills.json             # 빌드 타임 추출된 스킬 메타데이터
      agents.json             # 빌드 타임 추출된 에이전트 메타데이터
    store/
      pipelineStore.ts        # [확장] Zustand 상태 관리 + temporal(undo/redo)
    utils/
      serializer.ts           # [확장] React Flow -> Pipeline JSON
      deserializer.ts         # [신규] Pipeline JSON -> React Flow
      validator.ts            # [확장] 불러오기 시 스키마 검증
      autoLayout.ts           # [신규] dagre 기반 자동 레이아웃
      fileAccess.ts           # [신규] File System Access API 래퍼
      recentFiles.ts          # [신규] 최근 파일 관리 (localStorage)
    hooks/
      useKeyboardShortcuts.ts # [신규] Ctrl+S, Ctrl+Z 등 단축키
      useUnsavedWarning.ts    # [신규] beforeunload 이탈 방지
      useFileSystemAccess.ts  # [신규] File System Access API 기능 감지 훅
    App.tsx                   # [수정] 라우팅: 목록 <-> 에디터
    main.tsx
  scripts/
    extract-metadata.js       # SKILL.md/agent.md에서 메타데이터 추출
  public/
  package.json                # [수정] zundo, dagre 의존성 추가
  vite.config.ts
```

### 추가 의존성

```json
{
  "dependencies": {
    "reactflow": "^11.x",
    "zustand": "^4.x",
    "zundo": "^2.x",         // [신규] undo/redo 미들웨어
    "dagre": "^0.8.x",       // [신규] 자동 레이아웃
    "@dagrejs/dagre": "^1.x"  // (또는 이 포크 버전)
  }
}
```

---

## 9. 키보드 단축키

| 단축키 | 기능 |
|--------|------|
| `Ctrl+S` | 저장 (File System Access API 있으면 덮어쓰기, 없으면 다운로드) |
| `Ctrl+Shift+S` | 다른 이름으로 저장 |
| `Ctrl+Z` | 실행취소 (Undo) |
| `Ctrl+Shift+Z` | 다시실행 (Redo) |
| `Ctrl+O` | 파일 열기 |
| `Ctrl+N` | 새 파이프라인 |
| `Delete` / `Backspace` | 선택된 노드/엣지 삭제 |
| `Ctrl+A` | 전체 선택 |
| `Ctrl+C` | 선택 노드 복사 |
| `Ctrl+V` | 복사된 노드 붙여넣기 |
| `Ctrl+D` | 선택 노드 복제 |
| `Space` (드래그) | 캔버스 패닝 |
| `Ctrl+Shift+V` | 클립보드에서 파이프라인 불러오기 |

---

## 10. 에러 처리 및 엣지 케이스

### 10.1 불러오기 시 에러

| 상황 | 대응 |
|------|------|
| JSON 파싱 실패 | "유효한 JSON 파일이 아닙니다" 에러 다이얼로그. 로드 중단 |
| 필수 필드 누락 (name, nodes, edges) | "파이프라인 형식이 올바르지 않습니다: [구체적 에러]" 에러 다이얼로그 |
| 스키마 버전 불일치 | "버전 X.X 파이프라인입니다. 변환을 시도합니다" 경고 + 계속 로드 |
| position 누락 | 자동 레이아웃 적용 + "일부 노드의 위치가 자동 배치되었습니다" 알림 |
| 존재하지 않는 노드를 참조하는 엣지 | 해당 엣지를 제거하고 경고 표시 |
| Start 노드 없음 | Start 노드 자동 추가 + 경고 |
| End 노드 없음 | End 노드 자동 추가 + 경고 |
| 빈 파이프라인 (노드 0개) | "빈 파이프라인입니다. 새로 만드시겠습니까?" 제안 |
| 매우 큰 파이프라인 (50+ 노드) | 경고 없이 로드하되, 성능 저하 시 미니맵 자동 활성화 |

### 10.2 저장 시 에러

| 상황 | 대응 |
|------|------|
| File System Access API 권한 거부 | "파일 쓰기 권한이 거부되었습니다. 다운로드로 저장합니다" -> 다운로드 폴백 |
| 디스크 공간 부족 | 에러 메시지 표시. 클립보드 복사 제안 |
| 파이프라인 이름 미입력 | "파이프라인 이름을 입력해주세요" 유효성 검증 |
| 유효성 경고가 있는 상태에서 저장 | 경고 목록 표시 + "그래도 저장하시겠습니까?" 확인 |

### 10.3 편집 시 엣지 케이스

| 상황 | 대응 |
|------|------|
| Start 노드 삭제 시도 | "Start 노드는 삭제할 수 없습니다" 방지 |
| End 노드 삭제 시도 | "End 노드는 삭제할 수 없습니다" 방지 |
| Start 노드 2개 이상 | "Start 노드는 하나만 존재할 수 있습니다" 방지 |
| Fork 노드 삭제 시 연결된 Join이 있음 | "연결된 Join 노드도 함께 삭제하시겠습니까?" 확인 |
| 순환 엣지 생성 (루프백이 아닌 의도치 않은 순환) | 경고 표시하되 허용 (의도된 루프일 수 있으므로) |
| 같은 포트에 여러 엣지 연결 (in 포트) | 허용 (Join 노드 등에서 필요) |
| ok 포트에 여러 엣지 | 경고 + 허용 (사용자가 의도한 것일 수 있음) |

---

## 11. 구현 우선순위

### Phase 1: MVP (핵심 편집 기능)

| 순서 | 기능 | 구현 난이도 |
|------|------|------------|
| 1 | JSON 파싱 + 스키마 검증 (validator.ts) | 낮음 |
| 2 | JSON -> React Flow 역직렬화 (deserializer.ts) | 보통 |
| 3 | 파일 업로드 (`<input type="file">`) | 낮음 |
| 4 | 캔버스 렌더링 + fitView | 낮음 (React Flow 내장) |
| 5 | Zustand 스토어에 dirty state 추가 | 낮음 |
| 6 | 저장: JSON 직렬화 + Blob 다운로드 | 낮음 |
| 7 | Undo/Redo (zundo) | 보통 |
| 8 | 이탈 방지 (beforeunload) | 낮음 |
| 9 | 키보드 단축키 (Ctrl+S, Ctrl+Z) | 낮음 |

**MVP 예상 소요**: 컴포넌트 6개 신규 + 유틸 4개 신규 + 스토어 확장

### Phase 2: 고급 UX

| 순서 | 기능 |
|------|------|
| 1 | File System Access API 지원 (덮어쓰기 저장) |
| 2 | 최근 파일 목록 (localStorage) |
| 3 | 랜딩 화면 (PipelineList) |
| 4 | 메타데이터 편집 패널 (MetadataPanel) |
| 5 | Drag & Drop 파일 불러오기 |
| 6 | 클립보드 불러오기/복사 |
| 7 | dagre 자동 레이아웃 |

### Phase 3: 고급 기능

| 순서 | 기능 |
|------|------|
| 1 | File System Access API 디렉토리 탐색 (`.claude/pipelines/`) |
| 2 | IndexedDB 캐시 + 자동 저장 |
| 3 | editorState (viewport 복원) |
| 4 | 노드 복사/붙여넣기 (Ctrl+C/V) |
| 5 | 스키마 버전 마이그레이션 |

---

## 12. 주요 포인트 요약

1. **불러오기 4가지 방식**: File Input (모든 브라우저), File System Access API (Chromium), Drag & Drop, 클립보드
2. **저장 4가지 방식**: 덮어쓰기 (File System Access API), 다른 이름으로 저장, Blob 다운로드 (폴백), 클립보드 복사
3. **역직렬화**: Pipeline JSON -> React Flow 노드/엣지 직접 매핑 + dagre 자동 레이아웃 (position 누락 시)
4. **직렬화**: React Flow 상태 -> Pipeline JSON (React Flow 내부 필드 정리)
5. **상태 관리**: Zustand + zundo (temporal) 미들웨어로 undo/redo (100단계)
6. **dirty state**: 변경 감지 + 이탈 방지 + 저장 후 clean
7. **파이프라인 목록**: localStorage 기반 최근 파일 (MVP) -> File System Access API 디렉토리 (고급)
8. **기존 스키마 변경 불필요**: 현재 스키마가 편집 기능을 완벽히 지원
9. **버전 관리**: git이 담당. 에디터 내 별도 버전 관리 불필요
10. **자동 저장**: MVP 이후 IndexedDB 기반 자동 저장으로 브라우저 충돌 대비

## 출처

- File System Access API: https://developer.mozilla.org/en-US/docs/Web/API/File_System_Access_API
- zundo (undo/redo for Zustand): https://github.com/charkour/zundo
- dagre (그래프 레이아웃): https://github.com/dagrejs/dagre
- React Flow: https://reactflow.dev/
