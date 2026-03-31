# Worklog

## 2026-03-31

**What changed:**
- `bash/.bash_extra`: PATH extension now deduplicates — only adds `~/.local/bin` and `~/bin` if not already in `$PATH`
- `setup.sh`: Added `stow --adopt bin` to deploy `~/bin` scripts
- `setup.sh`: Added `stow --adopt claude` with `mkdir -p ~/.claude` pre-step
- `bin/bin/validate_setup.sh`: New script — validates entire setup (prerequisites, repo sync, stow symlinks, SSH, git, apt packages, Claude Code) with green/yellow/red reporting and fix commands in dependency order
- `claude/.claude/settings.json`: New stow package for Claude Code global config (model, status line, auto-memory)
- `claude/.claude/CLAUDE.md`: Global Claude instructions — WORKLOG convention, memory usage, general preferences
- `CLAUDE.md`: Project-specific instructions for this repo
- `bin/bin/init_project.sh`: Bootstrap script to create CLAUDE.md + WORKLOG.md templates in any project
- Status line configured to use `~/bin/claude_status.sh`

**Decisions & rationale:**
- Stow package for `~/.claude/` only tracks `settings.json` and `CLAUDE.md` — credentials, transcripts, and project data are machine-specific and must not be version-controlled
- `~/.claude` must be `mkdir -p`'d before stow because Claude Code writes other files there (stow would otherwise make it a directory symlink)
- `validate_setup.sh` prints fix commands in dependency order (SSH before git) to avoid cascading failures during repair

**Open threads:**
- Raindrop project needs its own CLAUDE.md and WORKLOG.md
- Claude Code settings.json could gain more config (permissions, hooks) as conventions solidify
