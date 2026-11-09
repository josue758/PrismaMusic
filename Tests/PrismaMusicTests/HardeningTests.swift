import AVFoundation
import AppKit
import Synchronization
import XCTest

@testable import PrismaMusic

final class HardeningTests: XCTestCase {
    func testWelcomeMigrationAndAppearancePreserveAudioSettings() throws {
        var preferences = try JSONDecoder().decode(ListeningPreferences.self, from: Data("{}".utf8))
        XCTAssertFalse(preferences.hasCompletedWelcome)
        preferences.eqEnabled = true
        preferences.selectPreset("jazz")
        preferences.playbackRate = 1.15
        preferences.scanWorkers = 2
        let gains = preferences.eqGains
        for preset in ["glass", "calm", "contrast"] {
            preferences.applyAppearancePreset(preset)
            XCTAssertEqual(preferences.eqGains, gains)
            XCTAssertTrue(preferences.eqEnabled)
            XCTAssertEqual(preferences.playbackRate, 1.15)
            XCTAssertEqual(preferences.scanWorkers, 2)
        }
        XCTAssertEqual(preferences.glassTransparency, 0.15)
        preferences.hasCompletedWelcome = true
        XCTAssertTrue(
            try JSONDecoder().decode(ListeningPreferences.self, from: JSONEncoder().encode(preferences))
                .hasCompletedWelcome)
    }
    @MainActor
    func testWelcomeCompletionPersistsAndReopeningDoesNotReset() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(directory: root, autoStart: false)
        store.preferences.eqGains[3] = 4
        store.preferences.startSection = "albums"
        store.showWelcome = true
        store.finishWelcome(scanAfter: false)
        try await store.flushSaving()
        XCTAssertFalse(store.showWelcome)
        XCTAssertEqual(store.section, "albums")
        let reopened = LibraryStore(directory: root, autoStart: false)
        XCTAssertTrue(reopened.preferences.hasCompletedWelcome)
        XCTAssertEqual(reopened.preferences.eqGains[3], 4)
        reopened.showSettings = true
        reopened.openWelcome()
        XCTAssertFalse(reopened.showSettings)
        XCTAssertFalse(reopened.showWelcome)
        reopened.settingsDismissed()
        XCTAssertTrue(reopened.showWelcome)
        XCTAssertEqual(reopened.preferences.eqGains[3], 4)
    }
    @MainActor
    func testRetryRecoversRepairedFileWithoutPruningUnrelatedTracks() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let good = music.appendingPathComponent("good.m4a")
        let bad = music.appendingPathComponent("bad.m4a")
        try FileManager.default.copyItem(at: demo, to: good)
        try Data([0, 0, 0, 0]).write(to: bad)
        let store = LibraryStore(directory: root.appendingPathComponent("Data"), autoStart: false)
        await store.addSources([music])
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.scanAudit?.failed, 1)
        try FileManager.default.removeItem(at: good)
        try FileManager.default.removeItem(at: bad)
        try FileManager.default.copyItem(at: demo, to: bad)
        await store.retryFailedScan()
        XCTAssertEqual(store.tracks.count, 2)
        XCTAssertEqual(store.scanAudit?.discovered, 2)
        XCTAssertEqual(store.scanAudit?.failed, 0)
        XCTAssertEqual(store.scanAudit?.imported, 2)
        XCTAssertTrue(store.scanAudit?.issues.isEmpty == true)
        try await store.flushSaving()
        let reopened = LibraryStore(directory: root.appendingPathComponent("Data"), autoStart: false)
        XCTAssertEqual(reopened.tracks.count, 2)
        XCTAssertEqual(reopened.scanAudit?.failed, 0)
    }
    func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testIncompleteCancelledAndReplacedSourcesCannotPrune() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        let report = SourceScanner.enumerate(source, recursive: true)
        XCTAssertTrue(SourceScanner.canReconcile(report, cancelled: false))
        XCTAssertFalse(SourceScanner.canReconcile(report, cancelled: true))
        var incomplete = report
        incomplete.complete = false
        XCTAssertFalse(SourceScanner.canReconcile(incomplete, cancelled: false))
        try FileManager.default.moveItem(at: source, to: root.appendingPathComponent("Old"))
        try FileManager.default.createDirectory(at: source, withIntermediateDirectories: true)
        XCTAssertFalse(SourceScanner.canReconcile(report, cancelled: false))
        XCTAssertFalse(SourceScanner.enumerate(root.appendingPathComponent("Missing"), recursive: true).complete)
        XCTAssertFalse(
            SourceScanner.isWithin(URL(fileURLWithPath: "/Music2/a.mp3"), source: URL(fileURLWithPath: "/Music")))
        XCTAssertFalse(
            SourceScanner.isWithin(
                URL(fileURLWithPath: "/Music/Album/a.mp3"), source: URL(fileURLWithPath: "/Music"), recursive: false))
    }
    func testMigrationDeduplicatesArtworkAndIncrementalWritesOneRecord() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 8, pixelsHigh: 8, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
            isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        let art = bitmap.representation(using: .png, properties: [:])!
        var tracks = (0..<100).map {
            Track(
                url: URL(fileURLWithPath: "/\($0).m4a"), title: "Song \($0)", artist: "Artist", album: "Album",
                genre: "Jazz", year: "2026", duration: 120)
        }
        for i in tracks.indices { tracks[i].artwork = art }
        let snapshot = LibrarySnapshot(tracks: tracks, sources: [], edited: [], playlists: [])
        let original = try JSONEncoder().encode(snapshot)
        try original.write(to: root.appendingPathComponent("library.json"))
        let persistence = LibraryPersistence(directory: root)
        var loaded = try XCTUnwrap(persistence.load())
        XCTAssertTrue(loaded.tracks.allSatisfy { $0.artwork == nil && $0.artworkURL != nil })
        XCTAssertEqual(Set(loaded.tracks.compactMap(\.artworkURL)).count, 1)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("library-v0.4-backup.json")), original)
        loaded.tracks[0].favorite = true
        persistence.save(loaded)
        try persistence.flushSync()
        XCTAssertEqual(persistence.lastChangedRows, 1)
        XCTAssertEqual(try LibraryPersistence(directory: root).load()?.tracks.filter(\.favorite).count, 1)
    }
    func testCorruptLegacyLibraryIsReportedAndPreserved() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let original = Data("{broken".utf8)
        let url = root.appendingPathComponent("library.json")
        try original.write(to: url)
        XCTAssertThrowsError(try LibraryPersistence(directory: root).load())
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    func testTenThousandRecordsAndCoalescedLatestSave() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let persistence = LibraryPersistence(directory: root)
        var tracks = (0..<10000).map {
            Track(
                url: URL(fileURLWithPath: "/Music/\($0).flac"), title: "Song \($0)", artist: "Artist \($0 % 100)",
                album: "Album \($0 % 1000)", genre: "Jazz", year: "2026", duration: 120)
        }
        let start = Date()
        persistence.save(.init(tracks: tracks, sources: [], edited: [], playlists: []))
        try persistence.flushSync()
        let first = Date().timeIntervalSince(start)
        for i in 0..<20 {
            tracks[0].title = "Revision \(i)"
            persistence.save(.init(tracks: tracks, sources: [], edited: [], playlists: []))
        }
        try persistence.flushSync()
        let loaded = try XCTUnwrap(LibraryPersistence(directory: root).load())
        XCTAssertEqual(loaded.tracks.count, 10000)
        XCTAssertEqual(loaded.tracks.first { $0.id == tracks[0].id }?.title, "Revision 19")
        print("PRISMA_BENCH 10000 records initial persistence seconds=\(first)")
    }
    private var demo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
    }
    func testUnreadableChildMakesScanIncompleteAndRecoverySucceeds() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: demo, to: folder.appendingPathComponent("song.m4a"))
        try FileManager.default.setAttributes([.posixPermissions: 0], ofItemAtPath: folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path) }
        let inaccessible = SourceScanner.enumerate(root, recursive: true)
        XCTAssertFalse(inaccessible.complete)
        XCTAssertFalse(inaccessible.errors.isEmpty)
        XCTAssertFalse(SourceScanner.canReconcile(inaccessible, cancelled: false))
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.path)
        let recovered = SourceScanner.enumerate(root, recursive: true)
        XCTAssertTrue(recovered.complete)
        XCTAssertEqual(recovered.files.count, 1)
        XCTAssertTrue(SourceScanner.canReconcile(recovered, cancelled: false))
    }
    @MainActor
    func testOverlappingSourcesAndFailedAudioReadKeepExistingTracks() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        let album = music.appendingPathComponent("Album", isDirectory: true)
        try FileManager.default.createDirectory(at: album, withIntermediateDirectories: true)
        let audio = album.appendingPathComponent("song.m4a")
        try FileManager.default.copyItem(at: demo, to: audio)
        let directory = root.appendingPathComponent("State")
        let store = LibraryStore(directory: directory, autoStart: false)
        await store.addSources([music, album])
        XCTAssertEqual(store.tracks.count, 1, "Overlapping folders must not duplicate a song")
        let outer = try XCTUnwrap(store.sources.first { $0.url == music })
        store.removeSource(outer)
        XCTAssertEqual(store.tracks.count, 1, "The remaining album source still owns the song")
        store.favorite(store.tracks[0])
        let old = store.tracks[0]
        try Data("damaged audio".utf8).write(to: audio, options: .atomic)
        await store.scan(force: true)
        XCTAssertEqual(store.tracks, [old], "A metadata read failure must retain the previous song and favorite")
        XCTAssertTrue(store.status.contains(store.t("scanErrors")))
        XCTAssertEqual(store.scanAudit?.failed, 1)
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        var relocated = old
        relocated.url = restored.sources[0].url.appendingPathComponent(old.url.lastPathComponent)
        XCTAssertEqual(restored.tracks, [relocated])
        XCTAssertEqual(restored.sources.count, 1)
    }
    @MainActor
    func testCorruptDatabasePreventsAutomaticReplacement() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("library.sqlite")
        let original = Data("corrupt database bytes".utf8)
        try original.write(to: url)
        let store = LibraryStore(directory: root, autoStart: false)
        XCTAssertNotNil(store.error)
        await store.addSources([demo])
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.tracks.isEmpty)
        store.save()
        do {
            try await store.flushSaving()
            XCTFail("A corrupt database must report an error")
        } catch {}
        XCTAssertEqual(try Data(contentsOf: url), original)
    }
    @MainActor
    func testQueryAndStatisticsRefreshAfterEditsAndPlaylistChanges() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(directory: root, autoStart: false)
        var a = Track(
            url: URL(fileURLWithPath: "/a.flac"), title: "Álbum azul", artist: "Uno", album: "Noche", genre: "Jazz",
            year: "2025", duration: 30)
        let b = Track(
            url: URL(fileURLWithPath: "/b.flac"), title: "Sol", artist: "Dos", album: "Día", genre: "Rock",
            year: "2026", duration: 60)
        store.tracks = [a, b]
        XCTAssertEqual(store.totalDuration, 90)
        XCTAssertEqual(store.groupedAlbums.count, 2)
        store.section = "favorites"
        XCTAssertTrue(store.filtered.isEmpty)
        store.favorite(a)
        XCTAssertEqual(store.filtered.map(\.id), [a.id])
        a = try XCTUnwrap(store.track(for: a.id))
        a.artist = "Tres"
        a.duration = 45
        store.update(a)
        XCTAssertEqual(store.statistics.artists, ["Dos", "Tres"])
        XCTAssertEqual(store.totalDuration, 105)
        store.createPlaylist("Prueba")
        let playlist = try XCTUnwrap(store.playlists.first)
        store.section = "playlist:\(playlist.id)"
        XCTAssertTrue(store.filtered.isEmpty)
        store.add(b, to: playlist)
        XCTAssertEqual(store.filtered.map(\.id), [b.id])
        store.removeFromPlaylist(b)
        XCTAssertTrue(store.filtered.isEmpty)
        store.section = "songs"
        store.search = "album azul"
        XCTAssertEqual(store.filtered.map(\.id), [a.id])
        try await store.flushSaving()
    }

    func testLosslessSourceDepthAndBitrateAreReadFromEncodedFile() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("24-bit.flac")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        do {
            let file = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatFLAC, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                    AVEncoderBitDepthHintKey: 24,
                ])
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 24000)!
            buffer.frameLength = 24000
            for channel in 0..<2 {
                for i in 0..<24000 {
                    buffer.floatChannelData![channel][i] = sin(Float(i) * 2 * .pi * 440 / 48000) * 0.1
                }
            }
            try file.write(from: buffer)
        }
        let original = try Data(contentsOf: url)
        var offset = 4
        var blocks: [(UInt8, Data)] = []
        while offset + 4 <= original.count {
            let header = original[offset]
            let length = Int(original[offset + 1]) << 16 | Int(original[offset + 2]) << 8 | Int(original[offset + 3])
            let type = header & 0x7f
            offset += 4
            if type != 4 && type != 6 { blocks.append((type, original.subdata(in: offset..<offset + length))) }
            offset += length
            if header & 0x80 != 0 { break }
        }
        func number(_ value: Int, little: Bool = false) -> Data {
            var integer = little ? UInt32(value).littleEndian : UInt32(value).bigEndian
            return withUnsafeBytes(of: &integer) { Data($0) }
        }
        let values = [
            "TITLE=Prueba única", "ARTIST=Artista", "ALBUM=Álbum", "GENRE=Ambient", "DATE=1999-04-12",
            "LYRICS=[00:01.00]Hola", "ALBUM ARTIST=Varios artistas",
        ]
        var comments = number(0, little: true) + number(values.count, little: true)
        for value in values {
            let bytes = Data(value.utf8)
            comments.append(number(bytes.count, little: true))
            comments.append(bytes)
        }
        blocks.append((4, comments))
        func image(_ color: NSColor) -> Data {
            let bitmap = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: 2, pixelsHigh: 2, bitsPerSample: 8, samplesPerPixel: 4,
                hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
            for x in 0..<2 { for y in 0..<2 { bitmap.setColor(color, atX: x, y: y) } }
            return bitmap.representation(using: .png, properties: [:])!
        }
        let front = image(.red)
        let other = image(.blue)
        for (type, pixels) in [(0, other), (3, front)] {
            let mime = Data("image/png".utf8)
            var picture = number(type) + number(mime.count) + mime + number(0)
            for value in [2, 2, 32, 0, pixels.count] { picture.append(number(value)) }
            picture.append(pixels)
            blocks.append((6, picture))
        }
        var tagged = Data([0x66, 0x4c, 0x61, 0x43])
        for (index, block) in blocks.enumerated() {
            let length = block.1.count
            tagged.append(contentsOf: [
                block.0 | (index == blocks.count - 1 ? 0x80 : 0), UInt8((length >> 16) & 255),
                UInt8((length >> 8) & 255), UInt8(length & 255),
            ])
            tagged.append(block.1)
        }
        tagged.append(original.suffix(from: offset))
        try tagged.write(to: url, options: .atomic)
        let track = try await MetadataReader.read(url)
        XCTAssertEqual(track.title, "Prueba única")
        XCTAssertEqual(track.artist, "Artista")
        XCTAssertEqual(track.albumArtist, "Varios artistas")
        XCTAssertEqual(track.album, "Álbum")
        XCTAssertEqual(track.genre, "Ambient")
        XCTAssertEqual(track.year, "1999")
        XCTAssertEqual(track.lyrics, "[00:01.00]Hola")
        XCTAssertEqual(track.artwork, front)
        let decoder = try AVAudioFile(forReading: url)
        let decoded = AVAudioPCMBuffer(pcmFormat: decoder.processingFormat, frameCapacity: 512)!
        try decoder.read(into: decoded, frameCount: 512)
        XCTAssertEqual(decoded.frameLength, 512)
        XCTAssertEqual(track.format, "FLAC")
        XCTAssertEqual(track.bitDepth, 24)
        XCTAssertGreaterThan(track.bitrate ?? 0, 0)
        XCTAssertEqual(track.sampleRate, 48000)
        XCTAssertEqual(track.channels, 2)
    }
    func testProgressReportsFinalCountAndCancellationStopsEnumeration() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<100 { try Data().write(to: root.appendingPathComponent("\(i).flac")) }
        let count = Atomic<Int>(-1)
        let report = SourceScanner.enumerate(root, recursive: true) { count.store($0, ordering: .relaxed) }
        XCTAssertTrue(report.complete)
        XCTAssertEqual(count.load(ordering: .relaxed), 100)
        let cancellation = ScanCancellation()
        cancellation.cancel()
        let stopped = SourceScanner.enumerate(root, recursive: true, cancellation: cancellation)
        XCTAssertFalse(stopped.complete)
        XCTAssertTrue(stopped.files.isEmpty)
    }

    @MainActor
    func testParallelScanImportsEveryFileAndSkipsUnchangedOnRepeat() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        for index in 0..<48 {
            try FileManager.default.copyItem(at: demo, to: music.appendingPathComponent("song-\(index).m4a"))
        }
        let directory = root.appendingPathComponent("State")
        let store = LibraryStore(directory: directory, autoStart: false)
        await store.addSources([music])
        XCTAssertEqual(store.tracks.count, 48)
        XCTAssertEqual(Set(store.tracks.map(\.id)).count, 48)
        XCTAssertEqual(store.scanAudit?.imported, 48)
        XCTAssertEqual(store.scanAudit?.failed, 0)
        let selected = store.tracks[0]
        store.preferences.scanWorkers = 2
        let rescan = Task { await store.scan(force: true) }
        while !store.scanning { await Task.yield() }
        store.preferences.scanWorkers = 8
        store.favorite(selected)
        var edited = selected
        edited.title = "User edit while scanning"
        edited.favorite = true
        store.update(edited)
        await rescan.value
        XCTAssertEqual(store.track(for: selected.id)?.title, "User edit while scanning")
        XCTAssertEqual(store.track(for: selected.id)?.favorite, true)
        await store.scan()
        XCTAssertEqual(store.scanAudit?.unchanged, 48)
        XCTAssertEqual(store.scanAudit?.imported, 0)
        XCTAssertEqual(store.scanProcessed, 48)
        let audit = try JSONDecoder().decode(
            ScanAudit.self, from: Data(contentsOf: directory.appendingPathComponent("scan-report.json")))
        XCTAssertEqual(audit.discovered, 48)
        XCTAssertNotNil(audit.finishedAt)
        XCTAssertFalse(audit.cancelled)
        store.createPlaylist("Keep")
        store.add(store.tracks[0], to: store.playlists[0])
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.tracks.count, 48)
        XCTAssertNotNil(restored.track(for: try XCTUnwrap(restored.playlists[0].trackIDs.first)))
    }
    func testHiddenFilesPackagesAndSymbolicLinksAreExcluded() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("Album")
        let package = root.appendingPathComponent("Hidden.app")
        for url in [folder, package] {
            try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            try Data().write(to: url.appendingPathComponent("song.flac"))
        }
        try Data().write(to: root.appendingPathComponent(".hidden.flac"))
        try FileManager.default.createSymbolicLink(at: root.appendingPathComponent("loop"), withDestinationURL: root)
        let report = SourceScanner.enumerate(root, recursive: true)
        XCTAssertTrue(report.complete)
        XCTAssertEqual(report.files.map(\.url), [folder.appendingPathComponent("song.flac")])
        XCTAssertTrue(SourceScanner.enumerate(root, recursive: false).files.isEmpty)
        let cancelled = ScanCancellation()
        cancelled.cancel()
        XCTAssertFalse(
            SourceScanner.enumerate(
                folder.appendingPathComponent("song.flac"), recursive: false, cancellation: cancelled
            ).complete)
    }
    func testWholeNASInventoryMatchesReferenceWhenRequested() throws {
        guard let path = ProcessInfo.processInfo.environment["PRISMA_NAS_INVENTORY"] else {
            throw XCTSkip("Opt-in full NAS inventory check")
        }
        struct Inventory: Decodable {
            var root: String
            var files: [String]
        }
        let expected = try JSONDecoder().decode(Inventory.self, from: Data(contentsOf: URL(fileURLWithPath: path)))
        let start = Date()
        let result = SourceScanner.enumerate(
            URL(fileURLWithPath: expected.root), recursive: true, readModificationDates: false)
        XCTAssertTrue(result.complete)
        XCTAssertTrue(result.errors.isEmpty)
        XCTAssertEqual(result.files.count, expected.files.count)
        XCTAssertTrue(
            Set(result.files.map { $0.url.path }) == Set(expected.files),
            "Native traversal must match the independent inventory")
        print(
            "PRISMA_FULL_NAS count=\(result.files.count) seconds=\(Date().timeIntervalSince(start)) complete=\(result.complete)"
        )
    }

    func testVorbisCommentParserPreservesUnicodeDatesAndLyricsAndRejectsMalformedLengths() {
        var data = Data()
        func integer(_ value: Int) {
            var little = UInt32(value).littleEndian
            withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
        }
        integer(0)
        let comments = ["TITLE=Órbita", "ARTIST=Prisma", "DATE=2026-11-07", "LYRICS=[00:01.00]Música"]
        integer(comments.count)
        for comment in comments {
            let bytes = Data(comment.utf8)
            integer(bytes.count)
            data.append(bytes)
        }
        let tags = NativeFLACMetadata.parseComments(data)
        XCTAssertEqual(tags?["TITLE"], "Órbita")
        XCTAssertEqual(tags?["DATE"], "2026-11-07")
        XCTAssertEqual(tags?["LYRICS"], "[00:01.00]Música")
        XCTAssertNil(NativeFLACMetadata.parseComments(Data([255, 255, 255, 255])))
        XCTAssertNil(NativeFLACMetadata.parseComments(data.dropLast()))
    }
    func testSidecarDiscoveryIsCaseInsensitiveAndDoesNotFetchNewFileDates() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        for name in ["Song.flac", "COVER.JPG", "Song.LRC"] { try Data().write(to: root.appendingPathComponent(name)) }
        let report = SourceScanner.enumerate(root, recursive: true, readModificationDates: false)
        let file = try XCTUnwrap(report.files.first)
        XCTAssertTrue(report.complete)
        XCTAssertTrue(file.sidecarsKnown)
        XCTAssertNil(file.modified)
        XCTAssertEqual(file.coverURL?.lastPathComponent, "COVER.JPG")
        XCTAssertEqual(file.lyricsURL?.lastPathComponent, "Song.LRC")
    }

    func testScanWorkerPreferencesMigrateAndClampWithoutChangingPlayback() throws {
        let old = Data("{\"playbackRate\":1.25}".utf8)
        var preferences = try JSONDecoder().decode(ListeningPreferences.self, from: old)
        XCTAssertEqual(preferences.scanWorkers, 4)
        XCTAssertEqual(preferences.playbackRate, 1.25)
        preferences.scanWorkers = 100
        preferences.sanitize()
        XCTAssertEqual(preferences.scanWorkers, 8)
        preferences.scanWorkers = 0
        preferences.sanitize()
        XCTAssertEqual(preferences.scanWorkers, 1)
        XCTAssertEqual(collectionTimeText(90061), "25 h 1 min")
        XCTAssertEqual(collectionTimeText(125), "2:05")
    }

    func testZeroFilledFLACIsReportedAsCorruptInsteadOfImported() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("broken.flac")
        try Data(repeating: 0, count: 1024).write(to: url)
        do {
            _ = try await MetadataReader.read(url)
            XCTFail("A zero-filled file is not a FLAC stream")
        } catch {
            XCTAssertEqual((error as NSError).domain, NSCocoaErrorDomain)
            XCTAssertEqual((error as NSError).code, CocoaError.fileReadCorruptFile.rawValue)
        }
    }

    @MainActor
    func testQuittingDuringStartupDoesNotStartAnAutomaticScan() async throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(directory: root, autoStart: true)
        try await store.prepareForTermination()
        XCTAssertFalse(store.scanning)
        XCTAssertNil(store.scanAudit)
        XCTAssertTrue(store.tracks.isEmpty)
    }

}
