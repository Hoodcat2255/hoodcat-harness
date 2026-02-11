# 에이전트 & 스킬 Best Practices 평가 보고서

> 평가일: 2026-02-12
> 평가 기준: `docs/research-claude-agent-skill-best-practices-antipatterns-20260212.md`

---

## 평가 기준 요약

| # | 평가 항목 | 설명 |
|---|-----------|------|
| A | 컨텍스트 효율성 | 줄 수 (SKILL.md 500줄 이하), 불필요한 설명 여부, Claude가 이미 아는 내용 포함 여부 |
| B | Description 품질 | 3인칭 서술, 무엇을 하는지 + 언제 사용하는지 포함, 구체적 키워드, NOT 조건 |
| C | 자유도 조절 | 작업 취약성에 맞는 지시 구체성 (높음/중간/낮음 적절성) |
| D | 도구 권한 스코핑 | 필요한 도구만 허용, 와일드카드 활용, 과도한 권한 방지 |
| E | Progressive Disclosure | 참조 파일 분리, 1레벨 깊이 참조, 필요시 로드 구조 |
| F | 검증 루프 포함 | 피드백 루프, exit code 기반 판단, BLOCK/PASS/WARN 처리 |
| G | Anti-pattern 해당 여부 | 리서치 문서의 anti-patterns 해당 여부 검사 |

점수: 1(심각한 문제) ~ 5(모범 사례)

---

## Part 1: 에이전트 평가

### 1.1 reviewer.md (138줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 138줄로 적절. 다만 PASS/WARN/BLOCK 예시가 각각 상당히 길어 약 60줄을 차지. 예시를 별도 파일로 분리하면 ~80줄로 축소 가능 |
| B. Description 품질 | 5/5 | 용도(코드 품질 리뷰), 트리거 조건(implement, fix 후), NOT 조건(아키텍처, 보안 제외)이 모두 명시됨 |
| C. 자유도 조절 | 5/5 | 텍스트 지침으로 리뷰 관점을 제시하면서, 구체적 출력 형식(PASS/WARN/BLOCK + 예시)으로 출력 품질을 보장. 리뷰 작업에 적합한 중간 자유도 |
| D. 도구 권한 스코핑 | 5/5 | Read, Glob, Grep만 허용. 읽기 전용으로 리뷰어에게 완벽한 스코핑 |
| E. Progressive Disclosure | 3/5 | 예시를 인라인으로 포함. 별도 `examples.md`로 분리하면 메인 정의가 더 간결해짐 |
| F. 검증 루프 | 4/5 | Handoff Context에서 PROCEED/REDO 판단 체계 명시. 다만 자체 검증 루프는 없음 (리뷰어 특성상 적절) |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.3/5**

**개선 제안:**
1. PASS/WARN/BLOCK 예시를 `reviewer/examples.md`로 분리하여 메인 파일을 ~80줄로 축소
2. "Minimum Output" 요구사항은 유지하되 예시는 참조로 전환

---

### 1.2 security.md (149줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 149줄로 약간 길지만 500줄 이하. 예시 블록이 ~65줄 차지 |
| B. Description 품질 | 5/5 | 용도(보안 리뷰), 트리거 조건(auth 변경, 사용자 입력, deploy 전, hotfix 시), NOT 조건(코드 스타일, 아키텍처 제외) 모두 포함. 에이전트 중 가장 상세한 description |
| C. 자유도 조절 | 5/5 | OWASP Top 10 체크리스트로 검사 범위를 구체화하면서, 심각도 판단은 에이전트 재량에 맡김. 보안 리뷰에 적합한 구성 |
| D. 도구 권한 스코핑 | 4/5 | Read, Glob, Grep, Bash 허용. Bash 사용 규칙을 본문에 명시(audit 명령만 허용, 파일 수정 금지)한 점이 좋음. 다만 `Bash(npm audit), Bash(pip audit), Bash(cargo audit), Bash(go vet), Bash(gh api *)` 같은 와일드카드 패턴으로 frontmatter에서 직접 제한하면 더 안전 |
| E. Progressive Disclosure | 3/5 | reviewer와 동일 - 예시를 인라인 포함 |
| F. 검증 루프 | 4/5 | PROCEED/BLOCK 체계 명시. Bash로 dependency audit 실행 가능하여 자동화된 검증 지원 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.2/5**

**개선 제안:**
1. Bash 도구 권한을 frontmatter의 `allowed-tools`에서 와일드카드로 제한: `Bash(npm audit *), Bash(pip audit *), Bash(cargo audit *), Bash(go vet *), Bash(gh api *)`
2. 예시를 `security/examples.md`로 분리
3. "Bash Usage Rules" 섹션은 frontmatter 수준 제한으로 대체하면 본문 6줄 절약

---

