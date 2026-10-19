#include "NppMacPlugin.h"

#include <ctype.h>
#include <stdlib.h>
#include <string.h>

static char *TakeSelection(NppMacHost *host, int *length) {
	int size = host->get_selection(host, 0, 0);
	if (size <= 0) {
		host->set_status(host, "Select the text to convert.");
		return 0;
	}
	char *buffer = (char *)malloc((size_t)size + 1);
	if (!buffer) {
		return 0;
	}
	*length = host->get_selection(host, buffer, size + 1);
	return buffer;
}

static char *Base64Encode(const unsigned char *data, int length) {
	static const char alphabet[] = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
	int outLength = 4 * ((length + 2) / 3);
	char *out = (char *)malloc((size_t)outLength + 1);
	int written = 0;
	for (int index = 0; index < length; index += 3) {
		int remain = length - index;
		unsigned int value = ((unsigned int)data[index]) << 16;
		if (remain > 1) {
			value |= ((unsigned int)data[index + 1]) << 8;
		}
		if (remain > 2) {
			value |= data[index + 2];
		}
		out[written++] = alphabet[(value >> 18) & 63];
		out[written++] = alphabet[(value >> 12) & 63];
		out[written++] = remain > 1 ? alphabet[(value >> 6) & 63] : '=';
		out[written++] = remain > 2 ? alphabet[value & 63] : '=';
	}
	out[written] = 0;
	return out;
}

static int DecodeDigit(unsigned char digit) {
	if (digit >= 'A' && digit <= 'Z') {
		return digit - 'A';
	}
	if (digit >= 'a' && digit <= 'z') {
		return digit - 'a' + 26;
	}
	if (digit >= '0' && digit <= '9') {
		return digit - '0' + 52;
	}
	if (digit == '+') {
		return 62;
	}
	if (digit == '/') {
		return 63;
	}
	return -1;
}

static char *Base64Decode(const char *text, int length, int *outLength) {
	char *out = (char *)malloc((size_t)length + 1);
	int written = 0;
	int value = 0;
	int bits = 0;
	for (int index = 0; index < length; index++) {
		unsigned char digit = (unsigned char)text[index];
		if (isspace(digit) || digit == '=') {
			continue;
		}
		int decoded = DecodeDigit(digit);
		if (decoded < 0) {
			free(out);
			return 0;
		}
		value = (value << 6) | decoded;
		bits += 6;
		if (bits >= 8) {
			bits -= 8;
			out[written++] = (char)((value >> bits) & 0xFF);
		}
	}
	out[written] = 0;
	*outLength = written;
	return out;
}

static int Unreserved(unsigned char byte) {
	return isalnum(byte) || byte == '-' || byte == '_' || byte == '.' || byte == '~';
}

static char *URLEncode(const unsigned char *data, int length) {
	char *out = (char *)malloc((size_t)length * 3 + 1);
	int written = 0;
	for (int index = 0; index < length; index++) {
		unsigned char byte = data[index];
		if (Unreserved(byte)) {
			out[written++] = (char)byte;
		} else {
			static const char hex[] = "0123456789ABCDEF";
			out[written++] = '%';
			out[written++] = hex[byte >> 4];
			out[written++] = hex[byte & 15];
		}
	}
	out[written] = 0;
	return out;
}

static int HexValue(unsigned char digit) {
	if (digit >= '0' && digit <= '9') {
		return digit - '0';
	}
	if (digit >= 'A' && digit <= 'F') {
		return digit - 'A' + 10;
	}
	if (digit >= 'a' && digit <= 'f') {
		return digit - 'a' + 10;
	}
	return -1;
}

static char *URLDecode(const char *text, int length, int *ok) {
	char *out = (char *)malloc((size_t)length + 1);
	int written = 0;
	*ok = 1;
	for (int index = 0; index < length; index++) {
		unsigned char byte = (unsigned char)text[index];
		if (byte == '%' && index + 2 < length) {
			int high = HexValue((unsigned char)text[index + 1]);
			int low = HexValue((unsigned char)text[index + 2]);
			if (high < 0 || low < 0) {
				*ok = 0;
				free(out);
				return 0;
			}
			out[written++] = (char)((high << 4) | low);
			index += 2;
		} else if (byte == '+') {
			out[written++] = ' ';
		} else {
			out[written++] = (char)byte;
		}
	}
	out[written] = 0;
	return out;
}

static void EncodeBase64(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	char *encoded = Base64Encode((const unsigned char *)text, length);
	host->replace_selection(host, encoded);
	host->set_status(host, "Base64 encoded.");
	free(encoded);
	free(text);
}

static void DecodeBase64(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	int decodedLength = 0;
	char *decoded = Base64Decode(text, length, &decodedLength);
	if (!decoded) {
		host->set_status(host, "The selection is not valid Base64.");
		free(text);
		return;
	}
	decoded[decodedLength] = 0;
	host->replace_selection(host, decoded);
	host->set_status(host, "Base64 decoded.");
	free(decoded);
	free(text);
}

static void EncodeURL(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	char *encoded = URLEncode((const unsigned char *)text, length);
	host->replace_selection(host, encoded);
	host->set_status(host, "URL encoded.");
	free(encoded);
	free(text);
}

static void DecodeURL(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	int ok = 0;
	char *decoded = URLDecode(text, length, &ok);
	if (!ok) {
		host->set_status(host, "The selection is not a valid URL encoding.");
		free(text);
		return;
	}
	host->replace_selection(host, decoded);
	host->set_status(host, "URL decoded.");
	free(decoded);
	free(text);
}

static const NppMacCommand kCommands[] = {
	{"Base64 Encode", EncodeBase64, 0},
	{"Base64 Decode", DecodeBase64, 0},
	{"URL Encode", EncodeURL, 0},
	{"URL Decode", DecodeURL, 0}
};

static int OnLoad(NppMacHost *host, const NppMacCommand **commands, int *count) {
	(void)host;
	*commands = kCommands;
	*count = 4;
	return 0;
}

static const NppMacPlugin kPlugin = {NPP_MAC_PLUGIN_ABI, "MIME Tools", "1.0", OnLoad, 0};

const NppMacPlugin *NppMacPluginEntry(void) {
	return &kPlugin;
}
