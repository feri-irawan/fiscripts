# Security Policy

## Scope

This repository contains standalone scripts that may inspect or modify local
files. A script's documentation is part of its security contract and should be
read before execution.

## Reporting a vulnerability

Please report security issues privately through GitHub's private vulnerability
reporting feature when it is enabled for this repository. If private reporting
is unavailable, open a GitHub issue without publishing exploit details and ask
for a private contact channel.

Include:

- the affected script and version;
- the operating system and runtime version;
- the exact command or input that triggers the issue;
- the expected and observed behavior;
- a safe reproduction case if possible.

Do not include secrets, personal data, or destructive proof-of-concept payloads
in a public issue.

## Security expectations for contributors

- Never add hidden network access to a script.
- Never fetch or execute unpinned remote code at runtime.
- Treat `src/` dependencies as build-time only; published artifacts must be
  standalone.
- Avoid `eval`, unsafe word splitting, and unquoted filesystem paths.
- Add explicit confirmation for destructive operations.
- Test destructive behavior only against temporary fixtures.
- Document known limitations instead of implying absolute safety.

Filesystem-changing scripts should be treated as utilities for user-owned
project directories, not as security boundaries against a malicious concurrent process.
