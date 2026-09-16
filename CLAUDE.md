# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repository is

Config, scripts and one application for running Omarchy/Hyprland on a **Lenovo Yoga Book 9 13IRU8 (82YQ)** — the dual-screen laptop. Nothing here is a package: `README.md` documents each hardware quirk (what you see → why → fix) and the files under `config/` and `bin/` are the snippets that fix it, copied into `~/.config` and `~/.local/bin` by hand or by `yoga-panel/install.py`.

Two hard assumptions run through everything: **`eDP-1` is the upper panel (mounted 180° out, `transform = 2`), `eDP-2` the lower one.** Device names, backlight mirroring, touch routing, workspace cycling and the panel's monitor lookup all hardcode those strings. Do not generalise them away without being asked.

Hyprland is configured in **Lua**, not `hyprland.conf`. `hyprctl keyword` does not work; test live changes with `hyprctl eval 'hl.monitor({...})'`.

## Layout

- `bin/` — standalone user scripts (`yoga-brightness`, `yoga-autorotate`, `yoga-volume`, `yoga-recovery`, `yoga-mode`, …). Bash or Python, no shebang-less files, installed to `~/.local/bin`.
- `config/` — drop-in fragments mirroring their real destination: `hypr/*.lua`, `systemd/`, `pipewire/`, `wireplumber/`, `udev/`, `libinput/`, `omarchy/` (bar layout `shell.json`, menu, post-update hook, and the `gon7187.*` bar plugins).
- `yoga-panel/` — the on-screen keyboard + touchpad application (see below), with its own Russian `README.md`.
- `README.md` (quirks, applying everything, open items), `HARDWARE.md` (device inventory), `SECUREBOOT.md`, `SWAP.md`, `CHANGELOG.md`.

## yoga-panel architecture

Four processes cooperate; the split is the thing to understand before editing.

1. **`shell.qml`** — Quickshell `ShellRoot`, the whole UI and all gesture state machines, run by `yoga-panel.service`. Keyboard rows come from `KeyboardLayout.js`; the touchpad's `sample()` function inside `shell.qml` is the pointer/scroll/tap/swipe recogniser. Exposes an `IpcHandler` named `panel` (`toggle`, `openPanel`, `hide`, `status`, plus test entry points like `testPrediction`, `touchStatus`, `testCenters`) — that is how `bin/yoga-panel` and the tests drive it.
2. **`backend.py`** — spawned by the QML as a child `Process`, spoken to over **private stdin** with one JSON object per line. It owns settings validation/persistence (`~/.config/yoga-panel/settings.json`, clamped by `LIMITS`, defaults in `defaults.json`), word prediction (`prediction.py`), autocorrect (`autocorrect.py`), Voxtype dictation (`voice.py`), workspace/minimize `hyprctl` commands, and a thread watching Hyprland's `.socket2` for layout and focus changes. There is no socket server and no input logging — keep it that way.
3. **`build/yoga-pointer`, `build/yoga-keyboard`** — small C helpers built from `pointer.c` / `keyboard.c` against the `virtual-pointer` / `virtual-keyboard` Wayland protocols in `protocol/`. All synthetic input goes through these.
4. **`build/yoga-panel-gesture.so`** — a Hyprland C++ plugin (`gesture.cpp`, recogniser in `gesture.hpp`). It forwards touches that land on the `yoga-input-panel` layer surface on `eDP-2` straight to that surface with `info.cancelled = true`, so Hyprland never refocuses the pointer onto the finger, and it recognises the closed-panel open gesture (3-finger, or 8–10-finger, short stationary tap).

Startup order is enforced by `systemd/yoga-panel.service`: `ensure-runtime.py` rebuilds the C helpers if `ldd` shows missing libraries, `ensure-plugin.py` rebuilds/loads the plugin once if the ABI moved, then `quickshell` starts. That is the recovery path after `omarchy update` or a Hyprland bump; `config/omarchy/hooks/90-yoga-check` plus `bin/yoga-recovery` handle snapshots and post-update verification.

`defaults.json` is the single source of truth for defaults — `shell.qml` property initialisers and `backend.py` must agree with it, and `test_defaults_and_language.py` checks that.

