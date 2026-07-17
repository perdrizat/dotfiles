# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

## [2026-07-17]

### Added

- `bin/bin/claude_status.sh`: when the usage endpoint returns HTTP 429, the 5h/7d fields show an amber `rate limited` instead of a generic `unknown`.
- `bin/bin/claude_status.sh`: honor the 429 `retry-after` header — record the deadline in a backoff file and make no further requests until it passes, so a rate-limited box stops re-tripping (and thereby indefinitely prolonging) its own limit.
- `bin/bin/claude_status.sh`: line 1 shows the account as `<email> · <Pro/Max/Team>` right-aligned via `$COLUMNS` (a few columns short of the edge so Claude Code's status-line truncation can't eat it), dropped gracefully when the terminal is too narrow or `$COLUMNS` is unset.

### Changed

- `tmux/.tmux.conf`: window labels now read `index:command@repo` (e.g. `1:claude@dotfiles`) — the active pane's command plus its working-dir basename — instead of just the command.
- `tmux/.tmux.conf`: delay the second window's `claude` by 10s (`sleep 10 &&`) on session start so the two statuslines don't hit the usage API simultaneously — the first fetch sets the shared throttle stamp before the second renders, avoiding a boot-time 429 burst.
- `agents/AGENTS.md`: strengthen the scratch-file rule — `<repo>/.tmp` is the *only* scratch location and explicitly overrides any harness-provided `/tmp` "scratchpad"; never fall back to `/tmp`, `/var/tmp`, or `$TMPDIR`.

### Fixed

