#!/bin/bash
# wsl_ssh_agent.sh — Provision/repair the YubiKey ssh-agent relay for WSL.
#
# Idempotent and detection-gated: re-run anytime to converge to a healthy state.
# It is a fast no-op when everything is already in place; the interactive steps
# (UAC for the agent service, touch/PIN for ssh-keygen -K) only fire when the
# corresponding piece is actually missing.
#
# Model: ONE resident ed25519-sk key, recovered per host. On each Windows host
# the local key handle is rebuilt from the YubiKey with `ssh-keygen -K` — the
# key already lives in GitHub, so there is no per-host GitHub step.
#
# What it does (all from inside WSL, driving Windows via powershell.exe):
#   1. Ensure socat (WSL side).
#   2. Ensure Windows OpenSSH >= 8.4 (winget -> Optional Feature -> instruct).
#   3. Ensure the Windows ssh-agent service is Automatic + running (one UAC).
#   4. Ensure npiperelay.exe is present on Windows (pinned download).
#   5. Ensure the sk key handle exists (`ssh-keygen -K`, touch+PIN) and is loaded.
#   6. Write ~/.config/dotfiles/ssh_agent.env, which ~/.bash_extra sources to
#      start the socat -> npiperelay relay and export SSH_AUTH_SOCK.
#
# validate_setup.sh diagnoses the relay and points here; it never runs this.

set -uo pipefail

# --- Constants ---
MIN_SSH_VERSION="8.4"                  # ssh-keygen -K (resident-key recovery) needs >= 8.4
SK_KEY_NAME="id_ed25519_sk"
AGENT_SOCK="$HOME/.ssh/agent.sock"
ENV_FILE="$HOME/.config/dotfiles/ssh_agent.env"
WIN_PIPE="//./pipe/openssh-ssh-agent"
# npiperelay: pinned release + sha256. Bump both to upgrade (checksums.txt is
# published alongside each release).
NPIPERELAY_VERSION="v0.1.0"
NPIPERELAY_SHA256="6b9ef61ffd17c03507a9a3d54d815dceb3dae669ac67fc3bf4225d1e764ce5f6"
NPIPERELAY_URL="https://github.com/jstarks/npiperelay/releases/download/${NPIPERELAY_VERSION}/npiperelay_windows_amd64.zip"

