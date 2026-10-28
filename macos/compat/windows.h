/* Minimal stand-in so the upstream LexUser.cxx can compile on macOS.
   The lexer includes windows.h for the MSVC _itoa helper only. */
#pragma once

#include <stdio.h>

static inline char *_itoa(int value, char *buffer, int radix) {
	const char *format = radix == 16 ? "%x" : "%d";
	snprintf(buffer, 12, format, value);
	return buffer;
}
