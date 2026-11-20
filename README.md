# Kumi

Kumi is a configurable menu for launching applications and scripts. Its
interface uses Qt Quick and KDE Kirigami.

## Requirements

- Python 3.10 or later and PySide6.
- The Qt Quick Controls and KDE Kirigami 6 QML modules and the
  `org.kde.desktop` style, installed using the system package manager. They
  must be compatible with the Qt version used by PySide6.
- Bash to run configured commands. Desktop notifications require `notify-send`
  (libnotify) with action support and a freedesktop.org-compatible
  notification service.

## Installation

From the project directory:

```sh
python3 -m pip install --user .
```

The installation provides the `kumi` command, desktop launcher and icons under
the installation prefix. For the application menu to find them, the prefix must
be included in the XDG data paths, and its `bin` directory must be in `PATH`.
In particular, resources installed in a virtual environment do not
automatically appear in the system menu. If using the distribution's Qt/KDE
packages, ensure that PySide6 uses a compatible Qt version; installing PySide6
from PyPI may include a different Qt version.

After installing the package, it can also be started with `python3 -m kumi`.

For detailed instructions, see the [user guide](docs/user-guide.md).

Press Escape to close Kumi when no supervised process is running. Detached
processes do not block this shortcut. In the output dialog, **Abort** stops the
process; once it finishes, the button changes to **Close** and Escape becomes
available again.

New items have **Notify** and **Run Detached** disabled. **Notify** reports
the result and offers actions to retry the command or open its error log.
It is incompatible with **Run Detached** because detached processes are not
supervised; enabling one disables the other. In older configurations without a
`notify` field, the editor's previous default is retained: enabled except for
detached processes. Notification actions require Kumi to remain open.

## Data

Configuration, history and statistics are stored in `$XDG_CONFIG_HOME/kumi/`,
or in `~/.config/kumi/` if `XDG_CONFIG_HOME` is unset. The files are
`kumi_config.json`, `kumi_history.json` and `kumi_stats.json`. To migrate data
from an earlier installation, copy these files into that directory without
overwriting data you wish to keep. Local data files are not included in the
distribution or Git. In **Recent**, the delete button removes an execution from
history without changing the configured menu or statistics.

## Development

To run the tests from the project directory, with PySide6 and the QML modules
listed above installed:

```sh
QT_QPA_PLATFORM=offscreen QT_QUICK_CONTROLS_STYLE=org.kde.desktop \
  PYTHONPATH=src python3 -m unittest discover -s tests -v
```

Check Python style with Flake8:

```sh
flake8 src/kumi tests
```

Qt signals and properties retain their existing camelCase names because they
are part of the QML interface; unittest lifecycle methods use the names
required by the framework.

## License

Kumi is distributed under the GNU General Public License, version 3 or any
later version. See [LICENSE](LICENSE).
