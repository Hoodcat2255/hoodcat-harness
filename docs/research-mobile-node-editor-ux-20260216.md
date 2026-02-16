# 모바일 노드 기반 그래프/워크플로우 에디터 UX 패턴 조사

> 조사일: 2026-02-16
> 주제: 모바일 환경에서의 노드 기반 워크플로우 에디터 UX 패턴 및 모범 사례
> 관련 문서:
> - `docs/research-pipeline-visual-editor-20260216.md` (비주얼 에디터 초기 설계)
> - `docs/research-pipeline-json-schema-20260216.md` (JSON 스키마 정식 설계)
> - `docs/research-pipeline-editor-load-edit-20260216.md` (불러오기/편집/저장 설계)

---

## 개요

노드 기반 그래프 에디터는 본질적으로 넓은 캔버스, 정밀한 포인터 조작, 드래그 앤 드롭 연결을 전제로 설계되어 모바일 터치 환경과 충돌이 크다. 본 조사에서는 n8n, Node-RED, Figma, draw.io, Apple Shortcuts, ComfyUI, Blender Geometry Nodes, Unreal Blueprint 등 8개 앱/도구의 모바일 대응 현황과 패턴을 분석하고, React Flow 기반 파이프라인 에디터의 모바일 최적화 전략을 도출한다.

핵심 발견: 대부분의 노드 에디터는 모바일을 1등 시민으로 지원하지 않는다. 유일하게 Apple Shortcuts만이 모바일 네이티브로 설계되었으며, 이는 노드 그래프가 아닌 선형 리스트 기반 UI를 채택했기 때문이다. ComfyUI 커뮤니티에서 3개 이상의 모바일 전용 프론트엔드가 개발되었는데, 모두 그래프 뷰를 포기하고 리스트/카드 뷰로 전환한 것이 공통점이다.

---

## 1. 앱별 모바일 대응 현황 분석

### 1.1 n8n

**현황**: 모바일 미지원. 데스크톱 전용 UI.

- GitHub Issue #7938 (2023)에서 "Interface should be mobile responsive" 요청이 있었으나, 이후 닫힌(closed) 상태
- 이슈 내용: 워크플로우 노드가 화면 밖으로 벗어나고, 노드를 클릭/편집하기 어려움
- n8n 팀은 모바일 대응을 우선순위에 두지 않는 것으로 판단됨
- 워크플로우 개요 페이지(목록)는 반응형이나, 실제 캔버스 에디터는 반응형 미적용

**시사점**: 전문적인 워크플로우 도구도 모바일 캔버스 편집을 지원하지 않으며, 모바일에서는 "보기 전용" 또는 "실행 트리거" 수준만 필요하다고 판단한 것으로 보임.

### 1.2 Node-RED

**현황**: 부분적 모바일 지원. 터치 기본 동작 가능하나 사용성 열악.

- GitHub Issue #5005: Node-RED 4.x로 업그레이드 후 모바일에서 Function 노드의 Monaco 코드 에디터가 동작하지 않는 문제 보고 (iPhone/iPad)
- 기본 캔버스(D3.js 기반)는 터치로 팬/줌이 되지만, 노드 연결(와이어링)이 터치로 어려움
- Node-RED Dashboard 2.0은 별도의 모바일 대응 대시보드 UI를 제공하지만, 이는 플로우 편집이 아닌 실행 결과 모니터링 용도

**UX 패턴**:
- 캔버스: 한 손가락 드래그 = 팬, 두 손가락 핀치 = 줌
- 노드 추가: 좌측 팔레트에서 드래그 (모바일에서 매우 불편)
- 노드 설정: 더블탭으로 설정 패널 열기
- 모바일 전용 최적화는 없음

**시사점**: 코드 에디터(Monaco) 같은 복잡한 컴포넌트는 모바일에서 근본적으로 문제가 있으며, 단순 텍스트 입력으로 대체해야 함.

### 1.3 Figma

