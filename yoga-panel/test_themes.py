import tempfile
import unittest
from pathlib import Path

from themes import SAFE_COLORS, Appearance


def write(path, text):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(text)


class ThemeTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.base = Path(self.directory.name)
        self.system = self.base / "system"
        self.user = self.base / "user"
        self.current = self.base / "current"
        self.themes = Appearance(self.system, self.user, self.current)

    def tearDown(self):
        self.directory.cleanup()

    def test_reload_overlay_and_malformed_current(self):
        write(
            self.system / "tokyo-night/colors.toml",
            'mode = "dark"\nbackground = "#101010"\nforeground = "#eeeeee"\naccent = "#123456"\nhyprland_active_border = ["rgba(123456ff)", "45deg"]\nmetadata = [1, 2]\n',
        )
        write(self.user / "tokyo-night/colors.toml", 'accent = "#abcdef"\n')
        write(self.current / "theme.name", "tokyo-night\n")
        write(
            self.current / "theme/colors.toml",
            'mode = "dark"\nbackground = "#111111"\nforeground = "#eeeeee"\naccent = "#abcdef"\n',
        )
        first = self.themes.changed()
        assert first is not None
        theme = first["appearance"]["themes"][0]
        self.assertEqual(theme["colors"]["accent"], "#abcdef")
        self.assertNotIn("hyprland_active_border", theme["colors"])
        self.assertEqual(first["appearance"]["current"]["name"], "tokyo-night")
        self.assertIsNone(self.themes.changed())
        write(
            self.current / "theme/colors.toml", 'mode = "dark"\nbackground = "broken"\n'
        )
        self.assertIsNone(self.themes.changed())
        write(self.current / "theme.name", "bad name\n")
        self.assertIsNone(self.themes.changed())
        write(self.current / "theme.name", "tokyo-night\n")
        write(
            self.current / "theme/colors.toml",
            'mode = "light"\nbackground = "#ffffff"\nforeground = "#111111"\naccent = "#abcdef"\n',
        )
        update = self.themes.changed()
        assert update is not None
        self.assertEqual(update["appearance"]["current"]["colors"]["mode"], "light")

    def test_safe_current_without_files(self):
        update = self.themes.changed()
        assert update is not None
        self.assertEqual(update["appearance"]["current"]["colors"], SAFE_COLORS)

    def test_invalid_known_token_is_rejected(self):
        write(
            self.system / "bad/colors.toml",
            'mode = "dark"\nbackground = "#000000"\nforeground = "#ffffff"\naccent = 1\n',
        )
        update = self.themes.changed()
        assert update is not None
        self.assertEqual(update["appearance"]["themes"], [])


if __name__ == "__main__":
    unittest.main()
