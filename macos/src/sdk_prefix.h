#import <Cocoa/Cocoa.h>

// The macOS 27 SDK no longer declares the 10.13 AppKit version constant that
// Scintilla's Cocoa port still compares against. 1561 is the historical value.
#ifndef NSAppKitVersionNumber10_13
#define NSAppKitVersionNumber10_13 1561.0
#endif