**현황**: 모바일 앱 존재 (Figma Mirror → Figma 앱). 제한적 편집 가능.

- Figma 모바일 앱은 주로 "프로토타입 미리보기"와 "코멘트 달기" 용도
- 캔버스 편집은 iPad에서 가능하지만, 정밀한 노드 조작은 Apple Pencil 필요
- 두 손가락 핀치 줌/팬이 매우 매끄러움 (네이티브 제스처 지원)
- 복잡한 속성 패널은 하단 시트(Bottom Sheet)로 전환

**UX 패턴**:
- 캔버스 네비게이션: 네이티브 수준의 핀치 줌/팬 (60fps)
- 요소 선택: 탭으로 선택, 길게 누르기로 컨텍스트 메뉴
- 속성 편집: 하단 시트 (Bottom Sheet) 패턴
- 요소 추가: 하단 도구 모음의 "+" 버튼 → 카테고리별 리스트
- 터치 타겟: 최소 44x44pt (Apple HIG 준수)

**시사점**: 모바일에서 그래프 편집을 지원하려면 iPad + 스타일러스 수준의 정밀도가 전제됨. 핸드폰에서는 "보기 + 간단한 편집"이 현실적.

### 1.4 draw.io (diagrams.net)

**현황**: 모바일 웹 지원. 반응형 UI로 기본적인 다이어그램 편집 가능.

- 공식적으로 Safari iOS 18.5+, WebView Android 137+ 지원
- 모바일 브라우저에서 app.diagrams.net 접속 시 자동으로 반응형 UI 로드
- 터치로 도형 드래그, 핀치 줌/팬 지원
- 그러나 복잡한 다이어그램에서는 조작이 어려움

**UX 패턴**:
- 캔버스: 한 손가락 = 도형 드래그(선택 시) 또는 팬(빈 영역), 두 손가락 핀치 = 줌
- 도형 추가: "+" 버튼 → 팝업 메뉴에서 도형 선택 → 캔버스에 자동 배치
- 연결: 도형 선택 시 파란 화살표 핸들 노출, 드래그로 연결
- 속성 편집: 우측 패널 → 모바일에서는 오버레이 패널로 전환
- 사이드바: 모바일에서는 숨김, 햄버거 메뉴로 접근

**시사점**: draw.io는 모바일에서 "기본적인" 편집은 가능하게 했지만, 복잡한 노드 그래프보다는 단순 다이어그램(박스 + 화살표)에 최적화됨. 노드 에디터에 적용 시 참고할 만한 패턴은 "도형 선택 시 핸들 노출" 방식.

### 1.5 Apple Shortcuts (심층 분석)

**현황**: 모바일 네이티브. 모바일에서의 워크플로우 편집 최고 모범 사례.

Apple Shortcuts는 유일하게 모바일(iPhone/iPad)에서 완전한 워크플로우 편집을 제공하는 앱이다. 핵심 설계 결정은 **노드 그래프를 사용하지 않는 것**이다.

**핵심 UX 패턴**:

1) **선형 리스트 레이아웃 (노드 그래프 X)**
   - 모든 액션이 위에서 아래로 순차적으로 나열됨
   - 좌우 스크롤 없음, 세로 스크롤만
   - 분기(If/Else)는 들여쓰기(indentation)로 표현
   - 병렬 실행 개념이 없음 (모든 것이 순차)

2) **액션 추가 방식**
   - 하단의 "+" 버튼 또는 빈 영역의 "앱 및 액션 검색" 텍스트 필드
   - 탭하면 전체 화면 카테고리 브라우저 열림
   - 카테고리별 분류 + 검색 = 수백 개 액션을 빠르게 찾기
   - 드래그 앤 드롭이 아니라 "탭하여 추가"

3) **액션 재배치**
   - 액션 블록을 길게 누르면 "들어올려짐" (haptic feedback)
   - 드래그하여 원하는 위치에 놓기
   - 리스트 내 재정렬이므로 2D 자유 배치보다 훨씬 직관적

