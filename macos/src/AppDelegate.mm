#import "AppDelegate.h"

#import "DocumentTab.h"
#import "EditorActions.h"
#import "EditorSettings.h"
#import "Encoding.h"
#import "LangCatalog.h"
#import "MacroStore.h"
#import "NppMacPlugin.h"
#import "Search.h"

#include <dlfcn.h>

@interface AppDelegate (ContextMenus)
- (void)selectTabForContext:(NSInteger)index;
- (NSMenu *)tabContextMenu;
@end

static NSString *const NppTabDragType = @"npp.document.tab";

@interface AppDelegate (TabDrag)
- (void)noteTabDragStarted:(DocumentTab *)document;
- (void)noteTabDragEnded;
- (DocumentTab *)draggedTabDocument;
- (void)moveDocument:(DocumentTab *)document toPane:(NSInteger)pane atIndex:(NSInteger)index;
- (void)showDocument:(DocumentTab *)document inPane:(NSInteger)pane;
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
	(void)screenPoint;
	(void)operation;
	[self.owner noteTabDragEnded];
}
@end

@interface NppTabCloseButton : NSButton
@property (nonatomic, weak) DocumentTab *document;
@end

@implementation NppTabCloseButton
@end

@interface NppTabChip : NSView
@property (nonatomic, weak) DocumentTab *document;
@end

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
	CGFloat toolbarHeight = 42;
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
		CGFloat barWidth = self.compareBar.bounds.size.width;
		for (NSView *view in self.compareBar.subviews) {
			if (view.tag == 41) {
				view.frame = NSMakeRect(12, 6, MAX(160, barWidth - 300), 20);
			} else if (view.tag == 42) {
				view.frame = NSMakeRect(barWidth - 252, 4, 84, 24);
			} else if (view.tag == 43) {
				view.frame = NSMakeRect(barWidth - 162, 4, 64, 24);
			} else if (view.tag == 44) {
				view.frame = NSMakeRect(barWidth - 92, 4, 80, 24);
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
		CGFloat sideHeight = self.sidebar.bounds.size.height;
		CGFloat sideWidth = self.sidebar.bounds.size.width;
		for (NSView *view in self.sidebar.subviews) {
			if (view.tag == 1) {
				view.frame = NSMakeRect(10, sideHeight - 24, MAX(40, sideWidth - 128), 18);
			} else if (view.tag == 3) {
				view.frame = NSMakeRect(sideWidth - 112, sideHeight - 26, 36, 22);
			} else if (view.tag == 4) {
				view.frame = NSMakeRect(sideWidth - 72, sideHeight - 26, 62, 22);
			} else if (view.tag == 2) {
				view.frame = NSMakeRect(8, sideHeight - 54, MAX(40, sideWidth - 16), 24);
			} else if ([view isKindOfClass:[NSScrollView class]]) {
				view.frame = NSMakeRect(0, 0, sideWidth, MAX(0, sideHeight - 62));
			}
		}
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

@interface NppPaneSlot : NSView
@property (nonatomic, assign) NSInteger paneIndex;
@property (nonatomic, copy) NSString *title;
@property (nonatomic, assign) BOOL activePane;
@property (nonatomic, strong) NppPaneTabBar *tabBar;
- (NSRect)editorRect;
- (void)layoutContents;
- (void)removeEditorViews;
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
- (NSDragOperation)draggingEntered:(id<NSDraggingInfo>)sender {
	return [self draggingUpdated:sender];
}
- (NSDragOperation)draggingUpdated:(id<NSDraggingInfo>)sender {
	if (![self.owner draggedTabDocument]) {
		return NSDragOperationNone;
	}
	NSPoint point = [self convertPoint:sender.draggingLocation fromView:nil];
	self.dropIndex = [self insertionIndexAtPoint:point];
	[self setNeedsDisplay:YES];
	return NSDragOperationMove;
}
- (void)draggingExited:(id<NSDraggingInfo>)sender {
	(void)sender;
	self.dropIndex = -1;
	[self setNeedsDisplay:YES];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	return [self.owner draggedTabDocument] != nil;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	DocumentTab *document = [self.owner draggedTabDocument];
	NSInteger index = self.dropIndex < 0 ? [self insertionIndexAtPoint:[self convertPoint:sender.draggingLocation fromView:nil]] : self.dropIndex;
	self.dropIndex = -1;
	[self setNeedsDisplay:YES];
	if (!document) {
		return NO;
	}
	[self.owner moveDocument:document toPane:self.paneIndex atIndex:index];
	return YES;
}
@end

@implementation NppPaneSlot
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
	for (NSView *subview in self.subviews) {
		if (subview == self.tabBar) {
			continue;
		}
		subview.frame = editorRect;
	}
}
- (void)removeEditorViews {
	for (NSView *subview in self.subviews.copy) {
		if (subview == self.tabBar) {
			continue;
		}
		[subview removeFromSuperview];
	}
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
	if (![self.tabBar.owner draggedTabDocument]) {
		return NSDragOperationNone;
	}
	self.tabBar.dropIndex = (NSInteger)self.tabBar.subviews.count;
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
	[self.tabBar setNeedsDisplay:YES];
}
- (BOOL)prepareForDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	return [self.tabBar.owner draggedTabDocument] != nil;
}
- (BOOL)performDragOperation:(id<NSDraggingInfo>)sender {
	(void)sender;
	DocumentTab *document = [self.tabBar.owner draggedTabDocument];
	NSInteger index = self.tabBar.dropIndex < 0 ? 0 : self.tabBar.dropIndex;
	self.tabBar.dropIndex = -1;
	if (!document) {
		return NO;
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
@property (nonatomic, strong) NSMutableArray<NppFolderNode *> *children;
@property (nonatomic, assign) BOOL loaded;
@end

@implementation NppFolderNode
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
	NSTextField *_status;
	NSButton *_tailButton;
	NSView *_sidebar;
	NSOutlineView *_folderOutline;
	NSString *_folderRoot;
	NppFolderNode *_folderRootNode;
	NSTextView *_preferencesShortcuts;
	NSWindow *_preferencesWindow;
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
	_plugins = [NSMutableArray array];
	_pluginErrors = [NSMutableArray array];
	_macro = [MacroStore new];
	_settings = [EditorSettings loadFromURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"]];
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
	NppRunEditorAction(document.editor, action, document.lexerName ?: @"");
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
	_window.title = @"Notepad++";
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
	_findField.tag = 1;
	_replaceField = [[NSTextField alloc] initWithFrame:NSZeroRect];
	_replaceField.placeholderString = @"Replace";
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
	for (NSButton *button in @[next, previous, replace, replaceAll, inFiles]) {
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
	_compareLabel = [NSTextField labelWithString:@"Compare"];
	_compareLabel.tag = 41;
	_compareLabel.font = [NSFont systemFontOfSize:13 weight:NSFontWeightMedium];
	_compareLabel.lineBreakMode = NSLineBreakByTruncatingTail;
	NSButton *comparePrevious = [self button:@"Previous" action:@selector(comparePrevious:) frame:NSZeroRect];
	comparePrevious.tag = 42;
	NSButton *compareNext = [self button:@"Next" action:@selector(compareNext:) frame:NSZeroRect];
	compareNext.tag = 43;
	NSButton *compareClose = [self button:@"Close" action:@selector(closeCompare:) frame:NSZeroRect];
	compareClose.tag = 44;
	for (NSView *view in @[_compareLabel, comparePrevious, compareNext, compareClose]) {
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
	NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
	button.frame = frame;
	return button;
}

- (NSButton *)toolButton:(NSString *)symbol tip:(NSString *)tip action:(SEL)action {
	NSImage *image = [NSImage imageWithSystemSymbolName:symbol accessibilityDescription:tip];
	image.size = NSMakeSize(16, 16);
	NSButton *button = [NSButton buttonWithImage:image target:self action:action];
	button.toolTip = tip;
	button.bezelStyle = NSBezelStyleTexturedRounded;
	button.imageScaling = NSImageScaleProportionallyDown;
	button.bordered = YES;
	return button;
}

- (NSView *)buildToolbar {
	NSView *bar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 42)];
	NSArray *items = @[
		@[@"doc.badge.plus", @"New", NSStringFromSelector(@selector(newDocument:))],
		@[@"folder", @"Open", NSStringFromSelector(@selector(openDocument:))],
		@[@"square.and.arrow.down", @"Save", NSStringFromSelector(@selector(saveDocument:))],
		@[@"square.and.arrow.down.on.square", @"Save All", NSStringFromSelector(@selector(saveAllDocuments:))],
		@[@"xmark", @"Close", NSStringFromSelector(@selector(closeDocument:))],
		@[@"|"],
		@[@"arrow.uturn.backward", @"Undo", NSStringFromSelector(@selector(undo:))],
		@[@"arrow.uturn.forward", @"Redo", NSStringFromSelector(@selector(redo:))],
		@[@"|"],
		@[@"scissors", @"Cut", NSStringFromSelector(@selector(cut:))],
		@[@"doc.on.doc", @"Copy", NSStringFromSelector(@selector(copy:))],
		@[@"doc.on.clipboard", @"Paste", NSStringFromSelector(@selector(paste:))],
		@[@"|"],
		@[@"magnifyingglass", @"Find", NSStringFromSelector(@selector(showFind:))],
		@[@"doc.text.magnifyingglass", @"Find in Files", NSStringFromSelector(@selector(showFindInFiles:))],
		@[@"arrow.left.arrow.right", @"Replace", NSStringFromSelector(@selector(showReplace:))],
		@[@"tail", @"Tail", NSStringFromSelector(@selector(toggleMonitoring:))],
		@[@"rectangle.split.2x1", @"Split", NSStringFromSelector(@selector(splitRight:))],
		@[@"|"],
		@[@"record.circle", @"Record Macro", NSStringFromSelector(@selector(startMacro:))],
		@[@"stop.circle", @"Stop Macro", NSStringFromSelector(@selector(stopMacro:))],
		@[@"play.circle", @"Play Macro", NSStringFromSelector(@selector(playMacro:))]
	];
	CGFloat x = 8;
	for (NSArray *item in items) {
		if ([item[0] isEqualToString:@"|"]) {
			NSBox *rule = [[NSBox alloc] initWithFrame:NSMakeRect(x + 4, 8, 1, 26)];
			rule.boxType = NSBoxSeparator;
			[bar addSubview:rule];
			x += 14;
			continue;
		}
		if ([item[0] isEqualToString:@"tail"]) {
			NSImage *image = [NSImage imageWithSystemSymbolName:@"text.append" accessibilityDescription:@"Tail"];
			image.size = NSMakeSize(14, 14);
			NSButton *button = [NSButton buttonWithTitle:@"Tail" image:image target:self action:@selector(toggleMonitoring:)];
			button.imagePosition = NSImageLeading;
			button.imageScaling = NSImageScaleProportionallyDown;
			button.bezelStyle = NSBezelStyleTexturedRounded;
			button.font = [NSFont systemFontOfSize:12];
			button.buttonType = NSButtonTypeToggle;
			button.toolTip = @"Start tail -f";
			button.frame = NSMakeRect(x, 6, 78, 30);
			_tailButton = button;
			[bar addSubview:button];
			x += 84;
			continue;
		}
		if ([item[0] isEqualToString:@"rectangle.split.2x1"]) {
			NSImage *image = [NSImage imageWithSystemSymbolName:@"rectangle.split.2x1" accessibilityDescription:@"Split"];
			image.size = NSMakeSize(14, 14);
			NSButton *button = [NSButton buttonWithTitle:@"Split" image:image target:self action:@selector(splitRight:)];
			button.imagePosition = NSImageLeading;
			button.imageScaling = NSImageScaleProportionallyDown;
			button.bezelStyle = NSBezelStyleTexturedRounded;
			button.font = [NSFont systemFontOfSize:12];
			button.toolTip = @"Split the tabs to the right into a new pane";
			button.frame = NSMakeRect(x, 6, 78, 30);
			[bar addSubview:button];
			x += 84;
			continue;
		}
		NSButton *button = [self toolButton:item[0] tip:item[1] action:NSSelectorFromString(item[2])];
		button.frame = NSMakeRect(x, 6, 32, 30);
		[bar addSubview:button];
		x += 36;
	}
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
			NSAttributedString *title = [[NSAttributedString alloc] initWithString:[@"  " stringByAppendingString:name] attributes:@{
				NSFontAttributeName: font,
				NSForegroundColorAttributeName: textColor
			}];
			NppTabButton *button = [[NppTabButton alloc] initWithFrame:NSZeroRect];
			button.buttonType = NSButtonTypeMomentaryPushIn;
			button.attributedTitle = title;
			button.alignment = NSTextAlignmentLeft;
			button.target = self;
			button.owner = self;
			button.document = document;
			button.action = @selector(selectTabButton:);
			button.bordered = NO;
			[button sizeToFit];
			CGFloat width = MAX(110, MIN(220, button.frame.size.width + 30));
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
			button.frame = NSMakeRect(0, 0, width, 24);
			NppTabCloseButton *close = [[NppTabCloseButton alloc] initWithFrame:NSMakeRect(width - 22, 2, 18, 20)];
			close.bordered = NO;
			close.title = @"×";
			close.contentTintColor = textColor;
			close.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
			close.target = self;
			close.action = @selector(closeTabButton:);
			close.document = document;
			close.toolTip = @"Close";
			[chip addSubview:button];
			[chip addSubview:close];
			[bar addSubview:chip];
			x += width + 4;
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
	if (document) {
		[self showDocument:document inPane:[self paneIndexOfDocument:document]];
		return;
	}
	[self rebuildTabStrip];
}

- (void)closeTabButton:(NSButton *)sender {
	DocumentTab *document = [sender isKindOfClass:[NppTabCloseButton class]] ? ((NppTabCloseButton *)sender).document : nil;
	if (!document) {
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
	_resultsScroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
	_resultsScroll.hasVerticalScroller = YES;
	_resultsTable = [[NSTableView alloc] initWithFrame:NSZeroRect];
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
		if ([columnInfo[0] isEqualToString:@"text"]) {
			column.resizingMask = NSTableColumnAutoresizingMask;
		}
		[_resultsTable addTableColumn:column];
	}
	_resultsTable.dataSource = self;
	_resultsTable.delegate = self;
	_resultsTable.target = self;
	_resultsTable.doubleAction = @selector(openSearchHit:);
	_resultsScroll.documentView = _resultsTable;
	for (NSView *view in @[findLabel, _filesQuery, replaceLabel, _filesReplace, filterLabel, _filesFilters, dirLabel, _filesDirectory, browse, findAll, replaceFiles, close, _filesCase, _filesWord, _filesRegex, _filesSubfolders, _resultsScroll]) {
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
	CGFloat field = MAX(140, MIN(360, width - 560));
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
	CGFloat form = 112;
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
		if (title.length == 0 || !top.submenu) {
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

- (NSMenuItem *)item:(NSString *)title action:(SEL)action command:(NSString *)command {
	NSString *spec = command ? [_settings shortcutForCommand:command] : @"";
	NSString *key = @"";
	NSEventModifierFlags flags = 0;
	[EditorSettings parseShortcut:spec key:&key modifiers:&flags];
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:action keyEquivalent:key];
	item.keyEquivalentModifierMask = flags;
	item.target = self;
	item.representedObject = command;
	return item;
}

- (NSMenuItem *)actionItem:(NSString *)title action:(NSString *)action command:(NSString *)command {
	NSString *key = @"";
	NSEventModifierFlags flags = 0;
	if (command.length) {
		[EditorSettings parseShortcut:[_settings shortcutForCommand:command] key:&key modifiers:&flags];
	}
	NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:title action:@selector(editorAction:) keyEquivalent:key];
	item.keyEquivalentModifierMask = flags;
	item.target = self;
	item.representedObject = action;
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
	NppRunEditorAction(document.editor, sender.representedObject, document.lexerName ?: @"");
	[self refreshStatus];
}

- (void)buildMenus {
	NSMenu *bar = [NSMenu new];
	NSMenu *appMenu = [NSMenu new];
	[appMenu addItem:[self item:@"About Notepad++" action:@selector(showAbout:) command:nil]];
	[appMenu addItem:[NSMenuItem separatorItem]];
	[appMenu addItem:[self item:@"Preferences…" action:@selector(showPreferences:) command:@"preferences"]];
	[appMenu addItem:[NSMenuItem separatorItem]];
	NSMenuItem *quit = [[NSMenuItem alloc] initWithTitle:@"Quit Notepad++" action:@selector(terminate:) keyEquivalent:@"q"];
	quit.keyEquivalentModifierMask = NSEventModifierFlagCommand;
	[appMenu addItem:quit];
	NSMenuItem *appItem = [NSMenuItem new];
	appItem.submenu = appMenu;
	[bar addItem:appItem];

	NSMenu *file = [NSMenu new];
	file.title = @"File";
	[file addItem:[self item:@"New" action:@selector(newDocument:) command:@"new"]];
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
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No recent files" action:nil keyEquivalent:@""];
		none.enabled = NO;
		[recent addItem:none];
	}
	for (NSString *path in paths) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:path.lastPathComponent action:@selector(openRecent:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = path;
		item.toolTip = path;
		[recent addItem:item];
	}
	NSMenuItem *recentItem = [[NSMenuItem alloc] initWithTitle:@"Open Recent" action:nil keyEquivalent:@""];
	recentItem.submenu = recent;
	[file addItem:recentItem];
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
	[edit addItem:lineItem];
	NSMenu *indent = [NSMenu new];
	[indent addItem:[self actionItem:@"Increase Line Indent" action:@"indent"]];
	[indent addItem:[self actionItem:@"Decrease Line Indent" action:@"outdent"]];
	NSMenuItem *indentItem = [[NSMenuItem alloc] initWithTitle:@"Indent" action:nil keyEquivalent:@""];
	indentItem.submenu = indent;
	[edit addItem:indentItem];
	NSMenu *convert = [NSMenu new];
	[convert addItem:[self actionItem:@"UPPERCASE" action:@"upper" command:@"upper"]];
	[convert addItem:[self actionItem:@"lowercase" action:@"lower" command:@"lower"]];
	[convert addItem:[self actionItem:@"iNVERT cASE" action:@"invert"]];
	NSMenuItem *convertItem = [[NSMenuItem alloc] initWithTitle:@"Convert Case to" action:nil keyEquivalent:@""];
	convertItem.submenu = convert;
	[edit addItem:convertItem];
	[edit addItem:[self actionItem:@"Toggle Line Comment" action:@"comment" command:@"comment"]];
	[edit addItem:[self actionItem:@"Trim Trailing Space" action:@"trim"]];
	[edit addItem:[self actionItem:@"TAB to Space" action:@"tabsToSpaces"]];
	[edit addItem:[NSMenuItem separatorItem]];
	[edit addItem:[self actionItem:@"Insert Date Time" action:@"datetime"]];
	[edit addItem:[self item:@"Copy Full File Path" action:@selector(copyFullPath:) command:nil]];
	[edit addItem:[self item:@"Copy Filename" action:@selector(copyFilename:) command:nil]];
	[edit addItem:[NSMenuItem separatorItem]];
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
	[search addItem:bookmarkItem];
	[self addMenu:search title:@"Search" to:bar];

	NSMenu *view = [NSMenu new];
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
	[self addMenu:view title:@"View" to:bar];

	NSMenu *encoding = [NSMenu new];
	NSMenu *characterSets = [NSMenu new];
	NSMutableDictionary<NSString *, NSMenu *> *groups = [NSMutableDictionary dictionary];
	for (int index = 0; index < NppEncodingCount(); index++) {
		const NppEncodingInfo *info = NppEncodingAt(index);
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@(info->name) action:@selector(chooseEncoding:) keyEquivalent:@""];
		item.target = self;
		item.tag = info->id;
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
			[characterSets addItem:parent];
		}
		[group addItem:item];
	}
	NSMenuItem *sets = [[NSMenuItem alloc] initWithTitle:@"Character sets" action:nil keyEquivalent:@""];
	sets.submenu = characterSets;
	[encoding addItem:sets];
	[self addMenu:encoding title:@"Encoding" to:bar];

	NSMenu *eol = [NSMenu new];
	NSArray *eols = @[@"Windows (CRLF)", @"Classic Mac (CR)", @"Unix (LF)"];
	for (NSInteger index = 0; index < 3; index++) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:eols[index] action:@selector(chooseEOL:) keyEquivalent:@""];
		item.target = self;
		item.tag = index;
		[eol addItem:item];
	}
	[self addMenu:eol title:@"Line Endings" to:bar];

	NSMenu *language = [NSMenu new];
	NSMenuItem *automatic = [[NSMenuItem alloc] initWithTitle:@"Automatic" action:@selector(chooseAutomaticLanguage:) keyEquivalent:@""];
	automatic.target = self;
	[language addItem:automatic];
	[language addItem:[NSMenuItem separatorItem]];
	for (LangInfo *info in _catalog.allLanguages) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:info.name action:@selector(chooseLanguage:) keyEquivalent:@""];
		item.target = self;
		item.representedObject = info.name;
		[language addItem:item];
	}
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
			[macro addItem:item];
		}
	}
	[self addMenu:macro title:@"Macro" to:bar];

	NSMenu *plugins = [NSMenu new];
	if (_plugins.count == 0 && _pluginErrors.count == 0) {
		NSMenuItem *none = [[NSMenuItem alloc] initWithTitle:@"No plugins loaded" action:nil keyEquivalent:@""];
		none.enabled = NO;
		[plugins addItem:none];
	}
	for (NSString *error in _pluginErrors) {
		NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:error action:nil keyEquivalent:@""];
		item.enabled = NO;
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
			[submenu addItem:item];
		}
		if (submenu.numberOfItems == 0) {
			NSMenuItem *empty = [[NSMenuItem alloc] initWithTitle:@"No commands" action:nil keyEquivalent:@""];
			empty.enabled = NO;
			[submenu addItem:empty];
		}
		NSMenuItem *pluginItem = [[NSMenuItem alloc] initWithTitle:plugin[@"name"] ?: @"Plugin" action:nil keyEquivalent:@""];
		pluginItem.submenu = submenu;
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
	menu.title = title;
	NSMenuItem *item = [NSMenuItem new];
	item.submenu = menu;
	item.title = title;
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
	if ([_settings.theme isEqualToString:@"dark"]) {
		_window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
	} else if ([_settings.theme isEqualToString:@"light"]) {
		_window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
	} else {
		_window.appearance = nil;
	}
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

