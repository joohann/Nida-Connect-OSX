#!/usr/bin/env bash
# Bouwt de .app uit config.json (enige plek voor naam, bundle-id en versie).
#   scripts/build.sh            -> build/<appName>.app
#   scripts/build.sh install    -> ook kopiëren naar /Applications en starten
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib.sh
APP_NAME=$(cfg appName)
EXE=$(cfg executableName)
BUNDLE_ID=$(cfg bundleId)
VERSION=$(cfg version)
MIN_OS=$(cfg minimumMacOS)
PUBLIC_KEY=$(cfg update.publicKey)
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister

# .env afleiden uit config.json, zodat er één bron is.
cat > .env <<ENV
# Gegenereerd uit config.json door scripts/build.sh. Niet handmatig wijzigen.
APP_NAME=$APP_NAME
EXECUTABLE_NAME=$EXE
BUNDLE_ID=$BUNDLE_ID
VERSION=$VERSION
ENV

scripts/i18n.sh || echo "Let op: vertalingen niet compleet (valt terug op EN)."

APP="build/$APP_NAME.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Sparkle (updates), pinned in config.json and checked against its SHA-256.
SPARKLE=$(sparkle_dir)
ditto "$SPARKLE/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
# The XPC services are only needed by sandboxed apps.
rm -rf "$APP/Contents/Frameworks/Sparkle.framework/Versions/B/XPCServices" \
       "$APP/Contents/Frameworks/Sparkle.framework/XPCServices"

# Universal binary: Apple silicon + Intel.
for ARCH in arm64 x86_64; do
  swiftc -O -swift-version 5 -parse-as-library \
    -target "$ARCH-apple-macos$MIN_OS" \
    -F "$SPARKLE" -framework Sparkle -Xlinker -rpath -Xlinker @executable_path/../Frameworks \
    Sources/*.swift -o "build/$EXE-$ARCH"
done
lipo -create "build/$EXE-arm64" "build/$EXE-x86_64" -output "$APP/Contents/MacOS/$EXE"
rm -f "build/$EXE-arm64" "build/$EXE-x86_64"

# App icon, drawn on the macOS icon grid (Icon/IconDrawing.swift) with the mosque from Nida's icon.
swiftc -swift-version 5 Icon/IconDrawing.swift Icon/Generate/main.swift -o build/icon-generator
rm -rf build/AppIcon.iconset
build/icon-generator Icon/AppIcon-source.png build/AppIcon.iconset build/AppIcon-1024.png
iconutil -c icns build/AppIcon.iconset -o "$APP/Contents/Resources/AppIcon.icns"

cp config.json "$APP/Contents/Resources/"
cp -R Resources/*.lproj Resources/*.html "$APP/Contents/Resources/"
LANGS=$(ls -d Resources/*.lproj | xargs -n1 basename | sed 's/\.lproj//' | sed 's/.*/<string>&<\/string>/' | tr -d '\n')

# Updates only when an EdDSA key is configured; without one the app never trusts a feed.
SPARKLE_KEYS=""
if [[ -n "$PUBLIC_KEY" ]]; then
  SPARKLE_KEYS="<key>SUFeedURL</key><string>$(expand "$(cfg update.feedUrl)")</string>
  <key>SUPublicEDKey</key><string>$PUBLIC_KEY</string>
  <key>SUEnableAutomaticChecks</key><true/>
  <key>SURequireSignedFeed</key><true/>
  <key>SUVerifyUpdateBeforeExtraction</key><true/>
  <key>SUAutomaticallyUpdate</key><false/>
  <key>SUScheduledCheckInterval</key><integer>$(cfg update.checkSeconds)</integer>"
else
  echo "Let op: update.publicKey in config.json is leeg, de updater staat uit in deze build."
fi

cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleName</key><string>$APP_NAME</string>
  <key>CFBundleDisplayName</key><string>$APP_NAME</string>
  <key>CFBundleExecutable</key><string>$EXE</string>
  <key>CFBundleIdentifier</key><string>$BUNDLE_ID</string>
  <key>CFBundleShortVersionString</key><string>$VERSION</string>
  <key>CFBundleVersion</key><string>$VERSION</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleDevelopmentRegion</key><string>en</string>
  <key>CFBundleLocalizations</key><array>$LANGS</array>
  <key>LSMinimumSystemVersion</key><string>$MIN_OS</string>
  <key>LSUIElement</key><true/>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSAppTransportSecurity</key><dict><key>NSAllowsLocalNetworking</key><true/></dict>
  <key>NSLocationUsageDescription</key><string>Shows the prayer times for where you are when you are away from home.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Shows the prayer times for where you are when you are away from home.</string>
  <key>NSBonjourServices</key><array><string>_home-assistant._tcp</string></array>
  <key>NSLocalNetworkUsageDescription</key><string>Finds Home Assistant on your network and reads the prayer times from Nida.</string>
  $SPARKLE_KEYS
</dict></plist>
PLIST

IDENTITY=$(cfg signing.identity)
OPTS=()
# Hardened runtime and a secure timestamp only with an Apple Developer ID (needed for notarisation).
# A local, self-signed identity (see README) just gives the app a stable signature for the Keychain.
[[ "$IDENTITY" == "Developer ID"* ]] && OPTS=(--options runtime --timestamp)
# Sign inside out: Sparkle's helpers, the framework (changed above), then the app.
FW="$APP/Contents/Frameworks/Sparkle.framework"
for ITEM in "$FW/Versions/B/Autoupdate" "$FW/Versions/B/Updater.app" "$FW" "$APP"; do
  codesign --force ${OPTS[@]+"${OPTS[@]}"} --sign "$IDENTITY" "$ITEM"
done
touch "$APP"
"$LSREGISTER" -f "$APP" 2>/dev/null || true
echo "Gebouwd: $APP ($(du -sh "$APP" | cut -f1))"

if [[ "${1:-}" == install ]]; then
  pkill -x "$EXE" 2>/dev/null || true
  rm -rf "/Applications/$APP_NAME.app"
  cp -R "$APP" /Applications/
  touch "/Applications/$APP_NAME.app"
  "$LSREGISTER" -f "/Applications/$APP_NAME.app" 2>/dev/null || true
  open "/Applications/$APP_NAME.app"
  echo "Geïnstalleerd in /Applications en gestart."
fi