### 1.3 navigator.md (142줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 3/5 | 142줄 중 예시 블록이 ~55줄. "Example" 섹션 전체가 상세한 시나리오인데, 이는 `examples.md`로 분리 적합. 또한 "Capabilities" 섹션의 "Find Related Files", "Map Impact Scope", "Describe Code Structure"는 Process 섹션과 일부 중복 |
| B. Description 품질 | 5/5 | 용도(코드베이스 탐색, 파일 매핑, 영향 범위 파악), 트리거 조건(워크플로우 시작 시, implement 전, fix 전, "where is X" 질문), NOT 조건(리뷰, 보안, 아키텍처 제외) 모두 포함 |
| C. 자유도 조절 | 4/5 | Process에서 6단계 절차를 명시하면서도 각 단계의 구체적 실행은 자유. 출력 형식은 엄격하게 고정. 탐색 작업에 적합 |
| D. 도구 권한 스코핑 | 5/5 | Read, Glob, Grep만 허용. 탐색 전용으로 완벽한 스코핑 |
| E. Progressive Disclosure | 3/5 | 상세 예시를 인라인 포함 |
| F. 검증 루프 | 3/5 | 탐색 에이전트 특성상 자체 검증 루프 불필요. "Minimum Output" 요구사항으로 출력 품질 보장 |
| G. Anti-pattern | 경미 | "Capabilities" 섹션과 "Process" 섹션 간 약간의 설명 중복. '2.1 과도한 컨텍스트 소비' 경향 |

**종합: 3.9/5**

**개선 제안:**
1. "Capabilities" 섹션(1-3번)을 삭제하거나 Process에 통합 - Purpose에서 이미 역할을 설명하고 있으므로 중복
2. 상세 예시를 `navigator/examples.md`로 분리
3. Output Format 템플릿은 유지하되 구체적 시나리오 예시는 참조로 전환
4. 예상 축소: 142줄 -> ~75줄

---

### 1.4 architect.md (130줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 130줄로 에이전트 중 가장 짧음. 예시 블록이 ~50줄. 구조가 reviewer/security와 일관됨 |
| B. Description 품질 | 5/5 | 용도(아키텍처 리뷰), 트리거 조건(blueprint 산출물, 새 모듈 추가, 시스템 경계 변경, 기술 스택 선택, deepresearch 결과 평가), NOT 조건(코드 스타일, 보안, 단순 버그 제외) 모두 포함 |
| C. 자유도 조절 | 5/5 | 평가 기준을 명확히 제시하면서 아키텍처 판단은 에이전트 재량. PASS/WARN/BLOCK 출력 형식으로 품질 보장 |
| D. 도구 권한 스코핑 | 5/5 | Read, Glob, Grep만 허용. 읽기 전용 |
| E. Progressive Disclosure | 3/5 | reviewer/security와 동일 패턴 - 예시 인라인 |
| F. 검증 루프 | 4/5 | PROCEED/REDO 체계 명시 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.3/5**

**개선 제안:**
1. 예시를 `architect/examples.md`로 분리
2. 4개 리뷰 에이전트(reviewer, security, navigator, architect)의 공통 패턴(Output Requirements, Handoff Context)을 공유 참조 파일로 추출하면 각 파일에서 ~20줄 절약 가능

---

### 1.5 workflow.md (106줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 5/5 | 106줄로 간결. 오케스트레이션 패턴을 코드 블록으로 명확히 제시 |
| B. Description 품질 | 4/5 | 용도(워크플로우 오케스트레이션)와 NOT 조건(사용자 직접 호출 불가) 포함. 다만 트리거 조건이 "워크플로우 스킬에서 사용"으로 약간 모호 - 어떤 스킬이 이 에이전트를 사용하는지 목록이 있으면 더 명확 |
| C. 자유도 조절 | 5/5 | 오케스트레이션 패턴(Skill, Task, 병렬, 팀)을 구체적 코드 예시로 제시. Verdict 처리 규칙(BLOCK 시 최대 2회 재시도)이 명확 |
| D. 도구 권한 스코핑 | 3/5 | 13개 도구 허용 - Skill, Task, Read, Write, Edit, Glob, Grep, Bash, TeamCreate, TaskCreate, TaskUpdate, TaskList, SendMessage, TeamDelete. 오케스트레이터 특성상 많은 도구가 필요하지만, Bash에 와일드카드 제한이 없어 사실상 모든 시스템 명령 실행 가능. `Bash(git *), Bash(npm *), Bash(npx *)` 등으로 스코핑 권장 |
| E. Progressive Disclosure | 4/5 | 참조 파일 없이도 충분히 간결. 현재 수준에서 분리 불필요 |
| F. 검증 루프 | 5/5 | "Verification Rules"에서 exit code 기반 판단 원칙 명시. BLOCK 시 최대 2회 재시도 후 에스컬레이션 정책 포함 |
| G. Anti-pattern | 경미 | '4.3 서브에이전트 Anti-pattern #2: 모든 도구 허용'에 약간 해당. Bash 무제한 허용은 오케스트레이터가 역할 이탈할 가능성 존재 |

**종합: 4.3/5**

**개선 제안:**
1. Bash 도구를 와일드카드로 제한: `Bash(git *), Bash(npm *), Bash(npx *), Bash(python *)` 등 빌드/테스트 관련 명령으로 스코핑
2. Description에 "bugfix, hotfix, implement, improve, new-project 워크플로우에서 사용된다"를 추가하여 소비 스킬 목록 명시

---

## 에이전트 종합 평가

