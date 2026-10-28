#import "Encoding.h"
#import "NppMacPlugin.h"

#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#import "ILexer.h"
#import "LangCatalog.h"
#import "Lexilla.h"
#import "Scintilla.h"
#import "ScintillaView.h"
#import "DocumentTab.h"
#import "EditorActions.h"
#import "EditorSettings.h"
#import "SciLexer.h"
#import "Search.h"
#import "ClipboardHistory.h"
#import "OutlineIndex.h"
#import "PreviewHTML.h"
#import "SnippetStore.h"
#import "StyleTheme.h"
#import "UserLanguages.h"
#import "Localization.h"
#import "TextTools.h"
#import "OfficeOpen.h"
#import <zlib.h>

#include <stdio.h>
#include <string.h>

static int g_failed = 0;

static void Expect(bool condition, const char *message) {
	if (!condition) {
		fprintf(stderr, "FAIL %s\n", message);
		g_failed++;
	} else {
		printf("ok %s\n", message);
	}
}

static void TestEncoding(void) {
	const uint8_t bom[] = {0xEF, 0xBB, 0xBF, 'A'};
	DecodedBuffer decoded = DecodeBuffer(bom, sizeof bom);
	Expect(decoded.encoding == kEncodingUTF8BOM && decoded.utf8 == "A", "utf-8 bom");

	const uint8_t utf16[] = {0xFF, 0xFE, 'A', 0x00};
	decoded = DecodeBuffer(utf16, sizeof utf16);
	Expect(decoded.encoding == kEncodingUTF16LE && decoded.utf8 == "A", "utf-16 le");

	const uint8_t crlf[] = {'a', '\r', '\n', 'b'};
	decoded = DecodeBuffer(crlf, sizeof crlf);
	Expect(decoded.eolMode == SC_EOL_CRLF, "crlf");

	const uint8_t cr[] = {'a', '\r', 'b'};
	decoded = DecodeBuffer(cr, sizeof cr);
	Expect(decoded.eolMode == SC_EOL_CR, "cr");

	const uint8_t bad[] = {0x80};
	decoded = DecodeBuffer(bad, sizeof bad);
	Expect(decoded.encoding == kEncodingWindows1252, "windows-1252 fallback");
	Expect(decoded.utf8.size() > 0, "windows-1252 produced text");

	std::string encoded;
	std::string error;
	Expect(EncodeBuffer("hi", kEncodingUTF8BOM, &encoded, &error) && encoded.size() == 5 && (unsigned char)encoded[0] == 0xEF, "utf-8 bom roundtrip");
	Expect(EncodeBuffer(std::string("A\0B", 3), kEncodingUTF16LE, &encoded, &error) && encoded.size() >= 4 && (unsigned char)encoded[0] == 0xFF, "utf-16 encode");
	Expect(NppEncodingCount() >= 50, "notepad++ encoding catalogue");
	Expect(EncodeBuffer("\xC3\xA9", kEncodingWindows1252, &encoded, &error) && encoded.size() == 1 && (unsigned char)encoded[0] == 0xE9, "windows-1252 e acute");
	int greek = NppEncodingIdNamed("ISO 8859-7");
	const uint8_t greekByte[] = {0xE1};
	DecodedBuffer greekText;
	Expect(greek > 0 && DecodeBufferAs(greekByte, 1, (NppTextEncoding)greek, &greekText, &error) && greekText.utf8 == "\xCE\xB1", "iso-8859-7 decode");
	Expect(EncodeBuffer("\xCE\xB1", (NppTextEncoding)greek, &encoded, &error) && encoded.size() == 1 && (unsigned char)encoded[0] == 0xE1, "iso-8859-7 encode");
	int shiftJis = NppEncodingIdNamed("Shift-JIS");
	Expect(shiftJis > 0 && EncodeBuffer("\xE6\x97\xA5", (NppTextEncoding)shiftJis, &encoded, &error) && encoded.size() == 2 && (unsigned char)encoded[0] == 0x93, "shift-jis encode");
	Expect(NppEncodingIdNamed("OEM 720") < 0, "oem 720 is not offered without a converter");
}

