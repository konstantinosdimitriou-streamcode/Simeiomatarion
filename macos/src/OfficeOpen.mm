#import "OfficeOpen.h"
#import "Localization.h"

#import <PDFKit/PDFKit.h>
#import <zlib.h>

@implementation NppOfficeRef
@end

static const NSInteger kNppCsvMaxRows = 8000;
static const NSInteger kNppCsvMaxColumns = 64;

NppOfficeKind NppOfficeKindForPath(NSString *path) {
	NSString *extension = path.pathExtension.lowercaseString;
	if ([extension isEqualToString:@"csv"]) {
		return NppOfficeKindCSV;
	}
	if ([extension isEqualToString:@"pdf"]) {
		return NppOfficeKindPDF;
	}
	if ([extension isEqualToString:@"doc"]) {
		return NppOfficeKindDOC;
	}
	if ([extension isEqualToString:@"docx"]) {
		return NppOfficeKindDOCX;
	}
	if ([extension isEqualToString:@"xlsx"]) {
		return NppOfficeKindXLSX;
	}
	return NppOfficeKindNone;
}

BOOL NppOfficeKindIsViewOnly(NppOfficeKind kind) {
	return kind == NppOfficeKindPDF || kind == NppOfficeKindDOC || kind == NppOfficeKindDOCX || kind == NppOfficeKindXLSX;
}

static NSAttributedString *NppWordAttributed(NSString *path, NppOfficeKind kind, NSString **error) {
	NSURL *url = path.length ? [NSURL fileURLWithPath:path] : nil;
	if (!url) {
		if (error) {
			*error = @"Could not read this Word file.";
		}
		return nil;
	}
	NSString *type = kind == NppOfficeKindDOCX ? NSOfficeOpenXMLTextDocumentType : NSDocFormatTextDocumentType;
	NSError *readError = nil;
	NSDictionary *options = @{NSDocumentTypeDocumentAttribute: type};
	NSAttributedString *attributed = [[NSAttributedString alloc] initWithURL:url options:options documentAttributes:nil error:&readError];
	if (!attributed) {
		attributed = [[NSAttributedString alloc] initWithURL:url options:@{} documentAttributes:nil error:&readError];
	}
	if (!attributed) {
		if (error) {
			*error = readError.localizedDescription.length ? readError.localizedDescription : @"Could not read this Word file.";
		}
	}
	return attributed;
}

BOOL NppWordPlainText(NSString *path, NppOfficeKind kind, NSString **text, NSString **error) {
	if (text) {
		*text = @"";
	}
	NSAttributedString *attributed = NppWordAttributed(path, kind, error);
	if (!attributed) {
		return NO;
	}
	if (text) {
		*text = attributed.string ?: @"";
	}
	return YES;
}

@implementation NppWordView {
	NSScrollView *_scroll;
	NSTextView *_text;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		self.appearance = [NSAppearance appearanceNamed:NSAppearanceNameAqua];
		_scroll = [[NSScrollView alloc] initWithFrame:self.bounds];
		_scroll.hasVerticalScroller = YES;
		_scroll.autohidesScrollers = YES;
		_scroll.drawsBackground = YES;
		_scroll.backgroundColor = NSColor.whiteColor;
		_scroll.borderType = NSNoBorder;
		_scroll.allowsMagnification = YES;
		_scroll.minMagnification = 0.5;
		_scroll.maxMagnification = 3;
		_scroll.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
		_text = [[NSTextView alloc] initWithFrame:NSMakeRect(0, 0, MAX(200, NSWidth(self.bounds)), MAX(200, NSHeight(self.bounds)))];
		_text.editable = NO;
		_text.selectable = YES;
		_text.richText = YES;
		_text.importsGraphics = YES;
		_text.drawsBackground = YES;
		_text.backgroundColor = NSColor.whiteColor;
		_text.textColor = NSColor.blackColor;
		_text.insertionPointColor = NSColor.blackColor;
		_text.textContainerInset = NSMakeSize(32, 28);
		_text.horizontallyResizable = NO;
		_text.verticallyResizable = YES;
		_text.autoresizingMask = NSViewWidthSizable;
		_text.minSize = NSMakeSize(0, 0);
		_text.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
		_text.textContainer.containerSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
		_text.textContainer.widthTracksTextView = YES;
		_text.textContainer.heightTracksTextView = NO;
		_scroll.documentView = _text;
		[self addSubview:_scroll];
	}
	return self;
}

- (void)layout {
	[super layout];
	_scroll.frame = self.bounds;
	CGFloat width = MAX(280, _scroll.contentSize.width);
	if (fabs(_text.frame.size.width - width) > 0.5) {
		[_text setFrameSize:NSMakeSize(width, MAX(_text.frame.size.height, _scroll.contentSize.height))];
	}
}

- (NSString *)plainText {
	return _text.string ?: @"";
}

- (BOOL)loadPath:(NSString *)path kind:(NppOfficeKind)kind error:(NSString **)error {
	NSAttributedString *attributed = NppWordAttributed(path, kind, error);
	if (!attributed) {
		return NO;
	}
	[_text.textStorage setAttributedString:attributed];
	return YES;
}

- (NSInteger)adjustZoom:(NSInteger)direction {
	if (direction == 0) {
		_scroll.magnification = 1;
	} else {
		CGFloat next = _scroll.magnification * (direction > 0 ? 1.15 : (1.0 / 1.15));
		_scroll.magnification = MIN(_scroll.maxMagnification, MAX(_scroll.minMagnification, next));
	}
	return (NSInteger)llround(_scroll.magnification * 100.0);
}

@end

NSView *NppPDFViewForPath(NSString *path, NSString **error) {
	NSURL *url = path.length ? [NSURL fileURLWithPath:path] : nil;
	PDFDocument *document = url ? [[PDFDocument alloc] initWithURL:url] : nil;
	if (!document || document.pageCount == 0) {
		if (error) {
			*error = @"Could not open this PDF.";
		}
		return nil;
	}
	PDFView *view = [[PDFView alloc] initWithFrame:NSMakeRect(0, 0, 640, 480)];
	view.document = document;
	view.autoScales = YES;
	view.displayMode = kPDFDisplaySinglePageContinuous;
	view.displayDirection = kPDFDisplayDirectionVertical;
	view.backgroundColor = NSColor.textBackgroundColor;
	return view;
}

