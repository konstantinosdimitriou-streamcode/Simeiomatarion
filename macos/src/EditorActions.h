#pragma once

#import "ScintillaView.h"

// Commands taken from the Notepad++ 8.9.8.1 Edit, Search, and View menus.
// `action` is one of the identifiers used by the macOS menus.
void NppRunEditorAction(ScintillaView *editor, NSString *action, NSString *lexer);
void NppPrefixSelectedLines(ScintillaView *editor, NSString *prefix);
