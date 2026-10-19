#import "StyleTheme.h"

#import "ScintillaView.h"

@implementation StyleTheme {
	NSDictionary<NSString *, NSArray<NSDictionary *> *> *_styles;
}

+ (instancetype)themeWithXML:(NSString *)path {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) {
		return nil;
	}
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:nil];
	if (!document) {
		return nil;
	}
	StyleTheme *theme = [StyleTheme new];
	NSMutableDictionary *styles = [NSMutableDictionary dictionary];
	for (NSXMLElement *lexer in [document nodesForXPath:@"//LexerType" error:nil]) {
		NSString *name = [[lexer attributeForName:@"name"] stringValue];
		if (name.length == 0) {
			continue;
		}
		NSMutableArray *entries = [NSMutableArray array];
		for (NSXMLNode *child in lexer.children) {
			if (![child isKindOfClass:[NSXMLElement class]]) {
				continue;
			}
			NSXMLElement *style = (NSXMLElement *)child;
			if (![style.name isEqualToString:@"WordsStyle"]) {
				continue;
			}
			NSString *styleID = [[style attributeForName:@"styleID"] stringValue];
			NSString *foreground = [[style attributeForName:@"fgColor"] stringValue];
			if (styleID.length == 0 || foreground.length != 6) {
				continue;
			}
			[entries addObject:@{
				@"id": @(styleID.intValue),
				@"fg": foreground.uppercaseString,
				@"bg": [[style attributeForName:@"bgColor"] stringValue].uppercaseString ?: @"FFFFFF",
				@"bold": @([[[style attributeForName:@"fontStyle"] stringValue] intValue] & 1)
			}];
		}
		styles[name] = entries;
	}
	theme->_styles = styles;
	return theme;
}

static NSString *AdjustedColor(NSString *hex, BOOL dark) {
	if (hex.length != 6) {
		return @"#000000";
	}
	unsigned value = 0;
	[[NSScanner scannerWithString:hex] scanHexInt:&value];
	unsigned red = (value >> 16) & 255;
	unsigned green = (value >> 8) & 255;
	unsigned blue = value & 255;
	if (dark) {
		double luminance = 0.299 * red + 0.587 * green + 0.114 * blue;
		if (luminance < 150) {
			red = MIN(255, (unsigned)(red + (255 - red) * 0.62));
			green = MIN(255, (unsigned)(green + (255 - green) * 0.62));
			blue = MIN(255, (unsigned)(blue + (255 - blue) * 0.62));
		}
	}
	return [NSString stringWithFormat:@"#%02X%02X%02X", red, green, blue];
}

- (void)applyToEditor:(ScintillaView *)editor language:(NSString *)language dark:(BOOL)dark {
	NSArray *entries = _styles[language ?: @""];
	if (!entries && [language isEqualToString:@"hypertext"]) {
		entries = _styles[@"html"];
	}
	if (!entries && [language isEqualToString:@"phpscript"]) {
		entries = _styles[@"php"];
	}
	for (NSDictionary *entry in entries) {
		int style = [entry[@"id"] intValue];
		[editor setColorProperty:SCI_STYLESETFORE parameter:style fromHTML:AdjustedColor(entry[@"fg"], dark)];
		[editor setGeneralProperty:SCI_STYLESETBOLD parameter:style value:[entry[@"bold"] boolValue] ? 1 : 0];
		NSString *background = entry[@"bg"];
		if (!dark && background.length == 6 && ![background isEqualToString:@"FFFFFF"]) {
			[editor setColorProperty:SCI_STYLESETBACK parameter:style fromHTML:[@"#" stringByAppendingString:background]];
		}
	}
}

@end
