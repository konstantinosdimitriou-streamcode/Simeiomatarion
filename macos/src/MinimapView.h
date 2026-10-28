#pragma once

#import <AppKit/AppKit.h>

@interface NppMinimapView : NSView
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<NSNumber *> *lineWidths;
@property (nonatomic, assign) CGFloat viewportStart;
@property (nonatomic, assign) CGFloat viewportScale;
@property (nonatomic, assign) CGFloat clickedFraction;
@property (nonatomic, assign) CGFloat hoverFraction;
@property (nonatomic, assign) BOOL hovering;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) SEL hoverAction;
@property (nonatomic, assign) NSInteger pane;
@end

@interface NppMinimapZoom : NSView
@property (nonatomic, copy) NSArray<NSString *> *rows;
@property (nonatomic, copy) NSArray<NSNumber *> *rowNumbers;
@property (nonatomic, assign) long focusLine;
@property (nonatomic, assign) long clickedLine;
@property (nonatomic, assign) long clickedColumn;
@property (nonatomic, assign) NSInteger pane;
@property (nonatomic, weak) id target;
@property (nonatomic, assign) SEL action;
@property (nonatomic, assign) SEL exitAction;
- (BOOL)clickAtViewPoint:(NSPoint)point;
@end
