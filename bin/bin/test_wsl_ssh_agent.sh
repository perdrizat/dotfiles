#!/bin/bash
# Tests for wsl_ssh_agent.sh — whole-script behavior + pure helper functions.
# The Windows/powershell.exe integration is not exercised here (it needs a real
# WSL+YubiKey host); we test the parsing/version logic and the guards.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SCRIPT="$SCRIPT_DIR/wsl_ssh_agent.sh"
PASS=0
FAIL=0

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" = "$expected" ]; then
        echo "  PASS: $label"; ((PASS++))
    else
        echo "  FAIL: $label — expected '$expected', got '$actual'"; ((FAIL++))
    fi
}

assert_contains() {
    local label="$1" output="$2" expected="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "  PASS: $label"; ((PASS++))
    else
        echo "  FAIL: $label — expected output to contain '$expected'"; ((FAIL++))
    fi
}

assert_true() {
    local label="$1"; shift
    if "$@"; then echo "  PASS: $label"; ((PASS++)); else echo "  FAIL: $label — expected success"; ((FAIL++)); fi
}

assert_false() {
    local label="$1"; shift
    if "$@"; then echo "  FAIL: $label — expected failure"; ((FAIL++)); else echo "  PASS: $label"; ((PASS++)); fi
}

# Run a snippet after sourcing the script (subshell isolates its `set -uo pipefail`).
src() { bash -c "source '$SCRIPT'; $1"; }

# --- Test 1: help output ---
echo "Test 1: script has help output"
assert_contains "help present" "$(bash "$SCRIPT" --help 2>&1)" "Usage\|usage\|USAGE"

# --- Test 2: guards against non-WSL ---
echo "Test 2: script detects non-WSL environment"
assert_contains "WSL guard" "$(WSL_DISTRO_NAME='' bash "$SCRIPT" 2>&1)" "WSL\|wsl"

# --- Test 3: syntax valid ---
echo "Test 3: script syntax valid"
if bash -n "$SCRIPT" 2>&1; then echo "  PASS: syntax valid"; ((PASS++)); else echo "  FAIL: syntax invalid"; ((FAIL++)); fi

# --- Test 4: parse_ssh_version extracts MAJOR.MINOR ---
echo "Test 4: parse_ssh_version"
assert_eq "Windows form" "9.5" "$(src 'parse_ssh_version "OpenSSH_for_Windows_9.5p1, LibreSSL 3.8.2"')"
assert_eq "Linux form"   "9.6" "$(src 'parse_ssh_version "OpenSSH_9.6p1, OpenSSL 3.0.13"')"
assert_eq "garbage"      ""    "$(src 'parse_ssh_version "not a version string"')"

# --- Test 5: version_ge compares MAJOR.MINOR ---
echo "Test 5: version_ge"
assert_true  "9.5 >= 8.4" src 'version_ge 9.5 8.4'
assert_true  "8.4 >= 8.4" src 'version_ge 8.4 8.4'
assert_false "8.2 >= 8.4" src 'version_ge 8.2 8.4'
assert_false "7.9 >= 8.4" src 'version_ge 7.9 8.4'

# --- Test 6: agent_lists_sk detects a security-key entry ---
echo "Test 6: agent_lists_sk"
assert_true  "matches ED25519-SK" src 'agent_lists_sk "256 SHA256:abc yubikey-github (ED25519-SK)"'
assert_false "no sk key"          src 'agent_lists_sk "256 SHA256:abc some-key (ED25519)"'

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
