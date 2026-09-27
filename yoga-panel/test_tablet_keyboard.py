#!/usr/bin/env python3
"""Live tablet OSK check. Run manually: python3 test_tablet_keyboard.py --live."""

import argparse
import json
import selectors
import subprocess
import sys
import time
from pathlib import Path

APP_ID = "org.gon7187.YogaTabletKeyboardTest"
PANEL = Path.home() / ".local/share/yoga-panel"
MODE = Path.home() / ".local/bin/yoga-mode"
UNIT = "yoga-autorotate.service"


def probe():
    import gi

    gi.require_version("Gtk", "4.0")
    from gi.repository import GLib, Gtk  # type: ignore

    app = Gtk.Application(application_id=APP_ID)

    def activate(application):
        window = Gtk.ApplicationWindow(
            application=application, title="Yoga tablet keyboard test"
        )
        window.set_default_size(800, 500)
        box = Gtk.Box(
            orientation=Gtk.Orientation.VERTICAL,
            spacing=12,
            margin_top=24,
            margin_bottom=24,
            margin_start=24,
            margin_end=24,
        )
        entry = Gtk.Entry(placeholder_text="Only this field opens the OSK")
        button = Gtk.Button(label="Non-text focus")
        box.append(entry)
        box.append(button)
        window.set_child(box)
        window.present()
        button.grab_focus()

        def command(_source, _condition):
            line = sys.stdin.readline().strip()
            if line == "entry":
                entry.grab_focus()
            elif line == "button":
                button.grab_focus()
            elif line == "fullscreen":
                window.fullscreen()
            elif line == "unfullscreen":
                window.unfullscreen()
            elif line == "quit":
                application.quit()
            else:
                return True
            print("OK " + line, flush=True)
            return True

        GLib.io_add_watch(sys.stdin, GLib.IO_IN, command)
        print("READY", flush=True)

    app.connect("activate", activate)
    app.run([])


def run(*args, check=True, **kwargs):
    return subprocess.run(args, check=check, text=True, **kwargs)


def output(*args):
    return subprocess.check_output(args, text=True).strip()


def data(*args):
    return json.loads(output(*args))


def active(unit):
    return (
        subprocess.run(
            ["systemctl", "--user", "is-active", "--quiet", unit], check=False
        ).returncode
        == 0
    )


def status():
    return output("quickshell", "ipc", "-p", str(PANEL), "call", "panel", "status")


def panel(action, check=True):
    return run(
        "quickshell",
        "ipc",
        "-p",
        str(PANEL),
        "call",
        "panel",
        action,
        check=check,
        stdout=subprocess.DEVNULL,
    )


def client():
    return next(
        (c for c in data("hyprctl", "clients", "-j") if c.get("class") == APP_ID), None
    )


def panel_layer():
    layers = data("hyprctl", "layers", "-j")
    for name, monitor in layers.items():
        for level in monitor["levels"].values():
            for layer in level:
                if layer.get("namespace") == "yoga-input-panel":
                    return {**layer, "monitor": name}
    return None


def wait_for(description, predicate, timeout=8):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        value = predicate()
        if value:
            return value
        time.sleep(0.1)
    current = client()
    details = (
        {
            key: current.get(key)
            for key in ("at", "size", "fullscreen", "fullscreenClient")
        }
        if current
        else None
    )
    state = subprocess.run(
        ["hyprctl", "yoga-tablet-status"], capture_output=True, text=True, check=False
    ).stdout.strip()
    raise AssertionError(
        f"Timed out: {description}; window={details}; panel={panel_layer()}; plugin={state}"
    )


def expect(proc, expected, timeout=3):
    assert proc.stdout
    selector = selectors.DefaultSelector()
    selector.register(proc.stdout, selectors.EVENT_READ)
    try:
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            if proc.poll() is not None:
                raise AssertionError("GTK probe exited before " + expected)
            if selector.select(min(0.1, deadline - time.monotonic())):
                line = proc.stdout.readline().strip()
                if line == expected:
                    return
    finally:
        selector.close()
    raise AssertionError("GTK probe did not acknowledge " + expected)


def send(proc, command):
    assert proc.stdin
    proc.stdin.write(command + "\n")
    proc.stdin.flush()
    expect(proc, "OK " + command)


def focus(address):
    run(
        "hyprctl",
        "eval",
        f"hl.dispatch(hl.dsp.focus({{window='address:{address}'}}))",
        stdout=subprocess.DEVNULL,
    )


def restore_focus(address):
    if address and any(
        c.get("address") == address for c in data("hyprctl", "clients", "-j")
    ):
        focus(address)


def resize_and_place(address, monitor):
    width = min(800, int(monitor["width"] / monitor["scale"]) - 40)
    height = min(500, int(monitor["height"] / monitor["scale"]) - 80)
    x = int(monitor["x"]) + 20
    y = int(monitor["y"] + monitor["height"] / monitor["scale"]) - height - 10
    run(
        "hyprctl",
        "eval",
        f'hl.dispatch(hl.dsp.window.resize({{window="address:{address}",x={width},y={height}}}))',
        stdout=subprocess.DEVNULL,
    )
    run(
        "hyprctl",
        "eval",
        f'hl.dispatch(hl.dsp.window.move({{window="address:{address}",x={x},y={y}}}))',
        stdout=subprocess.DEVNULL,
    )
    return wait_for(
        "floating test geometry",
        lambda: with_client(
            lambda current: (
                current["size"] == [width, height] and current["at"] == [x, y]
            )
        ),
    )


def with_client(predicate):
    current = client()
    return current if current and predicate(current) else None


def opened(label):
    layer = wait_for(label, lambda: panel_layer() if status() == "open" else None)
    assert layer["monitor"] == "eDP-1", layer
    return layer


