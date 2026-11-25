# Kumi user guide

Kumi is a configurable menu for launching applications and scripts. It uses
Qt Quick and KDE Kirigami.

## Requirements and installation

You need Python 3.10 or later, PySide6, Bash, the Qt Quick Controls and KDE
Kirigami 6 QML modules, and the `org.kde.desktop` style. Install the QML
modules and style with your system package manager. Their Qt version must be
compatible with the version used by PySide6.

From the project directory, install Kumi with:

```sh
python3 -m pip install --user .
```

Start it with `kumi` or `python3 -m kumi`. The installation also provides a
desktop launcher and icons. To see the launcher in your application menu, the
installation prefix must be in the XDG data paths and its `bin` directory must
be in `PATH`. Resources installed in a virtual environment do not automatically
appear in the system menu. PySide6 installed from PyPI may use a different Qt
version from your distribution's Qt/KDE packages.

Desktop notifications additionally require `notify-send` from libnotify, with
action support, and a freedesktop.org-compatible notification service.

## Create your first menu

1. Open Kumi and select **Settings** in the sidebar.
2. Select **Open Menu Editor**.
3. Select **Add Section** and enter a name for the section.
4. Select the section, then select **Add Item**.
5. Enter a label, a shell command and, optionally, default arguments. For
   example, use `echo` as the command and `hello` as the arguments.
6. Enable **Show Output** if you want to see the example's output.
7. Select **Save All Changes**. Return to the section and select **Run** or
   click the item to execute it.

The editor holds a working copy: save changes before leaving it. Sections and
items can be reordered with their arrow buttons and removed with their delete
buttons. Removing a section also removes its contents from the configuration
when you save.

### Submenus

Select a section or enter an existing submenu, then choose **Add Submenu**.
Give it a label and select **Enter** to edit its contents. Use **Back** to
return to the parent level. Submenus can contain items and other submenus.

### Item options

- **Notify**: show a desktop notification when a supervised command finishes.
  Depending on the result, the notification offers **Retry** and, when an
  error log is available, **View Log**. Kumi must remain open to handle these
  actions.
- **Ask Args**: open an argument dialog before running the item. You can enter
  arguments or choose previously used arguments for the same command.
- **Show Output**: open a window showing standard output and standard error
  while the command runs.
- **Run Detached**: launch the command independently, without monitoring its
  completion or collecting its output.
- **Shortcut 1** through **Shortcut 9**: assign a keyboard shortcut to the
  item. Choose **No shortcut** to remove the assignment.

New items have these switches disabled. **Notify** and **Run Detached** cannot
both be enabled; enabling one disables the other. For older items without a
`notify` setting, Notify defaults to enabled unless the item is detached.

## Run and find commands

Select a section in the sidebar and click an item or its **Run** button.
Submenus open with their **Open** button; use **Back** to return. The search
field searches action names and descriptions across configured sections and
submenus, regardless of the current section. Clear the search field to return
to the current list.

Kumi combines the command and arguments, expands user paths and environment
variables, and runs the result through Bash. Shell syntax is therefore
interpreted: only run commands you trust, and quote arguments as needed.
Supervised commands receive no interactive standard input.

Only one supervised command runs at a time. Starting another supervised
command stops the previous one; detached commands are independent. If a
supervised command fails, its output window opens even when **Show Output**
is disabled. In that window:

- **Abort** stops the running process; after it ends, the button becomes
  **Close**.
- **Save Log** saves the displayed output to a text file.

Press Escape to close Kumi when no supervised process is running. A detached
process does not block this shortcut.

## Recent items

**Recent** contains up to ten recently launched command-and-argument
combinations. Running the same combination again moves it to the top. Select
an entry to run it again, or use its delete button to remove it from Recent.
Deleting a recent entry does not remove the configured menu item or change
execution statistics. It also removes that entry from the available argument
history.

On startup, Kumi opens Recent if it contains entries; otherwise, it opens the
first configured section, if one exists.

## Settings and shortcuts

Open **Settings** to configure:

- **Always prompt for arguments before running**: prompt for arguments when
  launching items through the menu, even if **Ask Args** is disabled.
- **Show shell command under item title**: display commands on launcher cards.
- **Global Shortcut Modifier (1 to 9)**: choose `Ctrl+Shift` (the default),
  `Ctrl+Alt`, `Meta` or `Alt`. Combine it with an item's assigned number while
  Kumi has focus, for example `Ctrl+Shift+1`. Shortcut launches use the item's
  default arguments without opening the argument dialog.

In the menu editor, these shortcuts are also available:

| Shortcut | Action |
| --- | --- |
| `Ctrl+S` | Save all changes. |
| `Ctrl+Up` / `Ctrl+Down` | Move the selected section or item. |
| `Ctrl++` or `Ctrl+=` | Add a section when the section panel is selected at the root; otherwise add an item. |
| `Ctrl+Shift++` or `Ctrl+Shift+=` | Add a submenu to the current section or submenu. |
| `Ctrl+Delete` | Delete the selected section or item. |
| `Ctrl+Enter` | Enter the selected submenu in the item panel. |

## Statistics

Select **Settings > View Analytics** to see execution counts and last execution
times. Counts are recorded per command. **Reset Statistics** clears them without
clearing Recent or the menu configuration.

The path filter currently matches top-level section names. The **All** option
and nested submenu paths may not show the expected results; select a top-level
section to see its matching commands.

## Backups and data

Select **Settings > Export JSON Backup** to save the menu configuration and
global settings. **Import JSON Backup** replaces those settings and the menu
with the contents of a backup. Backups do not include Recent or statistics.

Kumi stores its data in `$XDG_CONFIG_HOME/kumi/` when `XDG_CONFIG_HOME` is an
absolute path, or in `~/.config/kumi/` otherwise:

| File | Contents |
| --- | --- |
| `kumi_config.json` | Menu sections and global settings. |
| `kumi_history.json` | Recent items and their arguments. |
| `kumi_stats.json` | Execution counts and last execution times. |

To migrate data from an earlier installation, copy the files into this
directory without overwriting data you want to keep. To back up all three
categories, copy all three files separately in addition to, or instead of,
exporting a JSON configuration backup.

### Protection of the configuration file

If `kumi_config.json` exists but cannot be read, is not valid JSON or has an
invalid menu structure, Kumi shows an error and does not overwrite it. Changes
to settings apply only to the current session, and the menu editor cannot save.
Recent items and statistics are not affected.

To recover, either fix the file and restart Kumi, or import a JSON backup.
Before an import replaces an invalid file, Kumi copies it to
`kumi_config.json.invalid-<timestamp>` in the same directory. If the copy
cannot be created, the import is cancelled.

Kumi saves the configuration through a temporary file, so a failed save keeps
the previous version. It follows symbolic links and keeps the permissions of
an existing file. If saving fails, Kumi reports the error.

Failed commands with captured output can also create temporary error logs.
Kumi attempts to remove logs older than 24 hours when it starts.

## Troubleshooting

- **Kumi does not start or the interface fails to load:** verify that PySide6
  and the system Qt/KDE QML modules use compatible Qt versions.
- **The desktop launcher is missing:** check the installation prefix, XDG data
  paths and `PATH` as described under installation.
- **No desktop notification appears:** enable **Notify** for the item, make
  sure it is not detached, and check that `notify-send` and a compatible
  notification service are available. Keep Kumi open to use its actions.
- **A command fails:** inspect the output window or save its log. Remember that
  commands run through Bash and supervised commands cannot prompt for input.
- **A shortcut does not work:** check the item's assigned number, modifier and
  desktop shortcut conflicts, and give Kumi focus.
