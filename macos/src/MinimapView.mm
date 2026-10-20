#import "MinimapView.h"

#import <objc/message.h>

@implementation NppMinimapView

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		self.wantsLayer = YES;
		self.layer.backgroundColor = NSColor.windowBackgroundColor.CGColor;
		_viewportScale = 0.2;
	}
	return self;
}

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	[NSColor.windowBackgroundColor setFill];
	NSRectFill(self.bounds);
	NSArray<NSNumber *> *widths = self.lineWidths;
	NSUInteger count = widths.count;
	if (count == 0) {
		NSString *text = self.text ?: @"";
		NSArray<NSString *> *lines = [text componentsSeparatedByCharactersInSet:[NSCharacterSet newlineCharacterSet]];
		NSMutableArray<NSNumber *> *measured = [NSMutableArray array];
		NSUInteger step = MAX(1, lines.count / 500);
		for (NSUInteger index = 0; index < lines.count; index += step) {
			[measured addObject:@(lines[index].length)];
		}
		widths = measured;
		count = widths.count;
	}
	if (count == 0) {
		return;
	}
	CGFloat row = self.bounds.size.height / count;
	CGFloat y = self.bounds.size.height;
	[NSColor.tertiaryLabelColor setFill];
	for (NSNumber *length in widths) {
		CGFloat bar = MIN(self.bounds.size.width - 6, MAX(2, length.doubleValue * 0.45));
		y -= row;
		NSRectFill(NSMakeRect(3, y, bar, MAX(1, row - 0.4)));
	}
	CGFloat height = MAX(8, self.bounds.size.height * MIN(1, MAX(0.02, self.viewportScale)));
	CGFloat origin = self.bounds.size.height * (1 - MIN(1, self.viewportStart)) - height;
	origin = MAX(0, MIN(self.bounds.size.height - height, origin));
	[[NSColor.controlAccentColor colorWithAlphaComponent:0.28] setFill];
	NSRectFill(NSMakeRect(0, origin, self.bounds.size.width, height));
	if (self.hovering) {
		CGFloat mark = self.bounds.size.height * (1 - MIN(1, MAX(0, self.hoverFraction)));
		[[NSColor.controlAccentColor colorWithAlphaComponent:0.95] setFill];
		NSRectFill(NSMakeRect(0, mark - 1, self.bounds.size.width, 2));
	}
}

- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *area in self.trackingAreas) {
		[self removeTrackingArea:area];
	}
	NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
	[self addTrackingArea:area];
}

- (void)reportHover:(NSEvent *)event inside:(BOOL)inside {
	if (inside) {
		NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
		self.hoverFraction = MIN(1, MAX(0, 1 - (point.y / MAX(1, self.bounds.size.height))));
		self.hovering = YES;
	} else {
		self.hovering = NO;
	}
	[self setNeedsDisplay:YES];
	if (self.target && self.hoverAction) {
		((void (*)(id, SEL, id))objc_msgSend)(self.target, self.hoverAction, self);
	}
}

- (void)mouseEntered:(NSEvent *)event {
	[self reportHover:event inside:YES];
}

- (void)mouseMoved:(NSEvent *)event {
	[self reportHover:event inside:YES];
}

- (void)mouseExited:(NSEvent *)event {
	[self reportHover:event inside:NO];
}

- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	CGFloat fraction = 1 - (point.y / MAX(1, self.bounds.size.height));
	self.clickedFraction = MIN(1, MAX(0, fraction));
	if (self.target && self.action) {
		((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
	}
}

@end

@implementation NppMinimapZoom

- (BOOL)isFlipped {
	return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
	(void)event;
	return YES;
}

- (BOOL)isOpaque {
	return YES;
}

- (NSRect)rectForRow:(NSInteger)index {
	return NSMakeRect(4, 8 + index * 17, MAX(8, self.bounds.size.width - 8), 17);
}

- (NSInteger)rowIndexAtPoint:(NSPoint)point {
	NSInteger count = (NSInteger)self.rowNumbers.count;
	if (count <= 0) {
		return 0;
	}
	for (NSInteger index = 0; index < count; index++) {
		if (NSPointInRect(point, [self rectForRow:index])) {
			return index;
		}
	}
	NSInteger guess = (NSInteger)floor((point.y - 8) / 17);
	return MIN(count - 1, MAX(0, guess));
}

- (void)updateTrackingAreas {
	[super updateTrackingAreas];
	for (NSTrackingArea *area in self.trackingAreas) {
		[self removeTrackingArea:area];
	}
	NSTrackingArea *area = [[NSTrackingArea alloc] initWithRect:NSZeroRect options:(NSTrackingMouseEnteredAndExited | NSTrackingMouseMoved | NSTrackingActiveInKeyWindow | NSTrackingInVisibleRect) owner:self userInfo:nil];
	[self addTrackingArea:area];
}

- (NSColor *)cardColor {
	NSColor *color = [NSColor.textBackgroundColor colorUsingType:NSColorTypeComponentBased];
	return color ?: [NSColor colorWithCalibratedWhite:1 alpha:1];
}

- (void)drawRect:(NSRect)dirtyRect {
	(void)dirtyRect;
	NSColor *background = [self cardColor];
	self.layer.backgroundColor = background.CGColor;
	self.layer.opaque = YES;
	[background setFill];
	NSRectFillUsingOperation(self.bounds, NSCompositingOperationCopy);
	NSRect card = NSInsetRect(self.bounds, 0.5, 0.5);
	NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:card xRadius:6 yRadius:6];
	[background setFill];
	[path fill];
	[NSColor.separatorColor setStroke];
	[path stroke];
	NSFont *font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	NSFont *numberFont = [NSFont fontWithName:@"Menlo" size:11] ?: font;
	NSArray<NSString *> *rows = self.rows ?: @[];
	NSArray<NSNumber *> *numbers = self.rowNumbers ?: @[];
	for (NSUInteger index = 0; index < rows.count; index++) {
		long number = index < numbers.count ? numbers[index].longValue : 0;
		NSRect row = [self rectForRow:(NSInteger)index];
		if (number == self.focusLine) {
			[[NSColor.controlAccentColor colorWithAlphaComponent:0.35] setFill];
			NSRectFill(row);
		}
		NSString *label = [NSString stringWithFormat:@"%ld", number];
		NSDictionary *numberAttributes = @{
			NSFontAttributeName: numberFont,
			NSForegroundColorAttributeName: number == self.focusLine ? NSColor.controlAccentColor : NSColor.secondaryLabelColor,
			NSParagraphStyleAttributeName: [self numberStyle]
		};
		NSDictionary *textAttributes = @{
			NSFontAttributeName: font,
			NSForegroundColorAttributeName: NSColor.labelColor,
			NSParagraphStyleAttributeName: [self clipStyle]
		};
		[label drawWithRect:NSMakeRect(8, row.origin.y, 46, row.size.height) options:NSStringDrawingUsesLineFragmentOrigin attributes:numberAttributes];
		[rows[index] drawWithRect:NSMakeRect(58, row.origin.y, MAX(8, row.size.width - 62), row.size.height) options:NSStringDrawingUsesLineFragmentOrigin attributes:textAttributes];
	}
}

- (NSParagraphStyle *)numberStyle {
	NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
	style.alignment = NSTextAlignmentRight;
	style.lineBreakMode = NSLineBreakByClipping;
	return style;
}

- (NSParagraphStyle *)clipStyle {
	NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
	style.lineBreakMode = NSLineBreakByClipping;
	return style;
}

- (void)mouseMoved:(NSEvent *)event {
	if (self.rowNumbers.count == 0) {
		return;
	}
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	NSInteger index = [self rowIndexAtPoint:point];
	long line = self.rowNumbers[index].longValue;
	if (line != self.focusLine) {
		self.focusLine = line;
		[self setNeedsDisplay:YES];
	}
}

- (BOOL)clickAtViewPoint:(NSPoint)point {
	NSArray<NSNumber *> *numbers = self.rowNumbers ?: @[];
	if (numbers.count == 0) {
		return NO;
	}
	NSInteger index = [self rowIndexAtPoint:point];
	self.focusLine = numbers[index].longValue;
	self.clickedLine = self.focusLine - 1;
	NSFont *font = [NSFont fontWithName:@"Menlo" size:12] ?: [NSFont monospacedSystemFontOfSize:12 weight:NSFontWeightRegular];
	CGFloat charWidth = MAX(1, [@"0" sizeWithAttributes:@{NSFontAttributeName: font}].width);
	if (point.x <= 58) {
		self.clickedColumn = 0;
	} else {
		self.clickedColumn = (long)floor(((point.x - 58) + charWidth * 0.5) / charWidth);
	}
	[self setNeedsDisplay:YES];
	if (self.target && self.action) {
		((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
	}
	return YES;
}

- (void)mouseDown:(NSEvent *)event {
	NSPoint point = [self convertPoint:event.locationInWindow fromView:nil];
	[self clickAtViewPoint:point];
}

- (void)mouseUp:(NSEvent *)event {
	(void)event;
	if (self.clickedLine < 0 || !(self.target && self.action)) {
		return;
	}
	((void (*)(id, SEL, id))objc_msgSend)(self.target, self.action, self);
}

- (void)mouseExited:(NSEvent *)event {
	(void)event;
	if (self.target && self.exitAction) {
		((void (*)(id, SEL, id))objc_msgSend)(self.target, self.exitAction, self);
	}
}

@end