# --- Colors (ANSI-C quoted) ---
RED=$'\033[0;31m'; GREEN=$'\033[0;32m'; YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'; BOLD=$'\033[1m'; NC=$'\033[0m'

print_header()  { [ "$QUIET" = true ] && return 0; printf "\n${BOLD}%s${NC}\n" "$1"; }
print_error()   { printf "${RED}ERROR: %s${NC}\n" "$1" >&2; }
print_success() { [ "$QUIET" = true ] && return 0; printf "${GREEN}OK: %s${NC}\n" "$1"; }
print_info()    { [ "$QUIET" = true ] && return 0; printf "${CYAN}INFO: %s${NC}\n" "$1"; }
print_warn()    { printf "${YELLOW}WARN: %s${NC}\n" "$1" >&2; }

# ============================================================================
#  Pure helpers
# ============================================================================

# Extract MAJOR.MINOR from an `ssh -V` string, or empty if unrecognised.
#   "OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2" -> 9.5
#   "OpenSSH_9.6p1, OpenSSL 3.0.13"             -> 9.6
parse_ssh_version() {
    if [[ "$1" =~ OpenSSH(_for_Windows)?_([0-9]+)\.([0-9]+) ]]; then
        echo "${BASH_REMATCH[2]}.${BASH_REMATCH[3]}"
    else
        echo ""
    fi
}

# 0 (true) if version $1 >= version $2, each "MAJOR.MINOR".
version_ge() {
    local a_major="${1%%.*}" a_minor="${1#*.}"
    local b_major="${2%%.*}" b_minor="${2#*.}"
    [[ "$a_minor" == "$1" ]] && a_minor=0
    [[ "$b_minor" == "$2" ]] && b_minor=0
    if (( a_major != b_major )); then (( a_major > b_major )); return; fi
    (( a_minor >= b_minor ))
}

# 0 (true) if `ssh-add -l` output contains a security-key entry.
agent_lists_sk() { grep -q 'ED25519-SK\|ECDSA-SK' <<< "$1"; }

# ============================================================================
#  Windows integration (powershell.exe)
# ============================================================================

# Guard: must be WSL.
check_wsl() {
    if ! grep -qi microsoft /proc/version 2>/dev/null || [ -z "${WSL_DISTRO_NAME:-}" ]; then
        print_error "Not running in WSL2 — this relay only makes sense inside WSL."
        exit 1
    fi
}

# Run a PowerShell command, stripping CRLF.
ps() { powershell.exe -NoProfile -Command "$1" 2>/dev/null | tr -d '\r'; }

# Run admin PowerShell in one elevated child (single UAC prompt).
ps_admin() {
    powershell.exe -NoProfile -Command \
        "Start-Process powershell -Verb RunAs -Wait -ArgumentList '-NoProfile','-Command','$1'" 2>/dev/null
}

# Windows %USERPROFILE% translated to a WSL path (e.g. /mnt/c/Users/me).
win_home_wsl() {
    local win; win=$(ps '$env:USERPROFILE')
    [ -z "$win" ] && return 1
    wslpath -u "$win" 2>/dev/null
}

ensure_socat() {
    if command -v socat >/dev/null 2>&1; then
        print_success "socat present"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then print_info "would: apt-get install socat"; return 0; fi
    print_info "Installing socat..."
    sudo apt-get -qq install -y socat && print_success "socat installed"
}

ensure_openssh() {
    local vstr ver
    vstr=$(ps 'ssh -V' 2>&1)               # ssh -V prints to stderr
    [ -z "$vstr" ] && vstr=$(powershell.exe -NoProfile -Command 'ssh -V' 2>&1 | tr -d '\r')
    ver=$(parse_ssh_version "$vstr")
    if [ -n "$ver" ] && version_ge "$ver" "$MIN_SSH_VERSION"; then
        print_success "Windows OpenSSH $ver (>= $MIN_SSH_VERSION)"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then print_info "would: install/upgrade Windows OpenSSH (have '${ver:-none}')"; return 0; fi
    print_warn "Windows OpenSSH is '${ver:-not found}' (need >= $MIN_SSH_VERSION) — installing..."
    OPENSSH_ADMIN_CMD="if (Get-Command winget -ErrorAction SilentlyContinue) { winget install --id Microsoft.OpenSSH.Beta --source winget --silent --accept-source-agreements --accept-package-agreements } else { Add-WindowsCapability -Online -Name OpenSSH.Client~~~~0.0.1.0 }"
}

# Ensure the Windows ssh-agent service is Automatic + running.
ensure_agent_service() {
    local start status
    start=$(ps '(Get-Service ssh-agent).StartType')
    status=$(ps '(Get-Service ssh-agent).Status')
    local svc_cmd=""
    [ "$start" != "Automatic" ] && svc_cmd+="Set-Service ssh-agent -StartupType Automatic; "
    [ "$status" != "Running" ]  && svc_cmd+="Start-Service ssh-agent; "

    # Nothing to do, and no OpenSSH install pending either.
    if [ -z "$svc_cmd" ] && [ -z "${OPENSSH_ADMIN_CMD:-}" ]; then
        print_success "Windows ssh-agent service Automatic + Running"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then
        print_info "would: elevate to ${OPENSSH_ADMIN_CMD:+install OpenSSH; }${svc_cmd:+configure ssh-agent service}"
        return 0
    fi
    print_info "Elevating (UAC) to configure Windows OpenSSH/agent..."
    ps_admin "${OPENSSH_ADMIN_CMD:+$OPENSSH_ADMIN_CMD; }$svc_cmd"
    print_success "Windows ssh-agent configured"
}

ensure_npiperelay() {
    local win_home; win_home=$(win_home_wsl) || { print_error "Could not resolve Windows home"; return 1; }
    NPIPERELAY_WSL="$win_home/.local/bin/npiperelay.exe"
    if [ -e "$NPIPERELAY_WSL" ]; then
        print_success "npiperelay.exe present"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then print_info "would: download npiperelay $NPIPERELAY_VERSION -> $NPIPERELAY_WSL"; return 0; fi
    print_info "Downloading npiperelay $NPIPERELAY_VERSION..."
    local tmp; tmp=$(mktemp -d)
    if ! curl -fsSL -o "$tmp/npr.zip" "$NPIPERELAY_URL"; then
        rm -rf "$tmp"; print_error "Failed to download npiperelay from $NPIPERELAY_URL"; return 1
    fi
    if ! echo "$NPIPERELAY_SHA256  $tmp/npr.zip" | sha256sum -c - >/dev/null 2>&1; then
        rm -rf "$tmp"; print_error "npiperelay checksum mismatch — refusing to install. Bump NPIPERELAY_SHA256 if you intended to upgrade."; return 1
    fi
    if unzip -o -q "$tmp/npr.zip" npiperelay.exe -d "$tmp"; then
        mkdir -p "$(dirname "$NPIPERELAY_WSL")"
        cp "$tmp/npiperelay.exe" "$NPIPERELAY_WSL"
        rm -rf "$tmp"
        print_success "npiperelay.exe installed -> $NPIPERELAY_WSL"
    else
        rm -rf "$tmp"
        print_error "Failed to extract npiperelay.exe from the archive."
        print_error "Place npiperelay.exe at $NPIPERELAY_WSL manually, or check the release asset."
        return 1
    fi
}

ensure_key_handle() {
    local win_home; win_home=$(win_home_wsl) || return 1
    local handle="$win_home/.ssh/$SK_KEY_NAME"
    if [ -e "$handle" ]; then
        print_success "sk key handle present on Windows"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then print_info "would: prompt for recover/generate/skip"; return 0; fi

    print_warn "No resident sk key handle found at Windows path: ~/.ssh/$SK_KEY_NAME"
    local choice
    while true; do
        printf "What would you like to do?\n"
        printf "  [r] Recover an existing resident key from YubiKey (ssh-keygen -K)\n"
        printf "  [g] Generate a new resident key on this YubiKey\n"
        printf "  [s] Skip for now (allows setup to continue)\n"
        read -r -p "> " choice
        case "$choice" in
            [Rr]* ) 
                print_info "Recovering resident sk key from YubiKey (touch + PIN)..."
                # Run in %USERPROFILE%\.ssh so -K writes the handle there. Run directly to avoid output buffering.
                powershell.exe -NoProfile -Command "Set-Location \$env:USERPROFILE\\.ssh; ssh-keygen -K"
                if [ -e "$handle" ]; then
                    print_success "sk key handle recovered"
                    return 0
                else
                    print_error "Key handle still missing — recovery failed."
                    return 1
                fi
                ;;
            [Gg]* )
                print_info "Generating new resident sk key (touch + PIN)..."
                # Generate directly into the expected path, no passphrase for the handle file. Run directly to avoid output buffering.
                powershell.exe -NoProfile -Command "ssh-keygen -t ed25519-sk -O resident -O application=ssh:wsl -f \$env:USERPROFILE\\.ssh\\$SK_KEY_NAME -N '\"\"'"
                if [ -e "$handle" ]; then
                    print_success "New sk key generated"
                    print_info "====================================================================="
                    print_info "ACTION REQUIRED: Since this is a new key, you must add it to GitHub:"
                    print_info "  1. Run this command to see your public key:"
                    print_info "     cat \"$handle.pub\""
                    print_info "  2. Copy the output and add it at https://github.com/settings/keys"
                    print_info "  3. Test your connection by opening a new shell and running:"
                    print_info "     ssh -T git@github.com"
                    print_info "====================================================================="
                    return 0
                else
                    print_error "Key generation failed."
                    return 1
                fi
                ;;
            [Ss]* )
                print_warn "Skipping YubiKey setup. The relay will start but no key will be loaded."
                return 0
                ;;
            * ) print_error "Please answer r, g, or s." ;;
        esac
    done
}

