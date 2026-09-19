#!/usr/bin/env python3
"""Receive Fn navigation only in our temporary exclusive Wayland test surface."""

import os
import selectors
import subprocess
import tempfile
import time
from pathlib import Path

BASE = Path(__file__).resolve().parent
SURFACE = """import QtQuick
import Quickshell
import Quickshell.Wayland
PanelWindow {
 screen: Quickshell.screens.find(s=>s.name==="eDP-1") ?? null
 implicitWidth: 500; implicitHeight: 100; color: "#101722"
 exclusionMode: ExclusionMode.Ignore
 WlrLayershell.namespace: "yoga-fn-test"
 WlrLayershell.layer: WlrLayer.Overlay
 WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive
 Text { anchors.centerIn: parent; text: "Проверка F-клавиш Yoga"; color: "white" }
 Item { focus: true; Component.onCompleted: forceActiveFocus()
  Keys.onPressed: event=>{ console.log("FN_INPUT:"+event.key); event.accepted=true; }
 }
 Timer { interval:15000; running:true; onTriggered:Qt.quit() }
}
"""


def main():
    with tempfile.TemporaryDirectory(prefix="yoga-fn-input-") as directory:
        Path(directory, "shell.qml").write_text(SURFACE)
        proc = subprocess.Popen(
            ["quickshell", "-p", directory, "--no-color"],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        assert proc.stdout is not None
        output = ""
        try:
            with selectors.DefaultSelector() as selector:
                selector.register(proc.stdout, selectors.EVENT_READ)
                deadline = time.monotonic() + 12
                sent = False
                # Qt key values: F1, F12, Insert, Home, PageUp, PageDown, End.
                expected = [
                    0x01000030,
                    0x0100003B,
                    0x01000006,
                    0x01000010,
                    0x01000016,
                    0x01000017,
                    0x01000011,
                ]
                while time.monotonic() < deadline and proc.poll() is None:
                    if selector.select(0.2):
                        output += os.read(proc.stdout.fileno(), 65536).decode(
                            errors="replace"
                        )
                    if "Configuration Loaded" in output and not sent:
                        time.sleep(0.3)
                        assert proc.poll() is None
                        subprocess.run(
                            [
                                "quickshell",
                                "ipc",
                                "-p",
                                str(BASE),
                                "call",
                                "panel",
                                "testFunctionKeys",
                            ],
                            check=True,
                            timeout=3,
                        )
                        sent = True
                    received = [
                        int(line.split("FN_INPUT:")[1].strip())
                        for line in output.splitlines()
                        if "FN_INPUT:" in line
                    ]
                    if len(received) >= len(expected):
                        assert received == expected, received
                        print(
                            "PASS: F1/F12/Insert and Fn Home/PageUp/PageDown/End received over Wayland"
                        )
                        return
                raise RuntimeError("Function keys not received:\n" + output)
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait()


if __name__ == "__main__":
    main()
