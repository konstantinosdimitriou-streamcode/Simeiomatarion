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
	ScintillaView *_mirror;
	BOOL _pairing;
	BOOL _spellEcho;
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
		[_editor message:SCI_SETMULTIPASTE wParam:SC_MULTIPASTE_EACH lParam:0];
		[_editor message:SCI_SETADDITIONALCARETSVISIBLE wParam:1 lParam:0];
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
	if (self.pinned) {
		name = [@"📌 " stringByAppendingString:name];
	}
	if (self.fileMonitoring) {
		name = [name stringByAppendingString:@"  [tail]"];
	}
	return self.dirty ? [name stringByAppendingString:@" •"] : name;
}

- (void)setUtf8Text:(NSString *)text {
	self.suppressMacro = YES;
	sptr_t readonly = [self.editor message:SCI_GETREADONLY];
	if (readonly) {
		[self.editor message:SCI_SETREADONLY wParam:0 lParam:0];
	}
	[self.editor setString:text ?: @""];
	[self.editor message:SCI_EMPTYUNDOBUFFER];
	[self.editor message:SCI_COLOURISE wParam:0 lParam:-1];
	if (readonly) {
		[self.editor message:SCI_SETREADONLY wParam:1 lParam:0];
	}
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
	_mirror.delegate = nil;
	_mirror = nil;
}

- (void)applyChromeTo:(ScintillaView *)editor settings:(EditorSettings *)settings {
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
	[editor message:SCI_SETCHANGEHISTORY wParam:settings.showChanges ? SC_CHANGE_HISTORY_MARKERS : SC_CHANGE_HISTORY_DISABLED lParam:0];
	[editor message:SCI_SETMARGINTYPEN wParam:3 lParam:SC_MARGIN_SYMBOL];
	[editor message:SCI_SETMARGINMASKN wParam:3 lParam:SC_MASK_HISTORY];
	[editor message:SCI_SETMARGINWIDTHN wParam:3 lParam:settings.showChanges ? 8 : 0];
	[editor message:SCI_INDICSETSTYLE wParam:11 lParam:INDIC_SQUIGGLE];
	[editor message:SCI_INDICSETFORE wParam:11 lParam:0x0000FF];
	[editor message:SCI_SETMULTIPLESELECTION wParam:1 lParam:0];
	[editor message:SCI_SETADDITIONALSELECTIONTYPING wParam:1 lParam:0];
	[editor message:SCI_SETMULTIPASTE wParam:SC_MULTIPASTE_EACH lParam:0];
	[editor message:SCI_SETADDITIONALCARETSVISIBLE wParam:1 lParam:0];
}

- (ScintillaView *)existingMirror {
	return _mirror;
}

- (ScintillaView *)mirrorView {
	if (_mirror) {
		return _mirror;
	}
	_mirror = [[ScintillaView alloc] initWithFrame:NSZeroRect];
	_mirror.delegate = self;
	_mirror.clipsToBounds = YES;
	_mirror.autoresizingMask = NSViewNotSizable;
	sptr_t document = [self.editor message:SCI_GETDOCPOINTER wParam:0 lParam:0];
	[self.editor message:SCI_ADDREFDOCUMENT wParam:0 lParam:document];
	[_mirror message:SCI_SETDOCPOINTER wParam:0 lParam:document];
	if (_settings) {
		[self applyChromeTo:_mirror settings:_settings];
	}
	[self restyleEditor:_mirror];
	return _mirror;
}

