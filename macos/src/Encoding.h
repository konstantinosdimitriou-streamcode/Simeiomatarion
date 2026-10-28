#pragma once

#include <cstddef>
#include <cstdint>
#include <string>

// Line-ending values match Scintilla's SC_EOL_CRLF, SC_EOL_CR, and SC_EOL_LF.
// Values 0–4 stay stable for documents saved by earlier builds. Later ids are
// the rest of the Encoding menu and live in the table in Encoding.cc.
enum NppTextEncoding {
	kEncodingUTF8 = 0,
	kEncodingUTF8BOM = 1,
	kEncodingUTF16LE = 2,
	kEncodingUTF16BE = 3,
	kEncodingWindows1252 = 4,
	kEncodingANSI = 5
};

struct NppEncodingInfo {
	int id;
	const char *name;
	const char *group;
	const char *iconvName;
};

struct DecodedBuffer {
	std::string utf8;
	NppTextEncoding encoding;
	int eolMode;
};

bool Utf8IsValid(const uint8_t *data, size_t length);
int DetectEOL(const std::string &utf8);
DecodedBuffer DecodeBuffer(const uint8_t *data, size_t length);
bool DecodeBufferAs(const uint8_t *data, size_t length, NppTextEncoding encoding, DecodedBuffer *decoded, std::string *error);
bool EncodeBuffer(const std::string &utf8, NppTextEncoding encoding, std::string *out, std::string *error);
const char *EncodingName(NppTextEncoding encoding);
int NppEncodingCount();
const NppEncodingInfo *NppEncodingAt(int index);
const NppEncodingInfo *NppEncodingById(int id);
int NppEncodingIdNamed(const char *name);
