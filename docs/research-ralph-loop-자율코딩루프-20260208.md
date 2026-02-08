# Ralph Loop (랄프 루프) 자율 코딩 루프 조사 결과

> 조사일: 2026-02-08

## 개요

Ralph Loop(랄프 루프)는 Geoffrey Huntley가 2025년 중반에 공개한 자율형 AI 코딩 기법으로, AI 코딩 에이전트를 무한 반복 루프에서 실행하여 작업이 완료될 때까지 논스탑으로 코드를 생성/수정/테스트하는 패러다임이다. 심슨스 캐릭터 랄프 위검(Ralph Wiggum)에서 이름을 따왔으며, 2025년 말 바이럴되어 2026년 현재 AI 코딩의 핵심 패턴으로 자리잡았다. Anthropic의 Claude Code에 공식 플러그인으로도 탑재되었다.

## 상세 내용

### 1. 핵심 원리

Ralph Loop의 가장 기본적인 형태는 놀랍도록 단순하다:

```bash
while :; do
  cat PROMPT.md | claude -p --dangerously-skip-permissions
done
```

이 한 줄의 bash 루프가 전부다. 핵심 철학은 다음과 같다:

- **반복 > 완벽**: 한 번에 완벽한 코드를 기대하지 않고, 반복을 통해 점진적으로 개선한다
- **신선한 컨텍스트**: 매 반복마다 새로운 에이전트 인스턴스를 생성하여 컨텍스트 오염을 방지한다
- **Git이 메모리**: LLM의 대화 기록 대신 Git 커밋 히스토리와 파일 시스템이 상태를 보존한다
- **외부 검증**: LLM의 자체 판단이 아닌 테스트/빌드/린트 같은 객관적 피드백에 의존한다

### 2. 기존 에이전트 루프와의 차이점

| 측면 | ReAct / Plan-Execute | Ralph Loop |
|------|---------------------|-----------|
| **제어 주체** | 에이전트 내부 로직 | 외부 bash 스크립트 / Stop Hook |
| **종료 조건** | LLM 자체 평가 ("완료했다고 판단") | 정확한 문자열 매칭 (completion promise) |
| **상태 관리** | 단일 세션 대화 히스토리 | 파일 시스템 + Git 이력 |
| **컨텍스트** | 누적 (오염 발생) | 매 반복 초기화 (clean start) |
| **실행 시간** | 단일 세션 (분 단위) | 수시간~수일 (수십 회 반복) |

**ReAct의 한계**: 전통적 에이전트 루프는 모든 대화/도구 결과를 메모리에 축적한다. 실패한 시도, 불필요한 파일 읽기 결과 등이 쌓여 "컨텍스트 오염(Context Pollution)"이 발생하고, 모델이 노이즈 속에서 혼란을 겪는다.

**Ralph의 해결**: "의도적으로 오염이 쌓이기 전에 신선한 상태로 회전"한다. 각 반복은 독립적인 에이전트 인스턴스이며, 이전 반복의 결과는 Git 커밋과 파일(progress.txt, prd.json)로만 전달된다.

### 3. 작동 방식 상세

#### 기본 워크플로우

```
1. PRD(Product Requirements Document) 작성 - 체크리스트 형태의 작업 목록
2. PRD를 prd.json으로 변환 (구조화)
3. Ralph 루프 시작
   ├── 3a. 새 에이전트 인스턴스 생성 (clean context)
   ├── 3b. prd.json에서 미완료 스토리 선택 (highest priority)
   ├── 3c. 해당 스토리 구현
   ├── 3d. 품질 검사 (typecheck, tests, lint)
   ├── 3e. 검사 통과 시 Git 커밋
   ├── 3f. prd.json에서 해당 스토리 passes: true 표시
   ├── 3g. progress.txt에 학습 내용 추가
   └── 3h. 다음 반복으로 이동 (또는 모든 스토리 완료 시 종료)
```

#### Stop Hook 메커니즘

에이전트가 작업 도중 종료하려 할 때, Stop Hook이 이를 가로채서:
1. 정의된 "완료 약속(Completion Promise)"을 출력했는지 확인
2. 약속 문자열이 없으면 원본 프롬프트를 재주입
3. 약속 문자열이 있으면 종료 허용

