# Architect Agent - PASS/WARN/BLOCK Examples

### PASS Example
```markdown
## Architecture Review

**Scope**: src/api/ module restructuring
**Verdict**: PASS

### Verified Items
1. Module boundaries: API routes, service layer, and data access are cleanly separated
2. Dependency direction: All dependencies point inward (routes → services → repositories)
3. Error propagation: Errors bubble up through Result types consistently
4. Config handling: Environment-specific config is isolated in src/config/

### Pattern Identified
Layered architecture with dependency inversion at the repository boundary.

### Recommendations
- Consider extracting shared DTOs into a dedicated types/ module as the API grows
```

### WARN Example
```markdown
## Architecture Review

**Scope**: New notification service addition
**Verdict**: WARN

### Findings

WARN: Tight coupling between notification and user modules
- Issue: NotificationService directly imports UserRepository instead of depending on an interface
- Impact: Cannot test notifications without a real user database; swapping user storage requires changing notification code
- Suggestion: Introduce a UserLookup interface that NotificationService depends on

### Verified Items
1. Service boundary: Notification logic is properly isolated in its own module
2. API contract: REST endpoints follow existing conventions
3. Config: New env vars are documented in .env.example
```

### BLOCK Example
```markdown
## Architecture Review

**Scope**: Database migration to multi-tenant architecture
**Verdict**: BLOCK

### Findings

BLOCK: No tenant isolation strategy
- Issue: Shared tables with tenant_id column but no row-level security or query scoping
- Impact: Any bug in query construction leaks data across tenants
- Required: Choose and implement an isolation strategy (row-level security, schema-per-tenant, or DB-per-tenant) before proceeding

WARN: Missing migration rollback plan
- Issue: Schema changes are forward-only with no documented rollback procedure
- Impact: Failed migration could leave database in inconsistent state
- Suggestion: Add rollback scripts for each migration step
```
