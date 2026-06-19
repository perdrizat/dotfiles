# Global Instructions

These instructions apply to all LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) across all projects.

## Precedence

Where a project's own instruction file (`CONTRIBUTING.md`, or its agent specific files `CLAUDE.md` / `AGENTS.md`) explicitly overrides a rule below, follow the project file for that repo. These global rules are the default wherever a project is silent.

## Patterns & Conventions

- **Always use red/green TDD**: Write failing tests first, then implement the code to make them pass. Never write production code without a corresponding test written beforehand.
- **No Emojis**: Do not use emojis in your text output unless explicitly requested by the user. If you need to indicate status, use unobtrusive textual symbols like `✓` (OK), `~` (WARN), and `x` (FAIL) to safe space. Colors are OK.

## Tool & Security Preferences

- **Node Ecosystem**: Always use `fnm` for Node version management and `pnpm` for package management.
- **Dependency Security**: When using `pnpm`, restrict installation to packages that are at least 7 days old.
- **Auditing**: Always run GitHub CI to audit the dependencies.

## Running commands (efficiency & safety)

Goal: do not generate needless permission prompts. The permission system can only auto-approve a **single, clean** command — the moment a command contains a shell operator (`>`, `>>`, `2>&1`, `|`, `&&`, `||`, `;`, `$(…)`, backticks) it falls back to asking, *even when the underlying command is safe*. So:

- **Run dev commands bare.** Build, lint, typecheck, and test commands (e.g. `pnpm build`, `pnpm lint`, `pnpm typecheck`, `pnpm test:fast`, `pnpm test:e2e`, `pnpm test:uat`, and equivalents in other ecosystems) should always be runnable without approval — run them exactly as the one command, with no redirection or chaining.
- **Never redirect or chain to capture output.** Don't write `cmd > file 2>&1`, `cmd; echo $?`, or `cmd && other`. To capture long output, run the command with the Bash tool's **background mode** — the harness writes the *complete* output to a file and reports the exit code on completion — then read that file with the **Read tool**. For short commands, the inline result already shows pass/fail.
- **Parallelize instead of chaining.** When you need several independent commands (e.g. probing a few `git diff` ranges), issue them as separate Bash tool calls in a single message — they run concurrently and each auto-approves on its own. Don't join them with `;` to save round-trips; that one operator forces a prompt for the whole line. Skip `echo ---` separators and `2>/dev/null` too — each call returns its output and exit code distinctly, and a failing command surfaces a readable error.
- **Quote refs containing `{}`.** Unquoted braces look like shell brace expansion and get flagged as unsafe, so write `git diff "@{upstream}...HEAD"` (quoted), not `git diff @{upstream}...HEAD`.
- **Inspect with the Read / Grep / Glob tools, never shell text utilities.** Do not use `cat`, `sed`, `awk`, `head`, `tail`, `wc`, or `grep` through Bash to read or scan files — each is a separate command that prompts, and `sed`/`awk` are flagged as unsafe. Test and log outputs are small: Read them in full. Use the Grep/Glob tools to search code.
- **Leave genuinely risky commands manual.** Mutating, installing, or networked commands (`git` writes, `rm`, `pnpm install`, launching a dev server) should still prompt — that is the security boundary worth keeping.

This pairs with an allow-list of the safe dev commands in settings (`~/.claude/settings.json` for cross-project effect). The verbal rules above are what keep the agent *using* those commands in an auto-approvable, bare form rather than re-wrapping them.

## Workflow

- **Always update CHANGELOG.md**: Before returning to the user after completing work, update (or create) `CHANGELOG.md` in the project root following [Keep a Changelog](https://keepachangelog.com/) format. Add entries under the `[Unreleased]` section using the appropriate category: Added, Changed, Deprecated, Removed, Fixed, Security. **Keep entries to one line each** — concise like git commit messages, not paragraphs.
- **One section per date**: each `## [YYYY-MM-DD]` heading must appear at most once. When promoting `[Unreleased]`, merge into that date's existing section if present, folding entries into the right type group (Added/Changed/…) — never append a second header for a date that already exists.
- **Record the net delta, not the journey**: each commit's entries state the net change versus the previous commit — never the steps taken to get there. Don't narrate intermediate edits, reversals, or changelog-about-changelog housekeeping. If something added to `[Unreleased]` is later backed out or superseded before you commit, delete or rewrite that entry so only the net effect lands.

## Compressing CHANGELOG.md

When `CHANGELOG.md` grows long, compress it to keep the context window focused on what matters. Apply these rules:

- **Keep**: today's `[Unreleased]` entries, open questions, key architectural decisions, active experiments, and anything not recoverable from git history or the current code.
- **Delete**: completed work from yesterday and earlier that is recoverable from `git log` or visible in the code itself. This includes routine additions, renames, bug fixes, and refactors whose outcomes are already reflected in the codebase.
- **Condense**: if older entries contain decisions, trade-offs, or context that would be lost, summarize them into a brief `## Archive` section at the bottom (one line per item, linking to the relevant commit or date if useful).

The goal is a changelog that helps the *next session* pick up where this one left off — not a complete history (that's what git is for).

## Preparing to commit

When asked to prepare a commit, run pre-commit checks, or help get code ready to commit, follow the steps below. **Never run `git add` or `git commit` — the user commits manually.**

1. **Run `pre_commit_check.sh`** — This utility lives in the user's `$PATH` (not inside the project). Run it with `pre_commit_check.sh` directly — do **not** check for it with `ls` or look for it inside the project directory. It performs the safety scan (secrets, debug remnants), documentation freshness check (CHANGELOG.md, CONTRIBUTING.md, README.md), and lists all changed files. Review its output and act on any warnings before proceeding.
2. **Build, lint, test, audit** — If the project has a build step, linter, or test suite, run them. For Node projects, always include `pnpm audit`. Adapt to whatever tooling the project uses (`npm`, `cargo`, `pytest`, `go`, etc.). Report failures; do not proceed until they pass.
3. **Promote changelog entries** — Move completed entries from `[Unreleased]` into today's `[YYYY-MM-DD]` section — create it if absent, otherwise merge into the existing one by type (never add a second header for the same date). Leave any in-progress or unfinished items under `[Unreleased]`.
4. **Commit message** — Squashed commits are preferred. Based on the diff, suggest a single short (under 72 chars) conventional commit message. Keep it extremely brief and to the point. If changes span multiple distinct concerns, you may propose splitting, but your suggestion must default to a single squashed commit.
5. **Copy-paste commands** — Print the exact git commands the user can paste into the terminal. Use `git add` for new/modified files, `git mv` for renames, `git rm` for deletions, `git restore --staged` for files that should be excluded. End with `git commit -a -m "suggested commit message" && git push`. Format as a single fenced code block.