| 에이전트 | 줄 수 | 종합 점수 | 핵심 강점 | 최우선 개선 |
|----------|-------|-----------|-----------|-------------|
| reviewer | 138 | 4.3/5 | 읽기 전용 도구, 상세한 출력 예시 | 예시 파일 분리 |
| security | 149 | 4.2/5 | 가장 상세한 description, Bash 규칙 명시 | Bash frontmatter 스코핑 |
| navigator | 142 | 3.9/5 | 명확한 출력 형식, 도구 스코핑 | 중복 섹션 제거, 예시 분리 |
| architect | 130 | 4.3/5 | 가장 간결, 일관된 구조 | 예시 파일 분리 |
| workflow | 106 | 4.3/5 | 오케스트레이션 패턴 명확, 검증 규칙 | Bash 스코핑 |

**에이전트 평균: 4.2/5**

### 에이전트 공통 강점
1. **일관된 구조**: 4개 리뷰 에이전트가 Perspective -> Protocol -> Handoff -> Output 순서로 통일
2. **NOT 조건 명시**: 모든 에이전트가 "What NOT to Review/Do"를 명시하여 역할 경계 확립
3. **Handoff Context**: 입출력 소비자를 명시하여 에이전트 간 연결 관계 명확
4. **PASS/WARN/BLOCK 체계**: 리뷰 에이전트들의 일관된 verdict 체계

### 에이전트 공통 개선점
1. **예시 파일 분리**: 4개 리뷰 에이전트 모두 PASS/WARN/BLOCK 예시를 `examples.md`로 분리 가능 (각 ~40-60줄 절약)
2. **공통 패턴 추출**: Output Requirements, Handoff Context의 공통 구조를 shared reference로 추출 가능

---

## Part 2: 스킬 평가

### 2.1 워커 스킬 (10개)

#### 2.1.1 test/SKILL.md (123줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 123줄로 적절. 프레임워크별 명령어 목록이 ~20줄이지만 Claude가 대부분 알고 있는 정보 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거 키워드 포함, argument-hint 포함, 용도 명확 |
| C. 자유도 조절 | 4/5 | 테스트 구조(Happy/Edge/Error)와 프레임워크 감지 순서를 제시하면서 구체적 실행은 자유. 적절한 중간 자유도 |
| D. 도구 권한 스코핑 | 4/5 | Read, Write, Edit, Glob, Grep, Bash, Task. Bash 무제한이지만 테스트 실행에 다양한 명령이 필요하므로 어느 정도 합리적. Task는 navigator 호출용 |
| E. Progressive Disclosure | 4/5 | 참조 파일 없이도 123줄로 적절 |
| F. 검증 루프 | 5/5 | "테스트 실행 -> 결과 수집 -> 자동 판정" 루프 포함. PROCEED/실패 분석 체계 명시 |
| G. Anti-pattern | 경미 | 프레임워크별 실행 명령(jest, pytest, cargo, go)은 Claude가 이미 아는 정보 - '2.1 과도한 컨텍스트 소비' 해당 |

**종합: 4.3/5**

**개선 제안:**
1. 프레임워크별 실행 명령(Phase 4)과 커버리지 명령(Phase 5)을 삭제 - Claude가 이미 알고 있음. "프레임워크에 맞는 테스트 실행 명령을 사용한다"로 충분
2. 예상 축소: 123줄 -> ~95줄

---

#### 2.1.2 commit/SKILL.md (98줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 98줄로 간결. Conventional Commits 타입 목록(feat, fix, docs 등)은 Claude가 이미 아는 정보이나 프로젝트 특수 규칙(한국어 description, Co-Authored-By 미포함)과 함께 있어 삭제하기 어려움 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거, argument-hint 포함 |
| C. 자유도 조절 | 5/5 | 커밋 메시지 형식은 엄격하게 지정(Conventional Commits + 한국어), 스테이징 판단은 자유. 커밋은 깨지기 쉬운 작업이므로 낮은 자유도 적절 |
| D. 도구 권한 스코핑 | 4/5 | Read, Glob, Grep, Bash. Write/Edit 미포함으로 파일 수정 방지. 다만 Bash에서 git 외 명령도 실행 가능. `Bash(git *)` 스코핑 권장 |
| E. Progressive Disclosure | 5/5 | 짧아서 분리 불필요 |
| F. 검증 루프 | 5/5 | pre-commit hook 실패 시 "분석 -> 수정 -> 재스테이징 -> 새 커밋" 루프 명시 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.7/5**

**개선 제안:**
1. `allowed-tools`에서 Bash를 `Bash(git *)` 로 스코핑
2. Conventional Commits 타입 목록 7줄을 "Conventional Commits 형식. 한국어 description. Co-Authored-By 미포함" 1줄로 축소 가능 (Claude가 타입 목록을 이미 알고 있음)

---

#### 2.1.3 security-scan/SKILL.md (121줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 121줄. Grep 검색 패턴 목록이 유용하지만, audit 명령 목록은 Claude가 알고 있는 정보 |
| B. Description 품질 | 5/5 | 상세한 트리거 키워드, argument-hint 포함 |
| C. 자유도 조절 | 4/5 | 검색 패턴과 감지 순서를 구체적으로 지정. 보안 검사는 일관성이 중요하므로 낮은 자유도 적절 |
| D. 도구 권한 스코핑 | 4/5 | Read, Write, Glob, Grep, Bash, Task. Write는 결과 파일 저장용. Bash 무제한이지만 audit 명령에 다양한 패키지 매니저가 필요 |
| E. Progressive Disclosure | 4/5 | 분리 불필요한 적절한 길이 |
| F. 검증 루프 | 5/5 | "High/Critical 이슈 발견 시 security 에이전트에게 평가 요청" - 자동 에스컬레이션 루프 포함 |
| G. Anti-pattern | 경미 | audit 명령 목록(npm audit, pip audit 등)은 Claude가 이미 아는 정보 |

