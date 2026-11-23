#!/bin/bash
# No network providers or personal NAS paths are required by this check.
set -euo pipefail
cd "$(dirname "$0")/.."
APP="${PRISMA_APP_PATH:-build/Prisma Music.app}"
swift test --scratch-path "${PRISMA_SCRATCH_PATH:-.build}"
./scripts/package-dmg.sh
PRISMA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :version' Sources/PrismaMusic/Resources/Version.plist)"
PRISMA_BUNDLE_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist")"
test "$PRISMA_VERSION" = "$PRISMA_BUNDLE_VERSION"
codesign --verify --deep --strict "$APP"
hdiutil verify "../Prisma-Music-${PRISMA_VERSION}.dmg"
