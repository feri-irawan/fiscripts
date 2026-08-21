# fiscripts

Auditable, standalone scripts for everyday developer and system tasks.

`fiscripts` is a collection of small utilities that are designed to be:

- safe by default;
- easy to inspect before execution;
- usable as standalone files;
- runnable from a pinned URL when appropriate;
- explicit about platform support, dependencies, and destructive behavior.

## Available scripts

| Script | Runtime | Variant | Tested platform | Version | Destructive |
| --- | --- | --- | --- | --- | --- |
| [node-modules-cleaner](docs/scripts/node-modules-cleaner.md) | Bash | `bash` | Linux | 1.0.0 | Yes, interactive |

## Quick start

Clone the repository and run the script locally:

```bash
git clone https://github.com/<OWNER>/fiscripts.git
cd fiscripts
./scripts/bash/node-modules-cleaner.sh "$HOME/Projects"
```

The positional argument is the **scan root**: an existing directory whose
descendants will be searched recursively. It can contain one project or many
projects. It is not a direct deletion target.

Other useful examples:

```bash
# Scan non-interactively (dry-run).
./scripts/bash/node-modules-cleaner.sh --list "$HOME/Projects"

# Sort by size (largest first).
./scripts/bash/node-modules-cleaner.sh --sort size "$HOME/Projects"

# Scan the current directory.
./scripts/bash/node-modules-cleaner.sh .

# Scan one project.
./scripts/bash/node-modules-cleaner.sh "$HOME/Projects/my-app"

# Paths with spaces must be quoted.
./scripts/bash/node-modules-cleaner.sh "$HOME/Archived Projects"
```

The script can also be executed directly from a URL. Review the file first and
prefer a tag or commit instead of a moving branch for automation:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/<OWNER>/fiscripts/v1.0.0/scripts/bash/node-modules-cleaner.sh \
  | bash -s -- "$HOME/Projects"
```

Do not pipe an unfamiliar destructive script to a shell without reviewing it.
The repository provides URL execution as a convenience, not as a substitute
for inspecting code and pinning a trusted revision.

## Repository architecture

```text
src/       Source code and internal runtime dependencies.
scripts/   Generated standalone artifacts intended for users and raw URLs.
docs/      Detailed documentation for each utility.
tests/     Fixture-based tests for source and published artifacts.
tools/     Manifest validation and deterministic artifact building.
```

Scripts may use internal dependencies under `src/` as the repository grows.
Operating system and runtime are tracked separately: a logical utility can
have Bash, PowerShell, Python, or other variants with different supported OS
lists. Each variant gets its own artifact, tests, and clearly labeled usage
documentation.
The build process bundles those dependencies into the corresponding file under
`scripts/`. Published artifacts must never require another repository file,
fetch a helper from the network, or depend on the caller's current directory.
Dependencies are declared as ordered source files in each manifest; the build
validator rejects duplicates, cross-runtime dependencies, duplicate outputs,
and duplicate script id/variant pairs.

## Development

Prerequisites for local development are **Python 3.10+**, **Bash**, and standard
Unix tools. **ShellCheck** is highly recommended locally and enforced by CI.

Install local Git hooks:

```bash
bash tools/install-hooks.sh
```

Canonical development commands:

```bash
make check        # Run local check suite
make strict       # Run full check suite requiring ShellCheck (same as CI)
make build        # Rebuild generated standalone artifacts under scripts/
```

To scaffold a new script boilerplate:

```bash
python3 tools/new-script.py <script-id> --runtime <bash|powershell|python>
```

See [CONTRIBUTING.md](CONTRIBUTING.md) for the complete development setup guide,
tooling installation per OS, and Conventional Commits specifications. See
[docs/architecture.md](docs/architecture.md) for the architecture and release model.

AI-assisted contributions are supported. Contributors and AI agents should
read [`AGENTS.md`](AGENTS.md) before working; [`CLAUDE.md`](CLAUDE.md) is a
compatibility entry point that references the same instructions.

## Security principles

Every script must document its supported platforms, required commands, and
whether it changes user data. Destructive utilities must use safe defaults,
validate their targets, and require explicit confirmation where practical.

The project does not claim that any filesystem-changing script is risk-free.
Read the relevant script documentation before running it, especially when
using a remote URL.

See [SECURITY.md](SECURITY.md) for reporting guidance and
[CONTRIBUTING.md](CONTRIBUTING.md) for the contribution checklist.

## License

This project is released under the MIT License. See [LICENSE](LICENSE).