**종합: 4.3/5**

**개선 제안:**
1. Phase 2의 프로젝트별 audit 명령을 "프로젝트 타입에 맞는 의존성 audit 도구를 실행한다. 도구 미설치 시 사용자에게 알린다"로 축소
2. Bash 스코핑: `Bash(npm audit *), Bash(pip audit *), Bash(cargo audit *), Bash(govulncheck *), Bash(gh *)`

---

#### 2.1.4 deploy/SKILL.md (106줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 106줄. Docker/GitHub Actions 구성 목록이 ~15줄이지만 유용한 체크리스트 역할 |
| B. Description 품질 | 5/5 | 상세한 트리거, argument-hint 포함 |
| C. 자유도 조절 | 4/5 | 생성할 파일 목록을 구체적으로 지정하면서 내용은 자유. 배포 설정은 일관성이 중요하므로 적절 |
| D. 도구 권한 스코핑 | 4/5 | Read, Write, Edit, Glob, Grep, Bash, Task. 파일 생성이 필요하므로 Write/Edit 적절. Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 5/5 | "생성 후 security 에이전트 리뷰 요청 -> BLOCK 시 수정 후 재리뷰" 루프 포함 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.3/5**

**개선 제안:**
1. `disable-model-invocation: true` 추가 권장 - 배포 설정 생성은 부작용이 있는 작업이므로 Claude 자동 호출 방지
2. Bash 스코핑

---

#### 2.1.5 fix/SKILL.md (97줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 5/5 | 97줄로 간결하면서 모든 필수 정보 포함 |
| B. Description 품질 | 5/5 | "Internal skill... Called by /bugfix and /hotfix workflows, not directly by users." 역할과 소비자 명시. `user-invocable: false` 적절 |
| C. 자유도 조절 | 5/5 | 진단 순서 5단계를 명시하면서도 "최소한의 수정", "버그만 고친다" 등 원칙을 제시. 버그 수정에 적합한 중간 자유도 |
| D. 도구 권한 스코핑 | 4/5 | Read, Write, Edit, Glob, Grep, Bash, Task. 코드 수정이 필요하므로 Write/Edit 적절. Bash 무제한 |
| E. Progressive Disclosure | 5/5 | 짧아서 분리 불필요 |
| F. 검증 루프 | 4/5 | "재현 시도 -> 진단 -> 패치 -> 회귀 테스트" 루프. 다만 자체 리뷰는 호출 워크플로우에 위임 (명시적으로 설명되어 있어 적절) |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.7/5**

**개선 제안:**
1. Bash 스코핑 (공통 개선사항)
2. 거의 모범적인 워커 스킬 구조

---

#### 2.1.6 blueprint/SKILL.md (111줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 111줄. 산출물 디렉토리 구조와 출력 템플릿이 유용 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거, argument-hint 포함 |
| C. 자유도 조절 | 5/5 | 프로세스 단계를 명시하면서 규모별 설계 깊이를 차등 적용(소/중/대규모). 기획은 높은 자유도가 적합하므로 적절 |
| D. 도구 권한 스코핑 | 4/5 | 많은 도구(Read, Write, Glob, Grep, Bash, Task, WebSearch, WebFetch, Context7 2개). 기획에 리서치가 필요하므로 합리적이나 Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 5/5 | "산출물 생성 -> architect 리뷰 -> BLOCK 시 수정" 루프 포함 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.5/5**

**개선 제안:**
1. Bash 스코핑: `Bash(gh *)`로 GitHub CLI만 허용 (기획 단계에서 시스템 명령은 불필요)
2. 동적 컨텍스트 주입 `!`date +%Y`` 패턴 사용 - 좋은 패턴 (best practice 8.1 해당)

---

#### 2.1.7 deepresearch/SKILL.md (92줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 5/5 | 92줄로 가장 간결한 스킬 중 하나. 불필요한 설명 없이 핵심만 포함 |
| B. Description 품질 | 5/5 | 매우 상세한 트리거 키워드(한국어 5개 + 영어 1개 + 설명), 용도 명확 |
| C. 자유도 조절 | 5/5 | 병렬 검색 패턴을 구체적으로 제시하면서 결과 분석은 자유. 리서치는 높은 자유도 적절 |
| D. 도구 권한 스코핑 | 4/5 | WebSearch, WebFetch, Context7, Read, Write, Glob, Grep, Bash. "Bash는 gh 명령 전용" 명시. frontmatter에서 `Bash(gh *)` 스코핑이면 더 강력 |
| E. Progressive Disclosure | 5/5 | 짧아서 분리 불필요 |
| F. 검증 루프 | 3/5 | 자체 검증 루프 없음. 리서치 특성상 자동 검증이 어렵지만, 최소 "수집된 출처 수 < 3이면 추가 검색" 같은 품질 게이트가 있으면 좋음 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.5/5**

