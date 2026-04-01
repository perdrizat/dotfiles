#!/bin/bash
# Tests for check_changelog.sh
# Uses a temporary git repo to simulate different scenarios.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/check_changelog.sh"
PASS=0
FAIL=0

setup_repo() {
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    git init -q
    echo "# Project" > README.md
    echo "# Changelog" > CHANGELOG.md
    git add -A && git commit -q -m "init"
}

teardown_repo() {
    cd /
    rm -rf "$TMPDIR"
}

assert_contains() {
    local label="$1" output="$2" expected="$3"
    if echo "$output" | grep -q "$expected"; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected output to contain '$expected'"
        echo "        got: $output"
        ((FAIL++))
    fi
}

assert_empty() {
    local label="$1" output="$2"
    if [ -z "$output" ]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected no output"
        echo "        got: $output"
        ((FAIL++))
    fi
}

# --- Test 1: Files changed, CHANGELOG.md NOT updated → should warn ---
echo "Test 1: warn when files changed but CHANGELOG.md is clean"
setup_repo
echo "change" >> README.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "outputs CHANGELOG reminder" "$output" "CHANGELOG"
teardown_repo

# --- Test 2: Files changed AND CHANGELOG.md updated → no warning ---
echo "Test 2: no warning when CHANGELOG.md is also modified"
setup_repo
echo "change" >> README.md
echo "update" >> CHANGELOG.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_empty "no output" "$output"
teardown_repo

# --- Test 3: No changes at all → no warning ---
echo "Test 3: no warning when working tree is clean"
setup_repo
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_empty "no output" "$output"
teardown_repo

# --- Test 4: Not a git repo → no warning (silent) ---
echo "Test 4: silent outside a git repo"
TMPDIR=$(mktemp -d)
cd "$TMPDIR"
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_empty "no output" "$output"
cd /
rm -rf "$TMPDIR"

# --- Test 5: Only CHANGELOG.md changed → no warning ---
echo "Test 5: no warning when only CHANGELOG.md changed"
setup_repo
echo "update" >> CHANGELOG.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_empty "no output" "$output"
teardown_repo

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
