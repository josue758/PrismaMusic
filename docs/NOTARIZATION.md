# Developer ID and notarization

**Current status: prepared, not notarized.** The published beta remains ad hoc signed. This Mac has no Developer ID Application identity or configured notarization profile, and the maintainer has not enrolled in the paid Apple Developer Program. The real signed/notarized path cannot be validated until those assets exist.

## Prerequisites supplied by the account owner

1. Enroll in the [Apple Developer Program](https://developer.apple.com/programs/enroll/). Apple lists an annual fee of USD 99, with regional pricing at enrollment. The owner must complete payment and legal agreements.
2. Create a [Developer ID Application certificate](https://developer.apple.com/help/account/certificates/create-developer-id-certificates/) using the account/Xcode and keep its private key in the local Keychain. Apple Development is a different identity and is rejected by these scripts.
3. Configure a `notarytool` Keychain profile locally using `xcrun notarytool store-credentials`. Follow its secure prompts; do not put passwords, private keys or app-specific passwords in the repository, command history or chat.

## Preflight and distribution

Use the full certificate name displayed by `security find-identity -v -p codesigning` and the profile name you created:

```bash
export PRISMA_SIGNING_IDENTITY='Developer ID Application: Your Name (TEAMID)'
export PRISMA_NOTARY_PROFILE='PrismaMusic'
./scripts/notarize.sh --check
./scripts/notarize.sh
```

The script validates the identity and credentials before building. It signs the app with Hardened Runtime and a secure timestamp, verifies the signature, uploads an app ZIP, requires an Accepted result, staples/validates the app ticket, and checks Gatekeeper. It packages that app without rebuilding, signs the DMG, submits and staples the DMG, checks Gatekeeper/integrity again, then calculates SHA-256.

Output is under ignored `build/distribution/`, separate from published beta assets. Logs and submission IDs stay there too. A timed-out request must be checked with `notarytool info`/`wait` before resubmission. No signed release is published automatically. Test the actual signed app's playback, NAS, models and windows before publishing the next version.

No extra entitlements are requested: Prisma currently contains its own executable and a data-only resource bundle. New executable frameworks/plug-ins require explicit inside-out signing; the script refuses that layout until it has a signing plan. The bundle identifier is preserved to keep current preferences and library behavior.

The ordinary build/CI path continues to use ad hoc signing. Supplying an invalid distribution identity fails instead of silently falling back to ad hoc.

See [Apple’s notarization workflow](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution) and [requirements](https://developer.apple.com/documentation/security/resolving-common-notarization-issues).