- (void)discardMirror {
	_mirror.delegate = nil;
	[_mirror removeFromSuperview];
	_mirror = nil;
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
	NSString *extension = self.path.pathExtension.lowercaseString;
	if ([extension isEqualToString:@"pdf"] || [extension isEqualToString:@"doc"] || [extension isEqualToString:@"docx"] || [extension isEqualToString:@"xlsx"]) {
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
	[self applyChromeTo:self.editor settings:settings];
	if (_mirror) {
		[self applyChromeTo:_mirror settings:settings];
	}
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
	[self restyleEditor:self.editor];
	if (_mirror) {
		[self restyleEditor:_mirror];
	}
}

- (void)restyleEditor:(ScintillaView *)editor {
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
		int updated = notification->updated;
		if ((updated & SC_UPDATE_V_SCROLL) && [self.delegate respondsToSelector:@selector(documentTabDidScroll:)]) {
			[self.delegate documentTabDidScroll:self];
		}
		if (updated & (SC_UPDATE_CONTENT | SC_UPDATE_SELECTION)) {
			if (_spellEcho) {
				return;
			}
			[self.delegate documentTabDidChange:self];
			if (_settings.spellCheck) {
				[NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(refreshSpelling) object:nil];
				[self performSelector:@selector(refreshSpelling) withObject:nil afterDelay:0.35];
			}
		}
	} else if (notification->nmhdr.code == SCN_CHARADDED && !_pairing) {
		[self handleTypedCharacter:notification->ch];
	}
}

- (NSString *)textFrom:(long)start to:(long)end {
	if (end <= start) {
		return @"";
	}
	long length = MIN(end - start, 12000);
	std::string buffer(static_cast<size_t>(length) + 1, '\0');
	Sci_TextRangeFull range;
	range.chrg.cpMin = start;
	range.chrg.cpMax = start + length;
	range.lpstrText = buffer.data();
	[self.editor message:SCI_GETTEXTRANGEFULL wParam:0 lParam:(sptr_t)&range];
	NSString *text = nil;
	NSUInteger count = (NSUInteger)length;
	while (count > 0 && !text) {
		text = [[NSString alloc] initWithBytes:buffer.data() length:count encoding:NSUTF8StringEncoding];
		if (!text) {
			count--;
		}
	}
	return text ?: @"";
}

- (void)insertText:(NSString *)text at:(long)position caret:(long)caret {
	const char *bytes = text.UTF8String ?: "";
	_pairing = YES;
	self.suppressMacro = YES;
	[self.editor message:SCI_INSERTTEXT wParam:(uptr_t)position lParam:(sptr_t)bytes];
	[self.editor message:SCI_GOTOPOS wParam:(uptr_t)caret lParam:0];
	self.suppressMacro = NO;
	_pairing = NO;
}

- (void)handleTypedCharacter:(int)character {
	if (!_settings) {
		return;
	}
	BOOL newline = character == '\n' || character == '\r';
	if (newline && _settings.smartIndent) {
		if (character == '\r' && self.eolMode != SC_EOL_CR) {
			return;
		}
		if (character == '\n' && self.eolMode == SC_EOL_CR) {
			return;
		}
		[self indentAfterEnter];
		return;
	}
	if (!_settings.autoClose || newline) {
		return;
	}
	NSString *typed = [NSString stringWithFormat:@"%c", character];
	NSDictionary<NSString *, NSString *> *pairs = @{@"(": @")", @"[": @"]", @"{": @"}", @"\"": @"\"", @"'": @"'"};
	long position = [self.editor message:SCI_GETCURRENTPOS];
	if ([@")]}'\"" containsString:typed]) {
		long next = [self.editor message:SCI_GETCHARAT wParam:(uptr_t)position lParam:0];
		if (next == character && position > 0) {
			_pairing = YES;
			[self.editor message:SCI_DELETERANGE wParam:(uptr_t)(position - 1) lParam:1];
			_pairing = NO;
		}
		return;
	}
	NSString *closer = pairs[typed];
	if (!closer) {
		return;
	}
	if ((character == '"' || character == '\'') && position > 1) {
		long previous = [self.editor message:SCI_GETCHARAT wParam:(uptr_t)(position - 2) lParam:0];
		if ((previous >= '0' && previous <= '9') || (previous >= 'A' && previous <= 'Z') || (previous >= 'a' && previous <= 'z') || previous == '_') {
			return;
		}
	}
	[self insertText:closer at:position caret:position];
}

