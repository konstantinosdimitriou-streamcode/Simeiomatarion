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
		@"preferences": @"cmd+,"
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
