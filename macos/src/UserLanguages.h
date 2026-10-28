#pragma once

#import <Foundation/Foundation.h>

@class LangInfo;

@interface NppUserLanguage : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *extensions;
@property (nonatomic, copy) NSString *keywords;
@property (nonatomic, copy) NSString *lexer;
- (LangInfo *)langInfo;
- (BOOL)matchesPath:(NSString *)path;
@end

@interface NppUserLanguageStore : NSObject
@property (nonatomic, strong) NSMutableArray<NppUserLanguage *> *languages;
+ (instancetype)loadFromURL:(NSURL *)url;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (NppUserLanguage *)languageForPath:(NSString *)path;
- (LangInfo *)langInfoNamed:(NSString *)name;
@end
