#pragma once

#import <Foundation/Foundation.h>

@interface MacroStep : NSObject
@property (nonatomic, assign) BOOL insert;
@property (nonatomic, assign) NSInteger position;
@property (nonatomic, copy) NSString *text;
@end

@interface MacroStore : NSObject
@property (nonatomic, readonly) BOOL recording;
@property (nonatomic, readonly) NSArray<MacroStep *> *steps;
- (void)start;
- (void)stop;
- (void)addInsert:(NSString *)text at:(NSInteger)position;
- (void)addDelete:(NSString *)text at:(NSInteger)position;
- (NSArray<NSString *> *)savedNames;
- (void)rememberCurrentAs:(NSString *)name;
- (BOOL)activateSaved:(NSString *)name;
- (BOOL)saveToURL:(NSURL *)url error:(NSError **)error;
- (BOOL)loadFromURL:(NSURL *)url error:(NSError **)error;
@end
