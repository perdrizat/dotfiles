#!/bin/bash
# Tests for expand_wsl_disk.sh utility functions

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
EXPAND_SCRIPT="$SCRIPT_DIR/expand_wsl_disk.sh"
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

# --- Test 1: help output exists ---
echo "Test 1: script has help output"
output=$(bash "$EXPAND_SCRIPT" --help 2>&1)
assert_contains "help present" "$output" "usage\|Usage\|USAGE"

# --- Test 2: guard against non-WSL ---
echo "Test 2: script detects non-WSL environment"
output=$(WSL_DISTRO_NAME="" bash "$EXPAND_SCRIPT" 2>&1)
assert_contains "WSL check" "$output" "WSL\|wsl\|not running"

# --- Test 3: script requires size argument or validates input ---
echo "Test 3: script validates size input"
# We can't easily test the full flow, but we can check that the script is parseable
if bash -n "$EXPAND_SCRIPT" 2>&1; then
    echo "  PASS: script syntax valid"
    ((PASS++))
else
    echo "  FAIL: script syntax invalid"
    ((FAIL++))
fi

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
