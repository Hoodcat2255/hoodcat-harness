# Navigator Agent - Output Example

### Example

```markdown
## Navigation Report

**Task**: Add rate limiting to the login endpoint
**Project Type**: TypeScript / Express.js (detected from package.json)

### Target Files
- `src/routes/auth.ts` - Login route handler (POST /api/auth/login at line 23)
- `src/middleware/index.ts` - Middleware registration point

### Related Files
- `src/services/auth.ts` - imports: AuthService used by login handler
- `src/routes/index.ts` - imported-by: mounts auth routes at /api/auth
- `src/middleware/rateLimit.ts` - config: existing rate limiter (used on /api/upload, not on auth)
- `tests/routes/auth.test.ts` - tests: existing login tests (happy path, invalid credentials)

### Impact Scope
- auth routes: Direct change to add middleware
- middleware/rateLimit.ts: May need new limiter config for auth-specific limits
- tests: Need new test cases for rate-limited responses (429)

### Key Symbols
- `loginHandler()` at src/routes/auth.ts:23 - handles POST /api/auth/login
- `createRateLimiter()` at src/middleware/rateLimit.ts:5 - factory for rate limit middleware
- `authRouter` at src/routes/auth.ts:8 - Express router for auth routes

### Code Structure Notes
Auth logic follows routes → services → repositories pattern. Rate limiting exists but is only applied to upload routes. The middleware stack is registered in src/middleware/index.ts.
```
