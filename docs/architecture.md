# Repository architecture

This repository is designed for small, auditable utilities that can be copied
or executed from a pinned URL without downloading repository dependencies at
runtime.

## Runtime, variant, and operating-system model

Operating system and shell/interpreter are separate properties:

- `runtime` identifies how an artifact runs: `bash`, `powershell`, `cmd`,
  `python`, or another registered runtime.
- `supported_os` identifies where that implementation is supported and tested:
  `linux`, `macos`, `windows`, or another documented target.
- `variant` identifies a concrete implementation when one logical utility has
  multiple runtime/platform versions.

For example, a future PowerShell implementation can use the same logical id as
the Bash implementation while having its own manifest, artifact, tests, and
supported operating systems:

```text
src/bash/node-modules-cleaner/manifest.json
  runtime: bash       variant: bash       supported_os: [linux]

src/powershell/node-modules-cleaner/manifest.json
  runtime: powershell variant: powershell supported_os: [windows]
```

Artifacts remain visibly distinct:

```text
scripts/bash/node-modules-cleaner.sh
scripts/powershell/node-modules-cleaner.ps1
```

The user-facing documentation should group these variants under one logical
script page and clearly label each command and support matrix. A runtime is
not considered supported until its build, test runner, static checks, and CI
job are registered.

## Source and distribution flow

```text
src/<runtime>/<script-id>/
  manifest.json + entrypoint + internal dependencies
                |
                v
          tools/build.py
                |
                v
scripts/<runtime>/<script-id>.<ext>  ->  users and pinned raw URLs
                ^
                |
        tests + tools/check.py + CI
```

- `src/` is the maintainable source tree. It may contain internal runtime
  dependencies under `src/<runtime>/_lib/` (such as `colors.sh` or `format.sh`).
- `manifest.json` is the machine-readable contract for identity, variant,
  version, runtime, output, supported operating systems, dependencies, and
  destructive behavior.
- `scripts/` contains generated standalone artifacts. Users should be able to
  run an artifact without cloning the repository or accessing another file in
  the repository.
- `docs/` contains the user-facing security and operation contract for each
  script.
- `tests/` contains fixture-based tests. Test files use runtime-specific names
  such as `tests/bash/*.test.sh`, `tests/powershell/*.test.ps1`, or
  `tests/python/*.test.py`. Shared testing frameworks and PTY runners reside in
  `tests/_lib/` (such as `tests/_lib/assert.sh` and `tests/_lib/pty_runner.py`).
- `tools/` contains build, manifest, and repository validation code.

## Dependency rules

Dependencies listed in a manifest are build-time source files, not runtime
downloads. They must remain under the same runtime directory, appear in bundle
order, and never escape `src/`. A published artifact must not source a file
from the repository, fetch code from the network, or depend on the caller's
current directory. Shared runtime libraries reside in `src/<runtime>/_lib/`.

Adding a new runtime requires a bundler in `tools/build.py`, an artifact
validation strategy, syntax/lint support in `tools/check.py`, a test runner,
documentation, and CI coverage on the target OS. Do not add a dependency
format that only one script understands without documenting it here.

Developers do not need every target OS installed for every contribution. They
can run all platform-independent build and manifest checks locally and run any
test whose interpreter is available. Missing target runtimes are reported as
skipped in normal mode. Strict target validation belongs in the corresponding
CI job, container, virtual machine, or native machine; contributors must not
claim a skipped platform test passed.

## Versioning and releases

Scripts use semantic versions. The manifest version is checked against the
Bash entrypoint's `SCRIPT_VERSION` when that variable is present. A version
bump therefore updates the manifest, the source entrypoint, the generated
artifact, the script documentation, and `CHANGELOG.md` together.

Before a release:

1. Update the version and changelog.
2. Rebuild generated artifacts with `python3 tools/build.py`.
3. Run `python3 tools/check.py --strict`.
4. Review the generated artifact and safety-related documentation.
5. Create a signed or otherwise trusted Git tag such as `v1.1.0`.

Raw URL examples should use a tag or commit, never an unreviewed moving
branch, for destructive scripts.

## Adding a script

Use an all-lowercase kebab-case script id and keep the following pieces
together:

```text
src/<runtime>/<script-id>/manifest.json
docs/scripts/<script-id>.md
tests/<runtime>/<script-id>.test.<ext>
scripts/<runtime>/<script-id>.<ext>
```

The README catalog should link to the script documentation. The documentation
must state supported platforms, runtime requirements, external commands,
network behavior, destructive behavior, limitations, examples, and test
instructions.

## Dependency terminology

The published Bash artifact has no third-party package dependency and does not
download dependencies at runtime. It still depends on the Bash interpreter and
standard operating-system utilities such as `find`, `rm`, `du`, and `mktemp`.
The repository's development checks depend on Python 3.10+, Bash, Git, and
ShellCheck in strict/CI mode. Therefore “no third-party runtime dependencies”
is accurate; “zero dependencies” without qualification is not.

## AI-assisted development

[`AGENTS.md`](../AGENTS.md) is the canonical instruction file for AI coding
agents. [`CLAUDE.md`](../CLAUDE.md) references it for Claude Code compatibility.
Agents must preserve existing user changes, avoid unrequested commits or
publishing actions, use temporary fixtures for destructive tests, and report
platform tests that were skipped because a target runtime or OS was unavailable.
