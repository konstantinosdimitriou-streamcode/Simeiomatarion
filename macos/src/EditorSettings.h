#pragma once

#import <AppKit/AppKit.h>

@interface EditorSettings : NSObject
@property (nonatomic, copy) NSString *fontName;
@property (nonatomic, assign) int fontSize;
@property (nonatomic, assign) int tabWidth;
@property (nonatomic, assign) BOOL useTabs;
@property (nonatomic, assign) BOOL wrap;
@property (nonatomic, assign) BOOL lineNumbers;
@property (nonatomic, assign) BOOL showWhitespace;
@property (nonatomic, copy) NSString *theme;
@property (nonatomic, assign) BOOL syncScroll;
@property (nonatomic, assign) BOOL confirmClose;
@property (nonatomic, assign) BOOL showMinimap;
@property (nonatomic, assign) BOOL autoClose;
@property (nonatomic, assign) BOOL smartIndent;
@property (nonatomic, assign) BOOL highlightMatches;
@property (nonatomic, assign) BOOL showChanges;
@property (nonatomic, assign) BOOL backupBeforeSave;
@property (nonatomic, assign) BOOL spellCheck;
@property (nonatomic, assign) BOOL showFileSize;
@property (nonatomic, assign) BOOL showCharacterPanel;
@property (nonatomic, assign) BOOL extraWindows;
@property (nonatomic, assign) BOOL formatDocuments;
@property (nonatomic, copy) NSString *fileSizeUnit;
@property (nonatomic, copy) NSString *uiLanguage;
@property (nonatomic, copy) NSArray<NSString *> *searchHistory;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *shortcuts;
+ (instancetype)loadFromURL:(NSURL *)url;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (NSString *)shortcutForCommand:(NSString *)command;
- (void)setShortcut:(NSString *)shortcut forCommand:(NSString *)command;
- (void)rememberSearch:(NSString *)query;
+ (NSString *)shortcutSpecForEvent:(NSEvent *)event;
+ (NSDictionary<NSString *, NSString *> *)defaultShortcuts;
+ (BOOL)parseShortcut:(NSString *)spec key:(NSString **)key modifiers:(NSEventModifierFlags *)modifiers;
@end
