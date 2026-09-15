# Yoga Panel: keyboard and touchpad for the Yoga Book 9

An on-screen RU/EN keyboard across the top of the lower screen and a touchpad
filling the rest of it. Built and tested on a Lenovo Yoga Book 9 13IRU8 (82YQ),
Omarchy / Hyprland 0.56.2, with the lower screen as `eDP-2`.

![Panel](images/panel.png)

The UI labels are in Russian; both layouts are printed on every key.

## Features

### Keyboard

- Both layouts visible at once: EN top-left, RU bottom-right, the active one
  highlighted. Standard row offsets, wide Enter, Caps Lock, two Shifts, arrow
  cluster. Shift respects Russian punctuation; Caps+Shift gives lowercase.
- **Shift**: tap for one capital, hold for capitals until released.
- **Alt+Shift** on the panel keys, in either order, switches the system layout
  too. System layout notifications update the panel; punctuation, space and
  Backspace keep the selected group. The RU/EN key fires once when the tap
  completes; sliding touches are cancelled. Switch acknowledgements guard
  against late events, including after dictation.
- Ctrl, Alt, Shift and **Super 🚀** are one-shot: press the modifier, then the
  key. They combine (Super → Shift → Tab) and reset after input.
  Super → 3 switches to workspace 3.
- **Words** toggles three offline suggestions from a two-letter prefix, shown in
  the header so the keyboard never shifts. **Settings → Autocorrect on space**
  is separate and works with suggestions hidden: a confident correction is
  applied on space, the next Backspace restores the original word, and a
  second space keeps it. Ambiguous candidates are left for manual choice.
  Bundled RU/EN dictionaries of 50k words each (~1.6 MB).