BOOL NppReloadPDFView(NSView *view, NSString *path, NSString **error) {
	if (![view isKindOfClass:[PDFView class]]) {
		if (error) {
			*error = @"Could not open this PDF.";
		}
		return NO;
	}
	NSURL *url = path.length ? [NSURL fileURLWithPath:path] : nil;
	PDFDocument *document = url ? [[PDFDocument alloc] initWithURL:url] : nil;
	if (!document || document.pageCount == 0) {
		if (error) {
			*error = @"Could not open this PDF.";
		}
		return NO;
	}
	((PDFView *)view).document = document;
	return YES;
}

static NSArray<NSArray<NSString *> *> *NppParseCSVWithDelimiter(NSString *source, unichar delimiter);

static NSString *NppCsvSample(NSString *text) {
	NSUInteger breaks = 0;
	NSUInteger length = MIN(text.length, (NSUInteger)65536);
	for (NSUInteger index = 0; index < length; index++) {
		unichar character = [text characterAtIndex:index];
		if (character == '\n' || character == '\r') {
			breaks++;
			if (breaks >= 40) {
				return [text substringToIndex:index];
			}
		}
	}
	return length == text.length ? text : [text substringToIndex:length];
}

static NSInteger NppCsvColumnAgreement(NSArray<NSArray<NSString *> *> *rows, NSInteger *columns) {
	NSMutableDictionary<NSNumber *, NSNumber *> *counts = [NSMutableDictionary dictionary];
	NSInteger bestColumns = 1;
	NSInteger bestCount = 0;
	for (NSArray<NSString *> *row in rows) {
		if (row.count <= 1 && rows.count > 1) {
			BOOL blank = YES;
			for (NSString *cell in row) {
				if (cell.length > 0) {
					blank = NO;
					break;
				}
			}
			if (blank) {
				continue;
			}
		}
		NSNumber *key = @(row.count);
		NSInteger count = counts[key].integerValue + 1;
		counts[key] = @(count);
		if (count > bestCount || (count == bestCount && (NSInteger)row.count > bestColumns)) {
			bestCount = count;
			bestColumns = (NSInteger)row.count;
		}
	}
	if (columns) {
		*columns = bestColumns;
	}
	return bestCount;
}

static unichar NppDetectDelimiter(NSString *text) {
	NSString *sample = NppCsvSample(text ?: @"");
	unichar candidates[] = {',', ';', '\t', '|', ':', '^', '~'};
	unichar best = ',';
	NSInteger bestColumns = 1;
	NSInteger bestAgreement = 0;
	for (NSUInteger index = 0; index < sizeof(candidates) / sizeof(candidates[0]); index++) {
		NSInteger columns = 1;
		NSInteger agreement = NppCsvColumnAgreement(NppParseCSVWithDelimiter(sample, candidates[index]), &columns);
		if (columns < 2) {
			continue;
		}
		if (agreement > bestAgreement || (agreement == bestAgreement && columns > bestColumns)) {
			bestAgreement = agreement;
			bestColumns = columns;
			best = candidates[index];
		}
	}
	return best;
}

static NSArray<NSArray<NSString *> *> *NppParseCSVWithDelimiter(NSString *source, unichar delimiter) {
	NSMutableArray<NSMutableArray<NSString *> *> *rows = [NSMutableArray array];
	NSMutableArray<NSString *> *row = [NSMutableArray array];
	NSMutableString *field = [NSMutableString string];
	BOOL quoted = NO;
	NSUInteger length = source.length;
	for (NSUInteger index = 0; index < length; index++) {
		unichar character = [source characterAtIndex:index];
		if (quoted) {
			if (character == '"') {
				if (index + 1 < length && [source characterAtIndex:index + 1] == '"') {
					[field appendString:@"\""];
					index++;
				} else {
					quoted = NO;
				}
			} else {
				[field appendFormat:@"%C", character];
			}
			continue;
		}
		if (character == '"') {
			quoted = YES;
			continue;
		}
		if (character == delimiter) {
			[row addObject:[field copy]];
			field = [NSMutableString string];
			continue;
		}
		if (character == '\n' || character == '\r') {
			if (character == '\r' && index + 1 < length && [source characterAtIndex:index + 1] == '\n') {
				index++;
			}
			[row addObject:[field copy]];
			field = [NSMutableString string];
			[rows addObject:row];
			row = [NSMutableArray array];
			continue;
		}
		[field appendFormat:@"%C", character];
	}
	if (field.length > 0 || row.count > 0) {
		[row addObject:[field copy]];
		[rows addObject:row];
	}
	return rows;
}

NSArray<NSArray<NSString *> *> *NppParseCSV(NSString *text, unichar *delimiterOut) {
	NSString *source = text ?: @"";
	unichar delimiter = NppDetectDelimiter(source);
	if (delimiterOut) {
		*delimiterOut = delimiter;
	}
	return NppParseCSVWithDelimiter(source, delimiter);
}

