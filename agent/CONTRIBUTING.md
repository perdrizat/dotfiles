# Global Instructions

These instructions apply to all LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) across all projects.

## Patterns & Conventions

- **Always use red/green TDD**: Write failing tests first, then implement the code to make them pass. Never write production code without a corresponding test written beforehand.

## Workflow

- **Always update CHANGELOG.md**: Before returning to the user after completing work, update (or create) `CHANGELOG.md` in the project root following [Keep a Changelog](https://keepachangelog.com/) format. Add entries under the `[Unreleased]` section using the appropriate category: Added, Changed, Deprecated, Removed, Fixed, Security. **Keep entries to one line each** — concise like git commit messages, not paragraphs.

## Compressing CHANGELOG.md

When `CHANGELOG.md` grows long, compress it to keep the context window focused on what matters. Apply these rules:

- **Keep**: today's `[Unreleased]` entries, open questions, key architectural decisions, active experiments, and anything not recoverable from git history or the current code.
- **Delete**: completed work from yesterday and earlier that is recoverable from `git log` or visible in the code itself. This includes routine additions, renames, bug fixes, and refactors whose outcomes are already reflected in the codebase.
- **Condense**: if older entries contain decisions, trade-offs, or context that would be lost, summarize them into a brief `## Archive` section at the bottom (one line per item, linking to the relevant commit or date if useful).

The goal is a changelog that helps the *next session* pick up where this one left off — not a complete history (that's what git is for).

## Preparing to commit

When asked to prepare a commit, run pre-commit checks, or help get code ready to commit, follow the steps below. **Never run `git add` or `git commit` — the user commits manually.**

1. **Run `pre_commit_check.sh`** — This utility lives in the user's `$PATH` (not inside the project). Run it with `pre_commit_check.sh` directly — do **not** check for it with `ls` or look for it inside the project directory. It performs the safety scan (secrets, debug remnants), documentation freshness check (CHANGELOG.md, CONTRIBUTING.md, README.md), and lists all changed files. Review its output and act on any warnings before proceeding.
2. **Build, lint, test** — If the project has a build step, linter, or test suite, run them. Adapt to whatever tooling the project uses (`npm`, `cargo`, `pytest`, `go`, etc.). Report failures; do not proceed until they pass.
3. **Promote changelog entries** — Move completed entries from `[Unreleased]` to a new `[YYYY-MM-DD]` section (today's date). Leave any in-progress or unfinished items under `[Unreleased]`.
4. **Commit message** — Based on the diff, suggest a short (under 72 chars) conventional commit message. If changes span multiple concerns, suggest splitting and provide a message for each.
5. **Copy-paste commands** — Print the exact git commands the user can paste into the terminal. Use `git add` for new/modified files, `git mv` for renames, `git rm` for deletions, `git restore --staged` for files that should be excluded. End with `git commit -a -m "suggested commit message" && git push`. Format as a single fenced code block.
