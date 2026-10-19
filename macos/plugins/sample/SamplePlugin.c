#include "NppMacPlugin.h"

#include <ctype.h>
#include <string.h>

static void UppercaseSelection(NppMacHost *host, void *user) {
	(void)user;
	char buffer[1024 * 256];
	int length = host->get_selection(host, buffer, (int)sizeof buffer);
	if (length < 0) {
		host->set_status(host, "Selection is too large for the sample plugin.");
		return;
	}
	for (int index = 0; index < length; index++) {
		buffer[index] = (char)toupper((unsigned char)buffer[index]);
	}
	host->replace_selection(host, buffer);
	host->set_status(host, "Sample plugin uppercased the selection.");
}

static const NppMacCommand kCommands[] = {
	{"Uppercase Selection", UppercaseSelection, 0}
};

static int OnLoad(NppMacHost *host, const NppMacCommand **commands, int *count) {
	(void)host;
	*commands = kCommands;
	*count = 1;
	return 0;
}

static const NppMacPlugin kPlugin = {
	NPP_MAC_PLUGIN_ABI,
	"Sample",
	"1.0",
	OnLoad,
	0
};

const NppMacPlugin *NppMacPluginEntry(void) {
	return &kPlugin;
}
