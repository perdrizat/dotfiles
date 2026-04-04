# Dotfiles

Personal dotfiles managed with GNU Stow. Deployed via `setup.sh`, validated via `validate_setup.sh`.

## Structure

Each top-level directory is a stow package. Running `stow --adopt <package>` from `~/dotfiles` symlinks its contents into `$HOME`.

| Package  | Contents                            |
|----------|-------------------------------------|
| `bash`   | `.bash_aliases`, `.bash_extra`      |
| `bin`    | `~/bin/` scripts (status, validate, init) |
| `claude` | `~/.claude/settings.json`           |
| `git`    | `.gitconfig`                        |
| `ssh`    | `.ssh/config`, `.ssh/id_ed25519.age` |

These directories are **not** stow packages — their symlinks are created manually in `setup.sh`:

| Directory  | Purpose                             |
|------------|-------------------------------------|
| `agent/`   | Global LLM instructions (`CONTRIBUTING.md`), symlinked into each agent's config dir |
| `gemini/`  | `~/.gemini/skills` (Google Antigravity) |

## LLM agent instructions

All LLM coding agents (Claude Code, OpenAI Codex, Google Antigravity) share a single source of truth for instructions at both levels:

**Global** — `agent/CONTRIBUTING.md` is symlinked by `setup.sh` to:
- `~/.claude/CLAUDE.md` (Claude Code)
- `~/.codex/AGENTS.md` (OpenAI Codex)
- `~/.gemini/AGENTS.md` (Google Antigravity)

**Per-project** — `CONTRIBUTING.md` in the project root is the primary file. Agent-specific symlinks point to it:
- `CLAUDE.md` → `CONTRIBUTING.md` (Claude Code)
- `AGENTS.md` → `CONTRIBUTING.md` (OpenAI Codex)
- `GEMINI.md` → `CONTRIBUTING.md` (Google Antigravity)

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

Reports green/yellow/red per item and prints fix commands in dependency order.

## Adding a new stow package

1. Create `~/dotfiles/<package>/` mirroring the target path under `$HOME`
2. Both `setup.sh` and `validate_setup.sh` auto-discover stow packages — no manual edits needed

## Key files

- `setup.sh` — **Must be self-contained** (curl-piped on fresh machines before the repo exists). Shared variables (`PREREQS`, `APT_PACKAGES`, `STOW_SKIP`) are defined here and sourced by `validate_setup.sh` via a guard (`[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0`)
- `agent/CONTRIBUTING.md` — Single source of truth for global LLM agent instructions
- `bin/bin/validate_setup.sh` — Health check for the entire setup
- `bin/bin/init_project.sh` — Bootstrap CONTRIBUTING.md + CLAUDE.md symlink + CHANGELOG.md in a new project
- `bin/bin/validate_project.sh` — Checks agent file setup in any project (symlinks, .gitignore)
- `bin/bin/pre_commit_check.sh` — Safety scan, doc freshness, changed files (used by prepare-to-commit workflow)
- `bin/bin/check_changelog.sh` — Stop hook: warns when files changed but CHANGELOG.md wasn't updated
- `bin/bin/test_check_changelog.sh`, `bin/bin/test_validate_project.sh`, `bin/bin/test_pre_commit_check.sh` — Tests
- `bash/.bash_extra` — PATH, editor, prompt, WSL config
- `bash/.bash_aliases` — Shell aliases
