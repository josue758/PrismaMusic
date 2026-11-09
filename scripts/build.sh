#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_MODE="${1:-release}"
source scripts/signing-config.sh
if [ -n "${PRISMA_SIGNING_IDENTITY:-}" ]; then prisma_signing_preflight; fi
VERSION_FILE="Sources/PrismaMusic/Resources/Version.plist"
PRISMA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :version' "$VERSION_FILE")"
PRISMA_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :build' "$VERSION_FILE")"
swift build --build-system swiftbuild -c "$BUILD_MODE"
BIN_DIR="$(swift build --build-system swiftbuild -c "$BUILD_MODE" --show-bin-path)"
APP="build/Prisma Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PrismaMusic" "$APP/Contents/MacOS/PrismaMusic"
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -print -quit)"
if [ -n "$RESOURCE_BUNDLE" ]; then cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"; fi
# SwiftPM builds an executable rather than an app bundle. Extract the App Shortcuts
# metadata from its compiler output before signing the bundle.
PRISMA_INTERMEDIATES="$(dirname "$(dirname "$BIN_DIR")")/Intermediates.noindex/PrismaMusic.build/$(basename "$BIN_DIR")"
PRISMA_INTENTS_INPUTS="$(mktemp -d)"
trap 'rm -rf "$PRISMA_INTENTS_INPUTS"' EXIT
find "$PWD/Sources/PrismaMusic" -name '*.swift' -print > "$PRISMA_INTENTS_INPUTS/sources"
find "$PRISMA_INTERMEDIATES" -name '*.swiftconstvalues' -print > "$PRISMA_INTENTS_INPUTS/const-values"
test -s "$PRISMA_INTENTS_INPUTS/const-values"
xcrun appintentsmetadataprocessor \
  --toolchain-dir "$(dirname "$(dirname "$(xcrun --find swiftc)")")" \
  --module-name PrismaMusic --sdk-root "$(xcrun --sdk macosx --show-sdk-path)" \
  --xcode-version "$(xcodebuild -version | awk '/Build version/{print $3}')" \
  --platform-family macOS --deployment-target 26.0 --target-triple "$(uname -m)-apple-macos26.0" \
  --source-file-list "$PRISMA_INTENTS_INPUTS/sources" --swift-const-vals-list "$PRISMA_INTENTS_INPUTS/const-values" \
  --output "$PRISMA_INTENTS_INPUTS"
test -s "$PRISMA_INTENTS_INPUTS/Metadata.appintents/extract.actionsdata"
ditto "$PRISMA_INTENTS_INPUTS/Metadata.appintents" "$APP/Contents/Resources/Metadata.appintents"
if [ -f scripts/AppIcon.icns ]; then cp scripts/AppIcon.icns "$APP/Contents/Resources/"; fi
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleExecutable</key><string>PrismaMusic</string>
<key>CFBundleIdentifier</key><string>local.prisma.music</string>
<key>CFBundleName</key><string>Prisma Music</string>
<key>CFBundleDisplayName</key><string>Prisma Music</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>${PRISMA_VERSION}</string>
<key>CFBundleVersion</key><string>${PRISMA_BUILD}</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSPrincipalClass</key><string>NSApplication</string>
<key>LSApplicationCategoryType</key><string>public.app-category.music</string>
<key>CFBundleDocumentTypes</key><array><dict><key>CFBundleTypeName</key><string>Audio</string><key>CFBundleTypeRole</key><string>Viewer</string><key>LSHandlerRank</key><string>Alternate</string><key>LSItemContentTypes</key><array><string>public.audio</string></array></dict></array>
</dict></plist>
PLIST
if [ -n "${PRISMA_SIGNING_IDENTITY:-}" ]; then
  # This app currently contains one executable and a data-only resource bundle.
  # New frameworks or plug-ins need explicit inside-out signing before this step.
  if [ -d "$APP/Contents/Frameworks" ] || [ -d "$APP/Contents/PlugIns" ]; then
    echo 'Nested executable bundles require an explicit signing plan.' >&2; exit 1
  fi
  codesign --force --options runtime --timestamp --sign "$PRISMA_SIGNING_IDENTITY" "$APP"
  prisma_verify_developer_app "$APP"
else
  codesign --force --sign - "$APP"
fi
echo "Built: $PWD/$APP"