ensure_key_in_agent() {
    local win_home; win_home=$(win_home_wsl) || return 1
    local handle="$win_home/.ssh/$SK_KEY_NAME"
    if [ ! -e "$handle" ]; then
        print_warn "sk key handle missing; skipping ssh-add"
        return 0
    fi
    if agent_lists_sk "$(ps 'ssh-add -l')"; then
        print_success "sk key loaded in Windows agent"
        return 0
    fi
    if [ "$DRY_RUN" = true ]; then print_info "would: ssh-add the sk key into the Windows agent"; return 0; fi
    print_info "Adding sk key to the Windows agent..."
    ps "ssh-add \$env:USERPROFILE\\.ssh\\$SK_KEY_NAME"
}

write_env_file() {
    if [ "$DRY_RUN" = true ]; then print_info "would: write $ENV_FILE"; return 0; fi
    mkdir -p "$(dirname "$ENV_FILE")"
    cat > "$ENV_FILE" <<EOF
# Generated by wsl_ssh_agent.sh — do not edit by hand.
# Sourced by ~/.bash_extra to relay the Windows ssh-agent (YubiKey) into WSL.
NPIPERELAY="${NPIPERELAY_WSL:-}"
export SSH_AUTH_SOCK="$AGENT_SOCK"
EOF
    print_success "Wrote $ENV_FILE"
}

