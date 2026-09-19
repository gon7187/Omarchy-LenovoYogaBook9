import threading
import unittest
from unittest.mock import patch

import backend
import system_actions


class ActionTests(unittest.TestCase):
    def test_action_commands_are_whitelisted(self):
        self.assertEqual(
            system_actions.command_for("volume-up"), ["yoga-volume", "raise"]
        )
        self.assertEqual(
            system_actions.command_for("brightness-down"),
            ["yoga-brightness", "--monitor", "eDP-1", "5%-"],
        )
        self.assertEqual(
            system_actions.command_for("displays"),
            ["omarchy-menu", "summon", "display"],
        )
        self.assertEqual(
            system_actions.command_for("power"),
            ["omarchy-shell", "shell", "toggle", "gon7187.power"],
        )

    def test_action_commands_reject_invalid_or_malformed_names(self):
        for action in (None, {}, "rm -rf /", "volume_up"):
            with self.assertRaises(ValueError):
                system_actions.command_for(action)

    def test_runner_reports_invalid_action(self):
        errors = []
        system_actions.ActionRunner(errors.append).launch({})
        self.assertEqual(errors, [{"actionError": "Недопустимое действие"}])

    def test_keyboard_accepts_fn_and_navigation_names(self):
        for key in ("F1", "F12", "Insert", "Prior", "Next"):
            self.assertEqual(
                backend.keyboard_args({"type": "key", "key": key}), ["wtype", "-k", key]
            )

    def test_runner_serializes_volume_and_reaps_failed_process(self):
        class Failed:
            def __init__(self):
                self.release = threading.Event()

            def wait(self):
                self.release.wait()
                return 1

        errors = []
        runner = system_actions.ActionRunner(errors.append)
        process = Failed()
        with patch("system_actions.subprocess.Popen", return_value=process) as popen:
            runner.launch("mute")
            runner.launch("volume-up")
            worker = runner.workers["volume"]
            process.release.set()
            worker.join()
        popen.assert_called_once_with(
            ["yoga-volume", "mute-toggle"],
            stdin=system_actions.subprocess.DEVNULL,
            stdout=system_actions.subprocess.DEVNULL,
            stderr=system_actions.subprocess.DEVNULL,
        )
        self.assertEqual(errors, [{"actionError": "Не удалось выполнить действие"}])
        self.assertNotIn("volume", runner.workers)

    def test_runner_reports_start_error(self):
        errors = []
        runner = system_actions.ActionRunner(errors.append)
        with patch("system_actions.subprocess.Popen", side_effect=OSError):
            runner.launch("audio")
        self.assertEqual(errors, [{"actionError": "Действие недоступно"}])


if __name__ == "__main__":
    unittest.main()