- (void)placeEditor:(DocumentTab *)document inPane:(NSInteger)pane {
	NppPaneSlot *slot = (NppPaneSlot *)[_splitHost slotAtIndex:pane];
	if (![slot isKindOfClass:[NppPaneSlot class]] || !document) {
		return;
	}
	[document.editor removeFromSuperview];
	[slot removeEditorViews];
	document.editor.scrollView.focusRingType = NSFocusRingTypeNone;
	document.editor.autoresizingMask = NSViewNotSizable;
	document.editor.frame = slot.editorRect;
	[slot addSubview:document.editor];
	[slot layoutContents];
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
	[_window makeFirstResponder:document.editor];
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

- (void)moveDocument:(DocumentTab *)document toPane:(NSInteger)pane atIndex:(NSInteger)index {
	if (![document isKindOfClass:[DocumentTab class]] || pane < 0 || pane >= (NSInteger)_paneDocuments.count) {
		return;
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
		[_window makeFirstResponder:((DocumentTab *)document).editor];
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

- (BOOL)openPath:(NSString *)path {
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
	LangInfo *info = [_catalog languageForPath:path sample:text];
	[document applyLanguage:info dark:[self darkAppearance]];
	[document markClean];
	[self rememberPath:path];
	[self noteDiskRevisionForDocument:document];
	BOOL writable = [[NSFileManager defaultManager] isWritableFileAtPath:path];
	[document.editor setEditable:writable];
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
		[self newDocument:nil];
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
	NSArray<DocumentTab *> *documents = [_documents copy];
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
		if (document != keep) {
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
	alert.messageText = message;
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
	NSArray<NppFindHit *> *hits = NppFindInFiles(directory, query, _filesFilters.stringValue, _filesSubfolders.state == NSControlStateValueOn, [self fileSearchFlags], 1000);
	[_hits removeAllObjects];
	[_hits addObjectsFromArray:hits];
	[_resultsTable reloadData];
	[self sizeResultColumns];
	[self setStatusText:[NSString stringWithFormat:@"Find in Files: %lu hit(s) in %@.", (unsigned long)hits.count, directory]];
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
	if (tableView == _folderOutline) {
		return 0;
	}
	return (NSInteger)_hits.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
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
	NSDictionary *attributes = @{NSFontAttributeName: [NSFont systemFontOfSize:[NSFont systemFontSize]]};
	CGFloat width = 160;
	for (NppFindHit *hit in _hits) {
		width = MAX(width, ceil([hit.path sizeWithAttributes:attributes].width) + 28);
	}
	pathColumn.width = width;
}

- (void)reloadFromDisk:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document.path.length) {
		[self alert:@"This document has not been saved."];
		return;
	}
	[document reloadFromDiskScrollingToEnd:NO];
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
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Save" action:@selector(saveDocument:) command:@"save"]];
	[menu addItem:[self item:@"Reload from Disk" action:@selector(reloadFromDisk:) command:nil]];
	NSMenuItem *tail = [self item:document.fileMonitoring ? @"Stop tail -f" : @"Start tail -f" action:@selector(toggleMonitoring:) command:nil];
	tail.state = document.fileMonitoring ? NSControlStateValueOn : NSControlStateValueOff;
	[menu addItem:tail];
	[menu addItem:[NSMenuItem separatorItem]];
	[menu addItem:[self item:@"Copy Full File Path" action:@selector(copyFullPath:) command:nil]];
	[menu addItem:[self item:@"Copy Filename" action:@selector(copyFilename:) command:nil]];
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
	[[self currentDocument].editor message:SCI_CLEAR];
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
	long found = NppFind([self currentDocument].editor, _findField.stringValue, true, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self setStatusText:found < 0 ? @"No match." : @"Match found."];
}

- (void)findPrevious:(id)sender {
	(void)sender;
	long found = NppFind([self currentDocument].editor, _findField.stringValue, false, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self setStatusText:found < 0 ? @"No match." : @"Match found."];
}

- (void)replaceNext:(id)sender {
	(void)sender;
	long found = NppReplace([self currentDocument].editor, _findField.stringValue, _replaceField.stringValue, _wrap.state == NSControlStateValueOn, [self searchFlags]);
	[self setStatusText:found < 0 ? @"No match." : @"Replaced."];
}

- (void)replaceAll:(id)sender {
	(void)sender;
	long count = NppReplaceAll([self currentDocument].editor, _findField.stringValue, _replaceField.stringValue, [self searchFlags]);
	[self setStatusText:[NSString stringWithFormat:@"Replaced %ld.", count]];
}

- (void)undo:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_UNDO]; }
- (void)redo:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_REDO]; }
- (void)cut:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_CUT]; }
- (void)copy:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_COPY]; }
- (void)paste:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_PASTE]; }
- (void)selectAll:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_SELECTALL]; }
- (void)zoomIn:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_ZOOMIN]; }
- (void)zoomOut:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_ZOOMOUT]; }
- (void)foldAll:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_FOLDALL wParam:SC_FOLDACTION_CONTRACT lParam:0]; }
- (void)unfoldAll:(id)sender { (void)sender; [[self currentDocument].editor message:SCI_FOLDALL wParam:SC_FOLDACTION_EXPAND lParam:0]; }

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
	LangInfo *info = [_catalog languageForPath:document.path sample:[document utf8Text]];
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
	long start = [document.editor message:SCI_GETSELECTIONSTART];
	long end = [document.editor message:SCI_GETSELECTIONEND];
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
	[document.editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	return [[NSString alloc] initWithBytes:buffer.data() length:(NSUInteger)length encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)replaceSelection:(NSString *)text {
	const char *bytes = text.UTF8String ?: "";
	[[self currentDocument].editor message:SCI_REPLACESEL wParam:0 lParam:(sptr_t)bytes];
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
	_statusOverride = text;
	[self refreshStatus];
}

- (void)updateTailButton {
	if (!_tailButton) {
		return;
	}
	BOOL on = [self currentDocument].fileMonitoring;
	_tailButton.state = on ? NSControlStateValueOn : NSControlStateValueOff;
	_tailButton.toolTip = on ? @"Stop tail -f" : @"Start tail -f";
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
	NSString *language = document.language.length ? document.language : @"Normal Text";
	if ([language isEqualToString:@"normal"] || [document.lexerName isEqualToString:@"null"]) {
		language = @"Normal Text";
	} else if ([language isEqualToString:@"javascript.js"]) {
		language = @"JavaScript";
	} else if ([language isEqualToString:@"json5"]) {
		language = @"JSON5";
	}
	if (document.fileMonitoring) {
		language = [language stringByAppendingString:@"    tail -f"];
	}
	if (_macro.recording) {
		language = [language stringByAppendingString:@"    RECORDING"];
	}
	long length = [document.editor message:SCI_GETLENGTH];
	NSString *base = [NSString stringWithFormat:@"  Ln %ld, Col %ld     %@     %s     %@     length %ld     %@", line, column, @(EncodingName(document.encoding)), eol, language, length, document.path.length ? document.path : @"unsaved"];
	_status.stringValue = _statusOverride.length ? [NSString stringWithFormat:@"%@     %@", base, _statusOverride] : base;
	[self syncEncodingChecks:[NSApp.mainMenu itemWithTitle:@"Encoding"].submenu document:document];
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
	alert.messageText = @"Notepad++ for Apple Silicon";
	alert.informativeText = @"Native arm64 port of Notepad++ 8.9.8.1.\nEditing engine: Scintilla 5.6.6 and Lexilla 5.5.3 from that release, with Notepad++'s Boost regular-expression search.\nThe Win32 shell and Windows plugins cannot run on macOS. This application is a GPL-3 derivative of Notepad++, Copyright 2021 Don HO and contributors.";
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

- (void)showPreferences:(id)sender {
	(void)sender;
	if (!_preferencesWindow) {
		_preferencesWindow = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 520) styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable backing:NSBackingStoreBuffered defer:NO];
		_preferencesWindow.title = @"Preferences";
		_preferencesWindow.releasedWhenClosed = NO;
		NSView *content = _preferencesWindow.contentView;
		[self preferenceField:@"Font" frame:NSMakeRect(20, 470, 250, 24) value:@"" tag:801 in:content];
		[self preferenceField:@"Size" frame:NSMakeRect(20, 436, 80, 24) value:@"" tag:802 in:content];
		[self preferenceField:@"Tab width" frame:NSMakeRect(20, 402, 80, 24) value:@"" tag:803 in:content];
		NSButton *spaces = [NSButton checkboxWithTitle:@"Insert spaces instead of tabs" target:nil action:nil];
		spaces.frame = NSMakeRect(20, 368, 260, 24);
		spaces.tag = 804;
		NSButton *wrap = [NSButton checkboxWithTitle:@"Word wrap" target:nil action:nil];
		wrap.frame = NSMakeRect(20, 340, 160, 24);
		wrap.tag = 805;
		NSButton *numbers = [NSButton checkboxWithTitle:@"Line numbers" target:nil action:nil];
		numbers.frame = NSMakeRect(190, 340, 140, 24);
		numbers.tag = 806;
		NSButton *whitespace = [NSButton checkboxWithTitle:@"Show whitespace" target:nil action:nil];
		whitespace.frame = NSMakeRect(340, 340, 180, 24);
		whitespace.tag = 807;
		NSTextField *themeLabel = [NSTextField labelWithString:@"Appearance"];
		themeLabel.frame = NSMakeRect(20, 304, 120, 24);
		NSPopUpButton *theme = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(150, 300, 180, 28) pullsDown:NO];
		theme.tag = 808;
		[theme addItemsWithTitles:@[@"Follow System", @"Light", @"Dark"]];
		NSButton *confirmClose = [NSButton checkboxWithTitle:@"Ask before closing a tab, folder, or the window" target:nil action:nil];
		confirmClose.frame = NSMakeRect(20, 268, 420, 24);
		confirmClose.tag = 809;
		NSTextField *shortcutLabel = [NSTextField labelWithString:@"Shortcuts, one per line as command=keys"];
		shortcutLabel.frame = NSMakeRect(20, 240, 400, 20);
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(20, 60, 520, 172)];
		scroll.hasVerticalScroller = YES;
		scroll.borderType = NSBezelBorder;
		_preferencesShortcuts = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, 500, 200)];
		_preferencesShortcuts.font = [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
		_preferencesShortcuts.automaticQuoteSubstitutionEnabled = NO;
		scroll.documentView = _preferencesShortcuts;
		NSButton *save = [self button:@"Save" action:@selector(savePreferences:) frame:NSMakeRect(360, 16, 80, 28)];
		NSButton *cancel = [self button:@"Cancel" action:@selector(closePreferences:) frame:NSMakeRect(450, 16, 90, 28)];
		for (NSView *view in @[spaces, wrap, numbers, whitespace, themeLabel, theme, confirmClose, shortcutLabel, scroll, save, cancel]) {
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
	font.stringValue = _settings.fontName ?: @"Menlo";
	size.stringValue = [NSString stringWithFormat:@"%d", _settings.fontSize];
	tabs.stringValue = [NSString stringWithFormat:@"%d", _settings.tabWidth];
	spaces.state = _settings.useTabs ? NSControlStateValueOff : NSControlStateValueOn;
	wrap.state = _settings.wrap ? NSControlStateValueOn : NSControlStateValueOff;
	numbers.state = _settings.lineNumbers ? NSControlStateValueOn : NSControlStateValueOff;
	whitespace.state = _settings.showWhitespace ? NSControlStateValueOn : NSControlStateValueOff;
	[theme selectItemAtIndex:[_settings.theme isEqualToString:@"light"] ? 1 : ([_settings.theme isEqualToString:@"dark"] ? 2 : 0)];
	confirmClose.state = _settings.confirmClose ? NSControlStateValueOn : NSControlStateValueOff;
	NSMutableString *shortcutText = [NSMutableString string];
	for (NSString *command in [_settings.shortcuts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		[shortcutText appendFormat:@"%@=%@\n", command, _settings.shortcuts[command]];
	}
	_preferencesShortcuts.string = shortcutText;
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
	_settings.fontName = font.stringValue.length ? font.stringValue : @"Menlo";
	_settings.fontSize = MAX(6, MIN(72, size.stringValue.intValue));
	_settings.tabWidth = MAX(1, MIN(32, tabs.stringValue.intValue));
	_settings.useTabs = spaces.state != NSControlStateValueOn;
	_settings.wrap = wrap.state == NSControlStateValueOn;
	_settings.lineNumbers = numbers.state == NSControlStateValueOn;
	_settings.showWhitespace = whitespace.state == NSControlStateValueOn;
	_settings.theme = theme.indexOfSelectedItem == 1 ? @"light" : (theme.indexOfSelectedItem == 2 ? @"dark" : @"system");
	_settings.confirmClose = confirmClose.state == NSControlStateValueOn;
	NSMutableDictionary *shortcutMap = [NSMutableDictionary dictionary];
	for (NSString *line in [_preferencesShortcuts.string componentsSeparatedByString:@"\n"]) {
		NSArray<NSString *> *parts = [line componentsSeparatedByString:@"="];
		if (parts.count == 2 && parts[0].length && parts[1].length) {
			shortcutMap[parts[0]] = parts[1];
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
	[_preferencesWindow close];
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
		_compareLabel.stringValue = @"The two panes match.";
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
	_compareLabel.stringValue = [NSString stringWithFormat:@"Difference %ld of %ld", (long)(index + 1), (long)_compareRows.count];
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

- (NSView *)buildFolderSidebar {
	NSView *side = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 280, 400)];
	side.wantsLayer = YES;
	side.layer.backgroundColor = NSColor.controlBackgroundColor.CGColor;
	NSTextField *title = [NSTextField labelWithString:@"Folder"];
	title.frame = NSMakeRect(10, 0, 150, 18);
	title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
	title.tag = 1;
	NSButton *up = [self button:@"Up" action:@selector(folderUp:) frame:NSMakeRect(0, 0, 36, 22)];
	up.tag = 3;
	up.toolTip = @"Enclosing folder";
	NSButton *hide = [self button:@"Hide" action:@selector(closeFolderSidebar:) frame:NSMakeRect(0, 0, 62, 22)];
	hide.tag = 4;
	hide.toolTip = @"Hide the folder";
	NSTextField *path = [[NSTextField alloc] initWithFrame:NSMakeRect(8, 0, 260, 24)];
	path.tag = 2;
	path.placeholderString = @"Folder path";
	path.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
	path.lineBreakMode = NSLineBreakByTruncatingHead;
	NSTextFieldCell *pathCell = path.cell;
	pathCell.wraps = NO;
	pathCell.scrollable = YES;
	path.target = self;
	path.action = @selector(commitFolderPath:);
	path.toolTip = @"Type a folder path and press Return";
	NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 280, 320)];
	scroll.hasVerticalScroller = YES;
	scroll.drawsBackground = NO;
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
	scroll.documentView = _folderOutline;
	for (NSView *view in @[title, up, hide, path, scroll]) {
		[side addSubview:view];
	}
	return side;
}

- (void)layoutFolderSidebar {
	CGFloat height = _sidebar.bounds.size.height;
	CGFloat width = _sidebar.bounds.size.width;
	for (NSView *view in _sidebar.subviews) {
		if (view.tag == 1) {
			view.frame = NSMakeRect(10, height - 24, MAX(40, width - 128), 18);
		} else if (view.tag == 3) {
			view.frame = NSMakeRect(width - 112, height - 26, 36, 22);
		} else if (view.tag == 4) {
			view.frame = NSMakeRect(width - 72, height - 26, 62, 22);
		} else if (view.tag == 2) {
			view.frame = NSMakeRect(8, height - 54, MAX(40, width - 16), 24);
		} else if ([view isKindOfClass:[NSScrollView class]]) {
			view.frame = NSMakeRect(0, 0, width, MAX(0, height - 62));
		}
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
	_folderRoot = path;
	_folderRootNode = [NppFolderNode new];
	_folderRootNode.path = path;
	_folderRootNode.name = path.lastPathComponent;
	_folderRootNode.directory = YES;
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
	if (!_folderRootNode) {
		return 0;
	}
	NppFolderNode *node = item ?: _folderRootNode;
	return node.directory ? (NSInteger)[self folderChildren:node].count : 0;
}

- (BOOL)outlineView:(NSOutlineView *)outlineView isItemExpandable:(id)item {
	(void)outlineView;
	return [item isKindOfClass:[NppFolderNode class]] && ((NppFolderNode *)item).directory;
}

- (id)outlineView:(NSOutlineView *)outlineView child:(NSInteger)index ofItem:(id)item {
	(void)outlineView;
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

- (void)openFolderItem:(id)sender {
	(void)sender;
	NppFolderNode *node = [_folderOutline itemAtRow:_folderOutline.clickedRow];
	if (![node isKindOfClass:[NppFolderNode class]]) {
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
			[_pluginErrors addObject:[NSString stringWithFormat:@"%@: not a Notepad++ Mac plugin", path.lastPathComponent]];
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
			? [NSString stringWithFormat:@"%@\n\nReload it and lose the changes made in Notepad++?", document.path]
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
	alert.messageText = @"Recover unsaved Notepad++ documents?";
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
	LangInfo *info = [_catalog languageNamed:item[@"language"]];
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
	return document;
}

- (BOOL)restoreSession {
	NSURL *url = [SupportDirectory() URLByAppendingPathComponent:@"session.json"];
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
			@"dirty": @(discard ? NO : document.dirty)
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
		@"folder": (_workspace.sidebarVisible && _folderRoot.length) ? _folderRoot : @""
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

@end
