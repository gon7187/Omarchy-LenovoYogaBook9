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
TARGET_SCREEN = "eDP-1"
AUTO_NAMESPACE = "yoga-screen-keyboard"
MANUAL_NAMESPACE = "yoga-input-panel"
PANEL_NAMESPACES = {AUTO_NAMESPACE, MANUAL_NAMESPACE}


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


def panel_layers():
    layers = data("hyprctl", "layers", "-j")
    found = []
    for name, monitor in layers.items():
        for level in monitor["levels"].values():
            for layer in level:
                if layer.get("namespace") in PANEL_NAMESPACES:
                    found.append({**layer, "monitor": name})
    return found


def panel_layer(namespace=None, screen_name=None):
    if screen_name is None:
        screen_name = TARGET_SCREEN
    return next(
        (
            layer
            for layer in panel_layers()
            if layer["monitor"] == screen_name
            and (namespace is None or layer["namespace"] == namespace)
        ),
        None,
    )


def reserved(screen_name):
    monitor = next(
        m for m in data("hyprctl", "monitors", "-j") if m["name"] == screen_name
    )
    return tuple(monitor["reserved"])


def screen(screen_name=None):
    if screen_name is None:
        screen_name = TARGET_SCREEN
    monitor = next(
        m for m in data("hyprctl", "monitors", "-j") if m["name"] == screen_name
    )
    width, height = (
        monitor["width"] / monitor["scale"],
        monitor["height"] / monitor["scale"],
    )
    if monitor["transform"] % 2:
        width, height = height, width
    return monitor, (monitor["x"], monitor["y"], width, height)


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


def resize_and_place(address):
    _, (screen_x, screen_y, screen_width, screen_height) = screen()
    width = min(800, int(screen_width) - 40)
    height = min(500, int(screen_height) - 80)
    x = int(screen_x) + 20
    y = int(screen_y + screen_height) - height - 10
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


def opened(label, namespace=AUTO_NAMESPACE):
    def fitted_layer():
        layer = panel_layer(namespace)
        if status() != "open" or not layer or len(panel_layers()) != 1:
            return None
        _, (x, y, width, height) = screen()
        if abs(layer["x"] - x) > 1 or abs(layer["w"] - width) > 1:
            return None
        return (
            layer if y <= layer["y"] and layer["y"] + layer["h"] <= y + height else None
        )

    return wait_for(label, fitted_layer)


def above(layer):
    return with_client(
        lambda current: current["at"][1] + current["size"][1] <= layer["y"]
    )


def alternate(mode):
    return {
        "stand": "book",
        "book": "stand",
        "book-flip": "book",
        "tablet": "tablet-left",
        "tablet-left": "tablet-right",
        "tablet-right": "tablet-left",
    }[mode]


def set_mode(mode):
    run(str(MODE), mode, stdout=subprocess.DEVNULL)
    expected = {
        "stand": {"eDP-1": (False, 2), "eDP-2": (False, 0)},
        "tablet": {"eDP-1": (False, 2), "eDP-2": (True, None)},
        "tablet-left": {"eDP-1": (False, 3), "eDP-2": (True, None)},
        "tablet-right": {"eDP-1": (False, 1), "eDP-2": (True, None)},
        "book": {"eDP-1": (False, 3), "eDP-2": (False, 1)},
        "book-flip": {"eDP-1": (False, 1), "eDP-2": (False, 3)},
    }[mode]

    def applied():
        monitors = {m["name"]: m for m in data("hyprctl", "monitors", "all", "-j")}
        return all(
            name in monitors
            and monitors[name]["disabled"] == disabled
            and (transform is None or monitors[name]["transform"] == transform)
            for name, (disabled, transform) in expected.items()
        )

    wait_for(
        mode,
        applied,
    )