- (void)indentAfterEnter {
	long position = [self.editor message:SCI_GETCURRENTPOS];
	long line = [self.editor message:SCI_LINEFROMPOSITION wParam:(uptr_t)position lParam:0];
	if (line <= 0) {
		return;
	}
	long previousStart = [self.editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)(line - 1) lParam:0];
	long previousEnd = [self.editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)(line - 1) lParam:0];
	NSString *previous = [self textFrom:previousStart to:previousEnd];
	NSUInteger index = 0;
	while (index < previous.length) {
		unichar value = [previous characterAtIndex:index];
		if (value != ' ' && value != '\t') {
			break;
		}
		index++;
	}
	NSString *indent = [previous substringToIndex:index];
	NSString *trimmed = [previous stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
	BOOL opens = trimmed.length && ([trimmed hasSuffix:@"{"] || [trimmed hasSuffix:@"("] || [trimmed hasSuffix:@"["] || [trimmed hasSuffix:@":"]);
	NSString *extra = @"";
	if (opens) {
		extra = _settings.useTabs ? @"\t" : [@"" stringByPaddingToLength:MAX(1, _settings.tabWidth) withString:@" " startingAtIndex:0];
	}
	long next = [self.editor message:SCI_GETCHARAT wParam:(uptr_t)position lParam:0];
	BOOL closes = next == '}' || next == ')' || next == ']';
	NSString *insertion = [indent stringByAppendingString:extra];
	long caret = position + (long)[insertion lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
	if (opens && closes) {
		insertion = [NSString stringWithFormat:@"%@\n%@", insertion, indent];
	}
	if (insertion.length == 0) {
		return;
	}
	[self insertText:insertion at:position caret:caret];
}

- (void)refreshSpelling {
	ScintillaView *editor = self.editor;
	long length = [editor message:SCI_GETLENGTH];
	_spellEcho = YES;
	[editor message:SCI_SETINDICATORCURRENT wParam:11 lParam:0];
	[editor message:SCI_INDICATORCLEARRANGE wParam:0 lParam:length];
	__weak DocumentTab *weakSelf = self;
	dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.2 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
		DocumentTab *strongSelf = weakSelf;
		strongSelf->_spellEcho = NO;
	});
	if (!_settings.spellCheck) {
		return;
	}
	BOOL prose = [self.lexerName isEqualToString:@"null"] || [self.lexerName isEqualToString:@"markdown"] || [self.language isEqualToString:@"normal"] || [self.language isEqualToString:@"markdown"];
	if (!prose) {
		return;
	}
	long firstDisplay = [editor message:SCI_GETFIRSTVISIBLELINE];
	long startLine = [editor message:SCI_DOCLINEFROMVISIBLE wParam:(uptr_t)firstDisplay lParam:0];
	long lastLine = MIN([editor message:SCI_GETLINECOUNT] - 1, startLine + [editor message:SCI_LINESONSCREEN] + 1);
	long start = [editor message:SCI_POSITIONFROMLINE wParam:(uptr_t)MAX(0, startLine) lParam:0];
	long end = [editor message:SCI_GETLINEENDPOSITION wParam:(uptr_t)MAX(0, lastLine) lParam:0];
	if (end - start > 12000) {
		end = start + 12000;
	}
	NSString *text = [self textFrom:start to:end];
	if (text.length == 0) {
		return;
	}
	NSSpellChecker *checker = [NSSpellChecker sharedSpellChecker];
	NSInteger location = 0;
	while (location < (NSInteger)text.length) {
		NSRange range = [checker checkSpellingOfString:text startingAt:location language:nil wrap:NO inSpellDocumentWithTag:0 wordCount:NULL];
		if (range.location == NSNotFound || range.length == 0) {
			break;
		}
		NSString *prefix = [text substringToIndex:range.location];
		NSString *word = [text substringWithRange:range];
		long byteStart = start + (long)[prefix lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		long byteLength = (long)[word lengthOfBytesUsingEncoding:NSUTF8StringEncoding];
		[editor message:SCI_INDICATORFILLRANGE wParam:(uptr_t)byteStart lParam:byteLength];
		location = (NSInteger)NSMaxRange(range);
		if (location <= (NSInteger)range.location) {
			break;
		}
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
