---
description: Performs rigorous quality, safety, and operational checks before code is committed. Triggers automatically when asked to "run pre-commit" or if the code is ready to commit.
---
# Pre-commit Checklist
Welcome to the pre-commit checklist. Please review the steps below and follow them precisely to ensure the codebase is clean, tested, and secure before we commit.
## 1. Safety & Secrets Check
First, scan the unstaged and staged changes (`git diff` and `git diff --cached`) to ensure no accidents occurred.
*   **Secrets File Check**: Verify that no files containing secrets (e.g., `.env`, credentials) are being accidentally tracked by Git.
*   **Debug Remnants Check**: Scan the diff for accidentally left-in debugging statements (e.g., `console.log`, `print()`, `debugger`, commented out chunks of trial-and-error code).
## 2. Compilation and Build Check
Never commit code that immediately breaks the build. If there is a build step, run it now.
// turbo
```bash
npm run build 
```
*(If the project uses a different build command like `cargo build` or `go build`, adapt accordingly.)*
## 3. Formatting and Linting
Check if the project has established rules and run them.
// turbo
```bash
npm run lint 
```
*(If the project uses a different linter/formatter, adapt accordingly.)*
## 4. Test Suite Verification
Code is not ready until tests pass.
// turbo
```bash
npm test
```
*(If the project uses a different runner like `pytest` or `go test`, adapt accordingly.)*
## 5. Diff Review & Commit Suggestion
Once all mechanical checks pass, provide a final review value-add.
*   **Review `git status`**: Show the user clearly what files are currently staged, unstaged, and untracked.
// turbo
```bash
git status
```
*   **Generate Commit Message**: Based on analyzing `git diff`, propose a concise, standard-compliant commit message (e.g., Conventional Commits) for the user to use. Give the user the exact command to run to commit.

