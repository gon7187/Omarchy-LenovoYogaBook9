#!/usr/bin/env python3
"""Live two-screen OSK focus regression; pass --live. Reads no user text."""

import json
import subprocess
import sys
import time


def out(*a):
    return subprocess.check_output(a, text=True).strip()


def data(*a):
    return json.loads(out(*a))


def dispatch(s):
    out("hyprctl", "eval", s)


def focus(a):
    dispatch('hl.dispatch(hl.dsp.focus({window="address:' + a + '"}))')


def layers():
    return [
        (m, l["namespace"])
        for m, d in data("hyprctl", "layers", "-j").items()
        for ls in d["levels"].values()
        for l in ls
        if l.get("namespace") == "yoga-screen-keyboard"
    ]


def wait(pred):
    for _ in range(100):
        v = pred()
        if v:
            return v
        time.sleep(0.05)
    raise AssertionError("timed out")


if sys.argv[1:] != ["--live"]:
    raise SystemExit("Usage: python3 test_keyboard_focus.py --live")
if not all(
    any(m["name"] == name for m in data("hyprctl", "monitors", "-j"))
    for name in ("eDP-1", "eDP-2")
):
    raise SystemExit("Both internal screens must be enabled")
original = data("hyprctl", "activewindow", "-j").get("address")
child = """import gi
gi.require_version('Gtk','4.0')
from gi.repository import Gtk
app=Gtk.Application(application_id='org.gon7187.FocusRegression')
def activate(a):
 for title,widget in [('Yoga field regression',Gtk.Entry()),('Yoga video regression',Gtk.Button(label='Video-like non-text focus'))]:
  w=Gtk.ApplicationWindow(application=a,title=title);w.set_default_size(500,300);w.set_child(widget);w.present();widget.grab_focus()
app.connect('activate',activate);app.run([])
"""
p = subprocess.Popen([sys.executable, "-c", child], stdout=subprocess.DEVNULL)
try:

    def windows():
        cs = data("hyprctl", "clients", "-j")
        return {
            c["title"]: c for c in cs if c.get("class") == "org.gon7187.FocusRegression"
        }

    cs = wait(lambda: (x if len(x) == 2 else None) if (x := windows()) else None)
    field = cs["Yoga field regression"]["address"]
    video = cs["Yoga video regression"]["address"]
    for addr, monitor in [(field, "eDP-2"), (video, "eDP-1")]:
        dispatch(
            f'hl.dispatch(hl.dsp.window.move({{window="address:{addr}",monitor="{monitor}",follow=false}}))'
        )
    dispatch(
        f'hl.dispatch(hl.dsp.window.fullscreen({{window="address:{video}",internal=2,client=2}}))'
    )
    focus(field)
    wait(lambda: ("eDP-2", "yoga-screen-keyboard") in layers())
    focus(video)
    seen = []
    for _ in range(35):
        w = windows()["Yoga video regression"]
        seen.append((w["fullscreen"], layers()))
        time.sleep(0.04)
    assert all(
        mode == 2 and ("eDP-1", "yoga-screen-keyboard") not in ls for mode, ls in seen
    ), seen
    print(
        "PASS: lower input -> upper fullscreen non-text preserves fullscreen and keyboard target"
    )
finally:
    p.terminate()
    p.wait(timeout=5)
    if original:
        focus(original)
