# Dotfiles

Personal dotfiles managed with GNU Stow. Deployed via `setup.sh`, validated via `validate_setup.sh`.

## Structure

Each top-level directory is a stow package. Running `stow --adopt <package>` from `~/dotfiles` symlinks its contents into `$HOME`.

| Package  | Contents                            |
|----------|-------------------------------------|
| `bash`   | `.bash_aliases`, `.bash_extra`      |
| `bin`    | `~/bin/` scripts (status, validate, init) |
| `claude` | `~/.claude/settings.json`, `~/.claude/CLAUDE.md` |
| `git`    | `.gitconfig`                        |
| `ssh`    | `.ssh/config`, keys, known_hosts    |

`agent/` is **not** a stow package — its symlinks are created manually in `setup.sh` because `~/.agent` must be a real directory.

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
2. Add `stow --adopt <package>` to `setup.sh` (alphabetical order)
3. Add symlink check(s) to `validate_setup.sh`

## Key files

- `setup.sh` — Installs prerequisites, runs stow, decrypts SSH key, installs apt packages
- `bin/bin/validate_setup.sh` — Health check for the entire setup
- `bin/bin/init_project.sh` — Bootstrap CLAUDE.md + WORKLOG.md in a new project
- `bash/.bash_extra` — PATH, editor, prompt, WSL config
- `bash/.bash_aliases` — Shell aliases