4) **액션 설정**
   - 각 액션 블록을 탭하면 인라인으로 설정 필드가 펼쳐짐
   - 별도 설정 패널이나 모달 없이, 블록 자체가 확장됨
   - "매직 변수" 시스템: 이전 액션의 출력을 변수로 참조
   - 변수 선택 시 이전 액션 목록이 드롭다운으로 표시

5) **조건 분기 (If/Otherwise)**
   - If 블록이 시각적으로 "그룹"을 형성
   - Then/Otherwise 영역이 들여쓰기로 구분
   - 중첩 가능하지만, 깊은 중첩은 가독성 떨어짐

6) **반복 (Repeat)**
   - "Repeat" 액션 블록 안에 반복할 액션을 배치
   - 시각적으로 그룹핑 (경계선/배경색)
   - "Repeat with Each"로 리스트 순회도 가능

7) **네비게이션**
   - 단순 세로 스크롤
   - 긴 워크플로우에서도 스크롤만으로 탐색 가능
   - 검색으로 특정 액션 찾기

**시사점**: Apple Shortcuts의 핵심 통찰은 "모바일에서 2D 자유 캔버스를 포기하고 1D 선형 리스트를 채택한 것"이다. 이것이 모바일 터치 UX와 완벽하게 맞는 이유:
- 한 손가락 스크롤이 자연스러움
- 터치 타겟이 넉넉함 (블록 전체가 탭 가능)
- 드래그 앤 드롭 재정렬이 iOS 표준 패턴
- 모달/패널 없이 인라인 확장으로 설정
- 병렬 실행이 없으므로 분기가 단순

### 1.6 ComfyUI

**현황**: 데스크톱 전용 LiteGraph.js 기반 노드 에디터. 커뮤니티에서 3+ 모바일 프론트엔드 개발 중.

ComfyUI의 모바일 대응은 커뮤니티 주도이며, 세 가지 주목할 만한 프로젝트가 있다:

#### a) comfyui-mobile-frontend (cosmicbuffalo)
- **접근법**: 그래프 뷰를 완전히 포기하고 리스트/카드 뷰로 전환
- "대부분의 경우 그래프 인터페이스가 방해만 된다. 스크롤하려 하면 줌이 되고, 팬하려 하면 노드를 드래그하게 된다."
- 워크플로우의 노드를 폴더블(접기 가능) 리스트로 표시
- 노드 간 연결 탐색을 "커넥션 내비게이션"으로 대체
- 즐겨찾기/북마크 기능으로 빠른 접근
- Apple Shortcuts와 유사한 1D 리스트 패턴

#### b) comfyui-mobile (viyiviyi)
- **접근법**: 기존 그래프 UI를 모바일 제스처로 최적화
- 핀치 줌 제스처 구현
- 길게 누르기로 컨텍스트 메뉴 호출
- 연결 가능한 노드를 자동으로 커서 근처로 이동
- 플로팅 패널을 필요 시에만 표시
- 입력 필드/메뉴를 화면 너비에 맞추고 중앙 정렬
- 기본 더블클릭 검색과 두 손가락 탭 메뉴 비활성화 (오작동 방지)

#### c) ComfyUI-MobileFriendly (XelaNull)
- **접근법**: 기존 UI에 모바일 친화적 패치 주입
- **핵심 해결 과제들**:
  - 브라우저 줌 방지: viewport meta tag + CSS touch-action + JS 제스처 인터셉트 3중 레이어
  - 터치 타겟 확대: 컨텍스트 메뉴, 버튼 크기 확대
  - 화면 공간 최적화: 불필요한 UI 요소 숨김 (액션바, 드래그 핸들 등)
  - 키보드 방지: 숫자 입력을 슬라이더로 대체
  - CSS `display:none` 대신 JavaScript 숨김 사용 (iOS에서 하위 요소까지 숨겨지는 문제 방지)
- viewport meta: `user-scalable=no, maximum-scale=1.0`
- CSS `touch-action`: html/body에 `pan-x pan-y`, canvas에 `none`

