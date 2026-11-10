#!/bin/zsh
# Builds "Dewdrop.app" next to this script. No Xcode project needed.
set -e
cd "$(dirname "$0")"
VERSION="1.0.0"
APP="Dewdrop.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cp Resources/dewdrop-helper.pl Resources/com.rishaan.dewdrop.helper.plist "$APP/Contents/Resources/"
swiftc -O -swift-version 5 Sources/*.swift -o "$APP/Contents/MacOS/Dewdrop"
cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>Dewdrop</string>
  <key>CFBundleIdentifier</key><string>com.rishaan.dewdrop</string>
  <key>CFBundleExecutable</key><string>Dewdrop</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
</dict></plist>
EOF
codesign --force --sign - "$APP"
echo "Built: $PWD/$APP"

# ./build.sh install  -> replace the copy in /Applications and relaunch (the app also replaces any older running copy)
if [[ "$1" == "install" ]]; then
  pkill -x Dewdrop 2>/dev/null || true
  sleep 1
  rm -rf "/Applications/$APP"
  cp -R "$APP" "/Applications/$APP"
  open "/Applications/$APP"
  echo "Installed and launched /Applications/$APP"
fi
