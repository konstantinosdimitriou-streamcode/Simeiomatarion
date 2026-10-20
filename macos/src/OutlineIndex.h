#pragma once

#import <AppKit/AppKit.h>

@interface NppSymbol : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *kind;
@property (nonatomic, assign) NSInteger line;
@end

NSArray<NppSymbol *> *NppOutlineSymbols(NSString *language, NSString *lexer, NSString *text);
NSColor *NppLanguageColor(NSString *language);
