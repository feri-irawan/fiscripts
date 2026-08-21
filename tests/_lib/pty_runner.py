#!/usr/bin/env python3
"""Reusable Pseudo-Terminal (PTY) Test Runner for Interactive CLI Utilities.

Enables automated testing of interactive terminal applications without requiring
an external test driver like expect or tmux.
"""

from __future__ import annotations

import os
import pty
import select
import signal
import sys
import time
from typing import Sequence


class PTYSession:
    """Manages an interactive terminal process lifecycle via a pseudo-terminal."""

    def __init__(
        self,
        command: Sequence[str],
        env: dict[str, str] | None = None,
        timeout: float = 20.0,
    ) -> None:
        self.command = list(command)
        self.timeout = timeout
        self.output = bytearray()
        self.exit_code: int | None = None

        run_env = os.environ.copy()
        run_env["TERM"] = "dumb"
        run_env["NO_COLOR"] = "1"
        if env:
            run_env.update(env)

        self.pid, self.fd = pty.fork()
        if self.pid == 0:
            os.execvpe(self.command[0], self.command, run_env)

    def read_available(self, timeout: float = 0.2) -> bytes:
        """Read all currently available data from the pseudo-terminal."""
        ready, _, _ = select.select([self.fd], [], [], timeout)
        if ready:
            try:
                data = os.read(self.fd, 4096)
                self.output.extend(data)
                return data
            except OSError:
                pass
        return b""

    def expect(self, target: str | bytes, timeout: float | None = None) -> bool:
        """Wait until target string or byte sequence appears in the output."""
        needle = target.encode("utf-8") if isinstance(target, str) else target
        deadline = time.monotonic() + (timeout or self.timeout)

        while time.monotonic() < deadline:
            if needle in self.output:
                return True
            self.read_available(timeout=0.1)
            self.poll()
            if self.exit_code is not None and needle in self.output:
                return True

        return needle in self.output

    def send(self, data: str | bytes) -> None:
        """Write raw characters or bytes to stdin."""
        payload = data.encode("utf-8") if isinstance(data, str) else data
        os.write(self.fd, payload)

    def send_line(self, text: str = "") -> None:
        """Write a string followed by a carriage return."""
        self.send(f"{text}\r")

    def poll(self) -> int | None:
        """Check if the process has terminated."""
        if self.exit_code is not None:
            return self.exit_code

        waited_pid, status = os.waitpid(self.pid, os.WNOHANG)
        if waited_pid == self.pid:
            self.exit_code = os.waitstatus_to_exitcode(status)
            return self.exit_code
        return None

    def wait_for_exit(self, timeout: float | None = None) -> int:
        """Wait for the process to terminate, killing it if it exceeds timeout."""
        deadline = time.monotonic() + (timeout or self.timeout)
        while time.monotonic() < deadline:
            self.read_available(timeout=0.1)
            code = self.poll()
            if code is not None:
                return code

        # Process timed out -> kill cleanly
        try:
            os.kill(self.pid, signal.SIGTERM)
            os.waitpid(self.pid, 0)
        except OSError:
            pass

        output_str = self.output.decode("utf-8", errors="replace")
        raise TimeoutError(
            f"Command {self.command} timed out after {timeout or self.timeout}s.\n"
            f"Captured Output:\n{output_str}"
        )

    def get_output_text(self) -> str:
        """Return all captured output decoded as UTF-8."""
        return self.output.decode("utf-8", errors="replace")


def run_interactive_flow(
    command: Sequence[str],
    steps: Sequence[tuple[str, str]],
    timeout: float = 15.0,
) -> tuple[int, str]:
    """Execute a predefined sequence of (expect_string, send_action) steps.

    Example steps:
        [
            ("Selected: 0/2", "a"),
            ("Selected: 2/2", "\\r"),
            ("Type exactly DELETE", "DELETE\\r"),
        ]
    """
    session = PTYSession(command, timeout=timeout)
    for expected, action in steps:
        if not session.expect(expected, timeout=timeout):
            session.wait_for_exit(timeout=1.0)
            raise AssertionError(
                f"Expected '{expected}' not found in output.\n"
                f"Output received:\n{session.get_output_text()}"
            )
        session.send(action)

    exit_code = session.wait_for_exit(timeout=timeout)
    return exit_code, session.get_output_text()


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python3 pty_runner.py <command> [args...]", file=sys.stderr)
        sys.exit(1)

    runner_session = PTYSession(sys.argv[1:])
    code = runner_session.wait_for_exit()
    sys.exit(code)
