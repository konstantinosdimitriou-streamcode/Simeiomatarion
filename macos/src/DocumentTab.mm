#import "DocumentTab.h"

#import "EditorSettings.h"
#import "ILexer.h"
#import "LangCatalog.h"
#import "Lexilla.h"
#import "StyleTheme.h"
#import "SciLexer.h"
#import "Scintilla.h"

#include <fcntl.h>
#include <unistd.h>

static NSColor *SRGB(int red, int green, int blue) {
	return [NSColor colorWithSRGBRed:red / 255.0 green:green / 255.0 blue:blue / 255.0 alpha:1];
}

static int KeywordIndex(NSString *name) {
	if ([name isEqualToString:@"instre1"]) return 0;
	if ([name isEqualToString:@"instre2"]) return 1;
	if ([name isEqualToString:@"type1"]) return 2;
	if ([name isEqualToString:@"type2"]) return 3;
	if ([name isEqualToString:@"type3"]) return 4;
	if ([name isEqualToString:@"type4"]) return 5;
	if ([name isEqualToString:@"type5"]) return 6;
	if ([name isEqualToString:@"type6"]) return 7;
	return -1;
}

@implementation DocumentTab {
	EditorSettings *_settings;
	BOOL _dark;
	NSMutableArray<NSString *> *_keywordStorage;
	dispatch_source_t _monitor;
	int _monitorFD;
}

- (instancetype)initWithFrame:(NSRect)frame {
	self = [super init];
	if (self) {
		_editor = [[ScintillaView alloc] initWithFrame:frame];
		_editor.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_editor.delegate = self;
		_encoding = kEncodingUTF8;
		_eolMode = SC_EOL_LF;
		_language = @"normal";
		_lexerName = @"null";
		_keywordStorage = [NSMutableArray array];
		_monitorFD = -1;
		[_editor message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];
		[_editor message:SCI_SETEOLMODE wParam:SC_EOL_LF lParam:0];
		[_editor message:SCI_SETMULTIPLESELECTION wParam:1 lParam:0];
		[_editor message:SCI_SETADDITIONALSELECTIONTYPING wParam:1 lParam:0];
		[_editor message:SCI_SETCHANGEHISTORY wParam:SC_CHANGE_HISTORY_DISABLED lParam:0];
		[_editor message:SCI_SETMARGINMASKN wParam:2 lParam:SC_MASK_FOLDERS];
		[_editor message:SCI_SETMARGINSENSITIVEN wParam:2 lParam:1];
		[_editor message:SCI_SETAUTOMATICFOLD wParam:(SC_AUTOMATICFOLD_SHOW | SC_AUTOMATICFOLD_CLICK | SC_AUTOMATICFOLD_CHANGE) lParam:0];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPEN lParam:SC_MARK_BOXMINUS];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDER lParam:SC_MARK_BOXPLUS];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERSUB lParam:SC_MARK_VLINE];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERTAIL lParam:SC_MARK_LCORNER];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEREND lParam:SC_MARK_BOXPLUSCONNECTED];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDEROPENMID lParam:SC_MARK_BOXMINUSCONNECTED];
		[_editor message:SCI_MARKERDEFINE wParam:SC_MARKNUM_FOLDERMIDTAIL lParam:SC_MARK_TCORNER];
		[_editor message:SCI_SETCARETLINEVISIBLE wParam:1 lParam:0];
		[_editor message:SCI_USEPOPUP wParam:0 lParam:0];
	}
	return self;
}

- (NSString *)title {
	NSString *name = self.displayName.length ? self.displayName : @"Untitled";
	if (self.fileMonitoring) {
		name = [name stringByAppendingString:@"  [tail]"];
	}
	return self.dirty ? [name stringByAppendingString:@" •"] : name;
}

- (void)setUtf8Text:(NSString *)text {
	self.suppressMacro = YES;
	[self.editor setString:text ?: @""];
	[self.editor message:SCI_EMPTYUNDOBUFFER];
	[self.editor message:SCI_COLOURISE wParam:0 lParam:-1];
	self.suppressMacro = NO;
	[self markClean];
}

