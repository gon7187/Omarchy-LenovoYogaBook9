"""Read Omarchy palettes locally; malformed files never escape into QML."""

import re
from pathlib import Path

import tomllib

HEX = re.compile(r"#[0-9a-fA-F]{6}\Z")
NAME = re.compile(r"[a-z0-9][a-z0-9-]*\Z")
SAFE_COLORS = {
    "mode": "dark",
    "background": "#000000",
    "foreground": "#f0f5ff",
    "accent": "#a5d6ff",
}
REQUIRED = ("background", "foreground", "accent")
TOKENS = {
    "mode",
    "accent",
    "selection",
    "muted",
    "background",
    "dark_background",
    "darker_background",
    "lighter_background",
    "foreground",
    "dark_foreground",
    "light_foreground",
    "bright_foreground",
    "red",
    "yellow",
    "orange",
    "green",
    "cyan",
    "blue",
    "magenta",
    "brown",
    "bright_red",
    "bright_yellow",
    "bright_green",
    "bright_cyan",
    "bright_blue",
    "bright_magenta",
    "active_border_color",
    "active_tab_background",
}


def theme_name(value):
    value = value.strip() if isinstance(value, str) else ""
    return value if NAME.fullmatch(value) else "system"


def read_colors(path, require_mode=True):
    with path.open("rb") as source:
        raw = tomllib.load(source)
    colors = {key: value for key, value in raw.items() if key in TOKENS}
    if not isinstance(colors, dict) or (
        require_mode and colors.get("mode") not in ("dark", "light")
    ):
        raise ValueError("Invalid theme mode")
    for key, value in colors.items():
        if key != "mode" and (not isinstance(value, str) or not HEX.fullmatch(value)):
            raise ValueError("Invalid theme colour")
    return colors


def label(name):
    return name.replace("-", " ").title()


def complete(colors):
    return colors.get("mode") in ("dark", "light") and all(
        isinstance(colors.get(key), str) and HEX.fullmatch(colors[key])
        for key in REQUIRED
    )


class Appearance:
    """Stat-driven catalogue/current-theme reader for the private backend."""

    def __init__(
        self, system=Path("/usr/share/omarchy/themes"), user=None, current=None
    ):
        self.system = Path(system)
        self.user = (
            Path.home() / ".config/omarchy/themes" if user is None else Path(user)
        )
        state = (
            Path.home() / ".local/state/omarchy/current"
            if current is None
            else Path(current)
        )
        self.current = state / "theme" if state.name != "theme" else state
        self.theme_file = self.current.parent / "theme.name"
        self.last_good = {"name": "system", "colors": SAFE_COLORS.copy()}
        self.signature = None
        self.last_appearance = None

    def _paths(self):
        paths = [self.system, self.user, self.current, self.theme_file]
        for root in (self.system, self.user):
            try:
                paths.extend(sorted(root.iterdir()))
                paths.extend(sorted(root.glob("*/colors.toml")))
            except OSError:
                pass
        paths.append(self.current / "colors.toml")
        return paths

    def _signature(self):
        result = []
        for path in self._paths():
            try:
                stat = path.stat()
                result.append((str(path), stat.st_mtime_ns, stat.st_size))
            except OSError:
                result.append((str(path), None, None))
        return tuple(result)

    def catalogue(self):
        files = {}
        for root in (self.system, self.user):
            try:
                for path in root.glob("*/colors.toml"):
                    files.setdefault(path.parent.name, {})[root] = path
            except OSError:
                pass
        themes = []
        for name, paths in sorted(files.items()):
            if not NAME.fullmatch(name):
                continue
            try:
                colors = {}
                for root in (self.system, self.user):
                    if root in paths:
                        colors.update(read_colors(paths[root], root == self.system))
                if not complete(colors):
                    raise ValueError("Incomplete theme palette")
                themes.append({"name": name, "label": label(name), "colors": colors})
            except (OSError, ValueError, tomllib.TOMLDecodeError):
                pass
        return themes

    def current_theme(self):
        try:
            name = self.theme_file.read_text().strip()
            if theme_name(name) != name:
                raise ValueError("Invalid current theme name")
            colors = read_colors(self.current / "colors.toml")
            if not complete(colors):
                raise ValueError("Incomplete current palette")
            self.last_good = {"name": name, "colors": colors}
        except (OSError, ValueError, tomllib.TOMLDecodeError):
            pass
        return self.last_good

    def read(self):
        return {
            "appearance": {"themes": self.catalogue(), "current": self.current_theme()}
        }

    def changed(self):
        signature = self._signature()
        if signature == self.signature:
            return None
        self.signature = signature
        appearance = self.read()
        if appearance == self.last_appearance:
            return None
        self.last_appearance = appearance
        return appearance
