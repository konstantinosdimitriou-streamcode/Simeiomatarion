#import "EditorActions.h"

#import "Scintilla.h"

static const int kBookmark = 20;

static NSString *EditorTextRange(ScintillaView *editor, long start, long end) {
	if (end < start) {
		long swap = start;
		start = end;
		end = swap;
	}
	long length = end - start;
	if (length <= 0) {
		return @"";
	}
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = start;
	range.chrg.cpMax = end;
	range.lpstrText = buffer.data();
	[editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	return [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)length encoding:NSUTF8StringEncoding] ?: @"";
}

static NSString *LineText(ScintillaView *editor, long line) {
	long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
	long end = [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
	return EditorTextRange(editor, start, end);
}

static void ReplaceLines(ScintillaView *editor, long startLine, long endLine, NSArray<NSString *> *lines) {
	long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)startLine lParam:0];
	long end = [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)endLine lParam:0];
	NSString *joined = [lines componentsJoinedByString:@"\n"];
	const char *bytes = joined.UTF8String ?: "";
	[editor message:SCI_BEGINUNDOACTION];
	[editor message:SCI_SETTARGETRANGE wParam:(uptr_t)start lParam:end];
	[editor message:SCI_REPLACETARGET wParam:strlen(bytes) lParam:(sptr_t)bytes];
	[editor message:SCI_ENDUNDOACTION];
}

typedef enum {
	LineScopeAll,
	LineScopeSelectionOrAll,
	LineScopeSelectionOrCurrent
} LineScope;

static void MutateLines(ScintillaView *editor, LineScope scope, void (^mutate)(NSMutableArray<NSString *> *lines)) {
	long lineCount = [editor message:SCI_GETLINECOUNT];
	if (lineCount <= 0) {
		return;
	}
	long startLine = 0;
	long endLine = lineCount - 1;
	long selectionStart = [editor message:SCI_GETSELECTIONSTART];
	long selectionEnd = [editor message:SCI_GETSELECTIONEND];
	if (scope != LineScopeAll) {
		if (selectionEnd > selectionStart) {
			startLine = [editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)selectionStart lParam:0];
			endLine = [editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)selectionEnd lParam:0];
			if (endLine > startLine && selectionEnd == [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)endLine lParam:0]) {
				endLine--;
			}
		} else if (scope == LineScopeSelectionOrCurrent) {
			startLine = [editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)selectionStart lParam:0];
			endLine = startLine;
		}
	}
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	for (long line = startLine; line <= endLine; line++) {
		[lines addObject:LineText(editor, line)];
	}
	mutate(lines);
	ReplaceLines(editor, startLine, endLine, lines);
}

static NSString *CommentPrefix(NSString *lexer) {
	NSString *name = lexer.lowercaseString ?: @"";
	if ([@[@"python", @"ruby", @"perl", @"bash", @"r", @"yaml", @"makefile", @"props", @"powershell", @"null"] containsObject:name]) {
		return @"# ";
	}
	if ([@[@"sql", @"lua", @"haskell"] containsObject:name]) {
		return @"-- ";
	}
	if ([@[@"hypertext", @"xml", @"html", @"phpscript"] containsObject:name]) {
		return @"<!--";
	}
	if ([name isEqualToString:@"css"]) {
		return @"/* ";
	}
	return @"// ";
}

static void ToggleLineComment(ScintillaView *editor, NSString *lexer) {
	NSString *prefix = CommentPrefix(lexer);
	if ([prefix isEqualToString:@"<!--"]) {
		long start = [editor message:SCI_GETSELECTIONSTART];
		long end = [editor message:SCI_GETSELECTIONEND];
		NSString *selected = EditorTextRange(editor, start, end);
		NSString *wrapped = [NSString stringWithFormat:@"<!--%@-->", selected];
		const char *bytes = wrapped.UTF8String;
		[editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
		return;
	}
	MutateLines(editor, LineScopeSelectionOrCurrent, ^(NSMutableArray<NSString *> *lines) {
		BOOL allCommented = lines.count > 0;
		for (NSString *line in lines) {
			if (![line hasPrefix:prefix] && ![[line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet] hasPrefix:prefix]) {
				allCommented = NO;
				break;
			}
		}
		for (NSUInteger index = 0; index < lines.count; index++) {
			NSString *line = lines[index];
			if (allCommented) {
				NSRange range = [line rangeOfString:prefix];
				if (range.location != NSNotFound) {
					lines[index] = [line stringByReplacingCharactersInRange:range withString:@""];
				}
			} else if (line.length) {
				lines[index] = [prefix stringByAppendingString:line];
			}
		}
	});
}

static NSString *InvertCase(NSString *text) {
	NSMutableString *result = [NSMutableString stringWithCapacity:text.length];
	[text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *substring, NSRange range, NSRange enclosing, BOOL *stop) {
		(void)range;
		(void)enclosing;
		(void)stop;
		NSString *upper = substring.uppercaseString;
		[result appendString:[substring isEqualToString:upper] ? substring.lowercaseString : upper];
	}];
	return result;
}

