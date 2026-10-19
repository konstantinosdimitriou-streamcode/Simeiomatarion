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

@interface NppTabButton : NSButton
@property (nonatomic, weak) AppDelegate *owner;
@end

@implementation NppTabButton
- (void)rightMouseDown:(NSEvent *)event {
	[self.owner selectTabForContext:self.tag];
	NSMenu *menu = [self.owner tabContextMenu];
	if (menu) {
		[NSMenu popUpContextMenu:menu withEvent:event forView:self];
	}
}
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
@property (nonatomic, assign) BOOL findVisible;
@property (nonatomic, assign) BOOL resultsVisible;
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
	CGFloat tabHeight = 30;
	CGFloat statusHeight = 24;
	CGFloat findHeight = self.findVisible ? 96 : 0;
	CGFloat resultsHeight = self.resultsVisible ? 260 : 0;
	CGFloat top = menuHeight + toolbarHeight + tabHeight;
	self.menuBar.frame = NSMakeRect(0, bounds.size.height - menuHeight, bounds.size.width, menuHeight);
	self.toolbar.frame = NSMakeRect(0, bounds.size.height - menuHeight - toolbarHeight, bounds.size.width, toolbarHeight);
	self.tabStrip.frame = NSMakeRect(0, bounds.size.height - top, bounds.size.width, tabHeight);
	self.status.frame = NSMakeRect(0, 0, bounds.size.width, statusHeight);
	self.results.frame = NSMakeRect(0, statusHeight, bounds.size.width, resultsHeight);
	self.results.hidden = !self.resultsVisible;
	self.findBar.frame = NSMakeRect(0, statusHeight + resultsHeight, bounds.size.width, findHeight);
	self.findBar.hidden = !self.findVisible;
	CGFloat bottom = statusHeight + resultsHeight + findHeight;
	NSRect editorFrame = NSMakeRect(0, bottom, bounds.size.width, MAX(0, bounds.size.height - top - bottom));
	self.tabs.frame = editorFrame;
	self.tabs.clipsToBounds = YES;
	if ([self.tabs isKindOfClass:[NSTabView class]]) {
		NSTabView *tabs = (NSTabView *)self.tabs;
		for (NSTabViewItem *item in tabs.tabViewItems) {
			item.view.frame = tabs.bounds;
		}
	}
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

@implementation AppDelegate {
	NSWindow *_window;
	WorkspaceView *_workspace;
	NSView *_menuBar;
	NSView *_toolbar;
	NSView *_tabStrip;
	NSTabView *_tabs;
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
	[self saveSession];
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
	_menuBar = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 26)];
	_toolbar = [self buildToolbar];
	_tabStrip = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 1100, 30)];
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
	_workspace.tabs = _tabs;
	_workspace.findBar = find;
	_workspace.status = _status;
	_workspace.findVisible = NO;
	[_workspace addSubview:_menuBar];
	[_workspace addSubview:_toolbar];
	[_workspace addSubview:_resultsPanel];
	[_workspace addSubview:_tabStrip];
	[_workspace addSubview:_tabs];
	[_workspace addSubview:find];
	[_workspace addSubview:_status];
	_window.contentView = _workspace;
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
		@[@"text.append", @"Monitoring (tail -f)", NSStringFromSelector(@selector(toggleMonitoring:))],
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
		NSButton *button = [self toolButton:item[0] tip:item[1] action:NSSelectorFromString(item[2])];
		button.frame = NSMakeRect(x, 6, 32, 30);
		[bar addSubview:button];
		x += 36;
	}
	return bar;
}

