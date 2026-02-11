# Security Agent - PASS/WARN/BLOCK Examples

### PASS Example
```markdown
## Security Review

**Scope**: src/api/auth/ module (login, token refresh, password reset)
**Verdict**: PASS

### Attack Surfaces Examined
1. Login endpoint: Password comparison uses constant-time bcrypt.compare
2. Token refresh: Tokens are short-lived (15min), refresh tokens are rotated on use
3. Password reset: Rate limited (3 attempts/hour), token expires in 10 minutes
4. Input validation: All user inputs sanitized via zod schemas at route level

### OWASP Categories Checked
- A01 Broken Access Control: Role checks present on all protected routes
- A02 Cryptographic Failures: Passwords hashed with bcrypt, cost factor 12
- A03 Injection: Parameterized queries used throughout
- A07 Auth Failures: Account lockout after 5 failed attempts

### Dependency Check
npm audit: 0 vulnerabilities found
```

### WARN Example
```markdown
## Security Review

**Scope**: src/api/upload.ts (file upload endpoint)
**Verdict**: WARN

### Findings

WARN: Missing file type validation
- Location: src/api/upload.ts:23
- Risk: Medium
- Attack Vector: Attacker uploads .html file → stored in public directory → served as HTML → stored XSS
- Mitigation: Validate file MIME type server-side (not just extension); serve uploads from a separate domain or with Content-Disposition: attachment

### Attack Surfaces Examined
1. File upload: Size limit present (10MB), but no type restriction
2. Storage: Files stored in /public/uploads with original names (path traversal check present)
```

### BLOCK Example
```markdown
## Security Review

**Scope**: src/api/admin.ts (admin panel endpoints)
**Verdict**: BLOCK

### Findings

BLOCK: SQL Injection in search endpoint
- Location: src/api/admin.ts:67
- Severity: Critical
- Attack Vector: User search query is concatenated directly into SQL string: `SELECT * FROM users WHERE name = '${query}'`
- Impact: Full database read/write access, potential data exfiltration
- Required Fix: Use parameterized queries: `db.query('SELECT * FROM users WHERE name = $1', [query])`

BLOCK: No authentication on admin endpoints
- Location: src/api/admin.ts:12
- Severity: Critical
- Attack Vector: Admin routes are registered without auth middleware; any unauthenticated user can access them
- Impact: Unauthorized access to user management, data deletion, system configuration
- Required Fix: Add adminAuth middleware to the router before all admin route handlers
```