static void TestCatalog(NSString *path) {
	LangCatalog *catalog = [LangCatalog catalogWithXML:path];
	Expect(catalog != nil, "langs.model.xml loaded");
	LangInfo *cpp = [catalog languageForPath:@"/tmp/main.cpp"];
	Expect([cpp.lexer isEqualToString:@"cpp"], "cpp lexer from extension");
	LangInfo *html = [catalog languageForPath:@"/tmp/index.html"];
	Expect([html.lexer isEqualToString:@"hypertext"], "html uses hypertext lexer");
	LangInfo *python = [catalog languageNamed:@"python"];
	Expect(python.keywords[@"instre1"].length > 0, "python keywords from langs.model.xml");
	Expect(CreateLexer("cpp") != nullptr, "lexilla cpp");
	Expect(CreateLexer("python") != nullptr, "lexilla python");
	Expect(GetLexerCount() > 50, "lexilla catalogue");
}

static void TestEditor(void) {
	ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
	Expect(editor != nil, "scintilla view");
	[editor message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];
	ILexer5 *lexer = CreateLexer("cpp");
	[editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
	[editor setLexerProperty:@"fold" value:@"1"];
	[editor setString:@"int main() {\n\treturn 0;\n}\n"];
	[editor message:SCI_COLOURISE wParam:0 lParam:-1];
	long level = [editor message:SCI_GETFOLDLEVEL wParam:0 lParam:0];
	Expect((level & SC_FOLDLEVELHEADERFLAG) != 0, "fold header on main");

	DocumentTab *jsonTab = [[DocumentTab alloc] initWithFrame:NSMakeRect(0, 0, 400, 200)];
	long foldFlags = [jsonTab.editor message:SCI_GETAUTOMATICFOLD wParam:0 lParam:0];
	Expect((foldFlags & SC_AUTOMATICFOLD_CLICK) != 0, "fold margin click");
	LangInfo *json = [LangInfo new];
	json.name = @"json";
	json.lexer = @"json";
	[jsonTab applyLanguage:json dark:NO];
	[jsonTab setUtf8Text:@"{\n\t\"a\": 1\n}\n"];
	long jsonLevel = [jsonTab.editor message:SCI_GETFOLDLEVEL wParam:0 lParam:0];
	Expect((jsonLevel & SC_FOLDLEVELHEADERFLAG) != 0, "json object fold header");
	[jsonTab.editor message:SCI_TOGGLEFOLD wParam:0 lParam:0];
	Expect([jsonTab.editor message:SCI_GETLINEVISIBLE wParam:1 lParam:0] == 0, "json fold hides the next line");

	SearchFlags flags = {};
	flags.matchCase = true;
	[editor setString:@"alpha beta alpha"];
	long found = NppFind(editor, @"beta", true, true, flags);
	Expect(found == 6, "literal find");

	flags.regex = true;
	flags.matchCase = false;
	[editor setString:@"cat cot cut"];
	found = NppFind(editor, @"c.t", true, false, flags);
	Expect(found == 0, "posix regex find");

	[editor setString:@"foo 123 bar"];
	found = NppFind(editor, @"[0-9]+", true, false, flags);
	Expect(found == 4, "posix digit class");

	flags.regex = false;
	flags.matchCase = true;
	[editor setString:@"a a a"];
	long count = NppReplaceAll(editor, @"a", @"b", flags);
	NSString *replaced = [editor string];
	Expect(count == 3 && [replaced isEqualToString:@"b b b"], "replace all");
}

static void TestFindInFiles(void) {
	NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-find-in-files"];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtPath:root error:nil];
	NSString *nested = [root stringByAppendingPathComponent:@"sub"];
	[files createDirectoryAtPath:nested withIntermediateDirectories:YES attributes:nil error:nil];
	[@"alpha\nbeta tail\n" writeToFile:[root stringByAppendingPathComponent:@"one.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[@"nope\n" writeToFile:[root stringByAppendingPathComponent:@"skip.cpp"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[@"tail end\n" writeToFile:[nested stringByAppendingPathComponent:@"two.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	SearchFlags flags = {};
	NSArray<NppFindHit *> *hits = NppFindInFiles(root, @"tail", @"*.txt", YES, flags, 100);
	Expect(hits.count == 2, "find in files hits");
	NppFindHit *one = nil;
	for (NppFindHit *hit in hits) {
		if ([hit.path.lastPathComponent isEqualToString:@"one.txt"]) {
			one = hit;
		}
	}
	Expect(one.line == 2, "find in files line");
	NSArray<NppFindHit *> *top = NppFindInFiles(root, @"tail", @"*.txt", NO, flags, 100);
	Expect(top.count == 1, "find in files skips subfolders");
}

static void TestLiveFind(void) {
	NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-live-find"];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtPath:root error:nil];
	[files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
	[@"alpha\nbeta tail\n" writeToFile:[root stringByAppendingPathComponent:@"one.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[@"tail end\n" writeToFile:[root stringByAppendingPathComponent:@"two.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	SearchFlags flags = {};
	__block BOOL done = NO;
	__block NSInteger liveHits = 0;
	__block BOOL cancelled = NO;
	NppFindScanToken *token = NppStartFindInFiles(root, @"tail", @"*.txt", YES, flags, 100, ^(NppFindScan *scan) {
		liveHits += (NSInteger)scan.hits.count;
		if (scan.finished) {
			done = YES;
			cancelled = scan.cancelled;
		}
	});
	NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:5];
	while (!done && [deadline timeIntervalSinceNow] > 0) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
	Expect(done && liveHits == 2 && !cancelled, "live find in files");
	(void)token;
	done = NO;
	cancelled = NO;
	token = NppStartFindInFiles(root, @"tail", @"*.txt", YES, flags, 100, ^(NppFindScan *scan) {
		if (scan.finished) {
			done = YES;
			cancelled = scan.cancelled;
		}
	});
	[token cancel];
	deadline = [NSDate dateWithTimeIntervalSinceNow:5];
	while (!done && [deadline timeIntervalSinceNow] > 0) {
		[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
	}
	Expect(done && cancelled, "cancel find in files");
	[files removeItemAtPath:root error:nil];
}

static void TestShortcuts(void) {
	NSString *key = nil;
	NSEventModifierFlags flags = 0;
	Expect([EditorSettings parseShortcut:@"cmd+shift+s" key:&key modifiers:&flags], "parse save all");
	Expect([key isEqualToString:@"S"] && flags == NSEventModifierFlagCommand, "shift letter shortcut");
	Expect([EditorSettings parseShortcut:@"cmd+f" key:&key modifiers:&flags], "parse find");
	Expect([key isEqualToString:@"f"] && flags == NSEventModifierFlagCommand, "find shortcut");
	Expect([EditorSettings parseShortcut:@"f3" key:&key modifiers:&flags], "parse f3");
	unichar f3 = NSF3FunctionKey;
	Expect(key.length == 1 && [key characterAtIndex:0] == f3 && flags == 0, "f3 key");
	Expect([EditorSettings parseShortcut:@"ctrl+q" key:&key modifiers:&flags], "parse comment");
	Expect([key isEqualToString:@"q"] && flags == NSEventModifierFlagControl, "comment shortcut");
}

static void TestLanguages(NSString *path) {
	LangCatalog *catalog = [LangCatalog catalogWithXML:path];
	LangInfo *json = [catalog languageForPath:@"/tmp/data.json" sample:nil];
	Expect([json.lexer isEqualToString:@"json"], "json extension");
	LangInfo *javascript = [catalog languageForPath:@"/tmp/app.js" sample:nil];
	Expect([javascript.name isEqualToString:@"javascript.js"] && [javascript.lexer isEqualToString:@"cpp"], "javascript extension");
	Expect([[catalog languageForPath:@"/tmp/main.py" sample:nil].lexer isEqualToString:@"python"], "python extension");
	Expect([[catalog languageForPath:@"/tmp/lib.rs" sample:nil].lexer isEqualToString:@"rust"], "rust extension");
	LangInfo *go = [catalog languageForPath:@"/tmp/main.go" sample:nil];
	Expect([go.name isEqualToString:@"go"] && [go.lexer isEqualToString:@"cpp"], "go extension");
	Expect([[catalog languageForPath:@"/tmp/app.ts" sample:nil].name isEqualToString:@"typescript"], "typescript extension");
	LangInfo *sniffed = [catalog languageForPath:@"/tmp/notes.txt" sample:@"{\n  \"ok\": true\n}\n"];
	Expect([sniffed.lexer isEqualToString:@"json"], "json sniffed from text");
	LangInfo *shebang = [catalog languageForPath:@"/tmp/script" sample:@"#!/usr/bin/env python3\nprint(1)\n"];
	Expect([shebang.name isEqualToString:@"python"], "python shebang");
}

static void TestJSONStyle(NSString *path) {
	NSString *stylers = [[path stringByDeletingLastPathComponent] stringByAppendingPathComponent:@"stylers.model.xml"];
	StyleTheme *theme = [StyleTheme themeWithXML:stylers];
	Expect(theme != nil, "stylers.model.xml loaded");
	ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 240, 80)];
	[editor message:SCI_SETCODEPAGE wParam:SC_CP_UTF8 lParam:0];
	ILexer5 *lexer = CreateLexer("json");
	Expect(lexer != nullptr, "lexilla json");
	[editor setReferenceProperty:SCI_SETILEXER parameter:0 value:lexer];
	[editor setLexerProperty:@"lexer.json.escape.sequence" value:@"1"];
	[editor setReferenceProperty:SCI_SETKEYWORDS parameter:0 value:"false null true"];
	[theme applyToEditor:editor language:@"json" dark:NO];
	[editor setString:@"{\"name\": true}\n"];
	[editor message:SCI_COLOURISE wParam:0 lParam:-1];
	long style = [editor message:SCI_GETSTYLEAT wParam:2 lParam:0];
	Expect(style == SCE_JSON_PROPERTYNAME, "json property style");
	long color = [editor message:SCI_STYLEGETFORE wParam:SCE_JSON_PROPERTYNAME lParam:0];
	Expect((color & 0xFFFFFF) == 0xFF0080, "json property color");
	long word = [editor message:SCI_GETSTYLEAT wParam:9 lParam:0];
	Expect(word == SCE_JSON_KEYWORD, "json keyword style");
}

static void TestReplace(void) {
	ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 200, 80)];
	[editor setString:@"alpha beta alpha"];
	[editor message:SCI_SETSEL wParam:0 lParam:5];
	SearchFlags flags = {};
	flags.matchCase = true;
	long replaced = NppReplace(editor, @"alpha", @"A", true, flags);
	Expect(replaced >= 0 && [[editor string] isEqualToString:@"A beta alpha"], "replace current match");
	long count = NppReplaceAll(editor, @"a", @"", flags);
	Expect(count == 3 && [[editor string] isEqualToString:@"A bet lph"], "replace all empty");
	[editor setString:@"aa"];
	count = NppReplaceAll(editor, @"a", @"", flags);
	Expect(count == 2 && [[editor string] isEqualToString:@""], "replace all removes every match");

	NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-replace-in-files"];
	NSFileManager *files = [NSFileManager defaultManager];
	[files removeItemAtPath:root error:nil];
	[files createDirectoryAtPath:root withIntermediateDirectories:YES attributes:nil error:nil];
	[@"tail\n" writeToFile:[root stringByAppendingPathComponent:@"one.txt"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	[@"tail\n" writeToFile:[root stringByAppendingPathComponent:@"skip.cpp"] atomically:YES encoding:NSUTF8StringEncoding error:nil];
	NppReplaceFilesResult *result = NppReplaceInFiles(root, @"tail", @"head", @"*.txt", NO, flags, nil);
	Expect(result.replacements == 1 && result.filesChanged == 1, "replace in files count");
	NSString *updated = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"one.txt"] encoding:NSUTF8StringEncoding error:nil];
	NSString *untouched = [NSString stringWithContentsOfFile:[root stringByAppendingPathComponent:@"skip.cpp"] encoding:NSUTF8StringEncoding error:nil];
	Expect([updated isEqualToString:@"head\n"] && [untouched isEqualToString:@"tail\n"], "replace in files contents");
}

static void TestEditorActions(void) {
	ScintillaView *editor = [[ScintillaView alloc] initWithFrame:NSMakeRect(0, 0, 200, 80)];
	[editor setString:@"b\na\na"];
	NppRunEditorAction(editor, @"sortAsc", @"cpp");
	Expect([[editor string] isEqualToString:@"a\na\nb"], "sort lines");
	[editor setString:@"beta"];
	[editor message:SCI_SELECTALL];
	NppRunEditorAction(editor, @"upper", @"cpp");
	Expect([[editor string] isEqualToString:@"BETA"], "uppercase");
}

static char g_pluginText[4096];

static int PluginGet(NppMacHost *host, char *buffer, int bufferLength) {
	(void)host;
	int length = (int)strlen(g_pluginText);
	if (!buffer || bufferLength <= 0) {
		return length;
	}
	int count = length < bufferLength - 1 ? length : bufferLength - 1;
	memcpy(buffer, g_pluginText, (size_t)count);
	buffer[count] = 0;
	return count;
}

static void PluginSet(NppMacHost *host, const char *utf8) {
	(void)host;
	snprintf(g_pluginText, sizeof g_pluginText, "%s", utf8 ?: "");
}

static void RunPlugin(const char *file, const char *command, const char *input, const char *expected) {
	void *handle = dlopen(file, RTLD_NOW);
	Expect(handle != nullptr, file);
	if (!handle) {
		return;
	}
	NppMacPluginEntryFn entry = (NppMacPluginEntryFn)dlsym(handle, "NppMacPluginEntry");
	const NppMacPlugin *plugin = entry ? entry() : nullptr;
	Expect(plugin && plugin->abi == NPP_MAC_PLUGIN_ABI, "plugin abi");
	if (!plugin) {
		dlclose(handle);
		return;
	}
	NppMacHost host = {};
	host.abi = NPP_MAC_PLUGIN_ABI;
	host.get_selection = PluginGet;
	host.replace_selection = PluginSet;
	host.get_text = PluginGet;
	host.set_text = PluginSet;
	host.set_status = [](NppMacHost *, const char *) {};
	const NppMacCommand *commands = nullptr;
	int count = 0;
	plugin->on_load(&host, &commands, &count);
	snprintf(g_pluginText, sizeof g_pluginText, "%s", input);
	BOOL ran = NO;
	for (int index = 0; index < count; index++) {
		if (strcmp(commands[index].title, command) == 0) {
			commands[index].perform(&host, commands[index].user);
			ran = YES;
		}
	}
	Expect(ran && strcmp(g_pluginText, expected) == 0, command);
	dlclose(handle);
}

static void TestFeatures(void) {
	NSArray<NppSymbol *> *python = NppOutlineSymbols(@"python", @"python", @"def ready():\n    return 1\n\nclass Box:\n    pass\n");
	Expect(python.count >= 2 && [python[0].name isEqualToString:@"ready"] && python[0].line == 1, "outline python def");
	NSArray<NppSymbol *> *json = NppOutlineSymbols(@"json", @"json", @"{\n  \"name\": \"Simeiomatarion\"\n}\n");
	Expect(json.count == 1 && [json[0].name isEqualToString:@"name"] && json[0].line == 2, "outline json key");
	NSArray<NppSymbol *> *markdown = NppOutlineSymbols(@"markdown", @"markdown", @"# Title\n\ntext\n");
	Expect(markdown.count == 1 && [markdown[0].name isEqualToString:@"Title"], "outline markdown heading");

	NSString *html = NppPreviewHTML(@"# Hello\n\n- one\n", @"markdown", @"markdown", NO);
	Expect([html containsString:@"<h1>Hello</h1>"] && [html containsString:@"<li>one</li>"], "markdown preview");
	NSString *page = NppPreviewHTML(@"<p>Hi</p>", @"html", @"hypertext", NO);
	Expect([page containsString:@"<p>Hi</p>"] && [page containsString:@"<body>"], "html preview wrap");

	NppSnippetStore *snippets = [NppSnippetStore loadFromURL:[NSURL fileURLWithPath:@"/tmp/proheiro-missing-snippets.json"]];
	Expect([[snippets bodyForName:@"todo"] isEqualToString:@"TODO: "], "default snippet");

	NppUserLanguage *language = [NppUserLanguage new];
	language.name = @"Widget";
	language.extensions = @".wlang, widget";
	language.keywords = @"alpha beta";
	language.lexer = @"cpp";
	NppUserLanguageStore *store = [NppUserLanguageStore new];
	store.languages = [@[language] mutableCopy];
	Expect([store languageForPath:@"/tmp/note.wlang"] == language, "user language extension");
	Expect([[store langInfoNamed:@"Widget"].keywords[@"instre1"] isEqualToString:@"alpha beta"], "user language keywords");

	NppClipboardHistory *clips = [NppClipboardHistory new];
	[clips remember:@"one"];
	[clips remember:@"one"];
	[clips remember:@"two"];
	Expect(clips.items.count == 2 && [clips.items[0] isEqualToString:@"two"], "clipboard history order");

	DocumentTab *shared = [[DocumentTab alloc] initWithFrame:NSMakeRect(0, 0, 200, 100)];
	[shared setUtf8Text:@"same buffer"];
	ScintillaView *mirror = [shared mirrorView];
	Expect([[shared utf8Text] isEqualToString:@"same buffer"], "clone keeps the original text");
	[mirror message:SCI_APPENDTEXT wParam:2 lParam:(sptr_t)"!\n"];
	Expect([[shared utf8Text] containsString:@"same buffer!"], "clone shares the buffer");
	[shared discardMirror];
}

static void TestToolsAndLanguage(void) {
	Expect([NppFormatByteCount(0, @"auto") isEqualToString:@"0.0 KB"], "zero bytes stay in KB");
	Expect([NppFormatByteCount(1536, @"auto") isEqualToString:@"1.5 KB"], "size uses KB below one megabyte");
	Expect([NppFormatByteCount(2ull * 1024ull * 1024ull, @"auto") isEqualToString:@"2.00 MB"], "size uses MB from one megabyte");
	Expect([NppFormatByteCount(2ull * 1024ull * 1024ull, @"kb") isEqualToString:@"2048 KB"], "KB unit stays in KB");
	Expect([NppFormatByteCount(512, @"mb") hasSuffix:@" MB"], "MB unit stays in MB");
	NSString *prettyJSON = NppPrettyJSON(@"{\"b\":1}", nil);
	Expect([prettyJSON containsString:@"\n"] && [prettyJSON containsString:@"\"b\""], "pretty JSON");
	NSString *prettyXML = NppPrettyXML(@"<a><b/></a>", nil);
	Expect([prettyXML containsString:@"\n"] && [prettyXML containsString:@"<b"], "pretty XML");
	NppSetUILanguage(@"en");
	Expect([NppL(@"File") isEqualToString:@"File"], "English UI");
	NppSetUILanguage(@"el");
	Expect([NppL(@"File") isEqualToString:@"Αρχείο"], "Greek UI");
	NppSetUILanguage(@"en");
	NSString *settingsPath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"simeiomatarion-settings-test.json"];
	[[NSFileManager defaultManager] removeItemAtPath:settingsPath error:nil];
	EditorSettings *fresh = [EditorSettings loadFromURL:[NSURL fileURLWithPath:settingsPath]];
	Expect(fresh.autoClose && fresh.showFileSize && fresh.formatDocuments && [fresh.fileSizeUnit isEqualToString:@"auto"], "new features default on");
	fresh.autoClose = NO;
	fresh.uiLanguage = @"el";
	fresh.fileSizeUnit = @"mb";
	NSError *error = nil;
	Expect([fresh saveToURL:[NSURL fileURLWithPath:settingsPath] error:&error], "settings save");
	EditorSettings *loaded = [EditorSettings loadFromURL:[NSURL fileURLWithPath:settingsPath]];
	Expect(!loaded.autoClose && [loaded.uiLanguage isEqualToString:@"el"] && [loaded.fileSizeUnit isEqualToString:@"mb"], "settings round trip");
	[loaded rememberSearch:@"alpha"];
	[loaded rememberSearch:@"beta"];
	[loaded rememberSearch:@"alpha"];
	Expect(loaded.searchHistory.count == 2 && [loaded.searchHistory[0] isEqualToString:@"alpha"], "search history");
	[[NSFileManager defaultManager] removeItemAtPath:settingsPath error:nil];
}

static void TestPlugins(void) {
	NSString *directory = @"build/Simeiomatarion.app/Contents/PlugIns";
	RunPlugin([directory stringByAppendingPathComponent:@"MimeTools.dylib"].UTF8String, "Base64 Encode", "hi", "aGk=");
	RunPlugin([directory stringByAppendingPathComponent:@"MimeTools.dylib"].UTF8String, "URL Encode", "a b", "a%20b");
	RunPlugin([directory stringByAppendingPathComponent:@"Converter.dylib"].UTF8String, "ASCII to HEX", "AB", "41 42");
	RunPlugin([directory stringByAppendingPathComponent:@"JsonTools.dylib"].UTF8String, "Format JSON", "{\"b\":1,\"a\":[2]}", "{\n\t\"b\": 1,\n\t\"a\": [\n\t\t2\n\t]\n}\n");
}

static void TestZipU16(NSMutableData *data, uint16_t value) {
	uint8_t bytes[2] = {(uint8_t)value, (uint8_t)(value >> 8)};
	[data appendBytes:bytes length:2];
}

static void TestZipU32(NSMutableData *data, uint32_t value) {
	uint8_t bytes[4] = {(uint8_t)value, (uint8_t)(value >> 8), (uint8_t)(value >> 16), (uint8_t)(value >> 24)};
	[data appendBytes:bytes length:4];
}

static NSData *TestDeflate(NSData *input) {
	z_stream stream;
	memset(&stream, 0, sizeof(stream));
	if (deflateInit2(&stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, -MAX_WBITS, 8, Z_DEFAULT_STRATEGY) != Z_OK) {
		return nil;
	}
	NSMutableData *output = [NSMutableData dataWithLength:deflateBound(&stream, (uLong)input.length) + 16];
	stream.next_in = (Bytef *)input.bytes;
	stream.avail_in = (uInt)input.length;
	stream.next_out = (Bytef *)output.mutableBytes;
	stream.avail_out = (uInt)output.length;
	int status = deflate(&stream, Z_FINISH);
	deflateEnd(&stream);
	if (status != Z_STREAM_END) {
		return nil;
	}
	output.length = stream.total_out;
	return output;
}

static BOOL TestWriteXlsx(NSString *path) {
	NSDictionary<NSString *, NSString *> *files = @{
		@"xl/workbook.xml": @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><workbook xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\" xmlns:r=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships\"><sheets><sheet name=\"Data\" sheetId=\"1\" r:id=\"rId1\"/></sheets></workbook>",
		@"xl/_rels/workbook.xml.rels": @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\"><Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet\" Target=\"worksheets/sheet1.xml\"/></Relationships>",
		@"xl/sharedStrings.xml": @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><sst xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><si><t>Name</t></si><si><t>City</t></si><si><t>Ann</t></si><si><t>Athens</t></si></sst>",
		@"xl/worksheets/sheet1.xml": @"<?xml version=\"1.0\" encoding=\"UTF-8\"?><worksheet xmlns=\"http://schemas.openxmlformats.org/spreadsheetml/2006/main\"><sheetData><row r=\"1\"><c r=\"A1\" t=\"s\"><v>0</v></c><c r=\"B1\" t=\"s\"><v>1</v></c></row><row r=\"2\"><c r=\"A2\" t=\"s\"><v>2</v></c><c r=\"B2\" t=\"s\"><v>3</v></c><c r=\"C2\"><v>3</v></c></row></sheetData></worksheet>",
	};
	NSArray<NSString *> *names = @[@"xl/workbook.xml", @"xl/_rels/workbook.xml.rels", @"xl/sharedStrings.xml", @"xl/worksheets/sheet1.xml"];
	NSMutableData *zip = [NSMutableData data];
	NSMutableArray<NSDictionary *> *locals = [NSMutableArray array];
	for (NSString *name in names) {
		NSData *raw = [files[name] dataUsingEncoding:NSUTF8StringEncoding];
		BOOL compressed = [name hasSuffix:@"sharedStrings.xml"];
		NSData *stored = compressed ? TestDeflate(raw) : raw;
		if (!stored) {
			return NO;
		}
		uint32_t checksum = (uint32_t)crc32(0, (const Bytef *)raw.bytes, (uInt)raw.length);
		uint32_t offset = (uint32_t)zip.length;
		TestZipU32(zip, 0x04034b50);
		TestZipU16(zip, 20);
		TestZipU16(zip, 0);
		TestZipU16(zip, compressed ? 8 : 0);
		TestZipU16(zip, 0);
		TestZipU16(zip, 0);
		TestZipU32(zip, checksum);
		TestZipU32(zip, (uint32_t)stored.length);
		TestZipU32(zip, (uint32_t)raw.length);
		TestZipU16(zip, (uint16_t)[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
		TestZipU16(zip, 0);
		[zip appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
		[zip appendData:stored];
		[locals addObject:@{@"name": name, @"offset": @(offset), @"method": @(compressed ? 8 : 0), @"crc": @(checksum), @"comp": @(stored.length), @"raw": @(raw.length)}];
	}
	uint32_t directoryOffset = (uint32_t)zip.length;
	for (NSDictionary *entry in locals) {
		NSString *name = entry[@"name"];
		TestZipU32(zip, 0x02014b50);
		TestZipU16(zip, 20);
		TestZipU16(zip, 20);
		TestZipU16(zip, 0);
		TestZipU16(zip, (uint16_t)[entry[@"method"] unsignedShortValue]);
		TestZipU16(zip, 0);
		TestZipU16(zip, 0);
		TestZipU32(zip, [entry[@"crc"] unsignedIntValue]);
		TestZipU32(zip, [entry[@"comp"] unsignedIntValue]);
		TestZipU32(zip, [entry[@"raw"] unsignedIntValue]);
		TestZipU16(zip, (uint16_t)[name lengthOfBytesUsingEncoding:NSUTF8StringEncoding]);
		TestZipU16(zip, 0);
		TestZipU16(zip, 0);
		TestZipU16(zip, 0);
		TestZipU16(zip, 0);
		TestZipU32(zip, 0);
		TestZipU32(zip, [entry[@"offset"] unsignedIntValue]);
		[zip appendData:[name dataUsingEncoding:NSUTF8StringEncoding]];
	}
	uint32_t directorySize = (uint32_t)zip.length - directoryOffset;
	TestZipU32(zip, 0x06054b50);
	TestZipU16(zip, 0);
	TestZipU16(zip, 0);
	TestZipU16(zip, (uint16_t)locals.count);
	TestZipU16(zip, (uint16_t)locals.count);
	TestZipU32(zip, directorySize);
	TestZipU32(zip, directoryOffset);
	TestZipU16(zip, 0);
	return [zip writeToFile:path atomically:YES];
}

static void TestOfficeFiles(void) {
	Expect(NppOfficeKindForPath(@"/tmp/a.csv") == NppOfficeKindCSV, "csv kind");
	Expect(NppOfficeKindForPath(@"/tmp/a.PDF") == NppOfficeKindPDF, "pdf kind");
	Expect(NppOfficeKindForPath(@"/tmp/a.docx") == NppOfficeKindDOCX, "docx kind");
	Expect(NppOfficeKindIsViewOnly(NppOfficeKindDOC) && !NppOfficeKindIsViewOnly(NppOfficeKindCSV), "word is view only");
	unichar delimiter = 0;
	NSArray *rows = NppParseCSV(@"name,city\n\"Doe, Ann\",\"Athens\"\n", &delimiter);
	Expect(delimiter == ',', "comma delimiter");
	Expect(rows.count == 2, "two csv rows");
	Expect([rows[1][0] isEqualToString:@"Doe, Ann"] && [rows[1][1] isEqualToString:@"Athens"], "quoted comma");
	rows = NppParseCSV(@"a;b\n1;2\n", &delimiter);
	Expect(delimiter == ';', "semicolon delimiter");
	NSString *written = NppFormatCSV(rows, delimiter);
	unichar again = 0;
	NSArray *round = NppParseCSV(written, &again);
	Expect(again == ';' && round.count == 2 && [round[0][0] isEqualToString:@"a"] && [round[1][1] isEqualToString:@"2"], "csv round trip");
	rows = NppParseCSV(@"\"say \"\"hi\"\"\"\n", &delimiter);
	Expect([rows[0][0] isEqualToString:@"say \"hi\""], "doubled quotes");
	rows = NppParseCSV(@"a|b|c\n1|2|3\n", &delimiter);
	Expect(delimiter == '|' && rows.count == 2 && [rows[0][2] isEqualToString:@"c"], "pipe delimiter");
	rows = NppParseCSV(@"name^city\nAnn^Athens\n", &delimiter);
	Expect(delimiter == '^' && [rows[1][1] isEqualToString:@"Athens"], "caret delimiter");
	rows = NppParseCSV(@"time,value\n12:30,1\n", &delimiter);
	Expect(delimiter == ',' && [rows[1][0] isEqualToString:@"12:30"], "colon stays inside a comma field");
	NSArray *filtered = @[@[@"Ann", @"Athens"], @[@"Bob", @"Rome"], @[@"Ann", @"Rome"]];
	NSIndexSet *kept = NppTableFilterIndexes(filtered, @{@0: [NSSet setWithObject:@"Ann"], @1: [NSSet setWithObject:@"Rome"]});
	Expect(kept.count == 1 && [kept containsIndex:2], "column filters combine");
	Expect(NppOfficeKindForPath(@"/tmp/a.xlsx") == NppOfficeKindXLSX, "xlsx kind");
	Expect(NppOfficeKindIsViewOnly(NppOfficeKindXLSX), "xlsx is view only");
	NSString *xlsx = [NSTemporaryDirectory() stringByAppendingPathComponent:@"npp-sample.xlsx"];
	Expect(TestWriteXlsx(xlsx), "write sample xlsx");
	NSArray<NSString *> *sheets = nil;
	NSArray *sheetRows = nil;
	BOOL truncated = NO;
	NSString *xlsxError = nil;
	Expect(NppXlsxLoad(xlsx, nil, &sheets, &sheetRows, &truncated, &xlsxError), "xlsx opens");
	Expect(sheets.count == 1 && [sheets.firstObject isEqualToString:@"Data"], "xlsx sheet name");
	Expect(sheetRows.count == 2 && [sheetRows[0][0] isEqualToString:@"Name"] && [sheetRows[1][1] isEqualToString:@"Athens"] && [sheetRows[1][2] isEqualToString:@"3"], "xlsx cells");
	[[NSFileManager defaultManager] removeItemAtPath:xlsx error:nil];
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		[application setActivationPolicy:NSApplicationActivationPolicyProhibited];
		TestEncoding();
		TestOfficeFiles();
		TestLiveFind();
		if (argc > 1) {
			TestCatalog(@(argv[1]));
		} else {
			Expect(false, "catalog path argument");
		}
		TestEditor();
		TestFindInFiles();
		TestEditorActions();
		TestReplace();
		TestShortcuts();
		TestFeatures();
		TestToolsAndLanguage();
		TestPlugins();
		if (argc > 1) {
			TestLanguages(@(argv[1]));
			TestJSONStyle(@(argv[1]));
		}
	}
	printf("%s (%d failed)\n", g_failed ? "FAILED" : "PASSED", g_failed);
	return g_failed ? 1 : 0;
}
