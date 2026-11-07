#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
./scripts/build.sh
STAGING="$(mktemp -d "${TMPDIR:-/tmp}/prisma-dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "build/Prisma Music.app" "$STAGING/Prisma Music.app"
ln -s /Applications "$STAGING/Applications"
hdiutil create -volname 'Prisma Music' -srcfolder "$STAGING" -ov -format UDZO "../Prisma-Music-0.5.1.dmg"
