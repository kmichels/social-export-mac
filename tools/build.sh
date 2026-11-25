#!/bin/bash
# Generate the Xcode project and build a signed Release app into "build/Social Export.app".
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build
xcodegen generate --quiet
xcodebuild -scheme SocialExport -configuration Release -derivedDataPath build/dd build > build/xcodebuild.log 2>&1 || {
  grep -E "error:" build/xcodebuild.log | sort -u | head -20
  echo "BUILD FAILED (full log: build/xcodebuild.log)"
  exit 1
}
rm -rf "build/Social Export.app"
cp -R "build/dd/Build/Products/Release/Social Export.app" build/

# Sparkle is embedded by SPM, but its inner helpers come out ad-hoc signed, which notarization
# rejects. Re-sign them inside-out with Developer ID + hardened runtime, keeping their own
# entitlements, then re-seal the framework and the app. Never --deep.
APP="build/Social Export.app"
IDENTITY="Developer ID Application"
FW="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
resign() { codesign --force --options runtime --timestamp --preserve-metadata=entitlements,requirements,identifier -s "$IDENTITY" "$1"; }
for inner in "$FW/XPCServices/Installer.xpc" "$FW/XPCServices/Downloader.xpc" "$FW/Autoupdate" "$FW/Updater.app"; do
  [ -e "$inner" ] || { echo "build: expected Sparkle bundle missing: $inner (framework layout changed?)" >&2; exit 1; }
  resign "$inner"
done
resign "$APP/Contents/Frameworks/Sparkle.framework"
resign "$APP"
codesign --verify --deep --strict "$APP"
echo "$PWD/$APP"