**시사점**: ComfyUI 커뮤니티의 경험은 매우 교훈적이다.
- 모바일에서 노드 그래프 UI는 근본적으로 불편하다는 것이 커뮤니티 합의
- 가장 성공적인 접근법은 그래프를 리스트로 변환하는 것
- 기존 UI를 패치하는 접근법도 가능하지만, 해결해야 할 문제가 산적함

### 1.7 Blender Geometry Nodes

**현황**: 데스크톱 전용. 모바일 미지원.

- Blender는 3D 모델링 소프트웨어로, Geometry Nodes는 절차적 모델링을 위한 노드 에디터
- 완전히 데스크톱 전용, 모바일/태블릿 미지원
- iPad 버전 요청이 있었으나, Blender Foundation은 "데스크톱 경험에 집중"한다고 밝힘
- 노드 에디터 UX: 마우스 중간 버튼 드래그 = 팬, 스크롤 = 줌, 좌클릭 드래그 = 노드 이동/연결
- 노드 추가: Shift+A 단축키 → 카테고리 메뉴 또는 검색

**시사점**: 데스크톱 전용 노드 에디터의 UX는 마우스 기반이며, 모바일로 직접 이식이 불가능.

### 1.8 Unreal Blueprint

**현황**: 데스크톱 전용. 모바일 미지원.

- Unreal Engine의 비주얼 스크립팅 시스템
- 완전히 마우스/키보드 기반
- 노드 추가: 우클릭 컨텍스트 메뉴 → 검색 필터
- 핀(포트) 연결: 드래그 앤 드롭
- 그래프 네비게이션: 우클릭 드래그 = 팬, 마우스 스크롤 = 줌
- 모바일 포트 계획 없음

**시사점**: 전문 게임 개발 도구로서 모바일 UX를 고려할 필요가 없는 영역.

---

## 2. 조사 포인트별 횡단 분석

### 2.1 모바일에서 노드 추가 방법

| 앱 | 방법 | 모바일 적합도 |
|----|------|-------------|
| Apple Shortcuts | 하단 "+" 버튼 → 전체화면 검색/카테고리 | 최적 |
| draw.io | "+" 버튼 → 팝업 메뉴 → 자동 배치 | 양호 |
| ComfyUI Mobile Frontend | 리스트에서 "+" 버튼 → 퍼지 검색 | 양호 |
| ComfyUI (comfyui-mobile) | 길게 누르기 → 컨텍스트 메뉴 | 보통 |
| n8n | 사이드바 드래그 앤 드롭 | 미지원 |
| Node-RED | 팔레트 드래그 앤 드롭 | 불편 |
| Blender/Unreal | 키보드 단축키 + 컨텍스트 메뉴 | 불가능 |

**최적 패턴**: "+" FAB(Floating Action Button) → 전체화면 검색/카테고리 브라우저 → 탭으로 추가 → 자동 배치

### 2.2 캔버스 네비게이션 (줌, 팬)

| 앱 | 팬 | 줌 | 특이사항 |
|----|-----|-----|---------|
| Figma | 한 손가락 드래그 (빈 영역) | 두 손가락 핀치 | 네이티브 수준 부드러움 |
| draw.io | 한 손가락 드래그 | 두 손가락 핀치 | 반응형 웹 |
| ComfyUI (패치) | 한 손가락 드래그 | 핀치 (커스텀 구현) | 브라우저 줌 방지 필요 |
| Apple Shortcuts | 세로 스크롤 | 해당 없음 (리스트) | 2D 캔버스 없음 |

**핵심 이슈**: 모바일 브라우저의 기본 핀치 줌이 캔버스 줌과 충돌한다.

**해결 방법** (ComfyUI-MobileFriendly에서 검증된 3중 레이어):
1. viewport meta tag: `<meta name="viewport" content="user-scalable=no, maximum-scale=1.0">`
2. CSS touch-action: body에 `pan-x pan-y`, 캔버스에 `none`
3. JavaScript: Safari gesturestart/gesturechange 이벤트 차단 (캔버스 외)

