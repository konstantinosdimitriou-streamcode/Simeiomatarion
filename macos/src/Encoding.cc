#include "Encoding.h"

#include <iconv.h>

#include <cerrno>
#include <cstring>

#include <CoreFoundation/CoreFoundation.h>

namespace {

const NppEncodingInfo kEncodings[] = {
	{kEncodingANSI, "ANSI", "", "CP1252"},
	{kEncodingUTF8, "UTF-8", "", nullptr},
	{kEncodingUTF8BOM, "UTF-8-BOM", "", nullptr},
	{kEncodingUTF16BE, "UTF-16 BE BOM", "", nullptr},
	{kEncodingUTF16LE, "UTF-16 LE BOM", "", nullptr},

	{10, "ISO 8859-6", "Arabic", "ISO-8859-6"},
	{11, "Windows-1256", "Arabic", "CP1256"},

	{20, "ISO 8859-4", "Baltic", "ISO-8859-4"},
	{21, "ISO 8859-13", "Baltic", "ISO-8859-13"},
	{22, "OEM 775", "Baltic", "CP775"},
	{23, "Windows-1257", "Baltic", "CP1257"},

	{30, "ISO 8859-14", "Celtic", "ISO-8859-14"},

	{40, "ISO 8859-5", "Cyrillic", "ISO-8859-5"},
	{41, "KOI8-R", "Cyrillic", "KOI8-R"},
	{42, "KOI8-U", "Cyrillic", "KOI8-U"},
	{43, "Macintosh", "Cyrillic", "CP10007"},
	{44, "OEM 855", "Cyrillic", "CP855"},
	{45, "OEM 866", "Cyrillic", "CP866"},
	{46, "Windows-1251", "Cyrillic", "CP1251"},

	{50, "OEM 852", "Central European", "CP852"},
	{51, "Windows-1250", "Central European", "CP1250"},

	{60, "Big5 (Traditional)", "Chinese", "BIG5"},
	{61, "GB2312 (Simplified)", "Chinese", "GB2312"},

	{70, "ISO 8859-2", "Eastern European", "ISO-8859-2"},

	{80, "ISO 8859-7", "Greek", "ISO-8859-7"},
	{81, "OEM 737", "Greek", "CP737"},
	{82, "OEM 869", "Greek", "CP869"},
	{83, "Windows-1253", "Greek", "CP1253"},

	{90, "ISO 8859-8", "Hebrew", "ISO-8859-8"},
	{91, "OEM 862", "Hebrew", "CP862"},
	{92, "Windows-1255", "Hebrew", "CP1255"},

	{100, "Shift-JIS", "Japanese", "SHIFT_JIS"},

	{110, "Windows 949", "Korean", "CP949"},
	{111, "EUC-KR", "Korean", "EUC-KR"},

	{120, "OEM 861 : Icelandic", "North European", "CP861"},
	{121, "OEM 865 : Nordic", "North European", "CP865"},

	{130, "TIS-620", "Thai", "TIS-620"},

	{140, "ISO 8859-3", "Turkish", "ISO-8859-3"},
	{141, "ISO 8859-9", "Turkish", "ISO-8859-9"},
	{142, "OEM 857", "Turkish", "CP857"},
	{143, "Windows-1254", "Turkish", "CP1254"},

	{150, "ISO 8859-1", "Western European", "ISO-8859-1"},
	{151, "ISO 8859-15", "Western European", "ISO-8859-15"},
	{152, "OEM 850", "Western European", "CP850"},
	{153, "OEM 858", "Western European", "CP858"},
	{154, "OEM 860 : Portuguese", "Western European", "CP860"},
	{155, "OEM 863 : French", "Western European", "CP863"},
	{156, "OEM-US : CP437", "Western European", "CP437"},
	{kEncodingWindows1252, "Windows-1252", "Western European", "CP1252"},

	{160, "Windows-1258", "Vietnamese", "CP1258"},
};

bool Continuation(uint8_t byte) {
	return (byte & 0xC0) == 0x80;
}

std::string CfToUtf8(CFStringRef string) {
	if (!string) {
		return {};
	}
	const char *fast = CFStringGetCStringPtr(string, kCFStringEncodingUTF8);
	if (fast) {
		return fast;
	}
	CFIndex length = CFStringGetLength(string);
	CFIndex maxBytes = CFStringGetMaximumSizeForEncoding(length, kCFStringEncodingUTF8) + 1;
	std::string out(static_cast<size_t>(maxBytes), '\0');
	if (!CFStringGetCString(string, out.data(), maxBytes, kCFStringEncodingUTF8)) {
		return {};
	}
	out.resize(strlen(out.c_str()));
	return out;
}

bool ConvertWithIconv(const char *to, const char *from, const char *input, size_t inputLength, std::string *out, std::string *error) {
	iconv_t converter = iconv_open(to, from);
	if (converter == (iconv_t)-1) {
		if (error) {
			*error = "This Mac cannot convert that encoding.";
		}
		return false;
	}
	std::string buffer(inputLength * 4 + 32, '\0');
	char *in = const_cast<char *>(input);
	size_t inLeft = inputLength;
	char *dest = buffer.data();
	size_t destLeft = buffer.size();
	while (true) {
		size_t converted = iconv(converter, inLeft ? &in : nullptr, inLeft ? &inLeft : nullptr, &dest, &destLeft);
		if (converted != static_cast<size_t>(-1) && inLeft == 0) {
			iconv(converter, nullptr, nullptr, &dest, &destLeft);
			break;
		}
		if (errno == E2BIG) {
			size_t used = buffer.size() - destLeft;
			buffer.resize(buffer.size() * 2 + 32);
			dest = buffer.data() + used;
			destLeft = buffer.size() - used;
			continue;
		}
		iconv_close(converter);
		if (error) {
			*error = "Some characters cannot be represented in the selected encoding.";
		}
		return false;
	}
	iconv_close(converter);
	buffer.resize(buffer.size() - destLeft);
	*out = std::move(buffer);
	return true;
}

bool EncodeWithCharset(const char *charset, const std::string &utf8, std::string *out, std::string *error) {
	std::string translit = std::string(charset) + "//TRANSLIT";
	if (ConvertWithIconv(translit.c_str(), "UTF-8", utf8.data(), utf8.size(), out, error)) {
		return true;
	}
	return ConvertWithIconv(charset, "UTF-8", utf8.data(), utf8.size(), out, error);
}

bool EncodeUtf16(const std::string &utf8, bool little, std::string *out, std::string *error) {
	CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, reinterpret_cast<const UInt8 *>(utf8.data()), static_cast<CFIndex>(utf8.size()), kCFStringEncodingUTF8, false);
	if (!string) {
		if (error) {
			*error = "The buffer is not valid UTF-8.";
		}
		return false;
	}
	CFStringEncoding wide = little ? kCFStringEncodingUTF16LE : kCFStringEncodingUTF16BE;
	CFIndex bytes = 0;
	CFStringGetBytes(string, CFRangeMake(0, CFStringGetLength(string)), wide, 0, false, nullptr, 0, &bytes);
	std::string payload(static_cast<size_t>(bytes), '\0');
	CFStringGetBytes(string, CFRangeMake(0, CFStringGetLength(string)), wide, 0, false, reinterpret_cast<UInt8 *>(payload.data()), bytes, nullptr);
	CFRelease(string);
	*out = (little ? std::string("\xFF\xFE", 2) : std::string("\xFE\xFF", 2)) + payload;
	return true;
}

