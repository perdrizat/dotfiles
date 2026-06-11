#!/bin/bash
# check_ipv6.sh — Diagnose IPv6 issues (WSL-aware), read-only
#
# Typical trigger: package managers (bun i, npm i, apt) hang — usually a broken
# IPv6 path being preferred over a working IPv4 one (Happy Eyeballs stalls).
# Checks every layer (interface, routing, ICMP, TCP/TLS, DNS, WSL boot config)
# and prints fix hints. Every probe runs behind a timeout: this script never hangs.
# Each check guards its prerequisite tool/file and is skipped (not failed) when absent.
#
# Exit codes: 0 = IPv6 healthy, 1 = issues found
#
# ── NETWORK CHANGE LOG (newest first) ────────────────────────────────────────────────
# Append a dated line whenever we change anything network-related, so the next debugging
# session reads history here instead of guessing through git. Confidence tags:
#   [H] confirmed (commit/diff/observed)   [M] inferred   [L] best guess
#
#   2026-06-11  Retired the wsl.conf static-IPv6 pin (was added 2026-04-07).          [H]
#               The pinned EUI-64 addr 2a02:16a:b205:0:3e6a:d2ff:fe7a:6a81 blackholes
#               under WSL mirrored networking — only Windows-mirrored SLAAC addresses
#               (flagged 'nodad noprefixroute') receive return traffic. Symptom: every
#               dual-stack client (bun i / npm i) hangs. Fix: dropped the live address,
#               merged+cleaned /etc/wsl.conf [boot] (removed the commented pin leftover),
#               deleted the WSL_BOOT block from setup.sh, and inverted the
#               validate_setup.sh check into a regression guard (pin present = fault).
#   ~2026-04→06 WSL networking became 'mirrored' at some point in this window; that is   [L]
#               what turned the once-helpful pin into a blackhole. Exact date unknown.
#   2026-04-07  Added the wsl.conf [boot] pin (commit 7c8ea45) on host bequiet:        [H]
#               `ip -6 addr change …b205:0:…3e6a /64 preferred_lft/valid_lft forever`
#               AND `ip -6 addr del …b205:1:…3e6a /64`. So two things: pin the b205:0:
#               EUI-64 address as permanently preferred, and delete a stale address on a
#               *different* prefix (b205:1:).
#               Motivation (commit had no body): a second/stale prefix b205:1: was        [M]
#               appearing and the box needed one stable, predictable preferred address.
#
#   Related but separate subsystem (not diagnosed by this script): the WSL YubiKey
#   ssh-agent relay (socat + npiperelay) — see wsl_ssh_agent.sh (2026-06-05, 2026-06-11). [H]
# ──────────────────────────────────────────────────────────────────────────────────────

set -uo pipefail

IFACE="${1:-eth0}"
PROBE_V6_DNS=(2606:4700:4700::1111 2001:4860:4860::8888)   # Cloudflare, Google anycast
PROBE_V4_DNS=1.1.1.1
PROBE_HOST=registry.npmjs.org                               # what bun/npm actually talk to

# Known address from the (now-retired) wsl.conf static-IPv6 pin. It may legitimately
# return in future (e.g. if WSL is switched off mirrored networking), so the doctor does
# not assume it is bad — it TESTS whether traffic sourced from it works. See setup.sh.
RETIRED_ADDR="2a02:16a:b205:0:3e6a:d2ff:fe7a:6a81"
STALE_PREFIX="2a02:16a:b205:1:"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; CYAN='\033[0;36m'; GRAY='\033[0;90m'; BOLD='\033[1m'; NC='\033[0m'

issues=0
print_header() { echo ""; printf "${BOLD}%s${NC}\n" "$1"; }
print_row()    { printf "  %-32s %b  %s\n" "$1" "$2" "$3"; }
pass() { print_row "$1" "${GREEN}✓ $2${NC}" "${3:-}"; }
warn() { print_row "$1" "${YELLOW}⚠ $2${NC}" "${3:-}"; issues=$((issues+1)); }
fail() { print_row "$1" "${RED}✗ $2${NC}" "${3:-}"; issues=$((issues+1)); }
skip() { print_row "$1" "${GRAY}– skipped${NC}" "${2:-}"; }            # missing prereq: not a fault

