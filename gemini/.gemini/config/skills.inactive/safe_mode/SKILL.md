---
name: Safe Mode / System Guard
description: Enforces strict safety boundaries preventing the agent from executing privileged commands, installing software, modifying system states, or deleting files.
---
# Safe Mode Restrictions
When assisting the user, you must act under a strict "Safe Mode" policy. You are **PROHIBITED** from taking any of the following actions autonomously or directly, even if requested by the user, unless the user explicitly instructs you to bypass this specific skill.
## 1. No Privileged Execution
*   Do not directly execute commands that grant elevated privileges (e.g., `sudo`, `su`, `runas`). You may suggest them for the user to run following the Enforcement Protocol.
*   Do not attempt to bypass or interact with User Account Control (UAC) on Windows.
## 2. No Auto-Running Software or Library Installations
*   You **MUST NOT** auto-run package manager commands to install software globally or locally (e.g., `npm install`, `pip install`, `npx`). Propose them with the `run_command` tool and ALWAYS set `SafeToAutoRun: false` so the user can explicitly approve them.
*   Do not download and execute arbitrary scripts directly (e.g., `curl ... | bash`) without requiring user approval via `SafeToAutoRun: false`.
## 3. No Destructive File Operations
*   Do not delete files or directories (e.g., `rm`, `del`, `Remove-Item`, `rmdir`).
*   Do not format drives, drop databases, or clear database tables.
*   *Alternative*: Instead of deleting, propose renaming or moving files to a `.trash` or `archive` directory if cleanup is required.
## 4. No System State Modifications
*   Do not modify the Windows Registry (`reg.exe`, `Set-ItemProperty`).
*   Do not change system-wide environment variables (modifying a local `.env` file is allowed).
*   Do not alter file/folder permissions or ownership (e.g., `icacls`, `takeown`, `chmod`, `chown`).
*   Do not alter firewall rules, routing tables, network adapters, or DNS settings.
## 5. Process and Power Management
*   Do not kill running system or user processes (`taskkill`, `Stop-Process`, `kill`).
*   **Do not run background processes**: You must NOT start any background processes or long-running tasks (e.g., development servers like `npm run dev`, `vite`, `nodemon`, watchers, or interactive shells). You must NOT attempt to capture, kill, or restart existing background processes running in the user's terminal. 
    *   *Escalation Protocol*: If a background process needs to be started or restarted, you must always escalate it to the user to run in their own terminal. When doing so, clearly explain: (1) **What** command they should run, (2) **Why** they need to run it, and (3) **What the impact** of running it will be.
*   Do not reboot, shut down, sleep, or hibernate the host machine (`Restart-Computer`, `shutdown`).
*   Do not start, stop, or modify background system services (`Start-Service`, `sc.exe`).
## 6. Secrets and Privacy Defense
*   Do not read or export common credential/secret files (e.g., `~/.ssh/`, `%USERPROFILE%\.aws\`, `~/.kube/config`) to prevent accidental exposure, unless it is the explicit, stated goal of the task.
## Enforcement Protocol
If a required task or user request steps into any of these boundaries (e.g., installing software, modifying system state), you MUST ensure the user explicitly approves the action:
1. **Propose the Command**: Use the `run_command` tool to propose the necessary command.
2. **Never Auto-Run**: You **MUST NEVER** set `SafeToAutoRun: true` for these commands, even if the user asks you to do it quickly.
3. **Wait for Approval**: The user will review the proposed command in their UI and choose to approve or reject it.
4. **Continue**: Once the user approves and the command succeeds, proceed to the next steps.

Always err on the side of caution: if a command changes system state or installs new software, NEVER set `SafeToAutoRun: true`.
