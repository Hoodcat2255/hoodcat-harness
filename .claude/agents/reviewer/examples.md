# Reviewer Agent - PASS/WARN/BLOCK Examples

### PASS Example
```markdown
## Code Review

**Scope**: src/services/auth.ts (new), src/routes/login.ts (modified)
**Verdict**: PASS

### Files Reviewed
- `src/services/auth.ts` (87 lines, new file)
- `src/routes/login.ts` (12 lines changed)
- `src/services/__tests__/auth.test.ts` (45 lines, new file)

### Verified Items
1. Naming: Function names clearly express intent (validateToken, refreshSession)
2. Consistency: Error handling follows the existing Result<T, E> pattern used in src/services/
3. Test quality: Tests cover happy path, expired token, and invalid signature cases

### Positive Notes
- Good use of early returns to reduce nesting in validateToken
- Test file mirrors the structure of existing tests in the project
```

### WARN Example
```markdown
## Code Review

**Scope**: src/utils/parser.ts (modified)
**Verdict**: WARN

### Files Reviewed
- `src/utils/parser.ts` (23 lines changed)

### Findings

WARN: Function too long
- File: src/utils/parser.ts:45-112
- Issue: parseDocument() is 67 lines with 4 levels of nesting
- Suggestion: Extract the validation block (lines 58-89) into a separate validateStructure() function

WARN: Inconsistent error handling
- File: src/utils/parser.ts:92
- Issue: Uses throw here but the rest of the module returns Result types
- Suggestion: Return Err(ParseError.InvalidStructure) to match module convention
```

### BLOCK Example
```markdown
## Code Review

**Scope**: src/db/migrations/003_add_orders.ts
**Verdict**: BLOCK

### Findings

BLOCK: No test coverage for critical business logic
- File: src/db/migrations/003_add_orders.ts:34-78
- Issue: Order total calculation logic has zero test coverage and handles money arithmetic with floating point
- Required: Add tests for calculation logic; use integer cents instead of float dollars for money values
```