- (NSString *)utf8Text {
	long length = [self.editor message:SCI_GETLENGTH];
	if (length < 0) {
		return @"";
	}
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	[self.editor message:SCI_GETTEXT wParam:static_cast<uptr_t>(length + 1) lParam:reinterpret_cast<sptr_t>(buffer.data())];
	buffer.resize(static_cast<size_t>(length));
	return [[NSString alloc] initWithBytes:buffer.data() length:buffer.size() encoding:NSUTF8StringEncoding] ?: @"";
}

- (void)dealloc {
	if (_monitor) {
		dispatch_source_cancel(_monitor);
		_monitor = nil;
	}
}

- (void)setFileMonitoring:(BOOL)enabled {
	if (_fileMonitoring == enabled && (!enabled || _monitor)) {
		return;
	}
	_fileMonitoring = enabled;
	if (_monitor) {
		dispatch_source_cancel(_monitor);
		_monitor = nil;
	}
	if (!enabled || self.path.length == 0) {
		[self.editor setEditable:YES];
		_fileMonitoring = NO;
		return;
	}
	int fd = open(self.path.fileSystemRepresentation, O_EVTONLY);
	if (fd < 0) {
		_fileMonitoring = NO;
		[self.editor setEditable:YES];
		return;
	}
	_monitorFD = fd;
	[self.editor setEditable:NO];
	dispatch_source_t source = dispatch_source_create(DISPATCH_SOURCE_TYPE_VNODE, (uintptr_t)fd, DISPATCH_VNODE_WRITE | DISPATCH_VNODE_EXTEND | DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME, dispatch_get_main_queue());
	__weak DocumentTab *weakSelf = self;
	dispatch_source_set_event_handler(source, ^{
		DocumentTab *strong = weakSelf;
		unsigned long flags = dispatch_source_get_data(source);
		if (!strong) {
			return;
		}
		if (flags & (DISPATCH_VNODE_DELETE | DISPATCH_VNODE_RENAME)) {
			[strong setFileMonitoring:NO];
			[strong.delegate documentTabDidChange:strong];
			return;
		}
		[strong reloadFromDiskScrollingToEnd:YES];
	});
	dispatch_source_set_cancel_handler(source, ^{
		close(fd);
	});
	dispatch_resume(source);
	_monitor = source;
}

- (void)reloadFromDiskScrollingToEnd:(BOOL)scrollToEnd {
	if (self.path.length == 0) {
		return;
	}
	NSData *data = [NSData dataWithContentsOfFile:self.path];
	if (!data) {
		return;
	}
	DecodedBuffer decoded = DecodeBuffer((const uint8_t *)data.bytes, data.length);
	NSString *text = [[NSString alloc] initWithBytes:decoded.utf8.data() length:decoded.utf8.size() encoding:NSUTF8StringEncoding] ?: @"";
	if ([text isEqualToString:[self utf8Text]]) {
		return;
	}
	long previous = [self.editor message:SCI_GETCURRENTPOS];
	[self setUtf8Text:text];
	self.encoding = decoded.encoding;
	self.eolMode = decoded.eolMode;
	long target = scrollToEnd ? [self.editor message:SCI_GETLENGTH] : previous;
	[self.editor message:SCI_GOTOPOS wParam:static_cast<uptr_t>(target) lParam:0];
	[self.editor message:SCI_SCROLLCARET];
	[self.delegate documentTabDidChange:self];
}

- (void)markClean {
	[self.editor message:SCI_SETSAVEPOINT];
	self.dirty = NO;
	[self.delegate documentTabDidChange:self];
}

