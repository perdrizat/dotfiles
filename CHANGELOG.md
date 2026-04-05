# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

## [2026-04-05]

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
- Renamed `WORKLOG.md` → `CHANGELOG.md` using [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format
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
