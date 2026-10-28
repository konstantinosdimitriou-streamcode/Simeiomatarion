# Architecture

Simeiomatarion is a native AppKit application for Apple Silicon. The editing engine is compiled from the third-party source tree at `upstream/` (see [`NOTICE`](../NOTICE) and [`scripts/fetch-upstream.sh`](../scripts/fetch-upstream.sh)). The application shell in `macos/src` is written for macOS.

## Engine components from `upstream/`

| Component | Source | Role |
| --- | --- | --- |
| Scintilla 5.6.6 | `upstream/scintilla/src` plus `upstream/scintilla/cocoa` | Document model, editing, folding, caret, multiple selections, change history |
| Lexilla 5.5.3 | `upstream/lexilla` | Every bundled lexer, including `LexUser.cxx` |
| Boost.Regex search | `upstream/boostregex`, compiled with `SCI_OWNREGEX` and `BOOST_REGEX_STANDALONE` | Regular-expression search |
| Language table | `macos/src/LangCatalog.mm` | Language name to lexer id (`html` → `hypertext`, `cs` → `cpp`, …) |
| Language keywords and extensions | `upstream/PowerEditor/src/langs.model.xml` | Copied into the app bundle and applied with `SCI_SETKEYWORDS` |
| Styles | `upstream/PowerEditor/src/stylers.model.xml` | Copied into the app bundle |

`LexUser.cxx` includes `windows.h` only to call `_itoa`. `macos/compat/windows.h` supplies that helper so the lexer file is unchanged.

## Application shell

| Area | Implementation |
| --- | --- |
| Window, menus, dialogs, toolbars | `macos/src/AppDelegate.mm` (AppKit) |
| Editor view | `ScintillaView` from Scintilla's Cocoa platform layer, wrapped by `DocumentTab` |
| Plugins | `NppMacPlugin.h` dylib ABI (bundled plugins in `Contents/PlugIns`) |
| Shortcuts | Preferences text map, applied to the menu bar |
| File dialogs | `NSOpenPanel` / `NSSavePanel` |
| Office views | `macos/src/OfficeOpen.mm` (PDFKit, DOC/DOCX through AppKit, XLSX and CSV parsers) |

## Process

`Simeiomatarion` is one arm64 executable. It statically links Scintilla, Lexilla, and Boost search. There is no x86_64 slice.

New files default to LF, which is the macOS convention. Files keep the line endings detected in the buffer (CRLF, CR, or LF). The Line Endings menu runs `SCI_CONVERTEOLS`.

Settings, sessions, macros and recovery files live in `~/Library/Application Support/Simeiomatarion/`.

## Tests

`macos/build/port_tests` runs with every `make test` / `./build.sh`:

- UTF-8 BOM, UTF-16 LE, Windows-1252 fallback, and encode round-trips
- CRLF and CR detection
- `langs.model.xml` mapping for `.cpp`, `.html`, and Python keywords
- `CreateLexer("cpp")`, `CreateLexer("python")`, and a Lexilla catalogue of more than 50 lexers
- An offscreen `ScintillaView`: C++ fold header, literal find, POSIX regex, digit class, replace all
- Find in Files, replace in files, CSV and XLSX parsing

## Not implemented

- Docking panels, function list, spell check, document map, and a style-configurator dialog
- A user-defined-language editor UI (the `user` lexer is linked)
- Column editor, character panel, and a project/workspace panel
- A full shortcut mapper, a run dialog, and a library of named macros (one macro is stored)

Style colors cover the C-family, Python, and HTML/XML lexers directly. Other lexers get their keywords and folding; their colors fall back to the default palette.