- (void)applySettings:(EditorSettings *)settings dark:(BOOL)dark {
	_settings = settings;
	_dark = dark;
	ScintillaView *editor = self.editor;
	[editor setFontName:settings.fontName ?: @"Menlo" size:settings.fontSize bold:NO italic:NO];
	[editor message:SCI_SETTABWIDTH wParam:static_cast<uptr_t>(MAX(1, settings.tabWidth)) lParam:0];
	[editor message:SCI_SETUSETABS wParam:settings.useTabs ? 1 : 0 lParam:0];
	[editor message:SCI_SETWRAPMODE wParam:settings.wrap ? 1 : 0 lParam:0];
	[editor message:SCI_SETMARGINWIDTHN wParam:0 lParam:settings.lineNumbers ? 46 : 0];
	[editor message:SCI_SETMARGINTYPEN wParam:0 lParam:SC_MARGIN_NUMBER];
	[editor message:SCI_SETMARGINTYPEN wParam:1 lParam:SC_MARGIN_SYMBOL];
	[editor message:SCI_SETMARGINWIDTHN wParam:1 lParam:16];
	[editor message:SCI_SETMARGINMASKN wParam:1 lParam:(1 << 20)];
	[editor message:SCI_MARKERDEFINE wParam:20 lParam:SC_MARK_BOOKMARK];
	[editor message:SCI_SETMARGINWIDTHN wParam:2 lParam:16];
	[editor message:SCI_SETVIEWWS wParam:settings.showWhitespace ? SCWS_VISIBLEALWAYS : SCWS_INVISIBLE lParam:0];
	[editor message:SCI_SETEOLMODE wParam:static_cast<uptr_t>(self.eolMode) lParam:0];
	[self restyle];
}

