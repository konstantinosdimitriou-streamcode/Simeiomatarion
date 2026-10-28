#import "Search.h"

#import "Encoding.h"
#import "Scintilla.h"
#import "BoostRegexSearch.h"

long NppSearchFlags(SearchFlags flags) {
	long value = 0;
	if (flags.matchCase) {
		value |= SCFIND_MATCHCASE;
	}
	if (flags.wholeWord) {
		value |= SCFIND_WHOLEWORD;
	}
	if (flags.regex) {
		// Same POSIX Boost expression flags Notepad++ uses for regular-expression search.
		value |= SCFIND_REGEXP | SCFIND_POSIX | SCFIND_REGEXP_SKIPCRLFASONE;
		if (flags.dotMatchesNewline) {
			value |= SCFIND_REGEXP_DOTMATCHESNL;
		}
	}
	return value;
}

static long SearchRange(ScintillaView *editor, const char *bytes, long byteLength, long start, long end) {
	[editor message:SCI_SETTARGETSTART wParam:static_cast<uptr_t>(start) lParam:0];
	[editor message:SCI_SETTARGETEND wParam:static_cast<uptr_t>(end) lParam:0];
	return [editor message:SCI_SEARCHINTARGET wParam:static_cast<uptr_t>(byteLength) lParam:reinterpret_cast<sptr_t>(bytes)];
}

long NppFind(ScintillaView *editor, NSString *text, bool forward, bool wrap, SearchFlags flags) {
	if (!editor || text.length == 0) {
		return -1;
	}
	const char *bytes = text.UTF8String;
	long byteLength = static_cast<long>(strlen(bytes));
	long documentLength = [editor message:SCI_GETLENGTH];
	long anchor = forward ? [editor message:SCI_GETSELECTIONEND] : [editor message:SCI_GETSELECTIONSTART];
	[editor message:SCI_SETSEARCHFLAGS wParam:static_cast<uptr_t>(NppSearchFlags(flags)) lParam:0];
	long found = forward ? SearchRange(editor, bytes, byteLength, anchor, documentLength)
						 : SearchRange(editor, bytes, byteLength, anchor, 0);
	if (found < 0 && wrap) {
		found = forward ? SearchRange(editor, bytes, byteLength, 0, anchor)
						: SearchRange(editor, bytes, byteLength, documentLength, anchor);
	}
	if (found >= 0) {
		long matchStart = [editor message:SCI_GETTARGETSTART];
		long matchEnd = [editor message:SCI_GETTARGETEND];
		[editor message:SCI_SETSEL wParam:static_cast<uptr_t>(matchStart) lParam:matchEnd];
		[editor message:SCI_SCROLLCARET];
	}
	return found;
}

static const int kSearchIndicator = 9;
static const int kCurrentMatchIndicator = 10;

