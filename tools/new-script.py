#!/usr/bin/env python3
"""Scaffold a new script structure across src, docs, tests, and manifest."""

from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
IDENTIFIER = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")

RUNTIME_EXTENSIONS = {
    "bash": "sh",
    "powershell": "ps1",
    "python": "py",
}


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("id", help="script id in kebab-case (e.g. cache-cleaner)")
    parser.add_argument(
        "--runtime",
        default="bash",
        choices=list(RUNTIME_EXTENSIONS.keys()),
        help="runtime interpreter (default: bash)",
    )
    parser.add_argument(
        "--description",
        default="A standalone utility.",
        help="short description for manifest and documentation",
    )
    parser.add_argument(
        "--destructive",
        action="store_true",
        help="mark the script as destructive in manifest",
    )
    parser.add_argument(
        "--os",
        nargs="+",
        default=["linux"],
        help="supported operating systems (default: linux)",
    )
    args = parser.parse_args(argv)

    script_id = args.id
    if not IDENTIFIER.fullmatch(script_id):
        print(f"error: script id must be kebab-case: {script_id!r}", file=sys.stderr)
        return 1

    runtime = args.runtime
    ext = RUNTIME_EXTENSIONS[runtime]
    src_dir = ROOT / "src" / runtime / script_id
    doc_path = ROOT / "docs" / "scripts" / f"{script_id}.md"
    test_path = ROOT / "tests" / runtime / f"{script_id}.test.{ext}"
    output_path = ROOT / "scripts" / runtime / f"{script_id}.{ext}"

    if src_dir.exists():
        print(f"error: source directory already exists: {src_dir.relative_to(ROOT)}", file=sys.stderr)
        return 1

    src_dir.mkdir(parents=True, exist_ok=True)
    doc_path.parent.mkdir(parents=True, exist_ok=True)
    test_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.parent.mkdir(parents=True, exist_ok=True)

    # 1. Manifest
    manifest_data = {
        "id": script_id,
        "variant": runtime,
        "version": "1.0.0",
        "runtime": runtime,
        "entrypoint": f"main.{ext}",
        "output": f"scripts/{runtime}/{script_id}.{ext}",
        "supported_os": args.os,
        "dependencies": [],
        "destructive": args.destructive,
        "description": args.description,
    }
    manifest_path = src_dir / "manifest.json"
    manifest_path.write_text(json.dumps(manifest_data, indent=2) + "\n", encoding="utf-8")
    print(f"created {manifest_path.relative_to(ROOT)}")

    # 2. Main Entrypoint
    entrypoint_path = src_dir / f"main.{ext}"
    if runtime == "bash":
        entrypoint_content = f"""#!/usr/bin/env bash

# {script_id}.sh
# Version: 1.0.0
# Runtime: Bash

set -euo pipefail

readonly SCRIPT_NAME="${{SCRIPT_NAME_OVERRIDE:-{script_id}.sh}}"
readonly SCRIPT_VERSION="1.0.0"

usage() {{
    cat <<EOF
Usage:
  $SCRIPT_NAME [OPTIONS]

Options:
  -h, --help       Show this help message and exit.
  -v, --version    Show the script version and exit.

Description:
  {args.description}

Version: $SCRIPT_VERSION
EOF
}}

if (( $# == 0 )); then
    usage
    exit 0
fi

case "$1" in
    -h|--help)
        usage
        exit 0
        ;;
    -v|--version)
        printf '%s %s\\n' "$SCRIPT_NAME" "$SCRIPT_VERSION"
        exit 0
        ;;
esac

printf 'Running %s...\\n' "$SCRIPT_NAME"
"""
    elif runtime == "python":
        entrypoint_content = f"""#!/usr/bin/env python3
\"\"\"{args.description}\"\"\"

from __future__ import annotations

import argparse
import sys

SCRIPT_VERSION = "1.0.0"


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("-v", "--version", action="version", version=f"%(prog)s {{SCRIPT_VERSION}}")
    args = parser.parse_args(argv)
    print("Running {script_id}...")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
"""
    else:
        entrypoint_content = f"# {script_id}.ps1\nWrite-Host 'Running {script_id}...'\n"

    entrypoint_path.write_text(entrypoint_content, encoding="utf-8")
    print(f"created {entrypoint_path.relative_to(ROOT)}")

    # 3. Documentation
    doc_content = f"""# {script_id}

{args.description}

## Support

- Runtime: {runtime.capitalize()}
- Variant: `{runtime}`
- Tested platform: {', '.join(args.os)}
- Version: `1.0.0`
- Distribution artifact: [`scripts/{runtime}/{script_id}.{ext}`](../../scripts/{runtime}/{script_id}.{ext})

## Usage

```bash
./scripts/{runtime}/{script_id}.{ext} --help
```
"""
    doc_path.write_text(doc_content, encoding="utf-8")
    print(f"created {doc_path.relative_to(ROOT)}")

    # 4. Test
    if runtime == "bash":
        test_content = f"""#!/usr/bin/env bash

set -Eeuo pipefail

readonly TEST_ROOT="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
readonly SCRIPT="$TEST_ROOT/scripts/bash/{script_id}.sh"

source "$TEST_ROOT/tests/_lib/assert.sh"

test_suite "{script_id} Baseline Checks"

test_case "published artifact exists and is executable"
assert_file_exists "$SCRIPT"
[[ -x "$SCRIPT" ]] || fail "published artifact is not executable: $SCRIPT"
pass

test_case "bash syntax checks"
bash -n "$TEST_ROOT/src/bash/{script_id}/main.sh"
bash -n "$SCRIPT"
pass

test_case "CLI --help flag output"
help_output=$("$SCRIPT" --help)
assert_contains "$help_output" "Usage:"
pass

report_and_exit
"""
    else:
        test_content = f"# Test placeholder for {script_id}\n"

    test_path.write_text(test_content, encoding="utf-8")
    print(f"created {test_path.relative_to(ROOT)}")

    print("\nNext steps:")
    print("  1. Implement script logic in", entrypoint_path.relative_to(ROOT))
    print("  2. Build generated artifact: python3 tools/build.py")
    print("  3. Run validation tests:    python3 tools/check.py --strict")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