have() { command -v "$1" >/dev/null 2>&1; }
# Run with a wall-clock cap when `timeout` exists, else run bare (dropping the duration arg)
if have timeout; then TO() { timeout "$@"; }; else TO() { shift; "$@"; }; fi

echo ""
printf "${BOLD}IPv6 Doctor${NC} — %s on %s\n" "$(hostname)" "$IFACE"
is_wsl() { grep -qi microsoft /proc/version 2>/dev/null; }

# State shared across sections
addrs=""
pin_present=false; pin_blackholed=unknown
ping_available=false; v6_ping_ok=false
v6_http_attempted=false; v6_http_ok=false

# --- 1. Kernel / interface ---
print_header "Interface ($IFACE)"

if have sysctl; then
    v6_disabled=$(sysctl -n "net.ipv6.conf.${IFACE}.disable_ipv6" 2>/dev/null || echo "?")
    if [ "$v6_disabled" = "0" ]; then
        pass "IPv6 enabled (sysctl)" "Yes" ""
    else
        fail "IPv6 enabled (sysctl)" "disable_ipv6=$v6_disabled" "sysctl -w net.ipv6.conf.${IFACE}.disable_ipv6=0"
    fi
else
    skip "IPv6 enabled (sysctl)" "sysctl not installed"
fi

if have ip; then
    addrs=$(ip -6 addr show dev "$IFACE" 2>/dev/null)
    global_ok=$(echo "$addrs" | grep 'scope global' | grep -vc deprecated)
    global_dep=$(echo "$addrs" | grep 'scope global' | grep -c deprecated)
    if [ "$global_ok" -gt 0 ]; then
        pass "Global address (preferred)" "$global_ok present" "$(echo "$addrs" | grep 'scope global' | grep -v deprecated | awk '{print $2}' | paste -sd' ')"
    else
        fail "Global address (preferred)" "None" "no usable source address — IPv6 is down for outbound"
    fi
    # Deprecated addrs alongside a working preferred one are normal SLAAC privacy rotation —
    # only a concern when they are ALL that's left (kernel has no preferred source to pick).
    if [ "$global_dep" -gt 0 ] && [ "$global_ok" -eq 0 ]; then
        fail "Deprecated global addrs" "$global_dep, none preferred" "only deprecated addrs left — outbound IPv6 has no valid source"
    fi

    if echo "$addrs" | grep -q "$STALE_PREFIX"; then
        fail "Stale prefix leftover" "Present" "${STALE_PREFIX}… — old leftover, remove it (drop any wsl.conf ip-6 pin)"
    fi

    # Retired static pin: present? then TEST it rather than condemn it.
    if echo "$addrs" | grep -qw "$RETIRED_ADDR"; then
        pin_present=true
        if have ping; then
            if ping -6 -c1 -W2 -I "$RETIRED_ADDR" "${PROBE_V6_DNS[0]}" >/dev/null 2>&1; then
                pin_blackholed=false
                pass "Static pin address" "Present & working" "$RETIRED_ADDR"
            else
                pin_blackholed=true
                fail "Static pin address" "Present & BLACKHOLED" "$RETIRED_ADDR — drop it: sudo ip -6 addr del $RETIRED_ADDR/64 dev $IFACE"
            fi
        else
            warn "Static pin address" "Present (untested)" "$RETIRED_ADDR — ping unavailable to verify"
        fi
    fi
else
    skip "Addresses" "iproute2 (ip) not installed — interface/routing checks unavailable"
fi

# --- 2. Routing ---
print_header "Routing"