main() {
    print_header "WSL ssh-agent relay (YubiKey)$([ "$DRY_RUN" = true ] && echo ' — DRY RUN')"
    check_wsl
    OPENSSH_ADMIN_CMD=""
    ensure_socat
    ensure_openssh           # may set OPENSSH_ADMIN_CMD for the elevated step
    ensure_agent_service     # single UAC; also runs any pending OpenSSH install
    ensure_npiperelay
    ensure_key_handle
    ensure_key_in_agent
    write_env_file
    print_header "Done"
    print_info "Open a new shell (or: . ~/.bash_extra) to start the relay, then: ssh-add -l"
}

show_help() {
    cat <<EOF
${BOLD}Usage:${NC} $(basename "$0") [OPTIONS]

Provision or repair the YubiKey ssh-agent relay for this WSL distro.
Idempotent — safe to re-run; only does work for what is actually missing.

${BOLD}Options:${NC}
  -h, --help       Show this help and exit
  -d, --dry-run    Show what would happen without changing anything
  -q, --quiet      Suppress success and info messages (errors and prompts remain visible)

${BOLD}Requirements:${NC}
  - WSL2 with powershell.exe interop
  - A YubiKey with a resident ed25519-sk key (generated with -O resident)
  - Windows admin rights (one UAC prompt) to configure the ssh-agent service

${BOLD}Notes:${NC}
  - Interactive steps (UAC, YubiKey touch/PIN) fire only when needed.
  - validate_setup.sh diagnoses the relay and points here to fix it.
EOF
}

# When sourced (e.g. by tests), stop here so only the helpers are defined.
[[ "${BASH_SOURCE[0]}" != "$0" ]] && return 0

DRY_RUN=false
QUIET=false
while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) show_help; exit 0 ;;
        -d|--dry-run|--dryrun) DRY_RUN=true ;;
        -q|--quiet) QUIET=true ;;
        -*) print_error "Unknown option: $1"; echo "Run '$(basename "$0") --help' for usage." >&2; exit 1 ;;
        *)  print_error "Unexpected argument: $1"; exit 1 ;;
    esac
    shift
done

main