- `bin/bin/claude_status.sh`: a cold cache renders `unknown` instead of a misleading `0%` until real usage data is cached; reset-time/extra-usage parsing is skipped when no data is cached, avoiding `date: invalid date` errors on the unknown path.
- `bin/bin/claude_status.sh`: usage stats recover automatically after a rate limit — scope the cache/throttle/backoff files per account (`subscriptionType`) so switching accounts no longer inherits another account's 429 backoff (which left a never-limited team account stuck showing "rate limited"), honor the server's full `retry-after` (probing again before it expires only re-arms the limit's acceleration penalty, which kept a box pinned at "rate limited"), and gate cold-cache fetches with the throttle stamp so a non-429 failure can't re-fetch on every render.

## [2026-07-16]

### Added

- `tmux/.tmux.conf`: enable `focus-events on` so apps (Claude Code, Vim) receive terminal focus-in/out events, fixing Claude Code's focus warning and notification timing.
- `claude/.claude/settings.json`: suppress non-essential UI that consumes terminal real estate — `spinnerTipsEnabled: false` (spinner tips), `awaySummaryEnabled: false` (return-from-away recap), `feedbackSurveyRate: 0` (session survey).
- `INSTALL_CHROME` toggle: `setup.sh` installs `google-chrome-stable` from Google's apt repo (amd64) and `validate_setup.sh` checks it, mirroring the Firefox blocks.
- `bash/.bash_aliases`: `monitor <file.md> [scan-depth]` shell function — live-renders a file's first markdown table (plus title/preamble) with glow, stopping before any second table, re-rendering on each change via mtime polling.

### Changed

- `bash/.bash_aliases`: `md` is now a function (was an alias) and both `md` and `monitor` wrap glow to the current terminal width via bash's `$COLUMNS` at call time (falling back to 170), instead of a fixed `-w170`. `$COLUMNS` is correct inside tmux, unlike `tput cols`, which reports 80 in a command substitution (its stdout is a pipe, not the terminal).
- `agents/AGENTS.md`: expand the "Running commands" guidance — never poll a long-running command with a shell loop (use background mode), cancel approvals stuck over ~10 min and simplify, propagate the command rules into every subagent brief (replaces the old "leave risky commands manual" bullet), and run `git` with the bare subcommand from the repo dir rather than the non-allowlisted `git -C <path>`.
- `gemini/.gemini/antigravity-cli/settings.json`: allowlist `git checkout` for agy.

### Fixed

- `bin/bin/validate_setup.sh`: the dotfiles-repo check only `git fetch`es (which may prompt for auth) when the last fetch is >24h old — within 24h it compares against the cached `origin/main` instead of hitting the server.
- `bin/bin/claude_status.sh`: 5h/7d usage bars no longer blank to 0% — the usage endpoint rate-limits (HTTP 429) when polled too often (multiple tmux panes at a 60s TTL), and the script cached the error, letting jq's `// 0` fallback show 0%. Now caches only valid payloads (keeping the last good numbers through a 429) and throttles to one shared fetch per 5 min.
- `setup.sh`: `mkdir -p ~/.config/gh` before stow so the directory can't fold into a symlink — `gh`'s secret `hosts.yml` now stays in `$HOME` instead of landing in the repo tree.
- `.gitignore`: ignore `gh/.config/gh/hosts.yml` as defense-in-depth so the `gh` auth token can never be accidentally committed.

## [2026-07-15]

### Added

- `tmux/.tmux.conf`: `session-created` hook opens every new session with two windows, each split vertically (~65% top / ~35% bottom) and auto-running `claude --resume` in the top pane — window 1 both panes in the start dir, window 2 both panes in `~/dotfiles` (attach never re-splits).

## [2026-07-13]

### Added

- `tmux/` stow package: added modern, screen-friendly `.tmux.conf` configuration (rebinds prefix to `Ctrl-A`, disables mouse to retain native terminal copy-paste per `.vimrc`, and adds intuitive shortcuts)
- `gh/` stow package: track `gh` preferences by committing `config.yml` while adding a `.stow-local-ignore` for `hosts.yml` to prevent the secret access token from being stowed or entering the repository

### Changed

- `tmux/.tmux.conf`: enable `mouse on` so the scroll wheel triggers native tmux scrollback rather than sending arrow keys to interactive shell apps like `agy`
- `setup.sh` and `validate_setup.sh`: added `tmux` to `APT_PACKAGES` to ensure it is always installed
- `validate_setup.sh` and `setup.sh`: verify that `gh auth status` is successful (if `gh` is installed) and print a login reminder or a `gh-auth` missing fix entry

## [2026-07-09]

### Added

- `bash/.bash_aliases`: `md` alias — `glow -pn -w0` for nicely formatted, unwrapped Markdown rendering in the pager.

## [2026-07-08]

### Changed

- `agents/AGENTS.md`: scratch-file rule now mandates the repo's gitignored `.tmp/` (create it if missing) as the single scratch location, dropping the session-scratch-dir alternative.
- `init_project.sh`: create `.tmp/` and add it to `.gitignore` when bootstrapping a project.
- `validate_project.sh`: check that `.tmp/` exists and is gitignored.
- `.gitignore`: ignore the `.tmp/` scratch dir in this repo too.

## [2026-07-06]

### Added

- `SSH_LOCAL` toggle (`.setup.conf.template`, default off): opt-in decryption of the age-encrypted SSH private key to `~/.ssh/id_ed25519`. Now the sole gate for local decryption (was implicitly gated behind `SSH_YUBIKEY != true`), so it works independently of the YubiKey relay; `validate_setup.sh` only flags `ssh-decrypt` when `SSH_LOCAL` is on.

### Changed

- `agents/AGENTS.md`: add a Patterns & Conventions rule to delegate coding tasks to an appropriately lower-power model run in a subagent, reserving the high-power orchestrator for planning/judgement/review.

### Fixed

- `setup.sh`: a wrong age passphrase left a 0-byte `~/.ssh/id_ed25519` that the old `[ ! -f ]` guard mistook for a decrypted key (skipping it on every rerun). Now decrypts under `umask 077`, verifies the result is non-empty, retries up to 3 times, and removes any stray empty key up front. `validate_setup.sh` flags a 0-byte key as `x Empty`.

## [2026-06-23]

### Changed

- `agents/AGENTS.md`: recast "Running commands" around staying within allowlisted behaviour to avoid approval prompts — name the two distinct prompt triggers (shell operators in the line; non-allowlisted tools/args, e.g. `sed`/`awk`, or `grep` with expansion-looking arguments) and route around each, targeting the recurring `cmd | grep | tail` habit specifically; add a rule to keep scratch files in the session scratch dir or a gitignored repo `.tmp/` rather than `/tmp` (and not to blanket-allowlist `/tmp`).
- `setup.sh`: reword the Firefox block header from "Setting up Mozilla apt repo" to "Installing Firefox from the Mozilla apt repo" — the repo-setup substeps are idempotent and silent when already present, so the old header falsely implied the repo was being recreated on every Firefox (re)install.

## [2026-06-22]

### Fixed

- `setup.sh` / `bin/bin/validate_setup.sh`: Ubuntu's `firefox` snap stub deb (version `1:1snap1-…`) satisfied the old `dpkg -s firefox` presence check, so the Mozilla deb was never installed and the snap stayed. Now a snap-versioned build counts as "needs the Mozilla deb": setup reinstalls it (`--allow-downgrades`, the stub's `1:` epoch outranks Mozilla's) and removes the leftover snap; validate flags it as `x Snap stub`.

## [2026-06-21]

### Added

- `vim` stow package (`vim/.vimrc`): `set mouse=` to disable the mouse so it never enters Visual mode on selection, letting the terminal handle copy/paste

## [2026-06-20]

### Fixed

- `setup.sh` / `bin/bin/validate_setup.sh`: gate all Antigravity config on `INSTALL_ANTIGRAVITY` — when false, the `gemini` stow package (agy skills + settings template) is added to `STOW_SKIP`, the `~/.gemini/config` mkdir and `~/.gemini/antigravity-cli` unfold are skipped, and validate no longer runs (or flags) the Antigravity Configuration section. Previously a disabled machine was told to re-run setup for a missing `agy settings.json`.
- `setup.sh` / `bin/bin/validate_setup.sh`: gate Claude settings on `INSTALL_CLAUDE` the same way — when false, `~/.claude/settings.json` is not deployed/merged and validate skips the Claude Code Configuration section. The always-on `~/.claude/CLAUDE.md` global-instructions symlink is unaffected.

### Changed

- `claude/.claude/settings.json`: allow internet access generally — replaced the three `WebFetch(domain:…)` entries with a broad `WebFetch` (all domains) plus `WebSearch`, so the agent no longer prompts per website

## [2026-06-16]

### Changed

- `agents/AGENTS.md`: commit-prep rule now mandates a single squashed commit and never splitting — removes the "you may suggest splitting" escape hatch that caused an over-split commit proposal

### Fixed

- `bin/bin/install_nerd_fonts.sh`: register per-user Windows fonts with their FULL PATH (was a bare filename) — `%LOCALAPPDATA%\…\Fonts` isn't on the font search path, so bare-filename HKCU entries loaded only for the live session and were dropped at the next logon (the "font vanishes after reboot" bug); self-heals existing bare-filename entries
- `bin/bin/install_nerd_fonts.sh`: fix idempotency — the install guard matched the registry full-path value (was grepping `"CaskaydiaCove Nerd Font"`, but the GDI registry name is the abbreviated `"CaskaydiaCove NF"`, so it re-downloaded every run); download guard now matches the real `CaskaydiaCove*`/`FiraCode*` files instead of the `CascadiaCode` archive name
- `bin/bin/install_nerd_fonts.sh`: header documents the CascadiaCode-archive vs CaskaydiaCove-family naming (OFL Reserved Font Name) and the dual DirectWrite name (`CaskaydiaCove Nerd Font`, used by Windows Terminal/VS Code) vs GDI alias (`CaskaydiaCove NF`, shown only by GDI/GDI+ tools)

## [2026-06-13]

### Fixed

- `bash/.bash_extra`: fix WSL ghost socket bug preventing `socat` restart by checking socket file existence and active process

## [2026-06-12]

### Added

- `agents/AGENTS.md`: Added rule forbidding emojis in text output (use unobtrusive text symbols like `✓`, `~`, `x` instead)
- `agents/AGENTS.md`: Added `pnpm audit` step to commit preparation for Node projects
- `agents/AGENTS.md`: Added global preference for single squashed commits with extremely brief commit messages

### Changed

- `validate_setup.sh`: Config validation now prints exact untracked/missing settings keys as a diff (+/- list) instead of just counts
- `bin/bin/*`: Replaced emojis (`⚠`, `✗`) with unobtrusive text symbols (`~`, `x`) in validation script outputs
- `CONTRIBUTING.md`: Replaced local squashed commit rule (now global) with a rule to invoke local `bin/bin` tools directly
## [2026-06-11]

### Added

- `bin/bin/check_ipv6.sh`: IPv6 doctor — layer-by-layer diagnosis (interface, routing, ICMP, per-source probes, Windows-host probe, DNS, HTTPS, wsl.conf) for the "bun i hangs" symptom; every probe is timeout-bounded and each check self-guards its prerequisite tool/file (skips, never errors, when absent); the retired static pin is verdicted by *testing* the address, not assuming it's bad. Header carries a network change log (dated, with confidence levels)

### Changed
- `bin/bin/wsl_ssh_agent.sh`: replace blind key recovery with an interactive prompt (recover/generate/skip) on fresh machines, invoke powershell directly to fix hidden stderr prompts, and display GitHub + test connection instructions for newly generated keys
- `bin/bin/wsl_ssh_agent.sh`: add `-q`/`--quiet` option to silence success/info messages (prompts and errors remain visible)
- `setup.sh`: invoke `wsl_ssh_agent.sh` with `-q` to avoid cluttering the output when the relay is already successfully configured
- `setup.sh`: skip decryption and regeneration of `~/.ssh/id_ed25519` via `age` when `SSH_YUBIKEY=true` (since the YubiKey resident key is used instead)
- `setup.sh`: make the `. ~/.bashrc` shell restart call-to-action contingent on actual changes (modifying `.bashrc`, or installing `rustup`, `fnm`, `dfxvm`, docker group, or a fresh YubiKey relay)
- `setup.sh`: retire the bequiet wsl.conf `[boot]` static-IPv6 pin — under WSL mirrored networking that locally-added EUI-64 address blackholes (return traffic only forwards for mirrored addresses), hanging every dual-stack client (bun/npm); mirrored SLAAC addresses work unaided. Replaced the `WSL_BOOT` block with a do-not-reintroduce note
- `bin/bin/validate_setup.sh`: WSL check inverted into a regression guard — an active `ip -6 addr` pin in wsl.conf is now flagged (was required); fix id `wsl-ipv6` → `wsl-ipv6-pin` with a targeted manual remedy (not setup.sh-fixable)

### Fixed

- bequiet IPv6 outage: removed the blackholing pinned address from the running interface and cleaned `/etc/wsl.conf` (merged duplicate `[boot]` sections, dropped the commented pin leftover) — `bun i` no longer hangs

## [2026-06-10]

### Added

- `bin/bin/agy_title.sh` + `title` block in the agy settings template: agy sets the terminal title to `agy@<workspace>` (✳-prefixed while working), mirroring Claude's `terminalTitleFromRename`; `setup.sh` merges `title` parity and `validate_setup.sh` requires the key
- `gemini/.stow-local-ignore`: permanently excludes `antigravity-cli` from stow — template stays repo-only, deployed copy stays local
- `bin/bin/validate_setup.sh`: "Behind template" check (Claude + agy) — flags template allows missing from the local settings.json, the until-now invisible reverse of the untracked-allows check; setup.sh-fixable

### Changed

- `setup.sh`: self-heal `.setup.conf` on every executed run — migrate `INSTALL_GEMINI_CLI` → `INSTALL_ANTIGRAVITY` (preserving its value) and append template keys missing from the machine config; skipped when sourced, so `validate_setup.sh` stays read-only
- `setup.sh`: uninstall the retired Gemini CLI when its binary is present; enforce SSH permissions (700 `~/.ssh`, 600 key, 644 config) behind the previously empty "Fixing remaining SSH permissions" step
- `setup.sh`: reverse-sync allows granted locally into the repo templates (Claude + agy, union only) with a "commit ~/dotfiles to share" hint; `validate_setup.sh` reclassifies `claude-untracked-allows`/`agy-untracked-allows` as setup.sh-fixable and drops their manual jq commands
- `bin/bin/validate_setup.sh`: consolidate fix commands — every finding that the idempotent `setup.sh` provisions now prints as a single `( cd ~/dotfiles && bash setup.sh )` fix; targeted commands remain only for repo clone/sync, the YubiKey relay, Claude settings deploy
- `CONTRIBUTING.md`: Validation section documents the consolidated setup.sh fix behavior; `gemini` package row documents the stow-excluded agy settings template
- `gemini/.gemini/antigravity-cli/settings.json`: template gains agy runtime defaults (`model`, `colorScheme`, `enableTelemetry`, `allowNonWorkspaceAccess`, `verbosity`) and a `pgrep` allow
- `setup.sh`: all four settings syncs (forward + reverse, Claude + agy) unified into a `merge_settings` helper sharing one allows-union jq program — writes only when the merge result differs from the destination as JSON, so "Merged/Synced" always means a real change (the agy merge previously rewrote and reported on every run); writes in place via redirect instead of mv/tmp-file, preserving the destination inode (hardlinks, symlinks)
- `setup.sh`: `.setup.conf` migration edits in memory and writes back via redirect — `sed -i` renames a temp file over the config, replacing its inode and clobbering a symlinked `DOTFILES_CONFIG` into a regular file
- `bin/bin/agy_status.sh`: comment marks the cache tmp+mv as deliberate (atomic publish for concurrent status-line readers; file never linked)
- `CONTRIBUTING.md`: "Link-safe file updates" convention — rewrite file content via in-memory edit + redirect, never `mv tmp-file target` or `sed -i` (inode replacement breaks hardlinks/symlinks); documents the relocation and atomic-publish exceptions

### Fixed

- `setup.sh`: forward-merge Claude template allows into `~/.claude/settings.json` (union, mirrors the agy merge) — previously the template only deployed when no local file existed, so allows committed on other machines never propagated and this box silently lacked the 7 pnpm allows
- `bin/bin/validate_setup.sh`: untracked-allows counts use jq `length` — the old word-split arrays overcounted entries containing spaces
- `setup.sh`: remove a stale pre-CLI-era `~/.local/bin/agy` symlink (dangling or pointing at the Windows IDE under `/mnt/*`) before installing — it blocked the installer's write with "Permission denied" on every run; warn when the install still doesn't yield a binary
- `setup.sh`: gemini uninstall runs the npm *next to the gemini launcher* under that dir's own node — npm's `env node` shebang made it inherit the PATH node (fnm) and uninstall from the wrong global prefix, leaving an nvm-installed gemini in place forever; also works without npm on PATH (`INSTALL_NODE=false`), where the uninstall previously skipped silently
- `setup.sh`: the agy settings merge enforces `statusLine`/`hooks` parity only for keys the template actually has — a template missing one of them no longer stamps `null` into (or erases hooks from) `~/.gemini/antigravity-cli/settings.json`, which had locked validate/setup into a permanent "missing keys: hooks" loop
- Root cause of the agy template corruption: the template lives inside the `gemini` stow package, so `setup.sh`'s `stow --adopt` adopted the live `~/.gemini/antigravity-cli/settings.json` into the repo (clobbering the template) or folded the whole dir into a repo symlink (agy then wrote runtime state — settings, logs, oauth token — straight into the git tree). Same bug class as the Claude `settings.json` stow fix from 2026-04-27; `claude` could be `STOW_SKIP`ped wholesale, `gemini` can't (skills must stow)
- `setup.sh`: unfold a symlinked `~/.gemini/antigravity-cli` before stowing, salvaging agy runtime state (oauth token, logs, history) from the repo into the new local dir
- `bin/bin/validate_setup.sh`: flag a symlinked `~/.gemini/antigravity-cli` as ✗ (was praised as "✓ Linked"); skip `.stow-local-ignore` and the excluded subtree in the stow checks

### Removed

- `bin/bin/validate_setup.sh`: orphaned `ssh-stow-dir-perms` fix entry (no check ever produced it)

## [2026-06-09]

### Added

- `bin/bin/install_nerd_fonts.sh`: script to download and install patched Nerd Fonts
- `gemini/.gemini/antigravity-cli/settings.json`: template config to enforce status-line and permissions parity with Claude Code
- `bin/bin/agy_status.sh`: native Antigravity status-line script matching Claude's HUD (dynamic model/quota tracking, token caching info, zero-latency background API refresh via `pgrep -x agy`)
- `bash/.bash_aliases`: `ac` alias for `agy -c` (Antigravity continue), mirroring `cc` (`claude --continue`)

### Changed

- `CONTRIBUTING.md`: add convention specifying preference for squashed commits and extremely brief commit messages
- `claude/.claude/settings.json` and `gemini/.gemini/antigravity-cli/settings.json`: auto-allow `pnpm` (`build`, `lint`, `typecheck`, `test` suites) without prompting
- `setup.sh`: dynamically merge the Antigravity `settings.json` template into local state (`~/.gemini/antigravity-cli/settings.json`) without destroying manual config blocks
- `bin/bin/validate_setup.sh`: add Antigravity checks for config file health and report/merge locally discovered untracked permissions (`agy-untracked-allows` and `claude-untracked-allows`)
- `gemini/.gemini/antigravity-cli/settings.json`: port Claude's `check_changelog.sh` Stop hook over to Antigravity so it enforces changelog updates natively upon session exit
- `agents/AGENTS.md`: revert explicit pre-flight check rule since Antigravity now enforces changelog updates via the native Stop hook
- `setup.sh`: make the Node toolchain block idempotent on re-run — skip `fnm install --lts` when a Node version is already present (upgrades stay in `validate_setup.sh -u`), and `npm install -g` only the missing globals (`vite`/`pnpm`)

## [2026-06-07]

### Added

- `CONTRIBUTING.md` imrove unattended automated testing
- `setup.sh`: create the project agent symlinks (`CLAUDE.md`/`AGENTS.md` → `CONTRIBUTING.md`) at the repo root when missing, so the repo satisfies its own `validate_project.sh` contract
- `bin/bin/validate_setup.sh`: new "Project Agent Files (~/dotfiles)" section checks the repo's `CLAUDE.md`/`AGENTS.md` → `CONTRIBUTING.md` symlinks, with a `project-agent-symlinks` fix entry

### Changed

- Rename `agent/CONTRIBUTING.md` → `agents/AGENTS.md` (the home-dir global agent-instruction source, not a project contributing guide; matches `agy`'s `AGENTS.md` convention); update `setup.sh` (incl. `STOW_SKIP`), `validate_setup.sh`, docs, and the home-dir symlinks
- `agents/AGENTS.md`: CHANGELOG rules — one section per date, and record the net delta vs the previous commit (not the editing journey)
- `agents/AGENTS.md`: add a "Precedence" clause (a project's own instruction files may override the global rules); `CONTRIBUTING.md` uses it to opt this repo out of Red-Green TDD and new test scripts
- `bin/bin/validate_project.sh`: collapse the fix block into a single-line subshell — `( cd "<run cwd>" && cmd1 && cmd2 && … )` — using `pwd` so the line is pasteable from any shell
- `setup.sh` / `.setup.conf.template` / `bin/bin/validate_setup.sh`: replace the Gemini CLI with the Antigravity CLI — `INSTALL_GEMINI_CLI` → `INSTALL_ANTIGRAVITY`, install `agy` via `curl -fsSL https://antigravity.google/cli/install.sh | bash`; validation checks `agy` and flags a leftover `gemini` binary / `INSTALL_GEMINI_CLI` key to migrate (Gemini CLI stops serving 2026-06-18)
- `setup.sh` / `bin/bin/validate_setup.sh`: Antigravity global instructions move to `~/.gemini/GEMINI.md` (symlink to `agents/AGENTS.md`)
- `gemini` stow package: relocate `agy` skills to `~/.gemini/config/skills` (+ `skills.inactive`); `setup.sh` pre-creates `~/.gemini/config` so stow folds at the skills level
- `setup.sh`: prune retired symlinks from earlier layouts on every run (`~/.gemini/AGENTS.md`, old top-level `~/.gemini/skills`/`skills.inactive`, repo-root `GEMINI.md`) — idempotent, symlinks only, so a pull + `setup.sh` fully self-heals an existing devbox
- `bin/bin/validate_setup.sh`: global-instructions fix now points to `( cd ~/dotfiles && bash setup.sh )` (complete remediation incl. pruning); standardize the other `setup.sh` fix hints on the same cwd-safe subshell form

### Removed

- All `bin/bin/test_*.sh` scripts (6) per the repo's new no-test-scripts policy; dropped their references in `CONTRIBUTING.md` and `wsl_ssh_agent.sh`
- `GEMINI.md` as a per-project agent file (Antigravity reads workspace `AGENTS.md`): `validate_project.sh`, `init_project.sh`, `.gitignore`, and the agent-file docs now track only `CLAUDE.md`/`AGENTS.md`

## [2026-06-02]

### Added

- `SSH_YUBIKEY` toggle: relay the Windows ssh-agent (YubiKey `ed25519-sk`) into WSL via `socat`+`npiperelay`, so one resident key works across all WSL distros/hosts
- `bin/bin/wsl_ssh_agent.sh`: idempotent, detection-gated provision/repair of the relay — ensures socat, Windows OpenSSH ≥ 8.4 (winget→Optional Feature), ssh-agent service (one UAC), pinned+checksummed npiperelay, sk key handle (`ssh-keygen -K`), and writes `~/.config/dotfiles/ssh_agent.env`
- `bash/.bash_extra`: WSL-guarded snippet that sources the generated env file and starts the relay (silent no-op when unprovisioned)
- `bin/bin/validate_setup.sh`: diagnostic-only "SSH Agent Relay (YubiKey)" section (socat, npiperelay, live relay) pointing at `wsl_ssh_agent.sh` to fix
- `INSTALL_FF` toggle (`.setup.conf` + template) for Firefox latest from the Mozilla apt repo; for now either `INSTALL_FF` or `INSTALL_FF_ESR` installs & validates both the latest and ESR builds
- `setup.sh`: installs `pnpm` globally via npm alongside `vite` in the Node toggle block
- `bin/bin/validate_setup.sh`: validates `pnpm` (and prints an install fix command) when `INSTALL_NODE=true`

### Fixed

- `setup.sh`: `CONFIG_FILE` is now overridable via `DOTFILES_CONFIG` so tests can drive toggles from a temp config (the toggle-sourcing refactor in 2c6360a had made env-var overrides ineffective — `.setup.conf` was sourced unconditionally over them)

## [2026-05-26]

### Fixed

- `bin/bin/expand_wsl_disk.sh`: rescan the SCSI block device upfront so prior VHDX expansions Linux missed are picked up; skip diskpart entirely when the block device is already at or above the requested size (previously diskpart errored with `E_INVALIDARG`/"parameter incorrect" trying to re-expand a VHDX that was already at the target)

## [2026-05-22]

### Added

- `setup.sh`: installs GitHub CLI (`gh`) by default from official GitHub apt repo
- `bin/bin/validate_setup.sh`: checks for `gh` (GitHub CLI) and provides install fix command

## [2026-05-16]

### Fixed

- `expand_wsl_disk.sh`: ensure script works when FS is full already. Plus misc bugfixes

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
- All toggles are now overridable via environment variables (`${VAR:-default}` pattern)
- Dev toolchain toggles in `setup.sh`: `INSTALL_RUST`, `INSTALL_NODE`, `INSTALL_ICP`, `INSTALL_PYTHON`, `INSTALL_DOCKER`
- Rust via `rustup`, Node via `fnm`, ICP via `dfxvm` + `ic-admin`, Python via apt, Docker via apt
- `validate_setup.sh` checks and fix commands for all dev toolchains
- Claude Code installed via `curl`
- `gr` alias for `git restore`

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

- `validate_setup.sh`: detect stow-folded directory symlinks at any depth (fixes gemini false positives)
- `validate_setup.sh`: remove hardcoded gemini check — fully covered by stow symlink loop
- `validate_setup.sh`: remove redundant git settings value check (covered by stow symlink)
- `validate_setup.sh` stow check: skip gitignored files (generated pub keys, known_hosts)
- `setup.sh` prevents stow from folding `~/.ssh` into a symlink
- `claude_status.sh` extra credits display: convert cents to dollars, show limit as whole dollars
- `validate_setup.sh` SSH checks: replace age decryption with sha256sum, fix pub key comparison

## [2026-04-01]

### Added

- `bin/bin/validate_project.sh` — checks agent file symlinks and .gitignore in any project
- `bin/bin/pre_commit_check.sh` — safety scan, doc freshness, changed files in one script
- `bin/bin/check_changelog.sh` — Stop hook that warns when files are modified but CHANGELOG.md is not
- `agent/CONTRIBUTING.md` — single source of truth for global LLM instructions (TDD, changelog compression, pre-commit checklist)
- `gemini/` directory — Antigravity skills/workflows (moved from `agent/`)
- `AGENTS.md` and `GEMINI.md` symlinks → `CONTRIBUTING.md` (for Codex and Antigravity)
- `init_project.sh` creates all three agent symlinks and adds them to `.gitignore`

### Changed

- `claude_status.sh` line 2: `5h: 73% oooooooooo till 22:00 | 7d: ...` — percentages before bars, times after
- Pre-commit workflow consolidated: safety/docs/files checks in `pre_commit_check.sh`, copy-paste git commands at the end
- `agent/CONTRIBUTING.md`: changelog compression rules, streamlined pre-commit steps
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
