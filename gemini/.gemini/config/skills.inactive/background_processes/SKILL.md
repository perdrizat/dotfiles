---
name: Background Processes & Long-Running Commands
description: Teaches the agent how to safely execute, monitor, and clean up continuous terminal processes like development servers without hanging.
---

# Handling Long-Running Commands

When you need to execute a continuous, long-running process (e.g., development servers like `npm run dev`, `vite`, `nodemon`, or interactive shells), you **MUST NOT** run them synchronously. Doing so will cause you to hang indefinitely while waiting for an exit code that will never arrive.

To adhere to secure and robust agentic practices, you must utilize the asynchronous capabilities of your execution tools to push these processes into the background.

## 1. Starting the Process
When using your terminal execution tool (e.g., `run_command`), you must configure it to push the process into the background after it successfully initializes.
*   Set the `WaitMsBeforeAsync` parameter to a reasonable startup time (e.g., `2000` to `5000` milliseconds).
*   This wait time allows you to synchronously catch any immediate crashes or syntax errors during the server's startup phase.
*   If the process stays alive past this duration, the tool will return control to you and provide a unique `CommandId`. You are now unblocked.

## 2. Monitoring the Process
Once the process is running in the background, you can continue your tasks (like running automated tests or pinging the local server) concurrently.
*   If you need to read the server's live output, stdout, or crash logs, use the `command_status` tool and provide the background `CommandId`.

## 3. Mandatory Cleanup (Termination)
Leaving orphaned dev servers running in the background consumes system resources and blocks critical network ports (e.g., keeping port `3000` or `5173` bound permanently). This will cause subsequent tasks to silently fail due to "Port already in use" errors.
*   Once you have finished interacting with the server or completed your tests, you **MUST** gracefully kill it.
*   Use the `send_command_input` tool, provide the `CommandId`, and explicitly set the `Terminate` parameter to `true`.
*   **Never leave a long-running process alive at the end of your task unless explicitly requested by the user.**

## Example Scenario: Testing a React App
1.  You need to verify a UI change in a React app.
2.  Execute `npm run dev` with `WaitMsBeforeAsync: 3000`. 
3.  After 3 seconds, control returns to you. The tool output gives you `CommandId: 12345`.
4.  Run your verification (e.g., reading a DOM snapshot, fetching an endpoint).
5.  Call `send_command_input` with `CommandId: 12345` and `Terminate: true`.
6.  Proceed to your next task knowing the port has been cleanly freed.
