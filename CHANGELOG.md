# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [2026-05-05]

### Fixed

- `setup.sh`: Firefox ESR install variable name mismatch (`INSTALL_FFESR` → `INSTALL_FF_ESR`); previously install never ran
- `bin/bin/validate_setup.sh`: Node validation now also checks `npm` and verifies Node/npm actually run (not just on PATH); catches partial fnm installs
- `bin/bin/validate_setup.sh`: ssh-decrypt fix command now also regenerates the public key in the same command (avoids two-step prompt)

## [2026-05-04]

### Fixed

- `setup.sh`: prereq check now loops over the full `PREREQS` array instead of hardcoding 4 of 5 commands, so `unzip` (needed by the fnm installer) is no longer silently skipped
- `setup.sh`: run `apt update` before installing prerequisites so packages like `age` and `stow` are found on a fresh machine

### Added

- `setup.sh` / `.setup.conf.template`: replace heredoc-generated config with a tracked template file; setup copies it on first clone so the user can configure the machine before the first full run
- `setup.sh` / `validate_setup.sh` / `.setup.conf.template`: add `INSTALL_FFESR` toggle to install Firefox ESR from the Mozilla apt repo
- `validate_setup.sh`: new "Machine Config" section checks `.setup.conf` against the template and reports any missing keys, with a fix command that appends the missing defaults

## [2026-05-02]

### Added

- `setup.sh`: install glow (markdown CLI pager) from Charm's apt repo, instead of batcat
- `bin/bin/validate_setup.sh`: check for glow installation with fix command that sets up Charm repo


## [2026-04-28]

### Changed

- `bin/bin/check_repos.sh`: outputs repos in alphabetical order (collected and sorted before processing); now outputs one line for every repo (clean or with changes), instead of only repos with changes
- `bin/bin/check_repos.sh`: repos with changes are displayed in bold
- `bin/bin/check_repos.sh`: displays repo names only (basename), not full paths
- `bin/bin/validate_setup.sh`: `-u|--update` mode now runs apt package updates first, then dev toolchains (better dependency order)
- `setup.sh`: silences Ubuntu Pro apt advertisements via `pro config set apt_news=false` and masking `apt-news`/`esm-cache` services (preserves `update-manager-core` etc.)
- `bin/bin/validate_setup.sh`: checks Pro `apt_news` setting and that apt-news/esm-cache services are masked; offers fix commands for both

### Fixed

- `bin/bin/validate_setup.sh`: fixed dfx update command to use `dfxvm update` (correct command when dfxvm is installed)

## [2026-04-27]

### Added

- `bin/bin/check_repos.sh` — Scans all git repos under ~ for uncommitted code; outputs one line per repo with changes

### Fixed

- `setup.sh`: ic-admin installation now correctly places binary in ~/.local/bin instead of current working directory
- `setup.sh`: claude package now skipped from stow, preventing settings.json from being symlinked (allows template copy deployment)
- `setup.sh`: ic-admin installation now correctly places binary in ~/.local/bin instead of current working directory
- `bin/bin/validate_setup.sh`: now checks locally-specific packages from MORE_APT_PACKAGES in .setup.conf
- `setup.sh` and `bin/bin/validate_setup.sh`: removed redundant `sudo apt update` from all package install commands; now only run in `-update` mode
- `setup.sh`: added reminder at end to run `validate_setup.sh -u|--update` for package/toolchain updates

## [2026-04-26]

### Added

- `bin/bin/validate_setup.sh -update`: Updates apt packages and active toolchains (rust, node, icp) based on config toggles
- `bin/bin/validate_setup.sh`: checks that `~/.claude/settings.json` exists and has all required keys (permissions, hooks, statusLine, terminalTitleFromRename, autoMemoryEnabled, remoteControlAtStartup)
- `bin/bin/validate_setup.sh`: detects if settings.json is a symlink (legacy stow deployment) and suggests converting to a copy

### Changed