**React Flow 대응**: React Flow는 기본적으로 터치 이벤트를 지원하며, `zoomOnPinch`, `panOnDrag`, `panOnScroll` 등의 props로 세밀하게 제어 가능.

### 2.3 노드 연결/엣지 관리

| 앱 | 방법 | 모바일 적합도 |
|----|------|-------------|
| React Flow | 핸들(포트) 드래그 또는 **탭 두 번** (connectOnClick) | 양호 |
| draw.io | 노드 선택 시 핸들 노출 → 드래그 | 보통 |
| Apple Shortcuts | 연결 개념 없음 (순차 리스트) | 해당 없음 |
| ComfyUI | 포트 드래그 (모바일에서 매우 어려움) | 불편 |

**React Flow의 터치 연결 패턴** (공식 예제):
- `connectOnClick={true}` (기본값): 첫 번째 핸들 탭 → 두 번째 핸들 탭으로 연결 생성
- 핸들 크기를 확대하여 터치 타겟 확보 (최소 44x44px)
- 공식 Touch Device 예제에서 이 패턴을 권장

```css
/* 터치 디바이스용 핸들 확대 */
.touch-flow .react-flow__handle {
  width: 20px;
  height: 20px;
}
```

### 2.4 사이드바/팔레트 처리

| 앱 | 데스크톱 | 모바일 |
|----|---------|--------|
| n8n | 좌측 고정 사이드바 | 미지원 |
| Node-RED | 좌측 팔레트 + 우측 설정 | 그대로 유지 (불편) |
| draw.io | 좌측 도형 팔레트 + 우측 속성 | 숨김 + 햄버거 메뉴 |
| Figma | 좌측 레이어 + 우측 속성 | 하단 시트 (Bottom Sheet) |
| Apple Shortcuts | 해당 없음 | 전체화면 카테고리 브라우저 |
| ComfyUI-MobileFriendly | 좌측 사이드바 | 숨김 + 커스텀 메뉴 버튼 |

**최적 패턴**:
- 노드 팔레트: 전체화면 오버레이 또는 하단 시트 (사이드바 X)
- 설정 패널: 하단 시트 또는 인라인 확장
- 메뉴: 햄버거 메뉴 또는 FAB

### 2.5 설정 패널 처리

| 앱 | 데스크톱 | 모바일 |
|----|---------|--------|
| n8n | 모달 다이얼로그 | 미지원 |
| Node-RED | 우측 사이드 패널 | 그대로 (좁은 화면에서 겹침) |
| draw.io | 우측 속성 패널 | 오버레이 패널 |
| Figma | 우측 속성 패널 | 하단 시트 (Bottom Sheet) |
| Apple Shortcuts | 인라인 확장 | 인라인 확장 (동일) |

**최적 패턴**: 3가지 접근법 순위
1. **인라인 확장** (Apple Shortcuts 스타일): 노드를 탭하면 노드 자체가 확장되어 설정 필드 노출 → 추가 UI 불필요
2. **하단 시트** (Figma 스타일): 노드를 탭하면 화면 하단에서 시트가 올라옴 → 캔버스와 동시에 보기 가능
3. **전체화면 모달**: 노드를 탭하면 전체화면 편집 모드 → 복잡한 설정에 적합

### 2.6 터치 최적화 전략

각 앱에서 확인된 터치 최적화 기법을 종합한다:

**제스처 충돌 해결**:
- 브라우저 기본 줌 비활성화 (viewport meta + touch-action CSS)
- 한 손가락 / 두 손가락 제스처 명확 분리
- 더블탭 줌 비활성화 (`touch-action: manipulation`)
- Safari의 gesturestart 이벤트 인터셉트

**터치 타겟 크기**:
- Apple HIG: 최소 44x44pt
- Material Design: 최소 48x48dp
- 핸들(포트) 크기를 데스크톱(10px) → 모바일(20px+)로 확대
- 엣지 히트 영역 확대 (pathfinder tolerance)

