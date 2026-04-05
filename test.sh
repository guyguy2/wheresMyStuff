#!/usr/bin/env zsh
# test.sh - Automated tests for wms
# Uses a temp data dir so real data is never touched.

set -euo pipefail

readonly WMS="./wms"
readonly TEST_DIR=$(mktemp -d)
readonly TEST_DATA="$TEST_DIR/wms"
readonly TEST_FILE="$TEST_DATA/items.tsv"

export XDG_DATA_HOME="$TEST_DIR"

passed=0
failed=0
total=0

cleanup() {
    rm -rf "$TEST_DIR"
}
trap cleanup EXIT

pass() {
    (( ++passed ))
    (( ++total ))
    print "  PASS: $1"
}

fail() {
    (( ++failed ))
    (( ++total ))
    print "  FAIL: $1"
    [[ -n "${2:-}" ]] && print "        $2"
}

assert_eq() {
    local label="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$label"
    else
        fail "$label" "expected='$expected' actual='$actual'"
    fi
}

assert_contains() {
    local label="$1" haystack="$2" needle="$3"
    if [[ "$haystack" == *"$needle"* ]]; then
        pass "$label"
    else
        fail "$label" "output does not contain '$needle'"
    fi
}

assert_exit() {
    local label="$1" expected_code="$2"
    shift 2
    local actual_code=0
    "$@" >/dev/null 2>&1 || actual_code=$?
    if [[ "$actual_code" -eq "$expected_code" ]]; then
        pass "$label"
    else
        fail "$label" "expected exit $expected_code, got $actual_code"
    fi
}

# Count data lines (excluding header)
data_lines() {
    tail -n +2 "$TEST_FILE" | wc -l | tr -d ' '
}

# Validate TSV: every line has exactly 5 fields (4 tabs)
tsv_valid() {
    local line_num=0
    while IFS= read -r line; do
        (( line_num++ ))
        local tab_count=$(printf '%s' "$line" | tr -cd '\t' | wc -c | tr -d ' ')
        if [[ "$tab_count" -ne 4 ]]; then
            print "TSV invalid at line $line_num: expected 4 tabs, got $tab_count"
            return 1
        fi
    done < "$TEST_FILE"
    return 0
}

# ------------------------------------------------------------------
print "\n=== wms test suite ===\n"

# --- init ---
print "[init]"
$WMS help >/dev/null 2>&1
if [[ -f "$TEST_FILE" ]]; then
    pass "init creates data file"
else
    fail "init creates data file"
fi

header=$(head -1 "$TEST_FILE")
assert_eq "header is correct" $'name\tlocation\tcategory\ttags\tnotes' "$header"

# --- add (non-interactive via flags) ---
print "\n[add]"
$WMS add "Passport" -l "Desk drawer" -c "Documents" -t "travel id" -n "expires 2030" </dev/null
assert_eq "add creates 1 item" "1" "$(data_lines)"

$WMS add "TV Remote" -l "Living room" -c "Electronics" -t "samsung" -n "" </dev/null
assert_eq "add creates 2nd item" "2" "$(data_lines)"

if tsv_valid; then
    pass "TSV valid after adds"
else
    fail "TSV valid after adds"
fi

# --- add with special characters ---
print "\n[add - special chars]"
$WMS add 'C++ Book' -l 'Shelf [3]' -c 'Books' -t 'programming' -n 'has a . in title' </dev/null
assert_eq "add with regex chars" "3" "$(data_lines)"

if tsv_valid; then
    pass "TSV valid after special char add"
else
    fail "TSV valid after special char add"
fi

# --- add with backslashes ---
print "\n[add - backslashes]"
$WMS add 'Config File' -l 'C:\Users\docs' -c 'Files' -t 'windows' -n 'path has backslash' </dev/null
assert_eq "add with backslash in location" "4" "$(data_lines)"

# Verify the backslash survived
local stored_line=$(tail -1 "$TEST_FILE")
assert_contains "backslash preserved in TSV" "$stored_line" 'C:\Users\docs'

# --- ls ---
print "\n[ls]"
local ls_out=$($WMS ls 2>&1)
assert_contains "ls shows Passport" "$ls_out" "Passport"
assert_contains "ls shows TV Remote" "$ls_out" "TV Remote"

# --- find ---
print "\n[find]"
local find_out=$($WMS find passport 2>&1)
assert_contains "find passport" "$find_out" "Passport"

find_out=$($WMS find travel id 2>&1)
assert_contains "find AND (travel + id)" "$find_out" "Passport"

# find with regex metacharacters
find_out=$($WMS find 'C++' 2>&1)
assert_contains "find with regex chars (C++)" "$find_out" "C++ Book"

find_out=$($WMS find '[3]' 2>&1)
assert_contains "find with brackets ([3])" "$find_out" "Shelf [3]"

# --- find no match ---
print "\n[find - no match]"
local find_none
find_none=$($WMS find "zzzznotfound" 2>&1) || true
assert_contains "find no match message" "$find_none" "No items found"

# --- find exit code on no match ---
print "\n[find - exit code]"
assert_exit "find returns non-zero on no match" 1 $WMS find "zzzznotfound"

# --- help ---
print "\n[help]"
local help_out=$($WMS help 2>&1)
assert_contains "help mentions add" "$help_out" "add"
assert_contains "help mentions find" "$help_out" "find"

# --- TSV integrity after all operations ---
print "\n[integrity]"
if tsv_valid; then
    pass "TSV valid at end of test run"
else
    fail "TSV valid at end of test run"
fi

# Check no empty lines crept in
local empty_lines=$(grep -c '^$' "$TEST_FILE" || true)
assert_eq "no empty lines in TSV" "0" "$empty_lines"

# ------------------------------------------------------------------
print "\n=== Results: $passed passed, $failed failed, $total total ===\n"

[[ $failed -eq 0 ]]
