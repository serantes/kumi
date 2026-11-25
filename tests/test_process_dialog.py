"""Integration tests for the launcher UI and supervised processes."""

import json
import os
import tempfile
import time
import unittest
from pathlib import Path
from unittest.mock import patch

from PySide6.QtCore import QMetaObject, QObject, QPointF, QProcess, Qt
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlApplicationEngine
from PySide6.QtQuick import QQuickWindow
from PySide6.QtTest import QTest

from kumi import __version__
from kumi.main import LauncherBackend, ProcessRunner


class ProcessDialogTests(unittest.TestCase):
    """Exercise process controls, notifications and menu editing."""

    @classmethod
    def setUpClass(cls):
        """Create the shared Qt application."""
        cls.app = QGuiApplication.instance() or QGuiApplication([])
        cls.app.setApplicationVersion(__version__)
        cls.app.setQuitOnLastWindowClosed(False)

    def setUp(self):
        """Create an isolated backend, process runner and QML window."""
        self.temp_dir = tempfile.TemporaryDirectory()
        self.backend = LauncherBackend(
            Path(self.temp_dir.name) / "config.json"
        )
        self.runner = ProcessRunner()
        self.engine = QQmlApplicationEngine()
        self.engine.rootContext().setContextProperty("backend", self.backend)
        self.engine.rootContext().setContextProperty(
            "processRunner", self.runner
        )
        self.engine.load(
            str(Path(__file__).resolve().parents[1] / "src/kumi/main.qml")
        )
        self.assertTrue(self.engine.rootObjects())
        self.window = self.engine.rootObjects()[0]
        self.dialog = self.window.findChild(QObject, "terminalDialog")
        self.button = self.window.findChild(QObject, "processActionButton")
        self.assertIsNotNone(self.dialog)
        self.assertIsNotNone(self.button)

    def tearDown(self):
        """Stop processes and release the window and temporary data."""
        self.runner.terminate_process()
        self.runner._process.waitForFinished(3000)
        self.window.close()
        self.engine.deleteLater()
        self.app.processEvents()
        self.temp_dir.cleanup()

    def wait_until(self, condition):
        """Process Qt events until a condition holds or the timeout expires."""
        deadline = time.monotonic() + 3
        while not condition() and time.monotonic() < deadline:
            QTest.qWait(20)
        self.assertTrue(condition())

    def test_application_title_includes_version(self):
        """Show the application version in the window title."""
        self.assertIn(f"Kumi {__version__}", self.window.title())

    def test_abort_remains_available_until_process_exits_then_close(self):
        """Keep Abort available until the process ends, then offer Close."""
        finished = []
        self.runner.processFinished.connect(
            lambda *args: finished.append(args)
        )
        QMetaObject.invokeMethod(self.dialog, "open")
        self.wait_until(lambda: self.dialog.property("opened"))
        self.runner.start_command_with_args("test", "exec sleep 30", "", False)
        self.assertTrue(self.runner.running)
        self.assertEqual(self.button.property("text"), "Abort")

        self.button.clicked.emit()
        self.wait_until(lambda: not self.runner.running)
        self.wait_until(lambda: len(finished) == 1)
        QTest.qWait(50)
        self.assertEqual(len(finished), 1)
        self.assertEqual(self.button.property("text"), "Close")
        self.assertTrue(self.dialog.property("opened"))
        self.button.clicked.emit()
        self.wait_until(lambda: not self.dialog.property("opened"))

    def test_press_outside_closes_dialog_only_when_idle(self):
        """Ignore outside clicks while a supervised process is running."""

        def click_outside():
            """Click near the window corner, outside the output dialog."""
            QTest.mouseClick(
                self.window,
                Qt.LeftButton,
                Qt.NoModifier,
                QPointF(self.window.width() - 5, 5).toPoint(),
            )

        QMetaObject.invokeMethod(self.dialog, "open")
        self.wait_until(lambda: self.dialog.property("opened"))
        self.runner.start_command_with_args("test", "exec sleep 30", "", False)
        click_outside()
        QTest.qWait(500)
        self.assertTrue(self.dialog.property("opened"))
        self.assertTrue(self.runner.running)

        self.button.clicked.emit()
        self.wait_until(lambda: not self.runner.running)
        click_outside()
        self.wait_until(lambda: not self.dialog.property("opened"))

    def test_button_changes_to_close_on_success(self):
        """Replace Abort with Close after successful execution."""
        QMetaObject.invokeMethod(self.dialog, "open")
        self.wait_until(lambda: self.dialog.property("opened"))
        self.runner.start_command_with_args("test", "true", "", False)
        self.assertEqual(self.button.property("text"), "Abort")
        self.wait_until(lambda: not self.runner.running)
        self.assertEqual(self.button.property("text"), "Close")

    def test_failed_start_reports_completion_once(self):
        """Report a process startup failure exactly once."""
        finished = []
        self.runner.processFinished.connect(
            lambda *args: finished.append(args)
        )
        self.runner._process.start("/nonexistent-kumi-test-command")
        self.wait_until(lambda: bool(finished))
        self.assertFalse(self.runner.running)
        self.assertEqual(len(finished), 1)
        self.assertEqual(finished[0][0], -1)
        self.assertEqual(self.button.property("text"), "Close")

    def test_escape_closes_application(self):
        """Allow Escape to close an idle application."""
        self.window.requestActivate()
        QTest.qWait(50)
        QTest.keyClick(self.window, Qt.Key.Key_Escape)
        self.wait_until(lambda: not self.window.isVisible())

    def test_escape_does_not_close_application_while_process_runs(self):
        """Prevent Escape from closing a running supervised process."""
        self.runner.start_command_with_args("test", "exec sleep 30", "", False)
        self.window.requestActivate()
        QTest.qWait(50)
        QTest.keyClick(self.window, Qt.Key.Key_Escape)
        QTest.qWait(100)
        self.assertTrue(self.window.isVisible())
        self.assertTrue(self.runner.running)

    def test_escape_disabled_until_output_process_finishes(self):
        """Keep the output dialog and application open while a process runs."""
        QMetaObject.invokeMethod(self.dialog, "open")
        self.wait_until(lambda: self.dialog.property("opened"))
        self.runner.start_command_with_args("test", "exec sleep 30", "", False)
        self.window.requestActivate()
        QTest.qWait(50)
        QTest.keyClick(self.window, Qt.Key.Key_Escape)
        QTest.qWait(100)
        self.assertTrue(self.window.isVisible())
        self.assertTrue(self.dialog.property("opened"))
        self.assertTrue(self.runner.running)
        self.assertEqual(self.button.property("text"), "Abort")

        self.button.clicked.emit()
        self.wait_until(lambda: not self.runner.running)
        self.assertEqual(self.button.property("text"), "Close")
        QTest.keyClick(self.window, Qt.Key.Key_Escape)
        self.wait_until(lambda: not self.window.isVisible())

    def test_escape_available_while_detached_process_runs(self):
        """Allow Escape while an independently launched process runs."""
        results = []
        start_detached = QProcess.startDetached

        def capture_start(*args):
            """Record the detached process result for verification."""
            result = start_detached(*args)
            results.append(result)
            return result

        try:
            with patch.object(
                QProcess, "startDetached", side_effect=capture_start
            ):
                self.runner.start_command_with_args(
                    "test", "exec sleep 1", "", True
                )
            started, pid = results[0]
            self.assertTrue(started)
            os.kill(pid, 0)
            self.assertFalse(self.runner.running)
            self.window.requestActivate()
            QTest.qWait(50)
            QTest.keyClick(self.window, Qt.Key.Key_Escape)
            self.wait_until(lambda: not self.window.isVisible())
            os.kill(pid, 0)
        finally:
            QTest.qWait(1100)

    def test_notify_only_for_enabled_supervised_commands(self):
        """Notify only when requested for supervised commands."""
        with patch.object(self.runner, "_send_notification") as notify:
            self.runner.start_command_with_args(
                "quiet", "true", "", False, False
            )
            self.wait_until(lambda: not self.runner.running)
            notify.assert_not_called()

            self.runner.start_command_with_args(
                "success", "true", "", False, True
            )
            self.wait_until(lambda: notify.call_count == 1)
            notify.assert_called_with(0)

            self.runner.start_command_with_args(
                "failure", "exit 7", "", False, True
            )
            self.wait_until(lambda: notify.call_count == 2)
            notify.assert_called_with(7)

            self.runner.start_command_with_args(
                "detached", "true", "", True, True
            )
            QTest.qWait(100)
            self.assertEqual(notify.call_count, 2)

    def test_notification_actions_target_the_original_command(self):
        """Retain the original execution when processing a retry action."""
        script = Path(self.temp_dir.name) / "notify-send"
        script.write_text(
            '#!/bin/sh\nprintf "%s\\n" "$@" > "$NOTIFY_ARGS"\nprintf retry\n',
            encoding="utf-8",
        )
        script.chmod(0o755)
        args_file = Path(self.temp_dir.name) / "notify-args"
        self.runner._last_name = "Original"
        self.runner._last_base_command = "echo original"
        self.runner._last_extra_args = "argument"
        self.runner._last_log_path = str(
            Path(self.temp_dir.name) / "error.log"
        )
        with (
            patch.dict(
                os.environ,
                {
                    "PATH": self.temp_dir.name,
                    "NOTIFY_ARGS": str(args_file),
                },
            ),
            patch.object(self.runner, "start_command_with_args") as retry,
        ):
            self.runner._send_notification(1)
            self.runner._last_name = "Later"
            self.runner._last_base_command = "echo later"
            self.wait_until(lambda: retry.called)
        retry.assert_called_once_with(
            "Original", "echo original", "argument", False, True
        )
        args = args_file.read_text(encoding="utf-8").splitlines()
        self.assertIn("--action=view=View Log", args)
        self.assertIn("Command failed: Original", args)

    def test_detached_launch_does_not_replace_supervised_notification(self):
        """Keep supervised notification data when launching a detached item."""
        with patch.object(self.runner, "_send_notification") as notify:
            self.runner.start_command_with_args(
                "supervised", "sleep 0.2", "", False, True
            )
            self.runner.start_command_with_args(
                "detached", "true", "", True, False
            )
            self.wait_until(lambda: notify.called)
            self.assertEqual(self.runner._last_name, "supervised")
            notify.assert_called_once_with(0)

    def test_notification_failure_is_reported(self):
        """Report a missing notification executable."""
        errors = []
        self.runner.notificationError.connect(errors.append)
        with patch.dict(os.environ, {"PATH": self.temp_dir.name}):
            self.runner._send_notification(0)
            self.wait_until(lambda: bool(errors))
        self.assertIn("notify-send", errors[0])

    def test_menu_launch_uses_item_notification_setting(self):
        """Pass the selected item's notification preference to the runner."""
        with patch.object(self.runner, "_send_notification") as notify:
            self.window.executeActionItem(
                {"name": "quiet", "command": "true", "notify": False}
            )
            self.wait_until(lambda: not self.runner.running)
            notify.assert_not_called()
            self.window.executeActionItem(
                {"name": "notify", "command": "true", "notify": True}
            )
            self.wait_until(lambda: notify.call_count == 1)

    def test_view_log_action_uses_notification_log(self):
        """Open the log associated with the selected notification."""
        script = Path(self.temp_dir.name) / "notify-send"
        script.write_text("#!/bin/sh\nprintf view\n", encoding="utf-8")
        script.chmod(0o755)
        self.runner._last_name = "Original"
        self.runner._last_log_path = "/tmp/original-kumi-test.log"
        with (
            patch.dict(os.environ, {"PATH": self.temp_dir.name}),
            patch.object(
                QProcess, "startDetached", return_value=(True, 123)
            ) as open_log,
        ):
            self.runner._send_notification(1)
            self.runner._last_log_path = "/tmp/later-kumi-test.log"
            self.wait_until(lambda: open_log.called)
        open_log.assert_called_once_with(
            "xdg-open", ["/tmp/original-kumi-test.log"]
        )

    def test_history_preserves_notification_setting(self):
        """Keep the notification preference in persisted history."""
        self.backend.record_history(
            {"name": "quiet", "command": "true", "notify": False}, ""
        )
        self.assertFalse(self.backend.favorites[0]["notify"])
        history = json.loads(
            (Path(self.temp_dir.name) / "kumi_history.json").read_text()
        )
        self.assertFalse(history[0]["notify"])

    def test_removing_recent_updates_view_and_persists_without_running(self):
        """Remove recent entries without running or changing statistics."""
        config = {
            "sections": [
                {
                    "title": "Test",
                    "items": [
                        {
                            "name": "Command",
                            "command": "echo test",
                            "type": "action",
                        }
                    ],
                }
            ]
        }
        self.backend.save_configuration_json(json.dumps(config))
        item = {"name": "Command", "command": "echo test", "notify": False}
        self.backend.record_history(item, "first")
        self.backend.record_history(item, "second")
        stats_before = self.backend.get_execution_stats()

        recent = next(
            obj
            for obj in self.window.findChildren(QObject)
            if obj.property("text") == "Recent" and hasattr(obj, "clicked")
        )
        recent.clicked.emit()

        def find_buttons(item):
            """Find visible recent-item removal buttons in the visual tree."""
            found = []
            if item.objectName() == "removeRecentButton" and item.isVisible():
                found.append(item)
            for child in item.childItems():
                found.extend(find_buttons(child))
            return found

        self.wait_until(
            lambda: len(find_buttons(self.window.contentItem())) == 2
        )
        buttons = find_buttons(self.window.contentItem())
        first = min(
            buttons, key=lambda button: button.mapToScene(QPointF()).y()
        )
        point = first.mapToScene(
            QPointF(first.width() / 2, first.height() / 2)
        )
        QTest.mouseClick(
            self.window, Qt.LeftButton, Qt.NoModifier, point.toPoint()
        )
        self.wait_until(lambda: len(self.backend.favorites) == 1)
        self.assertEqual(self.backend.favorites[0]["arguments"], "first")
        self.assertEqual(len(find_buttons(self.window.contentItem())), 1)
        self.assertFalse(self.runner.running)
        self.assertEqual(self.backend.sections, config["sections"])
        self.assertEqual(self.backend.get_execution_stats(), stats_before)
        reloaded = LauncherBackend(Path(self.temp_dir.name) / "config.json")
        self.assertEqual(reloaded.favorites[0]["arguments"], "first")
        self.assertEqual(len(reloaded.favorites), 1)
        button = find_buttons(self.window.contentItem())[0]
        point = button.mapToScene(
            QPointF(button.width() / 2, button.height() / 2)
        )
        QTest.mouseClick(
            self.window, Qt.LeftButton, Qt.NoModifier, point.toPoint()
        )
        self.wait_until(lambda: not self.backend.favorites)
        self.assertEqual(
            LauncherBackend(
                Path(self.temp_dir.name) / "config.json"
            ).favorites,
            [],
        )
        self.assertEqual(self.backend.get_execution_stats(), stats_before)

    def test_removing_recent_reports_save_failure_and_keeps_item(self):
        """Keep the item and report an error if history cannot be saved."""
        item = {"name": "Command", "command": "true"}
        self.backend.record_history(item, "")
        errors = []
        self.backend.statusNotification.connect(
            lambda message, success: errors.append((message, success))
        )
        with patch(
            "kumi.main.os.replace", side_effect=PermissionError("denied")
        ):
            self.backend.remove_recent("Command", "true", "")
        self.assertEqual(len(self.backend.favorites), 1)
        reloaded = LauncherBackend(Path(self.temp_dir.name) / "config.json")
        self.assertEqual(len(reloaded.favorites), 1)
        self.assertEqual(
            list(Path(self.temp_dir.name).glob(".kumi_history_*.tmp")), []
        )
        self.assertTrue(errors)
        self.assertFalse(errors[-1][1])

    def test_editor_defaults_and_mutually_exclusive_options(self):
        """Default both options to off and keep them mutually exclusive."""
        self.backend.save_configuration_json(
            json.dumps({"sections": [{"title": "Test", "items": []}]})
        )

        def find_button(text):
            """Find a button by its displayed text."""
            return next(
                (
                    obj
                    for obj in self.window.findChildren(QObject)
                    if obj.property("text") == text and hasattr(obj, "clicked")
                ),
                None,
            )

        def find_visual(name):
            """Find a named item in the window's visual tree."""

            def walk(item):
                """Search the visual tree recursively."""
                if item.objectName() == name:
                    return item
                for child in item.childItems():
                    found = walk(child)
                    if found:
                        return found
                return None

            self.assertIsInstance(self.window, QQuickWindow)
            return walk(self.window.contentItem())

        self.wait_until(lambda: find_button("Settings") is not None)
        find_button("Settings").clicked.emit()
        self.wait_until(lambda: find_button("Open Menu Editor") is not None)
        find_button("Open Menu Editor").clicked.emit()
        self.wait_until(lambda: find_button("Add Item") is not None)
        find_button("Add Item").clicked.emit()
        self.wait_until(lambda: find_visual("notifySwitch") is not None)
        notify = find_visual("notifySwitch")
        detached = find_visual("detachedSwitch")
        self.assertFalse(notify.property("checked"))
        self.assertFalse(detached.property("checked"))

        QMetaObject.invokeMethod(notify, "click")
        self.wait_until(
            lambda: find_visual("notifySwitch").property("checked")
        )
        QMetaObject.invokeMethod(find_visual("detachedSwitch"), "click")
        self.wait_until(
            lambda: find_visual("detachedSwitch").property("checked")
        )
        self.assertFalse(find_visual("notifySwitch").property("checked"))
        QMetaObject.invokeMethod(find_visual("notifySwitch"), "click")
        self.wait_until(
            lambda: find_visual("notifySwitch").property("checked")
        )
        self.assertFalse(find_visual("detachedSwitch").property("checked"))
        item = self.window.property("masterEditableConfig").toVariant()[0][
            "items"
        ][0]
        self.assertTrue(item["notify"])
        self.assertFalse(item["detached"])


if __name__ == "__main__":
    unittest.main()
