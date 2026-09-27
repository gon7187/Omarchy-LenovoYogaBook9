#!/usr/bin/env python3
"""Integration test: inject only while our own exclusive test surface lives."""

import os
import selectors
import subprocess
import time
from pathlib import Path

base = Path(__file__).parent
proc = subprocess.Popen(
    ["quickshell", "-p", str(base / "test-input"), "--no-color"],
    stdout=subprocess.PIPE,
    stderr=subprocess.STDOUT,
)
sel = selectors.DefaultSelector()
assert proc.stdout is not None
sel.register(proc.stdout, selectors.EVENT_READ)
action, expected = "testKeys", "1й "
output = ""
try:
    deadline = time.monotonic() + 15
    sent = False
    while time.monotonic() < deadline and proc.poll() is None:
        if sel.select(0.2):
            chunk = os.read(proc.stdout.fileno(), 65536).decode(errors="replace")
            output += chunk
        if "Configuration Loaded" in output and not sent:
            time.sleep(0.5)
            if proc.poll() is not None:
                raise RuntimeError("Test surface exited before injection")

            subprocess.run(
                ["quickshell", "ipc", "-p", str(base), "call", "panel", action],
                check=True,
            )
            sent = True
        if f"INPUT_TEST:{expected}" in output:
            print("PASS: UI delegate actions received by test field")
            break
    else:
        raise RuntimeError("No matching input received:\n" + output)
finally:
    proc.terminate()
    try:
        proc.wait(timeout=3)
    except subprocess.TimeoutExpired:
        proc.kill()
        proc.wait()
