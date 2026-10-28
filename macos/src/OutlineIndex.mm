#import "OutlineIndex.h"

@implementation NppSymbol
@end

static NSRegularExpression *NppRegex(NSString *pattern) {
	return [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionAnchorsMatchLines error:nil];
}

static void NppAddSymbol(NSMutableArray<NppSymbol *> *symbols, NSMutableSet<NSNumber *> *seen, NSString *name, NSString *kind, NSInteger line) {
	if (name.length == 0 || symbols.count >= 800 || [seen containsObject:@(line)]) {
		return;
	}
	[seen addObject:@(line)];
	NppSymbol *symbol = [NppSymbol new];
	symbol.name = name;
	symbol.kind = kind;
	symbol.line = line;
	[symbols addObject:symbol];
}

NSArray<NppSymbol *> *NppOutlineSymbols(NSString *language, NSString *lexer, NSString *text) {
	if (text.length == 0) {
		return @[];
	}
	if (text.length > 1500000) {
		text = [text substringToIndex:1500000];
	}
	NSString *lang = language.lowercaseString ?: @"";
	NSString *lex = lexer.lowercaseString ?: @"";
	NSMutableArray<NppSymbol *> *symbols = [NSMutableArray array];
	NSMutableSet<NSNumber *> *seen = [NSMutableSet set];
	BOOL json = [lang containsString:@"json"] || [lex isEqualToString:@"json"];
	BOOL markdown = [lang containsString:@"markdown"] || [lex isEqualToString:@"markdown"];
	BOOL html = [lex isEqualToString:@"hypertext"] || [lang isEqualToString:@"html"] || [lang isEqualToString:@"xml"] || [lex isEqualToString:@"xml"];
	NSRegularExpression *jsonKey = json ? NppRegex(@"\"((?:\\\\.|[^\"\\\\])*)\"\\s*:") : nil;
	NSRegularExpression *heading = markdown ? NppRegex(@"^(#{1,6})\\s+(.+?)\\s*$") : nil;
	NSRegularExpression *tag = html ? NppRegex(@"^\\s*</?([A-Za-z][\\w:.-]*)\\b") : nil;
	NSRegularExpression *decl = NppRegex(@"^\\s*(?:export\\s+|pub\\s+|public\\s+|private\\s+|protected\\s+|internal\\s+|static\\s+|async\\s+|final\\s+|override\\s+|func\\s+|function\\s+|def\\s+|fn\\s+|fun\\s+|class\\s+|struct\\s+|interface\\s+|enum\\s+|impl\\s+)*(class|struct|interface|enum|func|function|def|fn|fun)\\s+([A-Za-z_][\\w]*)");
	NSRegularExpression *named = NppRegex(@"^\\s*(?:export\\s+|pub\\s+|public\\s+|private\\s+|protected\\s+|static\\s+|async\\s+)*([A-Za-z_][\\w:]*)\\s*\\(");
	NSSet<NSString *> *skip = [NSSet setWithArray:@[@"if", @"for", @"while", @"switch", @"catch", @"return", @"sizeof", @"elif", @"foreach"]];
	__block NSInteger lineNumber = 0;
	[text enumerateLinesUsingBlock:^(NSString *line, BOOL *stop) {
		(void)stop;
		lineNumber++;
		NSRange full = NSMakeRange(0, line.length);
		if (jsonKey) {
			NSTextCheckingResult *match = [jsonKey firstMatchInString:line options:0 range:full];
			if (match.numberOfRanges > 1) {
				NppAddSymbol(symbols, seen, [line substringWithRange:[match rangeAtIndex:1]], @"key", lineNumber);
			}
			return;
		}
		if (heading) {
			NSTextCheckingResult *match = [heading firstMatchInString:line options:0 range:full];
			if (match.numberOfRanges > 2) {
				NSString *marks = [line substringWithRange:[match rangeAtIndex:1]];
				NSString *title = [line substringWithRange:[match rangeAtIndex:2]];
				NppAddSymbol(symbols, seen, title, [NSString stringWithFormat:@"h%lu", (unsigned long)marks.length], lineNumber);
			}
			return;
		}
		if (tag) {
			NSTextCheckingResult *match = [tag firstMatchInString:line options:0 range:full];
			if (match.numberOfRanges > 1 && ![line containsString:@"</"]) {
				NSString *name = [line substringWithRange:[match rangeAtIndex:1]];
				if (![name.lowercaseString isEqualToString:@"div"] && ![name.lowercaseString isEqualToString:@"span"]) {
					NppAddSymbol(symbols, seen, name, @"tag", lineNumber);
				}
			}
		}
		NSTextCheckingResult *declared = [decl firstMatchInString:line options:0 range:full];
		if (declared.numberOfRanges > 2) {
			NSString *kind = [line substringWithRange:[declared rangeAtIndex:1]];
			NSString *name = [line substringWithRange:[declared rangeAtIndex:2]];
			NppAddSymbol(symbols, seen, name, kind, lineNumber);
			return;
		}
		NSTextCheckingResult *call = [named firstMatchInString:line options:0 range:full];
		if (call.numberOfRanges > 1) {
			NSString *name = [line substringWithRange:[call rangeAtIndex:1]];
			NSString *leaf = [name componentsSeparatedByString:@":"].lastObject;
			if (![skip containsObject:leaf]) {
				NppAddSymbol(symbols, seen, name, @"function", lineNumber);
			}
		}
	}];
	return symbols;
}

NSColor *NppLanguageColor(NSString *language) {
	static NSArray<NSColor *> *colors;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		colors = @[
			[NSColor systemBlueColor],
			[NSColor systemGreenColor],
			[NSColor systemOrangeColor],
			[NSColor systemPurpleColor],
			[NSColor systemTealColor],
			[NSColor systemPinkColor],
			[NSColor systemIndigoColor],
			[NSColor systemBrownColor]
		];
	});
	NSString *key = language.length ? language.lowercaseString : @"text";
	NSUInteger hash = 0;
	for (NSUInteger index = 0; index < key.length; index++) {
		hash = hash * 33 + [key characterAtIndex:index];
	}
	return colors[hash % colors.count];
}
