# Simeiomatarion

Simeiomatarion is a native text and code editor for Apple Silicon Macs: tabs, side-by-side panes, syntax highlighting for dozens of languages, regular-expression search, and table and document views for CSV, PDF and Word files.

Simeiomatarion is based on Notepad++ source code under GPL-3. It is not affiliated with or endorsed by the Notepad++ project.

![Simeiomatarion editing a C++ file with syntax highlighting, code folding, tabs and the folder sidebar](docs/screenshots/editor.png)

## Screenshots

| | |
| --- | --- |
| ![Two panes side by side, a Python file on the left and a JavaScript file on the right, each with its own tabs](docs/screenshots/split-view.png) | ![A CSV file shown as a table with column headers](docs/screenshots/csv-table.png) |
| Two panes side by side, each with its own tabs | A CSV file opened as a table |

## Build

Command Line Tools are enough. Full Xcode is not required.

The build compiles the editing engine from the upstream source, which is not stored in this repository. Put it in `upstream/` at the repository root (tag `v8.9.8.1`, commit `dd40fe45598791e9aa38f3aeb200e10fb3d6338a`):

```sh
git clone --depth 1 --branch v8.9.8.1 https://github.com/notepad-plus-plus/notepad-plus-plus.git upstream
```

Run this from the repository root.

```sh
cd macos
./build.sh
open "build/Simeiomatarion.app"
```

Or, without rebuilding, from the `macos` folder:

```sh
open "build/Simeiomatarion.app"
```

`make test` also runs `build/port_tests`.

The version is in [`VERSION`](VERSION) and the build number in [`BUILD_NUMBER`](BUILD_NUMBER). See [Version in macos/README.md](macos/README.md#version) for how to bump it, and [`CHANGELOG.md`](CHANGELOG.md) for what changed.

## What you can do

- Edit several documents in tabs
- Drag one or more files onto the window, or onto the Dock icon, to open each in a tab
- Syntax highlighting and code folding through Lexilla, using the upstream `langs.model.xml`
- Find, find previous, replace, and replace all
- Regular expressions through Boost.Regex (`SCFIND_REGEXP | SCFIND_POSIX`)
- Record, stop, play, and persist one macro
- UTF-8, UTF-8 with BOM, UTF-16 LE, UTF-16 BE, and Windows-1252
- CRLF, CR, and LF, including conversion
- Font, tab width, spaces, wrap, line numbers, and whitespace settings
- Menu shortcuts stored as `command=keys` lines in Preferences
- Session restore, and recovery of dirty buffers every 30 seconds
- A native plugin (`PlugIns/SamplePlugin.dylib`, Plugins → Uppercase Selection)

Settings, macros, recovery files, and extra plugins live in `~/Library/Application Support/NotepadPlusPlus/`. Drop extra `dylib` files in the `plugins` folder there.

## License

GPL-3.0. See [`LICENSE`](LICENSE). Simeiomatarion is based on Notepad++ source code under GPL-3. It is not affiliated with or endorsed by the Notepad++ project. The editing engine uses Scintilla and Lexilla, which keep their own licenses in the upstream tree.
