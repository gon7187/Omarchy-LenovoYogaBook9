#!/usr/bin/env python3
"""Run the real installer against temporary system paths, without privileges."""

import os
import subprocess
import tempfile
from pathlib import Path


def main():
    repo = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory() as directory:
        root = Path(directory)
        script = (repo / "bin/yoga-lock-keyboard").read_text()
        for prefix in ("/usr/share", "/usr/local", "/etc"):
            script = script.replace(prefix, str(root) + prefix)
        executable = root / "repo/bin/yoga-lock-keyboard"
        executable.parent.mkdir(parents=True)
        executable.write_text(script)
        executable.chmod(0o755)
        qml = root / "repo/config/omarchy/lock/TouchKeys.qml"
        qml.parent.mkdir(parents=True)
        qml.write_text((repo / "config/omarchy/lock/TouchKeys.qml").read_text())
        lock = root / "usr/share/omarchy/shell/plugins/lock/LockView.qml"
        lock.parent.mkdir(parents=True)
        original = "Item {\n    BorderSurface {\n    }\n}\n"
        lock.write_text(original)
        sddm = root / "etc/sddm.conf.d/zz-yoga-relogin.conf"
        sddm.parent.mkdir(parents=True)
        sddm.write_text("# existing user configuration\n[Autologin]\nRelogin=false\n")
        expected = sddm.read_bytes()
        wrappers = root / "wrappers"
        wrappers.mkdir()
        for name in ("pkexec", "sudo"):
            wrapper = wrappers / name
            wrapper.write_text('#!/bin/sh\nexec "$@"\n')
            wrapper.chmod(0o755)
        env = {**os.environ, "PATH": str(wrappers) + ":" + os.environ["PATH"]}
        for _ in range(2):
            subprocess.run([str(executable), "install"], env=env, check=True)
            assert sddm.read_bytes() == expected, (
                "keyboard installation must preserve SDDM authentication policy"
            )
            assert lock.read_text().count("TouchKeys { view: root }") == 1
        subprocess.run([str(executable), "remove"], env=env, check=True)
        assert lock.read_text() == original
        assert sddm.read_bytes() == expected, (
            "keyboard removal must preserve SDDM configuration"
        )
    print("LOCK_INSTALLER_OK")


if __name__ == "__main__":
    main()
