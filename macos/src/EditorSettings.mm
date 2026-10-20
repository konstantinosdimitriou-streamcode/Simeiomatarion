#import "EditorSettings.h"

#import <AppKit/AppKit.h>

@implementation EditorSettings

+ (NSDictionary<NSString *, NSString *> *)defaultShortcuts {
	// Notepad++ Ctrl/Alt accelerators, with Command standing in for Ctrl.
	// Command-Q stays Quit, so the Notepad++ comment shortcut stays Control-Q.
	// Command-H stays Hide, so Replace keeps Command-Option-F. Control-H also opens Replace.
	return @{
		@"new": @"cmd+n",
		@"open": @"cmd+o",
		@"save": @"cmd+s",
		@"saveAs": @"cmd+alt+s",
		@"saveAll": @"cmd+shift+s",
		@"reload": @"cmd+r",
		@"close": @"cmd+w",
		@"closeAll": @"cmd+shift+w",
		@"print": @"cmd+p",
		@"quickOpen": @"cmd+shift+o",
		@"openFolder": @"cmd+alt+o",
		@"reveal": @"cmd+alt+r",
		@"undo": @"cmd+z",
		@"redo": @"cmd+shift+z",
		@"cut": @"cmd+x",
		@"copy": @"cmd+c",
		@"paste": @"cmd+v",
		@"selectAll": @"cmd+a",
		@"duplicate": @"cmd+d",
		@"moveUp": @"cmd+shift+up",
		@"moveDown": @"cmd+shift+down",
		@"join": @"cmd+j",
		@"split": @"cmd+i",
		@"upper": @"cmd+shift+u",
		@"lower": @"cmd+u",
		@"comment": @"ctrl+q",
		@"find": @"cmd+f",
		@"findInFiles": @"cmd+shift+f",
		@"findNext": @"f3",
		@"findPrev": @"shift+f3",
		@"selectFindNext": @"ctrl+f3",
		@"replace": @"cmd+alt+f",
		@"goto": @"cmd+g",
		@"brace": @"cmd+b",
		@"bookmark": @"cmd+f2",
		@"bookmarkNext": @"f2",
		@"bookmarkPrev": @"shift+f2",
		@"zoomIn": @"cmd+=",
		@"zoomOut": @"cmd+-",
		@"zoomReset": @"cmd+0",
		@"foldAll": @"alt+0",
		@"unfoldAll": @"alt+shift+0",
		@"nextTab": @"ctrl+tab",
		@"prevTab": @"ctrl+shift+tab",
		@"macroRecord": @"cmd+shift+r",
		@"macroPlay": @"cmd+shift+p",
		@"column": @"alt+c",
		@"preferences": @"cmd+,",
		@"clone": @"cmd+alt+2",
		@"outline": @"cmd+alt+l",
		@"clipboardHistory": @"cmd+shift+v",
		@"preview": @"cmd+alt+p",
		@"addNext": @"ctrl+d",
		@"pin": @"cmd+alt+t",
		@"minimap": @"cmd+alt+m",
		@"snippets": @"cmd+alt+k"
	};
}

