#!/usr/bin/env bash
# ==============================================================================
# tests/bash/node-modules-cleaner.test.sh
#
# Integration and unit test suite for node-modules-cleaner.
# Uses tests/_lib/assert.sh and tests/_lib/pty_runner.py.
# ==============================================================================

set -Eeuo pipefail

TEST_ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
readonly TEST_ROOT
readonly SCRIPT="$TEST_ROOT/scripts/bash/node-modules-cleaner.sh"

# shellcheck source=/dev/null
source "$TEST_ROOT/tests/_lib/assert.sh"

test_suite "node-modules-cleaner Validation & CLI Options"

test_case "published artifact exists and is executable"
assert_file_exists "$SCRIPT"
[[ -x "$SCRIPT" ]] || fail "artifact is not executable"
pass

test_case "source and artifact bash syntax check"
bash -n "$TEST_ROOT/src/bash/node-modules-cleaner/main.sh"
bash -n "$SCRIPT"
pass

test_case "CLI --help flag output"
help_output=$("$SCRIPT" --help)
assert_contains "$help_output" "Usage:"
assert_contains "$help_output" "SCAN_ROOT"
# shellcheck disable=SC2016
assert_contains "$help_output" '"$HOME/Projects"'
assert_contains "$help_output" "--list"
assert_contains "$help_output" "--sort"
assert_contains "$help_output" "Selector controls:"
assert_not_contains "$help_output" "home/"
pass

test_case "no arguments displays help and exits 0"
no_arg_output=$("$SCRIPT")
assert_contains "$no_arg_output" "Usage:"
pass

test_case "CLI --version and -v flags"
version_output=$("$SCRIPT" --version)
assert_contains "$version_output" "node-modules-cleaner.sh 1.0.0"
short_version_output=$("$SCRIPT" -v)
assert_contains "$short_version_output" "node-modules-cleaner.sh 1.0.0"
pass

# Setup fixture workspace
fixture=$(mktemp -d "${TMPDIR:-/tmp}/fiscripts-nm-test.XXXXXX")
trap 'rm -rf -- "$fixture"' EXIT
scan_root="$fixture/project root"

mkdir -p \
    "$scan_root/project-alpha/node_modules/pkg/hidden-pkg/node_modules" \
    "$scan_root/project-beta/node_modules" \
    "$scan_root/service-gamma/node_modules"
ln -s "$scan_root/project-beta" "$scan_root/project-link"

test_suite "Safety Guards & Input Validation"

test_case "reject scan when scan_root is node_modules itself"
invalid_output=$("$SCRIPT" "$scan_root/project-alpha/node_modules" 2>&1 || true)
assert_contains "$invalid_output" "scan root cannot itself be a node_modules directory"
pass

test_case "reject scan when scan_root does not exist"
missing_output=$("$SCRIPT" "$scan_root/nonexistent" 2>&1 || true)
assert_contains "$missing_output" "not an existing directory"
pass

test_case "reject execution as root or sudo"
sudo_output=$(SUDO_USER=fixture-user SUDO_UID=1234 "$SCRIPT" "$scan_root" 2>&1 || true)
assert_contains "$sudo_output" "must not be run as root or through sudo"
pass

test_case "reject scan of filesystem root (/)"
root_scan_output=$("$SCRIPT" / 2>&1 || true)
assert_contains "$root_scan_output" "refusing to scan the filesystem root"
pass

test_suite "Non-Interactive Scan & Sorting"

test_case "--list non-interactive mode"
list_output=$("$SCRIPT" --list "$scan_root")
assert_contains "$list_output" "Found 3 eligible node_modules directories."
assert_contains "$list_output" "Estimated space that can be freed:"
assert_dir_exists "$scan_root/project-alpha/node_modules"
assert_dir_exists "$scan_root/project-beta/node_modules"
assert_dir_exists "$scan_root/service-gamma/node_modules"
pass

test_case "--dry-run alias mode"
dry_output=$("$SCRIPT" --dry-run "$scan_root")
assert_contains "$dry_output" "Estimated space that can be freed:"
pass

test_case "--sort size mode"
sort_size_output=$("$SCRIPT" --list --sort size "$scan_root")
assert_contains "$sort_size_output" "Estimated space that can be freed:"
pass

test_case "--sort name mode"
sort_name_output=$("$SCRIPT" --list --sort name "$scan_root")
assert_contains "$sort_name_output" "Estimated space that can be freed:"
pass

test_suite "Interactive Selector, Filtering & Deletion via PTY"

test_case "interactive cancel flow (q key)"
python3 - "$SCRIPT" "$scan_root" "$TEST_ROOT/tests/_lib" <<'PY'
from __future__ import annotations

import sys
from pathlib import Path

script, fixture, lib_dir = sys.argv[1:4]
sys.path.insert(0, lib_dir)
from pty_runner import run_interactive_flow

steps = [
    ("Selected: 0/3", "q"),
]
code, output = run_interactive_flow([script, fixture], steps)
assert code == 0, f"Expected code 0, got {code}"
assert "Cancelled. Nothing was deleted." in output, "Expected cancellation message"
assert "hidden-pkg" not in output, "Nested node_modules must be pruned from scan"
PY
pass

test_case "interactive search/filter and deletion flow"
python3 - "$SCRIPT" "$scan_root" "$TEST_ROOT/tests/_lib" <<'PY'
from __future__ import annotations

import os
import sys

script, fixture, lib_dir = sys.argv[1:4]
sys.path.insert(0, lib_dir)
from pty_runner import run_interactive_flow

# Step 1: Filter for 'beta' -> select all visible -> press enter -> confirm DELETE
steps = [
    ("Selected: 0/3", "/"),
    ("Enter filter query", "beta\r"),
    ("Filter: \"beta\"", "a"),
    ("Selected: 1/3", "\r"),
    ("Deletion review", ""),
    ("Type exactly", "DELETE\r"),
]
code, output = run_interactive_flow([script, fixture], steps)
assert code == 0, f"Expected code 0, got {code}"
assert "Successfully removed: 1" in output, f"Unexpected deletion summary: {output}"
assert not os.path.exists(os.path.join(fixture, "project-beta", "node_modules")), "project-beta was not deleted"
assert os.path.exists(os.path.join(fixture, "project-alpha", "node_modules")), "project-alpha should not be deleted"
assert os.path.exists(os.path.join(fixture, "service-gamma", "node_modules")), "service-gamma should not be deleted"
assert os.path.islink(os.path.join(fixture, "project-link")), "symlink was corrupted"
PY
pass

report_and_exit
