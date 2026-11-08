import AVFoundation
import XCTest

@testable import PrismaMusic

final class LibraryTests: XCTestCase {
    func track(_ title: String, artist: String, genre: String, year: String) -> Track {
        Track(
            url: URL(fileURLWithPath: "/\(title).m4a"), title: title, artist: artist, album: "Colección", genre: genre,
            year: year, duration: 120)
    }
    func testFiltersCombineAndIgnoreAccents() {
        let tracks = [
            track("Órbita", artist: "Prisma", genre: "Ambient", year: "2026"),
            track("Horizonte", artist: "Prisma", genre: "Electronic", year: "2025"),
        ]
        XCTAssertEqual(
            LibraryQuery.filter(tracks, search: "orbita prisma", artist: "Prisma", genre: "Ambient", year: "2026").map(
                \.title), ["Órbita"])
        XCTAssertTrue(LibraryQuery.filter(tracks, search: "orbita", year: "2025").isEmpty)
        XCTAssertTrue(LibraryQuery.filter(tracks, favorites: true).isEmpty)
        XCTAssertEqual(LibraryQuery.filter(tracks, search: "2025 colección").count, 1)
    }
    func testSyncedLyricsMultipleTimestampsAndFractionalSeconds() {
        let lines = LyricLine.parse("[ar:Prisma]\n[00:05.25][00:10.50]Hola\n[00:02.00]Inicio\ninvalid")
        XCTAssertEqual(lines.map(\.time), [2, 5.25, 10.5])
        XCTAssertEqual(lines.map(\.text), ["Inicio", "Hola", "Hola"])
        XCTAssertTrue(LyricLine.parse("plain lyrics").isEmpty)
    }
    func testEmbeddedMetadataAndPlaybackDecode() async throws {
        let files = MetadataReader.files(in: demoDirectory)
        XCTAssertEqual(files.count, 3)
        let tracks = try await withThrowingTaskGroup(of: Track.self) { group in
            for file in files { group.addTask { try await MetadataReader.read(file) } }
            var result: [Track] = []
            for try await t in group { result.append(t) }
            return result
        }
        XCTAssertEqual(Set(tracks.map(\.title)), Set(["Órbita", "Horizonte", "Luz de agua"]))
        XCTAssertEqual(Set(tracks.map(\.year)), Set(["2026", "2025", "2024"]))
        XCTAssertEqual(Set(tracks.map(\.genre)), Set(["Ambient", "Electronic", "Downtempo"]))
        for track in tracks {
            XCTAssertTrue(track.duration > 23 && track.duration < 25)
            XCTAssertEqual(track.format, "M4A · AAC")
            XCTAssertEqual(track.sampleRate, 22050)
            XCTAssertEqual(track.channels, 1)
            XCTAssertTrue((track.bitrate ?? 0) > 1000)
            XCTAssertEqual(track.fileSize, Int64(try Data(contentsOf: track.url).count))
            XCTAssertTrue(track.qualitySummary.contains("kb/s"))
            XCTAssertFalse(track.artist == "—")
            XCTAssertFalse(track.album == "—")
            XCTAssertFalse(LyricLine.parse(track.lyrics ?? "").isEmpty)
            let player = try AVAudioPlayer(contentsOf: track.url)
            XCTAssertTrue(player.prepareToPlay())
        }
    }
    @MainActor
    func testScanPersistenceEditsFavoritesAndUnavailableSource() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let audio = root.appendingPathComponent("Music", isDirectory: true)
        try FileManager.default.createDirectory(at: audio, withIntermediateDirectories: true)
        let file = audio.appendingPathComponent("test.m4a")
        try FileManager.default.copyItem(at: MetadataReader.files(in: demoDirectory)[0], to: file)
        let store = LibraryStore(directory: root.appendingPathComponent("State"), autoStart: false)
        await store.addSources([audio])
        XCTAssertEqual(store.tracks.count, 1)
        store.favorite(store.tracks[0])
        var edited = store.tracks[0]
        edited.title = "Mi edición"
        edited.genre = "Jazz"
        store.update(edited)
        try FileManager.default.setAttributes(
            [.modificationDate: Date().addingTimeInterval(3)], ofItemAtPath: file.path)
        await store.scan()
        XCTAssertEqual(store.tracks[0].title, "Mi edición")
        XCTAssertEqual(store.tracks[0].genre, "Jazz")
        XCTAssertTrue(store.tracks[0].favorite)
        let restored = LibraryStore(directory: root.appendingPathComponent("State"), autoStart: false)
        XCTAssertEqual(restored.tracks[0].title, "Mi edición")
        let disconnected = root.appendingPathComponent("Disconnected", isDirectory: true)
        try FileManager.default.moveItem(at: audio, to: disconnected)
        await restored.scan()
        XCTAssertEqual(restored.tracks.count, 1, "A disconnected NAS must not erase the library")
        try FileManager.default.moveItem(at: disconnected, to: audio)
        try FileManager.default.removeItem(at: file)
        await restored.scan()
        XCTAssertTrue(restored.tracks.isEmpty, "Deleted files should disappear from available sources")
    }
    func testProviderQueryEncodesSpecialCharacters() {
        let url = OnlineMetadata.url(
            "https://lrclib.net/api/get", ["artist_name": "A & B", "track_name": "¿Canción? #1"])
        let items = URLComponents(url: url, resolvingAgainstBaseURL: false)!.queryItems!
        XCTAssertEqual(items.first { $0.name == "artist_name" }?.value, "A & B")
        XCTAssertEqual(items.first { $0.name == "track_name" }?.value, "¿Canción? #1")
        XCTAssertEqual(OnlineMetadata.normalized("ÓRBITA"), "orbita")
    }
    func testLiveProvidersWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_LIVE_NETWORK"] == "1" else {
            throw XCTSkip("Opt-in live provider check")
        }
        let song = Track(
            url: URL(fileURLWithPath: "/test.m4a"), title: "Yellow", artist: "Coldplay", album: "Parachutes",
            genre: "Alternative", year: "2000", duration: 266)
        let artwork = try await OnlineMetadata.artwork(for: song)
        XCTAssertNotNil(artwork)
        XCTAssertTrue((artwork?.0.count ?? 0) > 100)
        let lyrics = try await OnlineMetadata.lyrics(for: song)
        XCTAssertFalse(lyrics?.isEmpty ?? true)
    }
    private var demoDirectory: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo", isDirectory: true)
    }
}
