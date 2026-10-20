#pragma once

#import <Foundation/Foundation.h>

@interface NppSnippetStore : NSObject
@property (nonatomic, strong) NSMutableArray<NSMutableDictionary<NSString *, NSString *> *> *snippets;
+ (instancetype)loadFromURL:(NSURL *)url;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (NSString *)bodyForName:(NSString *)name;
@end