void NppClearSearchHighlights(ScintillaView *editor) {
	if (!editor) {
		return;
	}
	long length = [editor message:SCI_GETLENGTH];
	[editor message:SCI_SETINDICATORCURRENT wParam:kSearchIndicator lParam:0];
	[editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
	[editor message:SCI_SETINDICATORCURRENT wParam:kCurrentMatchIndicator lParam:0];
	[editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
}

void NppShowCurrentMatch(ScintillaView *editor, long start, long end) {
	if (!editor) {
		return;
	}
	long length = [editor message:SCI_GETLENGTH];
	[editor message:SCI_INDICSETSTYLE wParam:kCurrentMatchIndicator lParam:INDIC_FULLBOX];
	[editor message:SCI_INDICSETFORE wParam:kCurrentMatchIndicator lParam:0x0095FF];
	[editor message:SCI_INDICSETALPHA wParam:kCurrentMatchIndicator lParam:170];
	[editor message:SCI_INDICSETUNDER wParam:kCurrentMatchIndicator lParam:1];
	[editor message:SCI_SETINDICATORCURRENT wParam:kCurrentMatchIndicator lParam:0];
	[editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
	if (start < 0 || end <= start) {
		return;
	}
	[editor message:SCI_INDICATORFILLRANGE wParam:static_cast<uptr_t>(start) lParam:end - start];
	long line = [editor message:SCI_LINEFROMPOSITION wParam:static_cast<uptr_t>(start) lParam:0];
	[editor message:SCI_ENSUREVISIBLE wParam:static_cast<uptr_t>(line) lParam:0];
	[editor message:SCI_SCROLLCARET];
	long visible = [editor message:SCI_LINESONSCREEN];
	long top = visible > 2 ? line - visible / 3 : 0;
	if (top < 0) {
		top = 0;
	}
	[editor message:SCI_SETFIRSTVISIBLELINE wParam:static_cast<uptr_t>(top) lParam:0];
}

void NppHighlightMatches(ScintillaView *editor, NSString *text, SearchFlags flags) {
	NppClearSearchHighlights(editor);
	if (!editor || text.length == 0) {
		return;
	}
	[editor message:SCI_INDICSETSTYLE wParam:kSearchIndicator lParam:INDIC_STRAIGHTBOX];
	[editor message:SCI_INDICSETFORE wParam:kSearchIndicator lParam:0xFFAA44];
	[editor message:SCI_INDICSETALPHA wParam:kSearchIndicator lParam:70];
	[editor message:SCI_SETINDICATORCURRENT wParam:kSearchIndicator lParam:0];
	const char *bytes = text.UTF8String;
	long byteLength = static_cast<long>(strlen(bytes ?: ""));
	if (byteLength <= 0) {
		return;
	}
	long documentLength = [editor message:SCI_GETLENGTH];
	[editor message:SCI_SETSEARCHFLAGS wParam:static_cast<uptr_t>(NppSearchFlags(flags)) lParam:0];
	long start = 0;
	for (int count = 0; count < 2000 && start <= documentLength; count++) {
		long found = SearchRange(editor, bytes, byteLength, start, documentLength);
		if (found < 0) {
			break;
		}
		long matchStart = [editor message:SCI_GETTARGETSTART];
		long matchEnd = [editor message:SCI_GETTARGETEND];
		if (matchEnd <= matchStart) {
			start = matchStart + 1;
			continue;
		}
		[editor message:SCI_INDICATORFILLRANGE wParam:static_cast<uptr_t>(matchStart) lParam:matchEnd - matchStart];
		start = matchEnd;
	}
}

static void ReplaceTarget(ScintillaView *editor, NSString *replacement, bool regex) {
	const char *bytes = replacement.UTF8String ?: "";
	long length = static_cast<long>(strlen(bytes));
	unsigned int message = regex ? SCI_REPLACETARGETRE : SCI_REPLACETARGET;
	[editor message:message wParam:static_cast<uptr_t>(length) lParam:reinterpret_cast<sptr_t>(bytes)];
}

long NppReplace(ScintillaView *editor, NSString *text, NSString *replacement, bool wrap, SearchFlags flags) {
	if (!editor || text.length == 0) {
		return -1;
	}
	const char *bytes = text.UTF8String;
	long byteLength = static_cast<long>(strlen(bytes));
	long documentLength = [editor message:SCI_GETLENGTH];
	long origin = [editor message:SCI_GETSELECTIONSTART];
	[editor message:SCI_SETSEARCHFLAGS wParam:static_cast<uptr_t>(NppSearchFlags(flags)) lParam:0];
	long found = SearchRange(editor, bytes, byteLength, origin, documentLength);
	if (found < 0 && wrap) {
		found = SearchRange(editor, bytes, byteLength, 0, origin);
	}
	if (found < 0) {
		return -1;
	}
	ReplaceTarget(editor, replacement ?: @"", flags.regex);
	long end = [editor message:SCI_GETTARGETEND];
	[editor message:SCI_SETSEL wParam:static_cast<uptr_t>(end) lParam:end];
	[editor message:SCI_SCROLLCARET];
	return end;
}

long NppReplaceAll(ScintillaView *editor, NSString *text, NSString *replacement, SearchFlags flags) {
	if (!editor || text.length == 0) {
		return 0;
	}
	const char *bytes = text.UTF8String;
	long byteLength = static_cast<long>(strlen(bytes));
	[editor message:SCI_SETSEARCHFLAGS wParam:static_cast<uptr_t>(NppSearchFlags(flags)) lParam:0];
	[editor message:SCI_BEGINUNDOACTION];
	long count = 0;
	long start = 0;
	while (start <= [editor message:SCI_GETLENGTH]) {
		long documentLength = [editor message:SCI_GETLENGTH];
		long found = SearchRange(editor, bytes, byteLength, start, documentLength);
		if (found < 0) {
			break;
		}
		long before = [editor message:SCI_GETTARGETSTART];
		long matchLength = [editor message:SCI_GETTARGETEND] - before;
		ReplaceTarget(editor, replacement ?: @"", flags.regex);
		long after = [editor message:SCI_GETTARGETEND];
		start = matchLength == 0 ? before + 1 : after;
		count++;
		if (count > 1000000) {
			break;
		}
	}
	[editor message:SCI_ENDUNDOACTION];
	return count;
}

#import <fnmatch.h>

@implementation NppFindHit
@end

static BOOL MatchAllNames(NSString *filters) {
	NSString *trimmed = [filters stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
	return trimmed.length == 0 || [trimmed isEqualToString:@"*"] || [trimmed isEqualToString:@"*.*"];
}

static BOOL NameMatches(NSString *name, NSString *filters) {
	if (MatchAllNames(filters)) {
		return YES;
	}
	NSCharacterSet *separators = [NSCharacterSet characterSetWithCharactersInString:@" \t,;"];
	for (NSString *pattern in [filters componentsSeparatedByCharactersInSet:separators]) {
		if (pattern.length == 0) {
			continue;
		}
		if (fnmatch(pattern.UTF8String, name.UTF8String, 0) == 0) {
			return YES;
		}
	}
	return NO;
}

BOOL NppFileNameMatches(NSString *name, NSString *filters) {
	return NameMatches(name, filters);
}

static BOOL WholeWordAt(NSString *line, NSRange range) {
	NSCharacterSet *word = [NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789_"];
	if (range.location > 0 && [word characterIsMember:[line characterAtIndex:range.location - 1]]) {
		return NO;
	}
	NSUInteger end = NSMaxRange(range);
	if (end < line.length && [word characterIsMember:[line characterAtIndex:end]]) {
		return NO;
	}
	return YES;
}

static NSRegularExpression *ExpressionForQuery(NSString *query, SearchFlags flags, NSError **error) {
	NSRegularExpressionOptions options = flags.matchCase ? 0 : NSRegularExpressionCaseInsensitive;
	NSString *pattern = flags.wholeWord ? [NSString stringWithFormat:@"\\b(?:%@)\\b", query] : query;
	return [NSRegularExpression regularExpressionWithPattern:pattern options:options error:error];
}

static void CollectMatches(NSString *line, NSString *query, SearchFlags flags, NSMutableArray<NSValue *> *matches, NSString **error) {
	if (query.length == 0 || line.length == 0) {
		return;
	}
	if (flags.regex) {
		NSError *local = nil;
		NSRegularExpression *expression = ExpressionForQuery(query, flags, &local);
		if (!expression) {
			if (error && *error == nil) {
				*error = local.localizedDescription ?: @"Invalid regular expression.";
			}
			return;
		}
		for (NSTextCheckingResult *result in [expression matchesInString:line options:0 range:NSMakeRange(0, line.length)]) {
			[matches addObject:[NSValue valueWithRange:result.range]];
		}
		return;
	}
	NSStringCompareOptions options = flags.matchCase ? 0 : NSCaseInsensitiveSearch;
	NSRange span = NSMakeRange(0, line.length);
	while (span.length > 0) {
		NSRange found = [line rangeOfString:query options:options range:span];
		if (found.location == NSNotFound) {
			return;
		}
		if (!flags.wholeWord || WholeWordAt(line, found)) {
			[matches addObject:[NSValue valueWithRange:found]];
		}
		NSUInteger next = NSMaxRange(found);
		if (next >= line.length) {
			return;
		}
		span = NSMakeRange(next, line.length - next);
	}
}

static NSString *ReplaceAllInString(NSString *text, NSString *query, NSString *replacement, SearchFlags flags, NSInteger *count, NSString **error) {
	NSMutableArray<NSValue *> *matches = [NSMutableArray array];
	CollectMatches(text, query, flags, matches, error);
	if (error && *error) {
		return nil;
	}
	if (matches.count == 0) {
		if (count) {
			*count = 0;
		}
		return text;
	}
	NSMutableString *result = [NSMutableString string];
	NSUInteger cursor = 0;
	for (NSValue *value in matches) {
		NSRange found = value.rangeValue;
		if (found.location < cursor) {
			continue;
		}
		[result appendString:[text substringWithRange:NSMakeRange(cursor, found.location - cursor)]];
		[result appendString:replacement ?: @""];
		cursor = NSMaxRange(found);
	}
	if (cursor < text.length) {
		[result appendString:[text substringFromIndex:cursor]];
	}
	if (count) {
		*count = (NSInteger)matches.count;
	}
	return result;
}

static NSString *ReplaceDocument(NSString *text, NSString *query, NSString *replacement, SearchFlags flags, NSInteger *count, NSString **error) {
	NSArray<NSString *> *parts = [text componentsSeparatedByString:@"\n"];
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	NSInteger total = 0;
	for (NSString *raw in parts) {
		BOOL carriage = raw.length > 0 && [raw characterAtIndex:raw.length - 1] == '\r';
		NSString *line = carriage ? [raw substringToIndex:raw.length - 1] : raw;
		NSInteger lineCount = 0;
		NSString *updated = ReplaceAllInString(line, query, replacement, flags, &lineCount, error);
		if (!updated) {
			return nil;
		}
		total += lineCount;
		if (carriage) {
			updated = [updated stringByAppendingString:@"\r"];
		}
		[lines addObject:updated];
	}
	if (count) {
		*count = total;
	}
	return [lines componentsJoinedByString:@"\n"];
}

static BOOL SearchOneFile(NSURL *url, NSString *query, SearchFlags flags, NSInteger limit, NSMutableArray<NppFindHit *> *hits, NSString **error) {
	NSData *data = [NSData dataWithContentsOfURL:url];
	if (!data.length || (NSInteger)hits.count >= limit) {
		return YES;
	}
	const uint8_t *bytes = (const uint8_t *)data.bytes;
	NSUInteger probe = MIN(data.length, (NSUInteger)8192);
	for (NSUInteger index = 0; index < probe; index++) {
		if (bytes[index] == 0) {
			return YES;
		}
	}
	NSString *text = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!text) {
		text = [[NSString alloc] initWithData:data encoding:NSISOLatin1StringEncoding];
	}
	if (!text) {
		return YES;
	}
	NSInteger lineNumber = 0;
	for (NSString *rawLine in [text componentsSeparatedByString:@"\n"]) {
		NSString *line = [rawLine hasSuffix:@"\r"] ? [rawLine substringToIndex:rawLine.length - 1] : rawLine;
		lineNumber++;
		NSMutableArray<NSValue *> *matches = [NSMutableArray array];
		CollectMatches(line, query, flags, matches, error);
		if (error && *error) {
			return NO;
		}
		for (NSValue *value in matches) {
			NSRange found = value.rangeValue;
			NSString *prefix = found.location > 0 ? [line substringToIndex:found.location] : @"";
			NSString *match = [line substringWithRange:found];
			NppFindHit *hit = [NppFindHit new];
			hit.path = url.path;
			hit.line = lineNumber;
			hit.lineText = line;
			hit.byteOffset = (NSInteger)[prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			hit.byteLength = (NSInteger)[match lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
			[hits addObject:hit];
			if ((NSInteger)hits.count >= limit) {
				return YES;
			}
		}
	}
	return YES;
}

NSArray<NppFindHit *> *NppFindInFiles(NSString *directory, NSString *query, NSString *filters, BOOL subfolders, SearchFlags flags, NSInteger limit) {
	if (directory.length == 0 || query.length == 0 || limit <= 0) {
		return @[];
	}
	NSMutableArray<NppFindHit *> *hits = [NSMutableArray array];
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:directory] includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey] options:subfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil];
	NSInteger scanned = 0;
	for (NSURL *url in enumerator) {
		if ((NSInteger)hits.count >= limit || scanned >= 20000) {
			break;
		}
		NSNumber *regular = nil;
		NSNumber *size = nil;
		[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
		[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
		if (!regular.boolValue || size.unsignedLongLongValue > 8 * 1024 * 1024) {
			continue;
		}
		if (!NameMatches(url.lastPathComponent, filters)) {
			continue;
		}
		scanned++;
		NSString *error = nil;
		if (!SearchOneFile(url, query, flags, limit, hits, &error) || error) {
			break;
		}
	}
	return hits;
}

@implementation NppFindScan
@end

@implementation NppFindScanToken
- (void)cancel {
	self.cancelled = YES;
}
@end

NppFindScanToken *NppStartFindInFiles(NSString *directory, NSString *query, NSString *filters, BOOL subfolders, SearchFlags flags, NSInteger limit, void (^handler)(NppFindScan *scan)) {
	NppFindScanToken *token = [NppFindScanToken new];
	if (!handler) {
		return token;
	}
	NSString *root = [directory copy] ?: @"";
	NSString *needle = [query copy] ?: @"";
	NSString *pattern = [filters copy] ?: @"";
	NSInteger cap = limit;
	dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		NSLock *lock = [NSLock new];
		NSMutableArray<NppFindHit *> *pending = [NSMutableArray array];
		__block NSInteger scanned = 0;
		__block NSString *current = @"";
		__block BOOL scheduled = NO;
		__block BOOL ended = NO;
		__block BOOL limited = NO;
		__block NSString *failure = nil;
		void (^schedule)(void) = ^{
			BOOL start = NO;
			[lock lock];
			if (!scheduled) {
				scheduled = YES;
				start = YES;
			}
			[lock unlock];
			if (!start) {
				return;
			}
			dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.08 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
				NSArray<NppFindHit *> *batch = nil;
				NSInteger count = 0;
				NSString *path = nil;
				BOOL done = NO;
				BOOL stopped = NO;
				BOOL hitLimit = NO;
				NSString *error = nil;
				[lock lock];
				batch = [pending copy];
				[pending removeAllObjects];
				count = scanned;
				path = [current copy];
				done = ended;
				stopped = token.cancelled;
				hitLimit = limited;
				error = failure;
				scheduled = NO;
				[lock unlock];
				NppFindScan *scan = [NppFindScan new];
				scan.hits = batch ?: @[];
				scan.scanned = count;
				scan.path = path ?: @"";
				scan.finished = done;
				scan.cancelled = done && stopped;
				scan.limited = done && hitLimit;
				scan.error = error;
				handler(scan);
			});
		};
		if (root.length == 0 || needle.length == 0 || cap <= 0) {
			[lock lock];
			ended = YES;
			failure = @"Enter the text to find and a folder that exists.";
			[lock unlock];
			schedule();
			return;
		}
		NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:root] includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey] options:subfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil];
		NSInteger seen = 0;
		NSInteger total = 0;
		for (NSURL *url in enumerator) {
			if (token.cancelled || total >= cap || seen >= 20000) {
				break;
			}
			NSNumber *regular = nil;
			NSNumber *size = nil;
			[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
			[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
			if (!regular.boolValue || size.unsignedLongLongValue > 8 * 1024 * 1024 || !NameMatches(url.lastPathComponent, pattern)) {
				continue;
			}
			NSMutableArray<NppFindHit *> *fileHits = [NSMutableArray array];
			NSString *error = nil;
			SearchOneFile(url, needle, flags, cap - total, fileHits, &error);
			seen++;
			total += (NSInteger)fileHits.count;
			[lock lock];
			scanned = seen;
			current = url.lastPathComponent ?: @"";
			if (error) {
				failure = error;
				ended = YES;
			} else if (fileHits.count) {
				[pending addObjectsFromArray:fileHits];
			}
			[lock unlock];
			schedule();
			if (error) {
				return;
			}
		}
		[lock lock];
		if (total >= cap || seen >= 20000) {
			limited = !token.cancelled;
		}
		ended = YES;
		[lock unlock];
		schedule();
	});
	return token;
}

