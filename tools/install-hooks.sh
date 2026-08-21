#!/usr/bin/env bash
# ==============================================================================
# tools/install-hooks.sh
#
# Install local Git pre-commit and commit-msg hooks.
# - pre-commit: runs repository check suite before every commit.
# - commit-msg: validates Conventional Commits format.
# ==============================================================================

set -euo pipefail

REPO_ROOT="$(cd -- "$(dirname -- "$0")/.." && pwd -P)"
HOOKS_DIR="$REPO_ROOT/.git/hooks"

if [[ ! -d "$REPO_ROOT/.git" ]]; then
    printf 'Error: .git directory not found at %s\n' "$REPO_ROOT" >&2
    exit 1
fi

mkdir -p "$HOOKS_DIR"

# 1. pre-commit hook
cat >"$HOOKS_DIR/pre-commit" <<'PRE_COMMIT_EOF'
#!/usr/bin/env bash
# fiscripts pre-commit hook: runs tools/check.py before committing.

set -e
echo "Running fiscripts check suite before commit..."
python3 tools/check.py
PRE_COMMIT_EOF

chmod +x "$HOOKS_DIR/pre-commit"
printf 'Installed pre-commit hook at %s/pre-commit\n' "$HOOKS_DIR"

# 2. commit-msg hook
cat >"$HOOKS_DIR/commit-msg" <<'COMMIT_MSG_EOF'
#!/usr/bin/env bash
# fiscripts commit-msg hook: validates Conventional Commits message format.

set -euo pipefail

COMMIT_MSG_FILE="$1"
COMMIT_MSG=$(head -n 1 "$COMMIT_MSG_FILE")

# Allow merge commits or fixup commits
if [[ "$COMMIT_MSG" =~ ^Merge || "$COMMIT_MSG" =~ ^fixup! || "$COMMIT_MSG" =~ ^squash! ]]; then
    exit 0
fi

# Conventional Commits regex pattern
CONVENTIONAL_PATTERN="^(feat|fix|docs|style|refactor|perf|test|build|ci|chore|revert)(\([a-z0-9_-]+\))?!?: .+$"

if ! [[ "$COMMIT_MSG" =~ $CONVENTIONAL_PATTERN ]]; then
    printf '\n\033[0;31mError: Invalid commit message format.\033[0m\n' >&2
    printf 'Your commit message was:\n  \033[0;33m%s\033[0m\n\n' "$COMMIT_MSG" >&2
    printf 'fiscripts requires Conventional Commits format, for example:\n' >&2
    printf '  feat(node-modules-cleaner): add live search filter\n' >&2
    printf '  fix(node-modules-cleaner): handle terminal resize signal\n' >&2
    printf '  docs: update contributing guide\n' >&2
    printf '  test: add assertion helper\n' >&2
    printf '  chore: update build script\n\n' >&2
    printf 'Allowed types: feat, fix, docs, style, refactor, perf, test, build, ci, chore, revert\n' >&2
    exit 1
fi
COMMIT_MSG_EOF

chmod +x "$HOOKS_DIR/commit-msg"
printf 'Installed commit-msg hook at %s/commit-msg\n' "$HOOKS_DIR"
printf 'Git hooks successfully installed.\n'
