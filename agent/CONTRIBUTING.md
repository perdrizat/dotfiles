# Global Instructions

These instructions apply to all LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) across all projects.

## Precedence

Where a project's own instruction file (`CONTRIBUTING.md`, or its agent specific files `CLAUDE.md` / `AGENTS.md` / `GEMINI.md`) explicitly overrides a rule below, follow the project file for that repo. These global rules are the default wherever a project is silent.

## Patterns & Conventions

- **Always use red/green TDD**: Write failing tests first, then implement the code to make them pass. Never write production code without a corresponding test written beforehand.

## Running commands (efficiency & safety)

Goal: do not generate needless permission prompts. The permission system can only auto-approve a **single, clean** command — the moment a command contains a shell operator (`>`, `>>`, `2>&1`, `|`, `&&`, `||`, `;`, `$(…)`, backticks) it falls back to asking, *even when the underlying command is safe*. So:

- **Run dev commands bare.** Build, lint, typecheck, and test commands (e.g. `pnpm build`, `pnpm lint`, `pnpm typecheck`, `pnpm test:fast`, `pnpm test:e2e`, `pnpm test:uat`, and equivalents in other ecosystems) should always be runnable without approval — run them exactly as the one command, with no redirection or chaining.
- **Never redirect or chain to capture output.** Don't write `cmd > file 2>&1`, `cmd; echo $?`, or `cmd && other`. To capture long output, run the command with the Bash tool's **background mode** — the harness writes the *complete* output to a file and reports the exit code on completion — then read that file with the **Read tool**. For short commands, the inline result already shows pass/fail.
- **Inspect with the Read / Grep / Glob tools, never shell text utilities.** Do not use `cat`, `sed`, `awk`, `head`, `tail`, `wc`, or `grep` through Bash to read or scan files — each is a separate command that prompts, and `sed`/`awk` are flagged as unsafe. Test and log outputs are small: Read them in full. Use the Grep/Glob tools to search code.
- **Leave genuinely risky commands manual.** Mutating, installing, or networked commands (`git` writes, `rm`, `pnpm install`, launching a dev server) should still prompt — that is the security boundary worth keeping.

This pairs with an allow-list of the safe dev commands in settings (`~/.claude/settings.json` for cross-project effect). The verbal rules above are what keep the agent *using* those commands in an auto-approvable, bare form rather than re-wrapping them.

## Workflow

- **Always update CHANGELOG.md**: Before returning to the user after completing work, update (or create) `CHANGELOG.md` in the project root following [Keep a Changelog](https://keepachangelog.com/) format. Add entries under the `[Unreleased]` section using the appropriate category: Added, Changed, Deprecated, Removed, Fixed, Security. **Keep entries to one line each** — concise like git commit messages, not paragraphs.
- **One section per date**: each `## [YYYY-MM-DD]` heading must appear at most once. When promoting `[Unreleased]`, merge into that date's existing section if present, folding entries into the right type group (Added/Changed/…) — never append a second header for a date that already exists.

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
3. **Promote changelog entries** — Move completed entries from `[Unreleased]` into today's `[YYYY-MM-DD]` section — create it if absent, otherwise merge into the existing one by type (never add a second header for the same date). Leave any in-progress or unfinished items under `[Unreleased]`.
4. **Commit message** — Based on the diff, suggest a short (under 72 chars) conventional commit message. If changes span multiple concerns, suggest splitting and provide a message for each.
5. **Copy-paste commands** — Print the exact git commands the user can paste into the terminal. Use `git add` for new/modified files, `git mv` for renames, `git rm` for deletions, `git restore --staged` for files that should be excluded. End with `git commit -a -m "suggested commit message" && git push`. Format as a single fenced code block.
