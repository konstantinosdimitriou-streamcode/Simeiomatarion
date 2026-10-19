#pragma once

#import <Foundation/Foundation.h>
#import "ScintillaView.h"

struct SearchFlags {
	bool matchCase;
	bool wholeWord;
	bool regex;
	bool dotMatchesNewline;
};

long NppSearchFlags(SearchFlags flags);
// Returns the match start, or -1. On success the target range is the match.
long NppFind(ScintillaView *editor, NSString *text, bool forward, bool wrap, SearchFlags flags);
long NppReplace(ScintillaView *editor, NSString *text, NSString *replacement, bool wrap, SearchFlags flags);
long NppReplaceAll(ScintillaView *editor, NSString *text, NSString *replacement, SearchFlags flags);

@interface NppFindHit : NSObject
@property (nonatomic, copy) NSString *path;
@property (nonatomic, assign) NSInteger line;
@property (nonatomic, assign) NSInteger byteOffset;
@property (nonatomic, assign) NSInteger byteLength;
@property (nonatomic, copy) NSString *lineText;
@end

@interface NppReplaceFilesResult : NSObject
@property (nonatomic, assign) NSInteger filesChanged;
@property (nonatomic, assign) NSInteger replacements;
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, copy) NSString *error;
@end

// Directory search used by Notepad++ Find in Files. "*.*" matches every file name.
NSArray<NppFindHit *> *NppFindInFiles(NSString *directory, NSString *query, NSString *filters, BOOL subfolders, SearchFlags flags, NSInteger limit);
// Writes replacements into files on disk and returns the paths that changed.
BOOL NppFileNameMatches(NSString *name, NSString *filters);
NppReplaceFilesResult *NppReplaceInFiles(NSString *directory, NSString *query, NSString *replacement, NSString *filters, BOOL subfolders, SearchFlags flags, NSArray<NSString *> *skipPaths);
