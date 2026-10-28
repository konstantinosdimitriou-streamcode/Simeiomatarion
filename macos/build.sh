#!/bin/sh
set -eu
cd "$(dirname "$0")"
jobs=$(sysctl -n hw.ncpu 2>/dev/null || echo 8)
make -j"$jobs" test
lipo -info "build/Simeiomatarion.app/Contents/MacOS/NotepadPlusPlus"
file "build/Simeiomatarion.app/Contents/MacOS/NotepadPlusPlus"
