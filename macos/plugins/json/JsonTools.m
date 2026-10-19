#import "NppMacPlugin.h"

#import <Foundation/Foundation.h>

static char *CopyRange(NppMacHost *host, int wholeDocument, int *length) {
	int (*read)(NppMacHost *, char *, int) = wholeDocument ? host->get_text : host->get_selection;
	int size = read(host, 0, 0);
	if (size < 0) {
		size = 0;
	}
	char *buffer = malloc((size_t)size + 1);
	if (!buffer) {
		return 0;
	}
	*length = read(host, buffer, size + 1);
	if (*length < 0) {
		*length = 0;
	}
	buffer[*length] = 0;
	return buffer;
}

static BOOL SpaceByte(unsigned char byte) {
	return byte == ' ' || byte == '\t' || byte == '\n' || byte == '\r';
}

static NSString *FormatJSON(NSString *source, BOOL pretty, NSString **error) {
	NSData *data = [source dataUsingEncoding:NSUTF8StringEncoding];
	if (!data) {
		*error = @"The text is not UTF-8.";
		return nil;
	}
	NSError *parseError = nil;
	id parsed = [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingAllowFragments error:&parseError];
	if (!parsed) {
		*error = parseError.localizedDescription ?: @"Invalid JSON.";
		return nil;
	}
	const unsigned char *bytes = data.bytes;
	NSUInteger length = data.length;
	NSMutableData *out = [NSMutableData data];
	int depth = 0;
	BOOL inString = NO;
	BOOL escape = NO;
	for (NSUInteger index = 0; index < length; index++) {
		unsigned char byte = bytes[index];
		if (inString) {
			[out appendBytes:&byte length:1];
			if (escape) {
				escape = NO;
			} else if (byte == '\\') {
				escape = YES;
			} else if (byte == '"') {
				inString = NO;
			}
			continue;
		}
		if (SpaceByte(byte)) {
			continue;
		}
		if (byte == '"') {
			inString = YES;
			[out appendBytes:&byte length:1];
			continue;
		}
		if (byte == '{' || byte == '[') {
			[out appendBytes:&byte length:1];
			depth++;
			NSUInteger next = index + 1;
			while (next < length && SpaceByte(bytes[next])) {
				next++;
			}
			unsigned char closer = byte == '{' ? '}' : ']';
			if (pretty && (next >= length || bytes[next] != closer)) {
				[out appendBytes:"\n" length:1];
				for (int level = 0; level < depth; level++) {
					[out appendBytes:"\t" length:1];
				}
			}
			continue;
		}
		if (byte == '}' || byte == ']') {
			depth = depth > 0 ? depth - 1 : 0;
			const unsigned char *existing = out.bytes;
			unsigned char previous = out.length ? existing[out.length - 1] : 0;
			if (pretty && previous != '{' && previous != '[') {
				[out appendBytes:"\n" length:1];
				for (int level = 0; level < depth; level++) {
					[out appendBytes:"\t" length:1];
				}
			}
			[out appendBytes:&byte length:1];
			continue;
		}
		if (byte == ',') {
			[out appendBytes:&byte length:1];
			if (pretty) {
				[out appendBytes:"\n" length:1];
				for (int level = 0; level < depth; level++) {
					[out appendBytes:"\t" length:1];
				}
			}
			continue;
		}
		if (byte == ':') {
			[out appendBytes:pretty ? ": " : ":" length:pretty ? 2 : 1];
			continue;
		}
		[out appendBytes:&byte length:1];
	}
	if (pretty && out.length && ((const unsigned char *)out.bytes)[out.length - 1] != '\n') {
		[out appendBytes:"\n" length:1];
	}
	return [[NSString alloc] initWithData:out encoding:NSUTF8StringEncoding] ?: @"";
}

static void ApplyJSON(NppMacHost *host, BOOL pretty, const char *done) {
	int selectionLength = host->get_selection(host, 0, 0);
	int whole = selectionLength <= 0;
	if (whole && (!host->get_text || !host->set_text)) {
		host->set_status(host, "Select the JSON to format.");
		return;
	}
	int length = 0;
	char *text = CopyRange(host, whole, &length);
	if (!text) {
		return;
	}
	NSString *source = [[NSString alloc] initWithBytes:text length:(NSUInteger)length encoding:NSUTF8StringEncoding];
	free(text);
	if (source.length == 0) {
		host->set_status(host, "There is no JSON to format.");
		return;
	}
	NSString *error = nil;
	NSString *formatted = FormatJSON(source, pretty, &error);
	if (!formatted) {
		host->set_status(host, error.UTF8String ?: "Invalid JSON.");
		return;
	}
	if (whole) {
		host->set_text(host, formatted.UTF8String ?: "");
	} else {
		host->replace_selection(host, formatted.UTF8String ?: "");
	}
	host->set_status(host, done);
}

static void Format(NppMacHost *host, void *user) {
	(void)user;
	ApplyJSON(host, YES, "JSON formatted.");
}

static void Compress(NppMacHost *host, void *user) {
	(void)user;
	ApplyJSON(host, NO, "JSON compressed.");
}

static const NppMacCommand kCommands[] = {
	{"Format JSON", Format, 0},
	{"Compress JSON", Compress, 0}
};

static int OnLoad(NppMacHost *host, const NppMacCommand **commands, int *count) {
	(void)host;
	*commands = kCommands;
	*count = 2;
	return 0;
}

static const NppMacPlugin kPlugin = {NPP_MAC_PLUGIN_ABI, "JSON Viewer", "1.0", OnLoad, 0};

const NppMacPlugin *NppMacPluginEntry(void) {
	return &kPlugin;
}
