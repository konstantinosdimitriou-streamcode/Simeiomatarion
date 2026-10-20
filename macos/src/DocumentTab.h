#pragma once

#import <Cocoa/Cocoa.h>

#import "Encoding.h"
#import "ScintillaView.h"

@class EditorSettings;
@class LangInfo;
@class DocumentTab;

@protocol DocumentTabDelegate <NSObject>
- (void)documentTabDidChange:(DocumentTab *)tab;
- (void)documentTabDidScroll:(DocumentTab *)tab;
- (void)documentTab:(DocumentTab *)tab insertedText:(NSString *)text at:(NSInteger)position;
- (void)documentTab:(DocumentTab *)tab deletedText:(NSString *)text at:(NSInteger)position;
@end

@interface DocumentTab : NSObject <ScintillaNotificationProtocol>
@property (nonatomic, strong) ScintillaView *editor;
@property (nonatomic, copy) NSString *path;
@property (nonatomic, copy) NSString *displayName;
@property (nonatomic, assign) NppTextEncoding encoding;
@property (nonatomic, assign) int eolMode;
@property (nonatomic, assign) BOOL dirty;
@property (nonatomic, assign) BOOL manualLanguage;
@property (nonatomic, copy) NSString *language;
@property (nonatomic, copy) NSString *lexerName;
@property (nonatomic, assign) BOOL suppressMacro;
@property (nonatomic, assign) BOOL pinned;
@property (nonatomic, assign) BOOL fileMonitoring;
- (ScintillaView *)mirrorView;
- (ScintillaView *)existingMirror;
- (void)discardMirror;
@property (nonatomic, copy) NSDate *observedModificationDate;
@property (nonatomic, assign) unsigned long long observedFileSize;
@property (nonatomic, assign) BOOL missingOnDiskNoted;
@property (nonatomic, weak) id<DocumentTabDelegate> delegate;

- (void)setFileMonitoring:(BOOL)enabled;
- (void)reloadFromDiskScrollingToEnd:(BOOL)scrollToEnd;

- (instancetype)initWithFrame:(NSRect)frame;
- (void)applySettings:(EditorSettings *)settings dark:(BOOL)dark;
- (void)applyLanguage:(LangInfo *)info dark:(BOOL)dark;
- (void)setUtf8Text:(NSString *)text;
- (NSString *)utf8Text;
- (NSString *)title;
- (void)markClean;
@end
