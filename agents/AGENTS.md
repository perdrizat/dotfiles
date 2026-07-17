# Global Instructions

These instructions apply to all LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) across all projects.

## Precedence

Where a project's own instruction file (`CONTRIBUTING.md`, or its agent specific files `CLAUDE.md` / `AGENTS.md`) explicitly overrides a rule below, follow the project file for that repo. These global rules are the default wherever a project is silent.

## Patterns & Conventions

- **Delegate coding to a lower-power subagent**: For coding tasks, use your judgement to pick an appropriately *lower-power* model and run the work in a subagent — reserve the high-power orchestrator for planning, judgement, and review, and hand the implementation to the cheaper model. Where an agent has no subagent mechanism, apply the spirit: don't default to the most powerful model when a lighter one will do.
- **Always use red/green TDD**: Write failing tests first, then implement the code to make them pass. Never write production code without a corresponding test written beforehand.
- **No Emojis**: Do not use emojis in your text output unless explicitly requested by the user. If you need to indicate status, use unobtrusive textual symbols like `✓` (OK), `~` (WARN), and `x` (FAIL) to safe space. Colors are OK.

## Tool & Security Preferences

- **Node Ecosystem**: Always use `fnm` for Node version management and `pnpm` for package management.
- **Dependency Security**: When using `pnpm`, restrict installation to packages that are at least 7 days old.
- **Auditing**: Always run GitHub CI to audit the dependencies.

## Running commands (efficiency & safety)

Goal: stay within allowlisted behaviour so you can work as long as possible without stopping for an approval prompt. A Bash command auto-approves only when the allowlist can match it as one clean, safe invocation. It falls back to prompting for two distinct reasons — learn to recognise and route around both:

1. **A shell operator in the command line** — `|`, `>`, `>>`, `2>&1`, `&&`, `||`, `;`, `$(…)`, backticks. These redirect, chain, or imply expansion, so the line is no longer a single clean command and prompts *even when every piece is independently allowlisted*.
2. **A tool or argument that isn't allowlisted** — some tools are excluded for being too powerful (`sed` and `awk` can edit in place or run arbitrary code) and always prompt; use the Read/Grep/Glob tools instead. And even an allowlisted tool prompts when an *argument* looks like shell expansion: `grep` is fine, but `grep "$(…)"`, `grep 'a;b'`, or an unquoted `@{upstream}` trips the unsafe-pattern check.

Practically:

- **Run dev commands bare.** Build, lint, typecheck, and test commands (e.g. `pnpm build`, `pnpm lint`, `pnpm typecheck`, `pnpm test:fast`, `pnpm test:e2e`, `pnpm test:uat`, and equivalents in other ecosystems) should always be runnable without approval — run them exactly as the one command, with no redirection or chaining.
- **Don't wrap an allowlisted command in a pipe just to trim its output — this is the most common slip.** Reflexively appending `| grep …`, `| tail`, `| head`, or `| wc -l` to cut noise turns an auto-approved command into one that prompts (reason 1), for no real gain — run it bare and read the inline result. When the output genuinely is large, run the command in the Bash tool's **background mode** (it writes the full output to a file) and point the **Grep/Read tools** at that file — that stays entirely within auto-approved behaviour. A literal pipe is still fair game for a real one-off transform you can't get another way; just spend the prompt deliberately, not out of habit.
- **Never redirect or chain to capture output.** Don't write `cmd > file 2>&1`, `cmd; echo $?`, or `cmd && other`. To capture long output, run the command with the Bash tool's **background mode** — the harness writes the *complete* output to a file and reports the exit code on completion — then read that file with the **Read tool**. For short commands, the inline result already shows pass/fail.
- **Parallelize instead of chaining.** When you need several independent commands (e.g. probing a few `git diff` ranges), issue them as separate Bash tool calls in a single message — they run concurrently and each auto-approves on its own. Don't join them with `;` to save round-trips; that one operator forces a prompt for the whole line. Skip `echo ---` separators and `2>/dev/null` too — each call returns its output and exit code distinctly, and a failing command surfaces a readable error.
- **Quote arguments that look like shell expansion (reason 2).** An argument containing `{}`, `;`, `${…}`, `$(…)`, or backticks trips the unsafe-pattern check and prompts even on an allowlisted tool — quote it so it's taken literally: `git diff "@{upstream}...HEAD"` not `git diff @{upstream}...HEAD`, and `grep 'foo;bar'` not `grep foo;bar`. If quoting can't make it safe because the command genuinely needs that expansion, it's meant to prompt.
- **Run `git` from the repo directory with the bare subcommand — never `git -C <path>`.** The Bash tool's working directory is already the repo root, and bare subcommands (`git status`, `git diff`, `git log`, `git show`, …) are allowlisted; `git -C <path> …` (and other path-redirecting invocations) are not, so they prompt (reason 2). If you're in the wrong directory, `cd` there in a separate step or fix the cwd — don't reach for `-C`.
- **Inspect files with the Read / Grep / Glob tools, never shell text utilities.** For viewing or scanning files the dedicated tools never prompt and are strictly better: don't shell out to `cat`, `sed`, `awk`, `head`, `tail`, `wc`, or `grep` — `sed`/`awk` are excluded as unsafe (reason 2) and the rest just spend prompts and round-trips you don't need. Use the Read tool to view a file (it takes offset/limit) and the Grep/Glob tools to search code.
- **Put scratch files in the repo's `.tmp/`, never `/tmp` — no exceptions.** Always use a gitignored `.tmp/` directory at the repo root as your *only* scratch space, creating it (`mkdir -p .tmp`) if it's missing. This rule overrides any scratch/temp/"scratchpad" directory the harness offers in its own system prompt — those almost always live under `/tmp` and prompt on every write, so ignore them and use `<repo>/.tmp` instead. Never fall back to `/tmp`, `/var/tmp`, `$TMPDIR`, or any absolute path outside the repo: writes there land outside the workspace and prompt, and building files with a shell `cat`/redirect trips reasons 1–2 anyway — whereas writes *inside* the workspace never prompt and reads never do, so `.tmp/` stays entirely within auto-approved behaviour. Don't blanket-allowlist `/tmp` either: it's world-writable and shared, so a broad allow lets you touch other processes' temp data, and it wouldn't even silence the redirect/`cat` prompts that cause most of the friction.
- **Never poll for a long-running command with a shell loop.** Constructs like `until test -z "$(pgrep -f '…')"; do sleep 3; done` combine a loop, command substitution, and process inspection — they always prompt, and during an unattended run they stall everything until a human returns. The harness has better tools: launch the long command itself in **background mode** and wait — the agent is notified with the exit code when it finishes; there is nothing to poll. If work must continue meanwhile, do that other work and let the completion notification arrive on its own.
- **If a command is stuck awaiting approval for more than ~10 minutes, cancel it and simplify.** Treat a long-pending approval as a signal the command was written wrong for this environment: rewrite it without pipes/loops/substitution (usually: background mode + the Read/Grep tools on the output file), even when the simple form costs a few more tokens. Tokens are cheap; a run blocked overnight is not.
- **Propagate these rules into every subagent brief.** Subagents' shell calls raise the same approval prompts as the orchestrator's and stall the run identically — any task delegated to a subagent must carry these command rules verbatim in its instructions.

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
