#pragma once

#import "ScintillaView.h"

// Edit, Search, and View menu commands.
// `action` is one of the identifiers used by the macOS menus.
void NppRunEditorAction(ScintillaView *editor, NSString *action, NSString *lexer);
void NppPrefixSelectedLines(ScintillaView *editor, NSString *prefix);
