#!/usr/bin/env bash
# ==============================================================================
# tests/_lib/assert.sh
#
# Standard Assertion and Test Reporting Framework for fiscripts Bash Tests.
# Provides structured assertions, colored pass/fail outputs, and summary counters.
# ==============================================================================

TESTS_RUN=0
TESTS_PASSED=0
TESTS_FAILED=0
CURRENT_SUITE=""
CURRENT_CASE=""

# Detect terminal colors
if [[ -z "${TERM:-}" || "${TERM:-dumb}" == "dumb" || -n "${NO_COLOR:-}" ]]; then
    _CLR_GREEN=''
    _CLR_RED=''
    _CLR_YELLOW=''
    _CLR_BOLD=''
    _CLR_RESET=''
else
    _CLR_GREEN=$'\033[0;32m'
    _CLR_RED=$'\033[0;31m'
    _CLR_YELLOW=$'\033[0;33m'
    _CLR_BOLD=$'\033[1m'
    _CLR_RESET=$'\033[0m'
fi

test_suite() {
    CURRENT_SUITE="$1"
    printf '\n%s==> Test Suite: %s%s\n' "$_CLR_BOLD" "$CURRENT_SUITE" "$_CLR_RESET"
}

test_case() {
    CURRENT_CASE="$1"
    ((TESTS_RUN += 1))
    printf '  • %s ... ' "$CURRENT_CASE"
}

pass() {
    ((TESTS_PASSED += 1))
    printf '%sPASSED%s\n' "$_CLR_GREEN" "$_CLR_RESET"
}

fail() {
    local reason="${1:-assertion failed}"
    ((TESTS_FAILED += 1))
    printf '%sFAILED%s\n' "$_CLR_RED" "$_CLR_RESET"
    printf '    %sError:%s %s\n' "$_CLR_RED" "$_CLR_RESET" "$reason" >&2
    if [[ -n "${2:-}" ]]; then
        printf '    %sDetails:%s %s\n' "$_CLR_YELLOW" "$_CLR_RESET" "$2" >&2
    fi
    exit 1
}

assert_eq() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-expected values to be equal}"
    if [[ "$expected" != "$actual" ]]; then
        fail "$msg" "Expected: '$expected', Got: '$actual'"
    fi
}

assert_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-expected text to contain substring}"
    if [[ "$haystack" != *"$needle"* ]]; then
        fail "$msg" "Missing substring: '$needle'"
    fi
}

assert_not_contains() {
    local haystack="$1"
    local needle="$2"
    local msg="${3:-expected text NOT to contain substring}"
    if [[ "$haystack" == *"$needle"* ]]; then
        fail "$msg" "Unexpectedly found substring: '$needle'"
    fi
}

assert_file_exists() {
    local path="$1"
    local msg="${2:-expected file to exist}"
    if [[ ! -f "$path" ]]; then
        fail "$msg" "File does not exist: $path"
    fi
}

assert_dir_exists() {
    local path="$1"
    local msg="${2:-expected directory to exist}"
    if [[ ! -d "$path" ]]; then
        fail "$msg" "Directory does not exist: $path"
    fi
}

assert_file_not_exists() {
    local path="$1"
    local msg="${2:-expected file not to exist}"
    if [[ -e "$path" && ! -d "$path" ]]; then
        fail "$msg" "File exists: $path"
    fi
}

assert_dir_not_exists() {
    local path="$1"
    local msg="${2:-expected directory not to exist}"
    if [[ -d "$path" ]]; then
        fail "$msg" "Directory exists: $path"
    fi
}

assert_symlink() {
    local path="$1"
    local msg="${2:-expected path to be a symlink}"
    if [[ ! -L "$path" ]]; then
        fail "$msg" "Path is not a symlink: $path"
    fi
}

assert_exit_code() {
    local expected="$1"
    local actual="$2"
    local msg="${3:-unexpected exit status}"
    if (( expected != actual )); then
        fail "$msg" "Expected exit code $expected, got $actual"
    fi
}

assert_matches() {
    local text="$1"
    local pattern="$2"
    local msg="${3:-expected text to match regular expression}"
    if ! [[ "$text" =~ $pattern ]]; then
        fail "$msg" "Text did not match pattern: '$pattern'"
    fi
}

assert_empty() {
    local value="$1"
    local msg="${2:-expected value to be empty}"
    if [[ -n "$value" ]]; then
        fail "$msg" "Expected empty, got: '$value'"
    fi
}

assert_not_empty() {
    local value="$1"
    local msg="${2:-expected value to not be empty}"
    if [[ -z "$value" ]]; then
        fail "$msg" "Expected non-empty value"
    fi
}

report_and_exit() {
    printf '\n%s-------------------------------------------------------%s\n' "$_CLR_BOLD" "$_CLR_RESET"
    if (( TESTS_FAILED == 0 )); then
        printf '%sALL %d TESTS PASSED SUCCESSFULLY.%s\n\n' "$_CLR_GREEN" "$TESTS_PASSED" "$_CLR_RESET"
        exit 0
    else
        printf '%sTEST SUITE FAILED (%d failed out of %d run).%s\n\n' "$_CLR_RED" "$TESTS_FAILED" "$TESTS_RUN" "$_CLR_RESET"
        exit 1
    fi
}
