#!/usr/bin/env python3
"""Run the repository's complete local validation and test suite."""

from __future__ import annotations

import argparse
import re
import shutil
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SHELL_ROOTS = (ROOT / "src", ROOT / "scripts", ROOT / "tests")
PUBLIC_PATH_ROOTS = (ROOT / "README.md", ROOT / "docs", ROOT / "src", ROOT / "scripts")
MACHINE_PATH = re.compile(r"(?:home|Users)[/\\][A-Za-z0-9_.-]+[/\\]")


class CheckError(RuntimeError):
    """Raised when a repository check cannot be completed."""


def relative(path: Path) -> str:
    return path.relative_to(ROOT).as_posix()


def run(label: str, command: list[str]) -> None:
    print(f"==> {label}", flush=True)
    result = subprocess.run(command, cwd=ROOT)
    if result.returncode != 0:
        raise CheckError(f"check failed ({result.returncode}): {' '.join(command)}")


def shell_files() -> list[Path]:
    return sorted(
        path
        for root in SHELL_ROOTS
        for path in root.rglob("*.sh")
        if path.is_file()
    )


def python_files() -> list[Path]:
    return sorted(
        path
        for path in ROOT.rglob("*.py")
        if path.is_file()
        and ".git" not in path.parts
        and "__pycache__" not in path.parts
    )


def test_files() -> list[Path]:
    return sorted(
        path
        for path in (ROOT / "tests").rglob("*")
        if path.is_file()
        and path.name.endswith((".test.sh", ".test.ps1", ".test.py"))
    )


def test_command(path: Path) -> tuple[str, list[str]] | None:
    if path.name.endswith(".test.sh"):
        bash = shutil.which("bash")
        return ("Bash", [bash, str(path)]) if bash else None
    if path.name.endswith(".test.py"):
        return ("Python", [sys.executable, str(path)])
    if path.name.endswith(".test.ps1"):
        powershell = shutil.which("pwsh") or shutil.which("powershell")
        return (
            ("PowerShell", [powershell, "-NoLogo", "-NoProfile", "-File", str(path)])
            if powershell
            else None
        )
    return None


def repository_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        if (
            path.is_file()
            and ".git" not in path.parts
            and "__pycache__" not in path.parts
        ):
            files.append(path)
    return sorted(files)


def check_text_hygiene() -> None:
    for path in repository_files():
        try:
            text = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue

        for line_number, line in enumerate(text.splitlines(), start=1):
            if line.rstrip(" \t") != line:
                raise CheckError(f"trailing whitespace: {relative(path)}:{line_number}")

        if path in PUBLIC_PATH_ROOTS or any(
            path.is_relative_to(root) for root in PUBLIC_PATH_ROOTS if root.is_dir()
        ):
            if MACHINE_PATH.search(text):
                raise CheckError(f"machine-specific path example: {relative(path)}")


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--strict",
        action="store_true",
        help="fail when ShellCheck is not installed",
    )
    args = parser.parse_args(argv)

    try:
        run("validate manifests", [sys.executable, "tools/validate-manifests.py"])
        run("verify generated artifacts", [sys.executable, "tools/build.py", "--check"])

        for path in python_files():
            run(f"Python syntax: {relative(path)}", [sys.executable, "-m", "py_compile", str(path)])

        for path in shell_files():
            run(f"Bash syntax: {relative(path)}", ["bash", "-n", str(path)])

        shellcheck = shutil.which("shellcheck")
        if shellcheck:
            run(
                "ShellCheck",
                [shellcheck, *[str(path) for path in shell_files()]],
            )
        elif args.strict:
            raise CheckError("ShellCheck is required in strict mode but was not found")
        else:
            print("==> ShellCheck skipped (install ShellCheck or use --strict)", flush=True)

        tests = test_files()
        if not tests:
            raise CheckError("no test scripts found under tests/")
        for path in tests:
            command_info = test_command(path)
            if command_info is None:
                message = f"test skipped (runtime unavailable): {relative(path)}"
                if args.strict:
                    raise CheckError(message)
                print(f"==> {message}", flush=True)
                continue
            runtime_name, command = command_info
            run(f"{runtime_name} test: {relative(path)}", command)

        check_text_hygiene()
        print("==> repository text hygiene", flush=True)
    except CheckError as exc:
        print(f"check error: {exc}", file=sys.stderr)
        return 1

    print("All checks passed.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
