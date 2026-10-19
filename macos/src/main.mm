#import "AppDelegate.h"

int main(int argc, const char *argv[]) {
	(void)argc;
	(void)argv;
	@autoreleasepool {
		NSApplication *application = [NSApplication sharedApplication];
		[application setActivationPolicy:NSApplicationActivationPolicyRegular];
		static AppDelegate *delegate;
		delegate = [AppDelegate new];
		application.delegate = delegate;
		[application run];
	}
	return 0;
}
