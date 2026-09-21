# General Anti-patterns

These are structural anti-patterns that apply across all languages. Claude already knows these concepts - this file serves as a checklist to verify during reviews.

## Architecture

- God Object: A single class/module handling too many responsibilities. Split by domain.
- Circular Dependencies: Module A imports B which imports A. Introduce an interface or mediator.
- Hardcoded Configuration: DB URLs, ports, feature flags embedded in code. Externalize to env vars or config files.

## Error Handling

- Swallowed Exceptions: Catching errors without logging or re-raising. Always log at minimum.
- Overly Broad Catch: Catching all errors when only specific ones are expected. Be specific.
- Error Codes as Returns: Returning -1 or null to indicate errors instead of using the language's error mechanism.

## Security

- Secrets in Source: API keys, passwords, tokens in code or config files checked into git.
- Debug Mode in Production: Debug flags, verbose logging, or development endpoints left enabled.
- Missing Input Validation: User input reaching business logic or DB without sanitization.

## Performance

- N+1 Queries: Looping through records and issuing a query for each one. Use joins or batch queries.
- Unbounded Queries: SELECT * without LIMIT on tables that can grow. Always paginate.
- Missing Resource Cleanup: File handles, DB connections, or network sockets not properly closed.
