#import "SandboxAccess.h"

static NSString *const kBookmarksKey = @"securityScopedBookmarks";
static const NSUInteger kMaxBookmarks = 200;

BOOL NppIsSandboxed(void) {
	static BOOL sandboxed;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		sandboxed = NSProcessInfo.processInfo.environment[@"APP_SANDBOX_CONTAINER_ID"].length > 0;
	});
	return sandboxed;
}

static NSMutableSet<NSString *> *ActivePaths(void) {
	static NSMutableSet<NSString *> *paths;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		paths = [NSMutableSet set];
	});
	return paths;
}

static NSString *Normalized(NSString *path) {
	return path.length ? path.stringByStandardizingPath : @"";
}

static NSDictionary<NSString *, NSData *> *StoredBookmarks(void) {
	NSDictionary *stored = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kBookmarksKey];
	return [stored isKindOfClass:[NSDictionary class]] ? stored : @{};
}

static void StoreBookmarks(NSDictionary<NSString *, NSData *> *bookmarks) {
	[[NSUserDefaults standardUserDefaults] setObject:bookmarks forKey:kBookmarksKey];
}

static NSData *BookmarkFor(NSURL *url) {
	return [url bookmarkDataWithOptions:NSURLBookmarkCreationWithSecurityScope includingResourceValuesForKeys:nil relativeToURL:nil error:nil];
}

static BOOL StartFromBookmark(NSString *key, NSData *data) {
	BOOL stale = NO;
	NSURL *url = [NSURL URLByResolvingBookmarkData:data options:NSURLBookmarkResolutionWithSecurityScope | NSURLBookmarkResolutionWithoutUI relativeToURL:nil bookmarkDataIsStale:&stale error:nil];
	if (!url || ![url startAccessingSecurityScopedResource]) {
		return NO;
	}
	[ActivePaths() addObject:key];
	if (stale) {
		NSData *fresh = BookmarkFor(url);
		if (fresh) {
			NSMutableDictionary *bookmarks = [StoredBookmarks() mutableCopy];
			bookmarks[key] = fresh;
			StoreBookmarks(bookmarks);
		}
	}
	return YES;
}

BOOL NppBeginAccess(NSString *path) {
	if (!NppIsSandboxed()) {
		return YES;
	}
	NSString *target = Normalized(path);
	if (target.length == 0) {
		return NO;
	}
	NSDictionary<NSString *, NSData *> *bookmarks = StoredBookmarks();
	// The path itself, then each parent folder.
	for (NSString *candidate = target; candidate.length > 1; candidate = candidate.stringByDeletingLastPathComponent) {
		if ([ActivePaths() containsObject:candidate]) {
			return YES;
		}
		NSData *data = bookmarks[candidate];
		if (data && StartFromBookmark(candidate, data)) {
			return YES;
		}
	}
	return [[NSFileManager defaultManager] isReadableFileAtPath:target];
}

void NppRememberAccess(NSString *path) {
	if (!NppIsSandboxed()) {
		return;
	}
	NSString *target = Normalized(path);
	if (target.length == 0 || [ActivePaths() containsObject:target]) {
		return;
	}
	NSData *data = BookmarkFor([NSURL fileURLWithPath:target]);
	if (!data) {
		return;
	}
	NSMutableDictionary *bookmarks = [StoredBookmarks() mutableCopy];
	bookmarks[target] = data;
	while (bookmarks.count > kMaxBookmarks) {
		[bookmarks removeObjectForKey:bookmarks.allKeys.firstObject];
	}
	StoreBookmarks(bookmarks);
}

