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
#import "StyleTheme.h"

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

static void TestPlugins(void) {
	NSString *directory = @"build/Notepad++.app/Contents/PlugIns";
	RunPlugin([directory stringByAppendingPathComponent:@"MimeTools.dylib"].UTF8String, "Base64 Encode", "hi", "aGk=");
	RunPlugin([directory stringByAppendingPathComponent:@"MimeTools.dylib"].UTF8String, "URL Encode", "a b", "a%20b");
	RunPlugin([directory stringByAppendingPathComponent:@"Converter.dylib"].UTF8String, "ASCII to HEX", "AB", "41 42");
	RunPlugin([directory stringByAppendingPathComponent:@"JsonTools.dylib"].UTF8String, "Format JSON", "{\"b\":1,\"a\":[2]}", "{\n\t\"b\": 1,\n\t\"a\": [\n\t\t2\n\t]\n}\n");
}

int main(int argc, const char *argv[]) {
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		[application setActivationPolicy:NSApplicationActivationPolicyProhibited];
		TestEncoding();
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
		TestPlugins();
		if (argc > 1) {
			TestLanguages(@(argv[1]));
			TestJSONStyle(@(argv[1]));
		}
	}
	printf("%s (%d failed)\n", g_failed ? "FAILED" : "PASSED", g_failed);
	return g_failed ? 1 : 0;
}
