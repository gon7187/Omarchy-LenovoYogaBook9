#!/usr/bin/env python3
"""Check tablet rotation policy without changing hardware or reading user input."""

import runpy
from pathlib import Path
from tempfile import TemporaryDirectory

namespace = runpy.run_path(str(Path(__file__).with_name("yoga-autorotate")))
target_mode = namespace["target_mode"]
with TemporaryDirectory() as directory:
    hinge = Path(directory) / "hinge"
    target_mode.__globals__["HINGE_FILE"] = hinge
    hinge.write_text("360")
    for current in ("tablet", "tablet-left", "tablet-right", "tablet-upside"):
        for orientation, expected in (
            ("normal", "tablet"),
            ("left-up", "tablet-left"),
            ("right-up", "tablet-right"),
            ("bottom-up", "tablet-upside"),
        ):
            actual = target_mode(orientation, current)
            assert actual == expected, (current, orientation, actual, expected)
    hinge.write_text("305")
    assert target_mode("bottom-up", "stand") == "present"
    hinge.write_text("230")
    assert target_mode("bottom-up", "tablet") == "tablet-upside"
    hinge.write_text("200")
    assert target_mode("bottom-up", "tablet") == "present"
print("PASS: tablet keeps all four orientations; tent entry and unfold still work")
