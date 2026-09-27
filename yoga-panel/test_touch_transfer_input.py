#!/usr/bin/env python3
"""Explicit live test: replay touch only on our own GTK title bar.

Build test_touch_transfer_plugin.cpp into /tmp/yoga-touch-transfer-test.so first.
"""

import subprocess
import sys
import time
from pathlib import Path

import test_tablet_keyboard as t


def main():
    mode = sys.argv[1] if len(sys.argv) > 1 else "book"
    library = Path("/tmp/yoga-touch-transfer-test.so")
    original_mode = t.output(str(t.MODE), "status")
    original_panel = t.status()
    original_auto = t.active(t.UNIT)
    original_focus = t.data("hyprctl", "activewindow", "-j").get("address")
    original_windows = t.data("hyprctl", "clients", "-j")
    pointer = probe = None
    loaded = False
    try:
        if original_auto:
            t.run("systemctl", "--user", "stop", t.UNIT)
        t.run("hyprctl", "plugin", "load", str(library), stdout=subprocess.DEVNULL)
        assert any(
            p["name"] == "yoga-touch-transfer-test"
            for p in t.data("hyprctl", "plugin", "list", "-j")
        ), "Test helper did not load"
        loaded = True

        t.set_mode(mode)
        t.panel("hide")
        probe = subprocess.Popen(
            [sys.executable, str(t.PANEL / "test_tablet_keyboard.py"), "--probe"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        t.expect(probe, "READY", timeout=8)
        own = t.wait_for("own GTK test window", t.client)
        address = own["address"]

        def dispatch(command):
            t.run(
                "hyprctl", "eval", f"hl.dispatch({command})", stdout=subprocess.DEVNULL
            )

        dispatch(
            f'hl.dsp.window.move({{window="address:{address}",monitor="eDP-2",follow=true}})'
        )
        dispatch(f'hl.dsp.window.float({{window="address:{address}",action="set"}})')
        dispatch(f'hl.dsp.window.resize({{window="address:{address}",x=500,y=400}})')
        monitor = next(
            m for m in t.data("hyprctl", "monitors", "-j") if m["name"] == "eDP-2"
        )
        target = next(
            m for m in t.data("hyprctl", "monitors", "-j") if m["name"] == "eDP-1"
        )
        dispatch(
            f'hl.dsp.window.move({{window="address:{address}",x={monitor["x"] + 100},y=300}})'
        )
        t.focus(address)
        t.send(probe, "entry")
        t.TARGET_SCREEN = "eDP-2"
        t.opened("OSK before edge drag")
        time.sleep(0.3)
        own = t.client()
        assert own
        pointer = subprocess.Popen(
            [str(t.PANEL / "build/yoga-pointer")], stdin=subprocess.PIPE, text=True
        )
        assert pointer.stdin
        pointer.stdin.write(
            f"a {own['at'][0] + own['size'][0] // 2} {own['at'][1] + 12} 1800 1440\n"
        )
        pointer.stdin.flush()
        time.sleep(0.15)

        def touch(action):
            answer = t.output("hyprctl", "yoga-test-edge", action)
            assert answer == "ok", answer

        touch("down")
        touch("away")
        time.sleep(0.1)
        touch("edge")
        t.wait_for(
            "finger edge transfers window",
            lambda: t.with_client(lambda c: c["monitor"] == target["id"]),
            timeout=3,
        )
        for action in ["jitter", "edge", "away", "edge"]:
            touch(action)
            time.sleep(0.25)
            current = t.client()
            assert current and current["monitor"] == target["id"], (
                "Window bounced back while finger held"
            )
        touch("up")
        time.sleep(0.4)
        current = t.client()
        assert (
            current and current["monitor"] == target["id"] and not current["floating"]
        ), current
        print(f"PASS: {mode} finger-edge transfer, jitter/retreat latch, tiled drop")
    finally:
        if loaded:
            t.run(
                "hyprctl",
                "yoga-test-edge",
                "up",
                check=False,
                stdout=subprocess.DEVNULL,
            )
        if probe:
            # Destroying this window also destroys its decoration and test contact state.
            probe.terminate()
            probe.wait(timeout=3)
        if loaded:
            t.run(
                "hyprctl", "plugin", "unload", str(library), stdout=subprocess.DEVNULL
            )
        if pointer:
            if pointer.stdin:
                pointer.stdin.close()
            pointer.wait(timeout=3)
        t.run(str(t.MODE), original_mode, stdout=subprocess.DEVNULL)
        t.panel("openPanel" if original_panel == "open" else "hide")
        if original_auto:
            t.run("systemctl", "--user", "start", t.UNIT)
        remaining = {c["address"] for c in t.data("hyprctl", "clients", "-j")}
        for previous in original_windows:
            if previous["address"] in remaining and previous["fullscreen"]:
                t.run(
                    "hyprctl",
                    "eval",
                    "hl.dispatch(hl.dsp.window.fullscreen_state({"
                    f'window="address:{previous["address"]}",internal={previous["fullscreen"]},'
                    f"client={previous['fullscreenClient']}" + "}))",
                    stdout=subprocess.DEVNULL,
                )
        t.restore_focus(original_focus)


if __name__ == "__main__":
    main()
