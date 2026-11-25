import Foundation
import SQLite3
import XCTest

@testable import PrismaMusic

final class LibraryMaintenanceTests: XCTestCase {
    private var demo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
    }
    func testReviewUsesAlbumOwnerAndDoesNotConfuseDifferentRecordings() {
        func song(_ path: String, artist: String = "Singer", title: String = "Song", seconds: Double = 180) -> Track {
            Track(
                url: URL(fileURLWithPath: path), title: title, artist: artist, album: "Collection", genre: "", year: "",
                duration: seconds, artwork: nil)
        }
        var one = song("/a.flac", artist: "Singer A")
        one.albumArtist = "Various Artists"
        var two = song("/b.flac", artist: "Singer B")
        two.albumArtist = "Various Artists"
        two.album = "collection"
        var copy = one
        copy.url = URL(fileURLWithPath: "/copy.flac")
        copy.duration = 181
        var live = one
        live.url = URL(fileURLWithPath: "/live.flac")
        live.duration = 210
        let missing = song("/unknown.flac", artist: "—")
        let issues = LibraryTagReview.find([one, two, copy, live, missing, one])
        XCTAssertEqual(issues.filter { $0.kind == .missingArtist }.count, 1)
        XCTAssertEqual(issues.filter { $0.kind == .splitAlbum }.count, 1)
        let duplicates = issues.filter { $0.kind == .possibleDuplicate }
        XCTAssertEqual(duplicates.count, 1)
        XCTAssertEqual(Set(duplicates[0].tracks.map(\.id)), Set([one.id, copy.id]))
        XCTAssertEqual(LibraryTagReview.key("  Ａrtist\nName  "), "ARTIST NAME")
    }
    func testNumericTagValidationAndEmptyValues() {
        for field in [TagField.year, .trackNumber, .discNumber] {
            XCTAssertTrue(field.isValid("9999"))
            XCTAssertTrue(field.isValid(""))
            for invalid in ["0", "-1", "10000", "1.5", "abc"] { XCTAssertFalse(field.isValid(invalid)) }
        }
        XCTAssertFalse(TagField.title.isValid("  "))
    }
    @MainActor
    func testFieldCorrectionsSurviveScanReopenUndoAndRestore() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: demo, to: music.appendingPathComponent("a.m4a"))
        try FileManager.default.copyItem(at: demo, to: music.appendingPathComponent("b.m4a"))
        let data = root.appendingPathComponent("Data")
        let store = LibraryStore(directory: data, autoStart: false)
        await store.addSources([music])
        let original = try XCTUnwrap(store.tracks.first)
        let ids = store.tracks.map(\.id)
        store.applyTagEdits(ids: ids, changes: [.title: "My title", .albumArtist: "My album artist"], numberingFrom: 5)
        XCTAssertEqual(store.tracks.map(\.trackNumber), [5, 6])
        store.favorite(store.tracks[0])
        store.tracks[0].playCount = 8
        store.undoTagEdits()
        XCTAssertEqual(store.tracks[0].title, original.title)
        XCTAssertTrue(store.tracks[0].favorite)
        XCTAssertEqual(store.tracks[0].playCount, 8)
        store.applyTagEdits(ids: [original.id], changes: [.title: "My title", .albumArtist: "My album artist"])
        store.tracks[0].artist = "Stale file metadata"
        await store.scan(force: true)
        let rescanned = try XCTUnwrap(store.track(for: original.id))
        XCTAssertEqual(rescanned.title, "My title")
        XCTAssertEqual(rescanned.artist, original.artist)
        XCTAssertEqual(rescanned.albumArtist, "My album artist")
        XCTAssertTrue(rescanned.favorite)
        XCTAssertEqual(rescanned.playCount, 8)
        try await store.flushSaving()
        let reopened = LibraryStore(directory: data, autoStart: false)
        await reopened.scan(force: true)
        let reopenedTrack = try XCTUnwrap(
            reopened.tracks.first { $0.url.lastPathComponent == original.url.lastPathComponent })
        XCTAssertEqual(reopenedTrack.title, "My title")
        try await reopened.restoreFileTags(reopenedTrack)
        XCTAssertEqual(reopened.track(for: reopenedTrack.id)?.title, original.title)
        XCTAssertTrue(reopened.track(for: reopenedTrack.id)?.favorite == true)
        XCTAssertEqual(reopened.track(for: reopenedTrack.id)?.playCount, 8)
        try await reopened.flushSaving()
        let restored = LibraryStore(directory: data, autoStart: false)
        XCTAssertEqual(
            restored.tracks.first { $0.url.lastPathComponent == original.url.lastPathComponent }?.title, original.title)
    }
    @MainActor
    func testSelectiveRetryPreservesOtherFailures() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let a = music.appendingPathComponent("a.m4a")
        let b = music.appendingPathComponent("b.m4a")
        try Data([0]).write(to: a)
        try Data([0]).write(to: b)
        let store = LibraryStore(directory: root.appendingPathComponent("Data"), autoStart: false)
        await store.addSources([music])
        XCTAssertEqual(store.scanAudit?.issues.count, 2)
        try FileManager.default.removeItem(at: a)
        try FileManager.default.copyItem(at: demo, to: a)
        await store.retryFailedScan(only: a)
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.scanAudit?.failed, 1)
        XCTAssertEqual(store.scanAudit?.issues.map(\.url), [b])
    }
    @MainActor
    func testSourceScanReportsPersistWithoutReplacingTheGeneralReport() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let first = MusicSource(url: root.appendingPathComponent("One", isDirectory: true))
        let second = MusicSource(url: root.appendingPathComponent("Two", isDirectory: true))
        for source in [first, second] {
            try FileManager.default.createDirectory(at: source.url, withIntermediateDirectories: true)
        }
        let a = first.url.appendingPathComponent("a.m4a")
        let b = second.url.appendingPathComponent("b.m4a")
        try Data([0]).write(to: a)
        try Data([0]).write(to: b)
        let directory = root.appendingPathComponent("Data")
        let store = LibraryStore(directory: directory, autoStart: false)
        store.sources = [first, second]
        await store.scan()
        let general = store.scanAudit?.finishedAt
        await store.scan(newOnly: true, sourceID: first.id)
        await store.scan(newOnly: true, sourceID: second.id)
        XCTAssertEqual(store.scanReport(for: first.id)?.issues.map(\.url), [a])
        XCTAssertEqual(store.scanReport(for: second.id)?.issues.map(\.url), [b])
        XCTAssertEqual(store.scanAudit?.finishedAt, general)
        XCTAssertEqual(store.scanAudit?.failed, 2)
        try FileManager.default.removeItem(at: a)
        try FileManager.default.copyItem(at: demo, to: a)
        await store.retryFailedScan(only: a, sourceID: first.id)
        XCTAssertEqual(store.scanReport(for: first.id)?.failed, 0)
        XCTAssertEqual(store.sourceStates[second.id], "ready")
        let reopened = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(reopened.scanReport(for: first.id)?.failed, 0)
        XCTAssertEqual(reopened.scanReport(for: second.id)?.issues.map(\.url), [b])
        XCTAssertEqual(reopened.scanAudit?.failed, 2)
    }
    func testDailySQLiteBackupRestoresCorruptionAndPreservesOriginal() async throws {
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath().appendingPathComponent(
            UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let song = Track(
            url: URL(fileURLWithPath: "/music/a.flac"), title: "Saved song", artist: "Artist", album: "Album",
            genre: "Jazz", year: "2026", duration: 180)
        var writer: LibraryPersistence? = LibraryPersistence(directory: root)
        writer?.save(.init(tracks: [song], sources: [], edited: [], playlists: []))
        try await writer?.flush()
        let backups = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(backups.filter { $0.pathExtension == "sqlite" }.count, 1)
        writer = nil
        let damaged = Data("This is a damaged database".utf8)
        try damaged.write(to: root.appendingPathComponent("library.sqlite"))
        let restored = LibraryPersistence(directory: root)
        XCTAssertEqual(try restored.load()?.tracks.map(\.title), ["Saved song"])
        XCTAssertNotNil(restored.recoveredBackup)
        let preserved = try XCTUnwrap(
            FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil).first {
                $0.lastPathComponent.hasPrefix("Damaged-")
            })
        XCTAssertEqual(try Data(contentsOf: preserved.appendingPathComponent("library.sqlite")), damaged)
    }
    func testBackupRetentionAndMissingBackupDoesNotReplaceCorruptLibrary() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var db: OpaquePointer?
        XCTAssertEqual(sqlite3_open(":memory:", &db), SQLITE_OK)
        defer { sqlite3_close(db) }
        XCTAssertEqual(
            sqlite3_exec(db, "CREATE TABLE test (id INTEGER); INSERT INTO test VALUES (1);", nil, nil, nil), SQLITE_OK)
        for day in 0..<10 {
            try LibraryDatabaseBackups.create(
                from: db, directory: root, date: Date(timeIntervalSince1970: 1_700_000_000 + Double(day * 86400)))
        }
        let files = try FileManager.default.contentsOfDirectory(
            at: root.appendingPathComponent("Backups"), includingPropertiesForKeys: nil)
        XCTAssertEqual(files.count, 7)
        try FileManager.default.removeItem(at: root.appendingPathComponent("Backups"))
        let bytes = Data("corrupt original".utf8)
        let original = root.appendingPathComponent("library.sqlite")
        try bytes.write(to: original)
        let writer = LibraryPersistence(directory: root)
        XCTAssertThrowsError(try writer.load())
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    @MainActor
    func testCancellingRelocationKeepsOriginalSourceAndTags() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music")
        let destination = root.appendingPathComponent("Moved")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        try FileManager.default.copyItem(at: demo, to: music.appendingPathComponent("a.m4a"))
        try FileManager.default.copyItem(at: music, to: destination)
        let store = LibraryStore(directory: root.appendingPathComponent("Data"), autoStart: false)
        await store.addSources([music])
        let source = try XCTUnwrap(store.sources.first)
        let id = try XCTUnwrap(store.tracks.first?.id)
        store.applyTagEdits(ids: [id], changes: [.albumArtist: "My artist"])
        let task = Task { await store.relocateSource(source, to: destination) }
        while !store.relocatingSource { await Task.yield() }
        store.cancelSourceRelocation()
        await task.value
        XCTAssertFalse(store.relocatingSource)
        XCTAssertEqual(store.sources.first?.url, source.url)
        XCTAssertEqual(store.track(for: id)?.albumArtist, "My artist")
        XCTAssertNil(store.error)
        await store.relocateSource(source, to: destination)
        XCTAssertEqual(store.sources.first?.url, destination)
        XCTAssertEqual(store.tracks.first?.albumArtist, "My artist")
        await store.scan(force: true)
        XCTAssertEqual(store.tracks.first?.albumArtist, "My artist")
    }

    @MainActor
    func testLegacyWholeTrackCorrectionsMigrateWithoutLosingUserTags() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let music = root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at: music, withIntermediateDirectories: true)
        let file = music.appendingPathComponent("a.m4a")
        try FileManager.default.copyItem(at: demo, to: file)
        var legacy = try await MetadataReader.read(file)
        legacy.title = "Legacy corrected title"
        legacy.artist = "Legacy corrected artist"
        let data = root.appendingPathComponent("Data")
        let writer = LibraryPersistence(directory: data)
        writer.save(.init(tracks: [legacy], sources: [MusicSource(url: music)], edited: [legacy.id], playlists: []))
        try await writer.flush()
        let migrated = LibraryStore(directory: data, autoStart: false)
        await migrated.scan(force: true)
        XCTAssertEqual(migrated.tracks.first?.title, legacy.title)
        XCTAssertEqual(migrated.tracks.first?.artist, legacy.artist)
        try await migrated.flushSaving()
        let saved = try XCTUnwrap(writer.load())
        XCTAssertEqual(saved.tagEdits?[legacy.id]?.values["title"], legacy.title)
        XCTAssertEqual(saved.tagEdits?[legacy.id]?.values["artist"], legacy.artist)
    }

}