bool DecodeUtf16(const uint8_t *data, size_t length, bool little, std::string *utf8, std::string *error) {
	size_t offset = 0;
	if (length >= 2) {
		bool le = data[0] == 0xFF && data[1] == 0xFE;
		bool be = data[0] == 0xFE && data[1] == 0xFF;
		if ((little && le) || (!little && be)) {
			offset = 2;
		}
	}
	if ((length - offset) % 2 != 0) {
		if (error) {
			*error = "The file is not valid UTF-16.";
		}
		return false;
	}
	CFStringEncoding wide = little ? kCFStringEncodingUTF16LE : kCFStringEncodingUTF16BE;
	CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, data + offset, static_cast<CFIndex>(length - offset), wide, false);
	if (!string && length > offset) {
		if (error) {
			*error = "The file is not valid UTF-16.";
		}
		return false;
	}
	*utf8 = CfToUtf8(string);
	if (string) {
		CFRelease(string);
	}
	return true;
}

} // namespace

int NppEncodingCount() {
	return static_cast<int>(sizeof kEncodings / sizeof kEncodings[0]);
}

const NppEncodingInfo *NppEncodingAt(int index) {
	if (index < 0 || index >= NppEncodingCount()) {
		return nullptr;
	}
	return &kEncodings[index];
}

