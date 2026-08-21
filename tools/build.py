#!/usr/bin/env python3
"""Build standalone script artifacts from manifest-driven sources."""

from __future__ import annotations

import argparse
import json
import os
import re
import stat
import sys
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
SRC_ROOT = ROOT / "src"
IDENTIFIER = re.compile(r"^[a-z0-9]+(?:-[a-z0-9]+)*$")
SEMVER = re.compile(r"^\d+\.\d+\.\d+(?:[-+][0-9A-Za-z.-]+)?$")


class BuildError(RuntimeError):
    """Raised when a manifest or build artifact is invalid."""


def repo_relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def ensure_inside(path: Path, parent: Path, label: str) -> Path:
    resolved = path.resolve()
    parent_resolved = parent.resolve()
    try:
        resolved.relative_to(parent_resolved)
    except ValueError as exc:
        raise BuildError(f"{label} escapes {repo_relative(parent)}: {path}") from exc
    return resolved


def load_manifest(path: Path) -> dict[str, Any]:
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise BuildError(f"cannot read manifest {repo_relative(path)}: {exc}") from exc
    if not isinstance(data, dict):
        raise BuildError(f"{repo_relative(path)} must contain a JSON object")

    required = {
        "id",
        "variant",
        "version",
        "runtime",
        "entrypoint",
        "output",
        "supported_os",
        "dependencies",
        "destructive",
    }
    missing = sorted(required - data.keys())
    if missing:
        raise BuildError(f"{repo_relative(path)} is missing: {', '.join(missing)}")
    if not isinstance(data["id"], str) or not IDENTIFIER.fullmatch(data["id"]):
        raise BuildError(f"{repo_relative(path)} has an invalid id")
    if path.parent.name != data["id"]:
        raise BuildError(
            f"manifest id {data['id']!r} does not match directory {path.parent.name!r}"
        )
    if not isinstance(data["version"], str) or not SEMVER.fullmatch(data["version"]):
        raise BuildError(f"{repo_relative(path)} has an invalid semantic version")
    if not isinstance(data["runtime"], str) or not IDENTIFIER.fullmatch(data["runtime"]):
        raise BuildError(f"{repo_relative(path)} has an invalid runtime")
    if not isinstance(data["variant"], str) or not IDENTIFIER.fullmatch(data["variant"]):
        raise BuildError(f"{repo_relative(path)} has an invalid variant")
    runtime_root = ensure_inside(SRC_ROOT / data["runtime"], SRC_ROOT, "runtime source")
    if not runtime_root.is_dir():
        raise BuildError(f"runtime source directory does not exist: {data['runtime']}")
    if not isinstance(data["supported_os"], list) or not data["supported_os"] or not all(
        isinstance(item, str) and item for item in data["supported_os"]
    ):
        raise BuildError(f"{repo_relative(path)} has invalid supported_os")
    for field in ("entrypoint", "output"):
        if not isinstance(data[field], str) or not data[field]:
            raise BuildError(f"{repo_relative(path)} has an invalid {field}")
    if not isinstance(data["dependencies"], list) or not all(
        isinstance(item, str) and item for item in data["dependencies"]
    ):
        raise BuildError(f"{repo_relative(path)} has invalid dependencies")
    if not isinstance(data["destructive"], bool):
        raise BuildError(f"{repo_relative(path)} has invalid destructive flag")

    entrypoint = ensure_inside(path.parent / data["entrypoint"], path.parent, "entrypoint")
    if not entrypoint.is_file():
        raise BuildError(f"entrypoint does not exist: {repo_relative(entrypoint)}")

    if data["runtime"] == "bash":
        source = entrypoint.read_text(encoding="utf-8")
        version_match = re.search(
            r'^readonly SCRIPT_VERSION="([^"]+)"$', source, re.MULTILINE
        )
        if version_match and version_match.group(1) != data["version"]:
            raise BuildError(
                f"{repo_relative(entrypoint)} version {version_match.group(1)!r} "
                f"does not match manifest version {data['version']!r}"
            )

    output = ensure_inside(ROOT / data["output"], ROOT / "scripts", "output")
    if output == (ROOT / "scripts").resolve():
        raise BuildError(f"output must be a file path: {data['output']}")
    if output.exists() and output.is_dir():
        raise BuildError(f"output must be a file path: {data['output']}")

    dependency_paths: list[Path] = []
    seen_dependencies: set[Path] = set()
    for dependency in data["dependencies"]:
        dep_path = ensure_inside(SRC_ROOT / dependency, SRC_ROOT, "dependency")
        ensure_inside(dep_path, runtime_root, "dependency")
        if not dep_path.is_file():
            raise BuildError(f"dependency does not exist: {dependency}")
        if dep_path in seen_dependencies:
            raise BuildError(f"duplicate dependency: {dependency}")
        if dep_path == entrypoint:
            raise BuildError(f"entrypoint cannot also be a dependency: {dependency}")
        seen_dependencies.add(dep_path)
        dependency_paths.append(dep_path)

    data["_manifest_path"] = path
    data["_entrypoint_path"] = entrypoint
    data["_output_path"] = output
    data["_dependency_paths"] = dependency_paths
    return data


