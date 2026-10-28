#!/bin/bash
# Builds build/MeetNotes.app from the Swift package.
#
#   scripts/build-app.sh                  # signed with your Developer ID if you have one, else ad-hoc
#   VERSION=0.3.0 scripts/build-app.sh    # sets the app version
#   SIGN_IDENTITY=- scripts/build-app.sh  # force an ad-hoc signature
set -euo pipefail
cd "$(dirname "$0")/.."

# SwiftPM from Xcode: Command Line Tools alone often ship a mismatched SDK.
export DEVELOPER_DIR="${DEVELOPER_DIR:-/Applications/Xcode.app/Contents/Developer}"
CONFIG="${CONFIG:-release}"

swift build -c "$CONFIG" --arch arm64 --product MeetNotes
BIN="$(swift build -c "$CONFIG" --arch arm64 --show-bin-path)"

APP=build/MeetNotes.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN/MeetNotes" "$APP/Contents/MacOS/"
cp Resources/Info.plist "$APP/Contents/"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
cp -R Resources/*.lproj "$APP/Contents/Resources/"
for bundle in "$BIN"/*.bundle; do
    [ -e "$bundle" ] && cp -R "$bundle" "$APP/Contents/Resources/"
done
# Sparkle ships as a framework next to the binary; apps load frameworks from Contents/Frameworks.
ditto "$BIN/Sparkle.framework" "$APP/Contents/Frameworks/Sparkle.framework"
install_name_tool -add_rpath @executable_path/../Frameworks "$APP/Contents/MacOS/MeetNotes"

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion $VERSION" "$APP/Contents/Info.plist"
fi

# A Developer ID certificate keeps macOS permissions across rebuilds; ad-hoc signatures lose them.
if [ -z "${SIGN_IDENTITY:-}" ]; then
    SIGN_IDENTITY="$(security find-identity -v -p codesigning | awk -F'"' '/Developer ID Application/ { print $2; exit }')"
fi
SIGN_IDENTITY="${SIGN_IDENTITY:--}"
# Notarization needs a secure timestamp; ad-hoc signatures cannot have one.
TIMESTAMP=--timestamp
[ "$SIGN_IDENTITY" = "-" ] && TIMESTAMP=--timestamp=none
sign() { codesign --force --options runtime $TIMESTAMP --sign "$SIGN_IDENTITY" "$@"; }

# Inside out, as Sparkle's documentation describes for apps signed outside Xcode.
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework"
sign "$SPARKLE/Versions/B/XPCServices/Installer.xpc"
sign --preserve-metadata=entitlements "$SPARKLE/Versions/B/XPCServices/Downloader.xpc"
sign "$SPARKLE/Versions/B/Autoupdate"
sign "$SPARKLE/Versions/B/Updater.app"
sign "$SPARKLE"
for bundle in "$APP"/Contents/Resources/*.bundle; do
    [ -e "$bundle" ] && sign "$bundle"
done
sign --entitlements Resources/MeetNotes.entitlements "$APP"

codesign --verify --strict --deep "$APP"
echo "$PWD/$APP"
