# Simeiomatarion

Native arm64 macOS application. It is a GPL-3 derivative of [Notepad++ 8.9.8.1](https://notepad-plus-plus.org/downloads/v8.9.8.1/). The official source is in `../upstream` (tag `v8.9.8.1`, commit `dd40fe45598791e9aa38f3aeb200e10fb3d6338a`).

The Windows shell in `PowerEditor` is Win32 and cannot be compiled on macOS. This port keeps the editing engine from that release and replaces the shell with AppKit.

## Build

Command Line Tools are enough. Full Xcode is not required.

Run this from the repository root.

```sh
cd macos
./build.sh
open "build/Simeiomatarion.app"
```

`make test` also runs `build/port_tests`.

## Version

The version has one source of truth at the repository root:

- `VERSION` holds the app version as `MAJOR.MINOR.PATCH` (semver). It becomes `CFBundleShortVersionString`.
- `BUILD_NUMBER` holds a positive integer. It becomes `CFBundleVersion`.

`macos/Info.plist` holds the placeholders `@VERSION@` and `@BUILD_NUMBER@`. The Makefile fills them in when it copies the plist into the app, and the About box reads the values from the bundle. `make version` prints the current values. `make BUILD_NUMBER=42` overrides the build number for one build without editing the file.

To bump the version:

1. Change `VERSION`: patch for fixes, minor for new features, major for breaking changes.
2. Increase `BUILD_NUMBER` by one. It must go up for every build you ship, including rebuilds of the same version.
3. Move the `## [Unreleased]` notes in `CHANGELOG.md` under a new `## [x.y.z] - YYYY-MM-DD` heading and add the compare link at the bottom.
4. Open a PR to `dev`. After the release is merged into `main`, tag it `vx.y.z`.

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
