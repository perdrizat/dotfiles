#!/bin/bash
# Tests for pre_commit_check.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHECK_SCRIPT="$SCRIPT_DIR/pre_commit_check.sh"
PASS=0
FAIL=0

setup_repo() {
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    git init -q
    echo "# Project" > README.md
    echo "# Changelog" > CHANGELOG.md
    echo "# Contributing" > CONTRIBUTING.md
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

# --- Test 1: Shows changed files ---
echo "Test 1: reports changed files"
setup_repo
echo "change" >> README.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "shows README.md in changed files" "$output" "README.md"
teardown_repo

# --- Test 2: Flags CHANGELOG.md as stale when not modified ---
echo "Test 2: flags stale CHANGELOG.md"
setup_repo
echo "change" >> README.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "flags CHANGELOG.md" "$output" "CHANGELOG.md"
assert_contains "shows stale warning" "$output" "not updated"
teardown_repo

# --- Test 3: No stale warning when CHANGELOG.md is modified ---
echo "Test 3: no stale warning when CHANGELOG.md updated"
setup_repo
echo "change" >> README.md
echo "update" >> CHANGELOG.md
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_not_contains "no stale CHANGELOG warning" "$output" "CHANGELOG.md.*not updated"
teardown_repo

# --- Test 4: Warns about .env in diff ---
echo "Test 4: warns about secrets"
setup_repo
echo "SECRET=abc123" > .env
git add .env
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "flags .env" "$output" ".env"
teardown_repo

# --- Test 5: Warns about console.log in diff ---
echo "Test 5: warns about debug remnants"
setup_repo
echo 'console.log("debug")' > app.js
git add app.js
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "flags console.log" "$output" "console.log"
teardown_repo

# --- Test 6: Clean tree → reports nothing to commit ---
echo "Test 6: clean tree"
setup_repo
output=$(bash "$CHECK_SCRIPT" 2>&1)
assert_contains "reports clean" "$output" "Nothing to commit"
teardown_repo

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
