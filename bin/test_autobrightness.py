#!/usr/bin/env python3
"""Offline checks: calibrated curve, AC detection and live-loop transitions."""

import importlib.machinery
import importlib.util
import tempfile
from pathlib import Path
from unittest.mock import patch

loader = importlib.machinery.SourceFileLoader(
    "autobrightness", str(Path(__file__).with_name("yoga-autobrightness"))
)
spec = importlib.util.spec_from_loader(loader.name, loader)
assert spec is not None
app = importlib.util.module_from_spec(spec)
loader.exec_module(app)

for lux, battery in ((1, 5), (20, 5), (30, 25), (40, 55), (60, 65), (600, 100)):
    assert app.target_pct(lux, app.DEFAULT_CURVE, False) == battery
    assert app.target_pct(lux, app.DEFAULT_CURVE, True) == min(100, battery + 15)
assert app.target_pct(20, app.curve_points({"curve": "20:7,600:97"}), True) == 22

with tempfile.TemporaryDirectory() as directory:
    root = Path(directory)
    assert not app.on_mains(root)
    for name, kind in (("hid-battery", "Battery"), ("ADP0", "Mains")):
        supply = root / name
        supply.mkdir()
        (supply / "type").write_text(kind)
        (supply / "online").write_text("1")
    assert app.on_mains(root)
    (root / "ADP0/online").write_text("0")
    assert not app.on_mains(root)
    (root / "ADP0/online").unlink()
    assert not app.on_mains(root)

# At the top of a custom curve, unplugging must apply even a 3-point change.
# The next manual move still pauses automation, including charger transitions.
with (
    patch.object(app, "Sensor") as sensor,
    patch.object(app.signal, "signal"),
    patch.object(app.time, "sleep", side_effect=[None] * 4 + [KeyboardInterrupt]),
    patch.object(app, "current_pct", side_effect=[97, 97, 100, 70]),
    patch.object(app, "on_mains", side_effect=[False, True, False]) as mains,
    patch.object(app, "config_values", return_value={"curve": "20:5,600:97"}),
    patch.object(app, "set_pct") as write,
):
    sensor.return_value.lux.return_value = 600
    try:
        app.main()
    except KeyboardInterrupt:
        pass
    assert [(c.args[0], c.args[1]) for c in write.call_args_list] == [
        (100, 97),
        (97, 100),
    ]
    assert mains.call_count == 3

print("autobrightness checks passed")
