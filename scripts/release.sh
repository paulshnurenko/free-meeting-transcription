#!/bin/bash
# Builds a release: dist/MeetNotes-<version>.dmg and dist/appcast.xml
#
#   scripts/release.sh 0.2.0
#
# Then publish both files as assets of a GitHub release tagged v<version> (not a pre-release:
# Sparkle reads the appcast from the latest release).
#
# One-time setup on the release machine:
#   - a "Developer ID Application" certificate in the keychain
#   - a notarytool profile:
#       xcrun notarytool store-credentials meetnotes --apple-id <apple id> --team-id <team id>
#   - the Sparkle signing key in the keychain (scripts/sparkle-tool generate_keys --account meetnotes);
#     its public half is SUPublicEDKey in Resources/Info.plist
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: scripts/release.sh <version>, e.g. 0.2.0}"
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
NOTARY_PROFILE="${NOTARY_PROFILE:-meetnotes}"
REPO="paulshnurenko/free-meeting-transcription"

SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
[ -n "$SIGN_IDENTITY" ] || { echo "No Developer ID Application certificate in the keychain." >&2; exit 1; }
xcrun notarytool history --keychain-profile "$NOTARY_PROFILE" >/dev/null 2>&1 \
    || { echo "No notarytool profile \"$NOTARY_PROFILE\"." >&2; exit 1; }
export SIGN_IDENTITY

VERSION="$VERSION" scripts/build-app.sh

mkdir -p dist
DMG="dist/MeetNotes-$VERSION.dmg"
STAGING="$(mktemp -d)"
cp -R build/MeetNotes.app "$STAGING/"
ln -s /Applications "$STAGING/Applications"
rm -f "$DMG"
hdiutil create -volname "MeetNotes $VERSION" -srcfolder "$STAGING" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGING"
codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"

echo "Notarizing (a few minutes)…"
xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$DMG"

# Appcast with this release only: Sparkle needs just the newest version.
SIGNATURE="$(scripts/sparkle-tool sign_update --account meetnotes "$DMG")"  # sparkle:edSignature="…" length="…"
cat > dist/appcast.xml <<XML
<?xml version="1.0" encoding="utf-8"?>
<rss version="2.0" xmlns:sparkle="http://www.andymatuschak.org/xml-namespaces/sparkle">
  <channel>
    <title>MeetNotes</title>
    <item>
      <title>MeetNotes $VERSION</title>
      <pubDate>$(LC_ALL=C date -u "+%a, %d %b %Y %H:%M:%S +0000")</pubDate>
      <sparkle:version>$VERSION</sparkle:version>
      <sparkle:shortVersionString>$VERSION</sparkle:shortVersionString>
      <sparkle:minimumSystemVersion>15.0</sparkle:minimumSystemVersion>
      <sparkle:fullReleaseNotesLink>https://github.com/$REPO/releases/tag/v$VERSION</sparkle:fullReleaseNotesLink>
      <enclosure url="https://github.com/$REPO/releases/download/v$VERSION/MeetNotes-$VERSION.dmg"
                 type="application/octet-stream" $SIGNATURE />
    </item>
  </channel>
</rss>
XML

shasum -a 256 "$DMG"
echo "$PWD/$DMG"
echo "$PWD/dist/appcast.xml"
