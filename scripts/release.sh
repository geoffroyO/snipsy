#!/bin/bash
# Builds Snipsy, signs it with Developer ID, notarizes the app and the DMG, and publishes a GitHub release.
#
#   scripts/release.sh            # version comes from MARKETING_VERSION in the Xcode project
#
# One-time setup:
#   - a "Developer ID Application" certificate for the team (Xcode → Settings → Accounts → Manage Certificates)
#   - notarization credentials in the keychain:
#       xcrun notarytool store-credentials snipsy --apple-id <email> --team-id DCD67SQY45
set -euo pipefail
cd "$(dirname "$0")/.."

TEAM=DCD67SQY45
PROFILE=snipsy
PROJECT=app/Snipsy.xcodeproj
OUT=build/release

VERSION=$(xcodebuild -project "$PROJECT" -scheme Snipsy -configuration Release -showBuildSettings 2>/dev/null |
          awk '$1 == "MARKETING_VERSION" { print $3; exit }')
DMG="$OUT/Snipsy-$VERSION.dmg"
echo "▸ Snipsy $VERSION"

git diff --quiet && git diff --cached --quiet || { echo "✗ Commit your changes first."; exit 1; }
! git rev-parse -q --verify "refs/tags/v$VERSION" >/dev/null || { echo "✗ v$VERSION already exists: bump MARKETING_VERSION."; exit 1; }

rm -rf "$OUT" && mkdir -p "$OUT"

echo "▸ Archive"
xcodebuild -project "$PROJECT" -scheme Snipsy -configuration Release -archivePath "$OUT/Snipsy.xcarchive" \
           -allowProvisioningUpdates archive -quiet

echo "▸ Export with Developer ID"
cat > "$OUT/export.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key><string>developer-id</string>
    <key>teamID</key><string>$TEAM</string>
    <key>signingStyle</key><string>automatic</string>
</dict>
</plist>
EOF
xcodebuild -exportArchive -archivePath "$OUT/Snipsy.xcarchive" -exportOptionsPlist "$OUT/export.plist" \
           -exportPath "$OUT/export" -allowProvisioningUpdates -quiet
APP="$OUT/export/Snipsy.app"

echo "▸ Notarize the app"
ditto -c -k --keepParent "$APP" "$OUT/Snipsy.zip"
xcrun notarytool submit "$OUT/Snipsy.zip" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$APP"

echo "▸ Build the DMG"
mkdir -p "$OUT/dmg" && cp -R "$APP" "$OUT/dmg/" && ln -s /Applications "$OUT/dmg/Applications"
hdiutil create -volname "Snipsy" -srcfolder "$OUT/dmg" -ov -format UDZO "$DMG" -quiet
# Signing the DMG itself needs the certificate in the keychain; with Apple's cloud-managed
# Developer ID (Xcode signs the app remotely) we skip it: notarization covers the DMG anyway.
if security find-identity -v -p codesigning | grep -q "Developer ID Application"; then
  codesign --sign "Developer ID Application" --timestamp "$DMG"
fi
xcrun notarytool submit "$DMG" --keychain-profile "$PROFILE" --wait
xcrun stapler staple "$DMG"

echo "▸ Verify"
spctl --assess --type execute -vv "$APP"
xcrun stapler validate "$DMG"

echo "▸ GitHub release"
git tag "v$VERSION" && git push origin "v$VERSION"
gh release create "v$VERSION" "$DMG" --title "Snipsy $VERSION" --generate-notes

echo "✓ Released Snipsy $VERSION"
