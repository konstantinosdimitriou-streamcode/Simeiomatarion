#import "TextTools.h"

NSString *NppFormatByteCount(unsigned long long bytes, NSString *unit) {
	NSString *mode = unit.lowercaseString ?: @"auto";
	BOOL forceMB = [mode isEqualToString:@"mb"];
	BOOL forceKB = [mode isEqualToString:@"kb"];
	if (forceMB || (!forceKB && bytes >= 1024ull * 1024ull)) {
		double mb = bytes / 1048576.0;
		if (mb < 10.0) {
			return [NSString stringWithFormat:@"%.2f MB", mb];
		}
		if (mb < 100.0) {
			return [NSString stringWithFormat:@"%.1f MB", mb];
		}
		return [NSString stringWithFormat:@"%.0f MB", mb];
	}
	double kb = bytes / 1024.0;
	if (kb < 10.0) {
		return [NSString stringWithFormat:@"%.1f KB", kb];
	}
	return [NSString stringWithFormat:@"%.0f KB", kb];
}

NSString *NppPrettyJSON(NSString *text, NSString **error) {
	NSData *data = [text dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) {
		if (error) {
			*error = @"Invalid JSON.";
		}
		return nil;
	}
	NSError *parseError = nil;
	id object = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingFragmentsAllowed error:&parseError];
	if (!object) {
		if (error) {
			*error = parseError.localizedDescription ?: @"Invalid JSON.";
		}
		return nil;
	}
	NSData *pretty = [NSJSONSerialization dataWithJSONObject:object options:NSJSONWritingPrettyPrinted error:&parseError];
	if (!pretty) {
		if (error) {
			*error = parseError.localizedDescription ?: @"Invalid JSON.";
		}
		return nil;
	}
	NSString *result = [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
	if (result.length && ![result hasSuffix:@"\n"]) {
		result = [result stringByAppendingString:@"\n"];
	}
	return result;
}

NSString *NppPrettyXML(NSString *text, NSString **error) {
	NSError *parseError = nil;
	NSXMLDocument *document = [[NSXMLDocument alloc] initWithXMLString:text ?: @"" options:NSXMLNodePreserveWhitespace error:&parseError];
	if (!document) {
		if (error) {
			*error = parseError.localizedDescription ?: @"Invalid XML.";
		}
		return nil;
	}
	document.characterEncoding = @"UTF-8";
	NSString *pretty = [document XMLStringWithOptions:NSXMLNodePrettyPrint];
	if (pretty.length && ![pretty hasSuffix:@"\n"]) {
		pretty = [pretty stringByAppendingString:@"\n"];
	}
	return pretty;
}
