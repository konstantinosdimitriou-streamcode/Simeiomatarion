# Changelog

All notable changes to Simeiomatarion are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
The app version lives in [`VERSION`](VERSION) and the build number in [`BUILD_NUMBER`](BUILD_NUMBER).

## [Unreleased]

## [1.0.0] - 2026-10-28

First versioned release of the native arm64 macOS port of Notepad++ 8.9.8.1.

### Added

- Native AppKit shell around the Notepad++ 8.9.8.1 editing engine: Scintilla 5.6.6, Lexilla 5.5.3 and the Boost.Regex search, statically linked into one arm64 executable.
- Tabs, opening files dropped onto the window or the Dock icon, and several files side by side in panes that keep their own tabs and sizes, with in-place compare.
- Syntax highlighting and folding for every Lexilla lexer, with keywords and styles from `langs.model.xml` and `stylers.model.xml`.
- Find, find previous, replace, replace all, regular expressions and Find in Files. The current match is highlighted and scrolled into view, and a document can be closed from its Find in Files row.
- Folder sidebar, outline, minimap, snippets, clipboard history, user languages, HTML preview and text tools.
- View-only Office views for PDF, DOC, DOCX and XLSX, and a table view for CSV.
- Encodings (UTF-8, UTF-8 BOM, UTF-16 LE/BE, Windows-1252) and CRLF/CR/LF detection and conversion.
- One recordable macro, configurable shortcuts, Preferences, session restore and recovery of unsaved buffers.
- Native dylib plugin ABI with bundled sample, MIME tools, converter and JSON tools plugins.
- Localization support and an app icon.
- `VERSION` and `BUILD_NUMBER` as the single source of truth for `CFBundleShortVersionString` and `CFBundleVersion`. The About box shows the version.
- GPL-3.0 `LICENSE` and a README that states the Notepad++ derivative.

### Changed

- The app is named Simeiomatarion.
- A prompt confirms before closing documents. Preferences can turn it off.

[Unreleased]: https://github.com/konstantinosdimitriou-streamcode/Simeiomatarion/compare/v1.0.0...dev
[1.0.0]: https://github.com/konstantinosdimitriou-streamcode/Simeiomatarion/releases/tag/v1.0.0
