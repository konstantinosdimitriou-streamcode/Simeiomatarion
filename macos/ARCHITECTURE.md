# Architecture

## Why this is not a line-by-line Win32 compile

Notepad++ 8.9.8.1's application is `PowerEditor`: about 123 C++ files built around `windows.h`, dialog resources, GDI, COM, and the Win32 plugin ABI (`NppPlugin`). That shell has no Cocoa implementation in the 8.9.8.1 tree. Compiling it on macOS would require a Win32 emulator. That would not be a native arm64 AppKit application and would not meet the "no Rosetta" requirement.

The editing engine is separate and already has a Cocoa port in this same tree.

## Reused from v8.9.8.1

| Component | Source | Role on macOS |
| --- | --- | --- |
| Scintilla 5.6.6 | `upstream/scintilla/src` plus `upstream/scintilla/cocoa` | Document model, editing, folding, caret, multiple selections, change history |
| Lexilla 5.5.3 | `upstream/lexilla` | Every lexer shipped with this release, including `LexUser.cxx` |
| Boost.Regex search | `upstream/boostregex`, compiled with `SCI_OWNREGEX` and `BOOST_REGEX_STANDALONE` | Same regular-expression path as `scintilla/win32/Scintilla.vcxproj` |
| Language table | `ScintillaEditView::_langNameInfoArray` | Language name to lexer id (`html` → `hypertext`, `cs` → `cpp`, …) |
| Language keywords and extensions | `PowerEditor/src/langs.model.xml` | Copied into the app bundle and applied with `SCI_SETKEYWORDS` |

`LexUser.cxx` includes `windows.h` only to call `_itoa`. `macos/compat/windows.h` supplies that helper so the lexer itself is still the upstream file.

## Replaced

| Windows piece | macOS replacement |
| --- | --- |
| Win32 frame, menus, dialogs, toolbars | `macos/src/AppDelegate.mm` (AppKit) |
| `ScintillaEditView` Win32 host | `ScintillaView` from the Cocoa port, wrapped by `DocumentTab` |
| Win32 `.dll` plugins | `NppMacPlugin.h` dylib ABI. A Windows Notepad++ plugin cannot be loaded. |
| Shortcut mapper dialog | Preferences text map, applied to the menu bar |
| WinGUp / installer / UAC | Not ported |
| MFC/Win32 file dialogs | `NSOpenPanel` / `NSSavePanel` |

## Process

`NotepadPlusPlus` is one arm64 executable. It statically links Scintilla, Lexilla, and Boost search. There is no x86_64 slice.

New files default to LF, which is the macOS convention. Windows files keep the line endings detected in the buffer (CRLF, CR, or LF). The Line Endings menu runs `SCI_CONVERTEOLS`.

## Tests that passed

`macos/build/port_tests` against this build, 0 failures:

- UTF-8 BOM, UTF-16 LE, Windows-1252 fallback, and encode round-trips
- CRLF and CR detection
- `langs.model.xml` mapping for `.cpp`, `.html`, and Python keywords
- `CreateLexer("cpp")`, `CreateLexer("python")`, and a Lexilla catalogue of more than 50 lexers
- An offscreen `ScintillaView`: C++ fold header, literal find, POSIX regex, digit class, replace all

The app bundle was launched with `testdata/sample.cpp`. It stayed running and created a 1100×792 window, which is the frame size requested in `AppDelegate`.

## Not in this port

These exist in the Windows 8.9.8.1 product and are not implemented here:

- Docking panels, function list, spell check, document map, and the style-configurator dialog
- User-defined-language editor UI (the `user` lexer is linked; there is no UDL dialog)
- Column-editor dialog, character panel, and the project/workspace panel
- The full shortcut mapper, run dialog, and macro library of named macros (one macro is stored)
- Session snapshot of every caret, bookmark, and unsaved untitled buffer beyond the recovery files
- Any Windows-only integration: shell extension, WinGUp, authenticode, UAC, or `NPPM_*` plugin messages

Style colors cover the C-family, Python, and HTML/XML lexers directly. Other lexers still get their keywords and folding; their colors fall back to the default palette.
