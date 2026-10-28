#import "PreviewHTML.h"

static NSString *NppEscape(NSString *text) {
	NSMutableString *escaped = [NSMutableString string];
	for (NSUInteger index = 0; index < text.length; index++) {
		unichar value = [text characterAtIndex:index];
		switch (value) {
		case '&': [escaped appendString:@"&amp;"]; break;
		case '<': [escaped appendString:@"&lt;"]; break;
		case '>': [escaped appendString:@"&gt;"]; break;
		default: [escaped appendFormat:@"%C", value]; break;
		}
	}
	return escaped;
}

static NSString *NppInlineMarkdown(NSString *line) {
	NSString *text = NppEscape(line);
	NSRegularExpression *code = [NSRegularExpression regularExpressionWithPattern:@"`([^`]+)`" options:0 error:nil];
	text = [code stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"<code>$1</code>"];
	NSRegularExpression *bold = [NSRegularExpression regularExpressionWithPattern:@"\\*\\*([^*]+)\\*\\*" options:0 error:nil];
	text = [bold stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"<strong>$1</strong>"];
	NSRegularExpression *italic = [NSRegularExpression regularExpressionWithPattern:@"(?<!\\*)\\*([^*]+)\\*(?!\\*)" options:0 error:nil];
	text = [italic stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"<em>$1</em>"];
	NSRegularExpression *link = [NSRegularExpression regularExpressionWithPattern:@"\\[([^\\]]+)\\]\\(([^)]+)\\)" options:0 error:nil];
	text = [link stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@"<a href=\"$2\">$1</a>"];
	return text;
}

static NSString *NppMarkdownBody(NSString *text) {
	NSMutableString *html = [NSMutableString string];
	NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
	BOOL inCode = NO;
	BOOL inList = NO;
	NSMutableString *paragraph = [NSMutableString string];
	void (^flushParagraph)(void) = ^{
		if (paragraph.length == 0) {
			return;
		}
		[html appendFormat:@"<p>%@</p>\n", NppInlineMarkdown(paragraph)];
		[paragraph setString:@""];
	};
	for (NSString *line in lines) {
		if ([line hasPrefix:@"```"]) {
			flushParagraph();
			if (inList) {
				[html appendString:@"</ul>\n"];
				inList = NO;
			}
			if (inCode) {
				[html appendString:@"</code></pre>\n"];
				inCode = NO;
			} else {
				[html appendString:@"<pre><code>"];
				inCode = YES;
			}
			continue;
		}
		if (inCode) {
			[html appendString:NppEscape(line)];
			[html appendString:@"\n"];
			continue;
		}
		if (line.length == 0) {
			flushParagraph();
			if (inList) {
				[html appendString:@"</ul>\n"];
				inList = NO;
			}
			continue;
		}
		if ([line hasPrefix:@"###### "]) {
			flushParagraph();
			[html appendFormat:@"<h6>%@</h6>\n", NppInlineMarkdown([line substringFromIndex:7])];
			continue;
		}
		if ([line hasPrefix:@"##### "]) {
			flushParagraph();
			[html appendFormat:@"<h5>%@</h5>\n", NppInlineMarkdown([line substringFromIndex:6])];
			continue;
		}
		if ([line hasPrefix:@"#### "]) {
			flushParagraph();
			[html appendFormat:@"<h4>%@</h4>\n", NppInlineMarkdown([line substringFromIndex:5])];
			continue;
		}
		if ([line hasPrefix:@"### "]) {
			flushParagraph();
			[html appendFormat:@"<h3>%@</h3>\n", NppInlineMarkdown([line substringFromIndex:4])];
			continue;
		}
		if ([line hasPrefix:@"## "]) {
			flushParagraph();
			[html appendFormat:@"<h2>%@</h2>\n", NppInlineMarkdown([line substringFromIndex:3])];
			continue;
		}
		if ([line hasPrefix:@"# "]) {
			flushParagraph();
			[html appendFormat:@"<h1>%@</h1>\n", NppInlineMarkdown([line substringFromIndex:2])];
			continue;
		}
		if ([line hasPrefix:@"- "] || [line hasPrefix:@"* "]) {
			flushParagraph();
			if (!inList) {
				[html appendString:@"<ul>\n"];
				inList = YES;
			}
			[html appendFormat:@"<li>%@</li>\n", NppInlineMarkdown([line substringFromIndex:2])];
			continue;
		}
		if (paragraph.length) {
			[paragraph appendString:@" "];
		}
		[paragraph appendString:line];
	}
	flushParagraph();
	if (inList) {
		[html appendString:@"</ul>\n"];
	}
	if (inCode) {
		[html appendString:@"</code></pre>\n"];
	}
	return html;
}

NSString *NppPreviewHTML(NSString *text, NSString *language, NSString *lexer, BOOL dark) {
	NSString *lang = language.lowercaseString ?: @"";
	NSString *lex = lexer.lowercaseString ?: @"";
	BOOL html = [lang isEqualToString:@"html"] || [lang isEqualToString:@"xml"] || [lex isEqualToString:@"hypertext"] || [lex isEqualToString:@"xml"];
	BOOL markdown = [lang containsString:@"markdown"] || [lex isEqualToString:@"markdown"];
	NSString *color = dark ? @"#d4d4d4" : @"#1e1e1e";
	NSString *background = dark ? @"#1e1e1e" : @"#ffffff";
	NSString *style = [NSString stringWithFormat:@"body{font:16px -apple-system,sans-serif;color:%@;background:%@;margin:24px;line-height:1.45} pre,code{font:13px Menlo,monospace} pre{background:%@;padding:12px;overflow:auto} a{color:#1a73c7}", color, background, dark ? @"#2a2a2a" : @"#f4f4f4"];
	if (html && text.length) {
		if ([text.lowercaseString containsString:@"<html"]) {
			return text;
		}
		return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><style>%@</style></head><body>%@</body></html>", style, text];
	}
	NSString *body = markdown ? NppMarkdownBody(text ?: @"") : [NSString stringWithFormat:@"<pre>%@</pre>", NppEscape(text ?: @"")];
	return [NSString stringWithFormat:@"<!doctype html><html><head><meta charset=\"utf-8\"><style>%@</style></head><body>%@</body></html>", style, body];
}
