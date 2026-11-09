#!/bin/bash
# Requires a paid Apple Developer membership and locally configured Keychain assets.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/signing-config.sh
case "${1:-}" in
  ''|--check) ;;
  *) echo 'Usage: ./scripts/notarize.sh [--check]' >&2; exit 2 ;;
esac
prisma_signing_preflight
: "${PRISMA_NOTARY_PROFILE:?Set PRISMA_NOTARY_PROFILE to an existing notarytool Keychain profile.}"
# Validate credentials before building or submitting a binary. No passwords are printed.
xcrun notarytool history --keychain-profile "$PRISMA_NOTARY_PROFILE" --output-format plist >/dev/null
if [ "${1:-}" = --check ]; then
  echo 'Developer ID identity and notarization credentials are available.'; exit 0
fi
./scripts/build.sh release
APP="$PWD/build/Prisma Music.app"
prisma_verify_developer_app "$APP"
PRISMA_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :version' Sources/PrismaMusic/Resources/Version.plist)"
DIST="$PWD/build/distribution"
mkdir -p "$DIST"
ZIP="$DIST/Prisma-Music-${PRISMA_VERSION}-notary.zip"
ditto -c -k --keepParent "$APP" "$ZIP"
submit_for_notarization() {
  local artifact="$1" report="$2" status submission_id
  if ! xcrun notarytool submit "$artifact" --keychain-profile "$PRISMA_NOTARY_PROFILE" --wait --timeout 20m --output-format plist > "$report"; then
    echo "Notarization did not finish successfully. Inspect $report before retrying; do not resubmit a timed-out request blindly." >&2
    return 1
  fi
  status="$(/usr/libexec/PlistBuddy -c 'Print :status' "$report")"
  if [ "$status" != Accepted ]; then
    submission_id="$(/usr/libexec/PlistBuddy -c 'Print :id' "$report")"
    xcrun notarytool log "$submission_id" --keychain-profile "$PRISMA_NOTARY_PROFILE" "${report%.plist}-log.json" || true
    echo "Apple did not accept this submission ($status). No notarized release was produced." >&2
    return 1
  fi
}
submit_for_notarization "$ZIP" "$DIST/app-notary.plist"
xcrun stapler staple "$APP"
xcrun stapler validate "$APP"
prisma_verify_developer_app "$APP"
spctl --assess --type execute --verbose=2 "$APP"
# Package the stapled app without rebuilding it. Use a separate output from public beta assets.
export PRISMA_SKIP_BUILD=1
export PRISMA_DMG_PATH="$DIST/Prisma-Music-${PRISMA_VERSION}-notarized.dmg"
./scripts/package-dmg.sh
submit_for_notarization "$PRISMA_DMG_PATH" "$DIST/dmg-notary.plist"
xcrun stapler staple "$PRISMA_DMG_PATH"
xcrun stapler validate "$PRISMA_DMG_PATH"
codesign --verify --strict "$PRISMA_DMG_PATH"
spctl --assess --type open --context context:primary-signature --verbose=2 "$PRISMA_DMG_PATH"
hdiutil verify "$PRISMA_DMG_PATH"
(cd "$DIST" && shasum -a 256 "$(basename "$PRISMA_DMG_PATH")" > SHA256SUMS-notarized.txt)
echo "Validated notarized distribution: $PRISMA_DMG_PATH"