static void BookmarkSetup(ScintillaView *editor) {
	[editor message:SCI_SETMARGINTYPEN wParam:1 lParam:SC_MARGIN_SYMBOL];
	[editor message:SCI_SETMARGINWIDTHN wParam:1 lParam:16];
	[editor message:SCI_SETMARGINMASKN wParam:1 lParam:(1 << kBookmark)];
	[editor message:SCI_MARKERDEFINE wParam:kBookmark lParam:SC_MARK_BOOKMARK];
	[editor message:SCI_MARKERSETFORE wParam:kBookmark lParam:0x0000AA];
	[editor message:SCI_MARKERSETBACK wParam:kBookmark lParam:0x0000FF];
}

static long CurrentLine(ScintillaView *editor) {
	long position = [editor message:SCI_GETCURRENTPOS];
	return [editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)position lParam:0];
}

void NppPrefixSelectedLines(ScintillaView *editor, NSString *prefix) {
	if (!editor || prefix.length == 0) {
		return;
	}
	MutateLines(editor, LineScopeSelectionOrCurrent, ^(NSMutableArray<NSString *> *lines) {
		for (NSUInteger index = 0; index < lines.count; index++) {
			lines[index] = [prefix stringByAppendingString:lines[index]];
		}
	});
}

void NppRunEditorAction(ScintillaView *editor, NSString *action, NSString *lexer) {
	if (!editor || action.length == 0) {
		return;
	}
	if ([action isEqualToString:@"duplicate"]) {
		[editor message:SCI_LINEDUPLICATE];
	} else if ([action isEqualToString:@"deleteLine"]) {
		[editor message:SCI_LINEDELETE];
	} else if ([action isEqualToString:@"moveUp"]) {
		[editor message:SCI_MOVESELECTEDLINESUP];
	} else if ([action isEqualToString:@"moveDown"]) {
		[editor message:SCI_MOVESELECTEDLINESDOWN];
	} else if ([action isEqualToString:@"join"]) {
		[editor message:SCI_LINESJOIN];
	} else if ([action isEqualToString:@"split"]) {
		[editor message:SCI_LINESSPLIT wParam:0 lParam:0];
	} else if ([action isEqualToString:@"indent"]) {
		[editor message:SCI_TAB];
	} else if ([action isEqualToString:@"outdent"]) {
		[editor message:SCI_BACKTAB];
	} else if ([action isEqualToString:@"upper"]) {
		[editor message:SCI_UPPERCASE];
	} else if ([action isEqualToString:@"lower"]) {
		[editor message:SCI_LOWERCASE];
	} else if ([action isEqualToString:@"invert"]) {
		long start = [editor message:SCI_GETSELECTIONSTART];
		long end = [editor message:SCI_GETSELECTIONEND];
		if (end == start) {
			return;
		}
		NSString *inverted = InvertCase(EditorTextRange(editor, start, end));
		const char *bytes = inverted.UTF8String ?: "";
		[editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
	} else if ([action isEqualToString:@"comment"]) {
		ToggleLineComment(editor, lexer);
	} else if ([action isEqualToString:@"trim"]) {
		NSCharacterSet *space = NSCharacterSet.whitespaceCharacterSet;
		MutateLines(editor, LineScopeAll, ^(NSMutableArray<NSString *> *lines) {
			for (NSUInteger index = 0; index < lines.count; index++) {
				NSString *line = lines[index];
				NSUInteger end = line.length;
				while (end > 0 && [space characterIsMember:[line characterAtIndex:end - 1]]) {
					end--;
				}
				lines[index] = [line substringToIndex:end];
			}
		});
	} else if ([action isEqualToString:@"empty"]) {
		MutateLines(editor, LineScopeAll, ^(NSMutableArray<NSString *> *lines) {
			NSMutableArray *kept = [NSMutableArray array];
			for (NSString *line in lines) {
				if ([line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].length) {
					[kept addObject:line];
				}
			}
			[lines removeAllObjects];
			[lines addObjectsFromArray:kept];
		});
	} else if ([action isEqualToString:@"duplicates"]) {
		MutateLines(editor, LineScopeAll, ^(NSMutableArray<NSString *> *lines) {
			NSMutableArray *kept = [NSMutableArray array];
			NSMutableSet *seen = [NSMutableSet set];
			for (NSString *line in lines) {
				if ([seen containsObject:line]) {
					continue;
				}
				[seen addObject:line];
				[kept addObject:line];
			}
			[lines removeAllObjects];
			[lines addObjectsFromArray:kept];
		});
	} else if ([action isEqualToString:@"sortAsc"] || [action isEqualToString:@"sortDesc"]) {
		BOOL ascending = [action isEqualToString:@"sortAsc"];
		MutateLines(editor, LineScopeSelectionOrAll, ^(NSMutableArray<NSString *> *lines) {
			[lines sortUsingComparator:^NSComparisonResult(NSString *left, NSString *right) {
				NSComparisonResult order = [left caseInsensitiveCompare:right];
				return ascending ? order : (NSComparisonResult)-order;
			}];
		});
	} else if ([action isEqualToString:@"reverse"]) {
		MutateLines(editor, LineScopeSelectionOrAll, ^(NSMutableArray<NSString *> *lines) {
			NSUInteger count = lines.count;
			for (NSUInteger index = 0; index < count / 2; index++) {
				[lines exchangeObjectAtIndex:index withObjectAtIndex:count - 1 - index];
			}
		});
	} else if ([action isEqualToString:@"tabsToSpaces"]) {
		long width = MAX(1, [editor message:SCI_GETTABWIDTH]);
		NSString *spaces = [@"" stringByPaddingToLength:(NSUInteger)width withString:@" " startingAtIndex:0];
		MutateLines(editor, LineScopeAll, ^(NSMutableArray<NSString *> *lines) {
			for (NSUInteger index = 0; index < lines.count; index++) {
				lines[index] = [lines[index] stringByReplacingOccurrencesOfString:@"\t" withString:spaces];
			}
		});
	} else if ([action isEqualToString:@"bookmark"]) {
		BookmarkSetup(editor);
		long line = CurrentLine(editor);
		long state = [editor message:SCI_MARKERGET wParam:(uptr_t)line lParam:0];
		if (state & (1 << kBookmark)) {
			[editor message:SCI_MARKERDELETE wParam:(uptr_t)line lParam:kBookmark];
		} else {
			[editor message:SCI_MARKERADD wParam:(uptr_t)line lParam:kBookmark];
		}
	} else if ([action isEqualToString:@"bookmarkNext"] || [action isEqualToString:@"bookmarkPrev"]) {
		BookmarkSetup(editor);
		long line = CurrentLine(editor);
		long found = [action isEqualToString:@"bookmarkNext"]
			? [editor message:SCI_MARKERNEXT wParam:(uptr_t)(line + 1) lParam:(1 << kBookmark)]
			: [editor message:SCI_MARKERPREVIOUS wParam:(uptr_t)(line - 1) lParam:(1 << kBookmark)];
		if (found >= 0) {
			[editor message:SCI_GOTOLINE wParam:(uptr_t)found lParam:0];
			[editor message:SCI_SCROLLCARET];
		}
	} else if ([action isEqualToString:@"bookmarkClear"]) {
		[editor message:SCI_MARKERDELETEALL wParam:kBookmark lParam:0];
	} else if ([action isEqualToString:@"bookmarkDelete"]) {
		BookmarkSetup(editor);
		[editor message:SCI_BEGINUNDOACTION];
		long lineCount = [editor message:SCI_GETLINECOUNT];
		for (long line = lineCount - 1; line >= 0; line--) {
			long state = [editor message:SCI_MARKERGET wParam:(uptr_t)line lParam:0];
			if (state & (1 << kBookmark)) {
				long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
				long end = line + 1 < lineCount ? [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)(line + 1) lParam:0] : [editor message:SCI_GETLENGTH];
				[editor message:SCI_DELETERANGE wParam:(uptr_t)start lParam:end - start];
			}
		}
		[editor message:SCI_ENDUNDOACTION];
	} else if ([action isEqualToString:@"eol"]) {
		long shown = [editor message:SCI_GETVIEWEOL];
		[editor message:SCI_SETVIEWEOL wParam:shown ? 0 : 1 lParam:0];
	} else if ([action isEqualToString:@"guides"]) {
		long shown = [editor message:SCI_GETINDENTATIONGUIDES];
		[editor message:SCI_SETINDENTATIONGUIDES wParam:shown ? 0 : SC_IV_LOOKBOTH lParam:0];
	} else if ([action isEqualToString:@"zoomReset"]) {
		[editor message:SCI_SETZOOM wParam:0 lParam:0];
	} else if ([action isEqualToString:@"readonly"]) {
		long readonly = [editor message:SCI_GETREADONLY];
		[editor message:SCI_SETREADONLY wParam:readonly ? 0 : 1 lParam:0];
	} else if ([action isEqualToString:@"rectangle"]) {
		[editor message:SCI_SETSELECTIONMODE wParam:SC_SEL_RECTANGLE lParam:0];
	} else if ([action isEqualToString:@"foldCurrent"]) {
		[editor message:SCI_TOGGLEFOLD wParam:(uptr_t)CurrentLine(editor) lParam:0];
	} else if ([action isEqualToString:@"datetime"]) {
		NSString *stamp = [NSDateFormatter localizedStringFromDate:[NSDate date] dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterMediumStyle];
		const char *bytes = stamp.UTF8String ?: "";
		[editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
	}
}
