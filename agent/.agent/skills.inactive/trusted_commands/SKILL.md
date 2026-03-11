---
name: Trusted Commands (Auto-Run)
description: Lists commands that the agent is explicitly authorized to run automatically without asking for user confirmation.
---
# Trusted Commands
The user has explicitly authorized you to execute the following commands automatically, without pausing to ask for user confirmation. 
Whenever you use your command execution tool (e.g., `run_command`) to run any of the commands listed below, you **MUST** set your internal `SafeToAutoRun` flag to `true` so that the execution happens seamlessly.
## Authorized Commands
*   `npm run test`
*   `npm test`
*(Note for the user: You can add more non-destructive commands to this list, such as `npm run lint` or `cargo test`, to allow the agent to run them autonomously anytime!)*