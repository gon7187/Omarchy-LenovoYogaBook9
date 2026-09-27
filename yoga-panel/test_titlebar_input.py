#!/usr/bin/env python3
"""Live regression: only our disposable window receives injected pointer events."""

import json
import os
import selectors
import subprocess
import sys
import time
from pathlib import Path

APP_ID = "org.gon7187.YogaTitlebarInputTest"


def probe():
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import Gtk  # type: ignore[attr-defined]

    app = Gtk.Application(application_id=APP_ID)

    def activate(application):
        window = Gtk.ApplicationWindow(
            application=application, title="Yoga titlebar input test"
        )
        window.set_titlebar(Gtk.Box())
        window.set_default_size(600, 300)
        area = Gtk.Box()
        click = Gtk.GestureClick()
        click.connect(
            "released", lambda _c, _n, x, y: print(f"CLICK {x:.0f} {y:.0f}", flush=True)
        )
        area.add_controller(click)
        window.set_child(area)
        window.present()

    app.connect("activate", activate)
    app.run([])


def data(*args):
    return json.loads(subprocess.check_output(args, text=True))


def main():
    binary = (
        sys.argv[1]
        if len(sys.argv) > 1
        else str(Path.home() / ".local/share/yoga-panel/build/yoga-pointer")
    )
    focus = data("hyprctl", "activewindow", "-j").get("address")
    cursor = data("hyprctl", "cursorpos", "-j")
    monitors = data("hyprctl", "monitors", "-j")
    width = round(
        max(
            m["x"] + (m["height"] if m["transform"] % 2 else m["width"]) / m["scale"]
            for m in monitors
        )
    )
    height = round(
        max(
            m["y"] + (m["width"] if m["transform"] % 2 else m["height"]) / m["scale"]
            for m in monitors
        )
    )
    touch_library = Path(sys.argv[2]).resolve() if len(sys.argv) > 2 else None
    loaded = False
    child = subprocess.Popen(
        [sys.executable, __file__, "--probe"],
        stdout=subprocess.PIPE,
        text=True,
        env=dict(os.environ, GSK_RENDERER="gl"),
    )
    pointer = subprocess.Popen([binary], stdin=subprocess.PIPE, text=True)
    assert child.stdout and pointer.stdin
    reader = selectors.DefaultSelector()
    reader.register(child.stdout, selectors.EVENT_READ)

    def send(command):
        assert pointer.stdin
        pointer.stdin.write(command + "\n")
        pointer.stdin.flush()

    def window():
        return next(
            (c for c in data("hyprctl", "clients", "-j") if c["class"] == APP_ID), None
        )

    def move(x, y):
        send(f"a {round(x)} {round(y)} {width} {height}")
        time.sleep(0.12)
        actual = data("hyprctl", "cursorpos", "-j")
        assert abs(actual["x"] - x) < 2 and abs(actual["y"] - y) < 2, (actual, x, y)

    def click(x, y):
        move(x, y)
        send("b 272 1")
        time.sleep(0.06)
        send("b 272 0")

    try:
        own = None
        for _ in range(80):
            own = window()
            if own:
                break
            time.sleep(0.1)
        assert own, "Test window did not appear"
        address = own["address"]
        subprocess.run(
            [
                "hyprctl",
                "eval",
                f'hl.dispatch(hl.dsp.window.float({{window="address:{address}",action="set"}}))',
            ],
            check=True,
            stdout=subprocess.DEVNULL,
        )
        time.sleep(0.5)
        own = window()
        assert own
        x, y = own["at"]
        w = own["size"][0]
        click(x + 100, y + 100)
        assert reader.select(1), "Probe content did not receive baseline click"
        assert child.stdout.readline().startswith("CLICK ")
        print("PASS: probe receives ordinary content clicks", flush=True)
        # Left/center, unused top-right, gap, outer edge and vertical margins.
        for dx, dy in [
            (20, 14),
            (w // 2, 14),
            (w - 90, 14),
            (w - 35, 14),
            (w - 4, 14),
            (w - 50, 1),
            (w - 50, 27),
        ]:
            click(x + dx, y + dy)
            assert reader.select(1), f"Client click swallowed at ({dx}, {dy})"
            result = child.stdout.readline().strip()
            assert result.startswith("CLICK "), result
        print("PASS: top-row client clicks pass through outside visible controls")
        move(x + w - 50, y + 14)
        send("b 272 1")
        time.sleep(0.1)
        send("m 70 50")
        time.sleep(0.35)
        send("b 272 0")
        time.sleep(0.3)
        after = window()
        assert after and after["at"] != own["at"], "Grip did not drag window"
        assert not reader.select(0.15), "Grip leaked click to client"
        print("PASS: visible grip drags without clicking client")
        if touch_library:
            subprocess.run(
                ["hyprctl", "plugin", "load", str(touch_library)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
            loaded = True

            def touch(action):
                result = subprocess.check_output(
                    ["hyprctl", "yoga-test-edge", action], text=True
                ).strip()
                assert result == "ok", result
                time.sleep(0.15)

            for action in ["client", "gap"]:
                touch(action)
                touch("up")
                assert reader.select(1), f"Client touch swallowed: {action}"
                result = child.stdout.readline().strip()
                assert result.startswith("CLICK "), result
            touch("down")
            touch("away")
            after = window()
            assert after and after["floating"] and after["at"] != own["at"], (
                "Touch grip did not drag"
            )
            assert not reader.select(0.15), "Touch grip leaked click to client"
            touch("up")
            time.sleep(0.4)
            after = window()
            assert after and not after["floating"], "Touch grip did not drop tiled"
            print(
                "PASS: client touch/gap pass through; touch grip drags and drops tiled"
            )
        click(after["at"][0] + after["size"][0] - 20, after["at"][1] + 14)
        for _ in range(30):
            if not window():
                break
            time.sleep(0.1)
        assert not window(), "Close button did not close test window"
        print("PASS: close button closes only test window")
    finally:
        if loaded:
            subprocess.run(
                ["hyprctl", "yoga-test-edge", "up"],
                check=False,
                stdout=subprocess.DEVNULL,
            )
            subprocess.run(
                ["hyprctl", "plugin", "unload", str(touch_library)],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        send("b 272 0")
        child.terminate()
        child.wait(timeout=5)
        reader.close()
        if focus and any(
            c["address"] == focus for c in data("hyprctl", "clients", "-j")
        ):
            subprocess.run(
                [
                    "hyprctl",
                    "eval",
                    f'hl.dispatch(hl.dsp.focus({{window="address:{focus}"}}))',
                ],
                check=True,
                stdout=subprocess.DEVNULL,
            )
        move(cursor["x"], cursor["y"])
        pointer.stdin.close()
        pointer.wait(timeout=5)


if __name__ == "__main__":
    probe() if "--probe" in sys.argv else main()
