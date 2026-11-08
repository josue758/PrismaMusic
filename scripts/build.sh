#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD_MODE="${1:-release}"
VERSION_FILE="Sources/PrismaMusic/Resources/Version.plist"
PRISMA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :version' "$VERSION_FILE")"
PRISMA_BUILD="$(/usr/libexec/PlistBuddy -c 'Print :build' "$VERSION_FILE")"
swift build -c "$BUILD_MODE"
BIN_DIR="$(swift build -c "$BUILD_MODE" --show-bin-path)"
APP="build/Prisma Music.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN_DIR/PrismaMusic" "$APP/Contents/MacOS/PrismaMusic"
RESOURCE_BUNDLE="$(find "$BIN_DIR" -maxdepth 1 -name '*.bundle' -print -quit)"
if [ -n "$RESOURCE_BUNDLE" ]; then cp -R "$RESOURCE_BUNDLE" "$APP/Contents/Resources/"; fi
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
codesign --force --deep --sign - "$APP"
echo "Built: $PWD/$APP"
