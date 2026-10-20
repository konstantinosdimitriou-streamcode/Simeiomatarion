#import "AppDelegate.h"

#import "ClipboardHistory.h"
#import "DocumentTab.h"
#import "EditorActions.h"
#import "EditorSettings.h"
#import "Encoding.h"
#import "LangCatalog.h"
#import "Localization.h"
#import "MacroStore.h"
#import "MinimapView.h"
#import "NppMacPlugin.h"
#import "OfficeOpen.h"
#import "OutlineIndex.h"
#import "PreviewHTML.h"
#import "Search.h"
#import "SnippetStore.h"
#import "TextTools.h"
#import "UserLanguages.h"

#import <PDFKit/PDFKit.h>
#import <WebKit/WebKit.h>

#include <dlfcn.h>

@interface AppDelegate (ContextMenus)
- (void)selectTabForContext:(NSInteger)index;
- (NSMenu *)tabContextMenu;
@end

static NSString *const NppTabDragType = @"npp.document.tab";

@interface AppDelegate (TabDrag)
- (void)forceCloseTab:(DocumentTab *)document fromView:(NSView *)view;
- (void)noteTabDragStarted:(DocumentTab *)document;
- (void)noteTabDragEnded;
- (void)moveDocumentToNewWindow:(DocumentTab *)document;
- (DocumentTab *)draggedTabDocument;
- (void)moveDocument:(DocumentTab *)document toPane:(NSInteger)pane atIndex:(NSInteger)index;
- (void)showDocument:(DocumentTab *)document inPane:(NSInteger)pane;
- (BOOL)canSplitDocument:(DocumentTab *)document besidePane:(NSInteger)pane onRight:(BOOL)onRight;
- (BOOL)splitDocument:(DocumentTab *)document besidePane:(NSInteger)pane onRight:(BOOL)onRight;
@end

@interface NppTabButton : NSButton <NSDraggingSource>
@property (nonatomic, weak) AppDelegate *owner;
@property (nonatomic, weak) DocumentTab *document;
@end

@implementation NppTabButton
- (void)rightMouseDown:(NSEvent *)event {
	if (self.document) {
		[self.owner showDocument:self.document inPane:NSNotFound];
	}
	NSMenu *menu = [self.owner tabContextMenu];
	if (menu) {
		[NSMenu popUpContextMenu:menu withEvent:event forView:self];
	}
}
- (void)otherMouseDown:(NSEvent *)event {
	if (event.buttonNumber == 2 && self.document) {
		[self.owner forceCloseTab:self.document fromView:self];
		return;
	}
	[super otherMouseDown:event];
}
- (void)mouseDown:(NSEvent *)event {
	NSPoint start = event.locationInWindow;
	NSEvent *dragEvent = nil;
	while (YES) {
		NSEvent *next = [self.window nextEventMatchingMask:NSEventMaskLeftMouseUp | NSEventMaskLeftMouseDragged];
		if (next.type == NSEventTypeLeftMouseUp) {
			break;
		}
		CGFloat dx = next.locationInWindow.x - start.x;
		CGFloat dy = next.locationInWindow.y - start.y;
		if (dx * dx + dy * dy > 16) {
			dragEvent = next;
			break;
		}
	}
	if (!dragEvent) {
		[self sendAction:self.action to:self.target];
		return;
	}
	[self.owner noteTabDragStarted:self.document];
	NSPasteboardItem *writer = [NSPasteboardItem new];
	[writer setString:self.document.displayName ?: @"Tab" forType:NppTabDragType];
	NSDraggingItem *item = [[NSDraggingItem alloc] initWithPasteboardWriter:writer];
	NSRect frame = self.bounds;
	item.draggingFrame = frame;
	NSImage *image = [[NSImage alloc] initWithSize:frame.size];
	[image lockFocus];
	[[NSColor.controlBackgroundColor colorWithAlphaComponent:0.92] setFill];
	NSRectFill(NSMakeRect(0, 0, frame.size.width, frame.size.height));
	[self.attributedTitle drawAtPoint:NSMakePoint(4, 4)];
	[image unlockFocus];
	[item setDraggingFrame:frame contents:image];
	[self beginDraggingSessionWithItems:@[item] event:dragEvent source:self];
}
- (NSDragOperation)draggingSession:(NSDraggingSession *)session sourceOperationMaskForDraggingContext:(NSDraggingContext)context {
	(void)session;
	(void)context;
	return NSDragOperationMove;
}
- (void)draggingSession:(NSDraggingSession *)session endedAtPoint:(NSPoint)screenPoint operation:(NSDragOperation)operation {
	(void)session;
	DocumentTab *document = self.document;
	BOOL outside = self.window && !NSPointInRect(screenPoint, self.window.frame);
	[self.owner noteTabDragEnded];
	if (outside && operation == NSDragOperationNone && document) {
		[self.owner moveDocumentToNewWindow:document];
	}
}
@end

@interface NppTabCloseButton : NSButton
@property (nonatomic, weak) DocumentTab *document;
@end

@implementation NppTabCloseButton
- (void)otherMouseDown:(NSEvent *)event {
	DocumentTab *document = self.document;
	if (event.buttonNumber == 2 && document && [self.target respondsToSelector:@selector(forceCloseTab:fromView:)]) {
		[(id)self.target forceCloseTab:document fromView:self];
		return;
	}
	[super otherMouseDown:event];
}
@end

@interface NppTabChip : NSView
@property (nonatomic, weak) DocumentTab *document;
@end

@interface NppTabLabel : NSView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) NSColor *textColor;
@end

@interface NppTabBadge : NSView
@property (nonatomic, copy) NSString *mark;
@property (nonatomic, strong) NSColor *fill;
@property (nonatomic, assign) BOOL darkText;
@end

@implementation NppTabBadge
- (NSView *)hitTest:(NSPoint)point {
	(void)point;
	return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	NSRect box = NSInsetRect(self.bounds, 0.5, 1);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:box xRadius:3 yRadius:3];
	[(self.fill ?: NSColor.systemGrayColor) setFill];
	[path fill];
	if (self.mark.length == 0) {
		return;
	}
	NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
	style.alignment = NSTextAlignmentCenter;
	CGFloat size = self.mark.length >= 3 ? 6 : (self.mark.length == 2 ? 7 : 9);
	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold],
		NSForegroundColorAttributeName: self.darkText ? NSColor.blackColor : NSColor.whiteColor,
		NSParagraphStyleAttributeName: style
	};
	[self.mark drawWithRect:NSMakeRect(0, 3, NSWidth(self.bounds), NSHeight(self.bounds) - 3) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
}
@end

@implementation NppTabLabel
- (NSView *)hitTest:(NSPoint)point {
	(void)point;
	return nil;
}

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	if (self.text.length == 0) {
		return;
	}
	NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
	style.lineBreakMode = NSLineBreakByClipping;
	style.alignment = NSTextAlignmentLeft;
	NSDictionary *attributes = @{
		NSFontAttributeName: self.font ?: [NSFont systemFontOfSize:12],
		NSForegroundColorAttributeName: self.textColor ?: NSColor.labelColor,
		NSParagraphStyleAttributeName: style
	};
	NSRect textRect = NSMakeRect(0, 1, self.bounds.size.width, self.bounds.size.height - 2);
	[self.text drawWithRect:textRect options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
}
@end

static NSString *NppFitTitle(NSString *text, NSFont *font, CGFloat maxWidth) {
	if (text.length == 0) {
		return @"";
	}
	NSDictionary *attributes = @{NSFontAttributeName: font ?: [NSFont systemFontOfSize:12]};
	if (maxWidth < 12 || [text sizeWithAttributes:attributes].width <= maxWidth) {
		return text;
	}
	NSString *ellipsis = @"…";
	NSString *best = ellipsis;
	NSInteger low = 2;
	NSInteger high = (NSInteger)text.length - 1;
	while (low <= high) {
		NSInteger mid = (low + high) / 2;
		NSInteger head = MAX(1, mid / 2);
		NSInteger tail = MAX(1, mid - head);
		if (head + tail >= (NSInteger)text.length) {
			high = mid - 1;
			continue;
		}
		NSString *candidate = [NSString stringWithFormat:@"%@%@%@", [text substringToIndex:(NSUInteger)head], ellipsis, [text substringFromIndex:text.length - (NSUInteger)tail]];
		if ([candidate sizeWithAttributes:attributes].width <= maxWidth) {
			best = candidate;
			low = mid + 1;
		} else {
			high = mid - 1;
		}
	}
	return best;
}

static BOOL NppKnownFileBadge(NSString *key, NSString **mark, NSString **kind, NSColor **fill, BOOL *darkText) {
	static NSDictionary<NSString *, NSArray *> *badges;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSColor *(^rgb)(int, int, int) = ^NSColor *(int red, int green, int blue) {
			return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1];
		};
		badges = @{
			@"html": @[@"<>", @"HTML", rgb(227, 76, 38), @NO],
			@"htm": @[@"<>", @"HTML", rgb(227, 76, 38), @NO],
			@"xml": @[@"<>", @"XML", rgb(240, 125, 40), @NO],
			@"svg": @[@"SV", @"SVG", rgb(255, 181, 38), @YES],
			@"json": @[@"{}", @"JSON", rgb(201, 162, 39), @YES],
			@"json5": @[@"{}", @"JSON", rgb(201, 162, 39), @YES],
			@"jsonc": @[@"{}", @"JSON", rgb(201, 162, 39), @YES],
			@"yml": @[@"YL", @"YAML", rgb(139, 92, 246), @NO],
			@"yaml": @[@"YL", @"YAML", rgb(139, 92, 246), @NO],
			@"properties": @[@"PR", @"Properties", rgb(100, 116, 139), @NO],
			@"props": @[@"PR", @"Properties", rgb(100, 116, 139), @NO],
			@"ini": @[@"CF", @"Config", rgb(100, 116, 139), @NO],
			@"conf": @[@"CF", @"Config", rgb(100, 116, 139), @NO],
			@"cfg": @[@"CF", @"Config", rgb(100, 116, 139), @NO],
			@"env": @[@"CF", @"Config", rgb(100, 116, 139), @NO],
			@"toml": @[@"TM", @"TOML", rgb(156, 110, 72), @NO],
			@"js": @[@"JS", @"JavaScript", rgb(201, 162, 39), @YES],
			@"mjs": @[@"JS", @"JavaScript", rgb(201, 162, 39), @YES],
			@"cjs": @[@"JS", @"JavaScript", rgb(201, 162, 39), @YES],
			@"jsx": @[@"JS", @"JavaScript", rgb(201, 162, 39), @YES],
			@"ts": @[@"TS", @"TypeScript", rgb(49, 120, 198), @NO],
			@"tsx": @[@"TS", @"TypeScript", rgb(49, 120, 198), @NO],
			@"css": @[@"CS", @"CSS", rgb(21, 114, 182), @NO],
			@"scss": @[@"CS", @"CSS", rgb(205, 103, 153), @NO],
			@"less": @[@"CS", @"CSS", rgb(29, 54, 93), @NO],
			@"py": @[@"PY", @"Python", rgb(55, 118, 171), @NO],
			@"md": @[@"MD", @"Markdown", rgb(90, 106, 122), @NO],
			@"markdown": @[@"MD", @"Markdown", rgb(90, 106, 122), @NO],
			@"sh": @[@"SH", @"Shell", rgb(78, 154, 81), @NO],
			@"bash": @[@"SH", @"Shell", rgb(78, 154, 81), @NO],
			@"zsh": @[@"SH", @"Shell", rgb(78, 154, 81), @NO],
			@"sql": @[@"SQ", @"SQL", rgb(51, 103, 145), @NO],
			@"php": @[@"PH", @"PHP", rgb(119, 123, 180), @NO],
			@"java": @[@"JV", @"Java", rgb(176, 114, 25), @NO],
			@"go": @[@"GO", @"Go", rgb(0, 173, 216), @YES],
			@"rs": @[@"RS", @"Rust", rgb(206, 65, 43), @NO],
			@"c": @[@"C", @"C", rgb(85, 85, 85), @NO],
			@"cc": @[@"C+", @"C++", rgb(0, 89, 156), @NO],
			@"cpp": @[@"C+", @"C++", rgb(0, 89, 156), @NO],
			@"cxx": @[@"C+", @"C++", rgb(0, 89, 156), @NO],
			@"h": @[@"C+", @"C++", rgb(0, 89, 156), @NO],
			@"hpp": @[@"C+", @"C++", rgb(0, 89, 156), @NO],
			@"swift": @[@"SW", @"Swift", rgb(240, 81, 56), @NO],
			@"rb": @[@"RB", @"Ruby", rgb(176, 42, 36), @NO],
			@"kt": @[@"KT", @"Kotlin", rgb(127, 82, 255), @NO],
			@"dart": @[@"DT", @"Dart", rgb(0, 180, 171), @YES],
			@"lua": @[@"LU", @"Lua", rgb(0, 0, 128), @NO],
			@"pl": @[@"PL", @"Perl", rgb(2, 152, 195), @NO],
			@"vue": @[@"VU", @"Vue", rgb(65, 184, 131), @YES],
			@"csv": @[@"CV", @"CSV", rgb(46, 125, 50), @NO],
			@"pdf": @[@"PF", @"PDF", rgb(220, 50, 47), @NO],
			@"doc": @[@"W", @"Word", rgb(43, 87, 154), @NO],
			@"docx": @[@"W", @"Word", rgb(43, 87, 154), @NO],
			@"xlsx": @[@"XL", @"Excel", rgb(33, 115, 70), @NO],
			@"log": @[@"LG", @"Log", rgb(120, 120, 120), @NO],
			@"txt": @[@"TX", @"Text", rgb(120, 120, 120), @NO],
			@"dockerfile": @[@"DK", @"Docker", rgb(36, 150, 237), @NO],
			@"makefile": @[@"MK", @"Makefile", rgb(108, 117, 125), @NO]
		};
	});
	NSArray *badge = badges[key.lowercaseString ?: @""];
	if (badge.count < 4) {
		return NO;
	}
	if (mark) {
		*mark = badge[0];
	}
	if (kind) {
		*kind = badge[1];
	}
	if (fill) {
		*fill = badge[2];
	}
	if (darkText) {
		*darkText = [badge[3] boolValue];
	}
	return YES;
}

static NSImage *NppTintedSymbol(NSString *name, NSColor *color) {
	NSImage *image = [NSImage imageWithSystemSymbolName:name accessibilityDescription:name];
	if (!image) {
		return nil;
	}
	NSImageSymbolConfiguration *size = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
	NSImageSymbolConfiguration *palette = [NSImageSymbolConfiguration configurationWithPaletteColors:@[color ?: NSColor.labelColor]];
	image = [image imageWithSymbolConfiguration:[size configurationByApplyingConfiguration:palette]] ?: image;
	image.size = NSMakeSize(16, 16);
	return image;
}

static NSImage *NppFileMarkImage(NSString *key) {
	static NSMutableDictionary<NSString *, NSImage *> *cache;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		cache = [NSMutableDictionary dictionary];
	});
	NSString *lookup = key.lowercaseString ?: @"";
	NSImage *cached = cache[lookup];
	if (cached) {
		return cached == (id)[NSNull null] ? nil : cached;
	}
	NSString *mark = nil;
	NSString *kind = nil;
	NSColor *fill = nil;
	BOOL darkText = NO;
	if (!NppKnownFileBadge(lookup, &mark, &kind, &fill, &darkText)) {
		cache[lookup] = (id)[NSNull null];
		return nil;
	}
	NSImage *image = [NSImage imageWithSize:NSMakeSize(16, 16) flipped:NO drawingHandler:^BOOL(NSRect rect) {
		NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0, 1) xRadius:3 yRadius:3];
		[fill setFill];
		[path fill];
		NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
		style.alignment = NSTextAlignmentCenter;
		CGFloat size = mark.length >= 3 ? 6 : (mark.length == 2 ? 7.5 : 9);
		NSDictionary *attributes = @{
			NSFontAttributeName: [NSFont monospacedSystemFontOfSize:size weight:NSFontWeightBold],
			NSForegroundColorAttributeName: darkText ? NSColor.blackColor : NSColor.whiteColor,
			NSParagraphStyleAttributeName: style
		};
		[mark drawWithRect:NSMakeRect(0, 2.5, 16, 12) options:NSStringDrawingUsesLineFragmentOrigin attributes:attributes];
		return YES;
	}];
	cache[lookup] = image;
	return image;
}

static NSImage *NppSidebarFileIcon(NSString *name, NSString *path, BOOL directory) {
	NSString *extension = name.pathExtension.lowercaseString ?: @"";
	if (directory && ![extension isEqualToString:@"app"]) {
		static NSImage *folder;
		static dispatch_once_t once;
		dispatch_once(&once, ^{
			folder = NppTintedSymbol(@"folder.fill", NSColor.systemBlueColor);
		});
		return folder;
	}
	if ([extension isEqualToString:@"app"] || [extension isEqualToString:@"png"] || [extension isEqualToString:@"jpg"] || [extension isEqualToString:@"jpeg"] || [extension isEqualToString:@"gif"] || [extension isEqualToString:@"webp"] || [extension isEqualToString:@"icns"] || [extension isEqualToString:@"pdf"] || [extension isEqualToString:@"dmg"]) {
		NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:path];
		icon.size = NSMakeSize(16, 16);
		return icon;
	}
	NSImage *badge = NppFileMarkImage(extension);
	if (!badge && name.length) {
		badge = NppFileMarkImage(name.lowercaseString);
	}
	if (badge) {
		return badge;
	}
	if ([@[@"zip", @"gz", @"tgz", @"tar", @"7z", @"rar"] containsObject:extension]) {
		static NSImage *archive;
		static dispatch_once_t once;
		dispatch_once(&once, ^{
			archive = NppTintedSymbol(@"doc.zipper", NSColor.systemBrownColor);
		});
		return archive;
	}
	static NSImage *plain;
	static dispatch_once_t plainOnce;
	dispatch_once(&plainOnce, ^{
		plain = NppTintedSymbol(@"doc", NSColor.secondaryLabelColor);
	});
	return plain;
}

static NSView *NppFileBadge(DocumentTab *document, NSString **kind) {
	NSString *extension = document.displayName.pathExtension.lowercaseString;
	if (extension.length == 0) {
		extension = document.path.pathExtension.lowercaseString;
	}
	NSString *base = document.displayName.stringByDeletingPathExtension.lowercaseString ?: @"";
	NSDictionary *aliases = @{
		@"hypertext": @"html",
		@"html": @"html",
		@"javascript.js": @"js",
		@"javascript": @"js",
		@"yaml": @"yml",
		@"props": @"properties",
		@"markdown": @"md",
		@"python": @"py",
		@"bash": @"sh",
		@"json5": @"json",
		@"phpscript": @"php",
		@"cpp": @"cpp"
	};
	NSMutableArray<NSString *> *keys = [NSMutableArray array];
	for (NSString *raw in @[extension ?: @"", base, document.language.lowercaseString ?: @"", document.lexerName.lowercaseString ?: @""]) {
		if (raw.length == 0) {
			continue;
		}
		[keys addObject:aliases[raw] ?: raw];
		[keys addObject:raw];
	}
	if ([base isEqualToString:@"dockerfile"] || [document.displayName.lowercaseString hasPrefix:@"dockerfile"]) {
		[keys insertObject:@"dockerfile" atIndex:0];
	}
	if ([base isEqualToString:@"makefile"] || [document.displayName.lowercaseString hasPrefix:@"makefile"]) {
		[keys insertObject:@"makefile" atIndex:0];
	}
	for (NSString *key in keys) {
		NSString *mark = nil;
		NSString *name = nil;
		NSColor *fill = nil;
		BOOL darkText = NO;
		if (!NppKnownFileBadge(key, &mark, &name, &fill, &darkText)) {
			continue;
		}
		if (kind) {
			*kind = name;
		}
		NppTabBadge *badge = [NppTabBadge new];
		badge.mark = mark;
		badge.fill = fill;
		badge.darkText = darkText;
		return badge;
	}
	if (kind) {
		*kind = nil;
	}
	NSImage *image = [NSImage imageWithSystemSymbolName:@"doc.text" accessibilityDescription:@"Text"];
	NSImageView *icon = [NSImageView imageViewWithImage:image];
	icon.imageScaling = NSImageScaleProportionallyDown;
	icon.contentTintColor = NSColor.secondaryLabelColor;
	icon.symbolConfiguration = [NSImageSymbolConfiguration configurationWithPointSize:12 weight:NSFontWeightRegular];
	return icon;
}

static NSString *NppZoomLine(ScintillaView *editor, long line) {
	long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
	long end = [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
	if (end < start) {
		return @"";
	}
	long length = MIN(240, end - start);
	if (length <= 0) {
		return @"";
	}
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = start;
	range.chrg.cpMax = start + length;
	range.lpstrText = buffer.data();
	[editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	NSString *text = nil;
	NSUInteger count = (NSUInteger)length;
	while (count > 0 && !text) {
		text = [[NSString alloc] initWithBytes:buffer.data() length:count encoding:NSUTF8StringEncoding];
		if (!text) {
			count--;
		}
	}
	text = [text ?: @"" stringByReplacingOccurrencesOfString:@"\t" withString:@"    "];
	if (end - start > length) {
		text = [text stringByAppendingString:@"…"];
	}
	return text;
}

static long NppZoomColumnPosition(ScintillaView *editor, long line, long visualColumn) {
	long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)line lParam:0];
	long end = [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0];
	if (visualColumn <= 0 || end <= start) {
		return start;
	}
	long length = MIN(end - start, 4000);
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = start;
	range.chrg.cpMax = start + length;
	range.lpstrText = buffer.data();
	[editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	NSString *text = nil;
	NSUInteger count = (NSUInteger)length;
	while (count > 0 && !text) {
		text = [[NSString alloc] initWithBytes:buffer.data() length:count encoding:NSUTF8StringEncoding];
		if (!text) {
			count--;
		}
	}
	if (text.length == 0) {
		return start;
	}
	__block NSUInteger used = 0;
	__block long visual = 0;
	[text enumerateSubstringsInRange:NSMakeRange(0, text.length) options:NSStringEnumerationByComposedCharacterSequences usingBlock:^(NSString *character, NSRange range, NSRange enclosing, BOOL *stop) {
		(void)enclosing;
		if (visual >= visualColumn) {
			*stop = YES;
			return;
		}
		visual += [character isEqualToString:@"\t"] ? 4 : 1;
		used = NSMaxRange(range);
	}];
	NSUInteger bytes = [[text substringToIndex:used] lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	long pos = start + (long)bytes;
	return MIN(end, MAX(start, pos));
}

@implementation NppTabChip
@end

static NSURL *SupportDirectory(void) {
	NSFileManager *files = [NSFileManager defaultManager];
	NSURL *base = [files URLForDirectory:NSApplicationSupportDirectory inDomain:NSUserDomainMask appropriateForURL:nil create:YES error:nil];
	NSURL *directory = [base URLByAppendingPathComponent:@"NotepadPlusPlus" isDirectory:YES];
	[files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
	return directory;
}

@interface WorkspaceView : NSView
@property (nonatomic, strong) NSView *menuBar;
@property (nonatomic, strong) NSView *toolbar;
@property (nonatomic, strong) NSView *tabStrip;
@property (nonatomic, strong) NSView *tabs;
@property (nonatomic, strong) NSView *findBar;
@property (nonatomic, strong) NSView *results;
@property (nonatomic, strong) NSView *status;
@property (nonatomic, strong) NSView *sidebar;
@property (nonatomic, strong) NSView *compareBar;
@property (nonatomic, assign) BOOL sidebarVisible;
@property (nonatomic, assign) BOOL findVisible;
@property (nonatomic, assign) BOOL resultsVisible;
@property (nonatomic, assign) BOOL compareVisible;
@property (nonatomic, weak) AppDelegate *dropOwner;
- (void)layoutPanes;
@end

@interface AppDelegate (DroppedFiles)
- (BOOL)openDroppedPaths:(NSArray<NSString *> *)paths;
@end

@interface AppDelegate (FolderLayout)
- (void)layoutFolderSidebar;
@end

@interface AppDelegate (Appearance)
- (void)systemAppearanceChanged;
@end

@interface NppDropOverlay : NSView
@end

@implementation NppDropOverlay
- (NSView *)hitTest:(NSPoint)point {
	(void)point;
	return nil;
}
@end

@implementation WorkspaceView {
	BOOL _layingOut;
	NppDropOverlay *_dropOverlay;
}
- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		[self registerForDraggedTypes:@[NSPasteboardTypeFileURL]];
	}
	return self;
}
- (void)viewDidChangeEffectiveAppearance {
	[super viewDidChangeEffectiveAppearance];
	[self.dropOwner systemAppearanceChanged];
}
- (NSView *)hitTest:(NSPoint)point {
	NSView *hit = [super hitTest:point];
	NSPoint local = [self convertPoint:point fromView:self.superview];
	for (NSView *view in self.subviews) {
		if (view.hidden || ![view.identifier isEqualToString:@"npp.minimapZoom"]) {
			continue;
		}
		if (!NSPointInRect(local, view.frame)) {
			continue;
		}
		NSView *cardHit = [view hitTest:local];
		if (cardHit) {
			return cardHit;
		}
	}
	return hit;
}
- (NSArray<NSString *> *)droppedFilePaths:(id<NSDraggingInfo>)sender {
	NSArray<NSURL *> *urls = [sender.draggingPasteboard readObjectsForClasses:@[[NSURL class]] options:@{NSPasteboardURLReadingFileURLsOnlyKey: @YES}];
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	NSFileManager *files = [NSFileManager defaultManager];
	for (NSURL *url in urls) {
		if (!url.isFileURL || url.path.length == 0) {
			continue;
		}
		BOOL directory = NO;
		if ([files fileExistsAtPath:url.path isDirectory:&directory] && !directory) {
			[paths addObject:url.path];
		}
	}
	return paths;
}
- (void)setDropHighlight:(BOOL)highlight {
	if (highlight) {
		if (!_dropOverlay) {
			_dropOverlay = [[NppDropOverlay alloc] initWithFrame:self.bounds];
			_dropOverlay.wantsLayer = YES;
			_dropOverlay.layer.borderWidth = 3;
			_dropOverlay.layer.borderColor = NSColor.controlAccentColor.CGColor;
			_dropOverlay.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.12].CGColor;
		}
		_dropOverlay.frame = self.bounds;
		[self addSubview:_dropOverlay positioned:NSWindowAbove relativeTo:nil];
	} else {
		[_dropOverlay removeFromSuperview];
	}
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	if ([self droppedFilePaths:sender].count == 0) {
		return NSDragOperationNone;
	}
	[self setDropHighlight:YES];
	return NSDragOperationCopy;
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	return [self droppedFilePaths:sender].count == 0 ? NSDragOperationNone : NSDragOperationCopy;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
	(void)sender;
	[self setDropHighlight:NO];
}
- (void)draggingEnded:(id<NSDraggingInfo>)sender {
	(void)sender;
	[self setDropHighlight:NO];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	return [self droppedFilePaths:sender].count > 0;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	NSArray<NSString *> *paths = [self droppedFilePaths:sender];
	[self setDropHighlight:NO];
	if (paths.count == 0) {
		return NO;
	}
	return [self.dropOwner openDroppedPaths:paths];
}
- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	[self layoutPanes];
}
- (void)resizeWithOldSuperviewSize:(NSSize)oldSize {
	[super resizeWithOldSuperviewSize:oldSize];
	[self layoutPanes];
}
- (void)layout {
	[super layout];
	[self layoutPanes];
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	(void)oldSize;
	[self layoutPanes];
}
- (void)layoutPanes {
	if (_layingOut || self.tabs == nil) {
		return;
	}
	_layingOut = YES;
	NSRect bounds = self.bounds;
	CGFloat menuHeight = 26;
	CGFloat toolbarHeight = 72;
	CGFloat tabHeight = self.tabStrip.hidden ? 0 : 30;
	CGFloat statusHeight = 24;
	CGFloat compareHeight = self.compareVisible ? 32 : 0;
	CGFloat findHeight = self.findVisible ? 96 : 0;
	CGFloat resultsHeight = self.resultsVisible ? 260 : 0;
	CGFloat top = menuHeight + toolbarHeight + tabHeight;
	self.menuBar.frame = NSMakeRect(0, bounds.size.height - menuHeight, bounds.size.width, menuHeight);
	self.toolbar.frame = NSMakeRect(0, bounds.size.height - menuHeight - toolbarHeight, bounds.size.width, toolbarHeight);
	self.tabStrip.frame = NSMakeRect(0, bounds.size.height - top, bounds.size.width, tabHeight);
	self.status.frame = NSMakeRect(0, 0, bounds.size.width, statusHeight);
	self.compareBar.frame = NSMakeRect(0, statusHeight, bounds.size.width, compareHeight);
	self.compareBar.hidden = !self.compareVisible;
	if (self.compareVisible) {
		CGFloat x = self.compareBar.bounds.size.width - 8;
		for (NSNumber *tag in @[@44, @43, @42, @46, @45]) {
			NSButton *button = nil;
			for (NSView *view in self.compareBar.subviews) {
				if (view.tag == tag.integerValue && [view isKindOfClass:[NSButton class]]) {
					button = (NSButton *)view;
					break;
				}
			}
			if (!button) {
				continue;
			}
			[button sizeToFit];
			CGFloat width = ceil(NSWidth(button.bounds)) + 14;
			x -= width;
			button.frame = NSMakeRect(x, 4, width, 24);
			x -= 6;
		}
		for (NSView *view in self.compareBar.subviews) {
			if (view.tag == 41) {
				view.frame = NSMakeRect(12, 6, MAX(40, x - 18), 20);
			}
		}
	}
	self.results.frame = NSMakeRect(0, statusHeight + compareHeight, bounds.size.width, resultsHeight);
	self.results.hidden = !self.resultsVisible;
	self.findBar.frame = NSMakeRect(0, statusHeight + compareHeight + resultsHeight, bounds.size.width, findHeight);
	self.findBar.hidden = !self.findVisible;
	CGFloat bottom = statusHeight + compareHeight + resultsHeight + findHeight;
	CGFloat side = self.sidebarVisible ? 280 : 0;
	CGFloat editorHeight = MAX(0, bounds.size.height - top - bottom);
	self.sidebar.frame = NSMakeRect(0, bottom, side, editorHeight);
	self.sidebar.hidden = !self.sidebarVisible;
	if (self.sidebarVisible) {
		[self.dropOwner layoutFolderSidebar];
	}
	NSRect editorFrame = NSMakeRect(side, bottom, MAX(0, bounds.size.width - side), editorHeight);
	self.tabs.frame = editorFrame;
	self.tabs.clipsToBounds = YES;
	if ([self.tabs isKindOfClass:[NSTabView class]]) {
		NSTabView *tabs = (NSTabView *)self.tabs;
		for (NSTabViewItem *item in tabs.tabViewItems) {
			item.view.frame = tabs.bounds;
		}
	}
	[self addSubview:self.compareBar positioned:NSWindowAbove relativeTo:self.tabs];
	[self addSubview:self.results positioned:NSWindowAbove relativeTo:self.tabs];
	[self addSubview:self.findBar positioned:NSWindowAbove relativeTo:self.results];
	[self addSubview:self.status positioned:NSWindowAbove relativeTo:self.findBar];
	if (_dropOverlay.superview == self) {
		_dropOverlay.frame = bounds;
		[self addSubview:_dropOverlay positioned:NSWindowAbove relativeTo:nil];
	}
	for (NSView *view in self.subviews) {
		if ([view.identifier isEqualToString:@"npp.minimapZoom"] && !view.hidden) {
			[self addSubview:view positioned:NSWindowAbove relativeTo:nil];
			break;
		}
	}
	_layingOut = NO;
}
@end

static const CGFloat kSplitDivider = 5;
static const CGFloat kPaneHeader = 30;
static const int kCompareMarker = 25;

@class NppPaneTabBar;

@interface AppDelegate (EditorSplit)
- (void)splitHostDidActivatePane:(NSInteger)pane;
- (void)splitHostDidFinishResize;
@end

@interface NppSplitPreview : NSView
@property (nonatomic, copy) NSString *label;
@end

@interface NppPaneSlot : NSView
@property (nonatomic, assign) NSInteger paneIndex;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL activePane;
@property (nonatomic, strong) NppPaneTabBar *tabBar;
@property (nonatomic, assign) NSInteger splitDropSide;
- (NSRect)editorRect;
- (void)layoutContents;
- (void)removeEditorViews;
- (void)showSplitPreview:(NSInteger)side;
- (void)clearSplitPreview;
@end

@interface NppSplitHost : NSView
@property (nonatomic, weak) AppDelegate *owner;
@property (nonatomic, assign) NSInteger activePane;
- (void)setPaneCount:(NSInteger)count;
- (NSInteger)paneCount;
- (NSView *)slotAtIndex:(NSInteger)index;
- (void)setFractions:(NSArray<NSNumber *> *)fractions;
- (NSArray<NSNumber *> *)fractions;
- (NSInteger)paneContainingView:(NSView *)view;
@end

@interface NppPaneTabBar : NSView <NSDraggingDestination>
@property (nonatomic, weak) AppDelegate *owner;
@property (nonatomic, assign) NSInteger paneIndex;
@property (nonatomic, assign) NSInteger dropIndex;
@property (nonatomic, assign) CGFloat scrollOffset;
@property (nonatomic, assign) CGFloat contentWidth;
@property (nonatomic, weak) DocumentTab *anchoredDocument;
- (void)noteContentWidth:(CGFloat)width;
- (void)revealDocument:(DocumentTab *)document;
@end

@implementation NppSplitPreview
- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		self.wantsLayer = YES;
		self.layer.backgroundColor = [NSColor.controlAccentColor colorWithAlphaComponent:0.20].CGColor;
		self.layer.borderWidth = 2;
		self.layer.borderColor = NSColor.controlAccentColor.CGColor;
	}
	return self;
}
- (NSView *)hitTest:(NSPoint)point {
	(void)point;
	return nil;
}
- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	NSString *text = self.label ?: @"";
	NSDictionary *attributes = @{
		NSFontAttributeName: [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold],
		NSForegroundColorAttributeName: NSColor.labelColor
	};
	NSSize size = [text sizeWithAttributes:attributes];
	NSRect textRect = NSMakeRect(NSMidX(self.bounds) - size.width / 2, NSMidY(self.bounds) - size.height / 2, size.width, size.height);
	[text drawInRect:textRect withAttributes:attributes];
}
@end

@implementation NppPaneTabBar
- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_dropIndex = -1;
		[self registerForDraggedTypes:@[NppTabDragType]];
	}
	return self;
}
- (NSInteger)insertionIndexAtPoint:(NSPoint)point {
	NSInteger index = 0;
	for (NSView *view in self.subviews) {
		if (![view isKindOfClass:[NppTabChip class]]) {
			continue;
		}
		if (point.x > NSMidX(view.frame)) {
			index++;
		}
	}
	return index;
}
- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	if (self.dropIndex < 0) {
		return;
	}
	CGFloat x = 4;
	NSInteger seen = 0;
	for (NSView *view in self.subviews) {
		if (![view isKindOfClass:[NppTabChip class]]) {
			continue;
		}
		if (seen == self.dropIndex) {
			x = NSMinX(view.frame) - 2;
			break;
		}
		x = NSMaxX(view.frame) + 2;
		seen++;
	}
	[NSColor.controlAccentColor setFill];
	NSRectFill(NSMakeRect(x, 4, 2, MAX(8, self.bounds.size.height - 8)));
}
- (NppPaneSlot *)paneSlot {
	return [self.superview isKindOfClass:[NppPaneSlot class]] ? (NppPaneSlot *)self.superview : nil;
}
- (BOOL)offerSplitForDocument:(DocumentTab *)document atPoint:(NSPoint)point {
	CGFloat chipsMin = CGFLOAT_MAX;
	CGFloat chipsMax = -1;
	BOOL overChip = NO;
	for (NSView *view in self.subviews) {
		if (![view isKindOfClass:[NppTabChip class]]) {
			continue;
		}
		chipsMin = MIN(chipsMin, NSMinX(view.frame));
		chipsMax = MAX(chipsMax, NSMaxX(view.frame));
		if (NSPointInRect(point, NSInsetRect(view.frame, -2, 0))) {
			overChip = YES;
		}
	}
	BOOL besideChips = chipsMax >= 0 && !overChip && (point.x < chipsMin - 8 || point.x > chipsMax + 28);
	if (!besideChips) {
		return NO;
	}
	BOOL onRight = point.x > chipsMax;
	if (![self.owner canSplitDocument:document besidePane:self.paneIndex onRight:onRight]) {
		return NO;
	}
	self.dropIndex = -1;
	[self.paneSlot showSplitPreview:onRight ? 1 : -1];
	[self setNeedsDisplay:YES];
	return YES;
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	return [self draggingUpdated:sender];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	DocumentTab *document = [self.owner draggedTabDocument];
	if (!document) {
		return NSDragOperationNone;
	}
	NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
	if ([self offerSplitForDocument:document atPoint:point]) {
		return NSDragOperationMove;
	}
	[self.paneSlot clearSplitPreview];
	self.dropIndex = [self insertionIndexAtPoint:point];
	[self setNeedsDisplay:YES];
	return NSDragOperationMove;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
	(void)sender;
	self.dropIndex = -1;
	[self.paneSlot clearSplitPreview];
	[self setNeedsDisplay:YES];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	return [self.owner draggedTabDocument] != nil;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	DocumentTab *document = [self.owner draggedTabDocument];
	NppPaneSlot *slot = self.paneSlot;
	BOOL split = slot.splitDropSide != 0;
	BOOL onRight = slot.splitDropSide > 0;
	NSInteger index = self.dropIndex < 0 ? [self insertionIndexAtPoint:[self convertPoint:sender.draggingLocation fromView:nil]] : self.dropIndex;
	self.dropIndex = -1;
	[slot clearSplitPreview];
	[self setNeedsDisplay:YES];
	if (!document) {
		return NO;
	}
	if (split) {
		return [self.owner splitDocument:document besidePane:self.paneIndex onRight:onRight];
	}
	[self.owner moveDocument:document toPane:self.paneIndex atIndex:index];
	return YES;
}
- (void)setScrollOffset:(CGFloat)offset {
	CGFloat maxOffset = MAX(0, _contentWidth - NSWidth(self.bounds));
	offset = MIN(MAX(0, offset), maxOffset);
	CGFloat delta = _scrollOffset - offset;
	_scrollOffset = offset;
	if (fabs(delta) < 0.01) {
		return;
	}
	for (NSView *view in self.subviews) {
		if (![view isKindOfClass:[NppTabChip class]]) {
			continue;
		}
		NSRect frame = view.frame;
		frame.origin.x += delta;
		view.frame = frame;
	}
	[self setNeedsDisplay:YES];
}
- (void)noteContentWidth:(CGFloat)width {
	_contentWidth = width;
	CGFloat saved = _scrollOffset;
	_scrollOffset = 0;
	[self setScrollOffset:saved];
}
- (void)revealDocument:(DocumentTab *)document {
	if (!document) {
		return;
	}
	NppTabChip *chip = nil;
	for (NSView *view in self.subviews) {
		if ([view isKindOfClass:[NppTabChip class]] && ((NppTabChip *)view).document == document) {
			chip = (NppTabChip *)view;
			break;
		}
	}
	if (!chip) {
		return;
	}
	CGFloat visible = NSWidth(self.bounds);
	CGFloat left = NSMinX(chip.frame);
	CGFloat right = NSMaxX(chip.frame);
	CGFloat adjust = 0;
	if (left < 4) {
		adjust = left - 4;
	} else if (right > visible - 4) {
		adjust = right - (visible - 4);
	}
	if (fabs(adjust) >= 1) {
		[self setScrollOffset:_scrollOffset + adjust];
	}
}
- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	[self setScrollOffset:_scrollOffset];
}
- (void)scrollWheel:(NSEvent *)event {
	CGFloat delta = event.scrollingDeltaX;
	if (fabs(delta) < fabs(event.scrollingDeltaY)) {
		delta = event.scrollingDeltaY;
	}
	if (!event.hasPreciseScrollingDeltas) {
		delta *= 16;
	}
	if (fabs(delta) < 0.01 || _contentWidth <= NSWidth(self.bounds) + 1) {
		return;
	}
	[self setScrollOffset:_scrollOffset - delta];
}
@end

@implementation NppPaneSlot {
	NppSplitPreview *_splitPreview;
	BOOL _updatingSplitPreview;
}
- (CGFloat)headerHeight {
	return kPaneHeader;
}
- (NSRect)editorRect {
	NSRect bounds = self.bounds;
	return NSMakeRect(0, 0, bounds.size.width, MAX(1, bounds.size.height - self.headerHeight));
}
- (void)layoutContents {
	CGFloat header = self.headerHeight;
	self.tabBar.frame = NSMakeRect(0, NSHeight(self.bounds) - header + 2, NSWidth(self.bounds), MAX(0, header - 2));
	NSRect editorRect = self.editorRect;
	NSView *minimap = nil;
	NSView *preview = nil;
	NSView *csvBar = nil;
	NSMutableArray<NSView *> *editors = [NSMutableArray array];
	for (NSView *subview in self.subviews) {
		if (subview == self.tabBar || subview == _splitPreview) {
			continue;
		}
		if ([subview.identifier isEqualToString:@"npp.minimap"]) {
			minimap = subview;
		} else if ([subview.identifier isEqualToString:@"npp.preview"]) {
			preview = subview;
		} else if ([subview.identifier isEqualToString:@"npp.minimapZoom"]) {
			continue;
		} else if ([subview.identifier isEqualToString:@"npp.csv.bar"]) {
			csvBar = subview;
		} else {
			[editors addObject:subview];
		}
	}
	CGFloat mini = (minimap && !minimap.hidden) ? 64 : 0;
	CGFloat previewWidth = (preview && !preview.hidden) ? floor(editorRect.size.width * 0.42) : 0;
	CGFloat editorsWidth = MAX(1, editorRect.size.width - mini - previewWidth);
	CGFloat csvBarHeight = csvBar ? 32 : 0;
	for (NSView *editor in editors) {
		editor.frame = NSMakeRect(editorRect.origin.x, editorRect.origin.y, editorsWidth, MAX(1, editorRect.size.height - csvBarHeight));
	}
	if (csvBar) {
		csvBar.frame = NSMakeRect(editorRect.origin.x, NSMaxY(editorRect) - csvBarHeight, editorsWidth, csvBarHeight);
		NSButton *button = [csvBar viewWithTag:1];
		button.title = NppL(@"As Table");
		[button sizeToFit];
		button.frame = NSMakeRect(8, 4, MAX(108, ceil(NSWidth(button.frame)) + 16), 24);
		NSTextField *hint = [csvBar viewWithTag:2];
		hint.stringValue = NppL(@"This CSV is open as text.");
		hint.frame = NSMakeRect(NSMaxX(button.frame) + 8, 7, MAX(40, NSWidth(csvBar.bounds) - NSMaxX(button.frame) - 16), 18);
	}
	if (preview && !preview.hidden) {
		preview.frame = NSMakeRect(editorRect.origin.x + editorsWidth, editorRect.origin.y, previewWidth, editorRect.size.height);
	}
	if (minimap && !minimap.hidden) {
		minimap.frame = NSMakeRect(NSMaxX(editorRect) - mini, editorRect.origin.y, mini, editorRect.size.height);
	}
	if (self.splitDropSide != 0 && !_updatingSplitPreview) {
		_updatingSplitPreview = YES;
		[self showSplitPreview:self.splitDropSide];
		_updatingSplitPreview = NO;
	}
}
- (void)removeEditorViews {
	for (NSView *subview in self.subviews.copy) {
		if (subview == self.tabBar || subview == _splitPreview || [subview.identifier isEqualToString:@"npp.minimap"] || [subview.identifier isEqualToString:@"npp.minimapZoom"] || [subview.identifier isEqualToString:@"npp.preview"]) {
			continue;
		}
		[subview removeFromSuperview];
	}
}
- (void)clearSplitPreview {
	self.splitDropSide = 0;
	[_splitPreview removeFromSuperview];
}
- (void)showSplitPreview:(NSInteger)side {
	if (side == 0) {
		[self clearSplitPreview];
		return;
	}
	self.splitDropSide = side;
	if (!_splitPreview) {
		_splitPreview = [[NppSplitPreview alloc] initWithFrame:NSZeroRect];
	}
	NSRect editor = self.editorRect;
	CGFloat width = MAX(80, floor(editor.size.width * 0.5));
	if (side < 0) {
		_splitPreview.frame = NSMakeRect(editor.origin.x, editor.origin.y, MIN(width, editor.size.width), editor.size.height);
		_splitPreview.label = @"Split left";
	} else {
		CGFloat previewWidth = MIN(width, editor.size.width);
		_splitPreview.frame = NSMakeRect(NSMaxX(editor) - previewWidth, editor.origin.y, previewWidth, editor.size.height);
		_splitPreview.label = @"Split right";
	}
	if (_splitPreview.superview != self) {
		[self addSubview:_splitPreview positioned:NSWindowBelow relativeTo:self.tabBar];
	}
	[_splitPreview setNeedsDisplay:YES];
}
- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	[self layoutContents];
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	[NSColor.textBackgroundColor setFill];
	NSRectFill(self.bounds);
	CGFloat headerHeight = self.headerHeight;
	if (headerHeight <= 0) {
		return;
	}
	NSRect bounds = self.bounds;
	NSRect header = NSMakeRect(0, bounds.size.height - headerHeight, bounds.size.width, headerHeight);
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(header);
	if (self.activePane) {
		[NSColor.controlAccentColor setFill];
		NSRectFill(NSMakeRect(0, header.origin.y, bounds.size.width, 2));
	} else {
		[NSColor.separatorColor setFill];
		NSRectFill(NSMakeRect(0, header.origin.y, bounds.size.width, 1));
	}
}
- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	if (point.y < self.bounds.size.height - self.headerHeight) {
		[super mouseDown:event];
		return;
	}
	NppSplitHost *host = (NppSplitHost *)self.superview;
	if ([host isKindOfClass:[NppSplitHost class]]) {
		[host.owner splitHostDidActivatePane:self.paneIndex];
	}
}
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	return [self draggingUpdated:sender];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	DocumentTab *document = [self.tabBar.owner draggedTabDocument];
	if (!document) {
		[self clearSplitPreview];
		return NSDragOperationNone;
	}
	NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
	NSRect editor = self.editorRect;
	if (editor.size.width > 1 && point.y <= NSMaxY(editor)) {
		CGFloat rel = (point.x - editor.origin.x) / editor.size.width;
		if (rel <= 0.45 || rel >= 0.55) {
			BOOL onRight = rel >= 0.55;
			if ([self.tabBar.owner canSplitDocument:document besidePane:self.paneIndex onRight:onRight]) {
				self.tabBar.dropIndex = -1;
				[self.tabBar setNeedsDisplay:YES];
				[self showSplitPreview:onRight ? 1 : -1];
				(void)sender;
				return NSDragOperationMove;
			}
		}
	}
	[self clearSplitPreview];
	NSInteger chips = 0;
	for (NSView *view in self.tabBar.subviews) {
		if ([view isKindOfClass:[NppTabChip class]]) {
			chips++;
		}
	}
	self.tabBar.dropIndex = chips;
	[self.tabBar setNeedsDisplay:YES];
	(void)sender;
	return NSDragOperationMove;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
	(void)sender;
	self.tabBar.dropIndex = -1;
	[self clearSplitPreview];
	[self.tabBar setNeedsDisplay:YES];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	return [self.tabBar.owner draggedTabDocument] != nil;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	DocumentTab *document = [self.tabBar.owner draggedTabDocument];
	BOOL split = self.splitDropSide != 0;
	BOOL onRight = self.splitDropSide > 0;
	NSInteger index = self.tabBar.dropIndex < 0 ? 0 : self.tabBar.dropIndex;
	self.tabBar.dropIndex = -1;
	[self clearSplitPreview];
	if (!document) {
		return NO;
	}
	if (split) {
		return [self.tabBar.owner splitDocument:document besidePane:self.paneIndex onRight:onRight];
	}
	[self.tabBar.owner moveDocument:document toPane:self.paneIndex atIndex:index];
	return YES;
}
@end

@implementation NppSplitHost {
	NSMutableArray<NppPaneSlot *> *_slots;
	NSMutableArray<NSNumber *> *_fractions;
	NSMutableArray<NSValue *> *_dividers;
	NSInteger _dragDivider;
	CGFloat _dragAnchor;
	CGFloat _dragLeft;
	CGFloat _dragRight;
}
- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_slots = [NSMutableArray array];
		_fractions = [NSMutableArray arrayWithObject:@1];
		_dividers = [NSMutableArray array];
		_dragDivider = -1;
		self.activePane = 0;
	}
	return self;
}
- (NSInteger)paneCount {
	return (NSInteger)_slots.count;
}
- (NSView *)slotAtIndex:(NSInteger)index {
	if (index < 0 || index >= (NSInteger)_slots.count) {
		return nil;
	}
	return _slots[index];
}
- (NSArray<NSNumber *> *)fractions {
	return [_fractions copy];
}
- (void)setFractions:(NSArray<NSNumber *> *)fractions {
	if (fractions.count != _slots.count || fractions.count == 0) {
		return;
	}
	CGFloat sum = 0;
	for (NSNumber *number in fractions) {
		sum += MAX(0.05, number.doubleValue);
	}
	_fractions = [NSMutableArray array];
	for (NSNumber *number in fractions) {
		[_fractions addObject:@(MAX(0.05, number.doubleValue) / sum)];
	}
	[self layoutSlots];
}
- (void)setPaneCount:(NSInteger)count {
	count = MAX(1, MIN(6, count));
	while ((NSInteger)_slots.count < count) {
		NppPaneSlot *slot = [[NppPaneSlot alloc] initWithFrame:NSZeroRect];
		slot.paneIndex = (NSInteger)_slots.count;
		slot.wantsLayer = YES;
		NppPaneTabBar *bar = [[NppPaneTabBar alloc] initWithFrame:NSZeroRect];
		bar.owner = self.owner;
		bar.paneIndex = slot.paneIndex;
		slot.tabBar = bar;
		[slot addSubview:bar];
		[slot registerForDraggedTypes:@[NppTabDragType]];
		[_slots addObject:slot];
		[self addSubview:slot];
	}
	while ((NSInteger)_slots.count > count) {
		NppPaneSlot *slot = _slots.lastObject;
		[slot removeFromSuperview];
		[_slots removeLastObject];
	}
	for (NSInteger index = 0; index < (NSInteger)_slots.count; index++) {
		_slots[index].paneIndex = index;
		_slots[index].tabBar.paneIndex = index;
		_slots[index].tabBar.owner = self.owner;
	}
	if ((NSInteger)_fractions.count != count) {
		CGFloat share = 1.0 / count;
		_fractions = [NSMutableArray array];
		for (NSInteger index = 0; index < count; index++) {
			[_fractions addObject:@(share)];
		}
	}
	if (self.activePane >= count) {
		self.activePane = count - 1;
	}
	[self layoutSlots];
}
- (void)setActivePane:(NSInteger)activePane {
	_activePane = activePane;
	[self layoutSlots];
}
- (NSInteger)paneContainingView:(NSView *)view {
	while (view) {
		if ([view isKindOfClass:[NppPaneSlot class]]) {
			return ((NppPaneSlot *)view).paneIndex;
		}
		view = view.superview;
	}
	return NSNotFound;
}
- (void)layoutSlots {
	NSInteger count = (NSInteger)_slots.count;
	if (count == 0) {
		return;
	}
	[_dividers removeAllObjects];
	CGFloat width = self.bounds.size.width;
	CGFloat height = self.bounds.size.height;
	CGFloat gaps = kSplitDivider * MAX(0, count - 1);
	CGFloat usable = MAX(1, width - gaps);
	CGFloat x = 0;
	for (NSInteger index = 0; index < count; index++) {
		CGFloat paneWidth = (index == count - 1) ? MAX(1, width - x) : floor(usable * _fractions[index].doubleValue);
		NppPaneSlot *slot = _slots[index];
		slot.frame = NSMakeRect(x, 0, paneWidth, height);
		slot.clipsToBounds = YES;
		slot.wantsLayer = YES;
		slot.layer.masksToBounds = YES;
		slot.layer.borderWidth = 0;
		slot.activePane = index == self.activePane;
		x += paneWidth;
		if (index + 1 < count) {
			[_dividers addObject:[NSValue valueWithRect:NSMakeRect(x, 0, kSplitDivider, height)]];
			x += kSplitDivider;
		}
	}
	[self resetCursorRects];
	[self setNeedsDisplay:YES];
}
- (void)drawRect:(NSRect)dirtyRect {
	[NSColor.textBackgroundColor setFill];
	NSRectFill(dirtyRect);
	[NSColor.separatorColor setFill];
	for (NSValue *value in _dividers) {
		NSRect rect = value.rectValue;
		NSRectFill(NSMakeRect(floor(NSMidX(rect)), 0, 1, rect.size.height));
	}
}
- (void)setFrameSize:(NSSize)newSize {
	[super setFrameSize:newSize];
	[self layoutSlots];
}
- (NSInteger)dividerAtPoint:(NSPoint)point {
	for (NSInteger index = 0; index < (NSInteger)_dividers.count; index++) {
		NSRect rect = NSInsetRect(_dividers[index].rectValue, -2, 0);
		if (NSPointInRect(point, rect)) {
			return index;
		}
	}
	return -1;
}
- (void)resetCursorRects {
	[self discardCursorRects];
	NSCursor *cursor = [NSCursor resizeLeftRightCursor];
	for (NSValue *value in _dividers) {
		[self addCursorRect:value.rectValue cursor:cursor];
	}
}
- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	_dragDivider = [self dividerAtPoint:point];
	if (_dragDivider < 0 || _dragDivider + 1 >= (NSInteger)_fractions.count) {
		return;
	}
	_dragAnchor = point.x;
	_dragLeft = _fractions[_dragDivider].doubleValue;
	_dragRight = _fractions[_dragDivider + 1].doubleValue;
}
- (void)mouseDragged:(NSEvent *)event {
	if (_dragDivider < 0) {
		return;
	}
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	CGFloat usable = MAX(1, self.bounds.size.width - kSplitDivider * MAX(0, (NSInteger)_slots.count - 1));
	CGFloat delta = (point.x - _dragAnchor) / usable;
	CGFloat left = _dragLeft + delta;
	CGFloat right = _dragRight - delta;
	CGFloat minimum = MIN(0.2, 80.0 / usable);
	CGFloat pair = _dragLeft + _dragRight;
	if (pair <= minimum * 2) {
		return;
	}
	if (left < minimum) {
		left = minimum;
		right = pair - minimum;
	} else if (right < minimum) {
		right = minimum;
		left = pair - minimum;
	}
	_fractions[_dragDivider] = @(left);
	_fractions[_dragDivider + 1] = @(right);
	[self layoutSlots];
}
- (void)mouseUp:(NSEvent *)event {
	(void)event;
	if (_dragDivider < 0) {
		return;
	}
	_dragDivider = -1;
	[self.owner splitHostDidFinishResize];
}
@end

@interface AppDelegate (SearchChrome)
- (void)layoutFindBar;
- (void)layoutResultsPanel;
@end

@interface NppChromeView : NSView
@property (nonatomic, weak) AppDelegate *owner;
@property (nonatomic, assign) BOOL resultsChrome;
@end

@implementation NppChromeView
- (instancetype)initWithFrame:(NSRect)frame {
	self = [super initWithFrame:frame];
	if (self) {
		self.wantsLayer = YES;
		self.layer.masksToBounds = YES;
	}
	return self;
}
- (void)drawRect:(NSRect)dirtyRect {
	[[NSColor windowBackgroundColor] setFill];
	NSRectFill(dirtyRect);
}
- (BOOL)isOpaque {
	return YES;
}
- (void)resizeSubviewsWithOldSize:(NSSize)oldSize {
	(void)oldSize;
	if (self.resultsChrome) {
		[self.owner layoutResultsPanel];
	} else {
		[self.owner layoutFindBar];
	}
}
@end

static NSArray<NSDictionary *> *NppDiffLines(NSArray<NSString *> *left, NSArray<NSString *> *right) {
	NSInteger prefix = 0;
	while (prefix < (NSInteger)left.count && prefix < (NSInteger)right.count && [left[prefix] isEqualToString:right[prefix]]) {
		prefix++;
	}
	NSInteger suffix = 0;
	while (suffix < (NSInteger)left.count - prefix && suffix < (NSInteger)right.count - prefix && [left[left.count - 1 - suffix] isEqualToString:right[right.count - 1 - suffix]]) {
		suffix++;
	}
	NSArray<NSString *> *a = [left subarrayWithRange:NSMakeRange((NSUInteger)prefix, left.count - (NSUInteger)prefix - (NSUInteger)suffix)];
	NSArray<NSString *> *b = [right subarrayWithRange:NSMakeRange((NSUInteger)prefix, right.count - (NSUInteger)prefix - (NSUInteger)suffix)];
	NSMutableArray<NSDictionary *> *changes = [NSMutableArray array];
	if (a.count > 400 || b.count > 400) {
		for (NSInteger index = 0; index < (NSInteger)a.count && changes.count < 800; index++) {
			[changes addObject:@{@"side": @"-", @"line": @(prefix + index + 1), @"text": a[index]}];
		}
		for (NSInteger index = 0; index < (NSInteger)b.count && changes.count < 800; index++) {
			[changes addObject:@{@"side": @"+", @"line": @(prefix + index + 1), @"text": b[index]}];
		}
		return changes;
	}
	NSInteger n = (NSInteger)a.count;
	NSInteger m = (NSInteger)b.count;
	NSMutableData *table = [NSMutableData dataWithLength:(NSUInteger)((n + 1) * (m + 1) * (NSInteger)sizeof(int))];
	int *dp = (int *)table.mutableBytes;
	for (NSInteger i = 1; i <= n; i++) {
		for (NSInteger j = 1; j <= m; j++) {
			if ([a[i - 1] isEqualToString:b[j - 1]]) {
				dp[i * (m + 1) + j] = dp[(i - 1) * (m + 1) + (j - 1)] + 1;
			} else {
				int up = dp[(i - 1) * (m + 1) + j];
				int leftScore = dp[i * (m + 1) + (j - 1)];
				dp[i * (m + 1) + j] = up > leftScore ? up : leftScore;
			}
		}
	}
	NSMutableArray<NSDictionary *> *reversed = [NSMutableArray array];
	NSInteger i = n;
	NSInteger j = m;
	while (i > 0 && j > 0) {
		if ([a[i - 1] isEqualToString:b[j - 1]]) {
			i--;
			j--;
		} else if (dp[(i - 1) * (m + 1) + j] >= dp[i * (m + 1) + (j - 1)]) {
			[reversed addObject:@{@"side": @"-", @"line": @(prefix + i), @"text": a[i - 1]}];
			i--;
		} else {
			[reversed addObject:@{@"side": @"+", @"line": @(prefix + j), @"text": b[j - 1]}];
			j--;
		}
	}
	while (i > 0) {
		[reversed addObject:@{@"side": @"-", @"line": @(prefix + i), @"text": a[i - 1]}];
		i--;
	}
	while (j > 0) {
		[reversed addObject:@{@"side": @"+", @"line": @(prefix + j), @"text": b[j - 1]}];
		j--;
	}
	for (NSDictionary *change in reversed.reverseObjectEnumerator) {
		[changes addObject:change];
	}
	return changes;
}

@interface NppFolderNode : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, assign) BOOL directory;
@property (nonatomic, strong) NSImage *icon;
@property (nonatomic, strong) NSMutableArray<NppFolderNode *> *children;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation NppFolderNode
@end

@interface NppFolderCell : NSTableCellView
@end

@implementation NppFolderCell
- (void)layout {
	[super layout];
	CGFloat height = NSHeight(self.bounds);
	self.imageView.frame = NSMakeRect(2, floor((height - 16) / 2.0), 16, 16);
	self.textField.frame = NSMakeRect(22, 0, MAX(0, NSWidth(self.bounds) - 28), height);
}
@end

@implementation AppDelegate {
	NSWindow *_window;
	WorkspaceView *_workspace;
	NSView *_menuBar;
	NSView *_toolbar;
	NSView *_tabStrip;
	NSTabView *_tabs;
	NppSplitHost *_splitHost;
	NSMutableArray *_paneDocuments;
	NSMutableArray *_paneTabs;
	DocumentTab *_draggedDocument;
	NSInteger _activePane;
	BOOL _syncingPane;
	NSView *_resultsPanel;
	NSTableView *_resultsTable;
	NSScrollView *_resultsScroll;
	NSMutableArray<NppFindHit *> *_hits;
	NSTextField *_filesQuery;
	NSTextField *_filesReplace;
	NSTextField *_filesDirectory;
	NSTextField *_filesFilters;
	NSButton *_filesCase;
	NSButton *_filesWord;
	NSButton *_filesRegex;
	NSButton *_filesSubfolders;
	NSProgressIndicator *_findProgress;
	NSTextField *_findProgressLabel;
	NSButton *_findCancel;
	NppFindScanToken *_findToken;
	NSTextField *_status;
	NSButton *_tailButton;
	NSView *_sidebar;
	NSOutlineView *_folderOutline;
	NSString *_folderRoot;
	NppFolderNode *_folderRootNode;
	NSSearchField *_folderFindField;
	NSString *_folderQuery;
	NSArray<NppFolderNode *> *_folderMatches;
	NSInteger _folderSearchGeneration;
	NSTextView *_preferencesShortcuts;
	NSWindow *_preferencesWindow;
	BOOL _captureShortcut;
	NSWindow *_characterPanel;
	NSWindow *_quickOpenPanel;
	NSSearchField *_quickOpenField;
	NSTableView *_quickOpenTable;
	NSArray *_quickOpenRows;
	BOOL _syncingScroll;
	BOOL _closingWithoutPrompt;
	BOOL _discardUnsavedSession;
	NSView *_compareBar;
	NSTextField *_compareLabel;
	DocumentTab *_compareLeft;
	DocumentTab *_compareRight;
	NSArray<NSDictionary *> *_compareRows;
	NSInteger _compareIndex;
	NSTextField *_findField;
	NSTextField *_replaceField;
	NSButton *_matchCase;
	NSButton *_wholeWord;
	NSButton *_regex;
	NSButton *_wrap;
	NSButton *_dotAll;
	LangCatalog *_catalog;
	EditorSettings *_settings;
	MacroStore *_macro;
	NSMutableArray<DocumentTab *> *_documents;
	NSMapTable<DocumentTab *, NppOfficeRef *> *_office;
	NSMutableArray<NSString *> *_pendingOpenPaths;
	NSInteger _untitled;
	NSTimer *_recoveryTimer;
	NSTimer *_fileWatchTimer;
	BOOL _showingReloadPrompt;
	BOOL _hasSavedWindowFrame;
	NSRect _savedWindowFrame;
	NppMacHost _host;
	NSMutableArray<NSDictionary *> *_plugins;
	NSMutableArray<NSString *> *_pluginErrors;
	NSString *_statusOverride;
	NSTableView *_outlineTable;
	NSArray<NppSymbol *> *_outlineRows;
	NSInteger _sidebarPage;
	WKWebView *_preview;
	BOOL _previewVisible;
	NppSnippetStore *_snippets;
	NppClipboardHistory *_clips;
	NppUserLanguageStore *_userLanguages;
	DocumentTab *_cloneSource;
	NSInteger _clonePane;
	NSMutableArray<NSMutableDictionary *> *_shortcutRows;
	NSTableView *_shortcutTable;
	NSWindow *_clipboardWindow;
	NSTableView *_clipboardTable;
	NSWindow *_snippetWindow;
	NSTableView *_snippetTable;
	NSWindow *_languageWindow;
	NSTableView *_languageTable;
	BOOL _suppressEmptyDocument;
	NSPanel *_zoomPanel;
	NppMinimapZoom *_zoomCard;
	__weak NppMinimapView *_zoomMap;
	id _zoomClickMonitor;
	NSInteger _zoomHideGeneration;
	CGFloat _cmdZoomAccum;
}

static AppDelegate *HostApp(NppMacHost *host) {
	return (__bridge AppDelegate *)host->ctx;
}

static int HostGetSelection(NppMacHost *host, char *buffer, int bufferLength) {
	NSString *text = [HostApp(host) selectedText] ?: @"";
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	if (!buffer || bufferLength <= 0) {
		return (int)data.length;
	}
	int count = (int)MIN((NSInteger)data.length, (NSInteger)bufferLength - 1);
	memcpy(buffer, data.bytes, (size_t)count);
	buffer[count] = 0;
	return count;
}

static void HostReplace(NppMacHost *host, const char *utf8) {
	[HostApp(host) replaceSelection:utf8 ? @(utf8) : @""];
}

static void HostInsert(NppMacHost *host, const char *utf8) {
	[HostApp(host) insertText:utf8 ? @(utf8) : @""];
}

static int HostGetText(NppMacHost *host, char *buffer, int bufferLength) {
	NSString *text = [[HostApp(host) currentDocument] utf8Text] ?: @"";
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
	if (!buffer || bufferLength <= 0) {
		return (int)data.length;
	}
	int count = (int)MIN((NSInteger)data.length, (NSInteger)bufferLength - 1);
	if (data.bytes && count > 0) {
		memcpy(buffer, data.bytes, (size_t)count);
	}
	buffer[count] = 0;
	return count;
}

static void HostSetText(NppMacHost *host, const char *utf8) {
	[HostApp(host) replaceDocumentText:utf8 ? @(utf8) : @""];
}

static void DisableKeyEquivalentSearch(NSMenu *menu) {
	if (!menu) {
		return;
	}
	SEL setter = NSSelectorFromString(@"setAllowsKeyEquivalentSearch:");
	if ([menu respondsToSelector:setter]) {
		NSMethodSignature *signature = [menu methodSignatureForSelector:setter];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
		invocation.target = menu;
		invocation.selector = setter;
		BOOL allowed = NO;
		[invocation setArgument:&allowed atIndex:2];
		[invocation invoke];
	}
	for (NSMenuItem *item in menu.itemArray) {
		if (item.submenu) {
			DisableKeyEquivalentSearch(item.submenu);
		}
	}
}

static const char *HostPath(NppMacHost *host) {
	return [HostApp(host) currentDocument].path.UTF8String;
}

static void HostStatus(NppMacHost *host, const char *text) {
	[HostApp(host) setStatusText:text ? @(text) : @""];
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification {
	(void)notification;
	_documents = [NSMutableArray array];
	_office = [NSMapTable weakToStrongObjectsMapTable];
	_clonePane = NSNotFound;
	_snippets = [NppSnippetStore loadFromURL:[SupportDirectory() URLByAppendingPathComponent:@"snippets.json"]];
	_clips = [NppClipboardHistory new];
	_userLanguages = [NppUserLanguageStore loadFromURL:[SupportDirectory() URLByAppendingPathComponent:@"languages.json"]];
	_plugins = [NSMutableArray array];
	_pluginErrors = [NSMutableArray array];
	_macro = [MacroStore new];
	_settings = [EditorSettings loadFromURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"]];
	NppSetUILanguage(_settings.uiLanguage);
	NSError *error = nil;
	[_macro loadFromURL:[SupportDirectory() URLByAppendingPathComponent:@"macro.json"] error:&error];
	NSString *langs = [NSBundle.mainBundle pathForResource:@"langs.model" ofType:@"xml"];
	_catalog = [LangCatalog catalogWithXML:langs];
	_host = {
		.abi = NPP_MAC_PLUGIN_ABI,
		.ctx = (__bridge void *)self,
		.get_selection = HostGetSelection,
		.replace_selection = HostReplace,
		.insert_text = HostInsert,
		.current_path = HostPath,
		.set_status = HostStatus,
		.get_text = HostGetText,
		.set_text = HostSetText
	};
	[self buildWindow];
	[self buildMenus];
	[self loadPlugins];
	[self buildMenus];
	BOOL opened = [self openArguments];
	if (_pendingOpenPaths.count > 0) {
		NSArray<NSString *> *pending = [_pendingOpenPaths copy];
		[_pendingOpenPaths removeAllObjects];
		if ([self openDroppedPaths:pending]) {
			opened = YES;
		}
	}
	if (!opened) {
		if (![self restoreSession]) {
			[self offerRecovery];
		}
	}
	if (_documents.count == 0) {
		[self newDocument:nil];
	}
	[self showEditorWindow];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self showEditorWindow];
	});
	_recoveryTimer = [NSTimer scheduledTimerWithTimeInterval:30 target:self selector:@selector(writeRecovery) userInfo:nil repeats:YES];
	_fileWatchTimer = [NSTimer scheduledTimerWithTimeInterval:2 target:self selector:@selector(checkExternalChanges) userInfo:nil repeats:YES];
	[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskKeyDown handler:^NSEvent *(NSEvent *event) {
		return [self handleEditorHotkey:event];
	}];
	[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskScrollWheel handler:^NSEvent *(NSEvent *event) {
		return [self handleCommandZoom:event];
	}];
	[NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
		return [self handleExtraCaretClick:event];
	}];
}

- (BOOL)editorIsFirstResponder {
	NSResponder *responder = _window.firstResponder;
	while (responder) {
		if ([responder isKindOfClass:[ScintillaView class]] || [NSStringFromClass(responder.class) isEqualToString:@"SCIContentView"]) {
			return YES;
		}
		responder = responder.nextResponder;
	}
	return NO;
}

- (NSMenuItem *)menuItemForCharacters:(NSString *)characters modifiers:(NSEventModifierFlags)modifiers inMenu:(NSMenu *)menu {
	BOOL shift = (modifiers & NSEventModifierFlagShift) != 0;
	NSEventModifierFlags others = modifiers & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
	for (NSMenuItem *item in menu.itemArray) {
		if (item.submenu) {
			NSMenuItem *found = [self menuItemForCharacters:characters modifiers:modifiers inMenu:item.submenu];
			if (found) {
				return found;
			}
		}
		if (item.keyEquivalent.length == 0 || !item.action) {
			continue;
		}
		BOOL itemShift = (item.keyEquivalentModifierMask & NSEventModifierFlagShift) != 0;
		NSString *equivalent = item.keyEquivalent;
		if (equivalent.length == 1) {
			unichar value = [equivalent characterAtIndex:0];
			if ([[NSCharacterSet uppercaseLetterCharacterSet] characterIsMember:value]) {
				itemShift = YES;
			}
			equivalent = equivalent.lowercaseString;
		}
		NSEventModifierFlags itemOthers = item.keyEquivalentModifierMask & (NSEventModifierFlagCommand | NSEventModifierFlagOption | NSEventModifierFlagControl);
		if ([equivalent isEqualToString:characters] && itemShift == shift && itemOthers == others) {
			return item;
		}
	}
	return nil;
}

- (NSEvent *)handleEditorHotkey:(NSEvent *)event {
	if (_captureShortcut && event.window == _preferencesWindow) {
		NSString *spec = [EditorSettings shortcutSpecForEvent:event];
		if (spec.length) {
			NSInteger row = _shortcutTable.selectedRow;
			if (row < 0 && _shortcutRows.count) {
				row = 0;
				[_shortcutTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
			}
			if (row >= 0 && row < (NSInteger)_shortcutRows.count) {
				_shortcutRows[row][@"keys"] = spec;
				[_shortcutTable reloadData];
			}
			_captureShortcut = NO;
			NSButton *record = [_preferencesWindow.contentView viewWithTag:822];
			record.title = NppL(@"Record keys");
		}
		return nil;
	}
	if (![self editorIsFirstResponder] || _window.attachedSheet) {
		return event;
	}
	NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
	flags &= ~NSEventModifierFlagFunction;
	NSString *characters = event.charactersIgnoringModifiers.lowercaseString;
	if (characters.length == 0) {
		return event;
	}
	unichar value = [characters characterAtIndex:0];
	if (value == '\t' && flags == 0 && [self expandSnippet]) {
		return nil;
	}
	BOOL functionKey = value >= NSF1FunctionKey && value <= NSF35FunctionKey;
	BOOL commandish = (flags & (NSEventModifierFlagCommand | NSEventModifierFlagControl | NSEventModifierFlagOption)) != 0;
	if (!functionKey && !commandish) {
		return event;
	}
	NSMenuItem *item = [self menuItemForCharacters:characters modifiers:flags inMenu:NSApp.mainMenu];
	if (!item && (flags & NSEventModifierFlagControl) && !(flags & NSEventModifierFlagCommand)) {
		NSEventModifierFlags aliased = (flags & ~NSEventModifierFlagControl) | NSEventModifierFlagCommand;
		item = [self menuItemForCharacters:characters modifiers:aliased inMenu:NSApp.mainMenu];
	}
	if (item && item.enabled && item.action) {
		[NSApp sendAction:item.action to:item.target from:item];
		return nil;
	}
	BOOL command = (flags & NSEventModifierFlagCommand) != 0;
	BOOL shift = (flags & NSEventModifierFlagShift) != 0;
	BOOL option = (flags & NSEventModifierFlagOption) != 0;
	BOOL control = (flags & NSEventModifierFlagControl) != 0;
	if ((command || control) && !shift && !option && [characters isEqualToString:@"y"]) {
		[self redo:nil];
		return nil;
	}
	if (control && !command && !shift && !option && [characters isEqualToString:@"h"]) {
		[self showReplace:nil];
		return nil;
	}
	if (command && !shift && !option && !control && [characters isEqualToString:@"/"]) {
		[self editorActionWithName:@"comment"];
		return nil;
	}
	if (command && shift && !option && !control && [characters isEqualToString:@"]"]) {
		[self nextTab:nil];
		return nil;
	}
	if (command && shift && !option && !control && [characters isEqualToString:@"["]) {
		[self previousTab:nil];
		return nil;
	}
	return event;
}

- (void)editorActionWithName:(NSString *)action {
	DocumentTab *document = [self currentDocument];
	if (!document || action.length == 0) {
		return;
	}
	NppRunEditorAction([self activeEditor] ?: document.editor, action, document.lexerName ?: @"");
	[self refreshStatus];
}

- (BOOL)applicationShouldHandleReopen:(NSApplication *)sender hasVisibleWindows:(BOOL)flag {
	(void)sender;
	(void)flag;
	if (_documents.count == 0) {
		[self newDocument:nil];
	}
	[self showEditorWindow];
	return NO;
}

- (NSRect)windowWillUseStandardFrame:(NSWindow *)window defaultFrame:(NSRect)newFrame {
	(void)newFrame;
	return window.screen ? window.screen.visibleFrame : newFrame;
}

- (void)windowDidResize:(NSNotification *)notification {
	(void)notification;
	[_workspace layoutPanes];
}

- (BOOL)savedFrameIsVisible:(NSRect)frame {
	for (NSScreen *screen in [NSScreen screens]) {
		if (NSIntersectsRect(frame, screen.visibleFrame)) {
			return YES;
		}
	}
	return NO;
}

- (void)showEditorWindow {
	if (_window.miniaturized) {
		[_window deminiaturize:nil];
	}
	if (_hasSavedWindowFrame && [self savedFrameIsVisible:_savedWindowFrame]) {
		[_window setFrame:_savedWindowFrame display:YES];
	} else {
		NSScreen *screen = [NSScreen screens].firstObject;
		if (screen) {
			NSRect visible = screen.visibleFrame;
			NSRect frame = _window.frame;
			frame.size.width = MIN(MAX(frame.size.width, 640), visible.size.width);
			frame.size.height = MIN(MAX(frame.size.height, 420), visible.size.height);
			frame.origin.x = NSMidX(visible) - frame.size.width / 2.0;
			frame.origin.y = NSMidY(visible) - frame.size.height / 2.0;
			[_window setFrame:frame display:YES];
		}
	}
	[NSApp activateIgnoringOtherApps:YES];
	[_window orderFrontRegardless];
	[_window makeKeyAndOrderFront:nil];
}

- (BOOL)windowShouldClose:(NSWindow *)sender {
	(void)sender;
	if (![self confirmClosingDocuments:_documents grouped:YES]) {
		_discardUnsavedSession = NO;
		return NO;
	}
	[self saveSession];
	_discardUnsavedSession = NO;
	return YES;
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
	(void)app;
	return NO;
}

- (void)buildWindow {
	NSRect frame = NSMakeRect(0, 0, 1100, 760);
	_window = [[NSWindow alloc] initWithContentRect:frame styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
	_window.releasedWhenClosed = NO;
	_window.title = @"Simeiomatarion";
	_window.delegate = self;
	_window.minSize = NSMakeSize(640, 420);
	_window.restorable = NO;
	_window.collectionBehavior = NSWindowCollectionBehaviorMoveToActiveSpace;
	_workspace = [[WorkspaceView alloc] initWithFrame:_window.contentView.bounds];
	_workspace.dropOwner = self;
	_workspace.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
	_workspace.translatesAutoresizingMaskIntoConstraints = YES;
	_tabs = [[NSTabView alloc] initWithFrame:NSZeroRect];
	_tabs.tabViewType = NSNoTabsNoBorder;
	_tabs.delegate = (id<NSTabViewDelegate>)self;
	_splitHost = [[NppSplitHost alloc] initWithFrame:NSZeroRect];
	_splitHost.owner = self;
	[_splitHost setPaneCount:1];
	_paneDocuments = [NSMutableArray arrayWithObject:[NSNull null]];
	_paneTabs = [NSMutableArray arrayWithObject:[NSMutableArray array]];
	_activePane = 0;
	_menuBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 26)];
	_toolbar = [self buildToolbar];
	_tabStrip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 30)];
	_tabStrip.hidden = YES;
	_hits = [NSMutableArray array];
	_resultsPanel = [self buildResultsPanel];
	_status = [NSTextField labelWithString:@"Ready"];
	_status.drawsBackground = YES;
	_status.backgroundColor = [NSColor windowBackgroundColor];
	_findField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_findField.placeholderString = @"Find";
	_findField.target = self;
	_findField.action = @selector(findNext:);
	_findField.delegate = (id<NSTextFieldDelegate>)self;
	_findField.tag = 1;
	_replaceField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_replaceField.placeholderString = @"Replace";
	_replaceField.delegate = (id<NSTextFieldDelegate>)self;
	_replaceField.tag = 2;
	NppChromeView *find = [[NppChromeView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 96)];
	find.owner = self;
	[find addSubview:_findField];
	[find addSubview:_replaceField];
	_matchCase = [self check:@"Match case" frame:NSZeroRect];
	_wholeWord = [self check:@"Whole word" frame:NSZeroRect];
	_regex = [self check:@"Regex" frame:NSZeroRect];
	_wrap = [self check:@"Wrap" frame:NSZeroRect];
	_dotAll = [self check:@". matches newline" frame:NSZeroRect];
	_wrap.state = NSControlStateValueOn;
	for (NSButton *box in @[_matchCase, _wholeWord, _regex, _wrap, _dotAll]) {
		[find addSubview:box];
	}
	NSButton *next = [self button:@"Next" action:@selector(findNext:) frame:NSZeroRect];
	next.tag = 11;
	NSButton *previous = [self button:@"Previous" action:@selector(findPrevious:) frame:NSZeroRect];
	previous.tag = 12;
	NSButton *replace = [self button:@"Replace" action:@selector(replaceNext:) frame:NSZeroRect];
	replace.tag = 13;
	NSButton *replaceAll = [self button:@"Replace All" action:@selector(replaceAll:) frame:NSZeroRect];
	replaceAll.tag = 14;
	NSButton *inFiles = [self button:@"In Files" action:@selector(showReplaceInFiles:) frame:NSZeroRect];
	inFiles.tag = 15;
	NSButton *findClose = [self button:@"Close" action:@selector(hideFind:) frame:NSZeroRect];
	findClose.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:NppL(@"Close")];
	findClose.image.size = NSMakeSize(12, 12);
	findClose.imagePosition = NSImageOnly;
	findClose.tag = 16;
	findClose.toolTip = NppL(@"Close");
	for (NSButton *button in @[next, previous, replace, replaceAll, inFiles, findClose]) {
		[find addSubview:button];
	}
	_workspace.menuBar = _menuBar;
	_workspace.toolbar = _toolbar;
	_workspace.results = _resultsPanel;
	_workspace.tabStrip = _tabStrip;
	_workspace.tabs = _splitHost;
	_workspace.findBar = find;
	_workspace.status = _status;
	_compareBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 32)];
	_compareBar.wantsLayer = YES;
	_compareBar.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	_compareLabel = [NSTextField labelWithString:NppL(@"Compare")];
	_compareLabel.tag = 41;
	_compareLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
	_compareLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	NSButton *removedLegend = [NSButton buttonWithTitle:NppL(@"Removed") image:[NSImage imageWithSystemSymbolName:@"minus.circle.fill" accessibilityDescription:NppL(@"Removed")] target:nil action:nil];
	removedLegend.image.size = NSMakeSize(14, 14);
	removedLegend.imagePosition = NSImageLeading;
	removedLegend.bordered = NO;
	removedLegend.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
	removedLegend.contentTintColor = [NSColor systemPinkColor];
	removedLegend.tag = 45;
	NSButton *addedLegend = [NSButton buttonWithTitle:NppL(@"Added") image:[NSImage imageWithSystemSymbolName:@"plus.circle.fill" accessibilityDescription:NppL(@"Added")] target:nil action:nil];
	addedLegend.image.size = NSMakeSize(14, 14);
	addedLegend.imagePosition = NSImageLeading;
	addedLegend.bordered = NO;
	addedLegend.font = [NSFont systemFontOfSize:12 weight:NSFontWeightMedium];
	addedLegend.contentTintColor = [NSColor systemGreenColor];
	addedLegend.tag = 46;
	NSButton *comparePrevious = [self button:@"Previous" action:@selector(comparePrevious:) frame:NSZeroRect];
	comparePrevious.image = [NSImage imageWithSystemSymbolName:@"chevron.up" accessibilityDescription:NppL(@"Previous")];
	comparePrevious.image.size = NSMakeSize(12, 12);
	comparePrevious.imagePosition = NSImageLeading;
	comparePrevious.tag = 42;
	NSButton *compareNext = [self button:@"Next" action:@selector(compareNext:) frame:NSZeroRect];
	compareNext.image = [NSImage imageWithSystemSymbolName:@"chevron.down" accessibilityDescription:NppL(@"Next")];
	compareNext.image.size = NSMakeSize(12, 12);
	compareNext.imagePosition = NSImageLeading;
	compareNext.tag = 43;
	NSButton *compareClose = [self button:@"Close" action:@selector(closeCompare:) frame:NSZeroRect];
	compareClose.image = [NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:NppL(@"Close")];
	compareClose.image.size = NSMakeSize(12, 12);
	compareClose.imagePosition = NSImageLeading;
	compareClose.tag = 44;
	for (NSView *view in @[_compareLabel, removedLegend, addedLegend, comparePrevious, compareNext, compareClose]) {
		[_compareBar addSubview:view];
	}
	_workspace.compareBar = _compareBar;
	_workspace.compareVisible = NO;
	_workspace.findVisible = NO;
	_sidebar = [self buildFolderSidebar];
	_workspace.sidebar = _sidebar;
	_workspace.sidebarVisible = NO;
	[_workspace addSubview:_menuBar];
	[_workspace addSubview:_toolbar];
	[_workspace addSubview:_resultsPanel];
	[_workspace addSubview:_tabStrip];
	[_workspace addSubview:_sidebar];
	[_workspace addSubview:_splitHost];
	[_workspace addSubview:find];
	[_workspace addSubview:_compareBar];
	[_workspace addSubview:_status];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(syncActivePaneFromFocus) name:NSWindowDidUpdateNotification object:_window];
	_window.contentView = _workspace;
	[self applyWindowTheme];
	[_workspace layoutPanes];
}

- (NSButton *)check:(NSString *)title frame:(NSRect)frame {
	NSButton *button = [NSButton checkboxWithTitle:title target:nil action:nil];
	button.frame = frame;
	return button;
}

- (NSButton *)button:(NSString *)title action:(SEL)action frame:(NSRect)frame {
	NSButton *button = [NSButton buttonWithTitle:NppL(title) target:self action:action];
	button.frame = frame;
	return button;
}

- (NSButton *)toolButton:(NSString *)symbol title:(NSString *)title tip:(NSString *)tip action:(SEL)action {
	NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:NppL(title)];
	image.size = NSMakeSize(16, 16);
	NSButton *button = [NSButton buttonWithTitle:NppL(title) image:image target:self action:action];
	button.imagePosition = NSImageLeading;
	button.imageScaling = NSImageScaleProportionallyDown;
	button.bezelStyle = NSBezelStyleTexturedRounded;
	button.font = [NSFont systemFontOfSize:12];
	button.toolTip = NppL(tip);
	button.identifier = title;
	button.bordered = YES;
	[button sizeToFit];
	NSRect frame = button.frame;
	frame.size.width = MAX(54, ceil(frame.size.width) + 10);
	frame.size.height = 30;
	button.frame = frame;
	return button;
}

- (NSView *)buildToolbar {
	NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 72)];
	bar.clipsToBounds = YES;
	NSArray *rows = @[
		@[
			@[@"doc.badge.plus", @"New", @"New", NSStringFromSelector(@selector(newDocument:))],
			@[@"folder", @"Open", @"Open", NSStringFromSelector(@selector(openDocument:))],
			@[@"square.and.arrow.down", @"Save", @"Save", NSStringFromSelector(@selector(saveDocument:))],
			@[@"square.and.arrow.down.on.square", @"All", @"Save All", NSStringFromSelector(@selector(saveAllDocuments:))],
			@[@"xmark", @"Close", @"Close", NSStringFromSelector(@selector(closeDocument:))],
			@[@"|"],
			@[@"arrow.uturn.backward", @"Undo", @"Undo", NSStringFromSelector(@selector(undo:))],
			@[@"arrow.uturn.forward", @"Redo", @"Redo", NSStringFromSelector(@selector(redo:))],
			@[@"|"],
			@[@"scissors", @"Cut", @"Cut", NSStringFromSelector(@selector(cut:))],
			@[@"doc.on.doc", @"Copy", @"Copy", NSStringFromSelector(@selector(copy:))],
			@[@"doc.on.clipboard", @"Paste", @"Paste", NSStringFromSelector(@selector(paste:))],
			@[@"|"],
			@[@"magnifyingglass", @"Find", @"Find", NSStringFromSelector(@selector(showFind:))],
			@[@"doc.text.magnifyingglass", @"Files", @"Find in Files", NSStringFromSelector(@selector(showFindInFiles:))],
			@[@"arrow.left.arrow.right", @"Replace", @"Replace", NSStringFromSelector(@selector(showReplace:))]
		],
		@[
			@[@"curlybraces", @"Format JSON", @"Format JSON", NSStringFromSelector(@selector(formatJSON:))],
			@[@"chevron.left.forwardslash.chevron.right", @"Format XML", @"Format XML", NSStringFromSelector(@selector(formatXML:))],
			@[@"plus.forwardslash.minus", @"Compare", @"Compare Panes", NSStringFromSelector(@selector(comparePanes:))],
			@[@"|"],
			@[@"text.append", @"Tail", @"Start tail -f", NSStringFromSelector(@selector(toggleMonitoring:))],
			@[@"rectangle.split.2x1", @"Split", @"Split the tabs to the right into a new pane", NSStringFromSelector(@selector(splitRight:))],
			@[@"|"],
			@[@"record.circle", @"Record", @"Record Macro", NSStringFromSelector(@selector(startMacro:))],
			@[@"stop.circle", @"Stop", @"Stop Macro", NSStringFromSelector(@selector(stopMacro:))],
			@[@"play.circle", @"Play", @"Play Macro", NSStringFromSelector(@selector(playMacro:))]
		]
	];
	for (NSInteger rowIndex = 0; rowIndex < (NSInteger)rows.count; rowIndex++) {
		CGFloat y = (rows.count - 1 - rowIndex) * 36 + 4;
		CGFloat x = 8;
		for (NSArray *item in rows[rowIndex]) {
			if ([item[0] isEqualToString:@"|"]) {
				NSBox *rule = [[NSBox alloc] initWithFrame:NSMakeRect(x + 4, y + 1, 1, 28)];
				rule.boxType = NSBoxSeparator;
				[bar addSubview:rule];
				x += 14;
				continue;
			}
			NSButton *button = [self toolButton:item[0] title:item[1] tip:item[2] action:NSSelectorFromString(item[3])];
			if ([item[1] isEqualToString:@"Tail"]) {
				button.buttonType = NSButtonTypeToggle;
				_tailButton = button;
			}
			if ([item[1] isEqualToString:@"Format JSON"] || [item[1] isEqualToString:@"Format XML"]) {
				button.enabled = _settings.formatDocuments;
			}
			NSRect frame = button.frame;
			frame.origin = NSMakePoint(x, y);
			button.frame = frame;
			[bar addSubview:button];
			x += frame.size.width + 4;
		}
	}
	bar.identifier = @"toolbar";
	return bar;
}

- (void)rebuildTabStrip {
	for (NSInteger pane = 0; pane < (NSInteger)_paneDocuments.count; pane++) {
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
		NppPaneTabBar *bar = slot.tabBar;
		if (!bar) {
			continue;
		}
		NSInteger dropIndex = bar.dropIndex;
		for (NSView *view in bar.subviews.copy) {
			[view removeFromSuperview];
		}
		NSArray *tabs = pane < (NSInteger)_paneTabs.count ? _paneTabs[pane] : @[];
		id visible = _paneDocuments[pane];
		CGFloat x = 6;
		for (DocumentTab *document in tabs) {
			if (![document isKindOfClass:[DocumentTab class]]) {
				continue;
			}
			BOOL current = document == visible;
			BOOL activePane = pane == _activePane;
			NSString *name = document.title ?: @"Untitled";
			NSFont *font = current ? [NSFont boldSystemFontOfSize:12] : [NSFont systemFontOfSize:12];
			NSColor *textColor = current ? NSColor.labelColor : NSColor.secondaryLabelColor;
			NSString *kind = nil;
			NSView *badge = NppFileBadge(document, &kind);
			CGFloat natural = ceil([name sizeWithAttributes:@{NSFontAttributeName: font}].width);
			CGFloat width = MIN(240, MAX(148, natural + 64));
			NppTabButton *button = [[NppTabButton alloc] initWithFrame:NSZeroRect];
			button.buttonType = NSButtonTypeMomentaryPushIn;
			button.title = @"";
			button.target = self;
			button.owner = self;
			button.document = document;
			button.action = @selector(selectTabButton:);
			button.bordered = NO;
			NSString *location = document.path.length ? document.path : name;
			button.toolTip = kind.length ? [NSString stringWithFormat:@"%@\n%@", location, kind] : location;
			NppTabChip *chip = [[NppTabChip alloc] initWithFrame:NSMakeRect(x, 2, width, 24)];
			chip.document = document;
			chip.wantsLayer = YES;
			chip.layer.cornerRadius = 5;
			chip.layer.backgroundColor = (current ? NSColor.controlBackgroundColor : NSColor.clearColor).CGColor;
			if (current && activePane) {
				chip.layer.borderWidth = 1;
				chip.layer.borderColor = NSColor.controlAccentColor.CGColor;
			} else if (current) {
				chip.layer.borderWidth = 1;
				chip.layer.borderColor = NSColor.separatorColor.CGColor;
			}
			badge.frame = NSMakeRect(5, 4, 18, 16);
			button.frame = NSMakeRect(0, 0, width, 24);
			CGFloat labelWidth = MAX(24, width - 52);
			NppTabLabel *label = [[NppTabLabel alloc] initWithFrame:NSMakeRect(26, 2, labelWidth, 20)];
			label.text = NppFitTitle(name, font, labelWidth);
			label.font = font;
			label.textColor = textColor;
			label.toolTip = button.toolTip;
			NppTabCloseButton *close = [[NppTabCloseButton alloc] initWithFrame:NSMakeRect(width - 22, 2, 18, 20)];
			close.bordered = NO;
			close.title = @"×";
			close.contentTintColor = document.dirty ? NSColor.systemOrangeColor : textColor;
			close.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
			close.target = self;
			close.action = @selector(closeTabButton:);
			close.document = document;
			close.toolTip = @"Close";
			chip.clipsToBounds = YES;
			[chip addSubview:button];
			[chip addSubview:badge];
			[chip addSubview:label];
			[chip addSubview:close];
			[bar addSubview:chip];
			x += width + 4;
		}
		[bar noteContentWidth:x + 6];
		DocumentTab *currentDocument = [visible isKindOfClass:[DocumentTab class]] ? visible : nil;
		if (currentDocument != bar.anchoredDocument) {
			bar.anchoredDocument = currentDocument;
			[bar revealDocument:currentDocument];
		}
		bar.dropIndex = dropIndex;
	}
	[self refreshPaneChrome];
}

- (void)refreshPaneChrome {
	for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:index];
		if (![slot isKindOfClass:[NppPaneSlot class]]) {
			continue;
		}
		id shown = _paneDocuments[index];
		DocumentTab *document = [shown isKindOfClass:[DocumentTab class]] ? shown : nil;
		slot.title = document.displayName.length ? document.displayName : (document ? @"Untitled" : @"Empty");
		slot.activePane = index == _activePane;
		[slot setNeedsDisplay:YES];
	}
	[self updateSplitWrapping];
}

- (void)updateSplitWrapping {
	BOOL split = _paneDocuments.count > 1;
	for (DocumentTab *document in _documents) {
		BOOL gather = split && [self paneIndexOfDocument:document] != NSNotFound;
		ScintillaView *editor = document.editor;
		if (gather || _settings.wrap) {
			[editor message:SCI_SETWRAPMODE wParam:gather ? SC_WRAP_CHAR : SC_WRAP_WORD lParam:0];
			[editor message:SCI_SETSCROLLWIDTHTRACKING wParam:0 lParam:0];
			[editor message:SCI_SETSCROLLWIDTH wParam:1 lParam:0];
		} else {
			[editor message:SCI_SETWRAPMODE wParam:SC_WRAP_NONE lParam:0];
			[editor message:SCI_SETSCROLLWIDTHTRACKING wParam:1 lParam:0];
			[editor message:SCI_SETSCROLLWIDTH wParam:2000 lParam:0];
		}
	}
}

- (void)selectTabButton:(NSButton *)sender {
	DocumentTab *document = [sender isKindOfClass:[NppTabButton class]] ? ((NppTabButton *)sender).document : nil;
	if (!document) {
		[self rebuildTabStrip];
		return;
	}
	NSInteger pane = [self paneIndexContainingView:sender];
	if (document == _cloneSource && pane == _clonePane) {
		[self focusClone];
		return;
	}
	[self showDocument:document inPane:pane == NSNotFound ? [self paneIndexOfDocument:document] : pane];
}

- (void)forceCloseTab:(DocumentTab *)document fromView:(NSView *)view {
	if (![document isKindOfClass:[DocumentTab class]]) {
		return;
	}
	NSInteger pane = view ? [self paneIndexContainingView:view] : [self paneIndexOfDocument:document];
	dispatch_async(dispatch_get_main_queue(), ^{
		if (document == self->_cloneSource && pane == self->_clonePane) {
			[self dropClone];
			return;
		}
		if (![self->_documents containsObject:document]) {
			return;
		}
		[self showDocument:document inPane:pane];
		self->_closingWithoutPrompt = YES;
		[self closeDocument:nil];
		self->_closingWithoutPrompt = NO;
	});
}

- (void)closeTabButton:(NSButton *)sender {
	DocumentTab *document = [sender isKindOfClass:[NppTabCloseButton class]] ? ((NppTabCloseButton *)sender).document : nil;
	if (!document) {
		return;
	}
	NSInteger pane = [self paneIndexContainingView:sender];
	if (document == _cloneSource && pane == _clonePane) {
		[self dropClone];
		return;
	}
	[self showDocument:document inPane:[self paneIndexOfDocument:document]];
	[self closeDocument:nil];
}

- (NSView *)buildResultsPanel {
	NppChromeView *panel = [[NppChromeView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 260)];
	panel.owner = self;
	panel.resultsChrome = YES;
	panel.autoresizesSubviews = NO;
	panel.wantsLayer = YES;
	panel.layer.masksToBounds = YES;
	NSTextField *findLabel = [NSTextField labelWithString:@"Find"];
	findLabel.tag = 31;
	_filesQuery = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_filesQuery.placeholderString = @"Find what";
	_filesQuery.target = self;
	_filesQuery.action = @selector(runFindInFiles:);
	_filesQuery.tag = 21;
	NSTextField *replaceLabel = [NSTextField labelWithString:@"Replace"];
	replaceLabel.tag = 32;
	_filesReplace = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_filesReplace.placeholderString = @"Replace with";
	_filesReplace.tag = 22;
	NSTextField *filterLabel = [NSTextField labelWithString:@"Filters"];
	filterLabel.tag = 33;
	_filesFilters = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_filesFilters.stringValue = @"*.*";
	_filesFilters.tag = 23;
	NSTextField *dirLabel = [NSTextField labelWithString:@"Directory"];
	dirLabel.tag = 34;
	_filesDirectory = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_filesDirectory.placeholderString = @"Folder to search";
	_filesDirectory.tag = 24;
	NSButton *browse = [self button:@"Browse…" action:@selector(browseFindDirectory:) frame:NSZeroRect];
	browse.tag = 28;
	NSButton *findAll = [self button:@"Find All" action:@selector(runFindInFiles:) frame:NSZeroRect];
	findAll.tag = 25;
	NSButton *replaceFiles = [self button:@"Replace in Files" action:@selector(runReplaceInFiles:) frame:NSZeroRect];
	replaceFiles.tag = 26;
	NSButton *close = [self button:@"Close" action:@selector(hideFindInFiles:) frame:NSZeroRect];
	close.tag = 27;
	_filesCase = [self check:@"Match case" frame:NSZeroRect];
	_filesWord = [self check:@"Whole word" frame:NSZeroRect];
	_filesRegex = [self check:@"Regex" frame:NSZeroRect];
	_filesSubfolders = [self check:@"In subfolders" frame:NSZeroRect];
	_filesSubfolders.state = NSControlStateValueOn;
	_findProgress = [[NSProgressIndicator alloc] initWithFrame:NSZeroRect];
	_findProgress.style = NSProgressIndicatorStyleBar;
	_findProgress.indeterminate = YES;
	_findProgress.displayedWhenStopped = NO;
	_findProgress.controlSize = NSControlSizeSmall;
	_findProgressLabel = [NSTextField labelWithString:@""];
	_findProgressLabel.font = [NSFont systemFontOfSize:11];
	_findProgressLabel.lineBreakMode = NSLineBreakByTruncatingMiddle;
	_findProgressLabel.tag = 35;
	_findProgressLabel.hidden = YES;
	_findCancel = [self button:@"Cancel" action:@selector(cancelFindInFiles:) frame:NSZeroRect];
	_findCancel.tag = 29;
	_findCancel.hidden = YES;
	_resultsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	_resultsScroll.hasVerticalScroller = YES;
	_resultsScroll.hasHorizontalScroller = YES;
	_resultsScroll.autohidesScrollers = NO;
	_resultsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
	_resultsTable.style = NSTableViewStyleFullWidth;
	_resultsTable.columnAutoresizingStyle = NSTableViewNoColumnAutoresizing;
	_resultsTable.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
	_resultsTable.gridColor = NSColor.separatorColor;
	_resultsTable.intercellSpacing = NSMakeSize(6, 1);
	NSTableColumn *closeColumn = [[NSTableColumn alloc] initWithIdentifier:@"close"];
	closeColumn.title = @"";
	closeColumn.width = 28;
	closeColumn.minWidth = 28;
	closeColumn.maxWidth = 36;
	closeColumn.resizingMask = NSTableColumnNoResizing;
	closeColumn.editable = YES;
	NSButtonCell *closeCell = [[NSButtonCell alloc] init];
	closeCell.buttonType = NSButtonTypeMomentaryPushIn;
	closeCell.bezelStyle = NSBezelStyleInline;
	closeCell.bordered = NO;
	closeCell.imagePosition = NSNoImage;
	closeCell.title = @"×";
	closeCell.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
	closeCell.target = self;
	closeCell.action = @selector(closeSearchHit:);
	closeColumn.dataCell = closeCell;
	[_resultsTable addTableColumn:closeColumn];
	for (NSArray *columnInfo in @[@[@"file", @"Path", @520], @[@"line", @"Line", @60], @[@"text", @"Text", @480]]) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:columnInfo[0]];
		column.title = columnInfo[1];
		column.width = [columnInfo[2] doubleValue];
		column.minWidth = [columnInfo[0] isEqualToString:@"line"] ? 48 : 120;
		column.resizingMask = NSTableColumnUserResizingMask;
		[_resultsTable addTableColumn:column];
	}
	_resultsTable.dataSource = self;
	_resultsTable.delegate = self;
	_resultsTable.target = self;
	_resultsTable.doubleAction = @selector(openSearchHit:);
	_resultsScroll.documentView = _resultsTable;
	for (NSView *view in @[findLabel, _filesQuery, replaceLabel, _filesReplace, filterLabel, _filesFilters, dirLabel, _filesDirectory, browse, findAll, replaceFiles, close, _filesCase, _filesWord, _filesRegex, _filesSubfolders, _findProgress, _findProgressLabel, _findCancel, _resultsScroll]) {
		[panel addSubview:view];
	}
	return panel;
}

- (NSView *)chromeTagged:(NSInteger)tag in:(NSView *)view {
	for (NSView *subview in view.subviews) {
		if (subview.tag == tag) {
			return subview;
		}
	}
	return nil;
}

- (void)layoutFindBar {
	NSView *bar = _workspace.findBar;
	CGFloat width = MAX(640, bar.bounds.size.width);
	CGFloat field = MAX(140, MIN(360, width - 600));
	_findField.frame = NSMakeRect(8, 58, field, 24);
	_replaceField.frame = NSMakeRect(8, 18, field, 24);
	CGFloat x = NSMaxX(_findField.frame) + 8;
	NSArray *buttons = @[
		@[@11, @72],
		@[@12, @88],
		@[@13, @84],
		@[@14, @108],
		@[@15, @80]
	];
	for (NSArray *info in buttons) {
		NSView *button = [self chromeTagged:[info[0] integerValue] in:bar];
		button.frame = NSMakeRect(x, 58, [info[1] doubleValue], 24);
		x += [info[1] doubleValue] + 6;
	}
	NSView *findClose = [self chromeTagged:16 in:bar];
	findClose.frame = NSMakeRect(width - 36, 58, 28, 24);
	x = NSMaxX(_replaceField.frame) + 8;
	for (NSButton *box in @[_matchCase, _wholeWord, _regex, _wrap, _dotAll]) {
		[box sizeToFit];
		NSRect frame = box.frame;
		frame.origin = NSMakePoint(x, 16);
		frame.size.height = 24;
		box.frame = frame;
		x += frame.size.width + 8;
	}
}

- (void)layoutResultsPanel {
	NSView *panel = _resultsPanel;
	CGFloat width = MAX(640, panel.bounds.size.width);
	CGFloat height = panel.bounds.size.height;
	NSView *findLabel = [self chromeTagged:31 in:panel];
	NSView *replaceLabel = [self chromeTagged:32 in:panel];
	NSView *filterLabel = [self chromeTagged:33 in:panel];
	NSView *dirLabel = [self chromeTagged:34 in:panel];
	findLabel.frame = NSMakeRect(8, height - 28, 36, 20);
	CGFloat queryX = 48;
	CGFloat buttonWidth = 90 + 130 + 70 + 16;
	CGFloat field = MAX(120, (width - queryX - buttonWidth - 90) / 2);
	_filesQuery.frame = NSMakeRect(queryX, height - 32, field, 24);
	replaceLabel.frame = NSMakeRect(NSMaxX(_filesQuery.frame) + 8, height - 28, 58, 20);
	_filesReplace.frame = NSMakeRect(NSMaxX(replaceLabel.frame) + 4, height - 32, field, 24);
	CGFloat x = NSMaxX(_filesReplace.frame) + 8;
	[self chromeTagged:25 in:panel].frame = NSMakeRect(x, height - 32, 90, 24);
	[self chromeTagged:26 in:panel].frame = NSMakeRect(x + 96, height - 32, 130, 24);
	[self chromeTagged:27 in:panel].frame = NSMakeRect(x + 232, height - 32, 70, 24);
	filterLabel.frame = NSMakeRect(8, height - 60, 48, 20);
	_filesFilters.frame = NSMakeRect(60, height - 64, 140, 24);
	dirLabel.frame = NSMakeRect(208, height - 60, 64, 20);
	_filesDirectory.frame = NSMakeRect(276, height - 64, MAX(160, width - 276 - 100), 24);
	[self chromeTagged:28 in:panel].frame = NSMakeRect(NSMaxX(_filesDirectory.frame) + 8, height - 64, 84, 24);
	x = 8;
	for (NSButton *box in @[_filesCase, _filesWord, _filesRegex, _filesSubfolders]) {
		[box sizeToFit];
		NSRect frame = box.frame;
		frame.origin = NSMakePoint(x, height - 96);
		frame.size.height = 24;
		box.frame = frame;
		x += frame.size.width + 10;
	}
	BOOL searching = _findCancel && !_findCancel.hidden;
	CGFloat form = searching ? 148 : 112;
	_findProgress.hidden = !searching;
	_findProgressLabel.hidden = !searching;
	if (searching) {
		_findCancel.frame = NSMakeRect(width - 92, height - 136, 80, 24);
		_findProgress.frame = NSMakeRect(8, height - 128, 140, 12);
		_findProgressLabel.frame = NSMakeRect(156, height - 136, MAX(80, width - 256), 22);
	}
	_resultsScroll.frame = NSMakeRect(0, 0, width, MAX(40, height - form));
}

- (void)installWindowMenuBar {
	if (!_menuBar) {
		return;
	}
	for (NSView *view in _menuBar.subviews.copy) {
		[view removeFromSuperview];
	}
	CGFloat x = 6;
	for (NSMenuItem *top in NSApp.mainMenu.itemArray) {
		NSString *title = top.submenu.title.length ? top.submenu.title : top.title;
		if ([title isEqualToString:@"NSMenuItem"] || title.length == 0) {
			title = top.submenu.identifier.length ? top.submenu.identifier : @"Simeiomatarion";
		}
		if (!top.submenu || title.length == 0) {
			continue;
		}
		NSPopUpButton *button = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:YES];
		button.bordered = NO;
		button.font = [NSFont menuFontOfSize:13];
		NSMenu *menu = [[NSMenu alloc] initWithTitle:title];
		[menu addItem:[[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""]];
		for (NSMenuItem *item in top.submenu.itemArray) {
			NSMenuItem *copy = [item copy];
			[menu addItem:copy];
		}
		DisableKeyEquivalentSearch(menu);
		button.menu = menu;
		[button sizeToFit];
		NSRect frame = button.frame;
		frame.origin = NSMakePoint(x, 1);
		frame.size.height = 24;
		button.frame = frame;
		[_menuBar addSubview:button];
		x += frame.size.width + 2;
	}
}

static NSString *NppMenuSymbol(NSString *title) {
	static NSDictionary<NSString *, NSString *> *symbols;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		symbols = @{
			@"About Simeiomatarion": @"info.circle",
			@"Add Next Occurrence": @"plus.magnifyingglass",
			@"All": @"square.and.arrow.down.on.square",
			@"Always on Top": @"pin",
			@"Automatic": @"wand.and.stars",
			@"Bookmark": @"bookmark",
			@"Character Panel…": @"textformat.abc",
			@"Character sets": @"textformat",
			@"Clear All Bookmarks": @"bookmark.slash",
			@"Clipboard History…": @"list.clipboard",
			@"CSV Table": @"tablecells",
			@"Clone Beside": @"plus.rectangle.on.rectangle",
			@"Close": @"xmark",
			@"Close All": @"xmark.circle",
			@"Close All but Active": @"xmark.rectangle",
			@"Close All but This": @"xmark.rectangle",
			@"Close Split": @"rectangle",
			@"Close Tab": @"xmark",
			@"Column Editor…": @"tablecells.badge.ellipsis",
			@"Column Mode": @"tablecells",
			@"Compare": @"plus.forwardslash.minus",
			@"Compare Panes": @"plus.forwardslash.minus",
			@"Convert Case to": @"textformat",
			@"Copy": @"doc.on.doc",
			@"Copy Filename": @"doc.text",
			@"Copy Full File Path": @"doc.on.clipboard",
			@"Cut": @"scissors",
			@"Dark": @"moon.fill",
			@"Decrease Line Indent": @"decrease.indent",
			@"Delete": @"trash",
			@"Delete Current Line": @"trash",
			@"Duplicate Current Line": @"plus.square.on.square",
			@"Find": @"magnifyingglass",
			@"Find Next": @"arrow.down",
			@"Find Previous": @"arrow.up",
			@"Find in Files": @"doc.text.magnifyingglass",
			@"Find in Files…": @"doc.text.magnifyingglass",
			@"Find…": @"magnifyingglass",
			@"Files": @"doc.text.magnifyingglass",
			@"Fold All": @"chevron.down",
			@"Fold Current Level": @"chevron.down.circle",
			@"Folder Sidebar": @"sidebar.left",
			@"Format JSON": @"curlybraces",
			@"Format XML": @"chevron.left.forwardslash.chevron.right",
			@"Go to Line…": @"number",
			@"Go to Matching Brace": @"curlybraces",
			@"Increase Line Indent": @"increase.indent",
			@"Indent": @"increase.indent",
			@"Insert Date Time": @"calendar",
			@"Join Lines": @"arrow.down.to.line.compact",
			@"Line Numbers": @"list.number",
			@"Line Operations": @"text.alignleft",
			@"Minimap": @"map",
			@"Monitoring (tail -f)": @"text.append",
			@"Move Line Down": @"arrow.down",
			@"Move Line Up": @"arrow.up",
			@"New": @"doc.badge.plus",
			@"New Window": @"macwindow.badge.plus",
			@"Next Bookmark": @"bookmark",
			@"Next Tab": @"chevron.right",
			@"No commands": @"puzzlepiece",
			@"No plugins loaded": @"puzzlepiece",
			@"No recent files": @"clock",
			@"No recent searches": @"clock",
			@"No saved sessions": @"archivebox",
			@"Open Folder…": @"folder.badge.plus",
			@"Open Plugins Folder": @"folder",
			@"Open Quickly…": @"magnifyingglass",
			@"Open Recent": @"clock.arrow.circlepath",
			@"Open…": @"folder",
			@"Outline": @"list.bullet.indent",
			@"Paste": @"doc.on.clipboard",
			@"Pin Tab": @"pin",
			@"Play": @"play.circle",
			@"Playback": @"play.circle",
			@"Preferences…": @"gearshape",
			@"Preview": @"eye",
			@"Previous Bookmark": @"bookmark",
			@"Previous Tab": @"chevron.left",
			@"Print…": @"printer",
			@"Quit Simeiomatarion": @"power",
			@"Read-Only": @"lock",
			@"Record": @"record.circle",
			@"Redo": @"arrow.uturn.forward",
			@"Reload Plugins": @"arrow.clockwise",
			@"Reload from Disk": @"arrow.clockwise",
			@"Remove Bookmarked Lines": @"trash",
			@"Remove Duplicate Lines": @"minus.square",
			@"Remove Empty Lines": @"line.3.horizontal.decrease",
			@"Replace": @"arrow.left.arrow.right",
			@"Replace All": @"arrow.triangle.2.circlepath",
			@"Replace in Files…": @"arrow.left.arrow.right.square",
			@"Replace…": @"arrow.left.arrow.right",
			@"Restore Default Zoom": @"arrow.counterclockwise",
			@"Reveal in Finder": @"arrow.up.forward.app",
			@"Reverse Line Order": @"arrow.up.arrow.down",
			@"Run a Macro Multiple Times…": @"repeat",
			@"Save": @"square.and.arrow.down",
			@"Save All": @"square.and.arrow.down.on.square",
			@"Save As…": @"square.and.arrow.down.on.square",
			@"Save Current Macro…": @"square.and.arrow.down",
			@"Save Session…": @"archivebox",
			@"Search History": @"clock",
			@"Select All": @"selection.pin.in.out",
			@"Select and Find Next": @"text.magnifyingglass",
			@"Sessions": @"archivebox",
			@"Show End of Line": @"return",
			@"Show Indent Guide": @"list.dash",
			@"Show Whitespace": @"space",
			@"Snippets…": @"note.text",
			@"Sort Lines Ascending": @"arrow.up",
			@"Sort Lines Descending": @"arrow.down",
			@"Split": @"rectangle.split.2x1",
			@"Split Left": @"rectangle.split.2x1",
			@"Split Lines": @"text.line.first.and.arrowtriangle.forward",
			@"Split Right": @"rectangle.split.2x1",
			@"Start Recording": @"record.circle",
			@"Start tail -f": @"text.append",
			@"Stop": @"stop.circle",
			@"Stop Recording": @"stop.circle",
			@"Stop tail -f": @"text.append",
			@"Summary…": @"list.bullet",
			@"Sync Scrolling": @"arrow.up.and.down",
			@"System": @"circle.lefthalf.filled",
			@"TAB to Space": @"arrow.left.and.right",
			@"Tail": @"text.append",
			@"Toggle Bookmark": @"bookmark",
			@"Toggle Line Comment": @"text.bubble",
			@"Toggle Recording": @"record.circle",
			@"Trim Trailing Space": @"delete.right",
			@"UPPERCASE": @"textformat.size",
			@"Undo": @"arrow.uturn.backward",
			@"Unfold All": @"chevron.right",
			@"Unix (LF)": @"return",
			@"Unpin Tab": @"pin.slash",
			@"User Languages…": @"person.crop.rectangle",
			@"White": @"sun.max",
			@"Windows (CRLF)": @"return",
			@"Word Wrap": @"arrow.turn.down.left",
			@"Zoom In": @"plus.magnifyingglass",
			@"Zoom Out": @"minus.magnifyingglass",
			@"iNVERT cASE": @"textformat.alt",
			@"lowercase": @"textformat"
		};
	});
	return symbols[title];
}

- (void)applyMenuIcon:(NSString *)symbol toItem:(NSMenuItem *)item {
	if (symbol.length == 0 || item == nil) {
		return;
	}
	NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:item.title];
	if (!image) {
		return;
	}
	NSImageSymbolConfiguration *config = [NSImageSymbolConfiguration configurationWithPointSize:13 weight:NSFontWeightRegular];
	image = [image imageWithSymbolConfiguration:config] ?: image;
	[image setTemplate:YES];
	item.image = image;
	// macOS 27 hides SF Symbol menu images unless visibility is requested.
	SEL visibility = NSSelectorFromString(@"setPreferredImageVisibility:");
	if ([item respondsToSelector:visibility]) {
		NSInteger visible = 1;
		NSMethodSignature *signature = [item methodSignatureForSelector:visibility];
		NSInvocation *invocation = [NSInvocation invocationWithMethodSignature:signature];
		invocation.target = item;
		invocation.selector = visibility;
		[invocation setArgument:&visible atIndex:2];
		[invocation invoke];
	}
}

- (NSMenuItem *)item:(NSString *)title action:(SEL)action command:(NSString *)command {
	NSString *spec = command ? [_settings shortcutForCommand:command] : @"";
	NSString *key = @"";
	NSEventModifierFlags flags = 0;
	[EditorSettings parseShortcut:spec key:&key modifiers:&flags];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NppL(title) action:action keyEquivalent:key];
	item.keyEquivalentModifierMask = flags;
	item.target = self;
	item.representedObject = command;
	[self applyMenuIcon:NppMenuSymbol(title) toItem:item];
	return item;
}

- (NSMenuItem *)actionItem:(NSString *)title action:(NSString *)action command:(NSString *)command {
	NSString *key = @"";
	NSEventModifierFlags flags = 0;
	if (command.length) {
		[EditorSettings parseShortcut:[_settings shortcutForCommand:command] key:&key modifiers:&flags];
	}
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NppL(title) action:@selector(editorAction:) keyEquivalent:key];
	item.keyEquivalentModifierMask = flags;
	item.target = self;
	item.representedObject = action;
	[self applyMenuIcon:NppMenuSymbol(title) toItem:item];
	return item;
}

- (NSMenuItem *)actionItem:(NSString *)title action:(NSString *)action {
	return [self actionItem:title action:action command:nil];
}

- (void)editorAction:(NSMenuItem *)sender {
	DocumentTab *document = [self currentDocument];
	if (!document || ![sender.representedObject isKindOfClass:[NSString class]]) {
		return;
	}
	if ([sender.representedObject isEqualToString:@"zoomReset"]) {
		[self nudgeVisibleZoom:0 target:[self zoomTargetUnderHit:nil]];
		return;
	}
	NppRunEditorAction(document.editor, sender.representedObject, document.lexerName ?: @"");
	[self refreshStatus];
}

- (void)buildMenus {
	NSMenu *bar = [NSMenu new];
	NSMenu *appMenu = [[NSMenu alloc] initWithTitle:@"Simeiomatarion"];
	[appMenu addItem:[self item:@"About Simeiomatarion" action:@selector(showAbout:) command:nil]];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItem:[self item:@"Preferences…" action:@selector(showPreferences:) command:@"preferences"]];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Simeiomatarion" action:@selector(terminate:) keyEquivalent:@"q"];
	quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	[self applyMenuIcon:NppMenuSymbol(@"Quit Simeiomatarion") toItem:quit];
	[appMenu addItem:quit];
	NSMenuItem *appItem = [[NSMenuItem alloc] initWithTitle:@"Simeiomatarion" action:nil keyEquivalent:@""];
	appItem.submenu = appMenu;
	[bar addItem:appItem];

	NSMenu *file = [NSMenu new];
	file.title = @"File";
	[file addItem:[self item:@"New" action:@selector(newDocument:) command:@"new"]];
	NSMenuItem *newWindow = [self item:@"New Window" action:@selector(newWindow:) command:nil];
	newWindow.enabled = _settings.extraWindows;
	[file addItem:newWindow];
	[file addItem:[self item:@"Open…" action:@selector(openDocument:) command:@"open"]];
	[file addItem:[self item:@"Open Folder…" action:@selector(openFolder:) command:@"openFolder"]];
	[file addItem:[self item:@"Open Quickly…" action:@selector(showQuickOpen:) command:@"quickOpen"]];
	[file addItem:[self item:@"Reveal in Finder" action:@selector(revealInFinder:) command:@"reveal"]];
	[file addItem:[NSMenuItem separatorItem]];
	[file addItem:[self item:@"Save" action:@selector(saveDocument:) command:@"save"]];
	[file addItem:[self item:@"Save As…" action:@selector(saveDocumentAs:) command:@"saveAs"]];
	[file addItem:[self item:@"Save All" action:@selector(saveAllDocuments:) command:@"saveAll"]];
	[file addItem:[self item:@"Reload from Disk" action:@selector(reloadFromDisk:) command:@"reload"]];
	[file addItem:[NSMenuItem separatorItem]];
	[file addItem:[self item:@"Close Tab" action:@selector(closeDocument:) command:@"close"]];
	[file addItem:[self item:@"Close All" action:@selector(closeAllDocuments:) command:@"closeAll"]];
	[file addItem:[self item:@"Close All but Active" action:@selector(closeOtherDocuments:) command:nil]];
	[file addItem:[NSMenuItem separatorItem]];
	[file addItem:[self item:@"Print…" action:@selector(printDocument:) command:@"print"]];
	NSMenu *recent = [NSMenu new];
	recent.title = @"Open Recent";
	NSArray *paths = [[NSUserDefaults standardUserDefaults] arrayForKey:@"recentFiles"];
	if (paths.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NppL(@"No recent files") action:nil keyEquivalent:@""];
		none.enabled = NO;
		[self applyMenuIcon:NppMenuSymbol(@"No recent files") toItem:none];
		[recent addItem:none];
	}
	for (NSString *path in paths) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:path.lastPathComponent action:@selector(openRecent:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = path;
		item.toolTip = path;
		[self applyMenuIcon:@"doc" toItem:item];
		[recent addItem:item];
	}
	NSMenuItem *recentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
	recentItem.submenu = recent;
	[self applyMenuIcon:NppMenuSymbol(@"Open Recent") toItem:recentItem];
	[file addItem:recentItem];
	NSMenu *sessions = [NSMenu new];
	[sessions addItem:[self item:@"Save Session…" action:@selector(saveNamedSession:) command:nil]];
	NSArray<NSString *> *sessionNames = [self namedSessionTitles];
	if (sessionNames.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NppL(@"No saved sessions") action:nil keyEquivalent:@""];
		none.enabled = NO;
		[self applyMenuIcon:NppMenuSymbol(@"No saved sessions") toItem:none];
		[sessions addItem:none];
	}
	for (NSString *name in sessionNames) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(openNamedSession:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = name;
		[self applyMenuIcon:@"archivebox" toItem:item];
		[sessions addItem:item];
	}
	NSMenuItem *sessionItem = [[NSMenuItem alloc] initWithTitle:@"Sessions" action:nil keyEquivalent:@""];
	sessionItem.submenu = sessions;
	[self applyMenuIcon:NppMenuSymbol(@"Sessions") toItem:sessionItem];
	[file addItem:sessionItem];
	[self addMenu:file title:@"File" to:bar];

	NSMenu *edit = [NSMenu new];
	edit.title = @"Edit";
	[edit addItem:[self item:@"Undo" action:@selector(undo:) command:@"undo"]];
	[edit addItem:[self item:@"Redo" action:@selector(redo:) command:@"redo"]];
	[edit addItem:[NSMenuItem separatorItem]];
	[edit addItem:[self item:@"Cut" action:@selector(cut:) command:@"cut"]];
	[edit addItem:[self item:@"Copy" action:@selector(copy:) command:@"copy"]];
	[edit addItem:[self item:@"Paste" action:@selector(paste:) command:@"paste"]];
	[edit addItem:[self item:@"Select All" action:@selector(selectAll:) command:@"selectAll"]];
	[edit addItem:[NSMenuItem separatorItem]];
	NSMenu *lines = [NSMenu new];
	[lines addItem:[self actionItem:@"Duplicate Current Line" action:@"duplicate" command:@"duplicate"]];
	[lines addItem:[self actionItem:@"Delete Current Line" action:@"deleteLine"]];
	[lines addItem:[self actionItem:@"Move Line Up" action:@"moveUp" command:@"moveUp"]];
	[lines addItem:[self actionItem:@"Move Line Down" action:@"moveDown" command:@"moveDown"]];
	[lines addItem:[self actionItem:@"Join Lines" action:@"join" command:@"join"]];
	[lines addItem:[self actionItem:@"Split Lines" action:@"split" command:@"split"]];
	[lines addItem:[self actionItem:@"Remove Empty Lines" action:@"empty"]];
	[lines addItem:[self actionItem:@"Remove Duplicate Lines" action:@"duplicates"]];
	[lines addItem:[self actionItem:@"Sort Lines Ascending" action:@"sortAsc"]];
	[lines addItem:[self actionItem:@"Sort Lines Descending" action:@"sortDesc"]];
	[lines addItem:[self actionItem:@"Reverse Line Order" action:@"reverse"]];
	NSMenuItem *lineItem = [[NSMenuItem alloc] initWithTitle:@"Line Operations" action:nil keyEquivalent:@""];
	lineItem.submenu = lines;
	[self applyMenuIcon:NppMenuSymbol(@"Line Operations") toItem:lineItem];
	[edit addItem:lineItem];
	NSMenu *indent = [NSMenu new];
	[indent addItem:[self actionItem:@"Increase Line Indent" action:@"indent"]];
	[indent addItem:[self actionItem:@"Decrease Line Indent" action:@"outdent"]];
	NSMenuItem *indentItem = [[NSMenuItem alloc] initWithTitle:@"Indent" action:nil keyEquivalent:@""];
	indentItem.submenu = indent;
	[self applyMenuIcon:NppMenuSymbol(@"Indent") toItem:indentItem];
	[edit addItem:indentItem];
	NSMenu *convert = [NSMenu new];
	[convert addItem:[self actionItem:@"UPPERCASE" action:@"upper" command:@"upper"]];
	[convert addItem:[self actionItem:@"lowercase" action:@"lower" command:@"lower"]];
	[convert addItem:[self actionItem:@"iNVERT cASE" action:@"invert"]];
	NSMenuItem *convertItem = [[NSMenuItem alloc] initWithTitle:@"Convert Case to" action:nil keyEquivalent:@""];
	convertItem.submenu = convert;
	[self applyMenuIcon:NppMenuSymbol(@"Convert Case to") toItem:convertItem];
	[edit addItem:convertItem];
	[edit addItem:[self actionItem:@"Toggle Line Comment" action:@"comment" command:@"comment"]];
	[edit addItem:[self actionItem:@"Trim Trailing Space" action:@"trim"]];
	[edit addItem:[self actionItem:@"TAB to Space" action:@"tabsToSpaces"]];
	[edit addItem:[NSMenuItem separatorItem]];
	[edit addItem:[self actionItem:@"Insert Date Time" action:@"datetime"]];
	[edit addItem:[self item:@"Copy Full File Path" action:@selector(copyFullPath:) command:nil]];
	[edit addItem:[self item:@"Copy Filename" action:@selector(copyFilename:) command:nil]];
	[edit addItem:[NSMenuItem separatorItem]];
	[edit addItem:[self item:@"Add Next Occurrence" action:@selector(addNextOccurrence:) command:@"addNext"]];
	[edit addItem:[self item:@"Clipboard History…" action:@selector(showClipboardHistory:) command:@"clipboardHistory"]];
	[edit addItem:[self item:@"Snippets…" action:@selector(showSnippets:) command:@"snippets"]];
	NSMenuItem *formatJSON = [self item:@"Format JSON" action:@selector(formatJSON:) command:nil];
	formatJSON.enabled = _settings.formatDocuments;
	[edit addItem:formatJSON];
	NSMenuItem *formatXML = [self item:@"Format XML" action:@selector(formatXML:) command:nil];
	formatXML.enabled = _settings.formatDocuments;
	[edit addItem:formatXML];
	NSMenuItem *characters = [self item:@"Character Panel…" action:@selector(showCharacterPanel:) command:nil];
	characters.enabled = _settings.showCharacterPanel;
	[edit addItem:characters];
	[edit addItem:[self item:@"Pin Tab" action:@selector(togglePin:) command:@"pin"]];
	[edit addItem:[self actionItem:@"Column Mode" action:@"rectangle" command:@"column"]];
	[edit addItem:[self item:@"Column Editor…" action:@selector(columnEditor:) command:nil]];
	[edit addItem:[self actionItem:@"Read-Only" action:@"readonly"]];
	[self addMenu:edit title:@"Edit" to:bar];

	NSMenu *search = [NSMenu new];
	[search addItem:[self item:@"Find…" action:@selector(showFind:) command:@"find"]];
	[search addItem:[self item:@"Find in Files…" action:@selector(showFindInFiles:) command:@"findInFiles"]];
	[search addItem:[self item:@"Replace in Files…" action:@selector(showReplaceInFiles:) command:nil]];
	[search addItem:[self item:@"Find Next" action:@selector(findNext:) command:@"findNext"]];
	[search addItem:[self item:@"Find Previous" action:@selector(findPrevious:) command:@"findPrev"]];
	NSMenu *history = [NSMenu new];
	history.title = NppL(@"Search History");
	if (_settings.searchHistory.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NppL(@"No recent searches") action:nil keyEquivalent:@""];
		none.enabled = NO;
		[self applyMenuIcon:NppMenuSymbol(@"No recent searches") toItem:none];
		[history addItem:none];
	}
	for (NSString *query in _settings.searchHistory) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:query action:@selector(findFromHistory:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = query;
		[self applyMenuIcon:@"magnifyingglass" toItem:item];
		[history addItem:item];
	}
	NSMenuItem *historyItem = [[NSMenuItem alloc] initWithTitle:NppL(@"Search History") action:nil keyEquivalent:@""];
	historyItem.submenu = history;
	[self applyMenuIcon:NppMenuSymbol(@"Search History") toItem:historyItem];
	[search addItem:historyItem];
	[search addItem:[self item:@"Replace…" action:@selector(showReplace:) command:@"replace"]];
	[search addItem:[self item:@"Replace All" action:@selector(replaceAll:) command:nil]];
	[search addItem:[NSMenuItem separatorItem]];
	[search addItem:[self item:@"Go to Line…" action:@selector(goToLine:) command:@"goto"]];
	[search addItem:[self item:@"Go to Matching Brace" action:@selector(goToMatchingBrace:) command:@"brace"]];
	[search addItem:[self item:@"Select and Find Next" action:@selector(selectAndFindNext:) command:@"selectFindNext"]];
	NSMenu *bookmarks = [NSMenu new];
	[bookmarks addItem:[self actionItem:@"Toggle Bookmark" action:@"bookmark" command:@"bookmark"]];
	[bookmarks addItem:[self actionItem:@"Next Bookmark" action:@"bookmarkNext" command:@"bookmarkNext"]];
	[bookmarks addItem:[self actionItem:@"Previous Bookmark" action:@"bookmarkPrev" command:@"bookmarkPrev"]];
	[bookmarks addItem:[self actionItem:@"Clear All Bookmarks" action:@"bookmarkClear"]];
	[bookmarks addItem:[self actionItem:@"Remove Bookmarked Lines" action:@"bookmarkDelete"]];
	NSMenuItem *bookmarkItem = [[NSMenuItem alloc] initWithTitle:@"Bookmark" action:nil keyEquivalent:@""];
	bookmarkItem.submenu = bookmarks;
	[self applyMenuIcon:NppMenuSymbol(@"Bookmark") toItem:bookmarkItem];
	[search addItem:bookmarkItem];
	[self addMenu:search title:@"Search" to:bar];

	NSMenu *view = [NSMenu new];
	NSArray *appearances = @[@"System", @"White", @"Dark"];
	for (NSInteger index = 0; index < 3; index++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:NppL(appearances[index]) action:@selector(chooseAppearance:) keyEquivalent:@""];
		item.target = self;
		item.tag = index;
		NSString *theme = _settings.theme ?: @"system";
		NSInteger selected = [theme isEqualToString:@"light"] ? 1 : ([theme isEqualToString:@"dark"] ? 2 : 0);
		item.state = index == selected ? NSControlStateValueOn : NSControlStateValueOff;
		[self applyMenuIcon:NppMenuSymbol(appearances[index]) toItem:item];
		[view addItem:item];
	}
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Zoom In" action:@selector(zoomIn:) command:@"zoomIn"]];
	[view addItem:[self item:@"Zoom Out" action:@selector(zoomOut:) command:@"zoomOut"]];
	[view addItem:[self actionItem:@"Restore Default Zoom" action:@"zoomReset" command:@"zoomReset"]];
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Fold All" action:@selector(foldAll:) command:@"foldAll"]];
	[view addItem:[self item:@"Unfold All" action:@selector(unfoldAll:) command:@"unfoldAll"]];
	[view addItem:[self actionItem:@"Fold Current Level" action:@"foldCurrent"]];
	[view addItem:[self item:@"Next Tab" action:@selector(nextTab:) command:@"nextTab"]];
	[view addItem:[self item:@"Previous Tab" action:@selector(previousTab:) command:@"prevTab"]];
	[view addItem:[self item:@"Summary…" action:@selector(showSummary:) command:nil]];
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Word Wrap" action:@selector(toggleWrap:) command:nil]];
	[view addItem:[self item:@"Show Whitespace" action:@selector(toggleWhitespace:) command:nil]];
	[view addItem:[self actionItem:@"Show End of Line" action:@"eol"]];
	[view addItem:[self actionItem:@"Show Indent Guide" action:@"guides"]];
	[view addItem:[self item:@"Line Numbers" action:@selector(toggleLineNumbers:) command:nil]];
	[view addItem:[self item:@"Always on Top" action:@selector(toggleAlwaysOnTop:) command:nil]];
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Split Right" action:@selector(splitRight:) command:nil]];
	[view addItem:[self item:@"Close Split" action:@selector(closeSplit:) command:nil]];
	NSMenuItem *syncItem = [self item:@"Sync Scrolling" action:@selector(toggleSyncScrolling:) command:nil];
	syncItem.state = _settings.syncScroll ? NSControlStateValueOn : NSControlStateValueOff;
	[view addItem:syncItem];
	[view addItem:[self item:@"Compare Panes" action:@selector(comparePanes:) command:nil]];
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Monitoring (tail -f)" action:@selector(toggleMonitoring:) command:nil]];
	[view addItem:[NSMenuItem separatorItem]];
	[view addItem:[self item:@"Outline" action:@selector(showOutline:) command:@"outline"]];
	[view addItem:[self item:@"Folder Sidebar" action:@selector(toggleFolderSidebar:) command:nil]];
	NSMenuItem *minimapItem = [self item:@"Minimap" action:@selector(toggleMinimap:) command:@"minimap"];
	minimapItem.state = _settings.showMinimap ? NSControlStateValueOn : NSControlStateValueOff;
	[view addItem:minimapItem];
	NSMenuItem *previewItem = [self item:@"Preview" action:@selector(togglePreview:) command:@"preview"];
	previewItem.state = _previewVisible ? NSControlStateValueOn : NSControlStateValueOff;
	[view addItem:previewItem];
	NSMenuItem *csvItem = [self item:@"CSV Table" action:@selector(toggleCsvTable:) command:nil];
	NppOfficeRef *csvOffice = [self officeRefForDocument:[self currentDocument]];
	csvItem.enabled = csvOffice.kind == NppOfficeKindCSV;
	csvItem.state = csvOffice.kind == NppOfficeKindCSV && csvOffice.showTable ? NSControlStateValueOn : NSControlStateValueOff;
	[view addItem:csvItem];
	[view addItem:[self item:@"Clone Beside" action:@selector(cloneBeside:) command:@"clone"]];
	[self addMenu:view title:@"View" to:bar];

	NSMenu *encoding = [NSMenu new];
	NSMenu *characterSets = [NSMenu new];
	NSMutableDictionary<NSString *, NSMenu *> *groups = [NSMutableDictionary dictionary];
	for (int index = 0; index < NppEncodingCount(); index++) {
		const NppEncodingInfo *info = NppEncodingAt(index);
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(info->name) action:@selector(chooseEncoding:) keyEquivalent:@""];
		item.target = self;
		item.tag = info->id;
		[self applyMenuIcon:@"textformat" toItem:item];
		if (info->group[0] == '\0') {
			[encoding addItem:item];
			continue;
		}
		NSMenu *group = groups[@(info->group)];
		if (!group) {
			group = [NSMenu new];
			groups[@(info->group)] = group;
			NSMenuItem *parent = [[NSMenuItem alloc] initWithTitle:@(info->group) action:nil keyEquivalent:@""];
			parent.submenu = group;
			[self applyMenuIcon:@"textformat" toItem:parent];
			[characterSets addItem:parent];
		}
		[group addItem:item];
	}
	NSMenuItem *sets = [[NSMenuItem alloc] initWithTitle:@"Character sets" action:nil keyEquivalent:@""];
	sets.submenu = characterSets;
	[self applyMenuIcon:NppMenuSymbol(@"Character sets") toItem:sets];
	[encoding addItem:sets];
	[self addMenu:encoding title:@"Encoding" to:bar];

	NSMenu *eol = [NSMenu new];
	NSArray *eols = @[NppL(@"Windows (CRLF)"), NppL(@"Classic Mac (CR)"), NppL(@"Unix (LF)")];
	for (NSInteger index = 0; index < 3; index++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:eols[index] action:@selector(chooseEOL:) keyEquivalent:@""];
		item.target = self;
		item.tag = index;
		[self applyMenuIcon:@"return" toItem:item];
		[eol addItem:item];
	}
	[self addMenu:eol title:@"Line Endings" to:bar];

	NSMenu *language = [NSMenu new];
	NSMenuItem *automatic = [[NSMenuItem alloc] initWithTitle:NppL(@"Automatic") action:@selector(chooseAutomaticLanguage:) keyEquivalent:@""];
	automatic.target = self;
	[self applyMenuIcon:NppMenuSymbol(@"Automatic") toItem:automatic];
	[language addItem:automatic];
	[language addItem:[NSMenuItem separatorItem]];
	for (LangInfo *info in _catalog.allLanguages) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:info.name action:@selector(chooseLanguage:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = info.name;
		[self applyMenuIcon:@"chevron.left.forwardslash.chevron.right" toItem:item];
		[language addItem:item];
	}
	if (_userLanguages.languages.count) {
		[language addItem:[NSMenuItem separatorItem]];
		for (NppUserLanguage *user in _userLanguages.languages) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:user.name action:@selector(chooseUserLanguage:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = user.name;
			[self applyMenuIcon:@"person.crop.rectangle" toItem:item];
			[language addItem:item];
		}
	}
	[language addItem:[NSMenuItem separatorItem]];
	[language addItem:[self item:@"User Languages…" action:@selector(showUserLanguages:) command:nil]];
	[self addMenu:language title:@"Language" to:bar];

	NSMenu *macro = [NSMenu new];
	[macro addItem:[self item:@"Toggle Recording" action:@selector(toggleMacroRecording:) command:@"macroRecord"]];
	[macro addItem:[self item:@"Start Recording" action:@selector(startMacro:) command:nil]];
	[macro addItem:[self item:@"Stop Recording" action:@selector(stopMacro:) command:nil]];
	[macro addItem:[self item:@"Playback" action:@selector(playMacro:) command:@"macroPlay"]];
	[macro addItem:[self item:@"Run a Macro Multiple Times…" action:@selector(playMacroMultiple:) command:nil]];
	[macro addItem:[self item:@"Save Current Macro…" action:@selector(saveMacroNamed:) command:nil]];
	if (_macro.savedNames.count) {
		[macro addItem:[NSMenuItem separatorItem]];
		for (NSString *name in _macro.savedNames) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:name action:@selector(playSavedMacro:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = name;
			[self applyMenuIcon:@"play.circle" toItem:item];
			[macro addItem:item];
		}
	}
	[self addMenu:macro title:@"Macro" to:bar];

	NSMenu *plugins = [NSMenu new];
	if (_plugins.count == 0 && _pluginErrors.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:NppL(@"No plugins loaded") action:nil keyEquivalent:@""];
		none.enabled = NO;
		[self applyMenuIcon:NppMenuSymbol(@"No plugins loaded") toItem:none];
		[plugins addItem:none];
	}
	for (NSString *error in _pluginErrors) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:error action:nil keyEquivalent:@""];
		item.enabled = NO;
		[self applyMenuIcon:@"exclamationmark.triangle" toItem:item];
		[plugins addItem:item];
	}
	for (NSDictionary *plugin in _plugins) {
		NSMenu *submenu = [NSMenu new];
		const NppMacCommand *commands = (const NppMacCommand *)[plugin[@"commands"] pointerValue];
		int count = [plugin[@"count"] intValue];
		for (int index = 0; index < count; index++) {
			NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(commands[index].title ?: "Command") action:@selector(runPluginCommand:) keyEquivalent:@""];
			item.target = self;
			item.representedObject = @[plugin, @(index)];
			[self applyMenuIcon:@"puzzlepiece" toItem:item];
			[submenu addItem:item];
		}
		if (submenu.numberOfItems == 0) {
			NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:NppL(@"No commands") action:nil keyEquivalent:@""];
			empty.enabled = NO;
			[self applyMenuIcon:NppMenuSymbol(@"No commands") toItem:empty];
			[submenu addItem:empty];
		}
		NSMenuItem *pluginItem = [[NSMenuItem alloc] initWithTitle:plugin[@"name"] ?: @"Plugin" action:nil keyEquivalent:@""];
		pluginItem.submenu = submenu;
		[self applyMenuIcon:@"puzzlepiece.extension" toItem:pluginItem];
		[plugins addItem:pluginItem];
	}
	[plugins addItem:[NSMenuItem separatorItem]];
	[plugins addItem:[self item:@"Reload Plugins" action:@selector(reloadPlugins:) command:nil]];
	[plugins addItem:[self item:@"Open Plugins Folder" action:@selector(openPluginsFolder:) command:nil]];
	[self addMenu:plugins title:@"Plugins" to:bar];

	NSMenu *windowMenu = [NSMenu new];
	[windowMenu addItem:[self item:@"Next Tab" action:@selector(nextTab:) command:nil]];
	[windowMenu addItem:[self item:@"Previous Tab" action:@selector(previousTab:) command:nil]];
	[windowMenu addItem:[NSMenuItem separatorItem]];
	NSInteger windowIndex = 0;
	for (DocumentTab *document in _documents) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:document.title ?: @"Untitled" action:@selector(selectWindowDocument:) keyEquivalent:@""];
		item.target = self;
		item.tag = windowIndex++;
		item.state = document == [self currentDocument] ? NSControlStateValueOn : NSControlStateValueOff;
		[self applyMenuIcon:@"doc.text" toItem:item];
		[windowMenu addItem:item];
	}
	[self addMenu:windowMenu title:@"Window" to:bar];

	NSMenu *settings = [NSMenu new];
	[settings addItem:[self item:@"Preferences…" action:@selector(showPreferences:) command:@"preferences"]];
	[self addMenu:settings title:@"Settings" to:bar];
	NSApp.mainMenu = bar;
	[self installWindowMenuBar];
}

- (void)addMenu:(NSMenu *)menu title:(NSString *)title to:(NSMenu *)bar {
	menu.title = NppL(title);
	menu.identifier = title;
	NSMenuItem *item = [NSMenuItem new];
	item.submenu = menu;
	item.title = NppL(title);
	[bar addItem:item];
}

- (DocumentTab *)currentDocument {
	NSTabViewItem *item = _tabs.selectedTabViewItem;
	return [item.identifier isKindOfClass:[DocumentTab class]] ? item.identifier : nil;
}

- (BOOL)darkAppearance {
	if ([_settings.theme isEqualToString:@"dark"]) {
		return YES;
	}
	if ([_settings.theme isEqualToString:@"light"]) {
		return NO;
	}
	NSAppearanceName match = [_window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]];
	return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)applyWindowTheme {
	NSAppearance *appearance = nil;
	if ([_settings.theme isEqualToString:@"dark"]) {
		appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
	} else if ([_settings.theme isEqualToString:@"light"]) {
		appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
	}
	NSApp.appearance = appearance;
	_window.appearance = appearance;
	_preferencesWindow.appearance = appearance;
	_characterPanel.appearance = appearance;
	[self layoutFolderSidebar];
}

- (void)systemAppearanceChanged {
	if ([_settings.theme isEqualToString:@"dark"] || [_settings.theme isEqualToString:@"light"]) {
		return;
	}
	for (DocumentTab *document in _documents) {
		[document applySettings:_settings dark:[self darkAppearance]];
	}
	[self layoutFolderSidebar];
}

- (void)addDocument:(DocumentTab *)document {
	document.delegate = (id<DocumentTabDelegate>)self;
	[_documents addObject:document];
	NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:document];
	item.label = document.title;
	item.view = [[NSView alloc] initWithFrame:NSZeroRect];
	document.editor.clipsToBounds = YES;
	[_tabs addTabViewItem:item];
	[_tabs selectTabViewItem:item];
	[document applySettings:_settings dark:[self darkAppearance]];
	[self attachEditorMenu:document];
	[self showDocument:document inPane:_activePane];
}

- (NSMutableArray<DocumentTab *> *)tabsForPane:(NSInteger)pane {
	if (!_paneTabs) {
		_paneTabs = [NSMutableArray array];
	}
	while ((NSInteger)_paneTabs.count < (NSInteger)_paneDocuments.count) {
		[_paneTabs addObject:[NSMutableArray array]];
	}
	if (pane < 0 || pane >= (NSInteger)_paneTabs.count) {
		return nil;
	}
	return _paneTabs[pane];
}

- (NSInteger)paneIndexOfDocument:(DocumentTab *)document {
	for (NSInteger index = 0; index < (NSInteger)_paneTabs.count && index < (NSInteger)_paneDocuments.count; index++) {
		if ([_paneTabs[index] containsObject:document]) {
			return index;
		}
	}
	for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
		if (_paneDocuments[index] == document) {
			return index;
		}
	}
	return NSNotFound;
}

- (ScintillaView *)editorForDocument:(DocumentTab *)document inPane:(NSInteger)pane {
	if (document == _cloneSource && pane == _clonePane) {
		return [document mirrorView];
	}
	return document.editor;
}

- (ScintillaView *)activeEditor {
	NSResponder *responder = _window.firstResponder;
	while (responder) {
		if ([responder isKindOfClass:[ScintillaView class]]) {
			return (ScintillaView *)responder;
		}
		responder = responder.nextResponder;
	}
	return [self currentDocument].editor;
}

- (NSInteger)paneIndexContainingView:(NSView *)view {
	while (view) {
		if ([view isKindOfClass:[NppPaneTabBar class]]) {
			return ((NppPaneTabBar *)view).paneIndex;
		}
		if ([view isKindOfClass:[NppPaneSlot class]]) {
			return ((NppPaneSlot *)view).paneIndex;
		}
		view = view.superview;
	}
	return NSNotFound;
}

- (NppOfficeRef *)officeRefForDocument:(DocumentTab *)document {
	return document ? [_office objectForKey:document] : nil;
}

- (BOOL)officeShowsSurface:(DocumentTab *)document {
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (!office.view) {
		return NO;
	}
	if (office.kind == NppOfficeKindPDF || office.kind == NppOfficeKindDOC || office.kind == NppOfficeKindDOCX) {
		return YES;
	}
	if (office.kind == NppOfficeKindXLSX) {
		return office.showTable && office.view != nil;
	}
	return office.kind == NppOfficeKindCSV && office.showTable;
}

- (void)rememberOffice:(NppOfficeRef *)office forDocument:(DocumentTab *)document {
	if (document && office) {
		[_office setObject:office forKey:document];
	}
}

- (void)lockOfficeText:(DocumentTab *)document {
	[document.editor setEditable:NO];
	[document.editor message:SCI_SETREADONLY wParam:1 lParam:0];
}

- (void)pushOfficeCsv:(NSString *)csv document:(DocumentTab *)document {
	if (!document) {
		return;
	}
	document.suppressMacro = YES;
	[document.editor setString:csv ?: @""];
	document.suppressMacro = NO;
	document.dirty = YES;
	[self refreshStatus];
}

- (NppCsvView *)csvViewForDocument:(DocumentTab *)document {
	NppOfficeRef *office = [self officeRefForDocument:document];
	NppCsvView *view = [office.view isKindOfClass:[NppCsvView class]] ? (NppCsvView *)office.view : nil;
	if (!view) {
		view = [[NppCsvView alloc] initWithFrame:NSZeroRect];
		__weak AppDelegate *weakSelf = self;
		__weak DocumentTab *weakDocument = document;
		view.onEdit = ^(NSString *csv) {
			[weakSelf pushOfficeCsv:csv document:weakDocument];
		};
		view.onShowText = ^{
			AppDelegate *strongSelf = weakSelf;
			DocumentTab *strongDocument = weakDocument;
			NppOfficeRef *current = [strongSelf officeRefForDocument:strongDocument];
			current.showTable = NO;
			NSInteger pane = [strongSelf paneIndexOfDocument:strongDocument];
			if (pane != NSNotFound) {
				[strongSelf placeEditor:strongDocument inPane:pane];
				[strongSelf->_window makeFirstResponder:strongDocument.editor];
			}
			[strongSelf buildMenus];
		};
		office.view = view;
	}
	return view;
}

- (void)placeEditor:(DocumentTab *)document inPane:(NSInteger)pane {
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
	if (![slot isKindOfClass:[NppPaneSlot class]] || !document) {
		return;
	}
	[slot removeEditorViews];
	if ([self officeShowsSurface:document]) {
		NSView *surface = [self officeRefForDocument:document].view;
		[surface removeFromSuperview];
		surface.autoresizingMask = NSViewNotSizable;
		surface.frame = slot.editorRect;
		[slot addSubview:surface];
		[slot layoutContents];
		return;
	}
	ScintillaView *view = [self editorForDocument:document inPane:pane];
	[view removeFromSuperview];
	view.scrollView.focusRingType = NSFocusRingTypeNone;
	view.autoresizingMask = NSViewNotSizable;
	view.clipsToBounds = YES;
	view.frame = slot.editorRect;
	[slot addSubview:view];
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (office.kind == NppOfficeKindCSV && !office.showTable) {
		NSView *bar = [[NSView alloc] initWithFrame:NSZeroRect];
		bar.identifier = @"npp.csv.bar";
		bar.wantsLayer = YES;
		bar.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		NSImage *image = [NSImage imageWithSystemSymbolName:@"tablecells" accessibilityDescription:NppL(@"As Table")];
		image.size = NSMakeSize(14, 14);
		[image setTemplate:YES];
		NSButton *button = [NSButton buttonWithTitle:NppL(@"As Table") image:image target:self action:@selector(toggleCsvTable:)];
		button.bezelStyle = NSBezelStyleRounded;
		button.imagePosition = NSImageLeading;
		button.font = [NSFont systemFontOfSize:12];
		button.tag = 1;
		NSTextField *hint = [NSTextField labelWithString:NppL(@"This CSV is open as text.")];
		hint.font = [NSFont systemFontOfSize:12];
		hint.textColor = NSColor.secondaryLabelColor;
		hint.lineBreakMode = NSLineBreakByTruncatingTail;
		hint.tag = 2;
		[bar addSubview:button];
		[bar addSubview:hint];
		[slot addSubview:bar];
	}
	if (NppOfficeKindIsViewOnly(office.kind)) {
		[self lockOfficeText:document];
	}
	[self attachMinimapToSlot:slot forDocument:document];
	if (_previewVisible && pane == _activePane) {
		[self attachPreviewToSlot:slot];
	}
	[slot layoutContents];
	[self refreshMinimapForDocument:document inPane:pane];
}

- (void)showDocument:(DocumentTab *)document inPane:(NSInteger)pane {
	if (![document isKindOfClass:[DocumentTab class]] || _paneDocuments.count == 0) {
		return;
	}
	NSInteger existing = [self paneIndexOfDocument:document];
	if (pane == NSNotFound) {
		pane = existing != NSNotFound ? existing : _activePane;
	}
	if (existing == NSNotFound) {
		if (pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
			pane = _activePane;
		}
		NSMutableArray<DocumentTab *> *tabs = [self tabsForPane:pane];
		if (tabs && ![tabs containsObject:document]) {
			[tabs addObject:document];
		}
		existing = pane;
	}
	id previous = _paneDocuments[existing];
	if (previous != document && [previous isKindOfClass:[DocumentTab class]]) {
		[((DocumentTab *)previous).editor removeFromSuperview];
	}
	_paneDocuments[existing] = document;
	[self placeEditor:document inPane:existing];
	_activePane = existing;
	[_tabs selectTabViewItem:[self itemForDocument:document]];
	[_splitHost setActivePane:existing];
	NSView *surface = [self officeShowsSurface:document] ? [self officeRefForDocument:document].view : document.editor;
	[_window makeFirstResponder:surface];
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)noteTabDragStarted:(DocumentTab *)document {
	_draggedDocument = document;
}

- (void)noteTabDragEnded {
	_draggedDocument = nil;
	for (NSInteger index = 0; index < [_splitHost paneCount]; index++) {
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:index];
		slot.tabBar.dropIndex = -1;
		[slot.tabBar setNeedsDisplay:YES];
		[slot clearSplitPreview];
	}
}

- (DocumentTab *)draggedTabDocument {
	return _draggedDocument;
}

- (void)closeEmptyPane:(NSInteger)index {
	if (_paneDocuments.count <= 1 || index < 0 || index >= (NSInteger)_paneDocuments.count) {
		return;
	}
	NSMutableArray<NSNumber *> *fractions = [[_splitHost fractions] mutableCopy];
	CGFloat removed = index < (NSInteger)fractions.count ? fractions[index].doubleValue : 0;
	if (index < (NSInteger)_paneTabs.count) {
		[_paneTabs removeObjectAtIndex:index];
	}
	[_paneDocuments removeObjectAtIndex:index];
	if (index < (NSInteger)fractions.count) {
		[fractions removeObjectAtIndex:index];
	}
	if (fractions.count == _paneDocuments.count && fractions.count > 0) {
		NSInteger neighbor = MIN(index, (NSInteger)fractions.count - 1);
		fractions[neighbor] = @(fractions[neighbor].doubleValue + removed);
		[_splitHost setPaneCount:_paneDocuments.count];
		[_splitHost setFractions:fractions];
	} else {
		[_splitHost setPaneCount:_paneDocuments.count];
	}
	if (_activePane >= (NSInteger)_paneDocuments.count) {
		_activePane = (NSInteger)_paneDocuments.count - 1;
	} else if (_activePane > index) {
		_activePane--;
	}
	[self relayoutPaneEditors];
}

- (BOOL)canSplitDocument:(DocumentTab *)document besidePane:(NSInteger)pane onRight:(BOOL)onRight {
	if (![document isKindOfClass:[DocumentTab class]] || _paneDocuments.count >= 6) {
		return NO;
	}
	if (pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
		return NO;
	}
	NSInteger source = [self paneIndexOfDocument:document];
	if (source == NSNotFound) {
		return NO;
	}
	BOOL alone = [self tabsForPane:source].count <= 1;
	if (alone && source == pane) {
		return NO;
	}
	if (alone && onRight && source == pane + 1) {
		return NO;
	}
	if (alone && !onRight && source == pane - 1) {
		return NO;
	}
	return YES;
}

- (BOOL)splitDocument:(DocumentTab *)document besidePane:(NSInteger)pane onRight:(BOOL)onRight {
	if (![self canSplitDocument:document besidePane:pane onRight:onRight]) {
		return NO;
	}
	NSInteger insert = onRight ? pane + 1 : pane;
	NSMutableArray<NSNumber *> *fractions = [[_splitHost fractions] mutableCopy];
	if (fractions.count != _paneDocuments.count) {
		fractions = [NSMutableArray array];
		CGFloat share = 1.0 / _paneDocuments.count;
		for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
			[fractions addObject:@(share)];
		}
	}
	CGFloat half = fractions[pane].doubleValue / 2.0;
	fractions[pane] = @(half);
	[fractions insertObject:@(half) atIndex:insert];
	[_paneDocuments insertObject:[NSNull null] atIndex:insert];
	[_paneTabs insertObject:[NSMutableArray array] atIndex:insert];
	[_splitHost setPaneCount:_paneDocuments.count];
	[_splitHost setFractions:fractions];
	[self moveDocument:document toPane:insert atIndex:0];
	return YES;
}

- (void)splitTabLeft:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	NSInteger pane = [self paneIndexOfDocument:document];
	if (pane != NSNotFound) {
		[self splitDocument:document besidePane:pane onRight:NO];
	}
}

- (void)splitTabRight:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	NSInteger pane = [self paneIndexOfDocument:document];
	if (pane != NSNotFound) {
		[self splitDocument:document besidePane:pane onRight:YES];
	}
}

- (void)moveDocument:(DocumentTab *)document toPane:(NSInteger)pane atIndex:(NSInteger)index {
	if (![document isKindOfClass:[DocumentTab class]] || pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
		return;
	}
	if (document == _cloneSource) {
		NSInteger clonePane = _clonePane;
		NSInteger before = (NSInteger)_paneDocuments.count;
		[self dropClone];
		if ((NSInteger)_paneDocuments.count < before && clonePane < pane) {
			pane--;
		}
		if (pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
			return;
		}
	}
	NSInteger source = [self paneIndexOfDocument:document];
	if (source == NSNotFound) {
		return;
	}
	NSMutableArray<DocumentTab *> *sourceTabs = [self tabsForPane:source];
	NSMutableArray<DocumentTab *> *destTabs = [self tabsForPane:pane];
	if (!sourceTabs || !destTabs) {
		return;
	}
	if (source != pane && sourceTabs.count == 1 && destTabs.count == 1) {
		[_paneTabs exchangeObjectAtIndex:source withObjectAtIndex:pane];
		[_paneDocuments exchangeObjectAtIndex:source withObjectAtIndex:pane];
		[self relayoutPaneEditors];
		[self showDocument:document inPane:pane];
		[self saveSession];
		return;
	}
	NSInteger from = [sourceTabs indexOfObject:document];
	if (source == pane) {
		if (from == NSNotFound) {
			return;
		}
		if (index > from) {
			index--;
		}
		if (index == from) {
			return;
		}
		[sourceTabs removeObjectAtIndex:from];
		index = MAX(0, MIN(index, (NSInteger)sourceTabs.count));
		[sourceTabs insertObject:document atIndex:index];
	} else {
		[sourceTabs removeObject:document];
		index = MAX(0, MIN(index, (NSInteger)destTabs.count));
		[destTabs insertObject:document atIndex:index];
		if (_paneDocuments[source] == document) {
			_paneDocuments[source] = sourceTabs.count ? sourceTabs[MIN(MAX(from, 0), (NSInteger)sourceTabs.count - 1)] : [NSNull null];
			id replacement = _paneDocuments[source];
			if ([replacement isKindOfClass:[DocumentTab class]]) {
				[self placeEditor:replacement inPane:source];
			}
		}
		if (sourceTabs.count == 0) {
			[self closeEmptyPane:source];
			if (pane > source) {
				pane--;
			}
		}
	}
	[self showDocument:document inPane:pane];
	[self saveSession];
}

- (void)splitHostDidActivatePane:(NSInteger)pane {
	if (pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
		return;
	}
	_activePane = pane;
	[_splitHost setActivePane:pane];
	id document = _paneDocuments[pane];
	if ([document isKindOfClass:[DocumentTab class]]) {
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		ScintillaView *editor = document == _cloneSource && pane == _clonePane ? [document existingMirror] : ((DocumentTab *)document).editor;
		[_window makeFirstResponder:editor ?: ((DocumentTab *)document).editor];
	}
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)syncActivePaneFromFocus {
	if (_syncingPane || !_splitHost) {
		return;
	}
	NSView *view = [_window.firstResponder isKindOfClass:[NSView class]] ? (NSView *)_window.firstResponder : nil;
	NSInteger index = [_splitHost paneContainingView:view];
	if (index == NSNotFound || index == _activePane) {
		return;
	}
	id document = _paneDocuments[index];
	if (![document isKindOfClass:[DocumentTab class]]) {
		return;
	}
	_syncingPane = YES;
	_activePane = index;
	[_tabs selectTabViewItem:[self itemForDocument:document]];
	[_splitHost setActivePane:index];
	[self rebuildTabStrip];
	[self refreshStatus];
	_syncingPane = NO;
}

- (void)splitHostDidFinishResize {
	[self saveSession];
}

- (void)relayoutPaneEditors {
	for (NSInteger pane = 0; pane < (NSInteger)_paneDocuments.count; pane++) {
		id shown = _paneDocuments[pane];
		if ([shown isKindOfClass:[DocumentTab class]]) {
			[self placeEditor:shown inPane:pane];
		} else {
			NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
			[slot removeEditorViews];
		}
	}
}

- (void)splitRight:(id)sender {
	(void)sender;
	if (_paneDocuments.count >= 6) {
		return;
	}
	NSInteger insert = MIN(_activePane + 1, (NSInteger)_paneDocuments.count);
	NSMutableArray<NSNumber *> *fractions = [[_splitHost fractions] mutableCopy];
	if (fractions.count != _paneDocuments.count) {
		fractions = [NSMutableArray array];
		CGFloat share = 1.0 / _paneDocuments.count;
		for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
			[fractions addObject:@(share)];
		}
	}
	CGFloat active = fractions[_activePane].doubleValue;
	CGFloat half = active / 2.0;
	fractions[_activePane] = @(half);
	[fractions insertObject:@(half) atIndex:insert];
	[_paneDocuments insertObject:[NSNull null] atIndex:insert];
	[_paneTabs insertObject:[NSMutableArray array] atIndex:insert];
	[_splitHost setPaneCount:_paneDocuments.count];
	[_splitHost setFractions:fractions];
	NSMutableArray<DocumentTab *> *sourceTabs = [self tabsForPane:_activePane];
	id visible = _paneDocuments[_activePane];
	NSInteger selected = [visible isKindOfClass:[DocumentTab class]] ? [sourceTabs indexOfObject:visible] : NSNotFound;
	NSArray<DocumentTab *> *moving = @[];
	if (selected != NSNotFound && selected + 1 < (NSInteger)sourceTabs.count) {
		moving = [sourceTabs subarrayWithRange:NSMakeRange(selected + 1, sourceTabs.count - (selected + 1))];
		[sourceTabs removeObjectsInArray:moving];
	} else if (sourceTabs.count > 1 && selected != NSNotFound) {
		moving = @[sourceTabs[selected]];
		[sourceTabs removeObjectAtIndex:selected];
		_paneDocuments[_activePane] = sourceTabs.lastObject;
	}
	NSMutableArray<DocumentTab *> *destination = _paneTabs[insert];
	[destination addObjectsFromArray:moving];
	[self relayoutPaneEditors];
	if (moving.count > 0) {
		[self showDocument:moving.firstObject inPane:insert];
	} else {
		_activePane = insert;
		[self newDocument:nil];
	}
}

- (void)closeSplit:(id)sender {
	(void)sender;
	if (_paneDocuments.count <= 1) {
		return;
	}
	NSInteger index = MIN(MAX(_activePane, 0), (NSInteger)_paneDocuments.count - 1);
	NSInteger neighbor = index == 0 ? 1 : index - 1;
	NSMutableArray<DocumentTab *> *moving = index < (NSInteger)_paneTabs.count ? _paneTabs[index] : nil;
	NSMutableArray<DocumentTab *> *destination = neighbor < (NSInteger)_paneTabs.count ? _paneTabs[neighbor] : nil;
	for (DocumentTab *document in [moving copy]) {
		if (![destination containsObject:document]) {
			[destination addObject:document];
		}
	}
	if (index < (NSInteger)_paneTabs.count) {
		[_paneTabs removeObjectAtIndex:index];
	}
	id document = _paneDocuments[index];
	if ([document isKindOfClass:[DocumentTab class]]) {
		[((DocumentTab *)document).editor removeFromSuperview];
	}
	NSMutableArray<NSNumber *> *fractions = [[_splitHost fractions] mutableCopy];
	CGFloat removed = fractions.count == _paneDocuments.count ? fractions[index].doubleValue : 0;
	[_paneDocuments removeObjectAtIndex:index];
	if (index >= 0 && (NSUInteger)index < fractions.count) {
		[fractions removeObjectAtIndex:index];
	}
	if (fractions.count == _paneDocuments.count && fractions.count > 0) {
		NSInteger keep = MIN(index, (NSInteger)fractions.count - 1);
		fractions[keep] = @(fractions[keep].doubleValue + removed);
		[_splitHost setPaneCount:_paneDocuments.count];
		[_splitHost setFractions:fractions];
	} else {
		[_splitHost setPaneCount:_paneDocuments.count];
	}
	NSInteger focused = neighbor > index ? neighbor - 1 : neighbor;
	_activePane = MAX(0, MIN(focused, (NSInteger)_paneDocuments.count - 1));
	[self relayoutPaneEditors];
	id active = _paneDocuments[_activePane];
	if ([active isKindOfClass:[DocumentTab class]]) {
		[_tabs selectTabViewItem:[self itemForDocument:active]];
		[_window makeFirstResponder:((DocumentTab *)active).editor];
	}
	[_splitHost setActivePane:_activePane];
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)newDocument:(id)sender {
	(void)sender;
	DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
	_untitled++;
	document.displayName = [NSString stringWithFormat:@"new %ld", (long)_untitled];
	document.eolMode = SC_EOL_LF;
	[self addDocument:document];
	LangInfo *info = [_catalog languageNamed:@"normal"] ?: [LangInfo new];
	info.name = info.name ?: @"normal";
	info.lexer = info.lexer ?: @"null";
	[document applyLanguage:info dark:[self darkAppearance]];
	[document markClean];
}

- (BOOL)openArguments {
	BOOL opened = NO;
	NSArray<NSString *> *arguments = NSProcessInfo.processInfo.arguments;
	for (NSUInteger index = 1; index < arguments.count; index++) {
		NSString *argument = arguments[index];
		if ([argument hasPrefix:@"-"]) {
			continue;
		}
		if ([self openPath:argument]) {
			opened = YES;
		}
	}
	return opened;
}

- (BOOL)openRichDocumentAtPath:(NSString *)path kind:(NppOfficeKind)kind {
	NSString *error = nil;
	NSString *text = @"";
	NSView *surface = nil;
	if (kind == NppOfficeKindPDF) {
		surface = NppPDFViewForPath(path, &error);
		if (!surface) {
			[self alert:error ?: @"Could not open this PDF."];
			return NO;
		}
	} else {
		NppWordView *word = [[NppWordView alloc] initWithFrame:NSZeroRect];
		if (![word loadPath:path kind:kind error:&error]) {
			[self alert:error ?: @"Could not read this Word file."];
			return NO;
		}
		surface = word;
		text = word.plainText ?: @"";
	}
	DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
	document.path = path;
	document.displayName = path.lastPathComponent;
	document.encoding = kEncodingUTF8;
	document.manualLanguage = YES;
	document.language = kind == NppOfficeKindPDF ? @"PDF" : @"Word";
	NppOfficeRef *office = [NppOfficeRef new];
	office.kind = kind;
	office.view = surface;
	[self rememberOffice:office forDocument:document];
	[document setUtf8Text:text ?: @""];
	[document markClean];
	[self addDocument:document];
	if (kind != NppOfficeKindPDF) {
		[self lockOfficeText:document];
	}
	[self rememberPath:path];
	[self noteDiskRevisionForDocument:document];
	return YES;
}

- (void)installXlsx:(NSArray<NSArray<NSString *> *> *)rows sheets:(NSArray<NSString *> *)sheets sheet:(NSString *)sheet truncated:(BOOL)truncated document:(DocumentTab *)document {
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (!office) {
		office = [NppOfficeRef new];
		[self rememberOffice:office forDocument:document];
	}
	office.kind = NppOfficeKindXLSX;
	office.showTable = YES;
	NppCsvView *table = [self csvViewForDocument:document];
	__weak AppDelegate *weakSelf = self;
	__weak DocumentTab *weakDocument = document;
	table.onSheet = ^(NSString *name) {
		[weakSelf reloadXlsxDocument:weakDocument sheet:name];
	};
	[table loadRows:rows editable:NO sheets:sheets selectedSheet:sheet truncated:truncated];
	document.manualLanguage = YES;
	document.language = @"Excel";
	[self lockOfficeText:document];
}

- (BOOL)reloadXlsxDocument:(DocumentTab *)document sheet:(NSString *)sheet {
	if (!document.path.length) {
		return NO;
	}
	NSString *error = nil;
	NSArray<NSString *> *sheets = nil;
	NSArray<NSArray<NSString *> *> *rows = nil;
	BOOL truncated = NO;
	if (!NppXlsxLoad(document.path, sheet, &sheets, &rows, &truncated, &error)) {
		[self alert:error ?: @"Could not open this Excel file."];
		return NO;
	}
	NSString *selected = sheet.length ? sheet : sheets.firstObject;
	[self installXlsx:rows sheets:sheets sheet:selected truncated:truncated document:document];
	NSInteger pane = [self paneIndexOfDocument:document];
	if (pane != NSNotFound) {
		[self placeEditor:document inPane:pane];
		[_window makeFirstResponder:[self officeRefForDocument:document].view];
	}
	[self noteDiskRevisionForDocument:document];
	[self refreshStatus];
	return YES;
}

- (BOOL)openSpreadsheetAtPath:(NSString *)path {
	NSString *error = nil;
	NSArray<NSString *> *sheets = nil;
	NSArray<NSArray<NSString *> *> *rows = nil;
	BOOL truncated = NO;
	if (!NppXlsxLoad(path, nil, &sheets, &rows, &truncated, &error)) {
		[self alert:error ?: @"Could not open this Excel file."];
		return NO;
	}
	DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
	document.path = path;
	document.displayName = path.lastPathComponent;
	document.encoding = kEncodingUTF8;
	[self addDocument:document];
	[document setUtf8Text:@""];
	[document markClean];
	[self installXlsx:rows sheets:sheets sheet:sheets.firstObject truncated:truncated document:document];
	[self rememberPath:path];
	[self noteDiskRevisionForDocument:document];
	[self placeEditor:document inPane:[self paneIndexOfDocument:document]];
	[_window makeFirstResponder:[self officeRefForDocument:document].view];
	[self refreshStatus];
	return YES;
}

- (void)attachCsvDocument:(DocumentTab *)document {
	if (!document || NppOfficeKindForPath(document.path) != NppOfficeKindCSV) {
		return;
	}
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (!office) {
		office = [NppOfficeRef new];
		office.kind = NppOfficeKindCSV;
		office.showTable = YES;
		[self rememberOffice:office forDocument:document];
	}
	NppCsvView *table = [self csvViewForDocument:document];
	[table loadCsv:[document utf8Text] ?: @""];
	if (!table.fitsInTable) {
		office.showTable = NO;
		[self setStatusText:@"This CSV is too large for the table."];
	}
}

- (BOOL)openPath:(NSString *)path {
	NppOfficeKind kind = NppOfficeKindForPath(path);
	if (kind == NppOfficeKindPDF || kind == NppOfficeKindDOC || kind == NppOfficeKindDOCX) {
		return [self openRichDocumentAtPath:path kind:kind];
	}
	if (kind == NppOfficeKindXLSX) {
		return [self openSpreadsheetAtPath:path];
	}
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) {
		return NO;
	}
	DecodedBuffer decoded = DecodeBuffer((const uint8_t *)data.bytes, data.length);
	DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
	document.path = path;
	document.displayName = path.lastPathComponent;
	document.encoding = decoded.encoding;
	document.eolMode = decoded.eolMode;
	NSString *text = [[NSString alloc] initWithBytes:decoded.utf8.data() length:decoded.utf8.size() encoding:NSUTF8StringEncoding] ?: @"";
	[self addDocument:document];
	[document setUtf8Text:text];
	NppUserLanguage *user = [_userLanguages languageForPath:path];
	LangInfo *info = user ? [user langInfo] : [_catalog languageForPath:path sample:text];
	[document applyLanguage:info dark:[self darkAppearance]];
	[document markClean];
	[self rememberPath:path];
	[self noteDiskRevisionForDocument:document];
	BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:path];
	[document.editor setEditable:writable];
	if (kind == NppOfficeKindCSV) {
		[self attachCsvDocument:document];
		[self placeEditor:document inPane:[self paneIndexOfDocument:document]];
	}
	return YES;
}

- (BOOL)openDroppedPaths:(NSArray<NSString *> *)paths {
	if (!_window || !_documents) {
		if (!_pendingOpenPaths) {
			_pendingOpenPaths = [NSMutableArray array];
		}
		[_pendingOpenPaths addObjectsFromArray:paths];
		return paths.count > 0;
	}
	BOOL opened = NO;
	for (NSString *path in paths) {
		BOOL directory = NO;
		if (![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] || directory) {
			continue;
		}
		DocumentTab *existing = [self documentForPath:path];
		if (existing) {
			[self showDocument:existing inPane:_activePane];
			opened = YES;
			continue;
		}
		if ([self openPath:path]) {
			opened = YES;
		}
	}
	if (opened) {
		[NSApp activateIgnoringOtherApps:YES];
		[_window makeKeyAndOrderFront:nil];
	}
	return opened;
}

- (void)openDocument:(id)sender {
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.allowsMultipleSelection = YES;
	panel.canChooseFiles = YES;
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	for (NSURL *url in panel.URLs) {
		[self openPath:url.path];
	}
}

- (BOOL)saveDocument:(DocumentTab *)document toPath:(NSString *)path error:(NSString **)error {
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (NppOfficeKindIsViewOnly(office.kind)) {
		if (error) {
			*error = @"This file is only open for reading.";
		}
		return NO;
	}
	if (office.kind == NppOfficeKindCSV && office.showTable && [office.view isKindOfClass:[NppCsvView class]]) {
		[self pushOfficeCsv:[(NppCsvView *)office.view csvText] document:document];
		document.dirty = YES;
	}
	[document.editor message:SCI_CONVERTEOLS wParam:(uptr_t)document.eolMode lParam:0];
	NSString *text = [document utf8Text];
	const char *utf8Bytes = text.UTF8String ?: "";
	std::string utf8(utf8Bytes, strlen(utf8Bytes));
	std::string encoded;
	std::string failure;
	if (!EncodeBuffer(utf8, document.encoding, &encoded, &failure)) {
		if (error) {
			*error = @(failure.c_str());
		}
		return NO;
	}
	NSData *data = [NSData dataWithBytes:encoded.data() length:encoded.size()];
	[self backupFileIfNeeded:path];
	NSError *writeError = nil;
	if (![data writeToFile:path options:NSDataWritingAtomic error:&writeError]) {
		if (error) {
			*error = writeError.localizedDescription;
		}
		return NO;
	}
	document.path = path;
	document.displayName = path.lastPathComponent;
	if (!document.manualLanguage) {
		LangInfo *info = [_catalog languageForPath:path sample:[document utf8Text]];
		[document applyLanguage:info dark:[self darkAppearance]];
	}
	[document markClean];
	[self rememberPath:path];
	[self noteDiskRevisionForDocument:document];
	return YES;
}

- (void)saveDocument:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	if (document.path.length == 0) {
		[self saveDocumentAs:sender];
		return;
	}
	if (NppOfficeKindIsViewOnly([self officeRefForDocument:document].kind)) {
		[self alert:@"This file is only open for reading."];
		return;
	}
	NSString *error = nil;
	if (![self saveDocument:document toPath:document.path error:&error]) {
		[self alert:error ?: @"Save failed."];
	}
}

- (NSMenu *)encodingPopupMenu {
	NSMenu *menu = [NSMenu new];
	NSString *lastGroup = @"";
	for (int index = 0; index < NppEncodingCount(); index++) {
		const NppEncodingInfo *info = NppEncodingAt(index);
		NSString *group = @(info->group);
		if (group.length > 0 && ![group isEqualToString:lastGroup]) {
			NSMenuItem *header = [[NSMenuItem alloc] initWithTitle:group action:nil keyEquivalent:@""];
			header.enabled = NO;
			header.tag = -1;
			[menu addItem:header];
			lastGroup = group;
		}
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(info->name) action:nil keyEquivalent:@""];
		item.tag = info->id;
		[self applyMenuIcon:@"textformat" toItem:item];
		[menu addItem:item];
	}
	return menu;
}

- (NSView *)saveAsAccessoryForDocument:(DocumentTab *)document {
	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 460, 68)];
	NSTextField *typeLabel = [NSTextField labelWithString:@"File type:"];
	typeLabel.frame = NSMakeRect(0, 38, 78, 20);
	NSTextField *encodingLabel = [NSTextField labelWithString:@"Encoding:"];
	encodingLabel.frame = NSMakeRect(0, 8, 78, 20);
	NSPopUpButton *types = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(82, 34, 370, 26) pullsDown:NO];
	types.tag = 701;
	NSPopUpButton *encodings = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(82, 4, 370, 26) pullsDown:NO];
	encodings.tag = 702;
	encodings.menu = [self encodingPopupMenu];
	[encodings selectItemWithTag:document.encoding];
	if (!encodings.selectedItem || encodings.selectedItem.tag < 0) {
		[encodings selectItemWithTag:kEncodingUTF8];
	}

	NSMenuItem *allFiles = [[NSMenuItem alloc] initWithTitle:@"All files (*.*)" action:nil keyEquivalent:@""];
	[types.menu addItem:allFiles];
	NSString *currentExtension = document.displayName.pathExtension.lowercaseString;
	NSMenuItem *matchingType = allFiles;
	NSArray<LangInfo *> *languages = [[_catalog allLanguages] sortedArrayUsingComparator:^NSComparisonResult(LangInfo *left, LangInfo *right) {
		return [left.name localizedCaseInsensitiveCompare:right.name];
	}];
	for (LangInfo *info in languages) {
		if (info.extensions.count == 0) {
			continue;
		}
		NSMutableString *title = [NSMutableString stringWithFormat:@"%@ (", info.name];
		NSUInteger shown = MIN(info.extensions.count, (NSUInteger)4);
		for (NSUInteger index = 0; index < shown; index++) {
			if (index > 0) {
				[title appendString:@"; "];
			}
			[title appendFormat:@"*.%@", info.extensions[index]];
		}
		if (info.extensions.count > shown) {
			[title appendString:@"; …"];
		}
		[title appendString:@")"];
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:nil keyEquivalent:@""];
		item.representedObject = info.extensions;
		[types.menu addItem:item];
		for (NSString *extension in info.extensions) {
			if (currentExtension.length > 0 && [extension.lowercaseString isEqualToString:currentExtension]) {
				matchingType = item;
			}
		}
	}
	[types selectItem:matchingType];
	types.target = self;
	types.action = @selector(saveAsFileTypeChanged:);
	[accessory addSubview:typeLabel];
	[accessory addSubview:encodingLabel];
	[accessory addSubview:types];
	[accessory addSubview:encodings];
	return accessory;
}

- (void)saveAsFileTypeChanged:(NSPopUpButton *)sender {
	NSSavePanel *panel = (NSSavePanel *)sender.window;
	if (![panel isKindOfClass:[NSSavePanel class]]) {
		return;
	}
	NSArray *extensions = sender.selectedItem.representedObject;
	if (![extensions isKindOfClass:[NSArray class]] || extensions.count == 0) {
		return;
	}
	NSString *name = panel.nameFieldStringValue ?: @"";
	NSString *current = name.pathExtension.lowercaseString;
	for (NSString *extension in extensions) {
		if ([extension.lowercaseString isEqualToString:current]) {
			return;
		}
	}
	NSString *base = name.stringByDeletingPathExtension;
	if (base.length == 0) {
		base = name.length ? name : @"Untitled";
	}
	panel.nameFieldStringValue = [base stringByAppendingPathExtension:extensions.firstObject];
}

- (void)saveDocumentAs:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	if (NppOfficeKindIsViewOnly([self officeRefForDocument:document].kind)) {
		[self alert:@"This file is only open for reading."];
		return;
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	panel.nameFieldStringValue = document.displayName ?: @"Untitled.txt";
	if (document.path.length > 0) {
		panel.directoryURL = [NSURL fileURLWithPath:document.path.stringByDeletingLastPathComponent];
	}
	panel.accessoryView = [self saveAsAccessoryForDocument:document];
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	NSPopUpButton *encodings = [panel.accessoryView viewWithTag:702];
	if (encodings.selectedItem && encodings.selectedItem.tag >= 0) {
		document.encoding = (NppTextEncoding)encodings.selectedItem.tag;
	}
	NSString *error = nil;
	if (![self saveDocument:document toPath:panel.URL.path error:&error]) {
		[self alert:error ?: @"Save failed."];
	}
}

- (void)saveAllDocuments:(id)sender {
	DocumentTab *returnTo = [self currentDocument];
	for (DocumentTab *document in [_documents copy]) {
		if (!document.dirty && document.path.length > 0) {
			continue;
		}
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		[self saveDocument:sender];
		if (document.dirty) {
			break;
		}
	}
	NSTabViewItem *item = [self itemForDocument:returnTo];
	if (item) {
		[_tabs selectTabViewItem:item];
	}
	[self rebuildTabStrip];
}

- (BOOL)confirmClosingDocuments:(NSArray<DocumentTab *> *)documents grouped:(BOOL)grouped {
	if (_closingWithoutPrompt || !_settings.confirmClose || documents.count == 0) {
		return YES;
	}
	if (!grouped && documents.count < 2) {
		return YES;
	}
	NSMutableArray<NSString *> *lines = [NSMutableArray array];
	NSMutableArray<DocumentTab *> *dirty = [NSMutableArray array];
	for (DocumentTab *document in documents) {
		NSString *name = document.displayName.length ? document.displayName : @"Untitled";
		[lines addObject:document.dirty ? [name stringByAppendingString:@" — unsaved"] : name];
		if (document.dirty) {
			[dirty addObject:document];
		}
	}
	NSAlert *alert = [NSAlert new];
	NSString *singleName = documents.firstObject.displayName.length ? documents.firstObject.displayName : @"Untitled";
	alert.messageText = documents.count == 1
		? [NSString stringWithFormat:@"Close %@?", singleName]
		: [NSString stringWithFormat:@"Close %ld items?", (long)documents.count];
	NSString *list = [lines componentsJoinedByString:@"\n"];
	alert.informativeText = [list stringByAppendingString:@"\n\nYou can turn off these prompts in Preferences."];
	if (dirty.count > 0) {
		[alert addButtonWithTitle:@"Save"];
		[alert addButtonWithTitle:@"Don't Save"];
		[alert addButtonWithTitle:@"Cancel"];
	} else {
		[alert addButtonWithTitle:@"Close"];
		[alert addButtonWithTitle:@"Cancel"];
	}
	NSModalResponse response = [alert runModal];
	if (dirty.count == 0) {
		return response == NSAlertFirstButtonReturn;
	}
	if (response == NSAlertThirdButtonReturn || response == NSModalResponseCancel) {
		return NO;
	}
	if (response == NSAlertSecondButtonReturn) {
		_discardUnsavedSession = YES;
		return YES;
	}
	for (DocumentTab *document in dirty) {
		NSTabViewItem *item = [self itemForDocument:document];
		if (item) {
			[_tabs selectTabViewItem:item];
		}
		[self saveDocument:nil];
		if (document.dirty) {
			return NO;
		}
	}
	return YES;
}

- (void)closeDocument:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	if (document == _cloneSource) {
		[self dropClone];
	}
	if (![self confirmClosingDocuments:@[document] grouped:YES]) {
		_discardUnsavedSession = NO;
		return;
	}
	_discardUnsavedSession = NO;
	NSTabViewItem *item = [self itemForDocument:document];
	NSInteger pane = [self paneIndexOfDocument:document];
	[document.editor removeFromSuperview];
	[document setFileMonitoring:NO];
	[_documents removeObject:document];
	if (item) {
		[_tabs removeTabViewItem:item];
	}
	if (pane != NSNotFound) {
		NSMutableArray<DocumentTab *> *tabs = [self tabsForPane:pane];
		NSInteger closedIndex = [tabs indexOfObject:document];
		[tabs removeObject:document];
		_paneDocuments[pane] = [NSNull null];
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
		[slot removeEditorViews];
		if (tabs.count > 0) {
			NSInteger next = closedIndex == NSNotFound ? 0 : MIN(closedIndex, (NSInteger)tabs.count - 1);
			[self showDocument:tabs[next] inPane:pane];
			return;
		}
	}
	if (_documents.count == 0) {
		if (!_suppressEmptyDocument) {
			[self newDocument:nil];
		}
		return;
	}
	if (pane != NSNotFound && _paneDocuments.count > 1) {
		_activePane = pane;
		[self closeSplit:nil];
		return;
	}
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)rememberPath:(NSString *)path {
	if (path.length == 0) {
		return;
	}
	NSMutableArray *recent = [[[NSUserDefaults standardUserDefaults] arrayForKey:@"recentFiles"] mutableCopy] ?: [NSMutableArray array];
	[recent removeObject:path];
	[recent insertObject:path atIndex:0];
	while (recent.count > 10) {
		[recent removeLastObject];
	}
	[[NSUserDefaults standardUserDefaults] setObject:recent forKey:@"recentFiles"];
	if (_menuBar) {
		[self buildMenus];
	}
}

- (void)openRecent:(NSMenuItem *)sender {
	NSString *path = sender.representedObject;
	if ([path isKindOfClass:[NSString class]]) {
		[self openPath:path];
	}
}

- (void)closeAllDocuments:(id)sender {
	NSMutableArray<DocumentTab *> *documents = [NSMutableArray array];
	for (DocumentTab *document in _documents) {
		if (!document.pinned) {
			[documents addObject:document];
		}
	}
	if (documents.count == 0) {
		[self setStatusText:@"Pinned tabs stay open."];
		return;
	}
	if (![self confirmClosingDocuments:documents grouped:YES]) {
		_discardUnsavedSession = NO;
		return;
	}
	_discardUnsavedSession = NO;
	_closingWithoutPrompt = YES;
	for (DocumentTab *document in documents) {
		NSTabViewItem *item = [self itemForDocument:document];
		if (item) {
			[_tabs selectTabViewItem:item];
		}
		[self closeDocument:sender];
	}
	_closingWithoutPrompt = NO;
}

- (void)closeOtherDocuments:(id)sender {
	DocumentTab *keep = [self currentDocument];
	NSMutableArray<DocumentTab *> *closing = [NSMutableArray array];
	for (DocumentTab *document in _documents) {
		if (document != keep && !document.pinned) {
			[closing addObject:document];
		}
	}
	if (![self confirmClosingDocuments:closing grouped:YES]) {
		_discardUnsavedSession = NO;
		return;
	}
	_discardUnsavedSession = NO;
	_closingWithoutPrompt = YES;
	for (DocumentTab *document in closing) {
		NSTabViewItem *item = [self itemForDocument:document];
		if (item) {
			[_tabs selectTabViewItem:item];
		}
		[self closeDocument:sender];
	}
	_closingWithoutPrompt = NO;
	NSTabViewItem *item = [self itemForDocument:keep];
	if (item) {
		[_tabs selectTabViewItem:item];
	}
}

- (void)printDocument:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	NSTextView *view = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 468, 648)];
	view.string = [document utf8Text] ?: @"";
	view.font = [NSFont fontWithName:_settings.fontName ?: @"Menlo" size:11];
	NSPrintOperation *operation = [NSPrintOperation printOperationWithView:view];
	[operation runOperationModalForWindow:_window delegate:nil didRunSelector:NULL contextInfo:NULL];
}

- (void)copyFullPath:(id)sender {
	(void)sender;
	NSString *path = [self currentDocument].path ?: @"";
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:path forType:NSPasteboardTypeString];
	[self setStatusText:path.length ? path : @"This document has not been saved."];
}

- (void)copyFilename:(id)sender {
	(void)sender;
	NSString *name = [self currentDocument].displayName ?: @"";
	[NSPasteboard.generalPasteboard clearContents];
	[NSPasteboard.generalPasteboard setString:name forType:NSPasteboardTypeString];
}

- (void)columnEditor:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Column Editor";
	alert.informativeText = @"Inserts this text at the start of each selected line. With no selection, the current line is used.";
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"Insert"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] == NSAlertFirstButtonReturn) {
		NppPrefixSelectedLines(document.editor, field.stringValue);
	}
}

- (void)selectAndFindNext:(id)sender {
	DocumentTab *document = [self currentDocument];
	NSString *selected = [self selectedText];
	if (selected.length == 0) {
		return;
	}
	_findField.stringValue = selected;
	[self findNext:sender];
	(void)document;
}

- (void)selectTabAtOffset:(NSInteger)offset {
	NSArray<DocumentTab *> *tabs = [self tabsForPane:_activePane];
	if (tabs.count == 0) {
		return;
	}
	id visible = _paneDocuments[_activePane];
	NSInteger index = [visible isKindOfClass:[DocumentTab class]] ? [tabs indexOfObject:visible] : 0;
	if (index == NSNotFound) {
		index = 0;
	}
	index = (index + offset + (NSInteger)tabs.count) % (NSInteger)tabs.count;
	[self showDocument:tabs[index] inPane:_activePane];
}

- (void)nextTab:(id)sender {
	(void)sender;
	[self selectTabAtOffset:1];
}

- (void)previousTab:(id)sender {
	(void)sender;
	[self selectTabAtOffset:-1];
}

- (void)selectWindowDocument:(NSMenuItem *)sender {
	if (sender.tag >= 0 && sender.tag < (NSInteger)_tabs.numberOfTabViewItems) {
		DocumentTab *document = _tabs.tabViewItems[sender.tag].identifier;
		if ([document isKindOfClass:[DocumentTab class]]) {
			[self showDocument:document inPane:_activePane];
		}
	}
}

- (void)showSummary:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	NSString *text = [document utf8Text] ?: @"";
	long lines = [document.editor message:SCI_GETLINECOUNT];
	NSArray *words = [text componentsSeparatedByCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
	NSUInteger wordCount = 0;
	for (NSString *word in words) {
		if (word.length) {
			wordCount++;
		}
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = document.displayName ?: @"Summary";
	alert.informativeText = [NSString stringWithFormat:@"Lines: %ld\nCharacters: %lu\nWords: %lu\nLanguage: %@", lines, (unsigned long)text.length, (unsigned long)wordCount, document.language ?: @"Normal Text"];
	[alert runModal];
}

- (void)toggleLineNumbers:(id)sender {
	(void)sender;
	_settings.lineNumbers = !_settings.lineNumbers;
	[[self currentDocument] applySettings:_settings dark:[self darkAppearance]];
}

- (void)alert:(NSString *)message {
	NSAlert *alert = [NSAlert new];
	alert.messageText = NppL(message);
	[alert runModal];
}

- (SearchFlags)searchFlags {
	SearchFlags flags;
	flags.matchCase = _matchCase.state == NSControlStateValueOn;
	flags.wholeWord = _wholeWord.state == NSControlStateValueOn;
	flags.regex = _regex.state == NSControlStateValueOn;
	flags.dotMatchesNewline = _dotAll.state == NSControlStateValueOn;
	return flags;
}

- (void)hideFind:(id)sender {
	(void)sender;
	_workspace.findVisible = NO;
	[_workspace layoutPanes];
	DocumentTab *document = [self currentDocument];
	if (document.editor) {
		[_window makeFirstResponder:document.editor];
	}
}

- (BOOL)control:(NSControl *)control textView:(NSTextView *)textView doCommandBySelector:(SEL)command {
	(void)textView;
	if (command == @selector(cancelOperation:) && (control == _findField || control == _replaceField)) {
		[self hideFind:nil];
		return YES;
	}
	return NO;
}

- (void)showFind:(id)sender {
	(void)sender;
	if (_findField.stringValue.length == 0) {
		NSString *selected = [self selectedText];
		if (selected.length && [selected rangeOfString:@"\n"].location == NSNotFound) {
			_findField.stringValue = selected;
		}
	}
	_workspace.findVisible = YES;
	[_workspace layoutPanes];
	[self layoutFindBar];
	[_window makeFirstResponder:_findField];
}

- (void)showReplace:(id)sender {
	[self showFind:sender];
	[_window makeFirstResponder:_replaceField];
}

- (void)presentFindInFilesReplacing:(BOOL)replacing {
	DocumentTab *document = [self currentDocument];
	if (_filesDirectory.stringValue.length == 0) {
		_filesDirectory.stringValue = document.path.length ? document.path.stringByDeletingLastPathComponent : NSHomeDirectory();
	}
	if (_findField.stringValue.length) {
		_filesQuery.stringValue = _findField.stringValue;
	}
	if (replacing) {
		_filesReplace.stringValue = _replaceField.stringValue;
	}
	_workspace.resultsVisible = YES;
	[_workspace layoutPanes];
	[self layoutResultsPanel];
	[_window makeFirstResponder:replacing ? _filesReplace : _filesQuery];
}

- (void)showFindInFiles:(id)sender {
	(void)sender;
	[self presentFindInFilesReplacing:NO];
}

- (void)showReplaceInFiles:(id)sender {
	(void)sender;
	[self presentFindInFilesReplacing:YES];
}

- (void)hideFindInFiles:(id)sender {
	(void)sender;
	[self cancelFindInFiles:nil];
	_workspace.resultsVisible = NO;
	[_workspace layoutPanes];
}

- (void)browseFindDirectory:(id)sender {
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = NO;
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = NO;
	if (_filesDirectory.stringValue.length) {
		panel.directoryURL = [NSURL fileURLWithPath:_filesDirectory.stringValue];
	}
	if ([panel runModal] == NSModalResponseOK) {
		_filesDirectory.stringValue = panel.URL.path;
	}
}

- (SearchFlags)fileSearchFlags {
	SearchFlags flags;
	flags.matchCase = _filesCase.state == NSControlStateValueOn;
	flags.wholeWord = _filesWord.state == NSControlStateValueOn;
	flags.regex = _filesRegex.state == NSControlStateValueOn;
	flags.dotMatchesNewline = NO;
	return flags;
}

- (void)setFindSearchActive:(BOOL)active {
	_findCancel.hidden = !active;
	NSButton *replaceFiles = (NSButton *)[self chromeTagged:26 in:_resultsPanel];
	replaceFiles.enabled = !active;
	if (active) {
		[_findProgress startAnimation:nil];
	} else {
		[_findProgress stopAnimation:nil];
	}
	[self layoutResultsPanel];
}

- (NSString *)findProgressTextForPath:(NSString *)path scanned:(NSInteger)scanned hits:(NSInteger)hits finished:(BOOL)finished cancelled:(BOOL)cancelled limited:(BOOL)limited {
	if (!finished) {
		return [NSString stringWithFormat:@"%@ · %@ · %ld %@ · %ld %@", NppL(@"Searching"), path.length ? path : @"…", (long)scanned, NppL(@"files"), (long)hits, NppL(@"hits")];
	}
	NSString *lead = cancelled ? NppL(@"Stopped") : NppL(@"Finished");
	NSString *text = [NSString stringWithFormat:@"%@ · %ld %@ · %ld %@", lead, (long)hits, NppL(@"hits"), (long)scanned, NppL(@"files")];
	if (limited && !cancelled) {
		text = [text stringByAppendingFormat:@" · %@", NppL(@"Result limit reached")];
	}
	return text;
}

- (void)cancelFindInFiles:(id)sender {
	(void)sender;
	[_findToken cancel];
}

- (void)runFindInFiles:(id)sender {
	(void)sender;
	NSString *query = _filesQuery.stringValue;
	NSString *directory = _filesDirectory.stringValue;
	BOOL directoryExists = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&directoryExists];
	if (query.length == 0 || !directoryExists) {
		[self alert:@"Enter the text to find and a folder that exists."];
		return;
	}
	[_findToken cancel];
	[_hits removeAllObjects];
	[_resultsTable reloadData];
	[self setFindSearchActive:YES];
	NSString *filters = _filesFilters.stringValue;
	BOOL subfolders = _filesSubfolders.state == NSControlStateValueOn;
	SearchFlags flags = [self fileSearchFlags];
	__weak AppDelegate *weakSelf = self;
	__block NppFindScanToken *token = nil;
	token = NppStartFindInFiles(directory, query, filters, subfolders, flags, 1000, ^(NppFindScan *scan) {
		AppDelegate *strongSelf = weakSelf;
		if (!strongSelf || !scan || strongSelf->_findToken != token) {
			return;
		}
		if (scan.hits.count) {
			[strongSelf->_hits addObjectsFromArray:scan.hits];
			[strongSelf->_resultsTable reloadData];
		}
		NSString *progress = [strongSelf findProgressTextForPath:scan.path scanned:scan.scanned hits:strongSelf->_hits.count finished:scan.finished cancelled:scan.cancelled limited:scan.limited];
		strongSelf->_findProgressLabel.stringValue = progress;
		[strongSelf setStatusText:progress];
		if (!scan.finished) {
			return;
		}
		if (scan.error.length) {
			[strongSelf alert:scan.error];
		}
		[strongSelf sizeResultColumns];
		[strongSelf setFindSearchActive:NO];
		strongSelf->_findToken = nil;
	});
	_findToken = token;
}

- (DocumentTab *)documentForPath:(NSString *)path {
	if (path.length == 0) {
		return nil;
	}
	NSString *standard = path.stringByStandardizingPath;
	for (DocumentTab *document in _documents) {
		if (document.path.length == 0) {
			continue;
		}
		if ([document.path.stringByStandardizingPath isEqualToString:standard]) {
			return document;
		}
	}
	return nil;
}

- (void)runReplaceInFiles:(id)sender {
	(void)sender;
	NSString *query = _filesQuery.stringValue;
	NSString *directory = _filesDirectory.stringValue;
	BOOL directoryExists = NO;
	[[NSFileManager defaultManager] fileExistsAtPath:directory isDirectory:&directoryExists];
	if (query.length == 0 || !directoryExists) {
		[self alert:@"Enter the text to find and a folder that exists."];
		return;
	}
	NSString *replacement = _filesReplace.stringValue ?: @"";
	NSAlert *confirm = [NSAlert new];
	confirm.messageText = @"Replace in Files";
	confirm.informativeText = [NSString stringWithFormat:@"Replace \"%@\" with \"%@\" under %@?", query, replacement, directory];
	[confirm addButtonWithTitle:@"Replace"];
	[confirm addButtonWithTitle:@"Cancel"];
	if ([confirm runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	BOOL subfolders = _filesSubfolders.state == NSControlStateValueOn;
	NSString *directoryPrefix = [directory hasSuffix:@"/"] ? directory : [directory stringByAppendingString:@"/"];
	NSMutableArray<NSString *> *dirtyPaths = [NSMutableArray array];
	for (DocumentTab *document in _documents) {
		if (!document.dirty || document.path.length == 0 || !NppFileNameMatches(document.path.lastPathComponent, _filesFilters.stringValue)) {
			continue;
		}
		BOOL inside = subfolders ? [document.path hasPrefix:directoryPrefix] : [document.path.stringByDeletingLastPathComponent isEqualToString:directory];
		if (inside) {
			[dirtyPaths addObject:document.path];
		}
	}
	NppReplaceFilesResult *result = NppReplaceInFiles(directory, query, replacement, _filesFilters.stringValue, subfolders, [self fileSearchFlags], dirtyPaths);
	NSInteger editorReplacements = 0;
	NSInteger editorFiles = 0;
	for (NSString *path in dirtyPaths) {
		DocumentTab *document = [self documentForPath:path];
		long count = NppReplaceAll(document.editor, query, replacement, [self fileSearchFlags]);
		if (count > 0) {
			editorReplacements += count;
			editorFiles++;
		}
	}
	if (result.error.length && result.filesChanged == 0 && editorReplacements == 0) {
		[self alert:result.error];
		return;
	}
	for (NSString *path in result.paths) {
		if ([dirtyPaths containsObject:path]) {
			continue;
		}
		DocumentTab *document = [self documentForPath:path];
		[document reloadFromDiskScrollingToEnd:NO];
	}
	NSArray<NppFindHit *> *hits = NppFindInFiles(directory, query, _filesFilters.stringValue, subfolders, [self fileSearchFlags], 1000);
	[_hits removeAllObjects];
	[_hits addObjectsFromArray:hits];
	[_resultsTable reloadData];
	[self sizeResultColumns];
	[self setStatusText:[NSString stringWithFormat:@"Replace in Files: %ld replacement(s) in %ld file(s).%@", (long)(result.replacements + editorReplacements), (long)(result.filesChanged + editorFiles), result.error.length ? [@" " stringByAppendingString:result.error] : @""]];
}

- (void)closeSearchHit:(id)sender {
	(void)sender;
	NSInteger row = _resultsTable.clickedRow;
	if (row < 0) {
		row = _resultsTable.selectedRow;
	}
	if (row < 0 || row >= (NSInteger)_hits.count) {
		return;
	}
	NSString *path = _hits[row].path ?: @"";
	DocumentTab *document = path.length ? [self documentForPath:path] : nil;
	if (document) {
		NSTabViewItem *item = [self itemForDocument:document];
		if (item) {
			[_tabs selectTabViewItem:item];
		}
		[self closeDocument:nil];
		if ([self documentForPath:path]) {
			return;
		}
	}
	[_hits removeObjectAtIndex:(NSUInteger)row];
	[_resultsTable reloadData];
	[self sizeResultColumns];
}

- (void)openSearchHit:(id)sender {
	(void)sender;
	NSInteger clickedColumn = _resultsTable.clickedColumn;
	if (clickedColumn >= 0 && clickedColumn < (NSInteger)_resultsTable.tableColumns.count) {
		NSTableColumn *column = _resultsTable.tableColumns[clickedColumn];
		if ([column.identifier isEqualToString:@"close"]) {
			return;
		}
	}
	NSInteger row = _resultsTable.clickedRow;
	if (row < 0) {
		row = _resultsTable.selectedRow;
	}
	if (row < 0 || row >= (NSInteger)_hits.count) {
		return;
	}
	NppFindHit *hit = _hits[row];
	DocumentTab *document = nil;
	for (DocumentTab *existing in _documents) {
		if (hit.path.length && ([existing.path isEqualToString:hit.path] || [existing.displayName isEqualToString:hit.path])) {
			document = existing;
			break;
		}
	}
	if (!document) {
		if (![self openPath:hit.path]) {
			return;
		}
		document = [self currentDocument];
	} else {
		[self showDocument:document inPane:_activePane];
	}
	long lineStart = [document.editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)MAX(0, hit.line - 1) lParam:0];
	if (hit.byteLength > 0) {
		long start = lineStart + (long)hit.byteOffset;
		long end = start + (long)hit.byteLength;
		[document.editor message:SCI_SETSEL wParam:(uptr_t)start lParam:end];
	} else {
		[document.editor message:SCI_GOTOLINE wParam:(uptr_t)MAX(0, hit.line - 1) lParam:0];
	}
	[document.editor message:SCI_SCROLLCARET];
	[_window makeFirstResponder:document.editor];
}

- (BOOL)tableView:(NSTableView *)tableView shouldTrackCell:(NSCell *)cell forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	(void)tableView;
	(void)cell;
	(void)row;
	return [tableColumn.identifier isEqualToString:@"close"];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	if (tableView == _quickOpenTable) {
		return (NSInteger)_quickOpenRows.count;
	}
	if (tableView == _outlineTable) {
		return (NSInteger)_outlineRows.count;
	}
	if (tableView == _shortcutTable) {
		return (NSInteger)_shortcutRows.count;
	}
	if (tableView == _clipboardTable) {
		return (NSInteger)_clips.items.count;
	}
	if (tableView == _snippetTable) {
		return (NSInteger)_snippets.snippets.count;
	}
	if (tableView == _languageTable) {
		return (NSInteger)_userLanguages.languages.count;
	}
	if (tableView == _folderOutline) {
		return 0;
	}
	return (NSInteger)_hits.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
	if (tableView == _outlineTable) {
		if (row < 0 || row >= (NSInteger)_outlineRows.count) {
			return @"";
		}
		NppSymbol *symbol = _outlineRows[row];
		return [column.identifier isEqualToString:@"line"] ? [NSString stringWithFormat:@"%ld", (long)symbol.line] : symbol.name;
	}
	if (tableView == _shortcutTable) {
		if (row < 0 || row >= (NSInteger)_shortcutRows.count) {
			return @"";
		}
		return _shortcutRows[row][column.identifier] ?: @"";
	}
	if (tableView == _clipboardTable) {
		if (row < 0 || row >= (NSInteger)_clips.items.count) {
			return @"";
		}
		NSString *text = _clips.items[row];
		NSString *line = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]].firstObject ?: text;
		return line.length > 80 ? [[line substringToIndex:80] stringByAppendingString:@"…"] : line;
	}
	if (tableView == _snippetTable) {
		if (row < 0 || row >= (NSInteger)_snippets.snippets.count) {
			return @"";
		}
		return _snippets.snippets[row][column.identifier] ?: @"";
	}
	if (tableView == _languageTable) {
		if (row < 0 || row >= (NSInteger)_userLanguages.languages.count) {
			return @"";
		}
		NppUserLanguage *language = _userLanguages.languages[row];
		if ([column.identifier isEqualToString:@"extensions"]) return language.extensions;
		if ([column.identifier isEqualToString:@"keywords"]) return language.keywords;
		if ([column.identifier isEqualToString:@"lexer"]) return language.lexer;
		return language.name;
	}
	if (tableView == _quickOpenTable) {
		if (row < 0 || row >= (NSInteger)_quickOpenRows.count) {
			return @"";
		}
		NSDictionary *entry = _quickOpenRows[row];
		return [column.identifier isEqualToString:@"where"] ? entry[@"where"] : entry[@"name"];
	}
	if (row < 0 || row >= (NSInteger)_hits.count) {
		return @"";
	}
	NppFindHit *hit = _hits[row];
	if ([column.identifier isEqualToString:@"close"]) {
		return @"×";
	}
	if ([column.identifier isEqualToString:@"line"]) {
		return [NSString stringWithFormat:@"%ld", (long)hit.line];
	}
	if ([column.identifier isEqualToString:@"text"]) {
		return hit.lineText;
	}
	return hit.path ?: @"";
}

- (NSString *)tableView:(NSTableView *)tableView toolTipForCell:(NSCell *)cell rect:(NSRectPointer)rect tableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row mouseLocation:(NSPoint)mouseLocation {
	(void)tableView;
	(void)cell;
	(void)rect;
	(void)mouseLocation;
	if (tableView != _resultsTable) {
		return @"";
	}
	if ([tableColumn.identifier isEqualToString:@"close"]) {
		return @"Close";
	}
	if (row < 0 || row >= (NSInteger)_hits.count) {
		return @"";
	}
	NppFindHit *hit = _hits[row];
	return [NSString stringWithFormat:@"%@:%ld", hit.path, (long)hit.line];
}

- (void)sizeResultColumns {
	NSTableColumn *pathColumn = [_resultsTable tableColumnWithIdentifier:@"file"];
	NSTableColumn *textColumn = [_resultsTable tableColumnWithIdentifier:@"text"];
	NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]};
	CGFloat pathWidth = 160;
	CGFloat textWidth = 160;
	for (NppFindHit *hit in _hits) {
		pathWidth = MAX(pathWidth, ceil([(hit.path ?: @"") sizeWithAttributes:attributes].width) + 28);
		textWidth = MAX(textWidth, ceil([(hit.lineText ?: @"") sizeWithAttributes:attributes].width) + 28);
	}
	pathColumn.width = MIN(pathWidth, 4000);
	textColumn.width = MIN(textWidth, 4000);
	[_resultsScroll reflectScrolledClipView:_resultsScroll.contentView];
}

- (void)reloadFromDisk:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document.path.length) {
		[self alert:@"This document has not been saved."];
		return;
	}
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (office.kind == NppOfficeKindPDF) {
		NSString *error = nil;
		if (!NppReloadPDFView(office.view, document.path, &error)) {
			[self alert:error ?: @"Could not open this PDF."];
		}
		[self noteDiskRevisionForDocument:document];
		return;
	}
	if (office.kind == NppOfficeKindXLSX) {
		[self reloadXlsxDocument:document sheet:[(NppCsvView *)office.view selectedSheet]];
		return;
	}
	if (office.kind == NppOfficeKindDOC || office.kind == NppOfficeKindDOCX) {
		NppWordView *word = [office.view isKindOfClass:[NppWordView class]] ? (NppWordView *)office.view : nil;
		if (!word) {
			word = [[NppWordView alloc] initWithFrame:NSZeroRect];
			office.view = word;
		}
		NSString *error = nil;
		if (![word loadPath:document.path kind:office.kind error:&error]) {
			[self alert:error ?: @"Could not read this Word file."];
			return;
		}
		[document.editor setEditable:YES];
		[document.editor message:SCI_SETREADONLY wParam:0 lParam:0];
		[document setUtf8Text:word.plainText ?: @""];
		[self lockOfficeText:document];
		NSInteger pane = [self paneIndexOfDocument:document];
		if (pane != NSNotFound) {
			[self placeEditor:document inPane:pane];
		}
		[self noteDiskRevisionForDocument:document];
		return;
	}
	[document reloadFromDiskScrollingToEnd:NO];
	if (office.kind == NppOfficeKindCSV && office.showTable) {
		[(NppCsvView *)office.view loadCsv:[document utf8Text] ?: @""];
	}
	[self noteDiskRevisionForDocument:document];
}

- (void)toggleMonitoring:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document.path.length) {
		[self alert:@"Save the document before monitoring it."];
		return;
	}
	if (document.dirty) {
		[self alert:@"The document is modified. Save it before monitoring it."];
		return;
	}
	BOOL enable = !document.fileMonitoring;
	[document setFileMonitoring:enable];
	if (!enable) {
		[self noteDiskRevisionForDocument:document];
	}
	[self setStatusText:enable ? @"Monitoring (tail -f). New file content is appended and the caret follows the end." : @"Monitoring stopped."];
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)selectTabForContext:(NSInteger)index {
	if (index >= 0 && index < (NSInteger)_tabs.numberOfTabViewItems) {
		DocumentTab *document = _tabs.tabViewItems[index].identifier;
		if ([document isKindOfClass:[DocumentTab class]]) {
			[self showDocument:document inPane:_activePane];
		}
	}
}

- (NSMenu *)editorContextMenu {
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Editor"];
	DisableKeyEquivalentSearch(menu);
	[menu addItem:[self item:@"Undo" action:@selector(undo:) command:@"undo"]];
	[menu addItem:[self item:@"Redo" action:@selector(redo:) command:@"redo"]];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Cut" action:@selector(cut:) command:nil]];
	[menu addItem:[self item:@"Copy" action:@selector(copy:) command:nil]];
	[menu addItem:[self item:@"Paste" action:@selector(paste:) command:nil]];
	[menu addItem:[self item:@"Delete" action:@selector(deleteSelection:) command:nil]];
	[menu addItem:[self item:@"Select All" action:@selector(selectAll:) command:nil]];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self actionItem:@"UPPERCASE" action:@"upper"]];
	[menu addItem:[self actionItem:@"lowercase" action:@"lower"]];
	[menu addItem:[self actionItem:@"Toggle Line Comment" action:@"comment"]];
	[menu addItem:[self actionItem:@"Duplicate Current Line" action:@"duplicate"]];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Find…" action:@selector(showFind:) command:@"find"]];
	[menu addItem:[self item:@"Replace…" action:@selector(showReplace:) command:@"replace"]];
	[menu addItem:[self item:@"Reveal in Finder" action:@selector(revealInFinder:) command:nil]];
	[menu addItem:[self actionItem:@"Toggle Bookmark" action:@"bookmark"]];
	[menu addItem:[self item:@"Monitoring (tail -f)" action:@selector(toggleMonitoring:) command:nil]];
	if (_plugins.count) {
		[menu addItem:[NSMenuItem separatorItem]];
		for (NSDictionary *plugin in _plugins) {
			const NppMacCommand *commands = (const NppMacCommand *)[plugin[@"commands"] pointerValue];
			int count = [plugin[@"count"] intValue];
			for (int index = 0; index < count; index++) {
				NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(commands[index].title ?: "Command") action:@selector(runPluginCommand:) keyEquivalent:@""];
				item.target = self;
				item.representedObject = @[plugin, @(index)];
				[self applyMenuIcon:@"puzzlepiece" toItem:item];
				[menu addItem:item];
			}
		}
	}
	return menu;
}

- (NSMenu *)tabContextMenu {
	DocumentTab *document = [self currentDocument];
	NSMenu *menu = [[NSMenu alloc] initWithTitle:@"Tab"];
	DisableKeyEquivalentSearch(menu);
	[menu addItem:[self item:@"Close" action:@selector(closeDocument:) command:@"close"]];
	[menu addItem:[self item:@"Close All but This" action:@selector(closeOtherDocuments:) command:nil]];
	[menu addItem:[self item:document.pinned ? @"Unpin Tab" : @"Pin Tab" action:@selector(togglePin:) command:@"pin"]];
	[menu addItem:[self item:@"Clone Beside" action:@selector(cloneBeside:) command:@"clone"]];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Save" action:@selector(saveDocument:) command:@"save"]];
	[menu addItem:[self item:@"Reload from Disk" action:@selector(reloadFromDisk:) command:nil]];
	NSMenuItem *tail = [self item:document.fileMonitoring ? @"Stop tail -f" : @"Start tail -f" action:@selector(toggleMonitoring:) command:nil];
	tail.state = document.fileMonitoring ? NSControlStateValueOn : NSControlStateValueOff;
	[menu addItem:tail];
	[menu addItem:[NSMenuItem separatorItem]];
	NSInteger tabPane = [self paneIndexOfDocument:document];
	NSMenuItem *splitLeft = [self item:@"Split Left" action:@selector(splitTabLeft:) command:nil];
	NSMenuItem *splitRight = [self item:@"Split Right" action:@selector(splitTabRight:) command:nil];
	splitLeft.enabled = [self canSplitDocument:document besidePane:tabPane onRight:NO];
	splitRight.enabled = [self canSplitDocument:document besidePane:tabPane onRight:YES];
	[menu addItem:splitLeft];
	[menu addItem:splitRight];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Copy Full File Path" action:@selector(copyFullPath:) command:nil]];
	[menu addItem:[self item:@"Copy Filename" action:@selector(copyFilename:) command:nil]];
	NSMenuItem *reveal = [self item:@"Reveal in Finder" action:@selector(revealInFinder:) command:nil];
	reveal.enabled = document.path.length > 0;
	[menu addItem:reveal];
	[menu addItem:[self item:@"Print…" action:@selector(printDocument:) command:nil]];
	[menu addItem:[self actionItem:@"Read-Only" action:@"readonly"]];
	return menu;
}

- (void)attachEditorMenu:(DocumentTab *)document {
	[document.editor message:SCI_USEPOPUP wParam:0 lParam:0];
	document.editor.menu = [self editorContextMenu];
}

- (void)deleteSelection:(id)sender {
	(void)sender;
	[[self activeEditor] message:SCI_CLEAR];
}

- (void)goToLine:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Go to line";
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 180, 24)];
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"Go"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	long line = field.stringValue.integerValue;
	if (line < 1) {
		return;
	}
	[document.editor message:SCI_GOTOLINE wParam:(uptr_t)(line - 1) lParam:0];
	[document.editor message:SCI_SCROLLCARET];
}

- (void)goToMatchingBrace:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	long position = [document.editor message:SCI_GETCURRENTPOS];
	long match = [document.editor message:SCI_BRACEMATCH wParam:(uptr_t)position lParam:0];
	if (match < 0 && position > 0) {
		match = [document.editor message:SCI_BRACEMATCH wParam:(uptr_t)(position - 1) lParam:0];
	}
	if (match >= 0) {
		[document.editor message:SCI_GOTOPOS wParam:(uptr_t)match lParam:0];
		[document.editor message:SCI_SCROLLCARET];
	}
}

- (void)toggleWrap:(id)sender {
	(void)sender;
	_settings.wrap = !_settings.wrap;
	[[self currentDocument] applySettings:_settings dark:[self darkAppearance]];
	[self updateSplitWrapping];
	[self setStatusText:_settings.wrap ? @"Word wrap on." : @"Word wrap off."];
}

- (void)toggleWhitespace:(id)sender {
	(void)sender;
	_settings.showWhitespace = !_settings.showWhitespace;
	[[self currentDocument] applySettings:_settings dark:[self darkAppearance]];
}

- (void)toggleAlwaysOnTop:(id)sender {
	(void)sender;
	_window.level = _window.level == NSFloatingWindowLevel ? NSNormalWindowLevel : NSFloatingWindowLevel;
}

- (void)findNext:(id)sender {
	(void)sender;
	_workspace.findVisible = YES;
	[_workspace layoutPanes];
	long found = NppFind([self activeEditor], _findField.stringValue, true, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self noteSearch:_findField.stringValue inEditor:[self activeEditor]];
	[self setStatusText:found < 0 ? @"No match." : @"Match found."];
}

- (void)findPrevious:(id)sender {
	(void)sender;
	long found = NppFind([self activeEditor], _findField.stringValue, false, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self noteSearch:_findField.stringValue inEditor:[self activeEditor]];
	[self setStatusText:found < 0 ? @"No match." : @"Match found."];
}

- (void)replaceNext:(id)sender {
	(void)sender;
	long found = NppReplace([self activeEditor], _findField.stringValue, _replaceField.stringValue, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self setStatusText:found < 0 ? @"No match." : @"Replaced."];
}

- (void)replaceAll:(id)sender {
	(void)sender;
	long count = NppReplaceAll([self activeEditor], _findField.stringValue, _replaceField.stringValue, [self searchFlags]);
	[self setStatusText:[NSString stringWithFormat:@"Replaced %ld.", count]];
}

- (void)rememberClipboardText {
	NSString *text = [NSPasteboard.generalPasteboard stringForType:NSPasteboardTypeString];
	[_clips remember:text];
	if (_clipboardTable) {
		[_clipboardTable reloadData];
	}
}
- (void)undo:(id)sender { (void)sender; [[self activeEditor] message:SCI_UNDO]; }
- (void)redo:(id)sender { (void)sender; [[self activeEditor] message:SCI_REDO]; }
- (void)cut:(id)sender { (void)sender; [[self activeEditor] message:SCI_CUT]; [self rememberClipboardText]; }
- (void)copy:(id)sender {
	(void)sender;
	NSView *surface = [self officeShowsSurface:[self currentDocument]] ? [self officeRefForDocument:[self currentDocument]].view : nil;
	if (surface && [self officeRefForDocument:[self currentDocument]].kind == NppOfficeKindPDF) {
		[NSApp sendAction:@selector(copy:) to:surface from:sender];
		return;
	}
	id responder = _window.firstResponder;
	if ([responder isKindOfClass:[NSText class]]) {
		[responder copy:sender];
		[self rememberClipboardText];
		return;
	}
	[[self activeEditor] message:SCI_COPY];
	[self rememberClipboardText];
}
- (void)paste:(id)sender { (void)sender; [[self activeEditor] message:SCI_PASTE]; }
- (void)selectAll:(id)sender {
	(void)sender;
	NSView *surface = [self officeShowsSurface:[self currentDocument]] ? [self officeRefForDocument:[self currentDocument]].view : nil;
	if (surface && [self officeRefForDocument:[self currentDocument]].kind == NppOfficeKindPDF) {
		[NSApp sendAction:@selector(selectAll:) to:surface from:sender];
		return;
	}
	id responder = _window.firstResponder;
	if ([responder isKindOfClass:[NSText class]]) {
		[responder selectAll:sender];
		return;
	}
	[[self activeEditor] message:SCI_SELECTALL];
}
- (id)zoomTargetUnderHit:(NSView *)hit {
	for (NSView *view = hit; view; view = view.superview) {
		if ([view isKindOfClass:[PDFView class]] || [view isKindOfClass:[NppWordView class]] || [view isKindOfClass:[NppCsvView class]] || [view isKindOfClass:[WKWebView class]] || [view isKindOfClass:[ScintillaView class]]) {
			return view;
		}
	}
	DocumentTab *document = [self currentDocument];
	if ([self officeShowsSurface:document]) {
		NSView *surface = [self officeRefForDocument:document].view;
		if (surface) {
			return surface;
		}
	}
	return [self activeEditor];
}

- (NSInteger)nudgeVisibleZoom:(NSInteger)direction target:(id)target {
	if (!target) {
		return 100;
	}
	NSInteger percent = 100;
	if ([target isKindOfClass:[ScintillaView class]]) {
		ScintillaView *editor = target;
		if (direction > 0) {
			[editor message:SCI_ZOOMIN];
		} else if (direction < 0) {
			[editor message:SCI_ZOOMOUT];
		} else {
			[editor message:SCI_SETZOOM wParam:0 lParam:0];
		}
		int base = MAX(6, _settings.fontSize);
		long zoom = [editor message:SCI_GETZOOM];
		percent = (NSInteger)llround(100.0 * (base + zoom) / (double)base);
	} else if ([target isKindOfClass:[PDFView class]]) {
		PDFView *pdf = target;
		if (direction == 0) {
			pdf.autoScales = YES;
		} else {
			CGFloat current = pdf.scaleFactor;
			if (current < 0.05) {
				current = 1;
			}
			pdf.autoScales = NO;
			CGFloat next = current * (direction > 0 ? 1.15 : (1.0 / 1.15));
			CGFloat minScale = pdf.minScaleFactor < 0.05 ? 0.15 : pdf.minScaleFactor;
			CGFloat maxScale = pdf.maxScaleFactor < 1 ? 6 : pdf.maxScaleFactor;
			pdf.scaleFactor = MIN(maxScale, MAX(minScale, next));
		}
		percent = (NSInteger)llround(MAX(pdf.scaleFactor, 0.01) * 100.0);
	} else if ([target isKindOfClass:[NppWordView class]]) {
		percent = [(NppWordView *)target adjustZoom:direction];
	} else if ([target isKindOfClass:[NppCsvView class]]) {
		percent = [(NppCsvView *)target adjustZoom:direction];
	} else if ([target isKindOfClass:[WKWebView class]]) {
		WKWebView *web = target;
		web.allowsMagnification = YES;
		if (direction == 0) {
			web.magnification = 1;
		} else {
			CGFloat next = web.magnification * (direction > 0 ? 1.15 : (1.0 / 1.15));
			web.magnification = MIN(4, MAX(0.4, next));
		}
		percent = (NSInteger)llround(web.magnification * 100.0);
	}
	[self setStatusText:[NSString stringWithFormat:@"Zoom %ld%%", (long)percent]];
	return percent;
}

- (void)zoomIn:(id)sender {
	(void)sender;
	[self nudgeVisibleZoom:1 target:[self zoomTargetUnderHit:nil]];
}
- (void)zoomOut:(id)sender {
	(void)sender;
	[self nudgeVisibleZoom:-1 target:[self zoomTargetUnderHit:nil]];
}

- (NSEvent *)handleCommandZoom:(NSEvent *)event {
	if (event.window != _window || (event.modifierFlags & NSEventModifierFlagCommand) == 0) {
		_cmdZoomAccum = 0;
		return event;
	}
	NSView *content = event.window.contentView;
	NSView *hit = [content hitTest:[content convertPoint:event.locationInWindow fromView:nil]];
	id target = [self zoomTargetUnderHit:hit];
	if (!target) {
		return event;
	}
	NSInteger steps = 0;
	if (event.hasPreciseScrollingDeltas) {
		_cmdZoomAccum += event.scrollingDeltaY;
		while (_cmdZoomAccum >= 12) {
			steps++;
			_cmdZoomAccum -= 12;
		}
		while (_cmdZoomAccum <= -12) {
			steps--;
			_cmdZoomAccum += 12;
		}
		if (event.phase == NSEventPhaseEnded || event.phase == NSEventPhaseCancelled) {
			_cmdZoomAccum = 0;
		}
	} else if (event.scrollingDeltaY > 0) {
		steps = 1;
	} else if (event.scrollingDeltaY < 0) {
		steps = -1;
	}
	NSInteger direction = steps > 0 ? 1 : -1;
	for (NSInteger index = 0; index < labs(steps); index++) {
		[self nudgeVisibleZoom:direction target:target];
	}
	return nil;
}
- (void)foldAll:(id)sender { (void)sender; [[self activeEditor] message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT lParam:0]; }
- (void)unfoldAll:(id)sender { (void)sender; [[self activeEditor] message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND lParam:0]; }

- (void)chooseEncoding:(NSMenuItem *)sender {
	DocumentTab *document = [self currentDocument];
	if (!document || sender.tag < 0) {
		return;
	}
	NppTextEncoding encoding = (NppTextEncoding)sender.tag;
	if (document.path.length > 0 && !document.dirty) {
		NSData *data = [NSData dataWithContentsOfFile:document.path];
		DecodedBuffer decoded;
		std::string failure;
		if (data && DecodeBufferAs(static_cast<const uint8_t *>(data.bytes), data.length, encoding, &decoded, &failure)) {
			NSString *text = [[NSString alloc] initWithBytes:decoded.utf8.data() length:decoded.utf8.size() encoding:NSUTF8StringEncoding] ?: @"";
			[document setUtf8Text:text];
			document.encoding = encoding;
			document.eolMode = decoded.eolMode;
			[document.editor message:SCI_SETEOLMODE wParam:(uptr_t)document.eolMode lParam:0];
			[self documentTabDidChange:document];
			return;
		}
		if (data) {
			[self alert:@(failure.c_str())];
			return;
		}
	}
	document.encoding = encoding;
	document.dirty = YES;
	[self documentTabDidChange:document];
}

- (void)chooseEOL:(NSMenuItem *)sender {
	DocumentTab *document = [self currentDocument];
	document.eolMode = (int)sender.tag;
	[document.editor message:SCI_SETEOLMODE wParam:(uptr_t)document.eolMode lParam:0];
	[document.editor message:SCI_CONVERTEOLS wParam:(uptr_t)document.eolMode lParam:0];
	[self refreshStatus];
}

- (void)chooseLanguage:(NSMenuItem *)sender {
	DocumentTab *document = [self currentDocument];
	LangInfo *info = [_catalog languageNamed:sender.representedObject];
	if (!document || !info) {
		return;
	}
	document.manualLanguage = YES;
	[document applyLanguage:info dark:[self darkAppearance]];
}

- (void)chooseAutomaticLanguage:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	document.manualLanguage = NO;
	NppUserLanguage *user = [_userLanguages languageForPath:document.path];
	LangInfo *info = user ? [user langInfo] : [_catalog languageForPath:document.path sample:[document utf8Text]];
	[document applyLanguage:info dark:[self darkAppearance]];
}

- (void)toggleMacroRecording:(id)sender {
	if (_macro.recording) {
		[self stopMacro:sender];
	} else {
		[self startMacro:sender];
	}
}

- (void)startMacro:(id)sender {
	(void)sender;
	[_macro start];
	[self setStatusText:@"Recording macro."];
	[self refreshStatus];
}

- (void)stopMacro:(id)sender {
	(void)sender;
	[_macro stop];
	NSError *error = nil;
	[_macro saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"macro.json"] error:&error];
	[self setStatusText:[NSString stringWithFormat:@"Macro stopped (%lu steps).", (unsigned long)_macro.steps.count]];
	[self refreshStatus];
}

- (void)saveMacroNamed:(id)sender {
	(void)sender;
	if (_macro.steps.count == 0) {
		[self alert:@"Record a macro before saving it."];
		return;
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Save Current Macro";
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 220, 24)];
	field.stringValue = @"Macro";
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn || field.stringValue.length == 0) {
		return;
	}
	[_macro rememberCurrentAs:field.stringValue];
	NSError *error = nil;
	[_macro saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"macro.json"] error:&error];
	[self buildMenus];
	[self setStatusText:[NSString stringWithFormat:@"Saved macro \"%@\".", field.stringValue]];
}

- (void)playSavedMacro:(NSMenuItem *)sender {
	if (![_macro activateSaved:sender.representedObject]) {
		return;
	}
	[self playMacro:sender];
}

- (void)playMacroMultiple:(id)sender {
	if (_macro.steps.count == 0) {
		[self alert:@"There is no recorded macro to play."];
		return;
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Run a Macro Multiple Times";
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 80, 24)];
	field.stringValue = @"1";
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"Run"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	NSInteger times = MAX(1, MIN(10000, field.stringValue.integerValue));
	for (NSInteger index = 0; index < times; index++) {
		[self playMacro:sender];
	}
}

- (void)playMacro:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document || _macro.steps.count == 0 || _macro.recording) {
		return;
	}
	document.suppressMacro = YES;
	ScintillaView *editor = document.editor;
	[editor message:SCI_BEGINUNDOACTION];
	NSInteger base = _macro.steps.firstObject.position;
	NSInteger caret = [editor message:SCI_GETCURRENTPOS];
	NSInteger delta = caret - base;
	for (MacroStep *step in _macro.steps) {
		NSInteger position = MAX(0, step.position + delta);
		const char *bytes = step.text.UTF8String ?: "";
		if (step.insert) {
			[editor message:SCI_INSERTTEXT wParam:(uptr_t)position lParam:(sptr_t)bytes];
		} else {
			[editor message:SCI_DELETERANGE wParam:(uptr_t)position lParam:(sptr_t)strlen(bytes)];
		}
	}
	[editor message:SCI_ENDUNDOACTION];
	document.suppressMacro = NO;
	[self setStatusText:@"Macro played."];
}

- (NSString *)selectedText {
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return @"";
	}
	ScintillaView *editor = [self activeEditor] ?: document.editor;
	long start = [editor message:SCI_GETSELECTIONSTART];
	long end = [editor message:SCI_GETSELECTIONEND];
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

- (void)replaceSelection:(NSString *)text {
	const char *bytes = text.UTF8String ?: "";
	[[self activeEditor] message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
}

- (void)insertText:(NSString *)text {
	[self replaceSelection:text];
}

- (void)replaceDocumentText:(NSString *)text {
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	[document setUtf8Text:text ?: @""];
	document.dirty = YES;
	[self documentTabDidChange:document];
}

- (void)setStatusText:(NSString *)text {
	_statusOverride = text.length ? NppL(text) : text;
	[self refreshStatus];
}

- (void)updateTailButton {
	if (!_tailButton) {
		return;
	}
	BOOL on = [self currentDocument].fileMonitoring;
	_tailButton.state = on ? NSControlStateValueOn : NSControlStateValueOff;
	_tailButton.toolTip = on ? NppL(@"Stop tail -f") : NppL(@"Start tail -f");
}

- (void)refreshStatus {
	[self updateTailButton];
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	NSTabViewItem *item = _tabs.selectedTabViewItem;
	item.label = document.title;
	long position = [document.editor message:SCI_GETCURRENTPOS];
	long line = [document.editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)position lParam:0] + 1;
	long column = [document.editor message:SCI_GETCOLUMN wParam:(uptr_t)position lParam:0] + 1;
	const char *eol = document.eolMode == SC_EOL_CRLF ? "Windows (CRLF)" : document.eolMode == SC_EOL_CR ? "Classic Mac (CR)" : "Unix (LF)";
	NSString *eolName = NppL(@(eol));
	NSString *language = document.language.length ? document.language : NppL(@"Normal Text");
	if ([language isEqualToString:@"normal"] || [document.lexerName isEqualToString:@"null"]) {
		language = NppL(@"Normal Text");
	} else if ([language isEqualToString:@"javascript.js"]) {
		language = @"JavaScript";
	} else if ([language isEqualToString:@"json5"]) {
		language = @"JSON5";
	}
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (office.kind == NppOfficeKindPDF) {
		language = NppL(@"PDF");
	} else if (office.kind == NppOfficeKindDOC || office.kind == NppOfficeKindDOCX) {
		language = NppL(@"Word, text only");
	} else if (office.kind == NppOfficeKindCSV && office.showTable) {
		language = NppL(@"CSV table");
	} else if (office.kind == NppOfficeKindXLSX) {
		language = NppL(@"Excel table");
	}
	if (document.fileMonitoring) {
		language = [language stringByAppendingString:[@"    " stringByAppendingString:NppL(@"Monitoring (tail -f)")]];
	}
	if (_macro.recording) {
		language = [language stringByAppendingFormat:@"    %@", NppL(@"RECORDING")];
	}
	long length = [document.editor message:SCI_GETLENGTH];
	NSString *fileName = document.displayName.length ? document.displayName : NppL(@"Untitled");
	_window.title = [NSString stringWithFormat:@"%@ — Simeiomatarion", fileName];
	_status.lineBreakMode = NSLineBreakByTruncatingTail;
	_status.cell.wraps = NO;
	_status.toolTip = document.path.length ? document.path : fileName;
	NSString *sizeText = @"";
	if (_settings.showFileSize) {
		unsigned long long bytes = (unsigned long long)MAX(0, length);
		if (document.path.length && !document.dirty) {
			NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:document.path error:nil];
			if (attributes) {
				bytes = [attributes fileSize];
			}
		}
		sizeText = [NSString stringWithFormat:@"     %@", NppFormatByteCount(bytes, _settings.fileSizeUnit)];
	}
	NSString *base = [NSString stringWithFormat:@"  %@     %@ %ld, %@ %ld     %@     %@     %@     %@ %ld%@", fileName, NppL(@"Ln"), line, NppL(@"Col"), column, @(EncodingName(document.encoding)), eolName, language, NppL(@"length"), length, sizeText];
	_status.stringValue = _statusOverride.length ? [NSString stringWithFormat:@"%@     %@", base, _statusOverride] : base;
	[self syncEncodingChecks:[self menuIdentified:@"Encoding"] document:document];
}

- (void)syncEncodingChecks:(NSMenu *)menu document:(DocumentTab *)document {
	for (NSMenuItem *item in menu.itemArray) {
		if (item.submenu) {
			[self syncEncodingChecks:item.submenu document:document];
		}
		if (item.action == @selector(chooseEncoding:)) {
			item.state = item.tag == document.encoding ? NSControlStateValueOn : NSControlStateValueOff;
		}
	}
}

- (void)documentTabDidScroll:(DocumentTab *)tab {
	[self updateMinimapViewport:tab];
	if (!_settings.syncScroll || _syncingScroll || _paneDocuments.count < 2) {
		return;
	}
	NSInteger pane = [self paneIndexOfDocument:tab];
	if (pane == NSNotFound || _paneDocuments[pane] != tab) {
		return;
	}
	long line = [tab.editor message:SCI_GETFIRSTVISIBLELINE];
	_syncingScroll = YES;
	for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
		if (index == pane) {
			continue;
		}
		id other = _paneDocuments[index];
		if ([other isKindOfClass:[DocumentTab class]]) {
			[((DocumentTab *)other).editor message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)line lParam:0];
		}
	}
	_syncingScroll = NO;
}

- (void)documentTabDidChange:(DocumentTab *)tab {
	if (tab == [self currentDocument]) {
		[self refreshStatus];
	}
	NSTabViewItem *item = [self itemForDocument:tab];
	item.label = tab.title;
	[self rebuildTabStrip];
	[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshLivePanels) object:nil];
	[self performSelector:@selector(refreshLivePanels) withObject:nil afterDelay:0.08];
}

- (void)documentTab:(DocumentTab *)tab insertedText:(NSString *)text at:(NSInteger)position {
	if (tab == [self currentDocument]) {
		[_macro addInsert:text at:position];
	}
	if (_workspace.compareVisible && (tab == _compareLeft || tab == _compareRight)) {
		[self closeCompare:nil];
	}
}

- (void)documentTab:(DocumentTab *)tab deletedText:(NSString *)text at:(NSInteger)position {
	if (tab == [self currentDocument]) {
		[_macro addDelete:text at:position];
	}
	if (_workspace.compareVisible && (tab == _compareLeft || tab == _compareRight)) {
		[self closeCompare:nil];
	}
}

- (NSTabViewItem *)itemForDocument:(DocumentTab *)document {
	for (NSTabViewItem *item in _tabs.tabViewItems) {
		if (item.identifier == document) {
			return item;
		}
	}
	return nil;
}

- (void)tabView:(NSTabView *)tabView didSelectTabViewItem:(NSTabViewItem *)tabViewItem {
	(void)tabView;
	(void)tabViewItem;
	_statusOverride = nil;
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)showAbout:(id)sender {
	(void)sender;
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Simeiomatarion";
	alert.informativeText = @"Text editor for Apple Silicon.\n\nIncludes code from Notepad++ 8.9.8.1, Copyright 2021 Don HO and contributors. GPL-3. Scintilla 5.6.6 and Lexilla 5.5.3.";
	[alert runModal];
}

- (NSTextField *)preferenceField:(NSString *)label frame:(NSRect)frame value:(NSString *)value tag:(NSInteger)tag in:(NSView *)parent {
	NSTextField *caption = [NSTextField labelWithString:label];
	caption.frame = NSMakeRect(frame.origin.x, frame.origin.y, 120, 24);
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(frame.origin.x + 130, frame.origin.y, frame.size.width, 24)];
	field.stringValue = value ?: @"";
	field.tag = tag;
	[parent addSubview:caption];
	[parent addSubview:field];
	return field;
}

- (NSMenu *)menuIdentified:(NSString *)identifier {
	for (NSMenuItem *item in NSApp.mainMenu.itemArray) {
		if ([item.submenu.identifier isEqualToString:identifier]) {
			return item.submenu;
		}
	}
	return nil;
}

- (void)backupFileIfNeeded:(NSString *)path {
	NSFileManager *files = [NSFileManager defaultManager];
	if (!_settings.backupBeforeSave || path.length == 0 || ![files fileExistsAtPath:path]) {
		return;
	}
	NSString *directory = [SupportDirectory().path stringByAppendingPathComponent:@"backups"];
	[files createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:nil];
	NSDateFormatter *formatter = [NSDateFormatter new];
	formatter.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
	formatter.dateFormat = @"yyyyMMdd-HHmmss";
	NSString *name = [NSString stringWithFormat:@"%@-%@", path.lastPathComponent, [formatter stringFromDate:[NSDate date]]];
	[files copyItemAtPath:path toPath:[directory stringByAppendingPathComponent:name] error:nil];
	NSURL *folder = [NSURL fileURLWithPath:directory isDirectory:YES];
	NSArray<NSURL *> *entries = [files contentsOfDirectoryAtURL:folder includingPropertiesForKeys:@[NSURLContentModificationDateKey] options:NSDirectoryEnumerationSkipsHiddenFiles error:nil];
	entries = [entries sortedArrayUsingComparator:^NSComparisonResult(NSURL *left, NSURL *right) {
		NSDate *leftDate = nil;
		NSDate *rightDate = nil;
		[left getResourceValue:&leftDate forKey:NSURLContentModificationDateKey error:nil];
		[right getResourceValue:&rightDate forKey:NSURLContentModificationDateKey error:nil];
		return [rightDate ?: NSDate.distantPast compare:leftDate ?: NSDate.distantPast];
	}];
	for (NSUInteger index = 30; index < entries.count; index++) {
		[files removeItemAtURL:entries[index] error:nil];
	}
}

- (void)noteSearch:(NSString *)query inEditor:(ScintillaView *)editor {
	if (_settings.highlightMatches && query.length) {
		NppHighlightMatches(editor, query, [self searchFlags]);
	} else {
		NppClearSearchHighlights(editor);
	}
	if (query.length == 0) {
		return;
	}
	NSString *previous = _settings.searchHistory.firstObject;
	[_settings rememberSearch:query];
	if ([previous isEqualToString:_settings.searchHistory.firstObject]) {
		return;
	}
	NSError *error = nil;
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self buildMenus];
}

- (void)newWindow:(id)sender {
	(void)sender;
	if (!_settings.extraWindows) {
		return;
	}
	NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
	configuration.createsNewApplicationInstance = YES;
	[[NSWorkspace sharedWorkspace] openApplicationAtURL:NSBundle.mainBundle.bundleURL configuration:configuration completionHandler:nil];
}

- (void)moveDocumentToNewWindow:(DocumentTab *)document {
	if (!_settings.extraWindows || !document || ![_documents containsObject:document]) {
		return;
	}
	if (document.dirty || document.path.length == 0) {
		[self alert:@"Save the document before moving it to a new window."];
		return;
	}
	NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
	configuration.createsNewApplicationInstance = YES;
	configuration.arguments = @[document.path];
	NSString *path = document.path;
	[[NSWorkspace sharedWorkspace] openApplicationAtURL:NSBundle.mainBundle.bundleURL configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
		(void)error;
		if (!application) {
			return;
		}
		dispatch_async(dispatch_get_main_queue(), ^{
			if (![_documents containsObject:document] || ![document.path isEqualToString:path]) {
				return;
			}
			NSInteger pane = [self paneIndexOfDocument:document];
			[self showDocument:document inPane:pane == NSNotFound ? 0 : pane];
			[self closeDocument:nil];
		});
	}];
}

- (void)replaceEditorText:(NSString *)text {
	DocumentTab *document = [self currentDocument];
	ScintillaView *editor = [self activeEditor] ?: document.editor;
	if (!document || !editor) {
		return;
	}
	document.suppressMacro = YES;
	[editor setString:text ?: @""];
	[editor message:SCI_COLOURISE wParam:0 lParam:-1];
	document.suppressMacro = NO;
	document.dirty = YES;
	[self refreshStatus];
}

- (void)formatJSON:(id)sender {
	(void)sender;
	if (!_settings.formatDocuments) {
		return;
	}
	NSString *error = nil;
	NSString *pretty = NppPrettyJSON([[self currentDocument] utf8Text], &error);
	if (!pretty) {
		[self alert:error.length ? error : @"Invalid JSON."];
		return;
	}
	[self replaceEditorText:pretty];
}

- (void)formatXML:(id)sender {
	(void)sender;
	if (!_settings.formatDocuments) {
		return;
	}
	NSString *error = nil;
	NSString *pretty = NppPrettyXML([[self currentDocument] utf8Text], &error);
	if (!pretty) {
		[self alert:error.length ? error : @"Invalid XML."];
		return;
	}
	[self replaceEditorText:pretty];
}

- (void)insertCharacter:(id)sender {
	NSString *symbol = [sender title];
	ScintillaView *editor = [self activeEditor];
	if (!editor || symbol.length == 0) {
		return;
	}
	[editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)symbol.UTF8String];
}

- (void)showCharacterPanel:(id)sender {
	(void)sender;
	if (!_settings.showCharacterPanel) {
		return;
	}
	if (!_characterPanel) {
		_characterPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 372, 230) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskUtilityWindow backing:NSBackingStoreBuffered defer:NO];
		_characterPanel.releasedWhenClosed = NO;
		NSArray<NSString *> *symbols = @[@"—", @"–", @"…", @"“", @"”", @"‘", @"’", @"«", @"»", @"•", @"·", @"°", @"±", @"×", @"÷", @"≠", @"≤", @"≥", @"∞", @"√", @"π", @"λ", @"€", @"£", @"¥", @"©", @"®", @"™", @"→", @"←", @"↑", @"↓", @"⇒", @"⌘", @"⌥", @"⇧", @"§", @"¶", @"†", @"‡", @"✓", @"✗"];
		CGFloat x = 10;
		CGFloat y = 188;
		for (NSString *symbol in symbols) {
			NSButton *button = [NSButton buttonWithTitle:symbol target:self action:@selector(insertCharacter:)];
			button.bezelStyle = NSBezelStyleRounded;
			button.font = [NSFont systemFontOfSize:14];
			button.frame = NSMakeRect(x, y, 36, 28);
			[_characterPanel.contentView addSubview:button];
			x += 40;
			if (x > 330) {
				x = 10;
				y -= 36;
			}
		}
	}
	_characterPanel.title = NppL(@"Character Panel…");
	[_characterPanel center];
	[_characterPanel makeKeyAndOrderFront:nil];
}

- (void)chooseAppearance:(id)sender {
	NSInteger choice = [sender tag];
	_settings.theme = choice == 1 ? @"light" : (choice == 2 ? @"dark" : @"system");
	NSError *error = nil;
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self applyWindowTheme];
	[self buildMenus];
	for (DocumentTab *document in _documents) {
		[document applySettings:_settings dark:[self darkAppearance]];
	}
}

- (void)findFromHistory:(id)sender {
	NSString *query = [sender representedObject];
	if (![query isKindOfClass:[NSString class]] || query.length == 0) {
		return;
	}
	_findField.stringValue = query;
	if (_workspace.findBar.hidden) {
		[self showFind:nil];
	}
	[self findNext:sender];
}

- (void)beginShortcutCapture:(id)sender {
	_captureShortcut = YES;
	NSButton *button = [sender isKindOfClass:[NSButton class]] ? sender : [_preferencesWindow.contentView viewWithTag:822];
	button.title = NppL(@"Listening for the next shortcut.");
	[_preferencesWindow makeFirstResponder:nil];
}

- (void)showPreferences:(id)sender {
	(void)sender;
	if (!_preferencesWindow) {
		_preferencesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 780) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
		_preferencesWindow.title = NppL(@"Preferences");
		_preferencesWindow.releasedWhenClosed = NO;
		NSView *content = _preferencesWindow.contentView;
		[self preferenceField:NppL(@"Font") frame:NSMakeRect(20, 730, 250, 24) value:@"" tag:801 in:content];
		[self preferenceField:NppL(@"Size") frame:NSMakeRect(20, 696, 80, 24) value:@"" tag:802 in:content];
		[self preferenceField:NppL(@"Tab width") frame:NSMakeRect(20, 662, 80, 24) value:@"" tag:803 in:content];
		NSArray *checks = @[
			@[NppL(@"Insert spaces instead of tabs"), @804, @20, @626],
			@[NppL(@"Word wrap"), @805, @20, @598],
			@[NppL(@"Line numbers"), @806, @220, @598],
			@[NppL(@"Show whitespace"), @807, @420, @598],
			@[NppL(@"Ask before closing a tab, folder, or the window"), @809, @20, @570],
			@[NppL(@"Auto-close brackets and quotes"), @810, @20, @470],
			@[NppL(@"Indent when Enter opens a block"), @811, @20, @442],
			@[NppL(@"Highlight every search match"), @812, @20, @414],
			@[NppL(@"Show edits since the last save"), @813, @20, @386],
			@[NppL(@"Keep a backup before each save"), @814, @20, @358],
			@[NppL(@"Spell check plain text and Markdown"), @815, @330, @470],
			@[NppL(@"Show the file size"), @816, @330, @442],
			@[NppL(@"Character panel"), @817, @330, @414],
			@[NppL(@"Open a dragged tab in a new window"), @818, @330, @386],
			@[NppL(@"Format JSON and XML"), @819, @330, @358]
		];
		NSMutableArray *views = [NSMutableArray array];
		for (NSArray *check in checks) {
			NSButton *button = [NSButton checkboxWithTitle:check[0] target:nil action:nil];
			button.frame = NSMakeRect([check[2] doubleValue], [check[3] doubleValue], 300, 24);
			button.tag = [check[1] integerValue];
			[views addObject:button];
		}
		NSTextField *themeLabel = [NSTextField labelWithString:NppL(@"Appearance")];
		themeLabel.frame = NSMakeRect(20, 534, 120, 24);
		NSPopUpButton *theme = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 530, 180, 28) pullsDown:NO];
		theme.tag = 808;
		[theme addItemsWithTitles:@[NppL(@"System"), NppL(@"White"), NppL(@"Dark")]];
		NSTextField *languageLabel = [NSTextField labelWithString:NppL(@"Language")];
		languageLabel.frame = NSMakeRect(20, 322, 120, 24);
		NSPopUpButton *language = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 318, 180, 28) pullsDown:NO];
		language.tag = 820;
		[language addItemsWithTitles:@[NppL(@"Follow System"), @"English", NppL(@"Greek")]];
		NSTextField *unitLabel = [NSTextField labelWithString:NppL(@"File size")];
		unitLabel.frame = NSMakeRect(360, 322, 90, 24);
		NSPopUpButton *unit = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(450, 318, 160, 28) pullsDown:NO];
		unit.tag = 821;
		[unit addItemsWithTitles:@[NppL(@"KB or MB"), NppL(@"Always KB"), NppL(@"Always MB")]];
		NSTextField *shortcutLabel = [NSTextField labelWithString:NppL(@"Shortcuts. Edit the keys column, for example cmd+shift+k")];
		shortcutLabel.frame = NSMakeRect(20, 286, 460, 20);
		NSButton *record = [self button:@"Record keys" action:@selector(beginShortcutCapture:) frame:NSMakeRect(490, 280, 130, 28)];
		record.tag = 822;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 600, 210)];
		scroll.hasVerticalScroller = YES;
		scroll.borderType = NSBezelBorder;
		_shortcutTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 580, 210)];
		NSTableColumn *commandColumn = [[NSTableColumn alloc] initWithIdentifier:@"command"];
		commandColumn.title = NppL(@"Command");
		commandColumn.width = 250;
		commandColumn.editable = NO;
		NSTableColumn *keysColumn = [[NSTableColumn alloc] initWithIdentifier:@"keys"];
		keysColumn.title = NppL(@"Keys");
		keysColumn.width = 300;
		keysColumn.editable = YES;
		[_shortcutTable addTableColumn:commandColumn];
		[_shortcutTable addTableColumn:keysColumn];
		_shortcutTable.dataSource = self;
		_shortcutTable.delegate = self;
		_shortcutTable.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
		scroll.documentView = _shortcutTable;
		NSButton *save = [self button:@"Save" action:@selector(savePreferences:) frame:NSMakeRect(430, 16, 80, 28)];
		NSButton *cancel = [self button:@"Cancel" action:@selector(closePreferences:) frame:NSMakeRect(520, 16, 100, 28)];
		[views addObjectsFromArray:@[themeLabel, theme, languageLabel, language, unitLabel, unit, shortcutLabel, record, scroll, save, cancel]];
		for (NSView *view in views) {
			[content addSubview:view];
		}
	}
	NSTextField *font = [_preferencesWindow.contentView viewWithTag:801];
	NSTextField *size = [_preferencesWindow.contentView viewWithTag:802];
	NSTextField *tabs = [_preferencesWindow.contentView viewWithTag:803];
	NSButton *spaces = [_preferencesWindow.contentView viewWithTag:804];
	NSButton *wrap = [_preferencesWindow.contentView viewWithTag:805];
	NSButton *numbers = [_preferencesWindow.contentView viewWithTag:806];
	NSButton *whitespace = [_preferencesWindow.contentView viewWithTag:807];
	NSPopUpButton *theme = [_preferencesWindow.contentView viewWithTag:808];
	NSButton *confirmClose = [_preferencesWindow.contentView viewWithTag:809];
	NSPopUpButton *language = [_preferencesWindow.contentView viewWithTag:820];
	NSPopUpButton *unit = [_preferencesWindow.contentView viewWithTag:821];
	font.stringValue = _settings.fontName ?: @"Menlo";
	size.stringValue = [NSString stringWithFormat:@"%d", _settings.fontSize];
	tabs.stringValue = [NSString stringWithFormat:@"%d", _settings.tabWidth];
	spaces.state = _settings.useTabs ? NSControlStateValueOff : NSControlStateValueOn;
	wrap.state = _settings.wrap ? NSControlStateValueOn : NSControlStateValueOff;
	numbers.state = _settings.lineNumbers ? NSControlStateValueOn : NSControlStateValueOff;
	whitespace.state = _settings.showWhitespace ? NSControlStateValueOn : NSControlStateValueOff;
	[theme selectItemAtIndex:[_settings.theme isEqualToString:@"light"] ? 1 : ([_settings.theme isEqualToString:@"dark"] ? 2 : 0)];
	confirmClose.state = _settings.confirmClose ? NSControlStateValueOn : NSControlStateValueOff;
	for (NSNumber *tag in @[@810, @811, @812, @813, @814, @815, @816, @817, @818, @819]) {
		NSButton *button = [_preferencesWindow.contentView viewWithTag:tag.integerValue];
		BOOL value = YES;
		switch (tag.integerValue) {
			case 810: value = _settings.autoClose; break;
			case 811: value = _settings.smartIndent; break;
			case 812: value = _settings.highlightMatches; break;
			case 813: value = _settings.showChanges; break;
			case 814: value = _settings.backupBeforeSave; break;
			case 815: value = _settings.spellCheck; break;
			case 816: value = _settings.showFileSize; break;
			case 817: value = _settings.showCharacterPanel; break;
			case 818: value = _settings.extraWindows; break;
			case 819: value = _settings.formatDocuments; break;
		}
		button.state = value ? NSControlStateValueOn : NSControlStateValueOff;
	}
	[language selectItemAtIndex:[_settings.uiLanguage isEqualToString:@"en"] ? 1 : ([_settings.uiLanguage isEqualToString:@"el"] ? 2 : 0)];
	[unit selectItemAtIndex:[_settings.fileSizeUnit isEqualToString:@"kb"] ? 1 : ([_settings.fileSizeUnit isEqualToString:@"mb"] ? 2 : 0)];
	_shortcutRows = [NSMutableArray array];
	for (NSString *command in [_settings.shortcuts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		[_shortcutRows addObject:[@{@"command": command, @"keys": _settings.shortcuts[command] ?: @""} mutableCopy]];
	}
	[_shortcutTable reloadData];
	[_preferencesWindow center];
	[_preferencesWindow makeKeyAndOrderFront:nil];
}

- (void)closePreferences:(id)sender {
	(void)sender;
	[_preferencesWindow close];
}

- (void)savePreferences:(id)sender {
	(void)sender;
	NSView *content = _preferencesWindow.contentView;
	NSTextField *font = [content viewWithTag:801];
	NSTextField *size = [content viewWithTag:802];
	NSTextField *tabs = [content viewWithTag:803];
	NSButton *spaces = [content viewWithTag:804];
	NSButton *wrap = [content viewWithTag:805];
	NSButton *numbers = [content viewWithTag:806];
	NSButton *whitespace = [content viewWithTag:807];
	NSPopUpButton *theme = [content viewWithTag:808];
	NSButton *confirmClose = [content viewWithTag:809];
	NSPopUpButton *language = [content viewWithTag:820];
	NSPopUpButton *unit = [content viewWithTag:821];
	NSString *previousLanguage = _settings.uiLanguage;
	_settings.fontName = font.stringValue.length ? font.stringValue : @"Menlo";
	_settings.fontSize = MAX(6, MIN(72, size.stringValue.intValue));
	_settings.tabWidth = MAX(1, MIN(32, tabs.stringValue.intValue));
	_settings.useTabs = spaces.state != NSControlStateValueOn;
	_settings.wrap = wrap.state == NSControlStateValueOn;
	_settings.lineNumbers = numbers.state == NSControlStateValueOn;
	_settings.showWhitespace = whitespace.state == NSControlStateValueOn;
	_settings.theme = theme.indexOfSelectedItem == 1 ? @"light" : (theme.indexOfSelectedItem == 2 ? @"dark" : @"system");
	_settings.confirmClose = confirmClose.state == NSControlStateValueOn;
	_settings.autoClose = [(NSButton *)[content viewWithTag:810] state] == NSControlStateValueOn;
	_settings.smartIndent = [(NSButton *)[content viewWithTag:811] state] == NSControlStateValueOn;
	_settings.highlightMatches = [(NSButton *)[content viewWithTag:812] state] == NSControlStateValueOn;
	_settings.showChanges = [(NSButton *)[content viewWithTag:813] state] == NSControlStateValueOn;
	_settings.backupBeforeSave = [(NSButton *)[content viewWithTag:814] state] == NSControlStateValueOn;
	_settings.spellCheck = [(NSButton *)[content viewWithTag:815] state] == NSControlStateValueOn;
	_settings.showFileSize = [(NSButton *)[content viewWithTag:816] state] == NSControlStateValueOn;
	_settings.showCharacterPanel = [(NSButton *)[content viewWithTag:817] state] == NSControlStateValueOn;
	_settings.extraWindows = [(NSButton *)[content viewWithTag:818] state] == NSControlStateValueOn;
	_settings.formatDocuments = [(NSButton *)[content viewWithTag:819] state] == NSControlStateValueOn;
	_settings.uiLanguage = language.indexOfSelectedItem == 1 ? @"en" : (language.indexOfSelectedItem == 2 ? @"el" : @"system");
	_settings.fileSizeUnit = unit.indexOfSelectedItem == 1 ? @"kb" : (unit.indexOfSelectedItem == 2 ? @"mb" : @"auto");
	NppSetUILanguage(_settings.uiLanguage);
	NSMutableDictionary *shortcutMap = [NSMutableDictionary dictionary];
	for (NSDictionary *row in _shortcutRows) {
		if ([row[@"command"] length] && [row[@"keys"] length]) {
			shortcutMap[row[@"command"]] = row[@"keys"];
		}
	}
	if (shortcutMap.count) {
		_settings.shortcuts = shortcutMap;
	}
	NSError *error = nil;
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self applyWindowTheme];
	[self buildMenus];
	for (DocumentTab *document in _documents) {
		[document applySettings:_settings dark:[self darkAppearance]];
	}
	[self updateSplitWrapping];
	NSView *toolbarButtons = [_toolbar isKindOfClass:[NSScrollView class]] ? ((NSScrollView *)_toolbar).documentView : _toolbar;
	for (NSView *view in toolbarButtons.subviews) {
		if ([view isKindOfClass:[NSButton class]] && view.identifier.length) {
			NSButton *button = (NSButton *)view;
			button.title = NppL(button.identifier);
			if ([button.identifier isEqualToString:@"Format JSON"] || [button.identifier isEqualToString:@"Format XML"]) {
				button.enabled = _settings.formatDocuments;
			}
		}
	}
	[self updateTailButton];
	[_preferencesWindow close];
	if (![previousLanguage isEqualToString:_settings.uiLanguage]) {
		_preferencesWindow = nil;
		_shortcutTable = nil;
	}
	[self refreshStatus];
}

- (void)revealInFinder:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (document.path.length == 0) {
		[self alert:@"Save the document before revealing it in Finder."];
		return;
	}
	[[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[[NSURL fileURLWithPath:document.path]]];
}

- (void)toggleSyncScrolling:(id)sender {
	(void)sender;
	_settings.syncScroll = !_settings.syncScroll;
	NSError *error = nil;
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self buildMenus];
	[self setStatusText:_settings.syncScroll ? @"Split panes scroll together." : @"Split panes scroll independently."];
}

- (void)clearCompareMarkersOn:(DocumentTab *)document {
	if (!document || ![_documents containsObject:document]) {
		return;
	}
	[document.editor message:SCI_MARKERDELETEALL wParam:kCompareMarker lParam:0];
}

- (void)markCompareLines:(NSIndexSet *)lines removed:(BOOL)removed in:(DocumentTab *)document {
	if (!document) {
		return;
	}
	ScintillaView *editor = document.editor;
	[editor message:SCI_MARKERDEFINE wParam:kCompareMarker lParam:SC_MARK_BACKGROUND];
	BOOL dark = [self darkAppearance];
	long color = removed ? (dark ? 0x6644AA : 0xD0D8FF) : (dark ? 0x44AA66 : 0xD8FFD0);
	[editor message:SCI_MARKERSETBACK wParam:kCompareMarker lParam:color];
	[editor message:SCI_MARKERSETALPHA wParam:kCompareMarker lParam:dark ? 70 : 110];
	[editor message:SCI_MARKERDELETEALL wParam:kCompareMarker lParam:0];
	[lines enumerateIndexesUsingBlock:^(NSUInteger line, BOOL *stop) {
		(void)stop;
		if (line > 0) {
			[editor message:SCI_MARKERADD wParam:line - 1 lParam:kCompareMarker];
		}
	}];
}

- (void)revealCompareLine:(NSInteger)line in:(DocumentTab *)document {
	if (!document || line < 1 || ![_documents containsObject:document]) {
		return;
	}
	long index = (long)line - 1;
	[document.editor message:SCI_GOTOLINE wParam:(uptr_t)index lParam:0];
	long top = index > 2 ? index - 2 : 0;
	[document.editor message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)top lParam:0];
}

- (void)showCompareIndex:(NSInteger)index {
	if (_compareRows.count == 0) {
		_compareLabel.stringValue = NppL(@"The two panes match.");
		return;
	}
	if (index < 0) {
		index = 0;
	}
	if (index >= (NSInteger)_compareRows.count) {
		index = (NSInteger)_compareRows.count - 1;
	}
	_compareIndex = index;
	NSDictionary *row = _compareRows[index];
	BOOL removed = [row[@"side"] isEqualToString:@"-"];
	DocumentTab *focus = removed ? _compareLeft : _compareRight;
	DocumentTab *other = removed ? _compareRight : _compareLeft;
	NSInteger pane = [self paneIndexOfDocument:focus];
	if (pane != NSNotFound) {
		[self showDocument:focus inPane:pane];
	}
	_syncingScroll = YES;
	[self revealCompareLine:[row[@"line"] integerValue] in:focus];
	[self revealCompareLine:[row[@"peer"] integerValue] in:other];
	_syncingScroll = NO;
	NSString *kind = NppL(removed ? @"Removed" : @"Added");
	_compareLabel.stringValue = [NSString stringWithFormat:@"%@ · %@ %ld / %ld", kind, NppL(@"Difference"), (long)(index + 1), (long)_compareRows.count];
}

- (void)comparePrevious:(id)sender {
	(void)sender;
	[self showCompareIndex:_compareIndex - 1];
}

- (void)compareNext:(id)sender {
	(void)sender;
	[self showCompareIndex:_compareIndex + 1];
}

- (void)closeCompare:(id)sender {
	(void)sender;
	[self clearCompareMarkersOn:_compareLeft];
	[self clearCompareMarkersOn:_compareRight];
	_compareLeft = nil;
	_compareRight = nil;
	_compareRows = nil;
	_compareIndex = 0;
	_workspace.compareVisible = NO;
	[_workspace layoutPanes];
}

- (void)comparePanes:(id)sender {
	(void)sender;
	if (_paneDocuments.count < 2) {
		[self alert:@"Split the window into two panes before comparing them."];
		return;
	}
	DocumentTab *left = [_paneDocuments[0] isKindOfClass:[DocumentTab class]] ? _paneDocuments[0] : nil;
	DocumentTab *right = [_paneDocuments[1] isKindOfClass:[DocumentTab class]] ? _paneDocuments[1] : nil;
	if (!left || !right) {
		[self alert:@"Both panes need an open document."];
		return;
	}
	[self clearCompareMarkersOn:_compareLeft];
	[self clearCompareMarkersOn:_compareRight];
	NSArray<NSString *> *leftLines = [[left utf8Text] ?: @"" componentsSeparatedByString:@"\n"];
	NSArray<NSString *> *rightLines = [[right utf8Text] ?: @"" componentsSeparatedByString:@"\n"];
	NSArray<NSDictionary *> *changes = NppDiffLines(leftLines, rightLines);
	NSMutableArray<NSDictionary *> *rows = [NSMutableArray array];
	NSMutableIndexSet *leftMarks = [NSMutableIndexSet indexSet];
	NSMutableIndexSet *rightMarks = [NSMutableIndexSet indexSet];
	for (NSInteger index = 0; index < (NSInteger)changes.count && rows.count < 800; index++) {
		NSDictionary *change = changes[index];
		NSString *side = change[@"side"];
		NSInteger line = [change[@"line"] integerValue];
		NSString *peerSide = [side isEqualToString:@"-"] ? @"+" : @"-";
		NSInteger peer = line;
		BOOL foundPeer = NO;
		for (NSInteger later = index; later < (NSInteger)changes.count; later++) {
			if ([changes[later][@"side"] isEqualToString:peerSide]) {
				peer = [changes[later][@"line"] integerValue];
				foundPeer = YES;
				break;
			}
		}
		if (!foundPeer) {
			for (NSInteger earlier = index; earlier >= 0; earlier--) {
				if ([changes[earlier][@"side"] isEqualToString:peerSide]) {
					peer = [changes[earlier][@"line"] integerValue];
					break;
				}
			}
		}
		if ([side isEqualToString:@"-"]) {
			[leftMarks addIndex:(NSUInteger)MAX(line, 0)];
		} else {
			[rightMarks addIndex:(NSUInteger)MAX(line, 0)];
		}
		[rows addObject:@{@"side": side ?: @"-", @"line": @(line), @"peer": @(peer)}];
	}
	_compareLeft = left;
	_compareRight = right;
	_compareRows = rows;
	[self markCompareLines:leftMarks removed:YES in:left];
	[self markCompareLines:rightMarks removed:NO in:right];
	_workspace.resultsVisible = NO;
	_workspace.compareVisible = YES;
	[_workspace layoutPanes];
	[self showCompareIndex:0];
}

- (void)showQuickOpen:(id)sender {
	(void)sender;
	if (!_quickOpenPanel) {
		_quickOpenPanel = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 360) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
		_quickOpenPanel.title = @"Open Quickly";
		_quickOpenPanel.releasedWhenClosed = NO;
		NSView *content = _quickOpenPanel.contentView;
		_quickOpenField = [[NSSearchField alloc] initWithFrame:NSMakeRect(16, 320, 528, 28)];
		_quickOpenField.placeholderString = @"Type a file or tab name";
		_quickOpenField.target = self;
		_quickOpenField.action = @selector(confirmQuickOpen:);
		_quickOpenField.delegate = (id<NSSearchFieldDelegate>)self;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(16, 16, 528, 292)];
		scroll.hasVerticalScroller = YES;
		_quickOpenTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 528, 292)];
		NSTableColumn *name = [[NSTableColumn alloc] initWithIdentifier:@"name"];
		name.title = @"Name";
		name.width = 180;
		NSTableColumn *where = [[NSTableColumn alloc] initWithIdentifier:@"where"];
		where.title = @"Where";
		where.width = 320;
		[_quickOpenTable addTableColumn:name];
		[_quickOpenTable addTableColumn:where];
		_quickOpenTable.headerView = nil;
		_quickOpenTable.dataSource = self;
		_quickOpenTable.delegate = self;
		_quickOpenTable.doubleAction = @selector(confirmQuickOpen:);
		_quickOpenTable.target = self;
		_quickOpenTable.tag = 900;
		scroll.documentView = _quickOpenTable;
		[content addSubview:_quickOpenField];
		[content addSubview:scroll];
	}
	_quickOpenField.stringValue = @"";
	[self reloadQuickOpen];
	[_quickOpenPanel center];
	[_quickOpenPanel makeKeyAndOrderFront:nil];
	[_quickOpenPanel makeFirstResponder:_quickOpenField];
}

- (void)controlTextDidChange:(NSNotification *)notification {
	if (notification.object == _quickOpenField) {
		[self reloadQuickOpen];
	} else if (notification.object == _folderFindField) {
		[self scheduleFolderSearch];
	}
}

- (void)reloadQuickOpen {
	NSString *query = _quickOpenField.stringValue.lowercaseString ?: @"";
	NSMutableArray *rows = [NSMutableArray array];
	NSMutableSet *seen = [NSMutableSet set];
	for (DocumentTab *document in _documents) {
		NSString *name = document.displayName ?: @"Untitled";
		NSString *path = document.path ?: @"";
		if (query.length && [name.lowercaseString rangeOfString:query].location == NSNotFound && [path.lowercaseString rangeOfString:query].location == NSNotFound) {
			continue;
		}
		[rows addObject:@{@"name": name, @"where": path.length ? path : @"Open tab", @"path": path, @"open": @YES}];
		if (path.length) {
			[seen addObject:path];
		}
	}
	for (NSString *path in [[NSUserDefaults standardUserDefaults] arrayForKey:@"recentFiles"]) {
		if ([seen containsObject:path]) {
			continue;
		}
		NSString *name = path.lastPathComponent ?: path;
		if (query.length && [name.lowercaseString rangeOfString:query].location == NSNotFound && [path.lowercaseString rangeOfString:query].location == NSNotFound) {
			continue;
		}
		[rows addObject:@{@"name": name, @"where": path, @"path": path, @"open": @NO}];
	}
	_quickOpenRows = rows;
	[_quickOpenTable reloadData];
	if (rows.count > 0) {
		[_quickOpenTable selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
	}
}

- (void)confirmQuickOpen:(id)sender {
	(void)sender;
	NSInteger row = _quickOpenTable.selectedRow;
	if (row < 0 || row >= (NSInteger)_quickOpenRows.count) {
		return;
	}
	NSDictionary *entry = _quickOpenRows[row];
	NSString *path = entry[@"path"];
	[_quickOpenPanel close];
	if ([entry[@"open"] boolValue]) {
		for (DocumentTab *document in _documents) {
			BOOL samePath = path.length && [document.path isEqualToString:path];
			BOOL sameName = path.length == 0 && [document.displayName isEqualToString:entry[@"name"]];
			if (samePath || sameName) {
				[self showDocument:document inPane:[self paneIndexOfDocument:document]];
				return;
			}
		}
	}
	if (path.length) {
		[self openPath:path];
	}
}

- (NSButton *)sidebarButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
	NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:NppL(tip)];
	image.size = NSMakeSize(13, 13);
	NSButton *button = [NSButton buttonWithImage:image target:self action:action];
	button.bezelStyle = NSBezelStyleTexturedRounded;
	button.imageScaling = NSImageScaleProportionallyDown;
	button.imagePosition = NSImageOnly;
	button.bordered = YES;
	button.title = @"";
	button.toolTip = NppL(tip);
	return button;
}

- (NSView *)buildFolderSidebar {
	NSView *side = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
	side.wantsLayer = YES;
	side.clipsToBounds = YES;
	side.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	NSImageView *glyph = [[NSImageView alloc] initWithFrame:NSMakeRect(10, 0, 16, 16)];
	glyph.image = NppTintedSymbol(@"folder.fill", NSColor.systemBlueColor);
	glyph.imageScaling = NSImageScaleProportionallyDown;
	glyph.tag = 6;
	NSTextField *title = [NSTextField labelWithString:NppL(@"Folder")];
	title.frame = NSMakeRect(30, 0, 150, 18);
	title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
	title.lineBreakMode = NSLineBreakByTruncatingTail;
	title.tag = 1;
	NSButton *up = [self sidebarButton:@"chevron.up" tip:@"Enclosing folder" action:@selector(folderUp:)];
	up.tag = 3;
	NSButton *symbols = [self sidebarButton:@"list.bullet.indent" tip:@"Symbols" action:@selector(showOutline:)];
	symbols.tag = 5;
	NSButton *hide = [self sidebarButton:@"sidebar.left" tip:@"Hide the folder" action:@selector(closeFolderSidebar:)];
	hide.tag = 4;
	NSTextField *path = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 0, 260, 22)];
	path.tag = 2;
	path.bezelStyle = NSTextFieldRoundedBezel;
	path.placeholderString = @"Folder path";
	path.font = [NSFont systemFontOfSize:11];
	path.textColor = NSColor.secondaryLabelColor;
	path.lineBreakMode = NSLineBreakByTruncatingHead;
	NSTextFieldCell *pathCell = path.cell;
	pathCell.wraps = NO;
	pathCell.scrollable = YES;
	path.target = self;
	path.action = @selector(commitFolderPath:);
	path.toolTip = @"Type a folder path and press Return";
	_folderFindField = [[NSSearchField alloc] initWithFrame:NSMakeRect(8, 0, 260, 22)];
	_folderFindField.tag = 7;
	_folderFindField.placeholderString = NppL(@"Find a file");
	_folderFindField.font = [NSFont systemFontOfSize:12];
	_folderFindField.sendsSearchStringImmediately = YES;
	_folderFindField.sendsWholeSearchString = NO;
	_folderFindField.target = self;
	_folderFindField.action = @selector(openFolderSearchResult:);
	_folderFindField.delegate = (id<NSSearchFieldDelegate>)self;
	NSBox *rule = [[NSBox alloc] initWithFrame:NSMakeRect(0, 0, 280, 1)];
	rule.boxType = NSBoxSeparator;
	rule.identifier = @"npp.sidebar.rule";
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	scroll.hasVerticalScroller = YES;
	scroll.drawsBackground = NO;
	scroll.identifier = @"npp.folder";
	_folderOutline = [[NSOutlineView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	column.title = @"Name";
	column.width = 250;
	[_folderOutline addTableColumn:column];
	_folderOutline.outlineTableColumn = column;
	_folderOutline.headerView = nil;
	_folderOutline.dataSource = self;
	_folderOutline.delegate = self;
	_folderOutline.doubleAction = @selector(openFolderItem:);
	_folderOutline.target = self;
	_folderOutline.tag = 901;
	_folderOutline.style = NSTableViewStyleSourceList;
	_folderOutline.rowHeight = 24;
	_folderOutline.intercellSpacing = NSMakeSize(0, 1);
	_folderOutline.indentationPerLevel = 14;
	_folderOutline.backgroundColor = NSColor.clearColor;
	_folderOutline.autoresizesOutlineColumn = YES;
	column.resizingMask = NSTableColumnAutoresizingMask;
	scroll.documentView = _folderOutline;
	scroll.automaticallyAdjustsContentInsets = NO;
	scroll.contentInsets = NSEdgeInsetsMake(4, 0, 8, 0);
	NSScrollView *outlineScroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	outlineScroll.hasVerticalScroller = YES;
	outlineScroll.drawsBackground = NO;
	outlineScroll.identifier = @"npp.outline";
	outlineScroll.hidden = YES;
	_outlineTable = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	NSTableColumn *symbolColumn = [[NSTableColumn alloc] initWithIdentifier:@"name"];
	symbolColumn.title = @"Symbol";
	symbolColumn.width = 190;
	NSTableColumn *lineColumn = [[NSTableColumn alloc] initWithIdentifier:@"line"];
	lineColumn.title = @"Line";
	lineColumn.width = 48;
	[_outlineTable addTableColumn:symbolColumn];
	[_outlineTable addTableColumn:lineColumn];
	_outlineTable.headerView = nil;
	_outlineTable.rowHeight = 22;
	_outlineTable.style = NSTableViewStyleSourceList;
	_outlineTable.backgroundColor = NSColor.clearColor;
	_outlineTable.intercellSpacing = NSMakeSize(4, 1);
	_outlineTable.dataSource = self;
	_outlineTable.delegate = self;
	_outlineTable.target = self;
	_outlineTable.doubleAction = @selector(openOutlineRow:);
	outlineScroll.documentView = _outlineTable;
	for (NSView *view in @[glyph, title, up, symbols, hide, path, _folderFindField, rule, scroll, outlineScroll]) {
		[side addSubview:view];
	}
	return side;
}

- (void)layoutFolderSidebar {
	if (!_sidebar) {
		return;
	}
	CGFloat height = _sidebar.bounds.size.height;
	CGFloat width = _sidebar.bounds.size.width;
	_sidebar.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	CGFloat listTop = _sidebarPage == 1 ? 36 : 96;
	_folderFindField.placeholderString = NppL(@"Find a file");
	for (NSView *view in _sidebar.subviews) {
		if (view.tag == 6) {
			view.frame = NSMakeRect(10, height - 26, 16, 16);
		} else if (view.tag == 1) {
			view.frame = NSMakeRect(32, height - 26, MAX(40, width - 124), 18);
		} else if (view.tag == 3) {
			view.frame = NSMakeRect(width - 90, height - 28, 26, 22);
			view.hidden = _sidebarPage == 1;
		} else if (view.tag == 5) {
			view.frame = NSMakeRect(width - 60, height - 28, 26, 22);
		} else if (view.tag == 4) {
			view.frame = NSMakeRect(width - 30, height - 28, 26, 22);
		} else if (view.tag == 2) {
			view.frame = NSMakeRect(8, height - 56, MAX(40, width - 16), 22);
			view.hidden = _sidebarPage == 1;
		} else if (view.tag == 7) {
			view.frame = NSMakeRect(8, height - 84, MAX(40, width - 16), 22);
			view.hidden = _sidebarPage == 1;
		} else if ([view.identifier isEqualToString:@"npp.sidebar.rule"]) {
			view.frame = NSMakeRect(8, height - listTop, MAX(0, width - 16), 1);
		} else if ([view.identifier isEqualToString:@"npp.folder"]) {
			view.hidden = _sidebarPage == 1;
			view.frame = NSMakeRect(0, 0, width, MAX(0, height - listTop));
		} else if ([view.identifier isEqualToString:@"npp.outline"]) {
			view.hidden = _sidebarPage != 1;
			view.frame = NSMakeRect(0, 0, width, MAX(0, height - listTop));
		}
	}
	if (_folderOutline.tableColumns.count) {
		_folderOutline.tableColumns.firstObject.width = MAX(80, width - 8);
	}
	_sidebar.clipsToBounds = YES;
	if (_folderFindField && _sidebarPage != 1) {
		_folderFindField.frame = NSMakeRect(8, MAX(0, height - 84), MAX(40, width - 16), 22);
	}
}

- (void)openFolder:(id)sender {
	(void)sender;
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	panel.canChooseFiles = NO;
	panel.canChooseDirectories = YES;
	panel.allowsMultipleSelection = NO;
	panel.prompt = @"Open Folder";
	if ([panel runModal] != NSModalResponseOK) {
		return;
	}
	[self showFolderAtPath:panel.URL.path];
}

- (void)showFolderAtPath:(NSString *)path {
	BOOL directory = NO;
	if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory] || !directory) {
		return;
	}
	_folderSearchGeneration++;
	_folderQuery = @"";
	_folderMatches = nil;
	_folderFindField.stringValue = @"";
	_folderRoot = path;
	_folderRootNode = [NppFolderNode new];
	_folderRootNode.path = path;
	_folderRootNode.name = path.lastPathComponent;
	_folderRootNode.directory = YES;
	_folderRootNode.icon = NppSidebarFileIcon(_folderRootNode.name, path, YES);
	NSTextField *title = [_sidebar viewWithTag:1];
	title.stringValue = path.lastPathComponent.length ? path.lastPathComponent : path;
	title.toolTip = path;
	NSTextField *pathField = [_sidebar viewWithTag:2];
	pathField.stringValue = path;
	pathField.toolTip = path;
	[_folderOutline reloadData];
	[_folderOutline expandItem:nil expandChildren:NO];
	_workspace.sidebarVisible = YES;
	[_workspace layoutPanes];
	[self layoutFolderSidebar];
	[self saveSession];
}

- (void)closeFolderSidebar:(id)sender {
	(void)sender;
	if (_settings.confirmClose) {
		NSAlert *alert = [NSAlert new];
		alert.messageText = @"Hide the folder?";
		alert.informativeText = _folderRoot.length
			? [_folderRoot stringByAppendingString:@"\n\nYou can turn off these prompts in Preferences."]
			: @"You can turn off these prompts in Preferences.";
		[alert addButtonWithTitle:@"Hide"];
		[alert addButtonWithTitle:@"Cancel"];
		if ([alert runModal] != NSAlertFirstButtonReturn) {
			return;
		}
	}
	_workspace.sidebarVisible = NO;
	[_workspace layoutPanes];
	[self saveSession];
}

- (void)folderUp:(id)sender {
	(void)sender;
	if (_folderRoot.length == 0 || [_folderRoot isEqualToString:@"/"]) {
		return;
	}
	NSString *parent = _folderRoot.stringByDeletingLastPathComponent;
	if (parent.length == 0 || [parent isEqualToString:_folderRoot]) {
		return;
	}
	[self showFolderAtPath:parent];
}

- (void)commitFolderPath:(id)sender {
	(void)sender;
	NSTextField *pathField = [_sidebar viewWithTag:2];
	NSString *path = [pathField.stringValue stringByExpandingTildeInPath];
	path = path.stringByStandardizingPath;
	BOOL directory = NO;
	if (path.length == 0 || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&directory]) {
		pathField.stringValue = _folderRoot ?: @"";
		[self alert:@"That path does not exist."];
		return;
	}
	if (!directory) {
		[self showFolderAtPath:path.stringByDeletingLastPathComponent];
		[self openPath:path];
		return;
	}
	[self showFolderAtPath:path];
}

static NSArray<NSDictionary *> *NppCollectFolderMatches(NSString *root, NSString *query) {
	NSString *needle = query.lowercaseString ?: @"";
	if (root.length == 0 || needle.length == 0) {
		return @[];
	}
	NSFileManager *files = [NSFileManager defaultManager];
	NSURL *rootURL = [NSURL fileURLWithPath:root isDirectory:YES];
	NSDirectoryEnumerator *enumerator = [files enumeratorAtURL:rootURL
		includingPropertiesForKeys:@[NSURLIsDirectoryKey]
		options:NSDirectoryEnumerationSkipsHiddenFiles | NSDirectoryEnumerationSkipsPackageDescendants
		errorHandler:nil];
	NSMutableArray<NSDictionary *> *hits = [NSMutableArray array];
	NSInteger seen = 0;
	for (NSURL *url in enumerator) {
		if (++seen > 20000) {
			break;
		}
		NSString *name = url.lastPathComponent ?: @"";
		if ([name isEqualToString:@"node_modules"]) {
			[enumerator skipDescendants];
			continue;
		}
		if ([name.lowercaseString rangeOfString:needle].location == NSNotFound) {
			continue;
		}
		NSNumber *directory = nil;
		[url getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
		NSString *full = url.path ?: @"";
		NSString *prefix = [root hasSuffix:@"/"] ? root : [root stringByAppendingString:@"/"];
		NSString *relative = [full hasPrefix:prefix] ? [full substringFromIndex:prefix.length] : name;
		[hits addObject:@{
			@"path": full,
			@"name": relative.length ? relative : name,
			@"directory": directory ?: @NO
		}];
		if (hits.count >= 200) {
			break;
		}
	}
	return [hits sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
		return [left[@"name"] localizedCaseInsensitiveCompare:right[@"name"]];
	}];
}

- (void)scheduleFolderSearch {
	NSString *query = [_folderFindField.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSInteger generation = ++_folderSearchGeneration;
	_folderQuery = query ?: @"";
	if (_folderQuery.length == 0 || _folderRoot.length == 0) {
		_folderMatches = nil;
		[_folderOutline reloadData];
		[_folderOutline expandItem:nil expandChildren:NO];
		return;
	}
	NSString *root = _folderRoot;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.15 * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
		if (generation != self->_folderSearchGeneration) {
			return;
		}
		NSArray<NSDictionary *> *found = NppCollectFolderMatches(root, query);
		dispatch_async(dispatch_get_main_queue(), ^{
			if (generation != self->_folderSearchGeneration) {
				return;
			}
			NSMutableArray<NppFolderNode *> *nodes = [NSMutableArray array];
			for (NSDictionary *hit in found) {
				NppFolderNode *node = [NppFolderNode new];
				node.path = hit[@"path"];
				node.name = hit[@"name"];
				node.directory = [hit[@"directory"] boolValue];
				node.icon = NppSidebarFileIcon(node.path.lastPathComponent, node.path, node.directory);
				[nodes addObject:node];
			}
			if (nodes.count == 0) {
				NppFolderNode *empty = [NppFolderNode new];
				empty.name = NppL(@"No matching files");
				[nodes addObject:empty];
			}
			self->_folderMatches = nodes;
			[self->_folderOutline reloadData];
			if (found.count > 0) {
				[self->_folderOutline selectRowIndexes:[NSIndexSet indexSetWithIndex:0] byExtendingSelection:NO];
			}
		});
	});
}

- (void)openFolderSearchResult:(id)sender {
	(void)sender;
	if (_folderQuery.length == 0) {
		return;
	}
	NSInteger row = _folderOutline.selectedRow;
	if (row < 0 && _folderMatches.count > 0 && _folderMatches.firstObject.path.length > 0) {
		row = 0;
	}
	[self openFolderNode:[_folderOutline itemAtRow:row]];
}

- (NSArray<NppFolderNode *> *)folderChildren:(NppFolderNode *)node {
	if (node.loaded) {
		return node.children;
	}
	node.loaded = YES;
	node.children = [NSMutableArray array];
	NSFileManager *files = [NSFileManager defaultManager];
	NSArray<NSString *> *names = [files contentsOfDirectoryAtPath:node.path error:nil];
	NSMutableArray<NppFolderNode *> *directories = [NSMutableArray array];
	NSMutableArray<NppFolderNode *> *regular = [NSMutableArray array];
	for (NSString *name in names) {
		if ([name hasPrefix:@"."] || [name isEqualToString:@"node_modules"]) {
			continue;
		}
		NSString *childPath = [node.path stringByAppendingPathComponent:name];
		BOOL directory = NO;
		if (![files fileExistsAtPath:childPath isDirectory:&directory]) {
			continue;
		}
		NppFolderNode *child = [NppFolderNode new];
		child.path = childPath;
		child.name = name;
		child.directory = directory;
		child.icon = NppSidebarFileIcon(name, childPath, directory);
		[(directory ? directories : regular) addObject:child];
		if (directories.count + regular.count >= 800) {
			break;
		}
	}
	NSComparator order = ^NSComparisonResult(NppFolderNode *left, NppFolderNode *right) {
		return [left.name localizedCaseInsensitiveCompare:right.name];
	};
	[directories sortUsingComparator:order];
	[regular sortUsingComparator:order];
	[node.children addObjectsFromArray:directories];
	[node.children addObjectsFromArray:regular];
	return node.children;
}

- (NSInteger)outlineView:(NSOutlineView *)outlineView numberOfChildrenOfItem:(id)item {
	(void)outlineView;
	if (_folderQuery.length > 0) {
		return item == nil ? (NSInteger)_folderMatches.count : 0;
	}
	if (!_folderRootNode) {
		return 0;
	}
	NppFolderNode *node = item ?: _folderRootNode;
	return node.directory ? (NSInteger)[self folderChildren:node].count : 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	(void)outlineView;
	if (_folderQuery.length > 0) {
		return NO;
	}
	return [item isKindOfClass:[NppFolderNode class]] && ((NppFolderNode *)item).directory;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	(void)outlineView;
	if (_folderQuery.length > 0) {
		if (item != nil || index < 0 || index >= (NSInteger)_folderMatches.count) {
			return nil;
		}
		return _folderMatches[index];
	}
	NppFolderNode *node = item ?: _folderRootNode;
	NSArray<NppFolderNode *> *children = [self folderChildren:node];
	if (index < 0 || index >= (NSInteger)children.count) {
		return nil;
	}
	return children[index];
}

- (id)outlineView:(NSOutlineView *)outlineView objectValueForTableColumn:(NSTableColumn *)tableColumn byItem:(id)item {
	(void)outlineView;
	(void)tableColumn;
	return [item isKindOfClass:[NppFolderNode class]] ? ((NppFolderNode *)item).name : @"";
}

- (NSView *)outlineView:(NSOutlineView *)outlineView viewForTableColumn:(NSTableColumn *)tableColumn item:(id)item {
	(void)tableColumn;
	if (outlineView != _folderOutline || ![item isKindOfClass:[NppFolderNode class]]) {
		return nil;
	}
	NppFolderNode *node = item;
	NppFolderCell *cell = [outlineView makeViewWithIdentifier:@"npp.folder.cell" owner:self];
	if (!cell) {
		cell = [[NppFolderCell alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
		cell.identifier = @"npp.folder.cell";
		NSImageView *imageView = [NSImageView imageViewWithImage:[NSImage new]];
		imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
		NSTextField *text = [NSTextField labelWithString:@""];
		text.lineBreakMode = NSLineBreakByTruncatingMiddle;
		text.font = [NSFont systemFontOfSize:12];
		text.textColor = NSColor.labelColor;
		cell.imageView = imageView;
		cell.textField = text;
		[cell addSubview:imageView];
		[cell addSubview:text];
	}
	cell.imageView.image = node.icon;
	cell.textField.stringValue = node.name ?: @"";
	cell.textField.textColor = node.path.length ? NSColor.labelColor : NSColor.secondaryLabelColor;
	cell.textField.font = node.directory
		? [NSFont systemFontOfSize:12 weight:NSFontWeightMedium]
		: [NSFont systemFontOfSize:12];
	cell.toolTip = node.path.length ? node.path : node.name;
	return cell;
}

- (void)openFolderNode:(NppFolderNode *)node {
	if (![node isKindOfClass:[NppFolderNode class]] || node.path.length == 0) {
		return;
	}
	if (node.directory) {
		[self showFolderAtPath:node.path];
		return;
	}
	DocumentTab *existing = [self documentForPath:node.path];
	if (existing) {
		[self showDocument:existing inPane:_activePane];
	} else {
		[self openPath:node.path];
	}
}

- (void)openFolderItem:(id)sender {
	(void)sender;
	[self openFolderNode:[_folderOutline itemAtRow:_folderOutline.clickedRow]];
}

- (NSURL *)pluginsDirectory {
	NSURL *user = [SupportDirectory() URLByAppendingPathComponent:@"plugins" isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:user withIntermediateDirectories:YES attributes:nil error:nil];
	return user;
}

- (void)unloadPlugins {
	for (NSDictionary *plugin in _plugins) {
		void *handle = [plugin[@"handle"] pointerValue];
		if (handle) {
			dlclose(handle);
		}
	}
	[_plugins removeAllObjects];
	[_pluginErrors removeAllObjects];
}

- (void)loadPlugins {
	[self unloadPlugins];
	NSMutableArray<NSString *> *paths = [NSMutableArray array];
	NSFileManager *files = [NSFileManager defaultManager];
	NSString *bundledDirectory = NSBundle.mainBundle.builtInPlugInsPath;
	for (NSString *name in [files contentsOfDirectoryAtPath:bundledDirectory error:nil]) {
		if ([name.pathExtension isEqualToString:@"dylib"]) {
			[paths addObject:[bundledDirectory stringByAppendingPathComponent:name]];
		}
	}
	for (NSURL *url in [files contentsOfDirectoryAtURL:[self pluginsDirectory] includingPropertiesForKeys:nil options:0 error:nil]) {
		if ([url.pathExtension isEqualToString:@"dylib"]) {
			[paths addObject:url.path];
		}
	}
	[paths sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	for (NSString *path in paths) {
		void *handle = dlopen(path.fileSystemRepresentation, RTLD_NOW | RTLD_LOCAL);
		if (!handle) {
			const char *error = dlerror();
			[_pluginErrors addObject:[NSString stringWithFormat:@"%@: %s", path.lastPathComponent, error ? error : "could not load"]];
			continue;
		}
		auto entry = reinterpret_cast<NppMacPluginEntryFn>(dlsym(handle, "NppMacPluginEntry"));
		const NppMacPlugin *plugin = entry ? entry() : nullptr;
		if (!plugin || plugin->abi != NPP_MAC_PLUGIN_ABI) {
			[_pluginErrors addObject:[NSString stringWithFormat:@"%@: not a Simeiomatarion plugin", path.lastPathComponent]];
			dlclose(handle);
			continue;
		}
		const NppMacCommand *commands = nullptr;
		int count = 0;
		if (plugin->on_load) {
			plugin->on_load(&_host, &commands, &count);
		}
		[_plugins addObject:@{
			@"name": @(plugin->name ?: "plugin"),
			@"handle": [NSValue valueWithPointer:handle],
			@"commands": [NSValue valueWithPointer:commands],
			@"count": @(count)
		}];
	}
	for (DocumentTab *document in _documents) {
		[self attachEditorMenu:document];
	}
}

- (void)reloadPlugins:(id)sender {
	(void)sender;
	[self loadPlugins];
	[self buildMenus];
	[self setStatusText:[NSString stringWithFormat:@"Plugins loaded: %lu.", (unsigned long)_plugins.count]];
}

- (void)openPluginsFolder:(id)sender {
	(void)sender;
	[NSWorkspace.sharedWorkspace openURL:[self pluginsDirectory]];
}

- (void)runPluginCommand:(NSMenuItem *)sender {
	NSArray *payload = sender.representedObject;
	NSDictionary *plugin = payload.firstObject;
	int index = [payload[1] intValue];
	const NppMacCommand *commands = (const NppMacCommand *)[plugin[@"commands"] pointerValue];
	if (commands && commands[index].perform) {
		commands[index].perform(&_host, commands[index].user);
	}
}

- (void)writeRecovery {
	NSURL *directory = [SupportDirectory() URLByAppendingPathComponent:@"recovery" isDirectory:YES];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtURL:directory error:nil];
	[files createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
	NSInteger index = 0;
	for (DocumentTab *document in _documents) {
		if (!document.dirty) {
			continue;
		}
		NSString *base = [NSString stringWithFormat:@"doc-%ld", (long)index++];
		NSURL *textURL = [directory URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"txt"]];
		NSURL *metaURL = [directory URLByAppendingPathComponent:[base stringByAppendingPathExtension:@"json"]];
		[[document utf8Text] writeToURL:textURL atomically:YES encoding:NSUTF8StringEncoding error:nil];
		NSDictionary *meta = @{
			@"path": document.path ?: @"",
			@"displayName": document.displayName ?: @"",
			@"encoding": @(document.encoding),
			@"eol": @(document.eolMode),
			@"language": document.language ?: @"normal"
		};
		NSData *data = [NSJSONSerialization dataWithJSONObject:meta options:0 error:nil];
		[data writeToURL:metaURL atomically:YES];
	}
	[self saveSession];
}

- (void)noteDiskRevisionForDocument:(DocumentTab *)document {
	if (document.path.length == 0) {
		document.observedModificationDate = nil;
		document.observedFileSize = 0;
		document.missingOnDiskNoted = NO;
		return;
	}
	NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:document.path error:nil];
	document.observedModificationDate = attributes.fileModificationDate;
	document.observedFileSize = attributes.fileSize;
	document.missingOnDiskNoted = attributes == nil;
}

- (void)placeCaretAt:(NSInteger)position firstLine:(NSInteger)firstLine {
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	long length = [document.editor message:SCI_GETLENGTH];
	if (position < 0) {
		position = 0;
	}
	if (position > length) {
		position = length;
	}
	[document.editor message:SCI_GOTOPOS wParam:(uptr_t)position lParam:0];
	if (firstLine >= 0) {
		[document.editor message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)firstLine lParam:0];
	}
	[document.editor message:SCI_SCROLLCARET];
}

- (void)checkExternalChanges {
	if (_showingReloadPrompt || !_window.isVisible || _window.attachedSheet) {
		return;
	}
	for (DocumentTab *document in [_documents copy]) {
		if (document.path.length == 0 || document.fileMonitoring) {
			continue;
		}
		NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:document.path error:nil];
		if (!attributes) {
			if (document.missingOnDiskNoted) {
				continue;
			}
			document.missingOnDiskNoted = YES;
			_showingReloadPrompt = YES;
			NSAlert *alert = [NSAlert new];
			alert.messageText = @"The file doesn't exist anymore.";
			alert.informativeText = [NSString stringWithFormat:@"%@\n\nKeep this file in the editor?", document.path];
			[alert addButtonWithTitle:@"Keep"];
			[alert addButtonWithTitle:@"Close"];
			NSModalResponse response = [alert runModal];
			_showingReloadPrompt = NO;
			if (response != NSAlertFirstButtonReturn) {
				[_tabs selectTabViewItem:[self itemForDocument:document]];
				document.dirty = NO;
				[self closeDocument:nil];
			}
			return;
		}
		NSDate *modified = attributes.fileModificationDate;
		unsigned long long size = attributes.fileSize;
		if (!document.observedModificationDate) {
			document.observedModificationDate = modified;
			document.observedFileSize = size;
			continue;
		}
		if ([modified isEqualToDate:document.observedModificationDate] && size == document.observedFileSize) {
			continue;
		}
		_showingReloadPrompt = YES;
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		NSAlert *alert = [NSAlert new];
		alert.messageText = @"This file has been modified by another program.";
		alert.informativeText = document.dirty
			? [NSString stringWithFormat:@"%@\n\nReload it and lose the changes made in Simeiomatarion?", document.path]
			: [NSString stringWithFormat:@"%@\n\nReload it?", document.path];
		[alert addButtonWithTitle:@"Reload"];
		[alert addButtonWithTitle:document.dirty ? @"Keep my changes" : @"Keep"];
		NSModalResponse response = [alert runModal];
		_showingReloadPrompt = NO;
		if (response == NSAlertFirstButtonReturn) {
			[document reloadFromDiskScrollingToEnd:NO];
		}
		[self noteDiskRevisionForDocument:document];
		return;
	}
}

- (BOOL)offerRecovery {
	NSURL *directory = [SupportDirectory() URLByAppendingPathComponent:@"recovery" isDirectory:YES];
	NSArray<NSURL *> *files = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:directory includingPropertiesForKeys:nil options:0 error:nil];
	NSMutableArray<NSURL *> *metas = [NSMutableArray array];
	for (NSURL *url in files) {
		if ([url.pathExtension isEqualToString:@"json"]) {
			[metas addObject:url];
		}
	}
	if (metas.count == 0) {
		return NO;
	}
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Recover unsaved Simeiomatarion documents?";
	alert.informativeText = [NSString stringWithFormat:@"%lu recovery file(s) were found.", (unsigned long)metas.count];
	[alert addButtonWithTitle:@"Recover"];
	[alert addButtonWithTitle:@"Discard"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		[[NSFileManager defaultManager] removeItemAtURL:directory error:nil];
		return NO;
	}
	for (NSURL *metaURL in metas) {
		NSDictionary *meta = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:metaURL] options:0 error:nil];
		NSURL *textURL = [[metaURL URLByDeletingPathExtension] URLByAppendingPathExtension:@"txt"];
		NSString *text = [NSString stringWithContentsOfURL:textURL encoding:NSUTF8StringEncoding error:nil] ?: @"";
		DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
		document.path = [meta[@"path"] length] ? meta[@"path"] : nil;
		document.displayName = [meta[@"displayName"] length] ? meta[@"displayName"] : @"Recovered";
		document.encoding = (NppTextEncoding)[meta[@"encoding"] intValue];
		document.eolMode = [meta[@"eol"] intValue];
		[self addDocument:document];
		[document setUtf8Text:text];
		[document applyLanguage:[_catalog languageNamed:meta[@"language"] ?: @"normal"] dark:[self darkAppearance]];
		document.dirty = YES;
	}
	return YES;
}

- (DocumentTab *)documentFromSessionItem:(NSDictionary *)item text:(NSString *)text {
	DocumentTab *document = [[DocumentTab alloc] initWithFrame:_tabs.bounds];
	NSString *path = item[@"path"];
	document.path = path.length ? path : nil;
	document.displayName = [item[@"displayName"] length] ? item[@"displayName"] : (path.lastPathComponent ?: @"Untitled");
	document.encoding = (NppTextEncoding)[item[@"encoding"] intValue];
	document.eolMode = [item[@"eol"] intValue];
	[self addDocument:document];
	[document setUtf8Text:text ?: @""];
	[document.editor message:SCI_SETEOLMODE wParam:(uptr_t)document.eolMode lParam:0];
	document.pinned = [item[@"pinned"] boolValue];
	LangInfo *info = [_userLanguages langInfoNamed:item[@"language"]];
	if (!info) {
		info = [_catalog languageNamed:item[@"language"]];
	}
	if (!info && path.length) {
		info = [_catalog languageForPath:path sample:text];
	}
	if (info) {
		[document applyLanguage:info dark:[self darkAppearance]];
	}
	document.manualLanguage = [item[@"manualLanguage"] boolValue];
	if ([item[@"dirty"] boolValue]) {
		document.dirty = YES;
		[self documentTabDidChange:document];
	}
	[self noteDiskRevisionForDocument:document];
	[self placeCaretAt:[item[@"position"] integerValue] firstLine:[item[@"firstLine"] integerValue]];
	[self restoreOfficeDocument:document];
	return document;
}

- (void)toggleCsvTable:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	NppOfficeRef *office = [self officeRefForDocument:document];
	if (office.kind != NppOfficeKindCSV) {
		return;
	}
	office.showTable = !office.showTable;
	if (office.showTable) {
		NppCsvView *table = [self csvViewForDocument:document];
		[table loadCsv:[document utf8Text] ?: @""];
		if (!table.fitsInTable) {
			office.showTable = NO;
			[self alert:@"This CSV is too large for the table."];
		}
	}
	NSInteger pane = [self paneIndexOfDocument:document];
	if (pane != NSNotFound) {
		[self placeEditor:document inPane:pane];
		[_window makeFirstResponder:office.showTable ? office.view : document.editor];
	}
	[self buildMenus];
	[self refreshStatus];
}

- (void)restoreOfficeDocument:(DocumentTab *)document {
	NppOfficeKind kind = NppOfficeKindForPath(document.path);
	if (kind == NppOfficeKindCSV) {
		[self attachCsvDocument:document];
		NSInteger pane = [self paneIndexOfDocument:document];
		if (pane != NSNotFound) {
			[self placeEditor:document inPane:pane];
		}
		return;
	}
	if (kind == NppOfficeKindXLSX) {
		[self reloadXlsxDocument:document sheet:nil];
		return;
	}
	if (kind != NppOfficeKindPDF && kind != NppOfficeKindDOC && kind != NppOfficeKindDOCX) {
		return;
	}
	NSString *error = nil;
	NSView *surface = nil;
	if (kind == NppOfficeKindPDF) {
		surface = NppPDFViewForPath(document.path, &error);
		if (!surface) {
			return;
		}
	} else {
		NppWordView *word = [[NppWordView alloc] initWithFrame:NSZeroRect];
		if (![word loadPath:document.path kind:kind error:&error]) {
			return;
		}
		surface = word;
		if (!document.dirty) {
			[document.editor setEditable:YES];
			[document.editor message:SCI_SETREADONLY wParam:0 lParam:0];
			[document setUtf8Text:word.plainText ?: @""];
		}
	}
	NppOfficeRef *office = [NppOfficeRef new];
	office.kind = kind;
	office.view = surface;
	[self rememberOffice:office forDocument:document];
	document.manualLanguage = YES;
	document.language = kind == NppOfficeKindPDF ? @"PDF" : @"Word";
	[self lockOfficeText:document];
	NSInteger pane = [self paneIndexOfDocument:document];
	if (pane != NSNotFound) {
		[self placeEditor:document inPane:pane];
	}
}

- (BOOL)restoreSession {
	return [self restoreSessionAtURL:[SupportDirectory() URLByAppendingPathComponent:@"session.json"]];
}

- (BOOL)restoreSessionAtURL:(NSURL *)url {
	id json = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:nil];
	NSArray *items = nil;
	NSInteger selected = 0;
	if ([json isKindOfClass:[NSDictionary class]]) {
		NSDictionary *session = json;
		items = session[@"documents"];
		selected = [session[@"selected"] integerValue];
		NSArray *frame = session[@"frame"];
		if ([frame isKindOfClass:[NSArray class]] && frame.count == 4) {
			_savedWindowFrame = NSMakeRect([frame[0] doubleValue], [frame[1] doubleValue], [frame[2] doubleValue], [frame[3] doubleValue]);
			_hasSavedWindowFrame = _savedWindowFrame.size.width >= 640 && _savedWindowFrame.size.height >= 420;
		}
	} else if ([json isKindOfClass:[NSArray class]]) {
		items = json;
	}
	if (![items isKindOfClass:[NSArray class]] || items.count == 0) {
		return NO;
	}
	NSInteger restored = 0;
	for (NSDictionary *item in items) {
		if (![item isKindOfClass:[NSDictionary class]]) {
			continue;
		}
		NSString *path = item[@"path"];
		BOOL hasText = [item[@"text"] isKindOfClass:[NSString class]];
		if (hasText || [item[@"dirty"] boolValue]) {
			[self documentFromSessionItem:item text:hasText ? item[@"text"] : @""];
			restored++;
			continue;
		}
		if (path.length && [self openPath:path]) {
			[self placeCaretAt:[item[@"position"] integerValue] firstLine:[item[@"firstLine"] integerValue]];
			restored++;
		}
	}
	NSArray *panes = [json isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)json)[@"panes"] : nil;
	NSInteger activePane = [json isKindOfClass:[NSDictionary class]] ? [((NSDictionary *)json)[@"activePane"] integerValue] : 0;
	[self restorePanes:panes active:activePane fallback:selected];
	NSString *folder = [json isKindOfClass:[NSDictionary class]] ? ((NSDictionary *)json)[@"folder"] : nil;
	if ([folder isKindOfClass:[NSString class]] && folder.length) {
		[self showFolderAtPath:folder];
	}
	if ([json isKindOfClass:[NSDictionary class]]) {
		[self restoreClone:((NSDictionary *)json)[@"clone"]];
	}
	return restored > 0;
}

- (DocumentTab *)documentMatchingPaneEntry:(NSDictionary *)entry {
	if (![entry isKindOfClass:[NSDictionary class]]) {
		return nil;
	}
	NSString *path = [entry[@"path"] isKindOfClass:[NSString class]] ? entry[@"path"] : @"";
	NSInteger documentIndex = [entry[@"document"] integerValue];
	DocumentTab *document = path.length ? [self documentForPath:path] : nil;
	if (!document && path.length == 0 && documentIndex >= 0 && documentIndex < (NSInteger)_documents.count) {
		DocumentTab *candidate = _documents[documentIndex];
		if (candidate.path.length == 0) {
			document = candidate;
		}
	}
	return document;
}

- (void)restorePanes:(NSArray *)panes active:(NSInteger)active fallback:(NSInteger)selected {
	if (![panes isKindOfClass:[NSArray class]] || panes.count == 0 || !_splitHost) {
		if (selected >= 0 && selected < (NSInteger)_documents.count) {
			[self showDocument:_documents[selected] inPane:0];
		}
		return;
	}
	NSInteger count = MIN((NSInteger)panes.count, 6);
	for (id shown in _paneDocuments) {
		if ([shown isKindOfClass:[DocumentTab class]]) {
			[((DocumentTab *)shown).editor removeFromSuperview];
		}
	}
	_paneDocuments = [NSMutableArray array];
	_paneTabs = [NSMutableArray array];
	NSMutableArray<NSNumber *> *fractions = [NSMutableArray array];
	NSMutableSet *used = [NSMutableSet set];
	for (NSInteger index = 0; index < count; index++) {
		NSDictionary *pane = [panes[index] isKindOfClass:[NSDictionary class]] ? panes[index] : @{};
		NSMutableArray<DocumentTab *> *tabs = [NSMutableArray array];
		NSArray *savedTabs = [pane[@"tabs"] isKindOfClass:[NSArray class]] ? pane[@"tabs"] : nil;
		for (id entry in savedTabs) {
			DocumentTab *tab = [self documentMatchingPaneEntry:entry];
			if (tab && ![used containsObject:tab]) {
				[tabs addObject:tab];
				[used addObject:tab];
			}
		}
		DocumentTab *visible = [self documentMatchingPaneEntry:pane];
		if (visible && ![tabs containsObject:visible] && ![used containsObject:visible]) {
			[tabs insertObject:visible atIndex:0];
			[used addObject:visible];
		}
		if (!visible || ![tabs containsObject:visible]) {
			visible = tabs.firstObject;
		}
		[_paneTabs addObject:tabs];
		[_paneDocuments addObject:visible ?: (id)[NSNull null]];
		double fraction = [pane[@"fraction"] doubleValue];
		[fractions addObject:@(fraction > 0 ? fraction : 1.0)];
	}
	if (_paneTabs.count == 0) {
		_paneTabs = [NSMutableArray arrayWithObject:[NSMutableArray array]];
		_paneDocuments = [NSMutableArray arrayWithObject:[NSNull null]];
	}
	for (DocumentTab *document in _documents) {
		if ([used containsObject:document]) {
			continue;
		}
		[_paneTabs[0] addObject:document];
		if (_paneDocuments[0] == [NSNull null]) {
			_paneDocuments[0] = document;
		}
	}
	[_splitHost setPaneCount:count];
	[_splitHost setFractions:fractions];
	for (NSInteger index = 0; index < count; index++) {
		id document = _paneDocuments[index];
		if ([document isKindOfClass:[DocumentTab class]]) {
			[self placeEditor:document inPane:index];
		}
	}
	if (active < 0 || active >= count) {
		active = 0;
	}
	_activePane = active;
	id activeDocument = _paneDocuments[active];
	if ([activeDocument isKindOfClass:[DocumentTab class]]) {
		[_tabs selectTabViewItem:[self itemForDocument:activeDocument]];
		[_window makeFirstResponder:((DocumentTab *)activeDocument).editor];
	}
	[_splitHost setActivePane:_activePane];
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)saveSession {
	NSMutableArray *documents = [NSMutableArray array];
	for (DocumentTab *document in _documents) {
		long position = [document.editor message:SCI_GETCURRENTPOS];
		long firstLine = [document.editor message:SCI_GETFIRSTVISIBLELINE];
		BOOL discard = _discardUnsavedSession && (document.dirty || document.path.length == 0);
		BOOL keepText = !discard && (document.dirty || document.path.length == 0);
		NSMutableDictionary *item = [@{
			@"path": document.path ?: @"",
			@"displayName": document.displayName ?: @"",
			@"encoding": @(document.encoding),
			@"eol": @(document.eolMode),
			@"language": document.language ?: @"normal",
			@"manualLanguage": @(document.manualLanguage),
			@"position": @(position),
			@"firstLine": @(firstLine),
			@"dirty": @(discard ? NO : document.dirty),
			@"pinned": @(document.pinned)
		} mutableCopy];
		if (keepText) {
			item[@"text"] = [document utf8Text] ?: @"";
		}
		[documents addObject:item];
	}
	NSRect frame = _window.frame;
	NSInteger selected = [_documents indexOfObject:[self currentDocument]];
	if (selected == NSNotFound) {
		selected = 0;
	}
	NSMutableArray *panes = [NSMutableArray array];
	NSArray<NSNumber *> *fractions = _splitHost ? [_splitHost fractions] : @[];
	for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
		id shown = _paneDocuments[index];
		DocumentTab *shownDocument = [shown isKindOfClass:[DocumentTab class]] ? shown : nil;
		NSInteger documentIndex = shownDocument ? [_documents indexOfObject:shownDocument] : NSNotFound;
		CGFloat fraction = index < (NSInteger)fractions.count ? fractions[index].doubleValue : 1.0;
		NSMutableArray *tabEntries = [NSMutableArray array];
		NSArray *tabs = index < (NSInteger)_paneTabs.count ? _paneTabs[index] : @[];
		for (DocumentTab *tab in tabs) {
			if (![tab isKindOfClass:[DocumentTab class]]) {
				continue;
			}
			NSInteger tabIndex = [_documents indexOfObject:tab];
			[tabEntries addObject:@{
				@"document": @(tabIndex == NSNotFound ? -1 : tabIndex),
				@"path": tab.path ?: @""
			}];
		}
		[panes addObject:@{
			@"document": @(documentIndex == NSNotFound ? -1 : documentIndex),
			@"path": shownDocument.path ?: @"",
			@"fraction": @(fraction),
			@"tabs": tabEntries
		}];
	}
	NSDictionary *session = @{
		@"selected": @(selected),
		@"activePane": @(_activePane),
		@"frame": @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
		@"documents": documents,
		@"panes": panes,
		@"folder": (_workspace.sidebarVisible && _folderRoot.length) ? _folderRoot : @"",
		@"clone": (_cloneSource && _clonePane != NSNotFound) ? @{@"document": @([_documents indexOfObject:_cloneSource]), @"pane": @(_clonePane)} : @{}
	};
	NSData *data = [NSJSONSerialization dataWithJSONObject:session options:0 error:nil];
	[data writeToURL:[SupportDirectory() URLByAppendingPathComponent:@"session.json"] atomically:YES];
}

- (void)applicationWillResignActive:(NSNotification *)notification {
	(void)notification;
	[self saveSession];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender {
	(void)sender;
	if (![self confirmClosingDocuments:[_documents copy] grouped:YES]) {
		_discardUnsavedSession = NO;
		return NSTerminateCancel;
	}
	_closingWithoutPrompt = YES;
	[self saveSession];
	_discardUnsavedSession = NO;
	[[NSFileManager defaultManager] removeItemAtURL:[SupportDirectory() URLByAppendingPathComponent:@"recovery"] error:nil];
	return NSTerminateNow;
}

- (BOOL)application:(NSApplication *)sender openFile:(NSString *)filename {
	(void)sender;
	if (filename.length == 0) {
		return NO;
	}
	return [self openDroppedPaths:@[filename]];
}

- (void)application:(NSApplication *)sender openFiles:(NSArray<NSString *> *)filenames {
	(void)sender;
	[self openDroppedPaths:filenames];
	[NSApp replyToOpenOrPrint:NSApplicationDelegateReplySuccess];
}

- (NSURL *)sessionsDirectory {
	NSURL *directory = [SupportDirectory() URLByAppendingPathComponent:@"sessions" isDirectory:YES];
	[[NSFileManager defaultManager] createDirectoryAtURL:directory withIntermediateDirectories:YES attributes:nil error:nil];
	return directory;
}

- (NSArray<NSString *> *)namedSessionTitles {
	NSMutableArray<NSString *> *names = [NSMutableArray array];
	for (NSURL *url in [[NSFileManager defaultManager] contentsOfDirectoryAtURL:[self sessionsDirectory] includingPropertiesForKeys:nil options:0 error:nil]) {
		if ([url.pathExtension isEqualToString:@"json"]) {
			[names addObject:url.URLByDeletingPathExtension.lastPathComponent];
		}
	}
	[names sortUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	return names;
}

- (void)saveNamedSession:(id)sender {
	(void)sender;
	NSAlert *alert = [NSAlert new];
	alert.messageText = @"Save Session";
	NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
	field.placeholderString = @"Name";
	alert.accessoryView = field;
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	NSString *name = [field.stringValue stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	NSCharacterSet *bad = [NSCharacterSet characterSetWithCharactersInString:@"/\\:"];
	if (name.length == 0 || [name rangeOfCharacterFromSet:bad].location != NSNotFound) {
		[self alert:@"Use a session name without slashes."];
		return;
	}
	[self saveSession];
	NSURL *source = [SupportDirectory() URLByAppendingPathComponent:@"session.json"];
	NSURL *dest = [[self sessionsDirectory] URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
	[[NSFileManager defaultManager] removeItemAtURL:dest error:nil];
	if (![[NSFileManager defaultManager] copyItemAtURL:source toURL:dest error:nil]) {
		[self alert:@"The session could not be saved."];
		return;
	}
	[self buildMenus];
	[self setStatusText:[NSString stringWithFormat:@"Saved session \"%@\".", name]];
}

- (void)openNamedSession:(NSMenuItem *)sender {
	NSString *name = sender.representedObject;
	if (![name isKindOfClass:[NSString class]] || name.length == 0) {
		return;
	}
	if (_documents.count && ![self confirmClosingDocuments:[_documents copy] grouped:YES]) {
		return;
	}
	NSURL *url = [[self sessionsDirectory] URLByAppendingPathComponent:[name stringByAppendingPathExtension:@"json"]];
	_closingWithoutPrompt = YES;
	_suppressEmptyDocument = YES;
	for (DocumentTab *document in [_documents copy]) {
		NSTabViewItem *item = [self itemForDocument:document];
		if (item) {
			[_tabs selectTabViewItem:item];
		}
		[self closeDocument:nil];
	}
	_suppressEmptyDocument = NO;
	_closingWithoutPrompt = NO;
	_cloneSource = nil;
	_clonePane = NSNotFound;
	_paneDocuments = [NSMutableArray arrayWithObject:[NSNull null]];
	_paneTabs = [NSMutableArray arrayWithObject:[NSMutableArray array]];
	_activePane = 0;
	[_splitHost setPaneCount:1];
	if (![self restoreSessionAtURL:url]) {
		[self newDocument:nil];
		[self alert:@"That session could not be opened."];
	}
	[self buildMenus];
}

- (void)restoreClone:(NSDictionary *)clone {
	if (![clone isKindOfClass:[NSDictionary class]] || clone[@"document"] == nil) {
		return;
	}
	NSInteger index = [clone[@"document"] integerValue];
	NSInteger pane = [clone[@"pane"] integerValue];
	if (index < 0 || index >= (NSInteger)_documents.count || pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
		return;
	}
	DocumentTab *document = _documents[index];
	NSInteger source = [self paneIndexOfDocument:document];
	if (source == NSNotFound || source == pane) {
		return;
	}
	_cloneSource = document;
	_clonePane = pane;
	NSMutableArray *tabs = [self tabsForPane:pane];
	if (tabs && ![tabs containsObject:document]) {
		[tabs insertObject:document atIndex:0];
	}
	_paneDocuments[pane] = document;
	[self placeEditor:document inPane:source];
	[self placeEditor:document inPane:pane];
	[self rebuildTabStrip];
}

- (void)insertEmptyPaneAt:(NSInteger)insert {
	if (_paneDocuments.count >= 6 || insert < 0 || insert > (NSInteger)_paneDocuments.count) {
		return;
	}
	NSMutableArray<NSNumber *> *fractions = [[_splitHost fractions] mutableCopy];
	if (fractions.count != _paneDocuments.count) {
		fractions = [NSMutableArray array];
		CGFloat share = 1.0 / MAX(1, _paneDocuments.count);
		for (NSInteger index = 0; index < (NSInteger)_paneDocuments.count; index++) {
			[fractions addObject:@(share)];
		}
	}
	NSInteger donor = insert > 0 ? insert - 1 : 0;
	CGFloat half = fractions[donor].doubleValue / 2.0;
	fractions[donor] = @(half);
	[fractions insertObject:@(half) atIndex:insert];
	[_paneDocuments insertObject:[NSNull null] atIndex:insert];
	[_paneTabs insertObject:[NSMutableArray array] atIndex:insert];
	[_splitHost setPaneCount:_paneDocuments.count];
	[_splitHost setFractions:fractions];
	if (insert <= _activePane) {
		_activePane++;
	}
	[self relayoutPaneEditors];
}

- (void)focusClone {
	if (!_cloneSource || _clonePane < 0 || _clonePane >= (NSInteger)_paneDocuments.count) {
		return;
	}
	_activePane = _clonePane;
	[_splitHost setActivePane:_clonePane];
	[_tabs selectTabViewItem:[self itemForDocument:_cloneSource]];
	[_window makeFirstResponder:[_cloneSource existingMirror]];
	[self rebuildTabStrip];
	[self refreshStatus];
}

- (void)dropClone {
	if (!_cloneSource) {
		return;
	}
	DocumentTab *source = _cloneSource;
	NSInteger pane = _clonePane;
	_cloneSource = nil;
	_clonePane = NSNotFound;
	[source discardMirror];
	if (pane >= 0 && pane < (NSInteger)_paneTabs.count) {
		NSMutableArray *tabs = _paneTabs[pane];
		[tabs removeObject:source];
		if (_paneDocuments[pane] == source) {
			_paneDocuments[pane] = tabs.count ? tabs[0] : [NSNull null];
		}
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
		[slot removeEditorViews];
		id shown = _paneDocuments[pane];
		if ([shown isKindOfClass:[DocumentTab class]]) {
			[self placeEditor:shown inPane:pane];
		}
		if (tabs.count == 0 && _paneDocuments.count > 1) {
			[self closeEmptyPane:pane];
		}
	}
	[self rebuildTabStrip];
	[self saveSession];
}

- (void)cloneBeside:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	if (_cloneSource == document && _clonePane != NSNotFound) {
		[self focusClone];
		return;
	}
	[self dropClone];
	NSInteger source = [self paneIndexOfDocument:document];
	if (source == NSNotFound) {
		return;
	}
	NSInteger dest = source + 1;
	if (dest >= (NSInteger)_paneDocuments.count) {
		if (_paneDocuments.count >= 6) {
			[self setStatusText:@"No room for another pane."];
			return;
		}
		[self insertEmptyPaneAt:dest];
	}
	if (dest >= (NSInteger)_paneDocuments.count) {
		return;
	}
	_cloneSource = document;
	_clonePane = dest;
	NSMutableArray<DocumentTab *> *tabs = [self tabsForPane:dest];
	if (tabs && ![tabs containsObject:document]) {
		[tabs insertObject:document atIndex:0];
	}
	_paneDocuments[dest] = document;
	[self placeEditor:document inPane:source];
	[self placeEditor:document inPane:dest];
	[self focusClone];
	[self saveSession];
	[self setStatusText:@"The same file is open in both panes."];
}

- (void)togglePin:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	document.pinned = !document.pinned;
	NSInteger pane = [self paneIndexOfDocument:document];
	NSMutableArray<DocumentTab *> *tabs = [self tabsForPane:pane];
	if (document.pinned && tabs && [tabs containsObject:document]) {
		[tabs removeObject:document];
		[tabs insertObject:document atIndex:0];
	}
	[self rebuildTabStrip];
	[self saveSession];
	[self setStatusText:document.pinned ? @"Tab pinned. Close All leaves it open." : @"Tab unpinned."];
}

- (BOOL)expandSnippet {
	ScintillaView *editor = [self activeEditor];
	if (!editor || [editor message:SCI_GETSELECTIONS] > 1) {
		return NO;
	}
	long position = [editor message:SCI_GETCURRENTPOS];
	long start = [editor message:SCI_WORDSTARTPOSITION wParam:(uptr_t)position lParam:1];
	if (start >= position || position - start > 40) {
		return NO;
	}
	long length = position - start;
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = start;
	range.chrg.cpMax = position;
	range.lpstrText = buffer.data();
	[editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	NSString *name = [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)length encoding:NSUTF8StringEncoding];
	NSString *body = [_snippets bodyForName:name];
	if (!body) {
		return NO;
	}
	[editor message:SCI_SETSEL wParam:(uptr_t)start lParam:(sptr_t)position];
	const char *bytes = body.UTF8String ?: "";
	[editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
	return YES;
}

- (void)addNextOccurrence:(id)sender {
	(void)sender;
	ScintillaView *editor = [self activeEditor];
	if (!editor) {
		return;
	}
	long selStart = [editor message:SCI_GETSELECTIONSTART];
	long selEnd = [editor message:SCI_GETSELECTIONEND];
	if (selStart == selEnd) {
		long position = [editor message:SCI_GETCURRENTPOS];
		selStart = [editor message:SCI_WORDSTARTPOSITION wParam:(uptr_t)position lParam:1];
		selEnd = [editor message:SCI_WORDENDPOSITION wParam:(uptr_t)position lParam:1];
		if (selEnd <= selStart) {
			return;
		}
		[editor message:SCI_SETSEL wParam:(uptr_t)selStart lParam:(sptr_t)selEnd];
	}
	long length = selEnd - selStart;
	if (length <= 0 || length > 400) {
		return;
	}
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = selStart;
	range.chrg.cpMax = selEnd;
	range.lpstrText = buffer.data();
	[editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	long selections = [editor message:SCI_GETSELECTIONS];
	long after = 0;
	for (long index = 0; index < selections; index++) {
		long end = [editor message:SCI_GETSELECTIONNEND wParam:(uptr_t)index lParam:0];
		if (end > after) {
			after = end;
		}
	}
	long docLength = [editor message:SCI_GETLENGTH];
	[editor message:SCI_SETSEARCHFLAGS wParam:SCFIND_MATCHCASE lParam:0];
	[editor message:SCI_SETTARGETSTART wParam:(uptr_t)after lParam:0];
	[editor message:SCI_SETTARGETEND wParam:(uptr_t)docLength lParam:0];
	long found = [editor message:SCI_SEARCHINTARGET wParam:(uptr_t)length lParam:(sptr_t)buffer.data()];
	if (found < 0) {
		long first = [editor message:SCI_GETSELECTIONNSTART wParam:0 lParam:0];
		[editor message:SCI_SETTARGETSTART wParam:0 lParam:0];
		[editor message:SCI_SETTARGETEND wParam:(uptr_t)first lParam:0];
		found = [editor message:SCI_SEARCHINTARGET wParam:(uptr_t)length lParam:(sptr_t)buffer.data()];
	}
	if (found < 0) {
		return;
	}
	long targetStart = [editor message:SCI_GETTARGETSTART];
	long targetEnd = [editor message:SCI_GETTARGETEND];
	[editor message:SCI_ADDSELECTION wParam:(uptr_t)targetEnd lParam:(sptr_t)targetStart];
	[editor message:SCI_SCROLLCARET];
}

- (NSEvent *)handleExtraCaretClick:(NSEvent *)event {
	if (event.window != _window) {
		return event;
	}
	NSEventModifierFlags flags = event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
	BOOL command = (flags & NSEventModifierFlagCommand) != 0;
	BOOL other = (flags & (NSEventModifierFlagOption | NSEventModifierFlagShift | NSEventModifierFlagControl)) != 0;
	if (!command || other) {
		return event;
	}
	NSView *hit = [_window.contentView hitTest:event.locationInWindow];
	ScintillaView *editor = nil;
	BOOL inContent = NO;
	for (NSView *view = hit; view; view = view.superview) {
		if ([NSStringFromClass(view.class) isEqualToString:@"SCIContentView"]) {
			inContent = YES;
		}
		if ([view isKindOfClass:[ScintillaView class]]) {
			editor = (ScintillaView *)view;
			break;
		}
	}
	if (!editor || !inContent) {
		return event;
	}
	NSView *content = hit;
	while (content && ![NSStringFromClass(content.class) isEqualToString:@"SCIContentView"]) {
		content = content.superview;
	}
	NSPoint local = [(content ?: editor) convertPoint:event.locationInWindow fromView:nil];
	long position = [editor message:SCI_CHARPOSITIONFROMPOINTCLOSE wParam:(uptr_t)MAX(0, (int)local.x) lParam:(sptr_t)MAX(0, (int)local.y)];
	if (position < 0) {
		return event;
	}
	[editor message:SCI_ADDSELECTION wParam:(uptr_t)position lParam:(sptr_t)position];
	[_window makeFirstResponder:editor];
	return nil;
}

- (void)showSidebarPage:(NSInteger)page {
	_sidebarPage = page;
	_workspace.sidebarVisible = YES;
	NSButton *button = [_sidebar viewWithTag:5];
	NSString *toggleSymbol = page == 1 ? @"folder" : @"list.bullet.indent";
	NSImage *toggleImage = [NSImage imageWithSystemSymbolName:toggleSymbol accessibilityDescription:page == 1 ? @"Folder" : @"Symbols"];
	toggleImage.size = NSMakeSize(13, 13);
	button.image = toggleImage;
	button.title = @"";
	button.toolTip = page == 1 ? NppL(@"Folder") : NppL(@"Symbols");
	NSImageView *glyph = [_sidebar viewWithTag:6];
	glyph.image = page == 1
		? NppTintedSymbol(@"list.bullet.indent", NSColor.controlAccentColor)
		: NppTintedSymbol(@"folder.fill", NSColor.systemBlueColor);
	NSTextField *title = [_sidebar viewWithTag:1];
	if (page == 1) {
		title.stringValue = NppL(@"Outline");
	} else if (_folderRoot.lastPathComponent.length) {
		title.stringValue = _folderRoot.lastPathComponent;
	} else {
		title.stringValue = NppL(@"Folder");
	}
	[_workspace layoutPanes];
	[self layoutFolderSidebar];
	if (page == 1) {
		[self reloadOutline];
	}
}

- (void)showOutline:(id)sender {
	(void)sender;
	if (_sidebarPage == 1 && _workspace.sidebarVisible) {
		if (_folderRoot.length) {
			[self showSidebarPage:0];
		} else {
			_workspace.sidebarVisible = NO;
			[_workspace layoutPanes];
		}
		return;
	}
	[self showSidebarPage:1];
}

- (void)toggleFolderSidebar:(id)sender {
	(void)sender;
	if (_workspace.sidebarVisible && _sidebarPage == 0) {
		[self closeFolderSidebar:nil];
		return;
	}
	if (_folderRoot.length == 0) {
		[self openFolder:nil];
		return;
	}
	[self showSidebarPage:0];
}

- (void)reloadOutline {
	DocumentTab *document = [self currentDocument];
	_outlineRows = document ? NppOutlineSymbols(document.language, document.lexerName, [document utf8Text] ?: @"") : @[];
	[_outlineTable reloadData];
}

- (void)openOutlineRow:(id)sender {
	(void)sender;
	NSInteger row = _outlineTable.clickedRow;
	if (row < 0) {
		row = _outlineTable.selectedRow;
	}
	if (row < 0 || row >= (NSInteger)_outlineRows.count) {
		return;
	}
	ScintillaView *editor = [self activeEditor];
	long line = _outlineRows[row].line - 1;
	[editor message:SCI_GOTOLINE wParam:(uptr_t)MAX(0, line) lParam:0];
	[editor message:SCI_SCROLLCARET];
	[_window makeFirstResponder:editor];
}

- (NppMinimapView *)minimapForSlot:(NppPaneSlot *)slot pane:(NSInteger)pane {
	NppMinimapView *map = nil;
	for (NSView *view in slot.subviews) {
		if ([view isKindOfClass:[NppMinimapView class]]) {
			map = (NppMinimapView *)view;
			break;
		}
	}
	if (!map) {
		map = [[NppMinimapView alloc] initWithFrame:NSZeroRect];
		map.identifier = @"npp.minimap";
		map.target = self;
		map.action = @selector(minimapJump:);
		[slot addSubview:map];
	}
	map.hoverAction = @selector(minimapHover:);
	map.pane = pane;
	map.hidden = !_settings.showMinimap;
	return map;
}

- (void)attachMinimapToSlot:(NppPaneSlot *)slot forDocument:(DocumentTab *)document {
	(void)document;
	[self minimapForSlot:slot pane:slot.paneIndex];
}

- (void)updateMinimapViewport:(DocumentTab *)document {
	NSInteger pane = [self paneIndexOfDocument:document];
	if (document == _cloneSource && _activePane == _clonePane) {
		pane = _clonePane;
	}
	if (pane == NSNotFound) {
		return;
	}
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
	NppMinimapView *map = nil;
	for (NSView *view in slot.subviews) {
		if ([view isKindOfClass:[NppMinimapView class]]) {
			map = (NppMinimapView *)view;
			break;
		}
	}
	if (!map || map.hidden) {
		return;
	}
	ScintillaView *editor = [self editorForDocument:document inPane:pane];
	long lines = MAX(1, [editor message:SCI_GETLINECOUNT]);
	long first = [editor message:SCI_GETFIRSTVISIBLELINE];
	long visible = MAX(1, [editor message:SCI_LINESONSCREEN]);
	map.viewportStart = (CGFloat)first / (CGFloat)lines;
	map.viewportScale = (CGFloat)visible / (CGFloat)lines;
	[map setNeedsDisplay:YES];
}

- (void)refreshMinimapForDocument:(DocumentTab *)document inPane:(NSInteger)pane {
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
	if (![slot isKindOfClass:[NppPaneSlot class]]) {
		return;
	}
	NppMinimapView *map = [self minimapForSlot:slot pane:pane];
	if (map.hidden) {
		[slot layoutContents];
		return;
	}
	ScintillaView *editor = [self editorForDocument:document inPane:pane];
	long lines = MAX(1, [editor message:SCI_GETLINECOUNT]);
	NSInteger step = MAX(1, (NSInteger)lines / 400);
	NSMutableArray<NSNumber *> *widths = [NSMutableArray array];
	for (long line = 0; line < lines; line += step) {
		long length = [editor message:SCI_LINELENGTH wParam:(uptr_t)line lParam:0];
		[widths addObject:@(MIN(180, MAX(0, length)))];
	}
	map.lineWidths = widths;
	long first = [editor message:SCI_GETFIRSTVISIBLELINE];
	long visible = MAX(1, [editor message:SCI_LINESONSCREEN]);
	map.viewportStart = (CGFloat)first / (CGFloat)lines;
	map.viewportScale = (CGFloat)visible / (CGFloat)lines;
	[map setNeedsDisplay:YES];
	[slot layoutContents];
}

- (NSRect)zoomCardScreenRect {
	if (!_zoomCard || _zoomCard.hidden || !_zoomCard.window) {
		return NSZeroRect;
	}
	return [_zoomCard.window convertRectToScreen:[_zoomCard convertRect:_zoomCard.bounds toView:nil]];
}

- (BOOL)mouseIsOverZoomPanel {
	NSRect card = NSInsetRect([self zoomCardScreenRect], -28, -28);
	if (!NSIsEmptyRect(card) && NSPointInRect(NSEvent.mouseLocation, card)) {
		return YES;
	}
	if (_zoomMap && !_zoomMap.hidden && _zoomMap.window) {
		NSRect map = [_zoomMap.window convertRectToScreen:[_zoomMap convertRect:_zoomMap.bounds toView:nil]];
		if (NSPointInRect(NSEvent.mouseLocation, NSInsetRect(map, -12, -12))) {
			return YES;
		}
	}
	return NO;
}

- (void)scheduleZoomHide {
	NSInteger token = ++_zoomHideGeneration;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.25 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		if (token != self->_zoomHideGeneration || [self mouseIsOverZoomPanel]) {
			return;
		}
		[self hideZoomPanel];
	});
}

- (void)hideZoomPanel {
	++_zoomHideGeneration;
	[_zoomPanel orderOut:nil];
	_zoomCard.hidden = YES;
	[_zoomCard removeFromSuperview];
	_zoomMap = nil;
}

- (NppMinimapZoom *)zoomCard {
	if (_zoomCard) {
		return _zoomCard;
	}
	_zoomCard = [[NppMinimapZoom alloc] initWithFrame:NSMakeRect(0, 0, 240, 200)];
	_zoomCard.identifier = @"npp.minimapZoom";
	_zoomCard.translatesAutoresizingMaskIntoConstraints = YES;
	_zoomCard.autoresizingMask = NSViewNotSizable;
	_zoomCard.wantsLayer = YES;
	_zoomCard.layer.shadowColor = NSColor.blackColor.CGColor;
	_zoomCard.layer.shadowOpacity = 0.28f;
	_zoomCard.layer.shadowRadius = 10;
	_zoomCard.layer.shadowOffset = CGSizeMake(0, -1);
	_zoomCard.target = self;
	_zoomCard.action = @selector(minimapZoomJump:);
	_zoomCard.exitAction = @selector(minimapZoomExited:);
	_zoomCard.clickedLine = -1;
	if (!_zoomClickMonitor) {
		__weak AppDelegate *weakSelf = self;
		_zoomClickMonitor = [NSEvent addLocalMonitorForEventsMatchingMask:NSEventMaskLeftMouseDown handler:^NSEvent *(NSEvent *event) {
			AppDelegate *strongSelf = weakSelf;
			return strongSelf ? [strongSelf zoomClickEvent:event] : event;
		}];
	}
	return _zoomCard;
}

- (NSEvent *)zoomClickEvent:(NSEvent *)event {
	if (event.window != _window || !_zoomCard.superview || _zoomCard.hidden || _zoomCard.rowNumbers.count == 0) {
		return event;
	}
	NSPoint inContent = [_zoomCard.superview convertPoint:event.locationInWindow fromView:nil];
	if (!NSPointInRect(inContent, _zoomCard.frame)) {
		return event;
	}
	[_zoomCard clickAtViewPoint:[_zoomCard convertPoint:event.locationInWindow fromView:nil]];
	return nil;
}

- (void)minimapHover:(NppMinimapView *)sender {
	NppPaneSlot *slot = [sender.superview isKindOfClass:[NppPaneSlot class]] ? (NppPaneSlot *)sender.superview : nil;
	if (!slot) {
		return;
	}
	if (!sender.hovering || sender.hidden) {
		[self scheduleZoomHide];
		return;
	}
	++_zoomHideGeneration;
	NSInteger pane = sender.pane;
	id shown = (pane >= 0 && pane < (NSInteger)_paneDocuments.count) ? _paneDocuments[pane] : nil;
	DocumentTab *document = [shown isKindOfClass:[DocumentTab class]] ? shown : [self currentDocument];
	ScintillaView *editor = document ? [self editorForDocument:document inPane:pane] : nil;
	if (!editor) {
		[self hideZoomPanel];
		return;
	}
	long lineCount = MAX(1, [editor message:SCI_GETLINECOUNT]);
	long focus = MIN(lineCount - 1, MAX(0, (long)(sender.hoverFraction * lineCount)));
	NSInteger capacity = MIN(18, MAX(5, (NSInteger)((NSHeight(sender.frame) - 16) / 17)));
	long startLine = MAX(0, focus - capacity / 2);
	long endLine = MIN(lineCount, startLine + capacity);
	startLine = MAX(0, endLine - capacity);
	NSMutableArray<NSString *> *rows = [NSMutableArray array];
	NSMutableArray<NSNumber *> *numbers = [NSMutableArray array];
	NSFont *font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	CGFloat textWidth = 80;
	for (long line = startLine; line < endLine; line++) {
		NSString *text = NppZoomLine(editor, line);
		[rows addObject:text];
		[numbers addObject:@(line + 1)];
		textWidth = MAX(textWidth, ceil([text sizeWithAttributes:@{NSFontAttributeName: font}].width));
	}
	CGFloat available = NSMinX(sender.frame) - 16;
	if (available < 140) {
		[self hideZoomPanel];
		return;
	}
	NppMinimapZoom *zoom = [self zoomCard];
	zoom.pane = pane;
	_zoomMap = sender;
	zoom.rows = rows;
	zoom.rowNumbers = numbers;
	zoom.focusLine = focus + 1;
	CGFloat width = MIN(textWidth + 74, available);
	width = MAX(180, MIN(width, available));
	CGFloat height = rows.count * 17 + 16;
	CGFloat focusIndex = focus - startLine;
	CGFloat focusCenter = 8 + focusIndex * 17 + 8.5;
	NSRect mapInWindow = [sender convertRect:sender.bounds toView:nil];
	NSView *content = _window.contentView;
	NSRect mapInContent = [content convertRect:mapInWindow fromView:nil];
	NSPoint mouseInContent = [content convertPoint:[_window convertPointFromScreen:NSEvent.mouseLocation] fromView:nil];
	CGFloat x = NSMinX(mapInContent) - width + 10;
	CGFloat y = mouseInContent.y - height + focusCenter;
	NSRect bounds = content.bounds;
	x = MIN(MAX(NSMinX(bounds) + 8, x), NSMaxX(bounds) - width - 8);
	y = MIN(MAX(NSMinY(bounds) + 8, y), NSMaxY(bounds) - height - 8);
	zoom.hidden = NO;
	zoom.frame = NSMakeRect(x, y, width, height);
	zoom.layer.zPosition = 1000;
	[content addSubview:zoom positioned:NSWindowAbove relativeTo:nil];
	[zoom setNeedsDisplay:YES];
}

- (void)hideMinimapZoomInSlot:(NSView *)slot {
	(void)slot;
	[self hideZoomPanel];
}

- (void)placeCaretInEditor:(ScintillaView *)editor line:(long)line column:(long)column {
	if (!editor) {
		return;
	}
	long lines = MAX(1, [editor message:SCI_GETLINECOUNT]);
	line = MIN(lines - 1, MAX(0, line));
	[editor message:SCI_ENSUREVISIBLE wParam:(uptr_t)line lParam:0];
	[editor message:SCI_GOTOLINE wParam:(uptr_t)line lParam:0];
	long pos = column < 0 ? [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)line lParam:0] : NppZoomColumnPosition(editor, line, column);
	[editor message:SCI_GOTOPOS wParam:(uptr_t)pos lParam:0];
	[editor message:SCI_SETEMPTYSELECTION wParam:(uptr_t)pos lParam:0];
	[self revealLine:line position:pos inEditor:editor];
	[self focusEditorForTyping:editor position:pos];
	dispatch_async(dispatch_get_main_queue(), ^{
		[self hideZoomPanel];
		[self revealLine:line position:pos inEditor:editor];
		[self focusEditorForTyping:editor position:pos];
	});
}

- (void)focusEditorForTyping:(ScintillaView *)editor position:(long)pos {
	if (!editor) {
		return;
	}
	[editor message:SCI_SETEMPTYSELECTION wParam:(uptr_t)pos lParam:0];
	[editor message:SCI_SCROLLCARET];
	NSView *typing = editor.content ?: editor;
	[_window makeKeyAndOrderFront:nil];
	[_window makeFirstResponder:typing];
	[editor message:SCI_SETFOCUS wParam:1 lParam:0];
	_statusOverride = nil;
	[self refreshStatus];
}

- (ScintillaView *)visibleEditorInPane:(NSInteger)pane document:(DocumentTab *)document {
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
	if ([slot isKindOfClass:[NppPaneSlot class]]) {
		for (NSView *subview in slot.subviews) {
			if ([subview isKindOfClass:[ScintillaView class]] && subview.window) {
				return (ScintillaView *)subview;
			}
		}
	}
	return document ? [self editorForDocument:document inPane:pane] : nil;
}

- (void)revealLine:(long)line position:(long)pos inEditor:(ScintillaView *)editor {
	if (!editor) {
		return;
	}
	long displayLine = [editor message:SCI_VISIBLEFROMDOCLINE wParam:(uptr_t)line lParam:0];
	long page = MAX(1, [editor message:SCI_LINESONSCREEN]);
	long top = MAX(0, displayLine - MAX(1, page / 3));
	[editor message:SCI_SETFIRSTVISIBLELINE wParam:(uptr_t)top lParam:0];
	NSScrollView *scroll = editor.scrollView;
	NSClipView *clip = scroll.contentView;
	if (!clip) {
		return;
	}
	CGFloat lineHeight = MAX(1.0, (CGFloat)[editor message:SCI_TEXTHEIGHT wParam:(uptr_t)MAX(0, line) lParam:0]);
	const char *sample = "0";
	CGFloat charWidth = MAX(1.0, (CGFloat)[editor message:SCI_TEXTWIDTH wParam:STYLE_DEFAULT lParam:(sptr_t)sample]);
	long caretColumn = [editor message:SCI_GETCOLUMN wParam:(uptr_t)pos lParam:0];
	CGFloat x = MAX(0, caretColumn * charWidth - 80);
	CGFloat y = MAX(0, top * lineHeight);
	[clip scrollToPoint:NSMakePoint(x, y)];
	[scroll reflectScrolledClipView:clip];
	[editor setNeedsDisplay:YES];
}

- (void)minimapZoomExited:(NppMinimapZoom *)sender {
	(void)sender;
	[self scheduleZoomHide];
}

- (void)minimapZoomJump:(NppMinimapZoom *)sender {
	long line = sender.clickedLine;
	long column = sender.clickedColumn;
	sender.clickedLine = -1;
	NSInteger pane = sender.pane;
	id shown = (pane >= 0 && pane < (NSInteger)_paneDocuments.count) ? _paneDocuments[pane] : nil;
	DocumentTab *document = [shown isKindOfClass:[DocumentTab class]] ? shown : [self currentDocument];
	ScintillaView *editor = [self visibleEditorInPane:pane document:document];
	[self placeCaretInEditor:editor line:line column:column];
}

- (void)minimapJump:(NppMinimapView *)sender {
	NSInteger pane = sender.pane;
	id shown = (pane >= 0 && pane < (NSInteger)_paneDocuments.count) ? _paneDocuments[pane] : nil;
	DocumentTab *document = [shown isKindOfClass:[DocumentTab class]] ? shown : [self currentDocument];
	if (!document) {
		return;
	}
	ScintillaView *editor = [self visibleEditorInPane:pane document:document];
	long lines = MAX(1, [editor message:SCI_GETLINECOUNT]);
	long line = MIN(lines - 1, MAX(0, (long)(sender.clickedFraction * lines)));
	[self placeCaretInEditor:editor line:line column:0];
	[self hideMinimapZoomInSlot:sender.superview];
}

- (void)toggleMinimap:(id)sender {
	(void)sender;
	_settings.showMinimap = !_settings.showMinimap;
	NSError *error = nil;
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self hideZoomPanel];
	for (NSInteger pane = 0; pane < [_splitHost paneCount]; pane++) {
		NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
		for (NSView *view in slot.subviews) {
			if ([view.identifier isEqualToString:@"npp.minimap"]) {
				view.hidden = !_settings.showMinimap;
			}
			if ([view.identifier isEqualToString:@"npp.minimapZoom"]) {
				view.hidden = YES;
			}
		}
		[slot layoutContents];
	}
	[self buildMenus];
	[self refreshLivePanels];
}

- (void)attachPreviewToSlot:(NppPaneSlot *)slot {
	if (!_preview) {
		_preview = [[WKWebView alloc] initWithFrame:NSZeroRect];
		_preview.identifier = @"npp.preview";
		_preview.allowsMagnification = YES;
	}
	_preview.hidden = !_previewVisible;
	if (_preview.superview != slot) {
		[_preview removeFromSuperview];
		[slot addSubview:_preview];
	}
}

- (void)reloadPreview {
	if (!_previewVisible) {
		return;
	}
	DocumentTab *document = [self currentDocument];
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:_activePane];
	if ([slot isKindOfClass:[NppPaneSlot class]]) {
		[self attachPreviewToSlot:slot];
		[slot layoutContents];
	}
	NSString *html = NppPreviewHTML([document utf8Text] ?: @"", document.language, document.lexerName, [self darkAppearance]);
	[_preview loadHTMLString:html baseURL:nil];
}

- (void)togglePreview:(id)sender {
	(void)sender;
	_previewVisible = !_previewVisible;
	if (!_previewVisible && _preview.superview) {
		_preview.hidden = YES;
		[_preview.superview setNeedsLayout:YES];
		if ([_preview.superview isKindOfClass:[NppPaneSlot class]]) {
			[(NppPaneSlot *)_preview.superview layoutContents];
		}
	}
	[self buildMenus];
	[self reloadPreview];
}

- (void)refreshLivePanels {
	if (_sidebarPage == 1 && _workspace.sidebarVisible) {
		[self reloadOutline];
	}
	for (NSInteger pane = 0; pane < (NSInteger)_paneDocuments.count; pane++) {
		id shown = _paneDocuments[pane];
		if ([shown isKindOfClass:[DocumentTab class]]) {
			[self refreshMinimapForDocument:shown inPane:pane];
		}
	}
	if (_previewVisible) {
		[self reloadPreview];
	}
}

- (void)showClipboardHistory:(id)sender {
	(void)sender;
	if (!_clipboardWindow) {
		_clipboardWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 420, 320) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
		_clipboardWindow.title = @"Clipboard History";
		_clipboardWindow.releasedWhenClosed = NO;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 420, 320)];
		scroll.hasVerticalScroller = YES;
		scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_clipboardTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"text"];
		column.title = @"Copied text";
		column.width = 380;
		[_clipboardTable addTableColumn:column];
		_clipboardTable.dataSource = self;
		_clipboardTable.delegate = self;
		_clipboardTable.target = self;
		_clipboardTable.doubleAction = @selector(pasteClipboardRow:);
		scroll.documentView = _clipboardTable;
		[_clipboardWindow.contentView addSubview:scroll];
	}
	[_clipboardTable reloadData];
	[_clipboardWindow center];
	[_clipboardWindow makeKeyAndOrderFront:nil];
}

- (void)pasteClipboardRow:(id)sender {
	(void)sender;
	NSInteger row = _clipboardTable.clickedRow >= 0 ? _clipboardTable.clickedRow : _clipboardTable.selectedRow;
	if (row < 0 || row >= (NSInteger)_clips.items.count) {
		return;
	}
	const char *bytes = _clips.items[row].UTF8String ?: "";
	[[self activeEditor] message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
	[_clipboardWindow close];
	[_window makeFirstResponder:[self activeEditor]];
}

- (void)showSnippets:(id)sender {
	(void)sender;
	if (!_snippetWindow) {
		_snippetWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 520, 360) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
		_snippetWindow.title = @"Snippets";
		_snippetWindow.releasedWhenClosed = NO;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 52, 496, 280)];
		scroll.hasVerticalScroller = YES;
		scroll.borderType = NSBezelBorder;
		_snippetTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
		for (NSArray *info in @[@[@"name", @"Name", @140], @[@"body", @"Text", @320]]) {
			NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:info[0]];
			column.title = info[1];
			column.width = [info[2] doubleValue];
			column.editable = YES;
			[_snippetTable addTableColumn:column];
		}
		_snippetTable.dataSource = self;
		_snippetTable.delegate = self;
		scroll.documentView = _snippetTable;
		NSButton *add = [self button:@"Add" action:@selector(addSnippet:) frame:NSMakeRect(12, 14, 80, 28)];
		NSButton *remove = [self button:@"Remove" action:@selector(removeSnippet:) frame:NSMakeRect(100, 14, 90, 28)];
		NSButton *save = [self button:@"Save" action:@selector(saveSnippets:) frame:NSMakeRect(420, 14, 88, 28)];
		[_snippetWindow.contentView addSubview:scroll];
		for (NSView *view in @[add, remove, save]) {
			[_snippetWindow.contentView addSubview:view];
		}
	}
	[_snippetTable reloadData];
	[_snippetWindow center];
	[_snippetWindow makeKeyAndOrderFront:nil];
}

- (void)addSnippet:(id)sender {
	(void)sender;
	[_snippets.snippets addObject:[@{@"name": @"snippet", @"body": @""} mutableCopy]];
	[_snippetTable reloadData];
}

- (void)removeSnippet:(id)sender {
	(void)sender;
	NSInteger row = _snippetTable.selectedRow;
	if (row >= 0 && row < (NSInteger)_snippets.snippets.count) {
		[_snippets.snippets removeObjectAtIndex:row];
		[_snippetTable reloadData];
	}
}

- (void)saveSnippets:(id)sender {
	(void)sender;
	NSError *error = nil;
	[_snippets saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"snippets.json"] error:&error];
	[self setStatusText:@"Snippets saved. Press Tab after a snippet name to insert it."];
	[_snippetWindow close];
}

- (void)chooseUserLanguage:(NSMenuItem *)sender {
	DocumentTab *document = [self currentDocument];
	LangInfo *info = [_userLanguages langInfoNamed:sender.representedObject];
	if (!document || !info) {
		return;
	}
	document.manualLanguage = YES;
	[document applyLanguage:info dark:[self darkAppearance]];
}

- (void)showUserLanguages:(id)sender {
	(void)sender;
	if (!_languageWindow) {
		_languageWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 640, 360) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
		_languageWindow.title = @"User Languages";
		_languageWindow.releasedWhenClosed = NO;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(12, 52, 616, 280)];
		scroll.hasVerticalScroller = YES;
		scroll.borderType = NSBezelBorder;
		_languageTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
		for (NSArray *info in @[@[@"name", @"Name", @120], @[@"extensions", @"Extensions", @140], @[@"keywords", @"Keywords", @240], @[@"lexer", @"Lexer", @80]]) {
			NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:info[0]];
			column.title = info[1];
			column.width = [info[2] doubleValue];
			column.editable = YES;
			[_languageTable addTableColumn:column];
		}
		_languageTable.dataSource = self;
		_languageTable.delegate = self;
		scroll.documentView = _languageTable;
		NSButton *add = [self button:@"Add" action:@selector(addUserLanguage:) frame:NSMakeRect(12, 14, 80, 28)];
		NSButton *remove = [self button:@"Remove" action:@selector(removeUserLanguage:) frame:NSMakeRect(100, 14, 90, 28)];
		NSButton *save = [self button:@"Save" action:@selector(saveUserLanguages:) frame:NSMakeRect(528, 14, 100, 28)];
		[_languageWindow.contentView addSubview:scroll];
		for (NSView *view in @[add, remove, save]) {
			[_languageWindow.contentView addSubview:view];
		}
	}
	[_languageTable reloadData];
	[_languageWindow center];
	[_languageWindow makeKeyAndOrderFront:nil];
}

- (void)addUserLanguage:(id)sender {
	(void)sender;
	NppUserLanguage *language = [NppUserLanguage new];
	language.name = @"My Language";
	language.extensions = @"mylang";
	language.keywords = @"";
	language.lexer = @"cpp";
	[_userLanguages.languages addObject:language];
	[_languageTable reloadData];
}

- (void)removeUserLanguage:(id)sender {
	(void)sender;
	NSInteger row = _languageTable.selectedRow;
	if (row >= 0 && row < (NSInteger)_userLanguages.languages.count) {
		[_userLanguages.languages removeObjectAtIndex:row];
		[_languageTable reloadData];
	}
}

- (void)saveUserLanguages:(id)sender {
	(void)sender;
	NSError *error = nil;
	[_userLanguages saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"languages.json"] error:&error];
	[self buildMenus];
	[self setStatusText:@"User languages saved. Matching extensions use them when a file opens."];
	[_languageWindow close];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)column row:(NSInteger)row {
	NSString *value = [object isKindOfClass:[NSString class]] ? object : @"";
	if (tableView == _shortcutTable && row >= 0 && row < (NSInteger)_shortcutRows.count && [column.identifier isEqualToString:@"keys"]) {
		_shortcutRows[row][@"keys"] = value;
	} else if (tableView == _snippetTable && row >= 0 && row < (NSInteger)_snippets.snippets.count) {
		_snippets.snippets[row][column.identifier] = value;
	} else if (tableView == _languageTable && row >= 0 && row < (NSInteger)_userLanguages.languages.count) {
		NppUserLanguage *language = _userLanguages.languages[row];
		if ([column.identifier isEqualToString:@"extensions"]) language.extensions = value;
		else if ([column.identifier isEqualToString:@"keywords"]) language.keywords = value;
		else if ([column.identifier isEqualToString:@"lexer"]) language.lexer = value;
		else language.name = value.length ? value : language.name;
	}
}

@end
