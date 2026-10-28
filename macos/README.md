# Simeiomatarion

Simeiomatarion is a native text and code editor for Apple Silicon Macs: tabs, side-by-side panes, syntax highlighting for dozens of languages, regular-expression search, and table and document views for CSV, PDF and Word files.

## Build

Command Line Tools are enough. Full Xcode is not required.

The editing engine is compiled from the third-party source tree at `upstream/` (see [`NOTICE`](../NOTICE)), which is not stored in this repository. The Makefile runs [`scripts/fetch-upstream.sh`](../scripts/fetch-upstream.sh) to fetch it at the pinned commit when it is missing. You can also run that script yourself.

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
- Syntax highlighting and code folding through Lexilla, using the bundled `langs.model.xml`
- Find, find previous, replace, and replace all
- Regular expressions through Boost.Regex (`SCFIND_REGEXP | SCFIND_POSIX`)
- Record, stop, play, and persist one macro
- UTF-8, UTF-8 with BOM, UTF-16 LE, UTF-16 BE, and Windows-1252
- CRLF, CR, and LF, including conversion
- Font, tab width, spaces, wrap, line numbers, and whitespace settings
- Menu shortcuts stored as `command=keys` lines in Preferences
- Session restore, and recovery of dirty buffers every 30 seconds
- A native plugin (`PlugIns/SamplePlugin.dylib`, Plugins → Uppercase Selection)

Settings, macros, recovery files, and extra plugins live in `~/Library/Application Support/Simeiomatarion/`. On first launch, settings from the folder used by builds before 1.0.0 are copied there. Drop extra `dylib` files in the `plugins` folder there.

## License

Licensed under GPL-3.0. Third-party notices: see [NOTICE](../NOTICE).
