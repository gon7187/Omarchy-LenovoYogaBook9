"""Installer rollback checks using a temporary HOME and no desktop/build commands."""

import importlib.util
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


class InstallerTests(unittest.TestCase):
    def test_original_hyprland_entrypoint_is_in_backup(self):
        spec = importlib.util.spec_from_file_location(
            "panel_install", Path(__file__).with_name("install.py")
        )
        assert spec and spec.loader
        installer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(installer)
        with tempfile.TemporaryDirectory() as directory:
            home = Path(directory)
            config = home / ".config/hypr/hyprland.lua"
            config.parent.mkdir(parents=True)
            original = b'-- existing user configuration\nrequire("hypr.input")\n'
            config.write_bytes(original)

            def run(args, **kwargs):
                return subprocess.CompletedProcess(args, 0)

            with (
                patch.object(installer, "HOME", home),
                patch.object(installer, "TARGET", home / ".local/share/yoga-panel"),
                patch.object(installer.subprocess, "run", run),
                patch.object(installer.shutil, "which", return_value="/fixture/tool"),
                patch("sys.argv", ["install.py", "--no-start"]),
            ):
                installer.main()
            backups = list((home / ".local/state/yoga-panel/backups").iterdir())
            self.assertEqual(len(backups), 1)
            saved = backups[0] / ".config/hypr/hyprland.lua"
            self.assertTrue(
                saved.is_file(), "Modified Hyprland entrypoint must be backed up"
            )
            self.assertEqual(saved.read_bytes(), original)
            self.assertIn('require("hypr.minimize")', config.read_text())
            config.write_bytes(saved.read_bytes())
            self.assertEqual(config.read_bytes(), original)


if __name__ == "__main__":
    unittest.main()