const NppEncodingInfo *NppEncodingById(int id) {
	for (const NppEncodingInfo &info : kEncodings) {
		if (info.id == id) {
			return &info;
		}
	}
	return nullptr;
}

int NppEncodingIdNamed(const char *name) {
	if (!name) {
		return -1;
	}
	for (const NppEncodingInfo &info : kEncodings) {
		if (strcmp(info.name, name) == 0) {
			return info.id;
		}
	}
	return -1;
}

bool Utf8IsValid(const uint8_t *data, size_t length) {
	size_t index = 0;
	while (index < length) {
		uint8_t lead = data[index];
		if (lead <= 0x7F) {
			index++;
			continue;
		}
		size_t need = 0;
		uint32_t minValue = 0;
		if ((lead & 0xE0) == 0xC0) {
			need = 2;
			minValue = 0x80;
		} else if ((lead & 0xF0) == 0xE0) {
			need = 3;
			minValue = 0x800;
		} else if ((lead & 0xF8) == 0xF0) {
			need = 4;
			minValue = 0x10000;
		} else {
			return false;
		}
		if (index + need > length) {
			return false;
		}
		uint32_t code = lead & ((1u << (7 - need)) - 1u);
		for (size_t extra = 1; extra < need; extra++) {
			if (!Continuation(data[index + extra])) {
				return false;
			}
			code = (code << 6) | (data[index + extra] & 0x3F);
		}
		if (code < minValue || code > 0x10FFFF || (code >= 0xD800 && code <= 0xDFFF)) {
			return false;
		}
		index += need;
	}
	return true;
}

int DetectEOL(const std::string &utf8) {
	int crlf = 0;
	int cr = 0;
	int lf = 0;
	for (size_t index = 0; index < utf8.size(); index++) {
		if (utf8[index] == '\r') {
			if (index + 1 < utf8.size() && utf8[index + 1] == '\n') {
				crlf++;
				index++;
			} else {
				cr++;
			}
		} else if (utf8[index] == '\n') {
			lf++;
		}
	}
	if (crlf >= lf && crlf >= cr && crlf > 0) {
		return 0;
	}
	if (cr > lf && cr > 0) {
		return 1;
	}
	if (lf > 0) {
		return 2;
	}
	return 2;
}

