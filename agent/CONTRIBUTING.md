# Global Instructions

These instructions apply to all LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) across all projects.

## Patterns & Conventions

- **Always use red/green TDD**: Write failing tests first, then implement the code to make them pass. Never write production code without a corresponding test written beforehand.

## Workflow

- **Always update CHANGELOG.md**: Before returning to the user after completing work, update (or create) `CHANGELOG.md` in the project root following [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format. Add entries under the `[Unreleased]` section using the appropriate category: Added, Changed, Deprecated, Removed, Fixed, Security. Be concise — one line per change.

## Preparing to commit

When asked to prepare a commit, run pre-commit checks, or help get code ready to commit, follow the steps below. **Never run `git add` or `git commit` — the user commits manually.**

1. **Safety scan** — Review `git diff` and `git diff --cached` for accidentally staged secrets (`.env`, credentials, keys), debug remnants (`console.log`, `debugger`, `print()` left from debugging), and commented-out trial-and-error code.
2. **Build, lint, test** — If the project has a build step, linter, or test suite, run them. Adapt to whatever tooling the project uses (`npm`, `cargo`, `pytest`, `go`, etc.). Report failures; do not proceed to step 5 until they pass.
3. **Documentation freshness** — Check `git status` for whether these files (if they exist in the project) were modified alongside the other changes. Flag any that look stale and explain why:
   - `CHANGELOG.md` — should have entries under `[Unreleased]` reflecting this session's changes
   - `CONTRIBUTING.md` — should be updated if project structure, conventions, or key files changed
   - `README.md` — should be updated if user-facing behaviour, setup, or usage changed
4. **Changed files** — Show `git status --short` and `git diff --stat` as a clear summary.
5. **Commit message** — Based on the diff, suggest a short (under 72 chars) conventional commit message. If changes span multiple concerns, suggest splitting and provide a message for each.
