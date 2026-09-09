#!/usr/bin/env python3
"""Smoke-test a release binary without closing stdin during bench."""

from __future__ import annotations

import pathlib
import queue
import re
import subprocess
import sys
import threading
import time


def main() -> int:
    if len(sys.argv) != 4:
        raise SystemExit("usage: release_smoke.py ENGINE VERSION FINGERPRINT_OUT")

    engine = pathlib.Path(sys.argv[1]).resolve()
    version = sys.argv[2]
    fingerprint = pathlib.Path(sys.argv[3])
    if not engine.is_file():
        raise SystemExit(f"release binary not found: {engine}")

    process = subprocess.Popen(
        [str(engine)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        encoding="utf-8",
        errors="replace",
        bufsize=1,
    )
    assert process.stdin is not None
    assert process.stdout is not None

    output: queue.Queue[str | None] = queue.Queue()

    def read_output() -> None:
        for line in process.stdout:
            output.put(line.rstrip("\r\n"))
        output.put(None)

    threading.Thread(target=read_output, daemon=True).start()

    seen: list[str] = []

    def wait_for(pattern: re.Pattern[str], timeout: float) -> re.Match[str]:
        deadline = time.monotonic() + timeout
        while True:
            remaining = deadline - time.monotonic()
            if remaining <= 0:
                raise RuntimeError(f"timed out waiting for {pattern.pattern}")
            try:
                line = output.get(timeout=remaining)
            except queue.Empty as error:
                raise RuntimeError(f"timed out waiting for {pattern.pattern}") from error
            if line is None:
                raise RuntimeError(f"engine exited while waiting for {pattern.pattern}")
            seen.append(line)
            print(line, flush=True)
            match = pattern.search(line)
            if match:
                return match

    try:
        process.stdin.write("uci\n")
        process.stdin.flush()
        wait_for(re.compile(r"^uciok$"), 15)
        if not any(line.startswith(f"id name Manta {version}") for line in seen):
            raise RuntimeError(f"UCI identity does not report Manta {version}")

        process.stdin.write("bench 6\n")
        process.stdin.flush()
        match = wait_for(re.compile(r"^Nodes searched\s*:\s*(?P<nodes>[0-9]+)$"), 180)
        nodes = int(match.group("nodes"))
        if nodes <= 0:
            raise RuntimeError("bench reported no work")
        wait_for(re.compile(r"^Nodes/second\s*:\s*[0-9]+$"), 15)

        # Release verification compares files produced by Windows and Unix.
        # Bytes avoid Python's platform-specific text newline translation.
        fingerprint.write_bytes(f"{nodes}\n".encode("ascii"))
        process.stdin.write("quit\n")
        process.stdin.flush()
        process.wait(timeout=15)
        if process.returncode != 0:
            raise RuntimeError(f"engine exited with {process.returncode}")
        print(f"release smoke passed: Manta {version}, bench-6 {nodes} nodes")
        return 0
    finally:
        if process.poll() is None:
            process.kill()
            process.wait()


if __name__ == "__main__":
    raise SystemExit(main())
