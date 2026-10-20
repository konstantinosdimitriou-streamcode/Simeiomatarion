#import "ClipboardHistory.h"

@implementation NppClipboardHistory {
	NSMutableArray<NSString *> *_items;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_items = [NSMutableArray array];
	}
	return self;
}

- (NSArray<NSString *> *)items {
	return [_items copy];
}

- (void)remember:(NSString *)text {
	if (text.length == 0) {
		return;
	}
	if (text.length > 8000) {
		text = [[text substringToIndex:8000] stringByAppendingString:@"…"];
	}
	if ([_items.firstObject isEqualToString:text]) {
		return;
	}
	[_items removeObject:text];
	[_items insertObject:text atIndex:0];
	while (_items.count > 30) {
		[_items removeLastObject];
	}
}

@end
