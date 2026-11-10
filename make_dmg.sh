#!/bin/zsh
# Packs Dewdrop.app into dist/Dewdrop-<version>.dmg with a drag-to-Applications window.
# Needs Dewdrop.app (run ./build.sh first). Uses Finder scripting to lay out the window, so macOS may ask once
# whether Terminal/your shell may control Finder.
set -e
cd "$(dirname "$0")"
APP="Dewdrop.app"
VERSION=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$APP/Contents/Info.plist")
VOL="Dewdrop"
OUT="dist/Dewdrop-$VERSION.dmg"
WORK=$(mktemp -d)
mkdir -p dist

# staging folder: the app, a shortcut to /Applications, and the window background
STAGE="$WORK/stage"
mkdir -p "$STAGE/.background"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
swiftc -O tools/make_dmg_background.swift -o "$WORK/mkbg"
"$WORK/mkbg" "$WORK/bg"
tiffutil -cathidpicheck "$WORK/bg/background.png" "$WORK/bg/background@2x.png" -out "$STAGE/.background/background.tiff" 2>/dev/null
cp Resources/AppIcon.icns "$STAGE/.VolumeIcon.icns"

# writable image -> lay out the Finder window -> compress
hdiutil detach "/Volumes/$VOL" -force >/dev/null 2>&1 || true
RW="$WORK/rw.dmg"
hdiutil create -srcfolder "$STAGE" -volname "$VOL" -fs HFS+ -format UDRW -size 60m "$RW" >/dev/null
hdiutil attach "$RW" -readwrite -noverify -noautoopen -mountpoint "/Volumes/$VOL" >/dev/null
SetFile -a C "/Volumes/$VOL" 2>/dev/null || true       # use the custom volume icon

if ! timeout 60 osascript <<OSA
tell application "Finder"
  tell disk "$VOL"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    set the bounds of container window to {200, 120, 860, 542}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP" of container window to {165, 190}
    set position of item "Applications" of container window to {495, 190}
    close
    open
    update without registering applications
    delay 2
    close
  end tell
end tell
OSA
then
  echo "note: Finder styling skipped (macOS has not allowed this shell to control Finder). The DMG still works; allow it and re-run for the styled window."
fi

sync
hdiutil detach "/Volumes/$VOL" >/dev/null 2>&1 || hdiutil detach "/Volumes/$VOL" -force >/dev/null
rm -f "$OUT"
hdiutil convert "$RW" -format UDZO -imagekey zlib-level=9 -o "$OUT" >/dev/null
codesign --force --sign - "$OUT" >/dev/null 2>&1 || true
rm -rf "$WORK"
echo "Wrote $OUT"
shasum -a 256 "$OUT"
