#!/usr/bin/env python3
"""Replay binary sensor bytes through the real unit command on an isolated PTY."""

import configparser
import os
import pty
import resource
import select
import shlex
import subprocess
import sys
import time
from pathlib import Path


def check(unit: Path) -> None:
    config = configparser.ConfigParser(interpolation=None)
    config.read(unit)
    command = config["Service"]["ExecStart"]
    device = "/dev/serial/by-id/usb-INGENIC_Gadget_Serial_and_keyboard_ingenic-if00"
    resource.setrlimit(resource.RLIMIT_CORE, (0, 0))
    for payload in (b"\x1c", b"\x04", bytes(range(256))):
        master, slave = pty.openpty()
        args = shlex.split(command.replace(device, os.ttyname(slave)))
        with subprocess.Popen(
            args,
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            start_new_session=True,
        ) as process:
            try:
                # Wait for exec cat, after any serial setup in the unit command.
                deadline = time.monotonic() + 3
                while time.monotonic() < deadline:
                    if process.poll() is not None:
                        raise AssertionError(
                            f"Unit exited during startup: {process.returncode}"
                        )
                    if (
                        Path(f"/proc/{process.pid}/comm").read_text().strip() == "cat"
                        and os.tcgetpgrp(master) == process.pid
                    ):
                        break
                    time.sleep(0.01)
                else:
                    raise AssertionError("Reader did not acquire the serial port")
                os.write(master, payload)
                assert process.stdout is not None
                received = b""
                deadline = time.monotonic() + 2
                while len(received) < len(payload) and time.monotonic() < deadline:
                    if select.select([process.stdout], [], [], 0.1)[0]:
                        chunk = os.read(process.stdout.fileno(), 4096)
                        if not chunk:
                            break
                        received += chunk
                assert received == payload, (
                    f"Binary input lost: {payload!r}, exit={process.poll()}"
                )
                assert process.poll() is None, "Reader exited on binary input"
                assert not select.select([master], [], [], 0.1)[0], (
                    "Sensor data echoed back to device"
                )
            finally:
                if process.poll() is None:
                    process.kill()
                process.wait()
                os.close(master)
                os.close(slave)
    print("PASS: QUIT, EOF and all 256 byte values remain data; no echo or exits")


if __name__ == "__main__":
    check(
        Path(sys.argv[1])
        if len(sys.argv) > 1
        else Path(__file__).resolve().parents[1]
        / "config/systemd/yoga-sensor-keepalive.service"
    )