DecodedBuffer DecodeBuffer(const uint8_t *data, size_t length) {
	DecodedBuffer decoded;
	decoded.encoding = kEncodingUTF8;
	decoded.eolMode = 2;
	if (!data || length == 0) {
		return decoded;
	}

	if (length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
		decoded.encoding = kEncodingUTF8BOM;
		if (Utf8IsValid(data + 3, length - 3)) {
			decoded.utf8.assign(reinterpret_cast<const char *>(data + 3), length - 3);
		}
		decoded.eolMode = DetectEOL(decoded.utf8);
		return decoded;
	}

	CFStringEncoding wide = kCFStringEncodingInvalidId;
	if (length >= 2 && data[0] == 0xFF && data[1] == 0xFE) {
		decoded.encoding = kEncodingUTF16LE;
		wide = kCFStringEncodingUTF16LE;
	} else if (length >= 2 && data[0] == 0xFE && data[1] == 0xFF) {
		decoded.encoding = kEncodingUTF16BE;
		wide = kCFStringEncodingUTF16BE;
	}
	if (wide != kCFStringEncodingInvalidId) {
		const uint8_t *payload = data + 2;
		size_t payloadLength = length - 2;
		CFStringRef string = CFStringCreateWithBytes(kCFAllocatorDefault, payload, static_cast<CFIndex>(payloadLength), wide, false);
		decoded.utf8 = CfToUtf8(string);
		if (string) {
			CFRelease(string);
		}
		decoded.eolMode = DetectEOL(decoded.utf8);
		return decoded;
	}

	if (Utf8IsValid(data, length)) {
		decoded.encoding = kEncodingUTF8;
		decoded.utf8.assign(reinterpret_cast<const char *>(data), length);
		decoded.eolMode = DetectEOL(decoded.utf8);
		return decoded;
	}

	decoded.encoding = kEncodingWindows1252;
	std::string converted;
	std::string error;
	if (ConvertWithIconv("UTF-8", "CP1252", reinterpret_cast<const char *>(data), length, &converted, &error)) {
		decoded.utf8 = std::move(converted);
	} else {
		decoded.utf8.assign(reinterpret_cast<const char *>(data), length);
	}
	decoded.eolMode = DetectEOL(decoded.utf8);
	return decoded;
}

bool DecodeBufferAs(const uint8_t *data, size_t length, NppTextEncoding encoding, DecodedBuffer *decoded, std::string *error) {
	if (!decoded) {
		return false;
	}
	decoded->encoding = encoding;
	decoded->eolMode = 2;
	decoded->utf8.clear();
	if (!data) {
		data = reinterpret_cast<const uint8_t *>("");
		length = 0;
	}
	const NppEncodingInfo *info = NppEncodingById(encoding);
	if (!info) {
		if (error) {
			*error = "Unknown encoding.";
		}
		return false;
	}
	if (encoding == kEncodingUTF8 || encoding == kEncodingUTF8BOM) {
		size_t offset = 0;
		if (length >= 3 && data[0] == 0xEF && data[1] == 0xBB && data[2] == 0xBF) {
			offset = 3;
		}
		if (!Utf8IsValid(data + offset, length - offset)) {
			if (error) {
				*error = "The file is not valid UTF-8.";
			}
			return false;
		}
		decoded->utf8.assign(reinterpret_cast<const char *>(data + offset), length - offset);
		decoded->eolMode = DetectEOL(decoded->utf8);
		return true;
	}
	if (encoding == kEncodingUTF16LE || encoding == kEncodingUTF16BE) {
		if (!DecodeUtf16(data, length, encoding == kEncodingUTF16LE, &decoded->utf8, error)) {
			return false;
		}
		decoded->eolMode = DetectEOL(decoded->utf8);
		return true;
	}
	if (!info->iconvName) {
		if (error) {
			*error = "This encoding cannot be decoded.";
		}
		return false;
	}
	if (!ConvertWithIconv("UTF-8", info->iconvName, reinterpret_cast<const char *>(data), length, &decoded->utf8, error)) {
		return false;
	}
	decoded->eolMode = DetectEOL(decoded->utf8);
	return true;
}

bool EncodeBuffer(const std::string &utf8, NppTextEncoding encoding, std::string *out, std::string *error) {
	if (!out) {
		return false;
	}
	if (encoding == kEncodingUTF8) {
		*out = utf8;
		return true;
	}
	if (encoding == kEncodingUTF8BOM) {
		*out = std::string("\xEF\xBB\xBF", 3) + utf8;
		return true;
	}
	if (encoding == kEncodingUTF16LE || encoding == kEncodingUTF16BE) {
		return EncodeUtf16(utf8, encoding == kEncodingUTF16LE, out, error);
	}
	const NppEncodingInfo *info = NppEncodingById(encoding);
	if (!info || !info->iconvName) {
		*out = utf8;
		return true;
	}
	return EncodeWithCharset(info->iconvName, utf8, out, error);
}

const char *EncodingName(NppTextEncoding encoding) {
	const NppEncodingInfo *info = NppEncodingById(encoding);
	return info ? info->name : "UTF-8";
}