def discover_manifests() -> list[dict[str, Any]]:
    manifests = sorted(SRC_ROOT.rglob("manifest.json"))
    if not manifests:
        raise BuildError("no manifests found under src/")

    loaded = [load_manifest(path) for path in manifests]
    ids: dict[tuple[str, str], Path] = {}
    outputs: dict[Path, Path] = {}
    for manifest in loaded:
        manifest_id = manifest["id"]
        manifest_key = (manifest_id, manifest["variant"])
        output = manifest["_output_path"]
        if manifest_key in ids:
            raise BuildError(
                f"duplicate manifest id/variant {manifest_key!r}: "
                f"{repo_relative(ids[manifest_key])} and "
                f"{repo_relative(manifest['_manifest_path'])}"
            )
        if output in outputs:
            raise BuildError(
                f"duplicate output {repo_relative(output)}: "
                f"{repo_relative(outputs[output])} and "
                f"{repo_relative(manifest['_manifest_path'])}"
            )
        ids[manifest_key] = manifest["_manifest_path"]
        outputs[output] = manifest["_manifest_path"]
    return loaded


def without_shebang(text: str) -> str:
    if text.startswith("#!"):
        return text.split("\n", 1)[1] if "\n" in text else ""
    return text


def build_bash(manifest: dict[str, Any]) -> str:
    parts = [
        "#!/usr/bin/env bash",
        "",
        f"# Generated by tools/build.py from {repo_relative(manifest['_manifest_path'])}.",
        f"# Source version: {manifest['version']}",
        "",
    ]
    for dependency, dep_path in zip(manifest["dependencies"], manifest["_dependency_paths"]):
        parts.extend(
            [
                f"# Begin dependency: {dependency}",
                without_shebang(dep_path.read_text(encoding="utf-8")).rstrip(),
                f"# End dependency: {dependency}",
                "",
            ]
        )

    entrypoint = manifest["_entrypoint_path"]
    parts.extend(
        [
            f"# Begin entrypoint: {repo_relative(entrypoint)}",
            without_shebang(entrypoint.read_text(encoding="utf-8")).rstrip(),
            f"# End entrypoint: {repo_relative(entrypoint)}",
            "",
        ]
    )
    return "\n".join(parts)


def build_artifact(manifest: dict[str, Any]) -> str:
    runtime = manifest["runtime"]
    if runtime == "bash":
        return build_bash(manifest)
    if manifest["dependencies"]:
        raise BuildError(
            f"runtime {runtime!r} has dependencies but no bundler is registered"
        )
    return manifest["_entrypoint_path"].read_text(encoding="utf-8")


def write_or_check(manifest: dict[str, Any], content: str, check: bool) -> None:
    output = manifest["_output_path"]
    existing = output.read_text(encoding="utf-8") if output.is_file() else None
    if check:
        if existing != content:
            raise BuildError(f"artifact is out of date: {repo_relative(output)}")
        if manifest["runtime"] == "bash" and not os.access(output, os.X_OK):
            raise BuildError(f"artifact is not executable: {repo_relative(output)}")
        return

    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(content, encoding="utf-8", newline="\n")
    if manifest["runtime"] == "bash":
        current_mode = stat.S_IMODE(output.stat().st_mode)
        output.chmod(current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    print(f"built {repo_relative(output)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify that committed artifacts match their sources",
    )
    args = parser.parse_args(argv)

    try:
        manifests = discover_manifests()
        for manifest in manifests:
            write_or_check(manifest, build_artifact(manifest), args.check)
    except BuildError as exc:
        print(f"build error: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
