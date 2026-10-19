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

static void ToHex(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	static const char hex[] = "0123456789ABCDEF";
	char *out = (char *)malloc((size_t)length * 3 + 1);
	int written = 0;
	for (int index = 0; index < length; index++) {
		unsigned char byte = (unsigned char)text[index];
		if (written) {
			out[written++] = ' ';
		}
		out[written++] = hex[byte >> 4];
		out[written++] = hex[byte & 15];
	}
	out[written] = 0;
	host->replace_selection(host, out);
	host->set_status(host, "Converted to hexadecimal.");
	free(out);
	free(text);
}

static void FromHex(NppMacHost *host, void *user) {
	(void)user;
	int length = 0;
	char *text = TakeSelection(host, &length);
	if (!text) {
		return;
	}
	char *out = (char *)malloc((size_t)length + 1);
	int written = 0;
	int high = -1;
	for (int index = 0; index < length; index++) {
		unsigned char byte = (unsigned char)text[index];
		if (isspace(byte) || byte == ',' || byte == ':') {
			continue;
		}
		if (byte == '0' && index + 1 < length && (text[index + 1] == 'x' || text[index + 1] == 'X') && high < 0) {
			index++;
			continue;
		}
		int value = HexValue(byte);
		if (value < 0) {
			host->set_status(host, "The selection is not hexadecimal.");
			free(out);
			free(text);
			return;
		}
		if (high < 0) {
			high = value;
		} else {
			out[written++] = (char)((high << 4) | value);
			high = -1;
		}
	}
	if (high >= 0) {
		host->set_status(host, "The selection is not hexadecimal.");
		free(out);
		free(text);
		return;
	}
	out[written] = 0;
	host->replace_selection(host, out);
	host->set_status(host, "Converted from hexadecimal.");
	free(out);
	free(text);
}

static const NppMacCommand kCommands[] = {
	{"ASCII to HEX", ToHex, 0},
	{"HEX to ASCII", FromHex, 0}
};

static int OnLoad(NppMacHost *host, const NppMacCommand **commands, int *count) {
	(void)host;
	*commands = kCommands;
	*count = 2;
	return 0;
}

static const NppMacPlugin kPlugin = {NPP_MAC_PLUGIN_ABI, "Converter", "1.0", OnLoad, 0};

const NppMacPlugin *NppMacPluginEntry(void) {
	return &kPlugin;
}
