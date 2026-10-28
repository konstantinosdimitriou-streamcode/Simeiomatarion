#pragma once

#import <Foundation/Foundation.h>

// App Store flavour: built with -DSIMEIO_APP_STORE=1 (make FLAVOR=appstore).
#ifndef SIMEIO_APP_STORE
#define SIMEIO_APP_STORE 0
#endif

// YES when the process runs inside the App Sandbox.
BOOL NppIsSandboxed(void);

// Starts security-scoped access for path, using a bookmark stored for the path
// or for one of its parent folders. Returns YES when the path is accessible.
// Outside the sandbox this does nothing and returns YES.
BOOL NppBeginAccess(NSString *path);

// Stores a security-scoped bookmark for path while the app has access to it
// (after an open panel, a save panel, a drop, or a Finder open). Outside the
// sandbox this does nothing.
void NppRememberAccess(NSString *path);

