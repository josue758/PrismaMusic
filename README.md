# Prisma Music

[![macOS validation](https://github.com/josue758/PrismaMusic/actions/workflows/ci.yml/badge.svg)](https://github.com/josue758/PrismaMusic/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

A native macOS music player for local collections and mounted NAS libraries. Built with Swift, SwiftUI, AVAudioEngine and Core Audio, with an artwork-driven Liquid Glass interface.

**Apple Silicon · macOS 26+ · Stable 0.16.1**

[Download the app](https://github.com/josue758/PrismaMusic/releases/tag/v0.16.1) · [Guía en español](docs/USER_GUIDE.es.md) · [Architecture](docs/ARCHITECTURE.md) · [Validation evidence](VALIDACION.md) · [Windows feature adaptation](docs/WINDOWS_PARITY.md)

## Try it

Download the DMG, drag **Prisma Music** to Applications, and open it. The welcome flow lets you choose Spanish, English or Portuguese, appearance and a music folder. Three redistributable instrumental demos are included; a NAS is optional.

This release uses an ad hoc signature. Prisma Music requires no account or subscription. Updates preserve the library and preferences. Use **Prisma Music → Check for Updates…** to download and open a newer installer from the app.

## Library maintenance

Adapted from the Windows edition: **Settings → Library → Tag Review** groups missing artists/albums, album spelling variants and possible duplicates. Select tracks and preview a batch correction, including album artist and disc/track numbers. In song lists drag across titles, use Shift + the arrow keys, or press Command-A to select multiple tracks and choose **Batch Tag Editor** from the contextual menu. Only enabled fields change; corrections are kept per field through future scans. **Undo Tag Edits** restores the last edit in the current session, while the individual editor can restore tags from the original file. The editors can also save tags directly to writable FLAC files. The encoded audio is copied without re-encoding.

The scan report can search paths and errors and retry one failed file without losing the other results. Resume an interrupted import with the new-music scan: already imported tracks are skipped during metadata reading, while directories are traversed again. Source relocation verifies the new files with progress and cancellation before changing paths.

SQLite integrity is checked on opening. Prisma retains up to seven daily SQLite snapshots in its data folder, restores a valid snapshot on database corruption, and preserves damaged files for inspection. A snapshot may predate the latest edits; it does not back up audio or artwork files. Manual JSON export remains available. Artist pages include your five most played tracks, based on local play counts, and shortcuts to their songs and albums.

## Listening and browsing

- Browse songs, albums and artists; filter by artist, genre and year. Album pages show their songs with disc/track ordering when the files provide it.
- Inspect the real codec/container, bitrate estimate, file size, sample rate, channel count and bit depth.
- Choose a Core Audio output or DAC. Direct output bypasses application DSP and requests the source sample rate; exclusive access is optional and device dependent.
- Open an independent full-screen listening window with artwork, transport and synchronized lyrics. Closing it returns to the unchanged library.
- Look up original lyrics across scripts with canonical Unicode normalization, search fallbacks and strict artist/duration/performance checks.
- Show Apple on-device Spanish translation beneath the original lyrics. Supported language models can be downloaded with the system prompt; unsupported languages keep the original.
- Use the native AirPlay picker, a floating mini player, lyrics, a visualizer, playlists, favorites and listening history.
- Discover attributed artist photographs and biographies from Wikipedia/Wikimedia, choose a portrait and keep that choice locally.
- Customize artwork-derived colors, glass, motion, EQ and listening behavior. Reduced motion and reduced transparency are respected.
- Browse song rows with **↑ / ↓**, play the selection with **Return**, find music with **⌘F**, and leave search with **Esc**. **⌘I** inspects the selection.

## Engineering decisions

| Concern | Implementation and tradeoff |
| --- | --- |
| Slow network storage | Directory enumeration and bounded metadata workers run away from the UI. Incomplete scans do not prune the collection. SMB calls can still take time to return. |
| Rapid playback changes | A serial audio-file loader and request identity prevent a late result from replacing a newer selection. Cancelling discards the result without forcibly interrupting an OS call. |
| Large libraries | SQLite WAL, incremental writes, coalesced snapshots and shared external artwork avoid rewriting an entire JSON library or duplicating embedded covers. |
| Listening fidelity | A dedicated direct graph skips EQ, balance, rate changes and application attenuation. Tests check PCM sample equality internally; this is not physical DAC certification. |
| Image loading | ImageIO downsampling, serial portrait loading, cancellation and bounded caches limit avoidable image work. Vision considers faces when framing portraits. |
| Privacy | Audio stays local. Online features send search metadata, not audio or NAS credentials. They can be disabled; source files are never retagged by library edits. |

```mermaid
flowchart LR
    UI[SwiftUI views] --> Store[LibraryStore · main actor]
    Store --> Scan[Scanner + bounded metadata reads]
    Store --> Disk[Serial SQLite persistence]
    Store --> Loader[Serial audio-file loader]
    Loader --> Audio[AVAudioEngine + Core Audio]
    Store --> AirPlay[AVPlayer + native route picker]
    Store --> Online[Optional metadata and portraits]
```

The app has no third-party Swift package dependencies. See [architecture and tradeoffs](docs/ARCHITECTURE.md) for isolation boundaries, persistence and current technical debt.

## Build and verify

Requires Xcode 26+ / Swift 6.2+ with the macOS 26 SDK or newer. The package currently uses Swift 5 language mode; strict Swift 6 concurrency migration is still planned.

```bash
git clone https://github.com/josue758/PrismaMusic.git
cd PrismaMusic
swift test
./scripts/build.sh
open "build/Prisma Music.app"
```

To run the same offline validation as CI, including a release build, signature check and DMG integrity verification:

```bash
./scripts/verify.sh
```

For 0.16.1, **112 tests passed locally** and seven optional checks were skipped. The run included real NAS FLAC playback during an incremental scan, update downloads, and direct PCM playback through a USB output. The wake-recovery test uses a simulated macOS notification. See [validation](VALIDACION.md) for previous test runs and their scope.

GitHub Actions runs this check on the standard [macOS 26 Apple Silicon runner](https://docs.github.com/en/actions/reference/runners/github-hosted-runners), with read-only repository permissions and actions pinned to commit IDs. Each run retains its log and installer for 14 days.

## Scope and next steps

Prisma has been exercised against a real SMB library with 7,854 listed files. It imported 7,813 files and reported 41 original-file issues.

Physical AirPlay transfer and bit-perfect output measured at the DAC remain outside the verified scope. The installer targets Apple Silicon. State coordination is concentrated in `LibraryStore`. See [the roadmap](docs/ROADMAP.md) for architectural work.

[Contributing](CONTRIBUTING.md) · [Changelog](CHANGELOG.md) · [MIT license](LICENSE)