- (void)applyLanguage:(LangInfo *)info dark:(BOOL)dark {
	if (!info) {
		return;
	}
	_dark = dark;
	self.language = info.name ?: @"normal";
	self.lexerName = info.lexer.length ? info.lexer : @"null";
	[_keywordStorage removeAllObjects];
	for (NSString *slot in info.keywords) {
		NSString *words = info.keywords[slot];
		if (words.length) {
			[_keywordStorage addObject:words];
		}
	}
	ILexer5 *lexer = CreateLexer(self.lexerName.UTF8String);
	if (!lexer) {
		NSString *lower = self.lexerName.lowercaseString;
		lexer = CreateLexer(lower.UTF8String);
		if (lexer) {
			self.lexerName = lower;
		}
	}
	if (!lexer) {
		self.lexerName = @"null";
		lexer = CreateLexer("null");
	}
	[self.editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
	[self.editor setLexerProperty:@"fold" value:@"1"];
	[self.editor setLexerProperty:@"fold.compact" value:@"0"];
	[self.editor setLexerProperty:@"fold.comment" value:@"1"];
	[self.editor setLexerProperty:@"fold.preprocessor" value:@"1"];
	[self.editor setLexerProperty:@"fold.html" value:@"1"];
	if ([self.lexerName isEqualToString:@"json"]) {
		[self.editor setLexerProperty:@"lexer.json.escape.sequence" value:@"1"];
		BOOL comments = [self.language isEqualToString:@"json5"];
		[self.editor setLexerProperty:@"lexer.json.allow.comments" value:comments ? @"1" : @"0"];
	}
	for (NSString *slot in info.keywords) {
		int index = KeywordIndex(slot);
		if (index < 0) {
			continue;
		}
		NSString *words = info.keywords[slot];
		[self.editor setReferenceProperty:SCI_SETKEYWORDS parameter:index value:words.UTF8String];
	}
	[self restyle];
	[self.editor message:SCI_COLOURISE wParam:0 lParam:-1];
	[self.delegate documentTabDidChange:self];
}

- (void)restyle {
	ScintillaView *editor = self.editor;
	NSColor *background = _dark ? SRGB(30, 30, 30) : NSColor.whiteColor;
	NSColor *foreground = _dark ? SRGB(212, 212, 212) : NSColor.blackColor;
	[editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_DEFAULT value:foreground];
	[editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_DEFAULT value:background];
	[editor setGeneralProperty:SCI_STYLECLEARALL parameter:0 value:0];
	[editor setColorProperty:SCI_STYLESETFORE parameter:STYLE_LINENUMBER value:_dark ? SRGB(133, 133, 133) : SRGB(128, 128, 128)];
	[editor setColorProperty:SCI_STYLESETBACK parameter:STYLE_LINENUMBER value:_dark ? SRGB(37, 37, 38) : SRGB(240, 240, 240)];
	[editor setColorProperty:SCI_SETCARETFORE parameter:0 value:foreground];
	[editor message:SCI_SETCARETLINEBACK wParam:_dark ? 0x282828 : 0xF5F5F5 lParam:0];

	static StyleTheme *theme;
	static dispatch_once_t once;
	dispatch_once(&once, ^{
		NSString *path = [NSBundle.mainBundle pathForResource:@"stylers.model" ofType:@"xml"];
		theme = [StyleTheme themeWithXML:path];
	});
	[theme applyToEditor:editor language:self.language dark:_dark];
	if ([self.lexerName isEqualToString:@"hypertext"] || [self.lexerName isEqualToString:@"xml"] || [self.lexerName isEqualToString:@"phpscript"]) {
		[theme applyToEditor:editor language:@"html" dark:_dark];
		[theme applyToEditor:editor language:@"javascript" dark:_dark];
	}
	if (_settings) {
		[editor setFontName:_settings.fontName ?: @"Menlo" size:_settings.fontSize bold:NO italic:NO];
	}
}

- (void)notification:(SCNotification *)notification {
	if (!notification) {
		return;
	}
	if (notification->nmhdr.code == SCN_SAVEPOINTREACHED) {
		self.dirty = NO;
		[self.delegate documentTabDidChange:self];
	} else if (notification->nmhdr.code == SCN_SAVEPOINTLEFT) {
		self.dirty = YES;
		[self.delegate documentTabDidChange:self];
	} else if (notification->nmhdr.code == SCN_MODIFIED && !self.suppressMacro) {
		int type = notification->modificationType;
		if ((type & SC_PERFORMED_USER) && notification->text && notification->length > 0) {
			NSString *text = [[NSString alloc] initWithBytes:notification->text length:static_cast<NSUInteger>(notification->length) encoding:NSUTF8StringEncoding];
			if (text.length) {
				if (type & SC_MOD_INSERTTEXT) {
					[self.delegate documentTab:self insertedText:text at:notification->position];
				} else if (type & SC_MOD_DELETETEXT) {
					[self.delegate documentTab:self deletedText:text at:notification->position];
				}
			}
		}
	} else if (notification->nmhdr.code == SCN_MARGINCLICK && notification->margin == 2) {
		long line = [self.editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)notification->position lParam:0];
		[self.editor message:SCI_TOGGLEFOLD wParam:(uptr_t)line lParam:0];
	} else if (notification->nmhdr.code == SCN_UPDATEUI) {
		[self highlightBraces];
		[self.delegate documentTabDidChange:self];
	}
}

- (void)highlightBraces {
	long position = [self.editor message:SCI_GETCURRENTPOS];
	long length = [self.editor message:SCI_GETLENGTH];
	auto isBrace = [](long value) {
		return value == '(' || value == ')' || value == '[' || value == ']' || value == '{' || value == '}';
	};
	long brace = -1;
	if (position > 0 && isBrace([self.editor message:SCI_GETCHARAT wParam:static_cast<uptr_t>(position - 1) lParam:0])) {
		brace = position - 1;
	} else if (position < length && isBrace([self.editor message:SCI_GETCHARAT wParam:static_cast<uptr_t>(position) lParam:0])) {
		brace = position;
	}
	if (brace < 0) {
		[self.editor message:SCI_BRACEHIGHLIGHT wParam:static_cast<uptr_t>(-1) lParam:-1];
		return;
	}
	long match = [self.editor message:SCI_BRACEMATCH wParam:static_cast<uptr_t>(brace) lParam:0];
	if (match >= 0) {
		[self.editor message:SCI_BRACEHIGHLIGHT wParam:static_cast<uptr_t>(brace) lParam:match];
	} else {
		[self.editor message:SCI_BRACEBADLIGHT wParam:static_cast<uptr_t>(brace) lParam:0];
	}
}

@end
