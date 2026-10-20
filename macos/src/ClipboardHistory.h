#pragma once

#import <Foundation/Foundation.h>

@interface NppClipboardHistory : NSObject
@property (nonatomic, readonly) NSArray<NSString *> *items;
- (void)remember:(NSString *)text;
@end
