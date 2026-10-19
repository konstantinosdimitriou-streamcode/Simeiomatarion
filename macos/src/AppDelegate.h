#pragma once

#import <Cocoa/Cocoa.h>

@class DocumentTab;

@interface AppDelegate : NSObject <NSApplicationDelegate, NSWindowDelegate, NSTableViewDataSource, NSTableViewDelegate>
- (DocumentTab *)currentDocument;
- (NSString *)selectedText;
- (void)replaceSelection:(NSString *)text;
- (void)insertText:(NSString *)text;
- (void)replaceDocumentText:(NSString *)text;
- (void)setStatusText:(NSString *)text;
@end
