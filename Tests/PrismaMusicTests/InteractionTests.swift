import XCTest

@testable import PrismaMusic

final class InteractionTests: XCTestCase {
    func testAnimationClockFreezesAndResumesWithoutJumping() {
        let origin = Date(timeIntervalSinceReferenceDate: 0)
        var clock = MotionClock()
        clock.setRunning(true, at: origin)
        clock.setRunning(true, at: origin.addingTimeInterval(10))
        XCTAssertEqual(clock.elapsed(at: origin.addingTimeInterval(15)), 15)
        clock.setRunning(false, at: origin.addingTimeInterval(15))
        XCTAssertEqual(clock.elapsed(at: origin.addingTimeInterval(100)), 15)
        clock.setRunning(true, at: origin.addingTimeInterval(100))
        XCTAssertEqual(clock.elapsed(at: origin.addingTimeInterval(103)), 18)
        clock.setRunning(false, at: origin.addingTimeInterval(103))
        clock.setRunning(false, at: origin.addingTimeInterval(200))
        XCTAssertEqual(clock.elapsed(at: origin.addingTimeInterval(250)), 18)
    }
    @MainActor
    func testUndoRejectsStaleNoticesAndKeepsThePlayingTrackInQueue() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let tracks = (0..<3).map { i in
            Track(
                url: URL(fileURLWithPath: "/\(i).m4a"), title: "Track \(i)", artist: "Prisma", album: "Test",
                genre: "Ambient", year: "2026", duration: 30)
        }
        store.tracks = tracks
        store.queue = [tracks[0].id, tracks[1].id]
        store.currentID = tracks[0].id
        store.enqueue(tracks[2], next: true)
        let stale = try XCTUnwrap(store.feedback?.id)
        store.favorite(tracks[1])
        let latest = try XCTUnwrap(store.feedback?.id)
        store.undoFeedback(id: stale)
        XCTAssertTrue(store.tracks[1].favorite)
        XCTAssertEqual(store.feedback?.id, latest)
        store.undoFeedback(id: latest)
        XCTAssertFalse(store.tracks[1].favorite)
        store.queue = [tracks[0].id, tracks[1].id]
        store.enqueue(tracks[2], next: true)
        store.currentID = tracks[2].id
        store.undoFeedback()
        XCTAssertEqual(store.queue, [tracks[0].id, tracks[2].id, tracks[1].id])
        store.preferences.showFeedback = false
        XCTAssertNil(store.feedback)
        store.favorite(tracks[0])
        XCTAssertNil(store.feedback)
    }
    @MainActor
    func testUndoPlaylistRemovalRestoresItsContentsAndPersists() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let track = Track(
            url: URL(fileURLWithPath: "/test.m4a"), title: "Test", artist: "Prisma", album: "Test", genre: "Jazz",
            year: "2026", duration: 30)
        store.tracks = [track]
        store.createPlaylist("Noche")
        let playlist = store.playlists[0]
        store.add(track, to: playlist)
        store.removePlaylist(store.playlists[0])
        XCTAssertTrue(store.playlists.isEmpty)
        store.undoFeedback()
        XCTAssertEqual(store.playlists[0].id, playlist.id)
        XCTAssertEqual(store.playlists[0].trackIDs, [track.id])
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.playlists, store.playlists)
        XCTAssertEqual(restored.tracks.count, 1)
    }
}