- (void)rebuildTabStrip {
	for (NSView *view in _tabStrip.subviews.copy) {
		[view removeFromSuperview];
	}
	DocumentTab *selected = [self currentDocument];
	CGFloat x = 6;
	for (NSTabViewItem *item in _tabs.tabViewItems) {
		DocumentTab *document = item.identifier;
		if (![document isKindOfClass:[DocumentTab class]]) {
			continue;
		}
		BOOL current = document == selected;
		NSInteger index = (NSInteger)[_tabs indexOfTabViewItem:item];
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
		button.action = @selector(selectTabButton:);
		button.tag = index;
		button.bordered = NO;
		[button sizeToFit];
		CGFloat width = MAX(110, button.frame.size.width + 30);
		NSView *tab = [[NSView alloc] initWithFrame:NSMakeRect(x, 3, width, 24)];
		tab.wantsLayer = YES;
		tab.layer.cornerRadius = 5;
		tab.layer.backgroundColor = (current ? NSColor.controlBackgroundColor : NSColor.clearColor).CGColor;
		if (current) {
			tab.layer.borderWidth = 1;
			tab.layer.borderColor = NSColor.controlAccentColor.CGColor;
		}
		button.frame = NSMakeRect(0, 0, width, 24);
		NSButton *close = [[NSButton alloc] initWithFrame:NSMakeRect(width - 22, 2, 18, 20)];
		close.bordered = NO;
		close.title = @"×";
		close.contentTintColor = textColor;
		close.font = [NSFont systemFontOfSize:15 weight:NSFontWeightSemibold];
		close.target = self;
		close.action = @selector(closeTabButton:);
		close.tag = index;
		close.toolTip = @"Close";
		[tab addSubview:button];
		[tab addSubview:close];
		[_tabStrip addSubview:tab];
		x += width + 4;
	}
}

- (void)selectTabButton:(NSButton *)sender {
	if (sender.tag >= 0 && sender.tag < (NSInteger)_tabs.numberOfTabViewItems) {
		[_tabs selectTabViewItemAtIndex:sender.tag];
	}
	[self rebuildTabStrip];
}

- (void)closeTabButton:(NSButton *)sender {
	if (sender.tag < 0 || sender.tag >= (NSInteger)_tabs.numberOfTabViewItems) {
		return;
	}
	[_tabs selectTabViewItemAtIndex:sender.tag];
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
	NSAppearanceName match = [_window.effectiveAppearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameDarkAqua, NSAppearanceNameAqua]];
	return [match isEqualToString:NSAppearanceNameDarkAqua];
}

