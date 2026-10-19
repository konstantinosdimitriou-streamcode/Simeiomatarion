#pragma once

#import <Foundation/Foundation.h>

@interface LangInfo : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *lexer;
@property (nonatomic, copy) NSArray<NSString *> *extensions;
@property (nonatomic, copy) NSDictionary<NSString *, NSString *> *keywords;
@end

@interface LangCatalog : NSObject
+ (instancetype)catalogWithXML:(NSString *)path;
- (LangInfo *)languageNamed:(NSString *)name;
- (LangInfo *)languageForPath:(NSString *)path;
- (LangInfo *)languageForPath:(NSString *)path sample:(NSString *)sample;
- (NSArray<LangInfo *> *)allLanguages;
@end
