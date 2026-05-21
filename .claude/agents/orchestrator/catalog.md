# Orchestrator Skill Catalog
> orchestrator의 Skill Catalog 정본. 본 파일이 정본이며 orchestrator.md에서는 cross-link로 참조한다.

### Research & Planning

| Skill | Agent | When to use |
|-------|-------|-------------|
| `deepresearch` | researcher | Technology research, pattern investigation, prior art |
| `blueprint` | researcher | Complex features, new projects, architecture decisions |
| `decide` | researcher | Technology comparison, library selection |

### Coding

| Skill | Agent | When to use |
|-------|-------|-------------|
| `code` | coder | All code changes: implement, fix bugs, refactor |
| `test` | coder | Write/run tests, verify changes |
| `scaffold` | coder | Create new skills/agents for the harness |

### Operations

| Skill | Agent | When to use |
|-------|-------|-------------|
| `commit` | committer | Git commits after code changes |
| `deploy` | coder | Deployment configuration |
| `security-scan` | coder | Dependency audits, vulnerability scanning |
| `sync-docs` | coder | Sync harness docs after skill/agent/hook changes |

### Review Agents (via Task)

| Agent | When to use |
|-------|-------------|
| `navigator` | Explore codebase before code changes |
| `reviewer` | Code quality review after changes |
| `security` | Auth, input validation, crypto-related code |
| `architect` | Structural changes, new modules |

### Team-based (large-scale)

| Skill | Agent | When to use |
|-------|-------|-------------|
| `team-review` | coder | Multi-lens review for large/high-risk changes |
| `qa-swarm` | coder | Parallel QA for diverse test suites |

Note: `/ultrareview` (Claude Code 공식 슬래시 커맨드, 별도 과금/background 실행)는 Orchestrator가 자동 호출하지 않는다. 사용자가 명시적으로 요청한 경우에만 안내한다. 자체 판단으로 다관점 리뷰가 필요하면 `team-review`를 사용한다. 상세 비교는 `docs/research-ultrareview-vs-team-review-20260516.md` 참고.

## OMC 호환 매핑 (Phase 3)

본 카탈로그는 hoodcat-harness 자체 스킬·에이전트 기준. OMC 전환 시 다음과 같이 매핑된다.

### Skill → OMC Agent/Skill 매핑

| hoodcat skill | OMC agent / skill | 호출 형태 | 신뢰도 |
|---------------|-------------------|----------|--------|
| `code` | executor | `Agent(subagent_type="oh-my-claudecode:executor", model="sonnet")` | 높음 |
| `test` | test-engineer / executor | `Agent(subagent_type="oh-my-claudecode:test-engineer", model="sonnet")` | 중간 |
| `blueprint` | planner | `Agent(subagent_type="oh-my-claudecode:planner", model="opus")` | 높음 |
| `commit` | git-master | `Agent(subagent_type="oh-my-claudecode:git-master", model="sonnet")` | 높음 |
| `deepresearch` | document-specialist | `Agent(subagent_type="oh-my-claudecode:document-specialist", model="sonnet")` | 높음 |
| `decide` | analyst | `Agent(subagent_type="oh-my-claudecode:analyst", model="opus")` | 중간 |
| `security-scan` | security-reviewer | `Agent(subagent_type="oh-my-claudecode:security-reviewer", model="opus")` | 중간 |
| `team-review` | team / ultrareview | `Skill("oh-my-claudecode:team", ...)` | 중간 |
| `qa-swarm` | ultraqa | `Skill("oh-my-claudecode:ultraqa", ...)` | 중간 |
| `deploy` | (매핑 없음) | executor에 위임 또는 신규 OMC 스킬 작성 | 낮음 |
| `scaffold` | (매핑 없음) | hoodcat 고유 메타-스킬 | 낮음 |
| `sync-docs` | (매핑 없음) | hoodcat 고유 메타-스킬 | 낮음 |

### Agent → OMC Agent 매핑

| hoodcat agent | OMC agent | 모델 | 비고 |
|---------------|-----------|------|------|
| orchestrator | (planner + main agent 디스패치) | opus | OMC는 Claude main agent가 디스패처. 동적 계획은 planner로. |
| coder | executor | sonnet (복잡 시 opus) | 1:1 매핑 |
| researcher | document-specialist (+scientist) | sonnet | 단일 주제 조사 |
| committer | git-master | sonnet | conventional commit 자동 감지 |
| navigator | explore | sonnet | read-only 단순 탐색 |
| reviewer | code-reviewer | opus | OMC code-reviewer는 항상 HIGH tier |
| architect | architect | opus | 이름·역할 동일 |
| security | security-reviewer | opus | OWASP·취약점 |

세부 사항·미해결 검증 항목은 `docs/migration-omc-mapping-20260522.md` 1·2절 참조.