if have ip; then
    gw=$(ip -6 route show default dev "$IFACE" 2>/dev/null | awk '/^default/ {print $3; exit}')
    if [ -n "$gw" ]; then
        pass "Default route" "Present" "via $gw"
        neigh_state=$(ip -6 neigh show dev "$IFACE" to "$gw" 2>/dev/null | awk '{print $NF}')
        case "$neigh_state" in
            REACHABLE|STALE|DELAY|PROBE) pass "Gateway neighbor" "$neigh_state" "$gw" ;;
            FAILED|INCOMPLETE)           fail "Gateway neighbor" "$neigh_state" "router not answering neighbor discovery" ;;
            *)                           warn "Gateway neighbor" "No entry" "not resolved yet (may be fine)" ;;
        esac
    else
        fail "Default route" "Missing" "no IPv6 default route — RA lost? try: sudo ip -6 route add default via <gw> dev $IFACE"
    fi

    src=$(ip -6 route get "${PROBE_V6_DNS[0]}" 2>/dev/null | grep -oP 'src \K\S+')
    if [ -n "$src" ]; then
        if echo "$addrs" | grep "$src" | grep -q deprecated; then
            fail "Source addr selection" "$src" "kernel picked a DEPRECATED source — connections will blackhole"
        else
            pass "Source addr selection" "OK" "src $src"
        fi
    else
        fail "Source addr selection" "Unroutable" "ip -6 route get found no path"
    fi
else
    skip "Routing" "iproute2 (ip) not installed"
fi

# --- 3. Reachability (ICMP) ---
print_header "Reachability (ICMP, 2s timeout)"

if have ping; then
    ping_available=true
    for dst in "${PROBE_V6_DNS[@]}"; do
        rtt=$(ping -6 -c1 -W2 "$dst" 2>/dev/null | grep -oP 'time=\K[0-9.]+')
        if [ -n "$rtt" ]; then
            pass "ping6 $dst" "${rtt}ms" ""
            v6_ping_ok=true
        else
            fail "ping6 $dst" "No reply" ""
        fi
    done
    rtt4=$(ping -4 -c1 -W2 "$PROBE_V4_DNS" 2>/dev/null | grep -oP 'time=\K[0-9.]+')
    if [ -n "$rtt4" ]; then
        pass "ping4 $PROBE_V4_DNS (baseline)" "${rtt4}ms" ""
    else
        warn "ping4 $PROBE_V4_DNS (baseline)" "No reply" "IPv4 also broken — problem is not IPv6-specific"
    fi

    # When the default path fails, try each candidate source address — discriminates
    # "one address blackholes" (fix: drop it) from "all of IPv6 is down" (upstream)
    if ! $v6_ping_ok && [ -n "$addrs" ]; then
        print_header "Per-source probes (which source address still works?)"
        while IFS= read -r cand; do
            [ -n "$cand" ] || continue
            if ping -6 -c1 -W2 -I "$cand" "${PROBE_V6_DNS[0]}" >/dev/null 2>&1; then
                pass "src $cand" "Works" "kernel default chose a different (broken) source!"
            else
                fail "src $cand" "No reply" ""
            fi
        done < <(echo "$addrs" | grep 'scope global' | awk '{print $2}' | cut -d/ -f1)
    fi
else
    skip "ICMP probes" "ping not installed — reachability not measured"
fi

# WSL: ask the Windows host itself — separates "router/ISP outage" from "WSL networking broken"
WIN_PING=/mnt/c/Windows/System32/ping.exe
if is_wsl && [ -x "$WIN_PING" ]; then
    if TO 8 "$WIN_PING" -6 -n 1 -w 2000 "${PROBE_V6_DNS[0]}" >/dev/null 2>&1; then
        pass "Windows host IPv6" "Works" "any outage is WSL-internal (mirroring/forwarding)"
    else
        fail "Windows host IPv6" "Down too" "router/ISP level — nothing to fix inside WSL"
    fi
elif is_wsl; then
    skip "Windows host IPv6" "ping.exe not reachable at $WIN_PING"
fi

# --- 4. DNS ---
print_header "DNS ($PROBE_HOST)"

if have getent; then
    aaaa=$(TO 5 getent ahostsv6 "$PROBE_HOST" 2>/dev/null | awk '{print $1}' | sort -u | head -3 | paste -sd' ')
    a=$(TO 5 getent ahostsv4 "$PROBE_HOST" 2>/dev/null | awk '{print $1}' | sort -u | head -3 | paste -sd' ')
    [ -n "$a" ]    && pass "A records" "Resolved" "$a"       || fail "A records" "Failed" "DNS itself is broken"
    [ -n "$aaaa" ] && pass "AAAA records" "Resolved" "$aaaa" || warn "AAAA records" "None" "host has no IPv6 — clients will use IPv4 (not a fault)"
else
    aaaa=""; a=""
    skip "DNS records" "getent not installed"
