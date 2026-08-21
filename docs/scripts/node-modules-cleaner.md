# node-modules-cleaner

Interactively find and remove selected `node_modules` directories to reclaim
disk space. Dependencies can be regenerated later with the relevant package
manager.

## Support

- Runtime: Bash
- Variant: `bash`
- Tested platform: Linux
- Version: `1.0.0`
- Distribution artifact: [`scripts/bash/node-modules-cleaner.sh`](../../scripts/bash/node-modules-cleaner.sh)
- No Node.js, package manager, or third-party package is required to run it.

The script uses standard commands including `find`, `rm`, `du`, `mktemp`,
`awk`, `sort`, `basename`, and `dirname`.

## Usage

```bash
./scripts/bash/node-modules-cleaner.sh [OPTIONS] SCAN_ROOT
```

`SCAN_ROOT` is an existing directory whose descendants will be scanned
recursively. It can contain one project or many projects; it is not a direct
deletion target.

Examples:

```bash
# Scan the current directory interactively.
./scripts/bash/node-modules-cleaner.sh .

# Scan non-interactively and list disk space usage (dry-run).
./scripts/bash/node-modules-cleaner.sh --list "$HOME/Projects"
./scripts/bash/node-modules-cleaner.sh --dry-run "$HOME/Projects"

# Sort results by size (largest first).
./scripts/bash/node-modules-cleaner.sh --sort size "$HOME/Projects"

# Scan a projects directory under your home directory.
./scripts/bash/node-modules-cleaner.sh "$HOME/Projects"

# Scan one project.
./scripts/bash/node-modules-cleaner.sh "$HOME/Projects/my-app"

# Quote paths that contain spaces.
./scripts/bash/node-modules-cleaner.sh "$HOME/Archived Projects"

./scripts/bash/node-modules-cleaner.sh --help
./scripts/bash/node-modules-cleaner.sh --version
```

Without an argument, the script displays its help and makes no changes.

## What it scans

The scan starts at `SCAN_ROOT` and finds directories named exactly
`node_modules`. Once a matching directory is found, `find` prunes that branch,
so `node_modules` directories inside it are intentionally not scanned.

Symlinks are not followed. The scan root itself cannot be a directory named
`node_modules`; pass the project directory containing it instead.

For example:

```text
Projects/
├── app-one/
│   └── node_modules/              ← found
├── app-two/
│   └── node_modules/              ← found
└── app-three/
    └── node_modules/
        └── package-a/
            └── node_modules/      ← intentionally ignored
```

## Interactive controls

The interactive selector features automatic terminal viewport pagination to
prevent scrolling overflow when many projects are found:

| Key | Action |
| --- | --- |
| Up/Down or `j`/`k` | Move between items (auto-pages at boundaries) |
| `PgUp` / `PgDn` | Jump previous/next page |
| Space | Toggle the current item |
| `a` | Select all items currently visible |
| `n` | Clear all selections currently visible |
| `s` | Cycle sort mode (`size` → `name` → `default`) |
| `/` | Live keyword filter / search (Escape to clear) |
| Enter | Continue to deletion review |
| `q` or Escape | Cancel |

After selection, the script prints the exact paths again. Deletion only starts
when the user types `DELETE` exactly.

## Safety behavior

- The script refuses to run as root or through `sudo`.
- The script refuses to scan the filesystem root (`/`); choose a narrower
  project directory.
- Scanning must complete successfully before selection is offered.
- Paths are collected with NUL delimiters to preserve special characters.
- Selected targets are validated again before deletion.
- A target must still be a non-symlink directory named exactly `node_modules`.
- GNU `rm --one-file-system` is used when available to avoid crossing mount points.
- No automatic selection or `--yes` mode is provided.
- Deletion is permanent and is performed with `rm -rf`.

Do not pass a path that is already `node_modules`; the script rejects it. The
filesystem root (`/`) is rejected as a scan root. Do not use it on a path you
do not own or understand.

## Regenerating dependencies

From the project directory, use the package manager appropriate for that
project, for example:

```bash
npm install
pnpm install
yarn install
bun install
```

## URL execution

Review the artifact before using remote execution. For a pinned repository tag:

```bash
curl -fsSL \
  https://raw.githubusercontent.com/<OWNER>/fiscripts/v1.0.0/scripts/bash/node-modules-cleaner.sh \
  | bash -s -- "$HOME/Projects"
```

Replace `<OWNER>` with the GitHub account that owns the public repository.
Using a commit URL is even more reproducible than using a tag.

## Limitations

The script is currently tested on Linux. It is not a general-purpose package
manager and does not inspect whether a project is currently open or in use.
Close development tools that may be using a project before removing its
dependencies.

This is intended for normal user-owned project directories, not adversarial or
concurrently modified filesystems. A process that changes the directory tree
between validation and deletion cannot be fully controlled by a shell script.
GNU systems use `rm --one-file-system` when available; other implementations
may not provide that mount-point protection.