**개선 제안:**
1. Bash frontmatter 스코핑: `Bash(gh *)`
2. 최소 품질 게이트 추가: "유의미한 출처가 3개 미만이면 검색 키워드를 변형하여 추가 검색"
3. `agent: general-purpose` 명시 - 이 필드가 유효한 값인지 확인 필요. 공식 문서에서는 agents/ 디렉토리의 에이전트 이름을 참조

---

#### 2.1.8 decide/SKILL.md (127줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 127줄. 결과 출력 템플릿(~30줄)이 약간 길지만 복잡한 판단의 구조화에 필요 |
| B. Description 품질 | 5/5 | 가장 상세한 트리거 키워드 목록(한국어 7개 + 영어 1개). 다양한 호출 시나리오를 포괄 |
| C. 자유도 조절 | 5/5 | 문제 구조화 -> 정보 수집 -> 분석 -> 판단의 명확한 프레임워크. "정답 없음도 답이다", "확신도 명시" 같은 판단 원칙 포함 |
| D. 도구 권한 스코핑 | 4/5 | deepresearch와 동일한 도구 세트. Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 3/5 | 자체 검증 루프 없음. 의사결정 특성상 자동 검증 어려움. "확신도: 낮음"인 경우 추가 조사를 권하는 규칙이 있으면 좋음 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.2/5**

**개선 제안:**
1. Bash frontmatter 스코핑: `Bash(gh *)`
2. `agent: general-purpose` 유효성 확인 (deepresearch와 동일)
3. 결과 출력 템플릿을 약간 축소 가능

---

#### 2.1.9 team-review/SKILL.md (139줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 139줄. 리뷰어 스폰 프롬프트가 각 ~7줄로 총 ~21줄 차지. 반복적이지만 팀원에게 충분한 컨텍스트를 제공하기 위해 필요 |
| B. Description 품질 | 5/5 | 용도, 트리거, 방법론(멀티렌즈) 모두 포함 |
| C. 자유도 조절 | 5/5 | 팀 생성 -> 태스크 생성 -> 스폰 -> 모니터링 -> 정리의 구체적 시퀀스. 에이전트팀 운영은 일관성이 중요하므로 낮은 자유도 적절 |
| D. 도구 권한 스코핑 | 4/5 | Task, Read, Glob, Grep, Bash + 팀 도구 6개. Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 4/5 | "3개 태스크 completed 확인 -> 결과 종합 -> verdict 판단" 체계 |
| G. Anti-pattern | 없음 | 비용 주의 섹션 포함 - 좋은 패턴 |

**종합: 4.3/5**

**개선 제안:**
1. 3명의 스폰 프롬프트에서 공통 부분을 추출하여 반복 감소
2. "적용 기준" 섹션 - 사용/미사용 기준이 명확하여 좋음
3. Bash 스코핑

---

#### 2.1.10 qa-swarm/SKILL.md (181줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 3/5 | **181줄로 스킬 중 가장 긺.** 태스크 생성 블록(~30줄), 팀원 스폰 블록(~25줄), 출력 템플릿(~30줄)이 각각 상세. 감지 대상 목록, 팀원별 프롬프트에 반복 내용 존재 |
| B. Description 품질 | 5/5 | 상세한 트리거 키워드, argument-hint 포함 |
| C. 자유도 조절 | 4/5 | 동적 태스크 생성(감지된 도구에 따라 건너뛰기)이 좋은 패턴. 다만 4명의 팀원 프롬프트가 매우 유사하여 하나의 템플릿으로 통합 가능 |
| D. 도구 권한 스코핑 | 4/5 | Task, Skill, Read, Glob, Grep, Bash + 팀 도구. Bash 무제한 |
| E. Progressive Disclosure | 2/5 | 181줄인데 참조 파일이 없음. 태스크 생성 예시와 팀원 프롬프트를 `qa-swarm/templates.md`로 분리 가능 |
| F. 검증 루프 | 5/5 | "exit code 기반 판단", "TaskCompleted 훅 자동 검증" 명시. 빌드/테스트 검증 규칙 별도 섹션 |
| G. Anti-pattern | 해당 | **'2.1 과도한 컨텍스트 소비'**: 태스크 생성 블록과 팀원 프롬프트가 유사한 내용을 반복. **'2.3 선택지 과다'**: 감지 대상 목록이 여러 언어/도구를 나열하지만 Claude가 대부분 알고 있는 정보 |

**종합: 3.8/5**

**개선 제안:**
1. **태스크 생성 + 팀원 스폰 템플릿을 단일 패턴으로 통합**: "감지된 각 테스트 유형별로 TaskCreate와 팀원 스폰을 수행한다. 프롬프트: 해당 유형의 도구를 실행하고, exit code로 결과를 판단하여 TaskUpdate로 보고하라."
2. 감지 대상 목록(package.json, Cargo.toml 등)을 삭제하거나 1-2줄로 축소 - Claude가 프로젝트 설정 파일을 감지하는 방법을 이미 알고 있음
3. 출력 템플릿을 `qa-swarm/output-template.md`로 분리
4. 예상 축소: 181줄 -> ~110줄

---

