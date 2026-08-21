#!/usr/bin/env python3
"""Validate all script manifests without changing generated artifacts."""

from __future__ import annotations

import sys

from build import BuildError, discover_manifests


def main() -> int:
    try:
        manifests = discover_manifests()
    except BuildError as exc:
        print(f"manifest error: {exc}", file=sys.stderr)
        return 1

    for manifest in manifests:
        print(f"valid: {manifest['id']} {manifest['version']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
