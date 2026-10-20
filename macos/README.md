# Simeiomatarion

Native arm64 macOS application. It is a GPL-3 derivative of [Notepad++ 8.9.8.1](https://notepad-plus-plus.org/downloads/v8.9.8.1/). The official source is in `../upstream` (tag `v8.9.8.1`, commit `dd40fe45598791e9aa38f3aeb200e10fb3d6338a`).

The Windows shell in `PowerEditor` is Win32 and cannot be compiled on macOS. This port keeps the editing engine from that release and replaces the shell with AppKit.

## Build

Command Line Tools are enough. Full Xcode is not required.

Run this from any directory. The project path contains spaces, so keep the quotes.

```sh
cd "/Users/konstantinosdimitriou/Documents/GitHub/notepad Plus plus/macos"
./build.sh
open "build/Simeiomatarion.app"
```

Or, without rebuilding:

```sh
open "/Users/konstantinosdimitriou/Documents/GitHub/notepad Plus plus/macos/build/Simeiomatarion.app"
```

`make test` also runs `build/port_tests`.

## What you can do

- Edit several documents in tabs
- Drag one or more files onto the window, or onto the Dock icon, to open each in a tab
- Syntax highlighting and code folding through Lexilla, using `langs.model.xml` from this Notepad++ release
- Find, find previous, replace, and replace all
- Regular expressions through the same Boost.Regex search Notepad++ uses (`SCFIND_REGEXP | SCFIND_POSIX`)
- Record, stop, play, and persist one macro
- UTF-8, UTF-8 with BOM, UTF-16 LE, UTF-16 BE, and Windows-1252
- CRLF, CR, and LF, including conversion
- Font, tab width, spaces, wrap, line numbers, and whitespace settings
- Menu shortcuts stored as `command=keys` lines in Preferences
- Session restore, and recovery of dirty buffers every 30 seconds
- A native plugin (`PlugIns/SamplePlugin.dylib`, Plugins → Uppercase Selection)

Settings, macros, recovery files, and extra plugins live in `~/Library/Application Support/NotepadPlusPlus/`. Drop extra `dylib` files in the `plugins` folder there.

## License

Notepad++ is GPL-3. See `../upstream/LICENSE`. Scintilla and Lexilla keep their own licenses in the upstream tree. This macOS shell is covered by the same GPL-3 terms as the Notepad++ work it is derived from.
