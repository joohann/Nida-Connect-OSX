#!/usr/bin/env bash
# Builds a shareable DMG: build/<executableName>-<version>.dmg (with a link to /Applications).
# Notarises only when config.json has a Developer ID and a notaryProfile.
set -euo pipefail
cd "$(dirname "$0")/.."

source scripts/lib.sh
APP_NAME=$(cfg appName)
EXE=$(cfg executableName)
VERSION=$(cfg version)
IDENTITY=$(cfg signing.identity)
PROFILE=$(cfg signing.notaryProfile)

scripts/build.sh
[[ -n "$(cfg update.publicKey)" ]] || { echo "update.publicKey is missing in config.json; no release without a key." >&2; exit 1; }
APP="build/$APP_NAME.app"
DMG="build/$EXE-$VERSION.dmg"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Background: drawn by Icon/DMGBackground, 1x and 2x in one TIFF. The generator also prints the layout.
mkdir -p "$STAGE/.background"
swiftc -O Icon/DMGBackground/main.swift -o build/dmg-background
eval "$(build/dmg-background "$APP_NAME" build/dmg-background.png build/dmg-background@2x.png)"
tiffutil -cathidpicheck build/dmg-background.png build/dmg-background@2x.png -out "$STAGE/.background/background.tiff" 2>/dev/null

# Read-write image first, so Finder can store the window layout; then compress.
RW="build/$EXE-rw.dmg"
rm -f "$DMG" "$RW"
hdiutil create -quiet -volname "$APP_NAME" -srcfolder "$STAGE" -fs HFS+ -format UDRW -size 60m "$RW"
MOUNT=$(hdiutil attach -readwrite -noverify -noautoopen "$RW" | awk -F'\t' '/\/Volumes\//{print $NF; exit}')
DISK=$(basename "$MOUNT")
osascript <<OSA
tell application "Finder"
  tell disk "$DISK"
    open
    set current view of container window to icon view
    set toolbar visible of container window to false
    set statusbar visible of container window to false
    -- Bounds include the title bar (32 pt), the background fills the area below it.
    set the bounds of container window to {200, 120, 200 + $DMG_WIDTH, 120 + $DMG_HEIGHT + 32}
    set opts to the icon view options of container window
    set arrangement of opts to not arranged
    set icon size of opts to 128
    set text size of opts to 13
    set background picture of opts to file ".background:background.tiff"
    set position of item "$APP_NAME.app" of container window to {$APP_X, $APP_Y}
    set position of item "Applications" of container window to {$FOLDER_X, $FOLDER_Y}
    update without registering applications
    delay 1
    close
  end tell
end tell
OSA
chflags hidden "$MOUNT/.background"
sync
hdiutil detach -quiet "$MOUNT"
hdiutil convert -quiet "$RW" -format UDZO -imagekey zlib-level=9 -o "$DMG"
rm -f "$RW"

if [[ "$IDENTITY" == "Developer ID"* ]]; then
  codesign --force --timestamp --sign "$IDENTITY" "$DMG"
  if [[ -n "$PROFILE" ]]; then
    xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
    xcrun stapler staple "$DMG"
  fi
fi

echo "Package: $DMG ($(du -h "$DMG" | cut -f1))"

# Appcast for Sparkle: the DMG is signed with the EdDSA key in the Keychain, then the feed itself.
SPARKLE=$(sparkle_dir)
ACCOUNT=$(cfg update.keyAccount)
ENCLOSURE=$("$SPARKLE/bin/sign_update" --account "$ACCOUNT" "$DMG")
NOTES=$(awk -v v="## $VERSION" '$0 == v {on=1; next} /^## / {on=0} on' CHANGELOG.md)
[[ -n "$NOTES" ]] || { echo "CHANGELOG.md has no section '## $VERSION'." >&2; exit 1; }
cat > appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>$APP_NAME</title>
    <item>
      <title>$APP_NAME $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>$(cfg minimumMacOS)</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>$(expand "$(cfg update.releaseNotesUrl)" "$VERSION")</sparkle:fullReleaseNotesLink>
      <description sparkle:format="markdown"><![CDATA[$NOTES
]]></description>
      <enclosure url="$(expand "$(cfg update.downloadUrl)" "$VERSION")" type="application/octet-stream" $ENCLOSURE/>
    </item>
  </channel>
</rss>
XML
"$SPARKLE/bin/sign_update" --account "$ACCOUNT" appcast.xml
echo "Appcast: appcast.xml. Publish the GitHub release with the DMG first, then push appcast.xml."
[[ "$IDENTITY" != "Developer ID"* ]] && echo "Note: not notarised. Recipients must allow the app once."
