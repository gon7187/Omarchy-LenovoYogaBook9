"""Whitelisted, detached desktop actions; never accept shell input."""

import subprocess
import threading

ACTIONS = {
    "mute": ["yoga-volume", "mute-toggle"],
    "volume-down": ["yoga-volume", "lower"],
    "volume-up": ["yoga-volume", "raise"],
    "mic-mute": ["omarchy-audio-input-mute"],
    "brightness-down": ["yoga-brightness", "--monitor", "eDP-1", "5%-"],
    "brightness-up": ["yoga-brightness", "--monitor", "eDP-1", "+5%"],
    "displays": ["omarchy-menu", "summon", "display"],
    "settings": ["omarchy-menu", "summon", "root"],
    "lock": ["omarchy-system-lock"],
    "power": ["omarchy-shell", "shell", "toggle", "gon7187.power"],
    "audio": ["omarchy-shell", "shell", "toggle", "omarchy.audio"],
    "nightlight": ["omarchy", "toggle", "nightlight"],
    "screenshot": ["omarchy-capture-screenshot"],
}


def command_for(action):
    if type(action) is not str or action not in ACTIONS:
        raise ValueError("Invalid action")
    return ACTIONS[action]


class ActionRunner:
    def __init__(self, error):
        self.error = error
        self.workers = {}
        self.lock = threading.Lock()

    def launch(self, action):
        try:
            command = command_for(action)
        except ValueError:
            self.error({"actionError": "Недопустимое действие"})
            return
        key = "volume" if action in ("mute", "volume-down", "volume-up") else action
        with self.lock:
            # Volume repeats share one read-modify-write path; busy repeats are dropped.
            if key in self.workers:
                return
            try:
                process = subprocess.Popen(
                    command,
                    stdin=subprocess.DEVNULL,
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                )
            except OSError:
                self.error({"actionError": "Действие недоступно"})
                return
            worker = threading.Thread(
                target=self.wait, args=(key, process), daemon=True
            )
            self.workers[key] = worker
            worker.start()

    def wait(self, action, process):
        try:
            failed = process.wait() != 0
        except OSError:
            failed = True
        with self.lock:
            self.workers.pop(action, None)
        if failed:
            self.error({"actionError": "Не удалось выполнить действие"})
