#pragma once

#import <Foundation/Foundation.h>

@class ScintillaView;

@interface StyleTheme : NSObject
+ (instancetype)themeWithXML:(NSString *)path;
- (void)applyToEditor:(ScintillaView *)editor language:(NSString *)language dark:(BOOL)dark;
@end
