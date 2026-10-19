#pragma once

#ifdef __cplusplus
extern "C" {
#endif

#define NPP_MAC_PLUGIN_ABI 1

typedef struct NppMacHost NppMacHost;

typedef struct NppMacCommand {
	const char *title;
	void (*perform)(NppMacHost *host, void *user);
	void *user;
} NppMacCommand;

struct NppMacHost {
	int abi;
	void *ctx;
	int (*get_selection)(NppMacHost *host, char *buffer, int bufferLength);
	void (*replace_selection)(NppMacHost *host, const char *utf8);
	void (*insert_text)(NppMacHost *host, const char *utf8);
	const char *(*current_path)(NppMacHost *host);
	void (*set_status)(NppMacHost *host, const char *text);
	int (*get_text)(NppMacHost *host, char *buffer, int bufferLength);
	void (*set_text)(NppMacHost *host, const char *utf8);
};

typedef struct NppMacPlugin {
	int abi;
	const char *name;
	const char *version;
	int (*on_load)(NppMacHost *host, const NppMacCommand **commands, int *count);
	void (*on_unload)(NppMacHost *host);
} NppMacPlugin;

typedef const NppMacPlugin *(*NppMacPluginEntryFn)(void);

#ifdef __cplusplus
}
#endif