def above(layer):
    return with_client(
        lambda current: current["at"][1] + current["size"][1] <= layer["y"]
    )


def live():
    if not MODE.exists() or not PANEL.exists():
        raise SystemExit("Install yoga-panel first")
    original_mode = output(str(MODE), "status")
    original_auto = active(UNIT)
    original_panel = status()
    original_focus = data("hyprctl", "activewindow", "-j").get("address")
    original_windows = data("hyprctl", "clients", "-j")
    proc = None
    try:
        if original_auto:
            run("systemctl", "--user", "stop", UNIT)
        run(str(MODE), "tablet", stdout=subprocess.DEVNULL)
        wait_for(
            "tablet mode",
            lambda: any(
                m["name"] == "eDP-2" and m["disabled"]
                for m in data("hyprctl", "monitors", "all", "-j")
            ),
        )
        if status() == "open":
            panel("hide")
        proc = subprocess.Popen(
            [sys.executable, __file__, "--probe"],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            text=True,
            bufsize=1,
        )
        expect(proc, "READY", timeout=8)
        own = wait_for("GTK window", client)
        address = own["address"]
        focus(address)

        send(proc, "entry")
        layer = opened("automatic OSK open for tiled window")
        tiled = wait_for("tiled window above OSK", lambda: above(layer))
        assert not tiled["floating"] and tiled["fullscreen"] == 0, tiled
        send(proc, "button")
        wait_for("automatic OSK hide after tiled window", lambda: status() == "closed")

        # GTK requests real client fullscreen. The plugin must make only the internal
        # mode maximized while its eDP-1 layer is mapped, then put both values back.
        send(proc, "fullscreen")
        before = wait_for(
            "client fullscreen",
            lambda: with_client(lambda c: c["fullscreenClient"] == 2),
        )
        send(proc, "entry")
        layer = opened("automatic OSK open for fullscreen window")
        during = wait_for(
            "maximized fullscreen above OSK",
            lambda: with_client(
                lambda c: (
                    c["fullscreen"] == 1 and c["at"][1] + c["size"][1] <= layer["y"]
                )
            ),
        )
        assert during["fullscreenClient"] == before["fullscreenClient"] == 2, during
        send(proc, "button")
        wait_for("automatic OSK hide", lambda: status() == "closed")
        after = wait_for(
            "fullscreen restoration",
            lambda: with_client(
                lambda c: (
                    c["fullscreen"] == before["fullscreen"]
                    and c["fullscreenClient"] == before["fullscreenClient"]
                )
            ),
        )
        assert after["fullscreen"] == after["fullscreenClient"] == 2, after
        send(proc, "unfullscreen")
        wait_for(
            "leave fullscreen",
            lambda: with_client(
                lambda c: c["fullscreen"] == c["fullscreenClient"] == 0
            ),
        )

        focus(address)
        run(
            "hyprctl",
            "eval",
            f'hl.dispatch(hl.dsp.window.float({{window="address:{address}",action="set"}}))',
            stdout=subprocess.DEVNULL,
        )
        wait_for("floating GTK window", lambda: with_client(lambda c: c["floating"]))
        monitor = next(
            m for m in data("hyprctl", "monitors", "-j") if m["name"] == "eDP-1"
        )
        before = resize_and_place(address, monitor)
        geometry = (before["at"], before["size"])
        send(proc, "entry")
        layer = opened("automatic OSK open for floating window")
        during = wait_for("floating window above OSK", lambda: above(layer))
        assert during["floating"], during
        send(proc, "button")
        wait_for(
            "automatic OSK hide after floating window", lambda: status() == "closed"
        )
        after = wait_for(
            "floating geometry restoration",
            lambda: with_client(lambda c: (c["at"], c["size"]) == geometry),
        )
        assert after["floating"], after
        print("PASS: tablet OSK auto-show, fullscreen and floating restoration")
    finally:
        cleanup_errors = []

        def cleanup(call, *args, **kwargs):
            try:
                call(*args, **kwargs)
            except (
                AssertionError,
                BrokenPipeError,
                OSError,
                subprocess.SubprocessError,
                ValueError,
            ) as error:
                cleanup_errors.append(error)

        if proc:
            cleanup(send, proc, "quit")
            cleanup(proc.wait, timeout=3)
            if proc.poll() is None:
                cleanup(proc.kill)
                cleanup(proc.wait)
        cleanup(run, str(MODE), original_mode, stdout=subprocess.DEVNULL, check=False)
        cleanup(panel, "openPanel" if original_panel == "open" else "hide", check=False)
        if original_auto:
            cleanup(
                run,
                "systemctl",
                "--user",
                "start",
                UNIT,
                stdout=subprocess.DEVNULL,
                check=False,
            )
        remaining = {c["address"] for c in data("hyprctl", "clients", "-j")}
        for previous in original_windows:
            if previous["address"] not in remaining or not previous["fullscreen"]:
                continue
            cleanup(
                run,
                "hyprctl",
                "eval",
                "hl.dispatch(hl.dsp.window.fullscreen_state({"
                f'window="address:{previous["address"]}",internal={previous["fullscreen"]},'
                f"client={previous['fullscreenClient']}" + "}))",
                stdout=subprocess.DEVNULL,
            )
        cleanup(restore_focus, original_focus)
        if cleanup_errors and sys.exc_info()[0] is None:
            raise RuntimeError("Cleanup failed: " + "; ".join(map(str, cleanup_errors)))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--live", action="store_true")
    parser.add_argument("--probe", action="store_true")
    args = parser.parse_args()
    if args.probe:
        probe()
    elif args.live:
        live()
    else:
        parser.error("pass --live; this test changes the display mode briefly")