- `bin/bin/claude_status.sh`: round 5h/7d reset times to nearest 10 minutes instead of 1-minute precision
- `setup.sh`: refactored to load machine-specific toggles from `.setup.conf` (created on first run with all toggles defaulting to false)
- `setup.sh`: added `MORE_APT_PACKAGES` variable in config for locally-specific apt packages
- `setup.sh`: include `python3-pip` when installing Python (was missing, required for pip updates)
- `bin/bin/validate_setup.sh`: Python check now validates python3-pip is installed along with python3 and python3-venv
- `setup.sh`: `claude/.claude/settings.json` no longer deployed via stow; now copied from template to `~/.claude/settings.json` on first run (allows per-machine customization)

### Removed

- Hard-coded dev toolchain and LLM agent toggle defaults from setup.sh (now all false in generated config)


## [2026-04-23]

### Added

- `bin/bin/expand_wsl_disk.sh` — Expand WSL2 disk space from within Ubuntu; finds VHDX via registry, uses diskpart (with Windows admin elevation), resizes filesystem with resize2fs
- `bin/bin/test_expand_wsl_disk.sh` — Tests for expand_wsl_disk.sh

## [2026-04-07]

### Added

- `setup.sh`: add IPv6 static address boot command to `/etc/wsl.conf` on hostname `bequiet`
- `validate_setup.sh`: check for IPv6 boot command in `/etc/wsl.conf` on `bequiet`

## [2026-04-05]

### Changed

- `settings.json`: enable `terminalTitleFromRename` for custom terminal titles with Claude Code status indicators
- `settings.json`: Stop hook uses `$WSL_DISTRO_NAME` (hostname fallback) and writes to stderr instead of `/dev/tty`

### Removed

