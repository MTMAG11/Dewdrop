#!/bin/zsh
# Builds Dewdrop.app and packs it as dist/Dewdrop-<version>.dmg and .zip (ad-hoc signed, not notarized),
# then writes dist/SHA256SUMS.txt.
set -e
cd "$(dirname "$0")"
./build.sh
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Dewdrop.app/Contents/Info.plist)
./make_dmg.sh
rm -f "dist/Dewdrop-$VERSION.zip"
ditto -c -k --keepParent Dewdrop.app "dist/Dewdrop-$VERSION.zip"
( cd dist && shasum -a 256 "Dewdrop-$VERSION.dmg" "Dewdrop-$VERSION.zip" > SHA256SUMS.txt && cat SHA256SUMS.txt )