fi

# --- 5. TCP/TLS (what bun/npm actually do) ---
print_header "HTTPS to $PROBE_HOST (8s timeout)"

if have curl; then
    if [ -n "$aaaa" ]; then
        v6_http_attempted=true
        out=$(curl -6 -sS -m 8 -o /dev/null -w '%{http_code} %{time_total} %{remote_ip}' "https://$PROBE_HOST/" 2>&1)
        if [[ "$out" =~ ^[23] ]]; then
            v6_http_ok=true
            pass "curl -6" "HTTP ${out%% *}" "$(echo "$out" | awk '{printf "%.0fms via %s", $2*1000, $3}')"
        else
            fail "curl -6" "Failed" "$out"
        fi
    fi
    out=$(curl -4 -sS -m 8 -o /dev/null -w '%{http_code} %{time_total} %{remote_ip}' "https://$PROBE_HOST/" 2>&1)
    if [[ "$out" =~ ^[23] ]]; then
        pass "curl -4 (baseline)" "HTTP ${out%% *}" "$(echo "$out" | awk '{printf "%.0fms via %s", $2*1000, $3}')"
    else
        fail "curl -4 (baseline)" "Failed" "$out"
    fi
else
    skip "HTTPS probes" "curl not installed"
fi

# --- 6. WSL boot config ---
if is_wsl; then
    print_header "WSL Configuration (/etc/wsl.conf)"

    if [ -f /etc/wsl.conf ]; then
        # The static-addr pin is retired. An active ip-6-addr boot command is judged by
        # whether the address it pins actually works (pin_blackholed, from the Interface
        # section): blackholed → the bug; working → deliberate-only; untested → caution.
        if grep -qE '^[[:space:]]*command[[:space:]]*=.*ip -6 addr' /etc/wsl.conf 2>/dev/null; then
            case "$pin_blackholed" in
                true)  fail "[boot] IPv6 addr pin" "Active & blackholed" "this pin is the bun-hang bug — remove the command, then wsl.exe --shutdown" ;;
                false) warn "[boot] IPv6 addr pin" "Active & working" "functional now, but pins a static addr that blackholes under mirrored networking — keep only deliberately" ;;
                *)     warn "[boot] IPv6 addr pin" "Active (effect untested)" "pins a static addr; verify it isn't blackholing (Interface section)" ;;
            esac
        elif grep -qE '^[[:space:]]*#.*command[[:space:]]*=.*ip -6 addr' /etc/wsl.conf 2>/dev/null; then
            warn "[boot] IPv6 addr pin" "Commented leftover" "harmless but stale — delete the line"
        else
            pass "[boot] IPv6 addr pin" "None" "good — no static pin to blackhole"
        fi

        boot_sections=$(grep -c '^\[boot\]' /etc/wsl.conf 2>/dev/null)
        if [ "${boot_sections:-0}" -gt 1 ]; then
            fail "wsl.conf sanity" "$boot_sections [boot] sections" "WSL honors only one — merge them"
        else
            pass "wsl.conf sanity" "OK" ""
        fi
    else
        skip "wsl.conf" "/etc/wsl.conf does not exist"
    fi
fi

# --- Verdict ---
echo ""
v6_broken=false
{ $ping_available && ! $v6_ping_ok; } && v6_broken=true
{ $v6_http_attempted && ! $v6_http_ok; } && v6_broken=true

if [ "$issues" -eq 0 ]; then
    printf "${GREEN}${BOLD}IPv6 looks healthy.${NC} If bun/npm still hangs, it is not the network layer of this box.\n\n"
    exit 0
fi
printf "${RED}${BOLD}%d issue(s) found.${NC}\n" "$issues"
if $v6_broken; then
    printf "IPv6 is ${BOLD}unreachable${NC} — dual-stack clients (bun, npm) will stall until their IPv6 attempts time out.\n"
    printf "Workaround while fixing: ${CYAN}force IPv4${NC}, e.g.  bun i  →  NODE_OPTIONS=--dns-result-order=ipv4first bun i\n"
fi
is_wsl && printf "After editing /etc/wsl.conf, apply with: ${CYAN}wsl.exe --shutdown${NC} (from Windows), then reopen the shell.\n"
echo ""
exit 1
