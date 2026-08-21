# Contributing

Thank you for helping improve `fiscripts`. Every contribution should keep the
repository easy to audit and every published script easy to run independently.

AI-assisted contributions are welcome. AI agents must read [`AGENTS.md`](AGENTS.md)
before working, preserve user changes, avoid unrequested commits, and report
skipped platform tests honestly. `CLAUDE.md` is a compatibility entry point
that references the same instructions.

## Add a script

1. Create a source directory under the appropriate runtime in `src/`.
2. Add a `manifest.json` with an id, variant, semantic version, runtime,
   entrypoint, output path, supported operating systems, dependencies, and
   destructive flag.
3. Keep internal dependencies under the same runtime's source tree. List them
   in bundle order, prerequisites before consumers, and do not duplicate them.
4. Add or update the generated artifact under `scripts/` by running the build.
5. Add detailed documentation at `docs/scripts/<script-id>.md`.
6. Add fixture-based tests under `tests/<runtime>/` using the runtime-specific
   naming convention, such as `*.test.sh`, `*.test.ps1`, or `*.test.py`.
7. Update the script catalog in `README.md`.

## Development setup

To ensure production-grade code quality and parity with CI checks, the following
local development setup is recommended:

### 1. Prerequisites

- **Python**: 3.10 or newer (for build tools, manifest validation, and PTY test runners).
- **Bash**: 3.2 or newer (standard Unix shell).
- **ShellCheck**: Static analysis linter for shell scripts.
- **Git**: Version control.
- **GNU Make**: Task runner (optional, for `make` shortcuts).

### 2. Tooling installation

**Ubuntu / Debian / Linux Mint:**
```bash
sudo apt update && sudo apt install -y python3 shellcheck make git
```

**Fedora / RHEL:**
```bash
sudo dnf install -y python3 ShellCheck make git
```

**Arch Linux:**
```bash
sudo pacman -S python shellcheck make git
```

**macOS (Homebrew):**
```bash
brew install python shellcheck make git
```

### 3. Git hooks setup

Install the local pre-commit and commit-msg hooks to catch issues before pushing:

```bash
bash tools/install-hooks.sh
```

### 4. Recommended IDE extensions

- **EditorConfig**: Enforces consistent indentation, line endings, and file formatting (`.editorconfig`).
- **ShellCheck**: Provides real-time inline linting for `.sh` files in VS Code, Neovim, or JetBrains.
- **Python**: Language server and syntax validation for Python tooling.

## Local checks

From the repository root:

```bash
# Rebuild generated standalone artifacts
make build        # or: python3 tools/build.py

# Run complete local check suite with strict ShellCheck analysis
make strict       # or: python3 tools/check.py --strict
```

`tools/check.py` is the canonical all-checks entry point. Without `--strict`,
it skips unavailable optional runtimes and ShellCheck; with `--strict`, missing
tools or test runtimes fail the check. CI runs strict mode on every pull request.
Test files must use the `*.test.<runtime-extension>` naming convention so the
full check can discover and dispatch them automatically.

Read [docs/architecture.md](docs/architecture.md) before adding a runtime,
dependency type, or release automation. Keep generated artifacts in sync with
their source; CI rejects stale artifacts.

## Script contract

Every published artifact must:

- run without another repository file;
- document runtime and platform support;
- document external command requirements;
- avoid hidden network activity;
- handle user-controlled paths safely;
- use safe defaults;
- make destructive actions explicit;
- expose `--help` and `--version` where appropriate;
- include a test that does not touch real user data.

## Commit messages

`fiscripts` enforces [Conventional Commits](https://www.conventionalcommits.org/)
for all commits and pull requests. This standard powers automated changelog
generation and release management.

Format:

```text
<type>(<optional scope>): <description>

[optional body]

[optional footer(s)]
```

Common types:
- `feat`: A new user-facing feature or utility (e.g. `feat(node-modules-cleaner): add live filter`).
- `fix`: A bug fix (e.g. `fix(node-modules-cleaner): handle terminal resize signal`).
- `docs`: Documentation changes only (e.g. `docs: update contributing guide`).
- `refactor`: Code change that neither fixes a bug nor adds a feature.
- `test`: Adding or correcting tests (e.g. `test: add assertion helper`).
- `chore`: Maintenance tasks, tooling, or build configuration (e.g. `chore: update check script`).
- `feat!:` or `fix!:`: Breaking changes.

Install local Git hooks to automatically validate commit messages:

```bash
bash tools/install-hooks.sh
```

## Pull requests

Pull requests should explain the user problem, the safety model, supported
platforms, and how the change was tested. Generated artifacts must be rebuilt
and committed when their source or dependencies change. PR titles must adhere
to Conventional Commits.
