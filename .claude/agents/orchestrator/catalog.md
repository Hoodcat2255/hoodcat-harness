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
