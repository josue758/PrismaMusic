#!/bin/bash
# Shared preflight: development certificates never qualify for public distribution.
prisma_signing_preflight() {
  case "${PRISMA_SIGNING_IDENTITY:-}" in
    'Developer ID Application: '*) ;;
    *) echo 'Set PRISMA_SIGNING_IDENTITY to the full name of an installed Developer ID Application certificate.' >&2; return 1 ;;
  esac
  if ! security find-identity -v -p codesigning | awk -F '"' -v identity="$PRISMA_SIGNING_IDENTITY" '$2 == identity { found=1 } END { exit !found }'; then
    echo 'The requested Developer ID Application identity and private key are not available in the Keychain.' >&2
    return 1
  fi
}
prisma_verify_developer_app() {
  codesign --verify --deep --strict "$1" || return 1
  local details
  details="$(codesign --display --verbose=4 "$1" 2>&1)" || return 1
  if ! printf '%s\n' "$details" | grep -Fxq "Authority=$PRISMA_SIGNING_IDENTITY"; then
    echo 'The app is not signed with the requested Developer ID Application identity.' >&2; return 1
  fi
  if ! printf '%s\n' "$details" | grep -Fq '(runtime)'; then
    echo 'The app does not have Hardened Runtime enabled.' >&2; return 1
  fi
  if ! printf '%s\n' "$details" | grep -q '^Timestamp='; then
    echo 'The app has no secure signing timestamp.' >&2; return 1
  fi
}
