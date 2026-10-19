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
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *shortcuts;
+ (instancetype)loadFromURL:(NSURL *)url;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (NSString *)shortcutForCommand:(NSString *)command;
- (void)setShortcut:(NSString *)shortcut forCommand:(NSString *)command;
+ (NSDictionary<NSString *, NSString *> *)defaultShortcuts;
+ (BOOL)parseShortcut:(NSString *)spec key:(NSString **)key modifiers:(NSEventModifierFlags *)modifiers;
@end