**피드백**:
- haptic feedback (길게 누르기, 드래그 시작)
- 시각적 피드백 (노드 선택 시 하이라이트, 연결 가능 포트 강조)
- 드래그 중 "snap-to" 가이드

**입력 방식 전환**:
- 숫자 입력을 슬라이더로 대체 (ComfyUI-MobileFriendly)
- 코드 에디터 대신 텍스트 입력 (Node-RED 교훈)
- 드롭다운/피커 우선 (키보드 최소화)

### 2.7 반응형 레이아웃 접근 방식

| 접근법 | 앱 | 설명 | 장단점 |
|--------|-----|------|--------|
| **완전 반응형** | draw.io | 하나의 UI가 화면 크기에 따라 변형 | 개발 비용 높음, UX 타협 |
| **별도 모바일 UI** | ComfyUI Mobile Frontend, Apple Shortcuts | 모바일 전용 UI | UX 최적화 가능, 이중 개발 |
| **모바일 패치** | ComfyUI-MobileFriendly | 기존 UI에 모바일 최적화 패치 | 빠르게 적용 가능, 한계 있음 |
| **모바일 미지원** | n8n, Blender, Unreal | 데스크톱만 지원 | 개발 비용 최소 |
| **모바일 = 보기 전용** | Figma (부분) | 모바일에서는 보기/코멘트만 | 합리적 타협 |

---

## 3. React Flow 기반 모바일 최적화 구체 전략

### 3.1 React Flow의 기본 터치 지원

React Flow 공식 문서 기준으로 이미 지원되는 기능:

- **터치로 노드 드래그**: 기본 지원
- **터치로 캔버스 팬**: `panOnDrag` prop
- **핀치 줌**: `zoomOnPinch` prop
- **탭으로 연결**: `connectOnClick` prop (두 핸들을 순차 탭)
- **뷰포트 이벤트**: MouseEvent | TouchEvent 모두 처리
- **핸들 커스터마이징**: CSS로 크기 조정 가능

**알려진 이슈**:
- xyflow/xyflow#5639: 모바일 Chrome에서 박스 선택이 동작하지 않음 (`touch-action: none` 필요)
- OnNodeDrag 타입이 MouseEvent만 정의됨 (TouchEvent 누락 가능성)

### 3.2 권장 모바일 대응 전략: 듀얼 모드

기존 설계(React Flow 기반 그래프 에디터)를 유지하면서, 모바일에서는 대체 뷰를 제공하는 **듀얼 모드** 전략을 권장한다.

#### 데스크톱 모드 (기존 설계 그대로)
- React Flow 캔버스 + 사이드바 팔레트 + 우측 설정 패널
- 마우스 기반 드래그 앤 드롭, 정밀 연결

#### 모바일 모드 (Apple Shortcuts 영감)
- **리스트 뷰**: execution_order 기반 선형 리스트
- **노드 카드**: 각 노드가 카드 형태, 탭하면 인라인 확장
- **노드 추가**: FAB → 전체화면 검색/카테고리
- **재배치**: 길게 누르기 → 드래그 재정렬
- **분기 표현**: 들여쓰기 + 아코디언 (Fork/Join 영역)
- **연결 편집**: 순서 변경으로 자동 연결 갱신

**모드 전환**:
```typescript
const isMobile = useMediaQuery('(max-width: 768px)') || 'ontouchstart' in window;

// 또는 사용자 수동 전환 토글
const [viewMode, setViewMode] = useState<'graph' | 'list'>(
  isMobile ? 'list' : 'graph'
);
```

### 3.3 모바일 리스트 뷰 설계안