```
예: --completion-promise "<promise>DONE</promise>"
```

#### Token 관리 전략

- 60% 미만 사용: 자유롭게 작동
- 60-80% 사용: 현재 작업 마무리 권고
- 80% 이상: 강제 회전 (새 인스턴스로 전환)

#### Guardrails 시스템

실패할 때마다 `.ralph/guardrails.md`에 규칙("Sign")을 추가한다. 예를 들어 중복 import로 빌드가 실패하면 "import 추가 전 기존 import 확인" 규칙이 추가되어, 이후 반복에서 같은 실수를 방지한다.

### 4. 구현 방법

#### 방법 1: 순수 Bash 루프 (가장 단순)

```bash
#!/bin/bash
MAX_ITERATIONS=${1:-10}
ITERATION=0

while [ $ITERATION -lt $MAX_ITERATIONS ]; do
  ITERATION=$((ITERATION + 1))
  echo "=== Iteration $ITERATION / $MAX_ITERATIONS ==="
  cat PROMPT.md | claude -p --dangerously-skip-permissions
done
```

#### 방법 2: snarktank/ralph (오픈소스 구현체)

```bash
# 설치
mkdir -p scripts/ralph
cp ralph.sh scripts/ralph/
cp CLAUDE.md scripts/ralph/CLAUDE.md  # Claude Code용
chmod +x scripts/ralph/ralph.sh

# 실행
./scripts/ralph/ralph.sh --tool claude 10  # Claude Code로 최대 10회 반복
```

주요 파일 구조:
- `ralph.sh`: 메인 루프 스크립트
- `prd.json`: 작업 목록 (passes 상태 포함)
- `progress.txt`: 반복 간 학습 내용 축적
- `CLAUDE.md` 또는 `prompt.md`: 에이전트 프롬프트 템플릿

#### 방법 3: Claude Code 공식 플러그인

```bash
# 플러그인 설치 (Claude Code marketplace)
/plugin install ralph-loop@claude-plugins-official

# 루프 실행
/ralph-loop:ralph-loop "REST API 구축" --completion-promise "DONE" --max-iterations 10

# 루프 취소
/ralph-loop:cancel-ralph
```

Claude Code의 공식 저장소(`anthropics/claude-code`)의 `plugins/ralph-wiggum` 디렉토리에 포함되어 있다.

#### 방법 4: ralph-wiggum.ai (SpecKit 기반)

```bash
# Plan 모드: 작업 계획 생성
./scripts/ralph-loop.sh plan

# Build 모드: 자율 실행
./scripts/ralph-loop.sh
```

### 5. 프롬프트 작성 모범 사례

#### 명확한 완료 기준 필수

```markdown
# 작업: TODO REST API 구축

## 완료 조건:
- [ ] 모든 CRUD 엔드포인트 작동
- [ ] 입력 검증 구현
- [ ] 테스트 커버리지 > 80%
- [ ] README 문서 포함

모든 항목 완료 시: <promise>COMPLETE</promise>
```

#### 작업 단위를 작게 유지

적절한 크기:
- 데이터베이스 컬럼 추가 및 마이그레이션
- 기존 페이지에 UI 컴포넌트 추가
- 서버 액션 로직 업데이트
- 리스트에 필터 드롭다운 추가

너무 큰 작업 (분할 필요):
- "전체 대시보드 구축"
- "인증 시스템 추가"
- "API 전체 리팩토링"

### 6. 실제 사용 사례 및 성과

- **Y Combinator 해커톤**: 'repo mirror' 팀이 랄프를 활용해 하룻밤 사이 6개 레포지토리 배포
- **Fruit Ninja 클론**: Cursor CLI + Ralph로 약 1시간, 8번의 컨텍스트 회전으로 완성
- **$50k 계약 완료**: $297의 API 비용으로 프로젝트 완수
- **CURSED 프로그래밍 언어**: 3개월간 Ralph 루프로 개발

### 7. 주의사항 및 한계

#### 비용
- 루프가 한 번 돌 때마다 API 토큰 소모
- 복잡한 작업은 수십 번 반복 가능
- Claude Max 플랜에서 2개 프로젝트 동시 실행 시 1시간 내 레이트 제한 도달 가능

