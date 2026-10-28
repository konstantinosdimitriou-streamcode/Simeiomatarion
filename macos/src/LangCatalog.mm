#import "LangCatalog.h"

// Language name -> Lexilla lexer id, taken from
// PowerEditor/src/ScintillaComponent/ScintillaEditView.cpp in the upstream tree (see NOTICE).
static const char *kLangLexerPairs[][2] = {
	{"normal", "null"}, {"php", "phpscript"}, {"c", "cpp"}, {"cpp", "cpp"}, {"cs", "cpp"},
	{"objc", "objc"}, {"java", "cpp"}, {"rc", "cpp"}, {"html", "hypertext"}, {"xml", "xml"},
	{"makefile", "makefile"}, {"pascal", "pascal"}, {"batch", "batch"}, {"ini", "props"},
	{"nfo", "null"}, {"udf", "user"}, {"asp", "hypertext"}, {"sql", "sql"}, {"vb", "vb"},
	{"javascript", "cpp"}, {"css", "css"}, {"perl", "perl"}, {"python", "python"},
	{"lua", "lua"}, {"tex", "tex"}, {"fortran", "fortran"}, {"bash", "bash"},
	{"actionscript", "cpp"}, {"nsis", "nsis"}, {"tcl", "tcl"}, {"lisp", "lisp"},
	{"scheme", "lisp"}, {"asm", "asm"}, {"diff", "diff"}, {"props", "props"},
	{"postscript", "ps"}, {"ruby", "ruby"}, {"smalltalk", "smalltalk"}, {"vhdl", "vhdl"},
	{"kix", "kix"}, {"autoit", "au3"}, {"caml", "caml"}, {"ada", "ada"},
	{"verilog", "verilog"}, {"matlab", "matlab"}, {"haskell", "haskell"}, {"inno", "inno"},
	{"searchResult", "searchResult"}, {"cmake", "cmake"}, {"yaml", "yaml"},
	{"cobol", "COBOL"}, {"gui4cli", "gui4cli"}, {"d", "d"}, {"powershell", "powershell"},
	{"r", "r"}, {"jsp", "hypertext"}, {"coffeescript", "coffeescript"}, {"json", "json"},
	{"javascript.js", "cpp"}, {"fortran77", "f77"}, {"baanc", "baan"}, {"srec", "srec"},
	{"ihex", "ihex"}, {"tehex", "tehex"}, {"swift", "cpp"}, {"asn1", "asn1"},
	{"avs", "avs"}, {"blitzbasic", "blitzbasic"}, {"purebasic", "purebasic"},
	{"freebasic", "freebasic"}, {"csound", "csound"}, {"erlang", "erlang"},
	{"escript", "escript"}, {"forth", "forth"}, {"latex", "latex"}, {"mmixal", "mmixal"},
	{"nim", "nimrod"}, {"nncrontab", "nncrontab"}, {"oscript", "oscript"},
	{"rebol", "rebol"}, {"registry", "registry"}, {"rust", "rust"}, {"spice", "spice"},
	{"txt2tags", "txt2tags"}, {"visualprolog", "visualprolog"}, {"typescript", "cpp"},
	{"json5", "json"}, {"mssql", "mssql"}, {"gdscript", "gdscript"},
	{"hollywood", "hollywood"}, {"go", "cpp"}, {"raku", "raku"}, {"toml", "toml"},
	{"sas", "sas"}, {"errorlist", "errorlist"}, {"escseq", "escseq"}, {"ext", "null"},
	{"markdown", "markdown"}, {"zig", "zig"}
};

static NSString *LexerForLanguage(NSString *name) {
	if (name.length == 0) {
		return @"null";
	}
	for (size_t index = 0; index < sizeof kLangLexerPairs / sizeof kLangLexerPairs[0]; index++) {
		if ([name isEqualToString:@(kLangLexerPairs[index][0])]) {
			return @(kLangLexerPairs[index][1]);
		}
	}
	return name;
}

@implementation LangInfo
@end

@implementation LangCatalog {
	NSArray<LangInfo *> *_languages;
	NSDictionary<NSString *, LangInfo *> *_byName;
	NSDictionary<NSString *, LangInfo *> *_byExtension;
}

+ (instancetype)catalogWithXML:(NSString *)path {
	NSData *data = [NSData dataWithContentsOfFile:path];
	if (!data) {
		return nil;
	}
	NSError *error = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithData:data options:0 error:&error];
	if (!document) {
		return nil;
	}
	LangCatalog *catalog = [LangCatalog new];
	NSMutableArray<LangInfo *> *languages = [NSMutableArray array];
	NSMutableDictionary<NSString *, LangInfo *> *byName = [NSMutableDictionary dictionary];
	NSMutableDictionary<NSString *, LangInfo *> *byExtension = [NSMutableDictionary dictionary];
	NSArray *nodes = [document nodesForXPath:@"//Language" error:&error];
	for (NSXMLElement *node in nodes) {
		LangInfo *info = [LangInfo new];
		info.name = [[node attributeForName:@"name"] stringValue] ?: @"";
		info.lexer = LexerForLanguage(info.name);
		NSString *ext = [[node attributeForName:@"ext"] stringValue] ?: @"";
		NSMutableArray *extensions = [NSMutableArray array];
		for (NSString *part in [ext componentsSeparatedByCharactersInSet:[NSCharacterSet whitespaceCharacterSet]]) {
			if (part.length) {
				[extensions addObject:part.lowercaseString];
			}
		}
		info.extensions = extensions;
		NSMutableDictionary *keywords = [NSMutableDictionary dictionary];
		for (NSXMLNode *child in node.children) {
			if (![child isKindOfClass:[NSXMLElement class]]) {
				continue;
			}
			NSXMLElement *element = (NSXMLElement *)child;
			if (![element.name isEqualToString:@"Keywords"]) {
				continue;
			}
			NSString *slot = [[element attributeForName:@"name"] stringValue];
			if (slot.length && element.stringValue.length) {
				keywords[slot] = element.stringValue;
			}
		}
		info.keywords = keywords;
		[languages addObject:info];
		if (info.name.length) {
			byName[info.name] = info;
		}
		for (NSString *extension in extensions) {
			if (!byExtension[extension]) {
				byExtension[extension] = info;
			}
		}
	}
	catalog->_languages = languages;
	catalog->_byName = byName;
	catalog->_byExtension = byExtension;
	return catalog;
}

