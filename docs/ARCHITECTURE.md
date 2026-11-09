# Architecture and tradeoffs

Prisma Music is a Swift Package executable and a native macOS app bundle. SwiftUI owns presentation; `LibraryStore` is the main-actor state coordinator. Services are deliberately small and use system frameworks rather than external Swift packages.

## State and presentation

`ContentView` routes between the library, artist/album details and listening views. `LibrarySongList` shares row behavior across collections. Pure `LibraryQueryCache`, `AlbumCollection`, `ArtistCollection` and `SongSelection` values keep grouping, sorting and selection rules testable without rendering a window.

The store invalidates query and identity caches when the library changes, instead of regrouping the collection on each meter tick. The store still has too many responsibilities: playback and import orchestration are candidates for extraction. This project does not claim a fully modular architecture.

## Import and persistence

1. Finder supplies URLs and security-scoped bookmarks. NAS access uses volumes mounted by macOS; Prisma does not implement SMB or store network passwords.
2. `SourceScanner` enumerates directories, tracks cancellation/completeness and discovers sidecar files once per folder.
3. Bounded workers read metadata, using native FLAC headers/comments where possible and AVFoundation for other cases. Parsing validates lengths and limits allocations.
4. Results reach the main actor in batches. Updated records merge with current favorite and edited-tag state.
5. `LibraryPersistence` coalesces pending snapshots on a private serial queue and writes changed SQLite rows in transactions. WAL and full synchronization favor recoverability. Shared artwork is stored separately.

Only a completed scan can remove missing records. A disconnected source or cancelled scan preserves existing records. An audit contains counts and bounded error details. Audio originals remain untouched by library tag edits.

## Playback and isolation

`AudioFileLoader` serializes `AVAudioFile` opening away from the UI. Each playback request has an identity; a late completion cannot install a superseded file. A cancellation invalidates the request but cannot forcibly stop a blocking macOS file operation. Session restore defers file opening until playback is requested.

Engine graph construction and transport control remain on the main actor. The ordinary graph supplies EQ, balance and playback rate. Direct output uses a separate path with unity gain and no DSP. `AudioDeviceController` handles nominal sample rate and optional exclusive ownership, with restoration on release. A disappearing selected output pauses playback.

AirPlay is a separate `AVPlayer` transport with the system route picker. DSP and direct Core Audio settings do not apply to it. Preparing a NAS file for AVPlayer is tested; a physical external transfer has not been tested.

The package uses Swift 5 language mode. Some resource handoffs use explicit `@unchecked Sendable` wrappers with serial ownership rather than compiler-enforced Swift 6 isolation. These boundaries need a dedicated strict-concurrency migration, not a blanket removal of diagnostics.

## Images, motion and accessibility

ImageIO downsampling avoids rendering full-resolution portrait files. Portrait downloads are serial and cancelled when no longer needed. Compressed-data and thumbnail caches have explicit cost/count limits; these are cache limits, not total application RAM guarantees.

Faces influence portrait framing; Wikimedia links and license metadata remain visible. Profile matching can still fail for ambiguous names. Vision processing stays on a utility task. Motion respects Reduce Motion and pauses its timeline when playback stops. Reduce Transparency uses opaque system-colored surfaces.

Song lists have a keyboard focus state independent of playback. Arrow keys select and scroll without playing; Return starts the selection. Search has a separate focus request, and modified arrow keys are left for command shortcuts. VoiceOver actions expose playback and album navigation; a full screen-reader usability audit remains future work.

## Independent listening window and translation

`ListeningWindowController` owns one additional native window and returns focus to the library on close. It shares the existing store, transport, output selection and artwork cache; it creates no second audio engine or meter timer. The library keeps its navigation and filters.

`LyricDocument` preserves original timed/plain entries and deduplicates only translation requests. A translation response must match both its client identifier and source text. Each job captures its document, source language and request identity, so late responses cannot overwrite a different song. Batches of 32 use Apple's on-device Translation framework, with an explicit system download action for missing models. The original remains visible on unsupported languages, failure or oversized documents.

Translations live in a bounded memory cache, keyed by lyric-content hash, source and Spanish target. They do not modify files or library metadata. Original timestamps drive highlighting and seeking; translations never invent timing. This is machine translation, with known limitations for poetry and multilingual lyrics.

## Reproducible distribution

`Resources/Version.plist` is the single source of version/build metadata for the UI, request user agent, app bundle and DMG filename. `scripts/verify.sh` runs the tests, builds the app/DMG, verifies the ad hoc signature and checks image integrity. CI uses no personal library, credentials or optional integration environment variables.

See [VALIDACION.md](../VALIDACION.md) for observed results and their limits. See [CONTRIBUTING.md](../CONTRIBUTING.md) for change verification and integration checks.
