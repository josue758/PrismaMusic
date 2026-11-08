# Contributing

Use a Mac with Xcode 26+, Swift 6.2+ and the macOS 26 SDK. Open `Package.swift` in Xcode or use the command line. No external Swift dependencies are required.

## Changes

Keep a change focused. Explain the user-visible trigger and resulting behavior, then the relevant tests. For a bug, add a regression that fails for the original behavior when practical. Avoid changing personal library data, defaults or audio device settings as part of a test.

Use `./scripts/format.sh` for the repository’s Swift formatting (the formatter ships with the Swift toolchain). Run `swift test` during iteration and `./scripts/verify.sh` before a distribution change. UI changes also need a manual check in the built app: keyboard focus, dark/light appearance, Reduce Motion, Reduce Transparency and long titles. Describe what was actually checked; do not call an unrun check passed.

## Optional integration checks

Ordinary tests skip six checks that need external resources. Enable only the resources you have:

```bash
PRISMA_LIVE_NETWORK=1 swift test
PRISMA_NAS_FILE="/Volumes/YourNAS/Music/sample.flac" swift test
PRISMA_AUDIO_HARDWARE=1 swift test
```

`PRISMA_NAS_INVENTORY` accepts a private JSON file with `root` (absolute directory) and `files` (absolute file paths). Its integration test compares the complete native traversal with that independent reference. Do not commit the inventory, real library exports, credentials, device UIDs or private logs. NAS decoding tests render offline rather than playing through speakers.

## Releases

Update version/build in `Sources/PrismaMusic/Resources/Version.plist`, document behavior and validation limits, and run the verification script. Build a source archive from the release tag, calculate SHA-256 checksums and attach the DMG, archive and checksums to a GitHub release. Verify uploaded asset digests. This workflow does not supply Developer ID signing or notarization.

## Reports

Include app version, macOS version, steps, expected result and actual result. Describe whether a file is local or on a mounted network volume. Remove personal paths and artist-library exports from logs before sharing them publicly. A minimal synthetic file is preferred when reproducing a metadata issue.
