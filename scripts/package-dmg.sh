#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing-config.sh
if [ -n "${PRISMA_SIGNING_IDENTITY:-}" ]; then prisma_signing_preflight; fi
if [ "${PRISMA_SKIP_BUILD:-0}" != 1 ]; then ./scripts/build.sh; fi
if [ -n "${PRISMA_SIGNING_IDENTITY:-}" ]; then prisma_verify_developer_app 'build/Prisma Music.app'; fi
PRISMA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :version' Sources/PrismaMusic/Resources/Version.plist)"
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/prisma-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "build/Prisma Music.app" "$STAGING/Prisma Music.app"
ln -s /Applications "$STAGING/Applications"
DMG="${PRISMA_DMG_PATH:-../Prisma-Music-${PRISMA_VERSION}.dmg}"
mkdir -p "$(dirname "$DMG")"
hdiutil create -volname 'Prisma Music' -srcfolder "$STAGING" -ov -format UDZO "$DMG"

if [ -n "${PRISMA_SIGNING_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$PRISMA_SIGNING_IDENTITY" "$DMG"
  codesign --verify --strict "$DMG"
fi
