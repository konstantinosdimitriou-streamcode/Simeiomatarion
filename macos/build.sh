#!/bin/sh
set -eu
cd "$(dirname "$0")"
jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
# FLAVOR=developer (default) or FLAVOR=appstore, e.g. `FLAVOR=appstore ./build.sh`.
flavor=${FLAVOR:-developer}
case "$flavor" in
	developer) out=build ;;
	appstore) out=build/appstore ;;
	*) echo "FLAVOR must be developer or appstore" >&2; exit 1 ;;
esac
make -j"$jobs" FLAVOR="$flavor" test
lipo -info "$out/Simeiomatarion.app/Contents/MacOS/Simeiomatarion"
file "$out/Simeiomatarion.app/Contents/MacOS/Simeiomatarion"
plist="$out/Simeiomatarion.app/Contents/Info.plist"
want_version=$(tr -d '[:space:]' < ../VERSION)
want_build=$(tr -d '[:space:]' < ../BUILD_NUMBER)
got_version=$(plutil -extract CFBundleShortVersionString raw "$plist")
got_build=$(plutil -extract CFBundleVersion raw "$plist")
if [ "$got_version" != "$want_version" ] || [ "$got_build" != "$want_build" ]; then
	echo "version check FAILED: bundle has $got_version ($got_build), expected $want_version ($want_build)" >&2
	exit 1
fi
echo "version $got_version ($got_build), flavour $flavor"
codesign -d --entitlements - "$out/Simeiomatarion.app" 2>/dev/null | grep -o "com.apple.security[a-z.-]*" | sort -u || true
