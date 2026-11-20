"""Tests for the XDG configuration directory."""

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from kumi.main import _config_dir


class ConfigDirectoryTests(unittest.TestCase):
    """Verify configuration directory selection and creation."""

    def test_uses_absolute_xdg_config_home(self):
        """Create the configuration directory under an absolute XDG path."""
        with tempfile.TemporaryDirectory() as directory:
            with patch.dict(os.environ, {"XDG_CONFIG_HOME": directory}):
                config_dir = _config_dir()
            self.assertEqual(config_dir, Path(directory) / "kumi")
            self.assertTrue(config_dir.is_dir())

    def test_unset_or_relative_xdg_config_home_uses_home(self):
        """Fall back to the home directory for invalid XDG paths.

        XDG_CONFIG_HOME must be absolute.
        """
        with tempfile.TemporaryDirectory() as directory:
            with patch.object(Path, "home", return_value=Path(directory)):
                for value in ("", "relative/path"):
                    with self.subTest(value=value):
                        with patch.dict(
                            os.environ, {"XDG_CONFIG_HOME": value}
                        ):
                            self.assertEqual(
                                _config_dir(),
                                Path(directory) / ".config" / "kumi",
                            )


if __name__ == "__main__":
    unittest.main()
