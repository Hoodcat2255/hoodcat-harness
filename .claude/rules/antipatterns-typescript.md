# TypeScript Anti-patterns

These are project-specific patterns to avoid. Claude already knows general TypeScript best practices - this file covers patterns that are commonly missed or project-specific.

## Type Safety

- Never use `as any` to bypass type errors. Fix the underlying type issue instead.
- Never use `@ts-ignore` or `@ts-expect-error` without a comment explaining why.
- Never use `!` (non-null assertion) without verifying the value cannot be null in context.

## Security

- Never use `innerHTML` with user input. Use `textContent` or a sanitizer like DOMPurify.
- Never use `eval()`, `new Function()`, or `setTimeout(string)`.
- Never concatenate user input into SQL strings. Use parameterized queries or an ORM.
- Never hardcode secrets or API keys. Use environment variables.

## Error Handling

- Never use empty `catch {}` blocks. At minimum, log the error.
- Never use `console.log` for production error handling. Use a proper logger.
- Always handle Promise rejections. Never leave `.catch()` empty or missing.

## React (if applicable)

- Never use array index as React `key` for lists that can be reordered or filtered.
- Never mutate state directly. Use setter functions or immutable patterns.
- Never put side effects in render. Use `useEffect` with proper dependency arrays.
