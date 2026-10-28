#import "SnippetStore.h"

@implementation NppSnippetStore

+ (NSArray<NSDictionary<NSString *, NSString *> *> *)defaults {
	return @[
		@{@"name": @"todo", @"body": @"TODO: "},
		@{@"name": @"note", @"body": @"NOTE: "},
		@{@"name": @"fixme", @"body": @"FIXME: "}
	];
}

+ (instancetype)loadFromURL:(NSURL *)url {
	NppSnippetStore *store = [NppSnippetStore new];
	store.snippets = [NSMutableArray array];
	NSData *data = [NSData dataWithContentsOfURL:url];
	id json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
	NSArray *rows = [json isKindOfClass:[NSArray class]] ? json : [self defaults];
	if (rows.count == 0) {
		rows = [self defaults];
	}
	for (id row in rows) {
		if (![row isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *name = [row[@"name"] isKindOfClass:[NSString class]] ? row[@"name"] : @"";
		NSString *body = [row[@"body"] isKindOfClass:[NSString class]] ? row[@"body"] : @"";
		if (name.length == 0) {
			continue;
		}
		[store.snippets addObject:[@{@"name": name, @"body": body} mutableCopy]];
	}
	return store;
}

- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error {
	NSData *data = [NSJSONSerialization dataWithJSONObject:self.snippets ?: @[] options:NSJSONWritingPrettyPrinted error:error];
	if (!data) {
		return NO;
	}
	[[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil];
	return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

- (NSString *)bodyForName:(NSString *)name {
	for (NSDictionary *row in self.snippets) {
		if ([row[@"name"] caseInsensitiveCompare:name] == NSOrderedSame) {
			return row[@"body"] ?: @"";
		}
	}
	return nil;
}

@end