### 2.2 워크플로우 스킬 (5개)

#### 2.2.1 bugfix/SKILL.md (131줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 131줄. 복잡 버그의 에이전트팀 패턴이 ~35줄로 상세하지만, 팀 기반 디버깅의 복잡성을 고려하면 필요 |
| B. Description 품질 | 5/5 | "fix"와 구분되는 트리거(사용자 대면), 한국어/영어 키워드 풍부 |
| C. 자유도 조절 | 5/5 | 단순/복잡 버그 분기 로직이 명확. 각 경로의 구체적 절차 제시. 디버깅은 체계적 접근이 중요하므로 적절 |
| D. 도구 권한 스코핑 | 3/5 | 14개 도구(Skill, Task, Read, Write, Edit, Glob, Grep, Bash + 팀 도구 6개). 워크플로우 특성상 많은 도구가 필요하지만 Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 5/5 | Phase 1(진단+수정) -> Phase 2(리뷰, BLOCK 시 재리뷰) -> Phase 3(회귀 테스트, 실패 시 자동 수정). exit code 기반 판단 명시 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.3/5**

**개선 제안:**
1. Bash 스코핑
2. "경쟁 가설 디버깅" 패턴이 잘 설계됨 - best practice '5.1 경쟁 가설 디버깅' 적용

---

#### 2.2.2 hotfix/SKILL.md (107줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 5/5 | 107줄로 간결. 4개 Phase를 명확하게 기술 |
| B. Description 품질 | 5/5 | bugfix와 구분되는 트리거(보안, 긴급), 한국어/영어 키워드 |
| C. 자유도 조절 | 5/5 | 심각도별 분기(Critical/High → 즉시 진행, Medium/Low → 사용자 확인), 이중 리뷰 요구. 보안 수정은 엄격한 절차가 필요하므로 적절 |
| D. 도구 권한 스코핑 | 3/5 | Skill, Task, Read, Write, Edit, Glob, Grep, Bash. 팀 도구 미포함(hotfix는 팀 불필요)은 좋음. Bash 무제한 |
| E. Progressive Disclosure | 5/5 | 짧아서 분리 불필요 |
| F. 검증 루프 | 5/5 | Phase 1(심각도 평가) -> Phase 2(수정) -> Phase 3(이중 리뷰, 병렬) -> Phase 4(테스트+보안스캔). 가장 엄격한 검증 체계 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.7/5**

**개선 제안:**
1. Bash 스코핑
2. 병렬 리뷰 패턴(`run_in_background=true`) - 모범적인 효율화

---

#### 2.2.3 implement/SKILL.md (143줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 4/5 | 143줄. 린트/포맷 감지 목록(~8줄)과 Phase 6 병렬 리뷰 예시가 약간 길지만 유용 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거, argument-hint 포함 |
| C. 자유도 조절 | 5/5 | 6개 Phase의 순서와 각 Phase의 구체적 절차 제시. 구현은 체계적 접근이 중요하므로 적절 |
| D. 도구 권한 스코핑 | 3/5 | Skill, Task, Read, Write, Edit, Glob, Grep, Bash. Bash 무제한 |
| E. Progressive Disclosure | 4/5 | 적절한 길이 |
| F. 검증 루프 | 5/5 | Phase 3(코드 작성) -> Phase 4(린트) -> Phase 5(테스트, 실패 시 fix+재테스트) -> Phase 6(리뷰, BLOCK 시 재리뷰). 가장 완전한 검증 체인 |
| G. Anti-pattern | 경미 | 린트/포맷 감지 목록은 Claude가 대부분 알고 있는 정보 |

**종합: 4.3/5**

**개선 제안:**
1. Phase 4의 감지 우선순위 목록 축소: "프로젝트의 린터/포맷터를 감지하여 실행한다"로 충분
2. Bash 스코핑
3. Phase 6의 병렬 리뷰 패턴 - 좋은 패턴

---

#### 2.2.4 improve/SKILL.md (97줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 5/5 | 97줄로 매우 간결. 3개 Phase + 조건부 Phase 1.5를 효율적으로 기술 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거, bugfix/new-project와의 차이점 명시 |
| C. 자유도 조절 | 5/5 | 변경 규모에 따른 분기(큰 변경 -> 기획 포함, 작은 변경 -> 개발 직행). 적응적 자유도 |
| D. 도구 권한 스코핑 | 3/5 | Skill, Task, Read, Write, Edit, Glob, Grep, Bash. Bash 무제한 |
| E. Progressive Disclosure | 5/5 | 짧아서 분리 불필요 |
| F. 검증 루프 | 5/5 | Phase 1(분석) -> Phase 1.5(기획+아키텍처 리뷰) -> Phase 2(개발+코드 리뷰) -> Phase 3(회귀 테스트). exit code 기반 판단 명시 |
| G. Anti-pattern | 없음 | 해당 없음 |

**종합: 4.7/5**

**개선 제안:**
1. Bash 스코핑
2. 거의 모범적인 워크플로우 구조. 간결하면서도 빈틈 없는 검증 체인

---

#### 2.2.5 new-project/SKILL.md (177줄)

