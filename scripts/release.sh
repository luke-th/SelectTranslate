#!/bin/bash
# Cut a release: bump version, build a universal DMG, sign it for Sparkle, regenerate appcast.xml,
# and (with --publish) create the GitHub release that installed copies poll for updates.
#
#   ./scripts/release.sh 0.2.0            build + appcast only (build/release/)
#   ./scripts/release.sh 0.2.0 --publish  also: commit the version bump, tag v0.2.0, gh release create
#
# One-time setup: the Sparkle EdDSA private key lives in your login Keychain (created with
# Sparkle's `generate_keys`; its public half is SUPublicEDKey in Resources/Info.plist).
# On another Mac: `generate_keys -x key.txt` here, `generate_keys -f key.txt` there.
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${1:?usage: release.sh <version> [--publish]}"
PUBLISH="${2:-}"
REPO="luke-th/SelectTranslate"
TAG="v$VERSION"
PLIST="Resources/Info.plist"

BUILD_NUMBER=$(( $(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$PLIST") + 1 ))
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$PLIST"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion $BUILD_NUMBER" "$PLIST"
echo "Version $VERSION (build $BUILD_NUMBER)"

UNIVERSAL=1 ./scripts/make-dmg.sh

OUT="build/release"
rm -rf "$OUT" && mkdir -p "$OUT"
cp "build/SelectTranslate-$VERSION.dmg" "$OUT/"

SPARKLE_BIN="$(dirname "$(find .build/artifacts -name generate_appcast -type f | head -1)")"
"$SPARKLE_BIN/generate_appcast" \
  --download-url-prefix "https://github.com/$REPO/releases/download/$TAG/" \
  --link "https://github.com/$REPO/releases" \
  -o "$OUT/appcast.xml" "$OUT"
echo "Appcast written to $OUT/appcast.xml"

if [[ "$PUBLISH" == "--publish" ]]; then
  git add "$PLIST"
  git commit -m "Release $VERSION" || true
  git tag -a "$TAG" -m "SelectTranslate $VERSION"
  git push origin HEAD "$TAG"
  gh release create "$TAG" "$OUT/SelectTranslate-$VERSION.dmg" "$OUT/appcast.xml" \
    --repo "$REPO" --title "SelectTranslate $VERSION" --generate-notes
  echo "Published https://github.com/$REPO/releases/tag/$TAG"
fi
