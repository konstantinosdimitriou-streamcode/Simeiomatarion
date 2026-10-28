#!/bin/sh
set -eu
cd "$(dirname "$0")"
jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
make -j"$jobs" test
lipo -info "build/Simeiomatarion.app/Contents/MacOS/NotepadPlusPlus"
file "build/Simeiomatarion.app/Contents/MacOS/NotepadPlusPlus"
plist="build/Simeiomatarion.app/Contents/Info.plist"
want_version=$(tr -d '[:space:]' < ../VERSION)
want_build=$(tr -d '[:space:]' < ../BUILD_NUMBER)
got_version=$(plutil -extract CFBundleShortVersionString raw "$plist")
got_build=$(plutil -extract CFBundleVersion raw "$plist")
if [ "$got_version" != "$want_version" ] || [ "$got_build" != "$want_build" ]; then
	echo "version check FAILED: bundle has $got_version ($got_build), expected $want_version ($want_build)" >&2
	exit 1
fi
echo "version $got_version ($got_build)"