| 항목 | 점수 | 평가 |
|------|------|------|
| A. 컨텍스트 효율성 | 3/5 | **177줄로 워크플로우 중 가장 긺.** Phase 3의 에이전트팀 병렬 개발 패턴이 ~35줄, 순차 개발 패턴이 ~5줄. 병렬 패턴의 상세 절차가 컨텍스트를 많이 소비 |
| B. Description 품질 | 5/5 | 한국어/영어 트리거, improve/bugfix와의 차이점 명시 |
| C. 자유도 조절 | 5/5 | Phase별 구체적 절차 + 병렬/순차 분기 조건(독립 태스크 3개 기준). 대규모 프로젝트 구축은 체계적 접근 필수 |
| D. 도구 권한 스코핑 | 3/5 | 14개 도구(Skill, Task, Read, Write, Edit, Glob, Grep, Bash + 팀 도구 6개). Bash 무제한 |
| E. Progressive Disclosure | 2/5 | 177줄인데 참조 파일 없음. Phase 3의 에이전트팀 패턴을 별도 파일로 분리 가능 |
| F. 검증 루프 | 5/5 | 5개 Phase 각각에 리뷰+검증 루프. BLOCK 시 최대 2회 재시도. TaskCompleted 훅 활용. 가장 포괄적인 검증 체계 |
| G. Anti-pattern | 경미 | Phase 3a의 에이전트팀 패턴이 team-review/qa-swarm과 유사한 팀 운영 코드를 반복. 공유 참조로 추출 가능 |

**종합: 3.8/5**

**개선 제안:**
1. **Phase 3a(에이전트팀 병렬 개발)를 `new-project/parallel-dev.md`로 분리**: "독립 태스크 3개 이상이면 `parallel-dev.md` 패턴을 따른다"로 참조
2. 팀 운영 공통 패턴(TeamCreate -> TaskCreate -> 스폰 -> 모니터링 -> shutdown -> TeamDelete)을 shared reference로 추출
3. 예상 축소: 177줄 -> ~120줄

---

## Part 3: 종합 분석

### 스킬 종합 점수

| 스킬 | 유형 | 줄 수 | 점수 | 등급 |
|------|------|-------|------|------|
| commit | 워커 | 98 | 4.7/5 | A |
| fix | 워커 | 97 | 4.7/5 | A |
| hotfix | 워크플로우 | 107 | 4.7/5 | A |
| improve | 워크플로우 | 97 | 4.7/5 | A |
| blueprint | 워커 | 111 | 4.5/5 | A |
| deepresearch | 워커 | 92 | 4.5/5 | A |
| test | 워커 | 123 | 4.3/5 | B+ |
| security-scan | 워커 | 121 | 4.3/5 | B+ |
| deploy | 워커 | 106 | 4.3/5 | B+ |
| team-review | 워커 | 139 | 4.3/5 | B+ |
| bugfix | 워크플로우 | 131 | 4.3/5 | B+ |
| implement | 워크플로우 | 143 | 4.3/5 | B+ |
| decide | 워커 | 127 | 4.2/5 | B+ |
| qa-swarm | 워커 | 181 | 3.8/5 | B |
| new-project | 워크플로우 | 177 | 3.8/5 | B |

**스킬 평균: 4.3/5**

### 전체 시스템 점수

| 범주 | 평균 점수 |
|------|-----------|
| 에이전트 (5개) | 4.2/5 |
| 워커 스킬 (10개) | 4.3/5 |
| 워크플로우 스킬 (5개) | 4.3/5 |
| **전체 평균** | **4.3/5** |

---

## Part 4: 시스템 레벨 분석

### 강점 (Best Practices 적합)

1. **전체 fork 격리**: 모든 15개 스킬이 `context: fork`로 서브에이전트에서 실행. 메인 컨텍스트 보호에 효과적 (BP 4.1, 8.2)

2. **일관된 DO/REVIEW 패턴**: 워크플로우 스킬들이 "DO(실행) -> REVIEW(검증) -> BLOCK 시 재시도(최대 2회)" 패턴을 일관되게 적용 (BP 1.7)

3. **exit code 기반 검증**: "텍스트 보고를 신뢰하지 않는다"는 원칙이 워크플로우 스킬 5개와 workflow 에이전트에 반복 명시 (BP 7.2)

4. **에이전트 역할 분리**: 4개 리뷰 에이전트가 각각 명확한 전문 영역을 가지며 NOT 조건으로 역할 경계 확립 (BP 4.3)

5. **적응적 스케일링**: bugfix(단순/복잡 분기), improve(큰/작은 변경 분기), new-project(병렬/순차 개발 분기)가 상황에 맞게 리소스 투입을 조절 (BP 5.1)

6. **동적 컨텍스트 주입**: deepresearch, decide, blueprint에서 `!`date +%Y`` 패턴 사용 (BP 8.1)

7. **비용 인식**: team-review, qa-swarm에 "비용 주의" 섹션 포함, 적용 기준(사용/미사용) 명시 (BP 5.2, 5.3)

8. **Handoff Context**: 에이전트들이 입력 소스와 출력 소비자를 명시하여 파이프라인 연결 관계가 명확

### 약점 (Anti-Patterns 해당)

