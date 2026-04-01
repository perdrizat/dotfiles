---
name: Safe Test Runner
description: Prevents test suite commands from hanging by enforcing timeouts, background execution, and strategies for slow integration tests.
---

# Safe Test Runner

Test suites that make real HTTP calls (e.g., integration tests hitting `localhost`) can hang indefinitely, blocking all further work. You **MUST** follow these rules whenever running tests.

## 1. Always Wrap the ENTIRE Pipeline with `timeout`

**CRITICAL:** `timeout` only kills the command directly after it, NOT any piped commands. If you write `timeout 30 npx vitest run 2>&1 | tail -10`, the `timeout` only wraps `npx vitest`, but `tail` runs as a separate, un-timed process. If vitest spawns child processes that keep stdout open, `tail` will hang forever waiting for EOF.

**Always wrap the full pipeline using `bash -c`:**

```bash
timeout 30 bash -c 'npx vitest run 2>&1 | tail -20'
timeout 30 bash -c 'npm run test --prefix server 2>&1 | tail -20'
timeout 30 bash -c 'npm run test --prefix client 2>&1 | tail -20'
```

**NEVER do this:**
```bash
# WRONG - timeout does not cover `tail`, which can hang forever
timeout 30 npm run test 2>&1 | tail -20
```

## 2. Always Run as Background Commands

Set `WaitMsBeforeAsync` to `500` so the command instantly goes to background. Then poll with `command_status` using `WaitDurationSeconds: 30`.

This way, if a test hangs, you regain control after 30 seconds and can terminate the process instead of being stuck.

## 3. Separate Fast Tests from Slow Integration Tests

This project has a known slow integration test: `SetupPage.test.jsx` (makes real HTTP calls to `localhost:3001`).

**Strategy — always run in two phases:**

**Phase 1: Fast tests (< 5s)**
```bash
timeout 30 bash -c 'npx vitest run --exclude "**/SetupPage.test.jsx" 2>&1 | tail -20'
```

**Phase 2: Integration tests (background, with timeout)**
```bash
timeout 60 bash -c 'npx vitest run src/pages/SetupPage.test.jsx 2>&1 | tail -30'
```

Run Phase 2 as a background command. If it doesn't complete within the timeout, terminate it and report the issue to the user rather than blocking indefinitely.

## 4. Pipe Output Through `tail`

Always pipe test output through `| tail -N` (typically `tail -20` or `tail -30`) to avoid overwhelming output. The summary lines at the end of vitest output contain the pass/fail counts which is all you need.

## 5. If a Test Hangs

If `command_status` shows `RUNNING` after two consecutive 30-second polls:
1. **Terminate** the command immediately using `send_command_input` with `Terminate: true`.
2. **Do not retry** the same command synchronously.
3. **Report** to the user that the test suite appears to hang and suggest investigating the specific test file.