```
+----------------------------------+
| Pipeline: feature-implementation |
| [그래프 뷰] [리스트 뷰]          |
+----------------------------------+
| [1] 코드베이스 탐색               |
|     agent: navigator              |
|     > 탭하여 설정 편집            |
+----------------------------------+
| [2] 구현                          |
|     skill: code                   |
|     retry: 1                      |
|     > 탭하여 설정 편집            |
+----------------------------------+
| [3] 테스트                        |
|     skill: test                   |
|     ↩ 실패 시 → [2] 구현 (max 3) |
|     > 탭하여 설정 편집            |
+----------------------------------+
| ┌ [4] 병렬 리뷰 (Fork)           |
| │ [4a] 코드 리뷰                  |
| │      agent: reviewer            |
| │ [4b] 보안 리뷰                  |
| │      agent: security            |
| └ Join: 모두 완료 대기            |
+----------------------------------+
| [5] 커밋                          |
|     skill: commit                 |
+----------------------------------+
|              [+]                  |
+----------------------------------+
```

이 리스트 뷰와 그래프 뷰는 같은 JSON 데이터를 공유하므로, 모드 전환 시 데이터 손실이 없다.

### 3.4 구현 시 CSS/HTML 주의사항

```html
<!-- viewport meta: 브라우저 줌 방지 -->
<meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
```

```css
/* 캔버스 영역: 터치 제스처를 React Flow가 처리 */
.react-flow {
  touch-action: none;
}

/* 캔버스 외 영역: 스크롤 허용, 줌 방지 */
body {
  touch-action: pan-x pan-y;
}

/* 모바일 핸들 확대 */
@media (max-width: 768px), (pointer: coarse) {
  .react-flow__handle {
    width: 20px;
    height: 20px;
  }

  .react-flow__edge-interaction {
    stroke-width: 20px; /* 엣지 탭 영역 확대 */
  }
}
```

### 3.5 React Flow 모바일 설정 권장값

```tsx
<ReactFlow
  // 터치 최적화
  connectOnClick={true}           // 탭으로 연결 (드래그 대신)
  zoomOnPinch={true}              // 핀치 줌
  panOnDrag={true}                // 한 손가락 팬 (모바일)
  panOnScroll={false}             // 스크롤 팬 비활성화 (핀치와 충돌)
  zoomOnScroll={false}            // 스크롤 줌 비활성화 (모바일에서 불편)
  zoomOnDoubleClick={false}       // 더블탭 줌 비활성화 (오작동 방지)
  preventScrolling={true}         // 캔버스에서 페이지 스크롤 방지

  // 줌 제한
  minZoom={0.3}                   // 넓은 파이프라인도 볼 수 있도록
  maxZoom={2}                     // 과도한 줌인 방지

  // 노드 동작
  nodesDraggable={!isMobile}      // 모바일에서 노드 드래그 비활성화 (팬과 충돌)
  elementsSelectable={true}       // 탭으로 선택

  // 초기 뷰
  fitView                         // 전체 파이프라인이 보이도록 맞춤
/>
```

**주의**: 모바일에서 `nodesDraggable`과 `panOnDrag`를 동시에 활성화하면, 노드 위에서 한 손가락 드래그 시 "노드 이동" vs "캔버스 팬" 구분이 어렵다. 해결책:
1. `nodesDraggable={false}`로 설정하고, 노드 재배치는 리스트 뷰에서만
2. 또는 `dragHandle` prop으로 특정 영역만 드래그 가능하게 설정

---

## 4. 권고 사항: 파이프라인 에디터 모바일 전략

### 4.1 MVP (Phase 1): 데스크톱 우선, 모바일은 보기 전용

- 데스크톱에서 React Flow 기반 그래프 에디터 완성
- 모바일에서는 파이프라인을 "읽기 전용"으로 표시
- React Flow의 기본 터치 지원 (팬, 줌)만 활용
- 노드 탭 시 설정 정보를 하단 시트로 표시 (수정 불가)

### 4.2 Phase 2: 모바일 리스트 뷰

- execution_order 기반 리스트 뷰 구현
- 리스트 뷰에서 노드 설정 인라인 편집
- 리스트 뷰에서 노드 추가/삭제/재정렬
- 그래프 뷰 ↔ 리스트 뷰 모드 전환
- 같은 JSON 데이터 공유 (양방향 동기화)