- `settings.json`: SessionStart title hook (overridden by Claude Code's built-in title)

### Added

- `setup.sh` adds user to docker group (`usermod -aG docker`) when `INSTALL_DOCKER=true`
- `validate_setup.sh` checks docker group membership and prints fix command

## [2026-04-04]

### Added

- `INSTALL_CLAUDE` and `INSTALL_GEMINI_CLI` toggles in `setup.sh` — Claude Code and Gemini CLI are now configurable like Rust, Node, etc.
- `validate_setup.sh` checks and fix commands for Claude Code and Gemini CLI, conditional on toggles
- `test_setup_toggles.sh` — tests for the new LLM agent toggles
- All toggles are now overridable via environment variables (`${VAR:-default}` pattern)

### Fixed

- `validate_setup.sh`: detect stow-folded directory symlinks at any depth (fixes gemini false positives)
- `validate_setup.sh`: remove hardcoded gemini check — fully covered by stow symlink loop
- `validate_setup.sh`: remove redundant git settings value check (covered by stow symlink)

## [2026-04-04]

### Added

- Dev toolchain toggles in `setup.sh`: `INSTALL_RUST`, `INSTALL_NODE`, `INSTALL_ICP`, `INSTALL_PYTHON`, `INSTALL_DOCKER`
- Rust via `rustup`, Node via `fnm`, ICP via `dfxvm` + `ic-admin`, Python via apt, Docker via apt
- `validate_setup.sh` checks and fix commands for all dev toolchains
- Claude Code installed via `curl`

### Fixed

- `validate_setup.sh` stow check: skip gitignored files (generated pub keys, known_hosts)
- `setup.sh` prevents stow from folding `~/.ssh` into a symlink

## [2026-04-04]

### Changed

- Stop tracking `id_ed25519.pub` and `known_hosts` in git (machine-specific, derived from private key)
- `setup.sh` regenerates public key from private key after decryption
- `setup.sh` switches dotfiles remote from HTTPS to SSH after keys are set up
- `setup.sh` ensures `~/bin/*.sh` scripts are executable after stow
- Remove stale `~/.gemini/workflows` symlink from setup and validate (directory doesn't exist)
- Auto-allow `pre_commit_check.sh`, `validate_setup.sh`, `validate_project.sh` in Claude Code permissions
- `validate_setup.sh` checks private key matches `.age` source and public key matches private key
- `validate_setup.sh` checks dotfiles remote is SSH (not HTTPS)
- `validate_setup.sh` checks `~/bin/*.sh` scripts are executable
- Update `CONTRIBUTING.md` to reflect current ssh package contents and gemini structure

### Fixed

- `claude_status.sh` extra credits display: convert cents to dollars, show limit as whole dollars
- `validate_setup.sh` SSH checks: replace age decryption with sha256sum, fix pub key comparison

### Added

- `gr` alias for `git restore`

## [2026-04-01]

### Added

- `bin/bin/validate_project.sh` — checks agent file symlinks and .gitignore in any project
- `bin/bin/pre_commit_check.sh` — safety scan, doc freshness, changed files in one script
- `bin/bin/test_validate_project.sh`, `bin/bin/test_pre_commit_check.sh` — tests for above

### Changed

- `claude_status.sh` line 2: `5h: 73% oooooooooo till 22:00 | 7d: ...` — percentages before bars, times after
- Pre-commit workflow consolidated: safety/docs/files checks in `pre_commit_check.sh`, copy-paste git commands at the end
- `agent/CONTRIBUTING.md`: changelog compression rules, streamlined pre-commit steps

## [2026-04-01]

### Added

- `bin/bin/check_changelog.sh` — Stop hook that warns when files are modified but CHANGELOG.md is not
- `bin/bin/test_check_changelog.sh` — 5 test scenarios for the Stop hook
- `agent/CONTRIBUTING.md` — single source of truth for global LLM instructions (TDD, changelog compression, pre-commit checklist)
- `gemini/` directory — Antigravity skills/workflows (moved from `agent/`)
- `AGENTS.md` and `GEMINI.md` symlinks → `CONTRIBUTING.md` (for Codex and Antigravity)
- `init_project.sh` creates all three agent symlinks and adds them to `.gitignore`

### Changed

- `claude_status.sh` line 2: compact format — `5h at HH:MM` / `7d at MM/DD HH:MM` with 24h clock
- Renamed project instructions `CLAUDE.md` → `CONTRIBUTING.md`; `CLAUDE.md`, `AGENTS.md`, `GEMINI.md` are gitignored symlinks
- Renamed `WORKLOG.md` → `CHANGELOG.md` using [Keep a Changelog](https://keepachangelog.com/) format
- `setup.sh` — creates global instruction symlinks to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/AGENTS.md`, `~/.gemini/GEMINI.md`; Antigravity targets `~/.gemini/`
- `claude/.claude/settings.json` — added `check_changelog.sh` as Stop hook
- `bin/bin/validate_setup.sh` — checks global LLM instruction symlinks and Antigravity at `~/.gemini/`
- `bin/bin/init_project.sh` — bootstraps `CONTRIBUTING.md` + agent symlinks + `CHANGELOG.md`

### Removed

- `claude/.claude/CLAUDE.md` — replaced by symlink to global instructions
- `claude/.claude/skills/pre-commit/SKILL.md` — merged into global instructions
- `agent/.agent/` — Antigravity skills/workflows moved to `gemini/.gemini/`

## [2026-03-31]

### Added

- `bin/bin/validate_setup.sh` — validates entire setup with green/yellow/red reporting and fix commands
- `claude/.claude/settings.json` — stow package for Claude Code config (model, status line, auto-memory)
- `claude/.claude/CLAUDE.md` — global Claude instructions
- `CLAUDE.md` — project-specific instructions for this repo
- `bin/bin/init_project.sh` — bootstrap script for CLAUDE.md + WORKLOG.md in new projects
- `bin/bin/claude_status.sh` — status line script

### Changed

- `bash/.bash_extra` — PATH extension now deduplicates `~/.local/bin` and `~/bin`
- `setup.sh` — added `stow --adopt bin` and `stow --adopt claude` with `mkdir -p ~/.claude`
