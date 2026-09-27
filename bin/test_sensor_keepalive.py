#!/usr/bin/env python3
"""Exercise the real reader on an isolated PTY, never on the hardware."""

import configparser
import os
import pty
import select
import shlex
import subprocess
import termios
import time
from pathlib import Path


def check() -> None:
    root = Path(__file__).resolve().parents[1]
    config = configparser.ConfigParser(interpolation=None)
    config.read(root / "config/systemd/yoga-sensor-keepalive.service")
    args = shlex.split(config["Service"]["ExecStart"])
    args[0] = str(root / "bin" / Path(args[0]).name)
    master, slave = pty.openpty()
    with subprocess.Popen(
        [*args, os.ttyname(slave)],
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        start_new_session=True,
    ) as process:
        try:
            deadline = time.monotonic() + 3
            while termios.tcgetattr(slave)[3] & (
                termios.ICANON | termios.ISIG | termios.ECHO
            ):
                assert process.poll() is None, "Reader exited during startup"
                assert time.monotonic() < deadline, "Reader did not enter raw mode"
                time.sleep(0.01)
            # Catch the open/stty race without intentionally crashing processes:
            # the session leader must never acquire this controlling TTY.
            assert os.tcgetpgrp(master) == 0, "Reader acquired a controlling TTY"
            os.set_blocking(master, False)
            payload = b"\x1c\x04" + bytes(range(256)) * 256
            sent = 0
            deadline = time.monotonic() + 3
            while sent < len(payload):
                assert process.poll() is None, "Reader exited on binary sensor data"
                assert time.monotonic() < deadline, "Reader stopped draining input"
                if select.select([], [master], [], 0.1)[1]:
                    try:
                        sent += os.write(master, payload[sent:])
                    except BlockingIOError:
                        pass
            assert not select.select([master], [], [], 0.1)[0], (
                "Sensor data echoed back"
            )
            assert process.poll() is None, "Reader exited on binary sensor data"
        finally:
            if process.poll() is None:
                process.terminate()
            stdout, stderr = process.communicate(timeout=3)
            os.close(master)
            os.close(slave)
        assert not stdout and not stderr, "Reader logged sensor data or an error"
    print(
        "PASS: no controlling TTY; binary stream drained without exit, echo or logging"
    )


if __name__ == "__main__":
    check()