def live(mode):
    global TARGET_SCREEN
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
        set_mode(mode)
        if status() == "open":
            panel("hide")
        wait_for("OSK hidden before reservation snapshot", lambda: not panel_layers())
        reserved_before_open = reserved(TARGET_SCREEN)
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
        run(
            "hyprctl",
            "eval",
            f'hl.dispatch(hl.dsp.window.move({{window="address:{address}",monitor="{TARGET_SCREEN}",follow=true}}))',
            stdout=subprocess.DEVNULL,
        )
        focus(address)

        send(proc, "entry")
        layer = opened("automatic OSK open for tiled window")
        if mode == "stand":
            # Layer creation reports its initial height before QML receives the output width.
            def compact_layer():
                current = panel_layer()
                return current if current and current["h"] in (339, 377) else None

            layer = wait_for("compact landscape keyboard height", compact_layer)
        tiled = wait_for("tiled window above OSK", lambda: above(layer))
        assert not tiled["floating"] and tiled["fullscreen"] == 0, tiled
        if mode in ("book", "stand"):
            former_screen = TARGET_SCREEN
            TARGET_SCREEN = "eDP-2" if former_screen == "eDP-1" else "eDP-1"
            run(
                "hyprctl",
                "eval",
                f'hl.dispatch(hl.dsp.window.move({{window="address:{address}",monitor="{TARGET_SCREEN}",follow=true}}))',
                stdout=subprocess.DEVNULL,
            )
            focus(address)
            layer = opened("OSK moved to active book screen")
            wait_for("tiled window above moved OSK", lambda: above(layer))
            wait_for(
                "former screen reserved space restored",
                lambda: reserved(former_screen) == reserved_before_open,
            )
        send(proc, "button")
        wait_for("automatic OSK hide after tiled window", lambda: status() == "closed")

        if mode == "stand":
            panel("openPanel")

            def full_manual_pad():
                layer = panel_layer(MANUAL_NAMESPACE, "eDP-2")
                if status() != "open" or not layer or len(panel_layers()) != 1:
                    return None
                _, (x, y, width, height) = screen("eDP-2")
                return (
                    layer
                    if abs(layer["x"] - x) <= 1
                    and abs(layer["y"] - y) <= 1
                    and abs(layer["w"] - width) <= 1
                    and abs(layer["h"] - height) <= 1
                    else None
                )

            wait_for("manual full lower pad", full_manual_pad)
            panel("hide")
            wait_for("manual pad hide", lambda: status() == "closed")

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
        set_mode(alternate(mode))
        layer = opened("OSK after rotation")
        wait_for(
            "fullscreen above rotated OSK",
            lambda: with_client(
                lambda c: (
                    c["fullscreen"] == 1 and c["at"][1] + c["size"][1] <= layer["y"]
                )
            ),
        )
        set_mode(mode)
        layer = opened("OSK after returning orientation")
        wait_for(
            "fullscreen above returned OSK",
            lambda: with_client(
                lambda c: (
                    c["fullscreen"] == 1 and c["at"][1] + c["size"][1] <= layer["y"]
                )
            ),
        )
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
        _, (x, y, width, height) = screen()
        assert (
            x <= after["at"][0]
            and y <= after["at"][1]
            and after["at"][0] + after["size"][0] <= x + width
            and after["at"][1] + after["size"][1] <= y + height
        ), after
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
        before = resize_and_place(address)
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
        print(
            f"PASS: {mode} {TARGET_SCREEN} OSK auto-show, fullscreen and floating restoration"
        )
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
    parser.add_argument(
        "--mode",
        choices=("stand", "tablet", "tablet-left", "tablet-right", "book", "book-flip"),
        default="tablet",
    )
    parser.add_argument("--monitor", choices=("eDP-1", "eDP-2"), default="eDP-1")
    args = parser.parse_args()
    TARGET_SCREEN = args.monitor
    if args.probe:
        probe()
    elif args.live:
        live(args.mode)
    else:
        parser.error("pass --live; this test changes the display mode briefly")
