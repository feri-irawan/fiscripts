# AI agent contribution guide

This file is the primary instruction source for AI coding agents working in
this repository. Read it before inspecting or changing files. `CLAUDE.md`
intentionally references this file instead of duplicating these rules.

## Mission

`fiscripts` publishes small, auditable, standalone utilities. Every published
artifact must be understandable, safe by default, independently runnable, and
documented for its exact runtime and operating-system support.

## Before changing anything

1. Read this file, `README.md`, `CONTRIBUTING.md`, and the relevant script docs.
2. Inspect `git status --short --branch` and preserve existing user changes.
3. Identify the source entrypoint, manifest, generated artifact, tests, and
   documentation before editing.
4. Do not commit, push, tag, publish, or open external communication unless the
   user explicitly requests it.

## Repository rules

- Edit source under `src/`; do not manually edit generated files under
  `scripts/`.
- Keep `manifest.json`, source, generated artifact, tests, docs, and changelog
  changes consistent.
- Dependencies in manifests are build-time files only. Published artifacts
  must not fetch code, source another repository file, or perform hidden
  network activity at runtime.
- Commits, PR titles, and changes must adhere to the Conventional Commits
  specification (`feat:`, `fix:`, `docs:`, `chore:`, `test:`, `refactor:`).
- Destructive behavior must use temporary fixtures in tests and require safe,
  explicit user confirmation in the utility itself.
- Never use real user directories, broad destructive commands, or secrets in
  tests and examples.
- Preserve user changes that do not belong to the current task.

## Runtime and platform model

Treat these as separate dimensions:

- `runtime`: the shell/interpreter, such as `bash`, `powershell`, `cmd`, or
  `python`.
- `supported_os`: operating systems on which that implementation is supported
  and tested, such as `linux`, `macos`, or `windows`.
- `variant`: the implementation identity when one logical script has multiple
  runtime/platform implementations.

Do not claim that a script works on an OS or shell that was not tested. If the
target runtime is unavailable, run all applicable static/build checks, state
which tests were skipped, and leave cross-platform verification to the matching
CI runner or a real target environment.

## Canonical commands

From the repository root:

```bash
# Rebuild generated artifacts after source or manifest changes.
python3 tools/build.py

# Run the complete locally available check suite.
python3 tools/check.py

# Require all local quality tools, including ShellCheck.
python3 tools/check.py --strict
```

The full checker discovers tests using the repository test naming convention.
For a new runtime, add its test runner/linter integration to `tools/check.py`
and its CI job before declaring the runtime supported.

## Completion checklist

Before reporting completion:

- Source syntax and generated artifacts are valid.
- Relevant tests pass against temporary fixtures.
- `python3 tools/build.py` was run when source or manifest files changed.
- `python3 tools/check.py` passes, or skipped tools/tests are explicitly
  reported.
- User documentation, safety limitations, platform support, and changelog are
  updated when behavior changed.
- No personal machine paths, secrets, untracked generated caches, or unrelated
  files were introduced.