### 4.3 Phase 3: 모바일 그래프 편집

- 노드 드래그 영역 분리 (dragHandle)
- 핸들 크기 확대 + 탭 연결
- 모바일 전용 노드 팔레트 (FAB + 하단 시트)
- 모바일 전용 설정 패널 (하단 시트)

### 4.4 구현 우선순위 매트릭스

| 기능 | 효과 | 구현 비용 | 우선순위 |
|------|------|----------|---------|
| 브라우저 줌 방지 (viewport meta + CSS) | 높음 | 낮음 | P0 |
| React Flow 터치 props 설정 | 높음 | 낮음 | P0 |
| 핸들 크기 확대 (CSS) | 중간 | 낮음 | P0 |
| connectOnClick 활성화 | 높음 | 낮음 | P0 |
| 하단 시트 설정 패널 | 높음 | 중간 | P1 |
| 노드 팔레트 → FAB + 검색 | 높음 | 중간 | P1 |
| 리스트 뷰 (별도 모드) | 매우 높음 | 높음 | P2 |
| 노드 재배치 (리스트 드래그) | 중간 | 중간 | P2 |
| dragHandle 분리 | 중간 | 중간 | P3 |
| 리스트 ↔ 그래프 동기화 | 높음 | 높음 | P3 |

---

## 5. 주요 포인트 요약

1. **노드 그래프 에디터는 본질적으로 모바일 비친화적이다.** 8개 앱 중 모바일에서 완전한 노드 편집을 지원하는 앱은 없다 (Apple Shortcuts는 노드 그래프가 아닌 리스트).

2. **모바일 워크플로우 편집의 모범 사례는 "선형 리스트 뷰"다.** Apple Shortcuts와 ComfyUI Mobile Frontend 모두 그래프를 리스트로 변환하여 모바일 UX를 해결했다.

3. **React Flow는 기본적인 터치를 지원하지만 최적화가 필요하다.** connectOnClick, zoomOnPinch, 핸들 크기 확대 등의 설정이 필수이며, 브라우저 줌 충돌 해결이 최우선.

4. **듀얼 모드 전략을 권장한다.** 데스크톱은 그래프 뷰, 모바일은 리스트 뷰. 같은 JSON 데이터를 공유하여 양방향 전환. 이미 설계된 execution_order가 리스트 뷰의 기반.

5. **MVP에서는 모바일을 "보기 전용"으로 시작하고, 리스트 뷰 편집은 Phase 2로 계획하는 것이 현실적이다.** 모바일 편집은 개발 비용이 높으므로, 데스크톱 에디터 완성이 우선.

---

## 출처

### 공식 문서/리포지토리
- React Flow Touch Device 예제: https://reactflow.dev/examples/interaction/touch-device
- React Flow Interaction Props: https://reactflow.dev/examples/interaction/interaction-props
- React Flow API Reference (Viewport/Interaction): https://reactflow.dev/api-reference/react-flow
- xyflow/xyflow Issue #5639 (모바일 Chrome 선택 버그): https://github.com/xyflow/xyflow/issues/5639
- draw.io 지원 브라우저: https://github.com/jgraph/drawio (README)

### n8n
- n8n Issue #7938 (모바일 반응형 요청): https://github.com/n8n-io/n8n/issues/7938

### Node-RED
- Node-RED Issue #5005 (모바일 코드 에디터 문제): https://github.com/node-red/node-red/issues/5005

### ComfyUI 모바일 프로젝트
- comfyui-mobile-frontend (리스트 뷰 접근): https://github.com/cosmicbuffalo/comfyui-mobile-frontend
- comfyui-mobile (제스처 최적화): https://github.com/viyiviyi/comfyui-mobile
- ComfyUI-MobileFriendly (모바일 패치): https://github.com/XelaNull/ComfyUI-MobileFriendly
