# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

## [Unreleased]

### Added

- `AGENTS.md` and `GEMINI.md` symlinks → `CONTRIBUTING.md` (for Codex and Antigravity)
- `init_project.sh` now creates all three agent symlinks and adds them to `.gitignore`

### Changed

- Renamed `AGENT.md` → `CONTRIBUTING.md` and `WORKLOG.md` → `CHANGELOG.md` across entire setup
- `agent/CONTRIBUTING.md` is now the global LLM instructions source of truth (was `agent/AGENT.md`)
- `CHANGELOG.md` follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) format with `[Unreleased]` section
- Global instructions now tell agents to update `CHANGELOG.md` using Keep a Changelog categories
- `check_changelog.sh` replaces `check_worklog.sh` (Stop hook)
- `test_check_changelog.sh` replaces `test_check_worklog.sh`
- `init_project.sh` now bootstraps `CONTRIBUTING.md`, `CLAUDE.md` symlink, and `CHANGELOG.md`

## [2026-04-01]

### Added

- `bin/bin/check_worklog.sh` — Stop hook that warns when files are modified but WORKLOG.md is not
- `bin/bin/test_check_worklog.sh` — 5 test scenarios for the Stop hook
- `agent/AGENT.md` — single source of truth for global LLM instructions (TDD, changelog, pre-commit)
- `gemini/` directory — Antigravity skills/workflows (moved from `agent/`)

### Changed

- `setup.sh` — creates global instruction symlinks to `~/.claude/CLAUDE.md`, `~/.codex/AGENTS.md`, `~/.gemini/AGENTS.md`; Antigravity symlinks target `~/.gemini/` instead of `~/.agent/`
- `claude/.claude/settings.json` — added `check_worklog.sh` as Stop hook
- `bin/bin/validate_setup.sh` — added Global LLM Instructions section; Antigravity checks use `~/.gemini/`
- `bin/bin/init_project.sh` — creates `AGENT.md` as primary + `CLAUDE.md` symlink
- Project instructions renamed from `CLAUDE.md` to `AGENT.md`; `CLAUDE.md` is now a symlink

### Removed

- `claude/.claude/CLAUDE.md` — replaced by symlink to global instructions
- `claude/.claude/skills/pre-commit/SKILL.md` — merged into global instructions
- `agent/.agent/workflows/pre_commit.md` — merged into global instructions

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
