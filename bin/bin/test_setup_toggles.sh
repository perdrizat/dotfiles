#!/bin/bash
# Tests for the INSTALL_* toggles in setup.sh / validate_setup.sh.
#
# Toggles are driven through a temp config via DOTFILES_CONFIG so the tests are
# hermetic — independent of the machine's own ~/dotfiles/.setup.conf.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOTFILES_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
PASS=0
FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected '$expected', got '$actual'"
        ((FAIL++))
    fi
}

assert_contains() {
    local label="$1" output="$2" expected="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected output to contain '$expected'"
        ((FAIL++))
    fi
}

assert_not_contains() {
    local label="$1" output="$2" unexpected="$3"
    if ! echo "$output" | grep -q "$unexpected"; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected output NOT to contain '$unexpected'"
        ((FAIL++))
    fi
}

# Run validate_setup.sh against a temp config containing the given toggle lines.
validate_with() {
    local conf; conf=$(mktemp)
    printf '%s\n' "$@" > "$conf"
    DOTFILES_CONFIG="$conf" bash "$SCRIPT_DIR/validate_setup.sh" 2>&1
    rm -f "$conf"
}

# --- Test 1: setup.sh binds toggles, defaulting to false on an empty config ---
echo "Test 1: setup.sh binds toggles (default false on empty config)"
empty_conf=$(mktemp)
export DOTFILES_CONFIG="$empty_conf"
source "$DOTFILES_DIR/setup.sh"
unset DOTFILES_CONFIG
rm -f "$empty_conf"
assert_eq "INSTALL_CLAUDE bound" "false" "$INSTALL_CLAUDE"
assert_eq "INSTALL_GEMINI_CLI bound" "false" "$INSTALL_GEMINI_CLI"
assert_eq "INSTALL_NODE bound" "false" "$INSTALL_NODE"

# --- Test 2: Claude Code CLI row gated on INSTALL_CLAUDE ---
# (Match "Claude Code CLI", not "Claude Code" — the always-on "Claude Code
#  Configuration" settings section contains the latter regardless of the toggle.)
echo "Test 2: Claude Code CLI row gated on INSTALL_CLAUDE"
assert_contains "Claude Code CLI row present" "$(validate_with INSTALL_CLAUDE=true)" "Claude Code CLI"
assert_not_contains "Claude Code CLI row absent" "$(validate_with INSTALL_CLAUDE=false)" "Claude Code CLI"

# --- Test 3: Gemini CLI section gated on INSTALL_GEMINI_CLI ---
echo "Test 3: Gemini CLI section gated on INSTALL_GEMINI_CLI"
assert_contains "Gemini CLI header present" "$(validate_with INSTALL_GEMINI_CLI=true)" "Gemini CLI"
assert_not_contains "Gemini CLI header absent" "$(validate_with INSTALL_GEMINI_CLI=false)" "Gemini CLI"

# --- Test 4: docker group check gated on INSTALL_DOCKER ---
echo "Test 4: docker group check gated on INSTALL_DOCKER"
assert_contains "docker group check present" "$(validate_with INSTALL_DOCKER=true)" "docker group"
assert_not_contains "docker group check absent" "$(validate_with INSTALL_DOCKER=false)" "docker group"

# --- Test 5: pnpm check gated on INSTALL_NODE ---
echo "Test 5: pnpm check gated on INSTALL_NODE"
assert_contains "pnpm check present" "$(validate_with INSTALL_NODE=true)" "pnpm"
assert_not_contains "pnpm check absent" "$(validate_with INSTALL_NODE=false)" "pnpm"

# --- Test 6: Firefox checks gated on INSTALL_FF / INSTALL_FF_ESR ---
# For now either toggle installs & checks BOTH the latest and ESR builds.
echo "Test 6: Firefox checks gated on INSTALL_FF / INSTALL_FF_ESR"
out_ff=$(validate_with INSTALL_FF=true)
assert_contains "INSTALL_FF shows Firefox latest" "$out_ff" "Firefox (latest)"
assert_contains "INSTALL_FF also shows Firefox ESR" "$out_ff" "Firefox ESR"
out_esr=$(validate_with INSTALL_FF_ESR=true)
assert_contains "INSTALL_FF_ESR shows Firefox latest" "$out_esr" "Firefox (latest)"
assert_contains "INSTALL_FF_ESR also shows Firefox ESR" "$out_esr" "Firefox ESR"
assert_not_contains "neither toggle shows Firefox" "$(validate_with INSTALL_FF=false)" "Firefox"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
