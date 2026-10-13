#!/usr/bin/env python3
"""Check gyro power policy using temporary sysfs-shaped files, no hardware."""

import os
import runpy
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch


def check_install(parent_active: bool) -> None:
    hinge = runpy.run_path(str(Path(__file__).with_name("yoga-hinge")))
    install = hinge["install"]
    namespace = install.__globals__
    real_run = subprocess.run
    started = []

    def run(args, **kwargs):
        if args[0] != "systemctl":
            return real_run(args, **kwargs)
        if "is-active" in args:
            return subprocess.CompletedProcess(args, 0 if parent_active else 3)
        if "start" in args or "--now" in args:
            started.append(args[-1])
        return subprocess.CompletedProcess(args, 0)

    with tempfile.TemporaryDirectory() as directory:
        namespace["UNIT"] = str(Path(directory) / "unit/yoga-hinge.service")
        namespace["find_gyros"] = lambda: [("iio:device0", "unused", 1)]
        with (
            patch.dict(os.environ, HOME=directory),
            patch.object(os, "access", return_value=True),
            patch.object(subprocess, "run", run),
        ):
            install()
        assert started == (["yoga-hinge"] if parent_active else []), (
            "Installing while auto-rotation is off must not start gyro streaming"
        )
        assert (Path(directory) / ".local/bin/yoga-hinge").is_file()


def check() -> None:
    hinge = runpy.run_path(str(Path(__file__).with_name("yoga-hinge")))
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        rate = hinge["sample_rate"]
        assert rate(root) == 100, "Unknown power state must preserve calibrated rate"
        battery = root / "BAT0"
        battery.mkdir()
        status = battery / "status"
        status.write_text("Discharging\n")
        assert rate(root) == 25
        status.write_text("Charging\n")
        assert rate(root) == 100
        status.write_text("Full\n")
        assert rate(root) == 100
        status.unlink()
        assert rate(root) == 100
    print("PASS: battery 25 Hz, AC/unknown 100 Hz, power source changes detected")
    check_install(False)
    check_install(True)
    print("PASS: install starts gyro streaming only with active auto-rotation")


if __name__ == "__main__":
    check()
