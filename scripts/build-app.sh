#!/bin/bash
# Builds SelectTranslate.app from the Swift package. No Xcode required — Command Line Tools are enough.
#   ./scripts/build-app.sh            release build → build/SelectTranslate.app
#   ./scripts/build-app.sh debug      debug build
#   UNIVERSAL=1 ./scripts/build-app.sh   arm64 + x86_64 (builds each slice, then lipo)
#   CODESIGN_IDENTITY="Developer ID Application: …" ./scripts/build-app.sh   sign with a real identity (default: ad-hoc)
set -euo pipefail
cd "$(dirname "$0")/.."

CONFIG="${1:-release}"

swift build -c "$CONFIG" --product SelectTranslate
BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BINARY="$BIN_DIR/SelectTranslate"

if [[ "${UNIVERSAL:-0}" == "1" ]]; then
  # `--arch a --arch b` needs Xcode's xcbuild; building each slice separately works with the Command Line Tools.
  NATIVE_ARCH="$(uname -m)"
  OTHER_ARCH=$([[ "$NATIVE_ARCH" == "arm64" ]] && echo x86_64 || echo arm64)
  swift build -c "$CONFIG" --product SelectTranslate --triple "$OTHER_ARCH-apple-macosx"
  OTHER_BIN="$(swift build -c "$CONFIG" --triple "$OTHER_ARCH-apple-macosx" --show-bin-path)/SelectTranslate"
  mkdir -p build
  lipo -create "$BINARY" "$OTHER_BIN" -output build/SelectTranslate-universal
  BINARY="build/SelectTranslate-universal"
fi

APP="build/SelectTranslate.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BINARY" "$APP/Contents/MacOS/SelectTranslate"
cp Resources/Info.plist "$APP/Contents/Info.plist"

# Sparkle ships as an xcframework via SwiftPM; the executable expects it at @executable_path/../Frameworks.
SPARKLE_SRC="$(find .build/artifacts -type d -path '*Sparkle.xcframework/macos-arm64_x86_64/Sparkle.framework' | head -1)"
[[ -n "$SPARKLE_SRC" ]] || { echo "Sparkle.framework not found — run 'swift package resolve'"; exit 1; }
mkdir -p "$APP/Contents/Frameworks"
cp -R "$SPARKLE_SRC" "$APP/Contents/Frameworks/Sparkle.framework"
printf 'APPL????' > "$APP/Contents/PkgInfo"

if [[ ! -f Resources/AppIcon.icns ]]; then
  swift scripts/make-icon.swift Resources/AppIcon.icns
fi
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# SwiftPM resource bundles (e.g. KeyboardShortcuts localizations)
shopt -s nullglob
for bundle in "$BIN_DIR"/*.bundle; do
  cp -R "$bundle" "$APP/Contents/Resources/"
done

BUNDLE_ID="app.selecttranslate.SelectTranslate"
IDENTITY="${CODESIGN_IDENTITY:--}"
RUNTIME_FLAGS=()
[[ "$IDENTITY" != "-" ]] && RUNTIME_FLAGS=(--options runtime)

# Sparkle's helpers must be signed inside-out before the framework and app (per Sparkle's docs).
SPARKLE="$APP/Contents/Frameworks/Sparkle.framework/Versions/B"
codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} --preserve-metadata=entitlements "$SPARKLE/XPCServices/Downloader.xpc"
codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} "$SPARKLE/XPCServices/Installer.xpc"
codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} "$SPARKLE/Autoupdate"
codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} "$SPARKLE/Updater.app"
codesign --force --sign "$IDENTITY" ${RUNTIME_FLAGS[@]+"${RUNTIME_FLAGS[@]}"} "$APP/Contents/Frameworks/Sparkle.framework"

if [[ -z "${CODESIGN_IDENTITY:-}" ]]; then
  # Ad-hoc signatures normally get a cdhash-based designated requirement, which changes on every build
  # and makes macOS forget the Accessibility grant. Pin the requirement to the bundle identifier instead.
  codesign --force --sign - --identifier "$BUNDLE_ID" \
    --requirements "=designated => identifier \"$BUNDLE_ID\"" "$APP"
else
  codesign --force --options runtime --sign "$CODESIGN_IDENTITY" "$APP"
fi
echo "Built $APP"
