"""Tests that protect the menu configuration against data loss."""

import json
import os
import stat
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from kumi.main import LauncherBackend

VALID = {"sections": [{"title": "Mine", "items": []}]}
BROKEN = '{"sections": [{"title": "Mine", "items": []}],}'
WRONG_SHAPES = (
    [],
    {"sections": None},
    {"sections": ["text"]},
    {"sections": [{"items": None}]},
    {"sections": [{"items": ["text"]}]},
    {"sections": [{"items": [{"type": "submenu", "items": {}}]}]},
)


class ConfigProtectionTests(unittest.TestCase):
    """Verify safe loading, saving and importing of the configuration."""

    def setUp(self):
        """Create an isolated configuration directory."""
        directory = tempfile.TemporaryDirectory()
        self.addCleanup(directory.cleanup)
        self.directory = Path(directory.name)
        self.path = self.directory / "kumi_config.json"

    def write(self, data, path=None):
        """Write ``data`` as JSON and return the file path."""
        path = path or self.path
        path.write_text(json.dumps(data), encoding="utf-8")
        return path

    def invalid_copies(self):
        """Return the preserved copies of invalid configurations."""
        return list(self.directory.glob("kumi_config.json.invalid-*"))

    def test_missing_file_is_not_an_error(self):
        """Start normally and allow saving on first run."""
        backend = LauncherBackend(self.path)
        self.assertEqual(backend.configError, "")
        self.assertTrue(backend.save_configuration_json(json.dumps(VALID)))

    def test_file_without_sections_is_still_accepted(self):
        """Keep accepting settings-only files, as before."""
        self.write({"show_command": True})
        backend = LauncherBackend(self.path)
        self.assertEqual(backend.configError, "")
        self.assertTrue(backend.showCommand)

    def test_invalid_file_is_never_overwritten(self):
        """Report an unreadable file and leave its bytes untouched."""
        contents = [BROKEN.encode(), b"\xff\xfe\x00"]
        contents += [json.dumps(item).encode() for item in WRONG_SHAPES]
        for content in contents:
            with self.subTest(content=content):
                self.path.write_bytes(content)
                backend = LauncherBackend(self.path)
                self.assertNotEqual(backend.configError, "")
                backend.showCommand = True
                backend.promptArguments = True
                backend.showOutputWindow = False
                backend.shortcutModifier = "Alt"
                self.assertFalse(
                    backend.save_configuration_json(json.dumps(VALID))
                )
                self.assertEqual(self.path.read_bytes(), content)

    def test_export_cannot_overwrite_invalid_file(self):
        """Refuse to export on top of the file that could not be loaded."""
        self.path.write_text(BROKEN, encoding="utf-8")
        backend = LauncherBackend(self.path)
        self.assertFalse(backend.export_configuration(str(self.path)))
        self.assertEqual(self.path.read_text(encoding="utf-8"), BROKEN)

    def test_import_recovers_and_preserves_invalid_file(self):
        """Keep a copy of the invalid file before replacing it."""
        self.path.write_text(BROKEN, encoding="utf-8")
        backend = LauncherBackend(self.path)
        backup = self.write(VALID, self.directory / "backup.json")
        self.assertTrue(backend.import_configuration(str(backup)))
        self.assertEqual(backend.configError, "")
        copies = self.invalid_copies()
        self.assertEqual(len(copies), 1)
        self.assertEqual(copies[0].read_text(encoding="utf-8"), BROKEN)
        reloaded = LauncherBackend(self.path)
        self.assertEqual(reloaded.sections, VALID["sections"])

    def test_import_works_if_invalid_file_was_deleted(self):
        """Allow recovery when there is no longer a file to preserve."""
        self.path.write_text(BROKEN, encoding="utf-8")
        backend = LauncherBackend(self.path)
        self.path.unlink()
        backup = self.write(VALID, self.directory / "backup.json")
        self.assertTrue(backend.import_configuration(str(backup)))
        self.assertEqual(self.invalid_copies(), [])

    def test_import_stops_if_invalid_file_cannot_be_copied(self):
        """Do not replace the invalid file without preserving it."""
        self.path.write_text(BROKEN, encoding="utf-8")
        backend = LauncherBackend(self.path)
        backup = self.write(VALID, self.directory / "backup.json")
        with patch.object(
            backend, "_preserve_invalid_config", side_effect=OSError("no")
        ):
            self.assertFalse(backend.import_configuration(str(backup)))
        self.assertEqual(self.path.read_text(encoding="utf-8"), BROKEN)

    def test_interrupted_save_keeps_previous_file_and_state(self):
        """Leave the old configuration intact when replacement fails."""
        self.write(VALID)
        original = self.path.read_bytes()
        backend = LauncherBackend(self.path)
        with patch("kumi.main.os.replace", side_effect=OSError("disk full")):
            self.assertFalse(
                backend.save_configuration_json('{"sections": []}')
            )
        self.assertEqual(self.path.read_bytes(), original)
        self.assertEqual(backend.sections, VALID["sections"])
        self.assertEqual(list(self.directory.glob("*.tmp")), [])

    def test_failed_import_restores_previous_state(self):
        """Report failure and keep the current menu and settings."""
        self.write(VALID)
        backend = LauncherBackend(self.path)
        backup = self.write(
            {"sections": [], "show_command": True},
            self.directory / "backup.json",
        )
        with patch("kumi.main.os.replace", side_effect=OSError("disk full")):
            self.assertFalse(backend.import_configuration(str(backup)))
        self.assertEqual(backend.sections, VALID["sections"])
        self.assertFalse(backend.showCommand)

    def test_invalid_structures_are_rejected_on_save_and_import(self):
        """Reject malformed data without changing the current file."""
        self.write(VALID)
        original = self.path.read_bytes()
        backend = LauncherBackend(self.path)
        for data in WRONG_SHAPES:
            with self.subTest(data=data):
                self.assertFalse(
                    backend.save_configuration_json(json.dumps(data))
                )
                source = self.write(data, self.directory / "bad.json")
                self.assertFalse(backend.import_configuration(str(source)))
                self.assertEqual(self.path.read_bytes(), original)

    def test_save_preserves_permissions_and_symlink(self):
        """Update the symlink target without changing its permissions."""
        target = self.write(VALID, self.directory / "real.json")
        target.chmod(0o640)
        self.path.symlink_to(target)
        backend = LauncherBackend(self.path)
        self.assertTrue(backend.save_configuration_json('{"sections": []}'))
        self.assertTrue(self.path.is_symlink())
        self.assertEqual(stat.S_IMODE(target.stat().st_mode), 0o640)
        self.assertEqual(json.loads(target.read_text())["sections"], [])

    def test_read_only_file_is_not_replaced(self):
        """Respect a file that the user cannot write."""
        self.write(VALID)
        original = self.path.read_bytes()
        backend = LauncherBackend(self.path)
        with patch("kumi.main.os.access", return_value=False):
            self.assertFalse(
                backend.save_configuration_json('{"sections": []}')
            )
        self.assertEqual(self.path.read_bytes(), original)
        self.assertTrue(os.path.exists(self.path))


if __name__ == "__main__":
    unittest.main()