#### 안전
- 반드시 `--max-iterations`로 무한 루프 방지
- 샌드박스 환경(Docker, VM) 사용 권장
- `--dangerously-skip-permissions` 플래그는 광범위한 권한 부여이므로 주의

#### 적합하지 않은 경우
- 주관적 판단이 필요한 작업 (디자인, UX)
- 불명확한 성공 기준
- 실시간 응답이 필요한 경우
- 프로덕션 환경 디버깅

#### 대규모 코드베이스
- 각 반복마다 신선한 컨텍스트로 시작하므로, 대규모 코드베이스의 전체 구조를 이해하기 어려울 수 있음
- AGENTS.md / CLAUDE.md에 코드베이스 컨텍스트를 충분히 기술하는 것이 중요

### 8. 고급 패턴

#### 병렬 개발 (Git Worktree)

```bash
git worktree add ../feature1 -b feature/auth
git worktree add ../feature2 -b feature/api

# 각각 별도 터미널에서 동시 실행
cd ../feature1 && /ralph-loop:ralph-loop "인증 구현..." --max-iterations 30
cd ../feature2 && /ralph-loop:ralph-loop "API 구축..." --max-iterations 25
```

#### 다단계 체이닝

```bash
# Phase 1 완료 후 Phase 2 시작
/ralph-loop:ralph-loop "Phase 1: 데이터 모델..." --completion-promise "PHASE1_DONE" --max-iterations 20
/ralph-loop:ralph-loop "Phase 2: API 레이어..." --completion-promise "PHASE2_DONE" --max-iterations 25
```

#### 에이전트 불가지론적 설계

Ralph Loop 패턴은 특정 AI 도구에 종속되지 않는다. Claude Code, Cursor, Amp, Gemini, Codex, 또는 로컬 모델(Ollama/Qwen) 어떤 것이든 동일하게 적용 가능하다.

## 주요 포인트

- **컨텍스트 초기화가 핵심**: 매 반복마다 새 인스턴스로 시작하여 컨텍스트 오염을 방지하고, Git과 파일 시스템으로 상태를 전달한다
- **외부 검증 의존**: LLM의 자체 판단("완료했다")을 신뢰하지 않고, 테스트/빌드/린트 같은 객관적 피드백으로 진행 상태를 판단한다
- **작업 단위를 작게**: 각 PRD 항목은 하나의 컨텍스트 윈도우 안에서 완료할 수 있을 만큼 작아야 한다
- **Guardrails 축적**: 반복하며 발견한 규칙을 AGENTS.md/guardrails에 기록하여 이후 반복에서 동일 실수를 방지한다
- **Claude Code 공식 지원**: Anthropic의 Claude Code에 공식 플러그인으로 탑재되어, `/ralph-loop` 명령으로 바로 사용 가능하다

## 출처

- [Geoffrey Huntley - Everything is a Ralph Loop](https://ghuntley.com/loop/)
- [DEV.to - 2026: The Year of the Ralph Loop Agent](https://dev.to/alexandergekov/2026-the-year-of-the-ralph-loop-agent-1gkj)
- [snarktank/ralph - GitHub](https://github.com/snarktank/ralph)
- [Ralph Wiggum - AI Loop Technique for Claude Code](https://awesomeclaude.ai/ralph-wiggum)
- [ralph-wiggum.ai - Viral Agentic Coding Loop, Simplified](https://ralph-wiggum.ai/)
- [Alibaba Cloud - From ReAct to Ralph Loop](https://www.alibabacloud.com/blog/from-react-to-ralph-loop-a-continuous-iteration-paradigm-for-ai-agents_602799)
- [Sketch.dev - The Unreasonable Effectiveness of an LLM Agent Loop](https://sketch.dev/blog/agent-loop)
- [Claude Code on Loop - YOLO Mode](https://mfyz.com/claude-code-on-loop-autonomous-ai-coding/)
- [anthropics/claude-code - Ralph Wiggum Plugin](https://github.com/anthropics/claude-code/tree/main/plugins/ralph-wiggum)
- [TILNOTE - 랄프(Ralph) 기법 완벽 정리](https://tilnote.io/en/pages/69632d981569d9997d65c18e)
- [frankbria/ralph-claude-code - GitHub](https://github.com/frankbria/ralph-claude-code)