- (void)addDocument:(DocumentTab *)document {
	document.delegate = (id<DocumentTabDelegate>)self;
	[_documents addObject:document];
	NSTabViewItem *item = [[NSTabViewItem alloc] initWithIdentifier:document];
	item.label = document.title;
	item.view = document.editor;
	document.editor.clipsToBounds = YES;
	[_tabs addTabViewItem:item];
	[_tabs selectTabViewItem:item];
	[document applySettings:_settings dark:[self darkAppearance]];
	[self attachEditorMenu:document];
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
			NSTabViewItem *item = [self itemForDocument:existing];
			if (item) {
				[_tabs selectTabViewItem:item];
				[self rebuildTabStrip];
				opened = YES;
			}
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

- (void)closeDocument:(id)sender {
	(void)sender;
	DocumentTab *document = [self currentDocument];
	if (!document) {
		return;
	}
	if (document.dirty) {
		NSAlert *alert = [NSAlert new];
		alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", document.displayName];
		[alert addButtonWithTitle:@"Save"];
		[alert addButtonWithTitle:@"Don't Save"];
		[alert addButtonWithTitle:@"Cancel"];
		NSModalResponse response = [alert runModal];
		if (response == NSAlertFirstButtonReturn) {
			[self saveDocument:nil];
			if (document.dirty) {
				return;
			}
		} else if (response == NSAlertThirdButtonReturn) {
			return;
		}
	}
	NSTabViewItem *item = _tabs.selectedTabViewItem;
	[document setFileMonitoring:NO];
	[_documents removeObject:document];
	[_tabs removeTabViewItem:item];
	if (_documents.count == 0) {
		[self newDocument:nil];
	}
	[self rebuildTabStrip];
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
	for (DocumentTab *document in [_documents copy]) {
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		NSUInteger before = _documents.count;
		[self closeDocument:sender];
		if (document.dirty && _documents.count == before) {
			return;
		}
	}
}

- (void)closeOtherDocuments:(id)sender {
	DocumentTab *keep = [self currentDocument];
	for (DocumentTab *document in [_documents copy]) {
		if (document == keep) {
			continue;
		}
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		NSUInteger before = _documents.count;
		[self closeDocument:sender];
		if (document.dirty && _documents.count == before) {
			return;
		}
	}
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
	NSInteger count = (NSInteger)_tabs.numberOfTabViewItems;
	if (count == 0) {
		return;
	}
	NSInteger index = (NSInteger)[_tabs indexOfTabViewItem:_tabs.selectedTabViewItem];
	index = (index + offset + count) % count;
	[_tabs selectTabViewItemAtIndex:index];
	[self rebuildTabStrip];
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
		[_tabs selectTabViewItemAtIndex:sender.tag];
		[self rebuildTabStrip];
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
		if ([existing.path isEqualToString:hit.path]) {
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
		[_tabs selectTabViewItem:[self itemForDocument:document]];
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
	(void)tableView;
	return (NSInteger)_hits.count;
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)column row:(NSInteger)row {
	(void)tableView;
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
		[_tabs selectTabViewItemAtIndex:index];
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

- (void)refreshStatus {
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
}

- (void)documentTab:(DocumentTab *)tab deletedText:(NSString *)text at:(NSInteger)position {
	if (tab == [self currentDocument]) {
		[_macro addDelete:text at:position];
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

- (void)showPreferences:(id)sender {
	(void)sender;
	NSAlert *alert = [[NSAlert alloc] init];
	alert.messageText = @"Editor settings";
	NSView *accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 420, 230)];
	NSTextField *shortcuts = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 150, 420, 72)];
	NSMutableString *shortcutText = [NSMutableString string];
	for (NSString *command in [_settings.shortcuts.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
		[shortcutText appendFormat:@"%@=%@\n", command, _settings.shortcuts[command]];
	}
	shortcuts.stringValue = shortcutText;
	shortcuts.font = [NSFont monospacedSystemFontOfSize:11 weight:NSFontWeightRegular];
	[accessory addSubview:[NSTextField labelWithString:@"Shortcuts (command=keys)"]];
	accessory.subviews.lastObject.frame = NSMakeRect(0, 206, 220, 18);
	[accessory addSubview:shortcuts];
	NSTextField *font = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 116, 200, 24)];
	font.stringValue = _settings.fontName;
	NSTextField *size = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 86, 60, 24)];
	size.stringValue = [NSString stringWithFormat:@"%d", _settings.fontSize];
	NSTextField *tabs = [[NSTextField alloc] initWithFrame:NSMakeRect(140, 56, 60, 24)];
	tabs.stringValue = [NSString stringWithFormat:@"%d", _settings.tabWidth];
	NSButton *spaces = [NSButton checkboxWithTitle:@"Insert spaces instead of tabs" target:nil action:nil];
	spaces.frame = NSMakeRect(140, 28, 220, 24);
	spaces.state = _settings.useTabs ? NSControlStateValueOff : NSControlStateValueOn;
	NSButton *wrap = [NSButton checkboxWithTitle:@"Wrap" target:nil action:nil];
	wrap.frame = NSMakeRect(0, 28, 80, 24);
	wrap.state = _settings.wrap ? NSControlStateValueOn : NSControlStateValueOff;
	NSButton *numbers = [NSButton checkboxWithTitle:@"Line numbers" target:nil action:nil];
	numbers.frame = NSMakeRect(0, 4, 120, 24);
	numbers.state = _settings.lineNumbers ? NSControlStateValueOn : NSControlStateValueOff;
	NSButton *whitespace = [NSButton checkboxWithTitle:@"Whitespace" target:nil action:nil];
	whitespace.frame = NSMakeRect(140, 4, 120, 24);
	whitespace.state = _settings.showWhitespace ? NSControlStateValueOn : NSControlStateValueOff;
	[accessory addSubview:[NSTextField labelWithString:@"Font"]];
	accessory.subviews.lastObject.frame = NSMakeRect(0, 116, 120, 20);
	[accessory addSubview:font];
	[accessory addSubview:[NSTextField labelWithString:@"Size"]];
	accessory.subviews.lastObject.frame = NSMakeRect(0, 86, 120, 20);
	[accessory addSubview:size];
	[accessory addSubview:[NSTextField labelWithString:@"Tab width"]];
	accessory.subviews.lastObject.frame = NSMakeRect(0, 56, 120, 20);
	[accessory addSubview:tabs];
	[accessory addSubview:spaces];
	[accessory addSubview:wrap];
	[accessory addSubview:numbers];
	[accessory addSubview:whitespace];
	alert.accessoryView = accessory;
	[alert addButtonWithTitle:@"Save"];
	[alert addButtonWithTitle:@"Cancel"];
	if ([alert runModal] != NSAlertFirstButtonReturn) {
		return;
	}
	_settings.fontName = font.stringValue.length ? font.stringValue : @"Menlo";
	_settings.fontSize = MAX(6, MIN(72, size.stringValue.intValue));
	_settings.tabWidth = MAX(1, MIN(32, tabs.stringValue.intValue));
	_settings.useTabs = spaces.state != NSControlStateValueOn;
	_settings.wrap = wrap.state == NSControlStateValueOn;
	_settings.lineNumbers = numbers.state == NSControlStateValueOn;
	_settings.showWhitespace = whitespace.state == NSControlStateValueOn;
	NSError *error = nil;
	NSMutableDictionary *shortcutMap = [NSMutableDictionary dictionary];
	for (NSString *line in [shortcuts.stringValue componentsSeparatedByString:@"\n"]) {
		NSArray<NSString *> *parts = [line componentsSeparatedByString:@"="];
		if (parts.count == 2 && parts[0].length && parts[1].length) {
			shortcutMap[parts[0]] = parts[1];
		}
	}
	if (shortcutMap.count) {
		_settings.shortcuts = shortcutMap;
	}
	[_settings saveToURL:[SupportDirectory() URLByAppendingPathComponent:@"settings.json"] error:&error];
	[self buildMenus];
	for (DocumentTab *document in _documents) {
		[document applySettings:_settings dark:[self darkAppearance]];
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
	if (selected >= 0 && selected < (NSInteger)_documents.count) {
		[_tabs selectTabViewItem:[self itemForDocument:_documents[selected]]];
		[self rebuildTabStrip];
	}
	return restored > 0;
}