static NSString *NppCsvEscape(NSString *value, unichar delimiter) {
	NSString *text = value ?: @"";
	NSString *specials = [NSString stringWithFormat:@"\"\r\n%C", delimiter];
	if ([text rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:specials]].location == NSNotFound) {
		return text;
	}
	return [NSString stringWithFormat:@"\"%@\"", [text stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

NSString *NppFormatCSV(NSArray<NSArray<NSString *> *> *rows, unichar delimiter) {
	if (delimiter == 0) {
		delimiter = ',';
	}
	NSMutableString *text = [NSMutableString string];
	for (NSArray<NSString *> *row in rows) {
		if (text.length > 0) {
			[text appendString:@"\n"];
		}
		for (NSUInteger index = 0; index < row.count; index++) {
			if (index > 0) {
				[text appendFormat:@"%C", delimiter];
			}
			[text appendString:NppCsvEscape(row[index], delimiter)];
		}
	}
	if (text.length > 0) {
		[text appendString:@"\n"];
	}
	return text;
}

static BOOL NppCsvLooksLikeHeader(NSArray<NSString *> *row) {
	if (row.count == 0) {
		return NO;
	}
	NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
	for (NSString *cell in row) {
		if (cell.length == 0 || [cell rangeOfCharacterFromSet:letters].location == NSNotFound) {
			return NO;
		}
	}
	return YES;
}

NSIndexSet *NppTableFilterIndexes(NSArray<NSArray<NSString *> *> *rows, NSDictionary<NSNumber *, NSSet<NSString *> *> *allowed) {
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	if (allowed.count == 0) {
		[indexes addIndexesInRange:NSMakeRange(0, rows.count)];
		return indexes;
	}
	[rows enumerateObjectsUsingBlock:^(NSArray<NSString *> *row, NSUInteger rowIndex, BOOL *stop) {
		(void)stop;
		for (NSNumber *column in allowed) {
			NSInteger index = column.integerValue;
			NSString *value = (index >= 0 && index < (NSInteger)row.count) ? (row[index] ?: @"") : @"";
			if (![allowed[column] containsObject:value]) {
				return;
			}
		}
		[indexes addIndex:rowIndex];
	}];
	return indexes;
}

static uint16_t NppZipU16(const uint8_t *bytes) {
	return (uint16_t)(bytes[0] | (bytes[1] << 8));
}

static uint32_t NppZipU32(const uint8_t *bytes) {
	return (uint32_t)bytes[0] | ((uint32_t)bytes[1] << 8) | ((uint32_t)bytes[2] << 16) | ((uint32_t)bytes[3] << 24);
}

static NSData *NppZipInflate(const uint8_t *bytes, NSUInteger length, NSUInteger expected) {
	if (expected == 0 || expected > 40 * 1024 * 1024) {
		expected = MIN(MAX(length * 4, (NSUInteger)1024), (NSUInteger)40 * 1024 * 1024);
	}
	NSMutableData *output = [NSMutableData dataWithLength:expected];
	z_stream stream;
	memset(&stream, 0, sizeof(stream));
	stream.next_in = (Bytef *)bytes;
	stream.avail_in = (uInt)length;
	if (inflateInit2(&stream, -MAX_WBITS) != Z_OK) {
		return nil;
	}
	int status = Z_OK;
	while (status == Z_OK) {
		if (stream.total_out >= output.length) {
			if (output.length >= 40 * 1024 * 1024) {
				inflateEnd(&stream);
				return nil;
			}
			[output increaseLengthBy:MAX((NSUInteger)output.length, (NSUInteger)4096)];
		}
		stream.next_out = (Bytef *)output.mutableBytes + stream.total_out;
		stream.avail_out = (uInt)(output.length - stream.total_out);
		status = inflate(&stream, Z_NO_FLUSH);
		if (status == Z_BUF_ERROR && stream.avail_out == 0) {
			status = Z_OK;
		}
	}
	inflateEnd(&stream);
	if (status != Z_STREAM_END) {
		return nil;
	}
	output.length = stream.total_out;
	return output;
}

static NSData *NppZipExtract(NSData *archive, NSString *wanted) {
	const uint8_t *bytes = (const uint8_t *)archive.bytes;
	NSUInteger length = archive.length;
	if (length < 22 || wanted.length == 0) {
		return nil;
	}
	NSUInteger limit = length > 65557 ? length - 65557 : 0;
	NSUInteger eocd = NSNotFound;
	for (NSUInteger index = length - 22; ; index--) {
		if (bytes[index] == 0x50 && bytes[index + 1] == 0x4b && bytes[index + 2] == 0x05 && bytes[index + 3] == 0x06) {
			eocd = index;
			break;
		}
		if (index == limit) {
			break;
		}
	}
	if (eocd == NSNotFound || eocd + 22 > length) {
		return nil;
	}
	uint16_t count = NppZipU16(bytes + eocd + 10);
	uint32_t directorySize = NppZipU32(bytes + eocd + 12);
	uint32_t directoryOffset = NppZipU32(bytes + eocd + 16);
	if (directoryOffset > length || directorySize > length - directoryOffset) {
		return nil;
	}
	NSString *needle = [wanted stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
	NSUInteger cursor = directoryOffset;
	for (uint16_t entry = 0; entry < count; entry++) {
		if (cursor + 46 > length || NppZipU32(bytes + cursor) != 0x02014b50) {
			return nil;
		}
		uint16_t method = NppZipU16(bytes + cursor + 10);
		uint32_t compressed = NppZipU32(bytes + cursor + 20);
		uint32_t uncompressed = NppZipU32(bytes + cursor + 24);
		uint16_t nameLength = NppZipU16(bytes + cursor + 28);
		uint16_t extraLength = NppZipU16(bytes + cursor + 30);
		uint16_t commentLength = NppZipU16(bytes + cursor + 32);
		uint32_t localOffset = NppZipU32(bytes + cursor + 42);
		if (cursor + 46 + nameLength > length) {
			return nil;
		}
		NSString *name = [[NSString alloc] initWithBytes:bytes + cursor + 46 length:nameLength encoding:NSUTF8StringEncoding] ?: @"";
		name = [name stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
		cursor += 46 + nameLength + extraLength + commentLength;
		if (![name isEqualToString:needle]) {
			continue;
		}
		if (localOffset + 30 > length || NppZipU32(bytes + localOffset) != 0x04034b50) {
			return nil;
		}
		uint16_t localName = NppZipU16(bytes + localOffset + 26);
		uint16_t localExtra = NppZipU16(bytes + localOffset + 28);
		NSUInteger dataOffset = localOffset + 30 + localName + localExtra;
		if (dataOffset > length || compressed > length - dataOffset) {
			return nil;
		}
		if (method == 0) {
			return [archive subdataWithRange:NSMakeRange(dataOffset, compressed)];
		}
		if (method == 8) {
			return NppZipInflate(bytes + dataOffset, compressed, uncompressed);
		}
		return nil;
	}
	return nil;
}

static NSInteger NppExcelColumn(NSString *reference) {
	NSInteger index = 0;
	BOOL letters = NO;
	for (NSUInteger cursor = 0; cursor < reference.length; cursor++) {
		unichar character = [reference characterAtIndex:cursor];
		if (character >= 'a' && character <= 'z') {
			character = (unichar)(character - 'a' + 'A');
		}
		if (character < 'A' || character > 'Z') {
			break;
		}
		letters = YES;
		index = index * 26 + (character - 'A' + 1);
	}
	return letters ? index - 1 : 0;
}

static NSString *NppExcelNumber(NSString *text) {
	if (text.length == 0) {
		return @"";
	}
	NSScanner *scanner = [NSScanner scannerWithString:text];
	double value = 0;
	if ([scanner scanDouble:&value] && scanner.isAtEnd) {
		if (fabs(value - round(value)) < 1e-8 && fabs(value) < 1e15) {
			return [NSString stringWithFormat:@"%.0f", value];
		}
		return [NSString stringWithFormat:@"%g", value];
	}
	return text;
}

@interface NppXlsxParser : NSObject <NSXMLParserDelegate>
@property (nonatomic, assign) BOOL sharedMode;
@property (nonatomic, assign) BOOL workbookMode;
@property (nonatomic, assign) BOOL relsMode;
@property (nonatomic, assign) BOOL truncated;
@property (nonatomic, strong) NSMutableArray<NSString *> *sharedStrings;
@property (nonatomic, strong) NSMutableArray<NSString *> *sheetNames;
@property (nonatomic, strong) NSMutableArray<NSString *> *sheetIds;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *targets;
@property (nonatomic, strong) NSMutableArray<NSMutableArray<NSString *> *> *rows;
@end

@implementation NppXlsxParser {
	NSMutableString *_text;
	NSMutableString *_shared;
	NSMutableString *_inline;
	NSMutableArray<NSString *> *_row;
	NSString *_cellType;
	NSString *_cellRef;
	BOOL _inCell;
	BOOL _inValue;
	BOOL _inText;
	NSInteger _width;
}

- (instancetype)init {
	self = [super init];
	if (self) {
		_text = [NSMutableString string];
		_sharedStrings = [NSMutableArray array];
		_sheetNames = [NSMutableArray array];
		_sheetIds = [NSMutableArray array];
		_targets = [NSMutableDictionary dictionary];
		_rows = [NSMutableArray array];
	}
	return self;
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified attributes:(NSDictionary<NSString *, NSString *> *)attributes {
	(void)parser;
	(void)uri;
	(void)qualified;
	if (self.truncated) {
		return;
	}
	if ([element isEqualToString:@"si"]) {
		_shared = [NSMutableString string];
	} else if ([element isEqualToString:@"row"]) {
		_row = [NSMutableArray array];
		_width = 0;
	} else if ([element isEqualToString:@"c"]) {
		_inCell = YES;
		_cellType = attributes[@"t"] ?: @"";
		_cellRef = attributes[@"r"] ?: @"";
		_inline = [NSMutableString string];
	} else if ([element isEqualToString:@"v"]) {
		_inValue = YES;
		_text = [NSMutableString string];
	} else if ([element isEqualToString:@"t"]) {
		_inText = YES;
		_text = [NSMutableString string];
	} else if ([element isEqualToString:@"sheet"]) {
		[_sheetNames addObject:attributes[@"name"] ?: @"Sheet"];
		[_sheetIds addObject:attributes[@"r:id"] ?: attributes[@"id"] ?: @""];
	} else if ([element isEqualToString:@"Relationship"]) {
		NSString *identifier = attributes[@"Id"] ?: @"";
		NSString *target = attributes[@"Target"] ?: @"";
		if (identifier.length && target.length) {
			_targets[identifier] = target;
		}
	}
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string {
	(void)parser;
	if (_inValue || _inText) {
		[_text appendString:string];
	}
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)element namespaceURI:(NSString *)uri qualifiedName:(NSString *)qualified {
	(void)parser;
	(void)uri;
	(void)qualified;
	if ([element isEqualToString:@"t"]) {
		if (_shared) {
			[_shared appendString:_text ?: @""];
		}
		if (_inCell) {
			[_inline appendString:_text ?: @""];
		}
		_inText = NO;
	} else if ([element isEqualToString:@"v"]) {
		_inValue = NO;
	} else if ([element isEqualToString:@"si"]) {
		[_sharedStrings addObject:_shared ?: @""];
		_shared = nil;
	} else if ([element isEqualToString:@"c"]) {
		NSInteger column = NppExcelColumn(_cellRef);
		NSString *value = @"";
		if ([_cellType isEqualToString:@"s"]) {
			NSInteger index = _text.integerValue;
			value = (index >= 0 && index < (NSInteger)_sharedStrings.count) ? _sharedStrings[index] : @"";
		} else if ([_cellType isEqualToString:@"b"]) {
			value = _text.integerValue ? @"TRUE" : @"FALSE";
		} else if ([_cellType isEqualToString:@"inlineStr"]) {
			value = _inline ?: @"";
		} else if ([_cellType isEqualToString:@"str"]) {
			value = _text.length ? _text : (_inline ?: @"");
		} else {
			value = NppExcelNumber(_text);
		}
		if (column >= kNppCsvMaxColumns) {
			self.truncated = YES;
		} else if (_row) {
			while ((NSInteger)_row.count <= column) {
				[_row addObject:@""];
			}
			_row[column] = value ?: @"";
			_width = MAX(_width, column + 1);
		}
		_inCell = NO;
		_text = [NSMutableString string];
	} else if ([element isEqualToString:@"row"]) {
		if (_row) {
			if ((NSInteger)_row.count > _width) {
				[_row removeObjectsInRange:NSMakeRange(_width, _row.count - _width)];
			}
			[_rows addObject:_row];
			if ((NSInteger)_rows.count >= kNppCsvMaxRows) {
				self.truncated = YES;
				[parser abortParsing];
			}
		}
		_row = nil;
	}
}

@end

static BOOL NppXlsxParse(NSData *data, NppXlsxParser *parser, NSString **error) {
	if (!data) {
		if (error) {
			*error = @"Could not open this Excel file.";
		}
		return NO;
	}
	NSXMLParser *xml = [[NSXMLParser alloc] initWithData:data];
	xml.delegate = parser;
	if (![xml parse] && !parser.truncated) {
		if (error) {
			*error = @"Could not open this Excel file.";
		}
		return NO;
	}
	return YES;
}

BOOL NppXlsxLoad(NSString *path, NSString *sheet, NSArray<NSString *> **sheetNames, NSArray<NSArray<NSString *> *> **rows, BOOL *truncated, NSString **error) {
	if (sheetNames) {
		*sheetNames = @[];
	}
	if (rows) {
		*rows = @[];
	}
	if (truncated) {
		*truncated = NO;
	}
	NSData *archive = path.length ? [NSData dataWithContentsOfFile:path] : nil;
	if (!archive) {
		if (error) {
			*error = @"Could not open this Excel file.";
		}
		return NO;
	}
	NppXlsxParser *book = [NppXlsxParser new];
	book.workbookMode = YES;
	if (!NppXlsxParse(NppZipExtract(archive, @"xl/workbook.xml"), book, error)) {
		return NO;
	}
	NppXlsxParser *rels = [NppXlsxParser new];
	rels.relsMode = YES;
	if (!NppXlsxParse(NppZipExtract(archive, @"xl/_rels/workbook.xml.rels"), rels, error)) {
		return NO;
	}
	if (book.sheetNames.count == 0) {
		if (error) {
			*error = @"Could not open this Excel file.";
		}
		return NO;
	}
	NSString *chosen = sheet.length ? sheet : book.sheetNames.firstObject;
	NSUInteger sheetIndex = [book.sheetNames indexOfObject:chosen];
	if (sheetIndex == NSNotFound) {
		sheetIndex = 0;
		chosen = book.sheetNames.firstObject;
	}
	NSString *identifier = sheetIndex < book.sheetIds.count ? book.sheetIds[sheetIndex] : @"";
	NSString *target = rels.targets[identifier] ?: @"";
	target = [target stringByReplacingOccurrencesOfString:@"\\" withString:@"/"];
	if ([target hasPrefix:@"/"]) {
		target = [target substringFromIndex:1];
	} else if (target.length && ![target hasPrefix:@"xl/"]) {
		target = [@"xl/" stringByAppendingString:target];
	}
	NSData *sharedData = NppZipExtract(archive, @"xl/sharedStrings.xml");
	NppXlsxParser *shared = [NppXlsxParser new];
	shared.sharedMode = YES;
	if (sharedData && !NppXlsxParse(sharedData, shared, error)) {
		return NO;
	}
	NppXlsxParser *grid = [NppXlsxParser new];
	grid.sharedStrings = shared.sharedStrings;
	if (!NppXlsxParse(NppZipExtract(archive, target), grid, error)) {
		return NO;
	}
	NSInteger width = 1;
	for (NSArray *row in grid.rows) {
		width = MAX(width, (NSInteger)row.count);
	}
	width = MIN(width, kNppCsvMaxColumns);
	NSMutableArray<NSArray<NSString *> *> *normalized = [NSMutableArray array];
	for (NSArray<NSString *> *source in grid.rows) {
		NSMutableArray<NSString *> *row = [NSMutableArray array];
		for (NSInteger index = 0; index < width; index++) {
			[row addObject:index < (NSInteger)source.count ? (source[index] ?: @"") : @""];
		}
		[normalized addObject:row];
	}
	if (sheetNames) {
		*sheetNames = book.sheetNames;
	}
	if (rows) {
		*rows = normalized;
	}
	if (truncated) {
		*truncated = grid.truncated;
	}
	return YES;
}

@interface NppCsvHeaderCell : NSTableHeaderCell
@property (nonatomic, assign) BOOL filtered;
@end

@implementation NppCsvHeaderCell
- (void)drawInteriorWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	cellFrame.size.width = MAX(16, cellFrame.size.width - 18);
	[super drawInteriorWithFrame:cellFrame inView:controlView];
}
- (void)drawWithFrame:(NSRect)cellFrame inView:(NSView *)controlView {
	[super drawWithFrame:cellFrame inView:controlView];
	NSImage *image = [NSImage imageWithSystemSymbolName:self.filtered ? @"line.3.horizontal.decrease.circle.fill" : @"line.3.horizontal.decrease" accessibilityDescription:NppL(@"Filter")];
	if (!image) {
		return;
	}
	image.size = NSMakeSize(11, 11);
	[image setTemplate:YES];
	[image drawInRect:NSMakeRect(NSMaxX(cellFrame) - 16, NSMidY(cellFrame) - 5, 11, 11) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:self.filtered ? 1 : 0.55];
}
@end

@interface NppFilterController : NSViewController <NSTableViewDataSource, NSTableViewDelegate>
- (instancetype)initWithValues:(NSArray<NSString *> *)values allowed:(NSSet<NSString *> *)allowed apply:(void (^)(NSSet<NSString *> *chosen, BOOL clear))apply;
@end

@implementation NppFilterController {
	NSArray<NSString *> *_values;
	NSMutableArray<NSString *> *_shown;
	NSMutableSet<NSString *> *_chosen;
	void (^_apply)(NSSet<NSString *> *, BOOL);
	NSTableView *_table;
	NSSearchField *_search;
}

- (instancetype)initWithValues:(NSArray<NSString *> *)values allowed:(NSSet<NSString *> *)allowed apply:(void (^)(NSSet<NSString *> *, BOOL))apply {
	self = [super initWithNibName:nil bundle:nil];
	if (self) {
		_values = values ?: @[];
		_shown = [_values mutableCopy];
		_chosen = allowed ? [allowed mutableCopy] : [NSMutableSet setWithArray:_values];
		_apply = [apply copy];
		NSView *root = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 300, 320)];
		_search = [[NSSearchField alloc] initWithFrame:NSMakeRect(8, 288, 284, 24)];
		_search.placeholderString = NppL(@"Filter values");
		_search.target = self;
		_search.action = @selector(searchChanged:);
		_search.delegate = (id<NSSearchFieldDelegate>)self;
		NSButton *all = [NSButton buttonWithTitle:NppL(@"All") target:self action:@selector(chooseAll:)];
		all.frame = NSMakeRect(8, 258, 80, 24);
		all.bezelStyle = NSBezelStyleRounded;
		NSButton *clear = [NSButton buttonWithTitle:NppL(@"Clear filter") target:self action:@selector(clearFilter:)];
		clear.frame = NSMakeRect(96, 258, 196, 24);
		clear.bezelStyle = NSBezelStyleRounded;
		NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(8, 8, 284, 244)];
		scroll.hasVerticalScroller = YES;
		_table = [[NSTableView alloc] initWithFrame:NSMakeRect(0, 0, 284, 244)];
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:@"value"];
		column.width = 220;
		[_table addTableColumn:column];
		_table.headerView = nil;
		_table.rowHeight = 22;
		_table.dataSource = self;
		_table.delegate = self;
		scroll.documentView = _table;
		[root addSubview:_search];
		[root addSubview:all];
		[root addSubview:clear];
		[root addSubview:scroll];
		self.view = root;
	}
	return self;
}

- (void)publishClear:(BOOL)clear {
	if (_apply) {
		_apply([_chosen copy], clear);
	}
}

- (void)chooseAll:(id)sender {
	(void)sender;
	[_chosen removeAllObjects];
	[_chosen addObjectsFromArray:_values];
	[_table reloadData];
	[self publishClear:YES];
}

- (void)clearFilter:(id)sender {
	(void)sender;
	[self chooseAll:sender];
}

- (void)searchChanged:(id)sender {
	(void)sender;
	NSString *query = _search.stringValue.lowercaseString ?: @"";
	[_shown removeAllObjects];
	for (NSString *value in _values) {
		NSString *label = value.length ? value : NppL(@"(empty)");
		if (query.length == 0 || [label.lowercaseString rangeOfString:query].location != NSNotFound) {
			[_shown addObject:value];
		}
	}
	[_table reloadData];
}

- (void)controlTextDidChange:(NSNotification *)notification {
	if (notification.object == _search) {
		[self searchChanged:nil];
	}
}

- (void)toggleValue:(NSButton *)sender {
	NSInteger row = sender.tag;
	if (row < 0 || row >= (NSInteger)_shown.count) {
		return;
	}
	NSString *value = _shown[row];
	if (sender.state == NSControlStateValueOn) {
		[_chosen addObject:value];
	} else {
		[_chosen removeObject:value];
	}
	[self publishClear:_chosen.count == _values.count];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	(void)tableView;
	return (NSInteger)_shown.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	(void)tableView;
	(void)tableColumn;
	NSButton *box = [tableView makeViewWithIdentifier:@"npp.filter.value" owner:self];
	if (!box) {
		box = [NSButton checkboxWithTitle:@"" target:self action:@selector(toggleValue:)];
		box.identifier = @"npp.filter.value";
		box.font = [NSFont systemFontOfSize:12];
	}
	NSString *value = _shown[row];
	box.title = value.length ? value : NppL(@"(empty)");
	box.state = [_chosen containsObject:value] ? NSControlStateValueOn : NSControlStateValueOff;
	box.tag = row;
	return box;
}

@end

@implementation NppCsvView {
	NSTableView *_table;
	NSScrollView *_scroll;
	NSButton *_textButton;
	NSTextField *_summary;
	NSMutableArray<NSMutableArray<NSString *> *> *_rows;
	NSArray<NSNumber *> *_visible;
	NSMutableDictionary<NSNumber *, NSSet<NSString *> *> *_filters;
	NSArray<NSString *> *_headers;
	NSPopUpButton *_sheetButton;
	NSPopover *_filterPopover;
	BOOL _usesHeader;
	BOOL _editable;
	BOOL _truncated;
	unichar _delimiter;
	BOOL _loading;
	BOOL _fits;
	CGFloat _zoom;
}

- (instancetype)initWithFrame:(NSRect)frameRect {
	self = [super initWithFrame:frameRect];
	if (self) {
		_delimiter = ',';
		_fits = YES;
		_editable = YES;
		_zoom = 1;
		_rows = [NSMutableArray array];
		_filters = [NSMutableDictionary dictionary];
		_textButton = [NSButton buttonWithTitle:NppL(@"As Text") target:self action:@selector(showText:)];
		_textButton.bezelStyle = NSBezelStyleRounded;
		_textButton.font = [NSFont systemFontOfSize:12];
		_summary = [NSTextField labelWithString:@""];
		_summary.font = [NSFont systemFontOfSize:12];
		_summary.textColor = NSColor.secondaryLabelColor;
		_summary.lineBreakMode = NSLineBreakByTruncatingTail;
		_sheetButton = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
		_sheetButton.hidden = YES;
		_sheetButton.font = [NSFont systemFontOfSize:12];
		_sheetButton.target = self;
		_sheetButton.action = @selector(chooseSheet:);
		_table = [[NSTableView alloc] initWithFrame:NSZeroRect];
		_table.dataSource = self;
		_table.delegate = self;
		_table.usesAlternatingRowBackgroundColors = YES;
		_table.columnAutoresizingStyle = NSTableViewUniformColumnAutoresizingStyle;
		_table.rowHeight = 22;
		_table.gridStyleMask = NSTableViewSolidHorizontalGridLineMask;
		_scroll = [[NSScrollView alloc] initWithFrame:NSZeroRect];
		_scroll.hasVerticalScroller = YES;
		_scroll.hasHorizontalScroller = YES;
		_scroll.autohidesScrollers = YES;
		_scroll.documentView = _table;
		_scroll.drawsBackground = NO;
		[self addSubview:_textButton];
		[self addSubview:_summary];
		[self addSubview:_sheetButton];
		[self addSubview:_scroll];
	}
	return self;
}

- (BOOL)fitsInTable {
	return _fits;
}

- (NSString *)selectedSheet {
	return _sheetButton.hidden ? @"" : _sheetButton.titleOfSelectedItem;
}

- (void)layout {
	[super layout];
	CGFloat width = NSWidth(self.bounds);
	CGFloat height = NSHeight(self.bounds);
	CGFloat x = 8;
	if (!_textButton.hidden) {
		[_textButton sizeToFit];
		CGFloat buttonWidth = MAX(88, ceil(NSWidth(_textButton.bounds)) + 18);
		_textButton.frame = NSMakeRect(8, height - 30, buttonWidth, 24);
		x = buttonWidth + 16;
	}
	CGFloat sheetWidth = 0;
	if (!_sheetButton.hidden) {
		sheetWidth = MIN(180, MAX(110, floor(width * 0.34)));
		_sheetButton.frame = NSMakeRect(width - sheetWidth - 8, height - 30, sheetWidth, 24);
	}
	_summary.frame = NSMakeRect(x, height - 28, MAX(40, width - x - sheetWidth - 16), 18);
	_scroll.frame = NSMakeRect(0, 0, width, MAX(0, height - 36));
}

- (void)showText:(id)sender {
	(void)sender;
	if (self.onShowText) {
		self.onShowText();
	}
}

- (void)loadCsv:(NSString *)csv {
	unichar delimiter = ',';
	NSArray<NSArray<NSString *> *> *parsed = NppParseCSV(csv ?: @"", &delimiter);
	_delimiter = delimiter;
	NSInteger columns = 1;
	for (NSArray<NSString *> *row in parsed) {
		columns = MAX(columns, (NSInteger)row.count);
	}
	_fits = parsed.count <= kNppCsvMaxRows && columns <= kNppCsvMaxColumns;
	[self loadRows:_fits ? parsed : @[] editable:YES sheets:nil selectedSheet:nil truncated:NO];
}

- (void)chooseSheet:(id)sender {
	(void)sender;
	if (_loading || !self.onSheet) {
		return;
	}
	self.onSheet(_sheetButton.titleOfSelectedItem ?: @"");
}

- (void)refreshSummary {
	if (!_fits) {
		_summary.stringValue = NppL(@"This CSV is too large for the table.");
		return;
	}
	NSInteger shown = _visible ? (NSInteger)_visible.count : (NSInteger)_rows.count;
	NSString *size = _visible
		? [NSString stringWithFormat:@"%ld / %ld × %ld", (long)shown, (long)_rows.count, (long)_headers.count]
		: [NSString stringWithFormat:@"%ld × %ld", (long)_rows.count, (long)_headers.count];
	if (_editable) {
		NSString *mark = _delimiter == '\t' ? @"tab" : [NSString stringWithFormat:@"%C", _delimiter];
		size = [size stringByAppendingFormat:@"    %@", mark];
	}
	if (_truncated) {
		size = [size stringByAppendingFormat:@"    %@", NppL(@"Showing the first rows of this sheet.")];
	}
	_summary.stringValue = size;
}

- (void)refreshHeaderMarks {
	for (NSTableColumn *column in _table.tableColumns) {
		NppCsvHeaderCell *cell = (NppCsvHeaderCell *)column.headerCell;
		if ([cell isKindOfClass:[NppCsvHeaderCell class]]) {
			cell.filtered = _filters[@(column.identifier.integerValue)] != nil;
		}
	}
	[_table.headerView setNeedsDisplay:YES];
}

- (NSInteger)sourceRow:(NSInteger)row {
	if (!_visible) {
		return row;
	}
	if (row < 0 || row >= (NSInteger)_visible.count) {
		return -1;
	}
	return _visible[row].integerValue;
}

- (void)rebuildVisibleRows {
	if (_filters.count == 0) {
		_visible = nil;
	} else {
		NSMutableArray<NSNumber *> *visible = [NSMutableArray array];
		[NppTableFilterIndexes(_rows, _filters) enumerateIndexesUsingBlock:^(NSUInteger index, BOOL *stop) {
			(void)stop;
			[visible addObject:@(index)];
		}];
		_visible = visible;
	}
	[_table reloadData];
	[self refreshSummary];
	[self refreshHeaderMarks];
}

- (void)loadRows:(NSArray<NSArray<NSString *> *> *)rows editable:(BOOL)editable sheets:(NSArray<NSString *> *)sheets selectedSheet:(NSString *)sheet truncated:(BOOL)truncated {
	_loading = YES;
	if (!editable || rows.count > 0) {
		_fits = YES;
	}
	[_filterPopover close];
	[_filters removeAllObjects];
	_visible = nil;
	_editable = editable;
	_truncated = truncated;
	_textButton.hidden = !editable;
	NSInteger columns = 1;
	for (NSArray<NSString *> *row in rows) {
		columns = MAX(columns, (NSInteger)row.count);
	}
	columns = MIN(columns, kNppCsvMaxColumns);
	_usesHeader = NppCsvLooksLikeHeader(rows.firstObject);
	NSArray<NSArray<NSString *> *> *body = rows ?: @[];
	if (_usesHeader) {
		_headers = rows.firstObject;
		body = rows.count > 1 ? [rows subarrayWithRange:NSMakeRange(1, rows.count - 1)] : @[];
	} else {
		NSMutableArray<NSString *> *headers = [NSMutableArray array];
		for (NSInteger index = 0; index < columns; index++) {
			[headers addObject:[NSString stringWithFormat:@"%ld", (long)(index + 1)]];
		}
		_headers = headers;
	}
	if ((NSInteger)_headers.count > columns) {
		_headers = [_headers subarrayWithRange:NSMakeRange(0, columns)];
	} else if ((NSInteger)_headers.count < columns) {
		NSMutableArray<NSString *> *padded = [_headers mutableCopy];
		while ((NSInteger)padded.count < columns) {
			[padded addObject:[NSString stringWithFormat:@"%ld", (long)padded.count + 1]];
		}
		_headers = padded;
	}
	_rows = [NSMutableArray array];
	for (NSArray<NSString *> *source in body) {
		NSMutableArray<NSString *> *row = [NSMutableArray array];
		for (NSInteger index = 0; index < (NSInteger)_headers.count; index++) {
			[row addObject:index < (NSInteger)source.count ? (source[index] ?: @"") : @""];
		}
		[_rows addObject:row];
	}
	while (_table.tableColumns.count > 0) {
		[_table removeTableColumn:_table.tableColumns.lastObject];
	}
	for (NSInteger index = 0; index < (NSInteger)_headers.count; index++) {
		NSTableColumn *column = [[NSTableColumn alloc] initWithIdentifier:[NSString stringWithFormat:@"%ld", (long)index]];
		NppCsvHeaderCell *header = [NppCsvHeaderCell new];
		column.headerCell = header;
		column.title = _headers[index];
		column.headerToolTip = NppL(@"Filter");
		column.width = 140;
		column.minWidth = 80;
		column.resizingMask = NSTableColumnUserResizingMask;
		[_table addTableColumn:column];
	}
	[_sheetButton removeAllItems];
	if (sheets.count > 1) {
		[_sheetButton addItemsWithTitles:sheets];
		if (sheet.length && [sheets containsObject:sheet]) {
			[_sheetButton selectItemWithTitle:sheet];
		}
		_sheetButton.hidden = NO;
	} else {
		_sheetButton.hidden = YES;
	}
	[self refreshSummary];
	[self refreshHeaderMarks];
	[self applyTableZoomPreservingWidths:NO];
	[_table reloadData];
	[self setNeedsLayout:YES];
	_loading = NO;
}

- (void)applyTableZoomPreservingWidths:(BOOL)preserveWidths {
	CGFloat zoom = _zoom > 0 ? _zoom : 1;
	CGFloat size = MAX(9, round(12 * zoom));
	NSFont *font = [NSFont systemFontOfSize:size];
	NSFont *chrome = [NSFont systemFontOfSize:MAX(11, size)];
	_table.rowHeight = MAX(18, round(22 * zoom));
	_summary.font = chrome;
	_textButton.font = chrome;
	_sheetButton.font = chrome;
	for (NSTableColumn *column in _table.tableColumns) {
		column.headerCell.font = font;
		column.minWidth = MAX(48, round(80 * zoom));
		if (!preserveWidths) {
			column.width = round(140 * zoom);
		}
	}
}

- (NSInteger)adjustZoom:(NSInteger)direction {
	CGFloat previous = _zoom > 0 ? _zoom : 1;
	CGFloat next = previous;
	if (direction > 0) {
		next = MIN(3, previous * 1.12);
	} else if (direction < 0) {
		next = MAX(0.55, previous / 1.12);
	} else {
		next = 1;
	}
	CGFloat ratio = previous > 0 ? next / previous : 1;
	_zoom = next;
	for (NSTableColumn *column in _table.tableColumns) {
		column.width = MAX(48, round(column.width * ratio));
	}
	[self applyTableZoomPreservingWidths:YES];
	[_table reloadData];
	[self setNeedsLayout:YES];
	return (NSInteger)llround(_zoom * 100.0);
}

- (NSString *)csvText {
	NSMutableArray<NSArray<NSString *> *> *rows = [NSMutableArray array];
	if (_usesHeader && _headers.count > 0) {
		[rows addObject:_headers];
	}
	[rows addObjectsFromArray:_rows];
	return NppFormatCSV(rows, _delimiter);
}

- (void)tableView:(NSTableView *)tableView mouseDownInHeaderOfTableColumn:(NSTableColumn *)tableColumn {
	(void)tableView;
	NSInteger column = tableColumn.identifier.integerValue;
	NSMutableOrderedSet<NSString *> *values = [NSMutableOrderedSet orderedSet];
	for (NSArray<NSString *> *row in _rows) {
		NSString *value = (column >= 0 && column < (NSInteger)row.count) ? (row[column] ?: @"") : @"";
		[values addObject:value];
	}
	NSArray<NSString *> *sorted = [values.array sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
	NSInteger shownCount = sorted.count;
	__weak NppCsvView *weakSelf = self;
	NppFilterController *controller = [[NppFilterController alloc] initWithValues:sorted allowed:_filters[@(column)] apply:^(NSSet<NSString *> *chosen, BOOL clear) {
		NppCsvView *strongSelf = weakSelf;
		if (!strongSelf || strongSelf->_loading) {
			return;
		}
		if (clear || chosen.count == (NSUInteger)shownCount) {
			[strongSelf->_filters removeObjectForKey:@(column)];
		} else {
			strongSelf->_filters[@(column)] = chosen ?: [NSSet set];
		}
		[strongSelf rebuildVisibleRows];
	}];
	[_filterPopover close];
	_filterPopover = [NSPopover new];
	_filterPopover.behavior = NSPopoverBehaviorTransient;
	_filterPopover.contentViewController = controller;
	NSInteger index = [_table columnWithIdentifier:tableColumn.identifier];
	if (index < 0) {
		return;
	}
	NSRect rect = [_table.headerView headerRectOfColumn:index];
	[_filterPopover showRelativeToRect:rect ofView:_table.headerView preferredEdge:NSRectEdgeMinY];
}

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView {
	(void)tableView;
	return _visible ? (NSInteger)_visible.count : (NSInteger)_rows.count;
}

- (NSView *)tableView:(NSTableView *)tableView viewForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row {
	(void)tableView;
	NSInteger column = tableColumn.identifier.integerValue;
	NSTextField *field = [tableView makeViewWithIdentifier:@"npp.csv.cell" owner:self];
	if (!field) {
		field = [[NSTextField alloc] initWithFrame:NSZeroRect];
		field.identifier = @"npp.csv.cell";
		field.bezeled = NO;
		field.drawsBackground = NO;
		field.editable = YES;
		field.selectable = YES;
		field.font = [NSFont systemFontOfSize:MAX(9, round(12 * (_zoom > 0 ? _zoom : 1)))];
		field.delegate = self;
		field.lineBreakMode = NSLineBreakByTruncatingTail;
	}
	NSInteger source = [self sourceRow:row];
	field.font = [NSFont systemFontOfSize:MAX(9, round(12 * (_zoom > 0 ? _zoom : 1)))];
	field.editable = _editable;
	field.tag = source * 100 + column;
	if (source >= 0 && source < (NSInteger)_rows.count && column >= 0 && column < (NSInteger)_rows[source].count) {
		field.stringValue = _rows[source][column];
	} else {
		field.stringValue = @"";
	}
	return field;
}

- (void)controlTextDidEndEditing:(NSNotification *)notification {
	if (_loading) {
		return;
	}
	NSTextField *field = notification.object;
	if (!_editable || ![field isKindOfClass:[NSTextField class]]) {
		return;
	}
	NSInteger row = field.tag / 100;
	NSInteger column = field.tag % 100;
	if (row < 0 || row >= (NSInteger)_rows.count || column < 0 || column >= (NSInteger)_rows[row].count) {
		return;
	}
	if ([_rows[row][column] isEqualToString:field.stringValue]) {
		return;
	}
	_rows[row][column] = field.stringValue ?: @"";
	if (self.onEdit) {
		self.onEdit([self csvText]);
	}
}

@end