## This machine is the test bench

The repo and this laptop are one setup, not a source tree and a separate target. A change is finished only when it is **applied live here and pushed to `origin`** (`github.com/gon7187/Omarchy-LenovoYogaBook9`, branch `main`) — the repo is the canonical copy, the running system is the proof it works. Editing a file under `~/.config` or `~/.local/bin` without bringing the change back into the repo loses it on the next `yoga-recovery restore`.

After editing `yoga-panel/`, reinstall — the service runs from `~/.local/share/yoga-panel`, a copy, not a symlink, so repo edits change nothing until then:

```bash
python3 yoga-panel/install.py          # rebuilds, backs up, restarts the units
~/.local/bin/yoga-panel show
```

After editing `bin/` or a whole-file config (`config/hypr/minimize.lua`, `yoga-windows.lua`, `config/omarchy/shell.json`, the `gon7187.*` bar plugins, systemd units), `install.py` copies most of them too; for anything it does not carry, copy it to its destination yourself and reload what owns it (`systemctl --user daemon-reload`, `hyprctl reload`, `omarchy-restart-shell`). `omarchy-shell shell rescanPlugins` logs "reloading" for a changed bar plugin but keeps the cached old QML — restart the shell to see an edit.

**`config/hypr/bindings.lua`, `monitors.lua` and `autostart.lua` are snippets, not whole files** — their live counterparts are longer and include Omarchy's own content. Merge by hand in both directions; never copy them over `~/.config/hypr/`.

## Build and test

```bash
cd yoga-panel
bash build.sh                    # wayland-scanner + gcc -Werror → build/yoga-pointer, build/yoga-keyboard
bash build-gesture.sh            # runs test-gesture, then builds the plugin .so (atomic mv: never truncate the mapped inode)
python3 install.py --dry-run     # shows every destination; then run without the flag
```

Offline tests (safe anywhere):

```bash
node test_touchpad.cjs                      # extracts sample() out of shell.qml and replays touch sequences
node test_layout.cjs                        # KeyboardLayout.js
python3 -m unittest test_prediction test_autocorrect test_voice test_workspaces test_recovery test_defaults_and_language
python3 -m unittest test_autocorrect.CorrectionTests.test_name   # single test
python3 -m py_compile backend.py ensure-plugin.py install.py
```

Tests needing a live Wayland/Hyprland session (they spawn their own exclusive Quickshell surface and inject into it): `test_keyboard.py`, `test_delegate_keyboard.py`, `test_autocorrect_input.py`, `test_punctuation_input.py`, `test_pointer_wayland.py`, `test_voice_shutdown.py`. Run them with `python3 <file>`; they briefly take focus.

`test_touchpad.cjs` parses the production QML text rather than a copy — renaming `sample()` or the `onPressed:` marker after it breaks the harness.

Diagnostics on a running system:

```bash
journalctl --user -u yoga-panel.service -n 40
quickshell ipc -p ~/.local/share/yoga-panel call panel touchStatus
hyprctl plugin list
```

## Conventions

- Prose for the owner — `CHANGELOG.md`, `yoga-panel/README.md`, user-visible QML strings and `notify-send` text — is **Russian**. Code comments, docstrings and git commit messages are **English**. The top-level `README.md` is English (upstream's) with a Russian fork section at the top.
- Python here is deliberately compact: no spaces around `=` in calls and assignments, single-line `if`/`def` bodies, module docstrings that state the security/privacy boundary. Match the surrounding file rather than reformatting it.
- Comments explain *why* a non-obvious line exists (an ABI quirk, a race, a driver bug), not what it does.
- A behaviour change gets a dated `CHANGELOG.md` entry at the top, in the existing `## YYYY-MM-DD — short title` form, naming the file and the reason.
- `install.py` backs up every file it replaces into `~/.local/state/yoga-panel/backups/<timestamp>/` and never needs root, installs packages, or touches kernel/firmware/bootloader. Preserve that: it is stated in the README as a guarantee.
- Dictionaries in `yoga-panel/data/` are CC BY-SA 4.0, not covered by the code's MIT licence — see `data/ATTRIBUTION.md` before touching them.
