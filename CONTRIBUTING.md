# Dotfiles

Personal dotfiles managed with GNU Stow. Deployed via `setup.sh`, validated via `validate_setup.sh`.

## Conventions for this repo

These intentionally override the [global agent instructions](agents/AGENTS.md) for this repo (see the **Precedence** rule there):

- **No Red-Green TDD** — implement directly; do not write a failing test first.
- **No new test scripts** — do not author `test_*.sh` (or equivalent) for changes here.
- **Link-safe file updates** — in a stow-managed home, files may be symlinks or have hardlinks. When rewriting a file's content, never replace its inode: no `mv tmp-file target` and no `sed -i` (both rename a temp file over the target, detaching hardlinks and clobbering a symlinked target into a regular file). Compute the new content in memory and write it back with a plain redirect (`> target`), which writes *through* links. Exceptions: true relocations between directories, and atomic publishes of never-linked files with concurrent readers (e.g. the `agy_status.sh` cache) — there `tmp+mv` is deliberate.
- **Local Tools** — all tools in `bin/bin` are in the local `$PATH`. When invoking them, call them directly by name (e.g., `validate_setup.sh` instead of `./bin/bin/validate_setup.sh`).

All other global rules (e.g. updating `CHANGELOG.md`, the commit-prep workflow) still apply. The repo carries no `test_*.sh` scripts.

## Structure

Each top-level directory is a stow package. Running `stow --adopt <package>` from `~/dotfiles` symlinks its contents into `$HOME`.

| Package  | Contents                            |
|----------|-------------------------------------|
| `bash`   | `.bash_aliases`, `.bash_extra`      |
| `bin`    | `~/bin/` scripts (status, validate, init) |
| `claude` | `~/.claude/settings.json`           |
| `gemini` | `~/.gemini/config/skills` + `skills.inactive` (Antigravity `agy` skills). Also carries the `agy` settings **template** (`antigravity-cli/settings.json`) — excluded from stow via `.stow-local-ignore`; `setup.sh` deploys/merges it as a local copy, never a symlink |
| `git`    | `.gitconfig`                        |
| `ssh`    | `.ssh/config`, `.ssh/id_ed25519.age` |

This directory is **not** a stow package — its symlinks are created manually in `setup.sh`:

| Directory  | Purpose                             |
|------------|-------------------------------------|
| `agents/`  | Global LLM instructions (`AGENTS.md`), symlinked into each agent's config dir |

## LLM agent instructions

All LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) share a single source of truth for instructions at both levels:

**Global** — `agents/AGENTS.md` is symlinked by `setup.sh` to:
- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.codex/AGENTS.md` (OpenAI Codex)
- `~/.gemini/GEMINI.md` (Google Antigravity `agy` — global config file)

**Per-project** — `CONTRIBUTING.md` in the project root is the primary file. Agent-specific symlinks point to it:
- `CLAUDE.md` → `CONTRIBUTING.md` (Claude Code)
- `AGENTS.md` → `CONTRIBUTING.md` (OpenAI Codex, Google Antigravity)

These symlinks are gitignored — only `CONTRIBUTING.md` is committed.

`init_project.sh` bootstraps both files (plus `CHANGELOG.md`) in new projects.

## Setup

```bash
# Fresh machine
curl -sL https://raw.githubusercontent.com/perdrizat/dotfiles/main/setup.sh | bash

# Or from a clone
cd ~/dotfiles && bash setup.sh
```

## Validation

```bash
validate_setup.sh
```

Reports green/yellow/red per item and prints fix commands in dependency order. Most findings consolidate into a single fix — re-running the idempotent `setup.sh`; targeted commands are printed only for what it can't do (repo clone/sync, YubiKey relay, Claude settings deploy).

## Adding a new stow package

1. Create `~/dotfiles/<package>/` mirroring the target path under `$HOME`
2. Both `setup.sh` and `validate_setup.sh` auto-discover stow packages — no manual edits needed

## Key files

- `setup.sh` — **Must be self-contained** (curl-piped on fresh machines before the repo exists). Shared variables (`PREREQS`, `APT_PACKAGES`, `STOW_SKIP`) are defined here and sourced by `validate_setup.sh` via a guard (`[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0`)
- `agents/AGENTS.md` — Single source of truth for global LLM agent instructions
- `bin/bin/validate_setup.sh` — Health check for the entire setup
- `bin/bin/init_project.sh` — Bootstrap CONTRIBUTING.md + CLAUDE.md symlink + CHANGELOG.md in a new project
- `bin/bin/validate_project.sh` — Checks agent file setup in any project (symlinks, .gitignore)
- `bin/bin/pre_commit_check.sh` — Safety scan, doc freshness, changed files (used by prepare-to-commit workflow)
- `bin/bin/check_changelog.sh` — Stop hook: warns when files changed but CHANGELOG.md wasn't updated
- `bash/.bash_extra` — PATH, editor, prompt, WSL config
- `bash/.bash_aliases` — Shell aliases
