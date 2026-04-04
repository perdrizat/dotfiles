#!/bin/bash
# Tests for INSTALL_CLAUDE and INSTALL_GEMINI_CLI toggles in setup.sh / validate_setup.sh

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

# --- Test 1: setup.sh defines INSTALL_CLAUDE toggle ---
echo "Test 1: INSTALL_CLAUDE toggle exists in setup.sh"
source "$DOTFILES_DIR/setup.sh"
assert_eq "INSTALL_CLAUDE is defined" "true" "$INSTALL_CLAUDE"

# --- Test 2: setup.sh defines INSTALL_GEMINI_CLI toggle ---
echo "Test 2: INSTALL_GEMINI_CLI toggle exists in setup.sh"
assert_eq "INSTALL_GEMINI_CLI is defined" "false" "$INSTALL_GEMINI_CLI"

# --- Test 3: validate_setup.sh shows Claude Code section when INSTALL_CLAUDE=true ---
echo "Test 3: validate output includes Claude Code when toggle is true"
output=$(INSTALL_CLAUDE=true bash "$SCRIPT_DIR/validate_setup.sh" 2>&1)
assert_contains "Claude Code header present" "$output" "Claude Code"

# --- Test 4: validate_setup.sh hides Claude Code section when INSTALL_CLAUDE=false ---
echo "Test 4: validate output excludes Claude Code when toggle is false"
# Override toggle by injecting it after source line
output=$(INSTALL_CLAUDE=false bash "$SCRIPT_DIR/validate_setup.sh" 2>&1)
assert_not_contains "Claude Code header absent" "$output" "Claude Code"

# --- Test 5: validate_setup.sh shows Gemini CLI section when INSTALL_GEMINI_CLI=true ---
echo "Test 5: validate output includes Gemini CLI when toggle is true"
output=$(INSTALL_GEMINI_CLI=true bash "$SCRIPT_DIR/validate_setup.sh" 2>&1)
assert_contains "Gemini CLI header present" "$output" "Gemini CLI"

# --- Test 6: validate_setup.sh hides Gemini CLI section when INSTALL_GEMINI_CLI=false ---
echo "Test 6: validate output excludes Gemini CLI when toggle is false"
output=$(INSTALL_GEMINI_CLI=false bash "$SCRIPT_DIR/validate_setup.sh" 2>&1)
assert_not_contains "Gemini CLI header absent" "$output" "Gemini CLI"

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