@implementation NppReplaceFilesResult
@end

NppReplaceFilesResult *NppReplaceInFiles(NSString *directory, NSString *query, NSString *replacement, NSString *filters, BOOL subfolders, SearchFlags flags, NSArray<NSString *> *skipPaths) {
	NppReplaceFilesResult *result = [NppReplaceFilesResult new];
	result.paths = @[];
	if (directory.length == 0 || query.length == 0) {
		result.error = @"Enter the text to find and a folder that exists.";
		return result;
	}
	BOOL directoryExists = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&directoryExists];
	if (!directoryExists) {
		result.error = @"The folder does not exist.";
		return result;
	}
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:[NSURL fileURLWithPath:directory] includingPropertiesForKeys:@[NSURLIsRegularFileKey, NSURLFileSizeKey] options:subfolders ? 0 : NSDirectoryEnumerationSkipsSubdirectoryDescendants errorHandler:nil];
	NSInteger scanned = 0;
	for (NSURL *url in enumerator) {
		if (scanned >= 20000) {
			break;
		}
		NSNumber *regular = nil;
		NSNumber *size = nil;
		[url getResourceValue:&regular forKey:NSURLIsRegularFileKey error:nil];
		[url getResourceValue:&size forKey:NSURLFileSizeKey error:nil];
		if (!regular.boolValue || size.unsignedLongLongValue > 8 * 1024 * 1024) {
			continue;
		}
		if (!NameMatches(url.lastPathComponent, filters) || [skipPaths containsObject:url.path]) {
			continue;
		}
		scanned++;
		NSData *data = [NSData dataWithContentsOfURL:url];
		if (!data.length) {
			continue;
		}
		const uint8_t *bytes = (const uint8_t *)data.bytes;
		NSUInteger probe = MIN(data.length, (NSUInteger)8192);
		BOOL binary = NO;
		for (NSUInteger index = 0; index < probe; index++) {
			if (bytes[index] == 0) {
				binary = YES;
				break;
			}
		}
		if (binary) {
			continue;
		}
		DecodedBuffer decoded = DecodeBuffer(bytes, data.length);
		NSString *text = [[NSString alloc] initWithBytes:decoded.utf8.data() length:decoded.utf8.size() encoding:NSUTF8StringEncoding];
		if (!text) {
			continue;
		}
		NSInteger count = 0;
		NSString *error = nil;
		NSString *updated = ReplaceDocument(text, query, replacement ?: @"", flags, &count, &error);
		if (error) {
			result.error = error;
			return result;
		}
		if (count == 0 || !updated) {
			continue;
		}
		std::string encoded;
		std::string failure;
		std::string utf8(updated.UTF8String ?: "", strlen(updated.UTF8String ?: ""));
		if (!EncodeBuffer(utf8, decoded.encoding, &encoded, &failure)) {
			result.error = @(failure.c_str());
			return result;
		}
		NSData *written = [NSData dataWithBytes:encoded.data() length:encoded.size()];
		if (![written writeToURL:url options:NSDataWritingAtomic error:nil]) {
			result.error = [NSString stringWithFormat:@"Could not write %@.", url.lastPathComponent];
			return result;
		}
		result.replacements += count;
		result.filesChanged += 1;
		[paths addObject:url.path];
	}
	result.paths = paths;
	return result;
}
