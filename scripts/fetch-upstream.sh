#!/bin/sh
# Fetch the third-party source tree into upstream/ at the pinned tag and verify
# the commit. See NOTICE for the copyright notices of that tree.
# Usage: scripts/fetch-upstream.sh [target-dir]   (default: <repo>/upstream)
set -eu

URL="https://github.com/notepad-plus-plus/notepad-plus-plus.git"
TAG="v8.9.8.1"
COMMIT="dd40fe45598791e9aa38f3aeb200e10fb3d6338a"

root=$(cd "$(dirname "$0")/.." && pwd)
dest=${1:-"$root/upstream"}

if [ -e "$dest" ]; then
	if [ -d "$dest/.git" ]; then
		have=$(git -C "$dest" rev-parse HEAD)
		if [ "$have" = "$COMMIT" ]; then
			echo "upstream: $dest already at $COMMIT"
			exit 0
		fi
		echo "upstream: $dest is at $have, expected $COMMIT. Move it away and run again." >&2
		exit 1
	fi
	if [ -f "$dest/scintilla/src/Editor.cxx" ]; then
		echo "upstream: $dest exists (not a git checkout), using it as is"
		exit 0
	fi
	echo "upstream: $dest exists but does not look like the source tree" >&2
	exit 1
fi

tmp="$dest.partial.$$"
trap 'rm -rf "$tmp"' EXIT INT TERM
echo "upstream: cloning $TAG into $dest"
git -c advice.detachedHead=false clone --quiet --depth 1 --branch "$TAG" "$URL" "$tmp"
have=$(git -C "$tmp" rev-parse HEAD)
if [ "$have" != "$COMMIT" ]; then
	echo "upstream: tag $TAG resolved to $have, expected $COMMIT. Refusing to use it." >&2
	exit 1
fi
mv "$tmp" "$dest"
trap - EXIT INT TERM
echo "upstream: OK at $COMMIT"
