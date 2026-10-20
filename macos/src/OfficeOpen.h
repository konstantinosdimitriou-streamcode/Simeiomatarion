#pragma once

#import <Cocoa/Cocoa.h>

typedef NS_ENUM(NSInteger, NppOfficeKind) {
	NppOfficeKindNone = 0,
	NppOfficeKindCSV,
	NppOfficeKindPDF,
	NppOfficeKindDOC,
	NppOfficeKindDOCX,
	NppOfficeKindXLSX
};

@interface NppOfficeRef : NSObject
@property (nonatomic, assign) NppOfficeKind kind;
@property (nonatomic, assign) BOOL showTable;
@property (nonatomic, strong) NSView *view;
@end

@interface NppCsvView : NSView <NSTableViewDataSource, NSTableViewDelegate, NSTextFieldDelegate>
@property (nonatomic, copy) void (^onEdit)(NSString *csv);
@property (nonatomic, copy) void (^onShowText)(void);
@property (nonatomic, copy) void (^onSheet)(NSString *sheet);
@property (nonatomic, readonly) BOOL fitsInTable;
@property (nonatomic, readonly, copy) NSString *selectedSheet;
- (void)loadCsv:(NSString *)csv;
- (void)loadRows:(NSArray<NSArray<NSString *> *> *)rows editable:(BOOL)editable sheets:(NSArray<NSString *> *)sheets selectedSheet:(NSString *)sheet truncated:(BOOL)truncated;
- (NSInteger)adjustZoom:(NSInteger)direction;
- (NSString *)csvText;
@end

@interface NppWordView : NSView
@property (nonatomic, readonly, copy) NSString *plainText;
- (BOOL)loadPath:(NSString *)path kind:(NppOfficeKind)kind error:(NSString **)error;
- (NSInteger)adjustZoom:(NSInteger)direction;
@end

NppOfficeKind NppOfficeKindForPath(NSString *path);
BOOL NppOfficeKindIsViewOnly(NppOfficeKind kind);
BOOL NppWordPlainText(NSString *path, NppOfficeKind kind, NSString **text, NSString **error);
NSView *NppPDFViewForPath(NSString *path, NSString **error);
BOOL NppReloadPDFView(NSView *view, NSString *path, NSString **error);
NSArray<NSArray<NSString *> *> *NppParseCSV(NSString *text, unichar *delimiter);
NSString *NppFormatCSV(NSArray<NSArray<NSString *> *> *rows, unichar delimiter);
BOOL NppXlsxLoad(NSString *path, NSString *sheet, NSArray<NSString *> **sheetNames, NSArray<NSArray<NSString *> *> **rows, BOOL *truncated, NSString **error);
NSIndexSet *NppTableFilterIndexes(NSArray<NSArray<NSString *> *> *rows, NSDictionary<NSNumber *, NSSet<NSString *> *> *allowed);
