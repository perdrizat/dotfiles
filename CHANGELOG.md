# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

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
