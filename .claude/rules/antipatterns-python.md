# Python Anti-patterns

These are project-specific patterns to avoid. Claude already knows general Python best practices - this file covers patterns that are commonly missed or project-specific.

## SQL & Data

- Never use f-strings or string concatenation for SQL queries. Always use parameterized queries (`?` or `%s` placeholders).
- Never use `pickle.loads()` on untrusted data. Use `json` or `msgpack` instead.
- Never use `yaml.load()` without `Loader=yaml.SafeLoader`.

## Security

- Never hardcode secrets, API keys, or passwords. Use `os.environ.get()` or a secrets manager.
- Never use `eval()` or `exec()` on user input.
- Never use `subprocess.shell=True` with user-provided arguments.
- Never use `random` module for security purposes. Use `secrets` module instead.

## Error Handling

- Never use bare `except:` or `except Exception:` without logging. At minimum, log the error.
- Never silently swallow exceptions with `pass` in except blocks unless explicitly justified.
- Use context managers (`with`) for all file and DB connection handling.

## Async

- Never use `time.sleep()` in async code. Use `asyncio.sleep()` instead.
- Never call blocking I/O functions directly in async handlers without `run_in_executor()`.
