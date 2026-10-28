#import "UserLanguages.h"

#import "LangCatalog.h"

static NSArray<NSString *> *NppTokens(NSString *text) {
	NSMutableArray<NSString *> *tokens = [NSMutableArray array];
	NSCharacterSet *split = [NSCharacterSet characterSetWithCharactersInString:@" ,;\t"];
	for (NSString *part in [text componentsSeparatedByCharactersInSet:split]) {
		NSString *token = part.lowercaseString;
		if ([token hasPrefix:@"*."]) {
			token = [token substringFromIndex:2];
		} else if ([token hasPrefix:@"."]) {
			token = [token substringFromIndex:1];
		}
		if (token.length) {
			[tokens addObject:token];
		}
	}
	return tokens;
}

@implementation NppUserLanguage

- (LangInfo *)langInfo {
	LangInfo *info = [LangInfo new];
	info.name = self.name.length ? self.name : @"user";
	info.lexer = self.lexer.length ? self.lexer : @"cpp";
	info.extensions = NppTokens(self.extensions);
	info.keywords = @{@"instre1": self.keywords ?: @""};
	return info;
}

- (BOOL)matchesPath:(NSString *)path {
	if (path.length == 0) {
		return NO;
	}
	NSString *ext = path.pathExtension.lowercaseString;
	NSString *file = path.lastPathComponent.lowercaseString;
	for (NSString *token in NppTokens(self.extensions)) {
		if ([token isEqualToString:ext] || [token isEqualToString:file]) {
			return YES;
		}
	}
	return NO;
}

@end

@implementation NppUserLanguageStore

+ (instancetype)loadFromURL:(NSURL *)url {
	NppUserLanguageStore *store = [NppUserLanguageStore new];
	store.languages = [NSMutableArray array];
	NSData *data = [NSData dataWithContentsOfURL:url];
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	if (![json isKindOfClass:[NSArray class]]) {
		return store;
	}
	for (id row in json) {
		if (![row isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NppUserLanguage *language = [NppUserLanguage new];
		language.name = [row[@"name"] isKindOfClass:[NSString class]] ? row[@"name"] : @"Language";
		language.extensions = [row[@"extensions"] isKindOfClass:[NSString class]] ? row[@"extensions"] : @"";
		language.keywords = [row[@"keywords"] isKindOfClass:[NSString class]] ? row[@"keywords"] : @"";
		language.lexer = [row[@"lexer"] isKindOfClass:[NSString class]] ? row[@"lexer"] : @"cpp";
		if (language.name.length) {
			[store.languages addObject:language];
		}
	}
	return store;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	NSMutableArray *rows = [NSMutableArray array];
	for (NppUserLanguage *language in self.languages) {
		[rows addObject:@{
			@"name": language.name ?: @"",
			@"extensions": language.extensions ?: @"",
			@"keywords": language.keywords ?: @"",
			@"lexer": language.lexer.length ? language.lexer : @"cpp"
		}];
	}
	NSData *data = [NSJSONSerialization dataWithJSONObject:rows options:NSJSONWritingPrettyPrinted error:error];
	if (!data) {
		return NO;
	}
	[[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NppUserLanguage *)languageForPath:(NSString *)path {
	for (NppUserLanguage *language in self.languages) {
		if ([language matchesPath:path]) {
			return language;
		}
	}
	return nil;
}

- (LangInfo *)langInfoNamed:(NSString *)name {
	for (NppUserLanguage *language in self.languages) {
		if ([language.name caseInsensitiveCompare:name] == NSOrderedSame) {
			return [language langInfo];
		}
	}
	return nil;
}

@end
