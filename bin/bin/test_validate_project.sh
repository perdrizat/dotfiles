#!/bin/bash
# Tests for validate_project.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VALIDATE_SCRIPT="$SCRIPT_DIR/validate_project.sh"
PASS=0
FAIL=0

setup_project() {
    TMPDIR=$(mktemp -d)
    cd "$TMPDIR"
    git init -q
}

teardown_project() {
    cd /
    rm -rf "$TMPDIR"
}

assert_exit() {
    local label="$1" expected="$2" actual="$3"
    if [ "$actual" -eq "$expected" ]; then
        echo "  PASS: $label"
        ((PASS++))
    else
        echo "  FAIL: $label — expected exit $expected, got $actual"
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
        echo "        got: $output"
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
        echo "        got: $output"
        ((FAIL++))
    fi
}

# --- Test 1: Fully correct setup → exit 0 ---
echo "Test 1: all correct"
setup_project
echo "# Project" > CONTRIBUTING.md
ln -s CONTRIBUTING.md CLAUDE.md
ln -s CONTRIBUTING.md AGENTS.md
ln -s CONTRIBUTING.md GEMINI.md
printf "CLAUDE.md\nAGENTS.md\nGEMINI.md\n" > .gitignore
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 0" 0 $?
teardown_project

# --- Test 2: Missing CONTRIBUTING.md → fail ---
echo "Test 2: missing CONTRIBUTING.md"
setup_project
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 1" 1 $?
assert_contains "reports missing" "$output" "CONTRIBUTING.md"
teardown_project

# --- Test 3: CLAUDE.md is a regular file, not a symlink → fail ---
echo "Test 3: CLAUDE.md is a regular file"
setup_project
echo "# Project" > CONTRIBUTING.md
echo "# Wrong" > CLAUDE.md
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 1" 1 $?
assert_contains "reports CLAUDE.md issue" "$output" "CLAUDE.md"
teardown_project

# --- Test 4: Symlink exists but not in .gitignore → fail ---
echo "Test 4: symlinks present but not gitignored"
setup_project
echo "# Project" > CONTRIBUTING.md
ln -s CONTRIBUTING.md CLAUDE.md
ln -s CONTRIBUTING.md AGENTS.md
ln -s CONTRIBUTING.md GEMINI.md
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 1" 1 $?
assert_contains "reports gitignore issue" "$output" ".gitignore"
teardown_project

# --- Test 5: One symlink missing → fail, others still checked ---
echo "Test 5: GEMINI.md missing"
setup_project
echo "# Project" > CONTRIBUTING.md
ln -s CONTRIBUTING.md CLAUDE.md
ln -s CONTRIBUTING.md AGENTS.md
printf "CLAUDE.md\nAGENTS.md\nGEMINI.md\n" > .gitignore
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 1" 1 $?
assert_contains "reports GEMINI.md missing" "$output" "GEMINI.md"
assert_not_contains "CLAUDE.md not flagged" "$output" "CLAUDE.md.*Missing"
teardown_project

# --- Test 6: Symlink points to wrong target → fail ---
echo "Test 6: CLAUDE.md symlink points to wrong file"
setup_project
echo "# Project" > CONTRIBUTING.md
echo "# Other" > OTHER.md
ln -s OTHER.md CLAUDE.md
ln -s CONTRIBUTING.md AGENTS.md
ln -s CONTRIBUTING.md GEMINI.md
printf "CLAUDE.md\nAGENTS.md\nGEMINI.md\n" > .gitignore
output=$(bash "$VALIDATE_SCRIPT" 2>&1)
assert_exit "exit 1" 1 $?
assert_contains "reports wrong target" "$output" "CLAUDE.md"
teardown_project

# --- Summary ---
echo ""
echo "Results: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ] && exit 0 || exit 1
