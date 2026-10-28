#pragma once

#import <Foundation/Foundation.h>

NSString *NppFormatByteCount(unsigned long long bytes, NSString *unit);
NSString *NppPrettyJSON(NSString *text, NSString **error);
NSString *NppPrettyXML(NSString *text, NSString **error);