+ (instancetype)loadFromURL:(NSURL *)url {
	EditorSettings *settings = [EditorSettings new];
	settings.fontName = @"Menlo";
	settings.fontSize = 13;
	settings.tabWidth = 4;
	settings.useTabs = YES;
	settings.wrap = NO;
	settings.lineNumbers = YES;
	settings.showWhitespace = NO;
	settings.theme = @"system";
	settings.syncScroll = NO;
	settings.confirmClose = YES;
	settings.showMinimap = YES;
	settings.autoClose = YES;
	settings.smartIndent = YES;
	settings.highlightMatches = YES;
	settings.showChanges = YES;
	settings.backupBeforeSave = YES;
	settings.spellCheck = YES;
	settings.showFileSize = YES;
	settings.showCharacterPanel = YES;
	settings.extraWindows = YES;
	settings.formatDocuments = YES;
	settings.fileSizeUnit = @"auto";
	settings.uiLanguage = @"system";
	settings.searchHistory = @[];
	settings.shortcuts = [EditorSettings defaultShortcuts];
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (!data) {
		return settings;
	}
	id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
	if (![object isKindOfClass:[NSDictionary class]]) {
		return settings;
	}
	NSDictionary *json = object;
	if ([json[@"fontName"] isKindOfClass:[NSString class]]) {
		settings.fontName = json[@"fontName"];
	}
	if (json[@"fontSize"]) {
		settings.fontSize = MAX(6, MIN(72, [json[@"fontSize"] intValue]));
	}
	if (json[@"tabWidth"]) {
		settings.tabWidth = MAX(1, MIN(32, [json[@"tabWidth"] intValue]));
	}
	if (json[@"useTabs"]) settings.useTabs = [json[@"useTabs"] boolValue];
	if (json[@"wrap"]) settings.wrap = [json[@"wrap"] boolValue];
	if (json[@"lineNumbers"]) settings.lineNumbers = [json[@"lineNumbers"] boolValue];
	if (json[@"showWhitespace"]) settings.showWhitespace = [json[@"showWhitespace"] boolValue];
	if ([json[@"theme"] isKindOfClass:[NSString class]]) settings.theme = json[@"theme"];
	if (json[@"syncScroll"]) settings.syncScroll = [json[@"syncScroll"] boolValue];
	if (json[@"confirmClose"] != nil) settings.confirmClose = [json[@"confirmClose"] boolValue];
	if (json[@"showMinimap"] != nil) settings.showMinimap = [json[@"showMinimap"] boolValue];
	if (json[@"autoClose"] != nil) settings.autoClose = [json[@"autoClose"] boolValue];
	if (json[@"smartIndent"] != nil) settings.smartIndent = [json[@"smartIndent"] boolValue];
	if (json[@"highlightMatches"] != nil) settings.highlightMatches = [json[@"highlightMatches"] boolValue];
	if (json[@"showChanges"] != nil) settings.showChanges = [json[@"showChanges"] boolValue];
	if (json[@"backupBeforeSave"] != nil) settings.backupBeforeSave = [json[@"backupBeforeSave"] boolValue];
	if (json[@"spellCheck"] != nil) settings.spellCheck = [json[@"spellCheck"] boolValue];
	if (json[@"showFileSize"] != nil) settings.showFileSize = [json[@"showFileSize"] boolValue];
	if (json[@"showCharacterPanel"] != nil) settings.showCharacterPanel = [json[@"showCharacterPanel"] boolValue];
	if (json[@"extraWindows"] != nil) settings.extraWindows = [json[@"extraWindows"] boolValue];
	if (json[@"formatDocuments"] != nil) settings.formatDocuments = [json[@"formatDocuments"] boolValue];
	if ([json[@"fileSizeUnit"] isKindOfClass:[NSString class]]) settings.fileSizeUnit = json[@"fileSizeUnit"];
	if ([json[@"uiLanguage"] isKindOfClass:[NSString class]]) settings.uiLanguage = json[@"uiLanguage"];
	if ([json[@"searchHistory"] isKindOfClass:[NSArray class]]) {
		NSMutableArray<NSString *> *history = [NSMutableArray array];
		for (id item in json[@"searchHistory"]) {
			if ([item isKindOfClass:[NSString class]] && [item length] > 0) {
				[history addObject:item];
			}
		}
		settings.searchHistory = history;
	}
	if ([json[@"shortcutVersion"] integerValue] >= 2 && [json[@"shortcuts"] isKindOfClass:[NSDictionary class]]) {
		NSMutableDictionary *merged = [settings.shortcuts mutableCopy];
		[merged addEntriesFromDictionary:json[@"shortcuts"]];
		settings.shortcuts = merged;
	}
	return settings;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	NSDictionary *payload = @{
		@"fontName": self.fontName ?: @"Menlo",
		@"fontSize": @(self.fontSize),
		@"tabWidth": @(self.tabWidth),
		@"useTabs": @(self.useTabs),
		@"wrap": @(self.wrap),
		@"lineNumbers": @(self.lineNumbers),
		@"showWhitespace": @(self.showWhitespace),
		@"theme": self.theme ?: @"system",
		@"syncScroll": @(self.syncScroll),
		@"confirmClose": @(self.confirmClose),
		@"showMinimap": @(self.showMinimap),
		@"autoClose": @(self.autoClose),
		@"smartIndent": @(self.smartIndent),
		@"highlightMatches": @(self.highlightMatches),
		@"showChanges": @(self.showChanges),
		@"backupBeforeSave": @(self.backupBeforeSave),
		@"spellCheck": @(self.spellCheck),
		@"showFileSize": @(self.showFileSize),
		@"showCharacterPanel": @(self.showCharacterPanel),
		@"extraWindows": @(self.extraWindows),
		@"formatDocuments": @(self.formatDocuments),
		@"fileSizeUnit": self.fileSizeUnit ?: @"auto",
		@"uiLanguage": self.uiLanguage ?: @"system",
		@"searchHistory": self.searchHistory ?: @[],
		@"shortcutVersion": @2,
		@"shortcuts": self.shortcuts ?: @{}
	};
	NSData *data = [NSJSONSerialization dataWithJSONObject:payload options:NSJSONWritingPrettyPrinted error:error];
	if (!data) {
		return NO;
	}
	[[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NSString *)shortcutForCommand:(NSString *)command {
	return self.shortcuts[command] ?: @"";
}

- (void)rememberSearch:(NSString *)query {
	if (query.length == 0) {
		return;
	}
	NSMutableArray<NSString *> *items = [self.searchHistory mutableCopy] ?: [NSMutableArray array];
	[items removeObject:query];
	[items insertObject:query atIndex:0];
	if (items.count > 20) {
		[items removeObjectsInRange:NSMakeRange(20, items.count - 20)];
	}
	self.searchHistory = items;
}

+ (NSString *)shortcutSpecForEvent:(NSEvent *)event {
	NSMutableArray<NSString *> *parts = [NSMutableArray array];
	NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
	if (flags & NSEventModifierFlagCommand) [parts addObject:@"cmd"];
	if (flags & NSEventModifierFlagOption) [parts addObject:@"alt"];
	if (flags & NSEventModifierFlagControl) [parts addObject:@"ctrl"];
	if (flags & NSEventModifierFlagShift) [parts addObject:@"shift"];
	NSString *characters = event.charactersIgnoringModifiers ?: @"";
	if (characters.length != 1) {
		return @"";
	}
	unichar value = [characters characterAtIndex:0];
	if (value >= NSF1FunctionKey && value <= NSF35FunctionKey) {
		[parts addObject:[NSString stringWithFormat:@"f%d", (int)(value - NSF1FunctionKey + 1)]];
	} else if (value == NSUpArrowFunctionKey) {
		[parts addObject:@"up"];
	} else if (value == NSDownArrowFunctionKey) {
		[parts addObject:@"down"];
	} else if (value == NSLeftArrowFunctionKey) {
		[parts addObject:@"left"];
	} else if (value == NSRightArrowFunctionKey) {
		[parts addObject:@"right"];
	} else if (value == '\t') {
		[parts addObject:@"tab"];
	} else if (value < 32 || value == 127) {
		return @"";
	} else {
		[parts addObject:characters.lowercaseString];
	}
	return parts.count ? [parts componentsJoinedByString:@"+"] : @"";
}

- (void)setShortcut:(NSString *)shortcut forCommand:(NSString *)command {
	NSMutableDictionary *copy = [self.shortcuts mutableCopy] ?: [NSMutableDictionary dictionary];
	copy[command] = shortcut ?: @"";
	self.shortcuts = copy;
}

+ (BOOL)parseShortcut:(NSString *)spec key:(NSString **)key modifiers:(NSEventModifierFlags *)modifiers {
	NSEventModifierFlags flags = 0;
	NSString *character = @"";
	for (NSString *raw in [spec.lowercaseString componentsSeparatedByString:@"+"]) {
		NSString *part = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if (part.length == 0) {
			continue;
		}
		if ([part isEqualToString:@"cmd"] || [part isEqualToString:@"command"]) {
			flags |= NSEventModifierFlagCommand;
		} else if ([part isEqualToString:@"shift"]) {
			flags |= NSEventModifierFlagShift;
		} else if ([part isEqualToString:@"alt"] || [part isEqualToString:@"opt"] || [part isEqualToString:@"option"]) {
			flags |= NSEventModifierFlagOption;
		} else if ([part isEqualToString:@"ctrl"] || [part isEqualToString:@"control"]) {
			flags |= NSEventModifierFlagControl;
		} else if ([part isEqualToString:@"up"]) {
			unichar value = NSUpArrowFunctionKey;
			character = [NSString stringWithCharacters:&value length:1];
		} else if ([part isEqualToString:@"down"]) {
			unichar value = NSDownArrowFunctionKey;
			character = [NSString stringWithCharacters:&value length:1];
		} else if ([part isEqualToString:@"left"]) {
			unichar value = NSLeftArrowFunctionKey;
			character = [NSString stringWithCharacters:&value length:1];
		} else if ([part isEqualToString:@"right"]) {
			unichar value = NSRightArrowFunctionKey;
			character = [NSString stringWithCharacters:&value length:1];
		} else if ([part isEqualToString:@"tab"]) {
			character = @"\t";
		} else if ([part hasPrefix:@"f"] && part.length >= 2 && part.length <= 3) {
			int number = [part substringFromIndex:1].intValue;
			if (number >= 1 && number <= 35) {
				unichar value = (unichar)(NSF1FunctionKey + number - 1);
				character = [NSString stringWithCharacters:&value length:1];
			}
		} else if (part.length == 1) {
			character = part;
		}
	}
	if (character.length == 0) {
		return NO;
	}
	if ((flags & NSEventModifierFlagShift) && character.length == 1) {
		unichar value = [character characterAtIndex:0];
		if (value >= 'a' && value <= 'z') {
			character = character.uppercaseString;
			flags &= ~NSEventModifierFlagShift;
		}
	}
	if (key) {
		*key = character;
	}
	if (modifiers) {
		*modifiers = flags;
	}
	return YES;
}

@end
