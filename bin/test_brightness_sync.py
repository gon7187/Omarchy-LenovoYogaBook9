#!/usr/bin/env python3
"""Check shared SDR/HDR brightness behavior without accessing real displays."""

import json
import runpy
import subprocess
import tempfile
from pathlib import Path
from unittest.mock import patch


def main():
    module = runpy.run_path(str(Path(__file__).with_name("yoga-brightness-sync")))
    calls = []
    monitor = {
        "name": "eDP-1",
        "width": 2880,
        "height": 1800,
        "refreshRate": 60,
        "x": 0,
        "y": 0,
        "scale": 2,
        "transform": 2,
        "mirrorOf": "none",
        "currentFormat": "XRGB2101010",
        "colorManagementPreset": "hdr",
        "sdrBrightness": 1.0,
    }

    def run(args, **kwargs):
        calls.append(args)
        return subprocess.CompletedProcess(args, 0, stdout=json.dumps([monitor]))

    with tempfile.TemporaryDirectory() as directory:
        module.get("sync_hdr", lambda primary: None).__globals__["CONFIG_PATH"] = (
            Path(directory) / "autobrightness.conf"
        )
        primary, secondary = Path(directory) / "primary", Path(directory) / "secondary"
        primary.mkdir()
        secondary.mkdir()
        (primary / "brightness").write_text("500")
        (primary / "max_brightness").write_text("1000")
        (secondary / "max_brightness").write_text("200")
        assert module["target_level"](primary, secondary) == 100
        sync = module.get("sync_hdr", lambda primary: None)
        with patch.object(subprocess, "run", run):
            sync(primary)
        changes = [args[2] for args in calls if args[:2] == ["hyprctl", "eval"]]
        assert len(changes) == 1, (
            "Shared helper must update HDR brightness as well as mirror SDR backlight"
        )
        assert "sdrbrightness = 1.5" in changes[0]
        assert "transform = 2" in changes[0] and "bitdepth = 10" in changes[0]
    print(
        "BRIGHTNESS_SYNC_OK: backlight scaling and HDR brightness retain monitor geometry"
    )


if __name__ == "__main__":
    main()
