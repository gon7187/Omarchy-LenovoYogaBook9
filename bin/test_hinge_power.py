#!/usr/bin/env python3
"""Check gyro power policy using temporary sysfs-shaped files, no hardware."""

import runpy
import tempfile
from pathlib import Path


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


if __name__ == "__main__":
    check()