1. **Bash 도구 무제한 허용 (전체 시스템 공통)**:
   - 해당 anti-pattern: '4.4 서브에이전트 AP #2: 모든 도구 허용'
   - 영향: 15개 스킬 중 13개, 5개 에이전트 중 2개에서 Bash 무제한
   - 위험: 역할 이탈, 의도치 않은 시스템 변경
   - **우선순위: 높음**

2. **예시 인라인 포함 (리뷰 에이전트 4개)**:
   - 해당 anti-pattern: '2.1 과도한 컨텍스트 소비'
   - 영향: 4개 리뷰 에이전트에서 총 ~220줄이 예시에 사용
   - **우선순위: 중간**

3. **Claude가 이미 아는 정보 포함 (워커 스킬 다수)**:
   - 해당 anti-pattern: '1.1 간결성 원칙' 위반
   - 해당 스킬: test(프레임워크 명령어), security-scan(audit 명령어), implement(린트 감지 목록), qa-swarm(감지 대상 목록)
   - 영향: 약 40-50줄의 불필요한 정보
   - **우선순위: 낮음**

4. **긴 스킬의 Progressive Disclosure 미활용**:
   - 해당 anti-pattern: '1.2 Progressive Disclosure' 미적용
   - 해당 스킬: qa-swarm(181줄), new-project(177줄)
   - 참조 파일로 분리하면 각각 ~110줄, ~120줄로 축소 가능
   - **우선순위: 중간**

5. **팀 운영 패턴 반복**:
   - 해당 anti-pattern: 간접적으로 '2.1 과도한 컨텍스트 소비'
   - 해당 스킬: team-review, qa-swarm, bugfix, new-project에서 TeamCreate -> TaskCreate -> 스폰 -> shutdown -> TeamDelete 패턴이 반복
   - 공유 참조 파일로 추출하면 각 스킬에서 ~15줄 절약
   - **우선순위: 낮음**

---

## Part 5: 우선순위별 개선 액션

### P0 (즉시 - 보안/안정성)

| # | 대상 | 액션 | 예상 효과 |
|---|------|------|-----------|
| 1 | 전체 스킬/에이전트 | Bash 도구 와일드카드 스코핑 적용 | 역할 이탈 방지, 의도치 않은 시스템 변경 차단 |
| 2 | deploy | `disable-model-invocation: true` 추가 | 배포 설정의 의도치 않은 자동 생성 방지 |

### P1 (단기 - 컨텍스트 효율)

| # | 대상 | 액션 | 예상 효과 |
|---|------|------|-----------|
| 3 | 리뷰 에이전트 4개 | PASS/WARN/BLOCK 예시를 `examples.md`로 분리 | 각 에이전트 ~40-60줄 절약 |
| 4 | qa-swarm | 태스크/팀원 템플릿 통합, 감지 목록 축소 | 181줄 -> ~110줄 |
| 5 | new-project | Phase 3a를 `parallel-dev.md`로 분리 | 177줄 -> ~120줄 |

### P2 (중기 - 품질)

| # | 대상 | 액션 | 예상 효과 |
|---|------|------|-----------|
| 6 | test, security-scan, implement | Claude가 아는 정보(명령어 목록) 삭제 | 각 ~10-15줄 절약 |
| 7 | navigator | Capabilities/Process 중복 제거 | 142줄 -> ~75줄 |
| 8 | deepresearch, decide | 최소 품질 게이트 추가 | 결과 품질 향상 |
| 9 | 팀 운영 스킬 4개 | 공통 팀 운영 패턴을 shared reference로 추출 | 각 ~15줄 절약, 일관성 향상 |

### P3 (장기 - 아키텍처)

| # | 대상 | 액션 | 예상 효과 |
|---|------|------|-----------|
| 10 | deepresearch, decide | `agent: general-purpose` 필드 유효성 확인 | 의도대로 동작하는지 검증 |
| 11 | workflow 에이전트 | description에 소비 스킬 목록 추가 | 디스커버리 정확도 향상 |

---

## 결론

전체 시스템은 **4.3/5점**으로 best practices를 높은 수준으로 따르고 있다.

핵심 강점은 전체 fork 격리, 일관된 DO/REVIEW 패턴, exit code 기반 검증, 적응적 스케일링이다. 이는 리서치 문서의 핵심 best practices(컨텍스트 보호, 검증 루프, 적절한 팀 활용)를 충실히 반영한다.

가장 시급한 개선 사항은 **Bash 도구의 와일드카드 스코핑**이다. 현재 13개 스킬에서 Bash가 무제한으로 허용되어 있어, 서브에이전트가 의도치 않은 시스템 명령을 실행할 위험이 있다. 이것은 리서치 문서의 '도구 권한 스코핑' best practice(섹션 8.5)와 '모든 도구 허용' anti-pattern(섹션 4.4 #2)에 정면으로 해당한다.

두 번째로 중요한 개선은 **Progressive Disclosure 활용**이다. qa-swarm(181줄)과 new-project(177줄)은 참조 파일 분리로 각각 ~70줄, ~57줄을 절약할 수 있다. 4개 리뷰 에이전트의 예시도 분리 대상이다.

이미 잘 되어 있는 부분(fork 격리, 역할 분리, 검증 체계)은 유지하면서, Bash 스코핑과 Progressive Disclosure만 적용해도 시스템 전체 점수를 4.5/5 이상으로 올릴 수 있다.