- (LangInfo *)languageNamed:(NSString *)name {
	return _byName[name];
}

- (LangInfo *)languageForPath:(NSString *)path {
	NSString *file = path.lastPathComponent.lowercaseString;
	if ([file isEqualToString:@"makefile"] || [file isEqualToString:@"gnumakefile"]) {
		return [self languageNamed:@"makefile"];
	}
	NSString *extension = path.pathExtension.lowercaseString;
	if (extension.length == 0) {
		return [self languageNamed:@"normal"];
	}
	LangInfo *info = _byExtension[extension];
	if (info) {
		return info;
	}
	if ([extension isEqualToString:@"hpp"] || [extension isEqualToString:@"hh"] || [extension isEqualToString:@"hxx"] || [extension isEqualToString:@"cc"] || [extension isEqualToString:@"cxx"] || [extension isEqualToString:@"mm"]) {
		return [self languageNamed:@"cpp"];
	}
	if ([extension isEqualToString:@"h"]) {
		return [self languageNamed:@"c"];
	}
	if ([extension isEqualToString:@"m"]) {
		return [self languageNamed:@"objc"];
	}
	return [self languageNamed:@"normal"];
}

- (LangInfo *)languageForShebang:(NSString *)line {
	NSString *lower = line.lowercaseString;
	if ([lower containsString:@"python"]) return [self languageNamed:@"python"];
	if ([lower containsString:@"ruby"]) return [self languageNamed:@"ruby"];
	if ([lower containsString:@"perl"]) return [self languageNamed:@"perl"];
	if ([lower containsString:@"node"] || [lower containsString:@"nodejs"]) return [self languageNamed:@"javascript.js"];
	if ([lower containsString:@"php"]) return [self languageNamed:@"php"];
	if ([lower containsString:@"lua"]) return [self languageNamed:@"lua"];
	if ([lower containsString:@"bash"] || [lower containsString:@"zsh"] || [lower containsString:@"sh"]) return [self languageNamed:@"bash"];
	return nil;
}

- (LangInfo *)languageForSample:(NSString *)sample {
	if (sample.length == 0) {
		return nil;
	}
	NSString *head = sample.length > 4096 ? [sample substringToIndex:4096] : sample;
	NSString *trimmed = [head stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if ([trimmed hasPrefix:@"#!"]) {
		NSRange lineEnd = [trimmed rangeOfString:@"\n"];
		NSString *line = lineEnd.location == NSNotFound ? trimmed : [trimmed substringToIndex:lineEnd.location];
		LangInfo *info = [self languageForShebang:line];
		if (info) {
			return info;
		}
	}
	NSString *lower = trimmed.lowercaseString;
	if ([lower hasPrefix:@"<?php"]) {
		return [self languageNamed:@"php"];
	}
	if ([lower hasPrefix:@"<?xml"]) {
		return [self languageNamed:@"xml"];
	}
	if ([lower hasPrefix:@"<!doctype html"] || [lower hasPrefix:@"<html"] || [lower hasPrefix:@"<head"] || [lower hasPrefix:@"<body"]) {
		return [self languageNamed:@"html"];
	}
	BOOL jsonStart = [trimmed hasPrefix:@"{"] || [trimmed hasPrefix:@"["];
	if (jsonStart && [trimmed containsString:@"\""] && ([trimmed containsString:@":"] || [trimmed hasPrefix:@"["])) {
		return [self languageNamed:@"json"];
	}
	return nil;
}

- (LangInfo *)languageForPath:(NSString *)path sample:(NSString *)sample {
	NSString *file = path.lastPathComponent.lowercaseString;
	if ([file isEqualToString:@"cmakelists.txt"]) {
		return [self languageNamed:@"cmake"];
	}
	if ([file isEqualToString:@"dockerfile"]) {
		return [self languageNamed:@"bash"];
	}
	LangInfo *info = path.length ? [self languageForPath:path] : nil;
	if (info && info.name.length && ![info.name isEqualToString:@"normal"] && ![info.lexer isEqualToString:@"null"]) {
		return info;
	}
	LangInfo *sniffed = [self languageForSample:sample];
	return sniffed ?: info ?: [self languageNamed:@"normal"];
}

- (NSArray<LangInfo *> *)allLanguages {
	return _languages;
}

@end