- **🎤 next to space**: hold to record with [Voxtype](https://github.com/peteonrails/voxtype)
  dictation, release to transcribe. Needs Voxtype and its `voxtype.service`
  user unit. For RU/EN use a multilingual model (no `.en`), e.g.
  `voxtype setup --download --model base`, `voxtype config set whisper.model base`,
  `voxtype config set whisper.language auto`, then `systemctl --user restart voxtype`.
- Backspace and arrows repeat while held, tolerating drift inside the key.

### Touchpad

- One finger moves the pointer; tap is a left click.
- Two-finger tap is a right click, even when the fingers land a few
  milliseconds apart. Two fingers moving more than 4 px scroll. Scroll mode
  holds until the fingers lift; small reverse movement at lift-off is filtered
  and a Wayland `axis_stop` is sent.
- Tap, then touch again and move: select / drag. Lifting or cancelling releases
  the button.
- Three-finger swipe right / left: next / previous workspace on the upper
  screen only, skipping workspace 2 (reserved for the lower screen).
- Three-finger swipe down: hide every window on the upper screen's workspace;
  swipe up: bring them back. This goes through `config/hypr/minimize.lua`,
  which the installer copies to `~/.config/hypr/` and requires from
  `hyprland.lua`. The same gesture works on the firmware's emulated touchpad
  through Hyprland.
- **⚙ Settings**: pointer speed and acceleration, scroll speed, inertia.
  Saved to `~/.config/yoga-panel/settings.json`. Zero acceleration means
  constant speed.

### Opening the panel and brightness

- A short three-finger tap, or an **8–10 finger tap on the lower screen**,
  opens a closed panel. Fingers must land together and lift within 0.8 s;
  noticeable movement cancels the gesture.
- A separate service mirrors `intel_backlight` onto the lower panel, including
  changes made from the system UI.

## Installation

Apply the display and touch configuration for your machine from the
[main README](../README.md) first. The panel expects `eDP-1` on top and
`eDP-2` below. Don't apply the 82YQ configuration to another model unchecked.

Requirements: running Hyprland and Quickshell, Python 3, `brightnessctl`,
GCC/G++, `pkg-config`, `wayland-scanner`, and headers for Hyprland, Wayland,
libinput, libdrm, pixman and libxkbcommon. On Arch: `base-devel`, `hyprland`,
`wayland`, `libinput`, `libdrm`, `pixman`, `libxkbcommon`. Node.js is needed
only for the gesture tests.

```bash
git clone https://github.com/pybe/Omarchy-LenovoYogaBook9.git
cd Omarchy-LenovoYogaBook9
python3 yoga-panel/install.py --dry-run
python3 yoga-panel/install.py
~/.local/bin/yoga-panel show
```

The installer builds before replacing anything. Sources and native helpers go
to `~/.local/share/yoga-panel`, commands to `~/.local/bin`, two user units to
`~/.config/systemd/user`. Replaced files are backed up under
`~/.local/state/yoga-panel/backups/`, keeping their relative paths. No root:
it installs no packages and changes no device permissions, kernel, firmware or
bootloader. `--no-start` installs and enables autostart without starting now.

## Updates and diagnostics

The Hyprland plugin is checked against the running Hyprland ABI. On start the
service verifies it is loaded and rebuilds once if not. An API change may still
need source changes. If packages were updated but the session still runs the
old libraries, log out and back in.

```bash
hyprctl plugin list
journalctl --user -u yoga-panel.service -n 40
quickshell ipc -p ~/.local/share/yoga-panel call panel touchStatus
systemctl --user status yoga-brightness-sync.service
```

Diagnostic counters never record typed text. The panel talks to its helpers over
private stdin; there is no network server.

Suggestions and corrections only see the word typed on this panel. Application
text is not read; no history or personal dictionary is kept. The prefix resets
on window, layout or navigation changes and touchpad movement; after 8 s idle a
suggestion is no longer inserted. Moving the caret with an external mouse in the
same field is not always detected, since Wayland exposes no surrounding text here.

### Surviving updates

`install.py` installs an Omarchy `post-update.d/90-yoga-check` hook. After
`omarchy update` it takes a local snapshot and checks services, libraries, the
plugin and the Hyprland configuration. It never restores old settings by itself.
Updating with pacman directly skips the hook; the panel's start-up checks remain.

```bash
yoga-recovery snapshot               # new local snapshot
yoga-recovery check                  # check the running session
yoga-recovery list                   # list snapshots
yoga-recovery verify /path/snapshot  # verify checksums
yoga-recovery restore /path/snapshot # explicitly restore user files
```

Snapshots live in `~/.local/state/yoga-book/backups` (mode 0700) and cover the
panel sources, display/touch/key config, Yoga commands and units, brightness,
audio, dictation and menu settings, and the Omarchy bar layout and user plugins.
They stay on this machine. Compiled files are rebuilt. Voxtype models are not
copied; they stay in `~/.local/share/voxtype/models`. The `/etc` sensor unit is
kept as a reference copy and never restored as root. A restore first snapshots
the current state.

## Tests

```bash
cd yoga-panel
bash build.sh
bash build-gesture.sh
node test_touchpad.cjs
node test_layout.cjs
python3 -m unittest test_prediction test_autocorrect test_workspaces \
  test_defaults_and_language test_voice test_voice_shutdown
python3 test_recovery.py
QT_QPA_PLATFORM=offscreen QT_QUICK_BACKEND=software \
  /usr/lib/qt6/bin/qmltestrunner -input tests
```

`test_touchpad.cjs` runs the production QML JavaScript against recorded-shape
touch sequences: right click including staggered fingers and settling drift,
scrolling with asynchronous finger updates, a stray stationary contact,
tap-drag, cancel, acceleration, three-finger horizontal and vertical swipes,
Super combinations, held Shift, and inertia. The build also runs the open
gesture test.

Interactive checks that briefly take focus in their own test window:
`test_keyboard.py` (RU/EN typing), `test_punctuation_input.py`,
`test_autocorrect_input.py`, `test_delegate_keyboard.py`, and
`test_pointer_wayland.py "$HOME/.local/share/yoga-panel/build/yoga-pointer"`.

On the device: pointer, two-finger scrolling, two-finger right click, held
Shift and workspace switching were confirmed by hand. Palm handling is a
heuristic, not a real palm-rejection driver.

## Scrolling and inertia

![Settings](images/settings.png)

- Scroll speed **1–500 %** in 1 % steps; 100 % is a factor of 0.18.
- Inertia on/off, strength **15–150 %**, duration **0.2–1.5 s**. Velocity decays
  to zero on a cubic curve, driven by Qt Quick `FrameAnimation`'s monotonic
  clock rather than a free-running 16 ms timer.
- Fractional movement accumulates before reaching Wayland, so small values
  aren't lost to protocol rounding.
- Touch, typing, a window change, closing the panel or changing settings stops
  inertia. A pause before lifting does not start a coast.
- **Reverse-inertia guard**: a direction change needs at least 10 logical px,
  three events and 32 ms of reverse movement; until then that axis's velocity
  is zeroed.
- **Repeated flicks**: residual velocity is remembered for 350 ms and a similar
  swipe adds part of it, with a bounded maximum. A late frame (80–500 ms) no
  longer cuts the decay short.

### Hyprland axis-source ordering

On Hyprland efb5099, `axis()` overwrites the pending event including its
source, and `axis_source()` applies to the last axis. The old source → axis
order lost the continuous-scroll type; with `input:emulate_discrete_scroll=1`
a −1…−0.004 sequence became −15 then +15. The pointer helper now sends
CONTINUOUS after **every** axis / axis_stop, before frame.

## Defaults

[`defaults.json`](defaults.json) is the profile a new install starts from:
pointer 2.4× with 0.1 acceleration, scroll 500 %, inertia 150 % / 0.65 s,
suggestions off, autocorrect on. An existing `settings.json` keeps its values
on update; "Reset touchpad" restores the motion values only.

## Workspaces and the lower screen

Swipes only switch the upper `eDP-1`: right goes 1 → 3 → 4 → … → 10 → 1, left
the reverse. Workspace 2 is reserved for the lower screen, and workspaces already
on other monitors are skipped. Focus moves to the upper monitor before an empty
workspace is created. With `eDP-1` disconnected the gesture does nothing.

## Disable / uninstall

```bash
~/.local/bin/yoga-panel stop
systemctl --user disable --now yoga-panel.service yoga-brightness-sync.service
```

Then remove `~/.local/share/yoga-panel`, the installed commands and the two unit
files, and run `systemctl --user daemon-reload`. Settings and backups are kept.

## Credits and licences

The Wayland protocol XML comes from wlr-protocols / wtype, with their licences
kept in the files. The [LICENSE](LICENSE) in this folder covers the panel code.

Dictionaries: [hermitdave/FrequencyWords](https://github.com/hermitdave/FrequencyWords),
pinned revision, **CC BY-SA 4.0**. The data is not covered by the code's MIT
licence; sources, checksums and attribution are in [data/ATTRIBUTION.md](data/ATTRIBUTION.md).

Autocorrect candidates: one extra, missing or wrong letter, or a swap of adjacent
letters, with a two-edit fallback. After «буду/будешь/будет/будем/будете/будут»
an infinitive is preferred («буду провирят» → «буду проверять»). This is a narrow
rule, not a contextual language model. Dictionary words are never replaced.