- (void)saveSession {
	NSMutableArray *documents = [NSMutableArray array];
	for (DocumentTab *document in _documents) {
		long position = [document.editor message:SCI_GETCURRENTPOS];
		long firstLine = [document.editor message:SCI_GETFIRSTVISIBLELINE];
		BOOL keepText = document.dirty || document.path.length == 0;
		NSMutableDictionary *item = [@{
			@"path": document.path ?: @"",
			@"displayName": document.displayName ?: @"",
			@"encoding": @(document.encoding),
			@"eol": @(document.eolMode),
			@"language": document.language ?: @"normal",
			@"manualLanguage": @(document.manualLanguage),
			@"position": @(position),
			@"firstLine": @(firstLine),
			@"dirty": @(document.dirty)
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
	NSDictionary *session = @{
		@"selected": @(selected),
		@"frame": @[@(frame.origin.x), @(frame.origin.y), @(frame.size.width), @(frame.size.height)],
		@"documents": documents
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
	for (DocumentTab *document in [_documents copy]) {
		if (!document.dirty) {
			continue;
		}
		[_tabs selectTabViewItem:[self itemForDocument:document]];
		NSAlert *alert = [NSAlert new];
		alert.messageText = [NSString stringWithFormat:@"Save changes to %@?", document.displayName];
		alert.informativeText = @"Remember keeps these edits for the next time Notepad++ opens. The file on disk is left unchanged.";
		[alert addButtonWithTitle:@"Save"];
		[alert addButtonWithTitle:@"Remember"];
		[alert addButtonWithTitle:@"Cancel"];
		NSModalResponse response = [alert runModal];
		if (response == NSAlertFirstButtonReturn) {
			[self saveDocument:nil];
			if (document.dirty) {
				return NSTerminateCancel;
			}
		} else if (response == NSAlertThirdButtonReturn) {
			return NSTerminateCancel;
		}
	}
	[self saveSession];
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
