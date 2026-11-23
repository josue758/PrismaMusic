import AVFoundation
import XCTest

@testable import PrismaMusic

final class StabilityTests: XCTestCase {
    func testReplayGainUsesAlbumAndLimitsPeakWithEqualizerHeadroom() {
        let gain = ReplayGain([
            "REPLAYGAIN_TRACK_GAIN": "-8.0 dB", "REPLAYGAIN_TRACK_PEAK": "0.9",
            "REPLAYGAIN_ALBUM_GAIN": "+8.0 dB", "REPLAYGAIN_ALBUM_PEAK": "1.0",
        ])
        XCTAssertEqual(gain.decibels(.off, eqBoost: 3), 0)
        XCTAssertEqual(gain.decibels(.track, eqBoost: 3), -8)
        XCTAssertEqual(gain.decibels(.album, eqBoost: 3), -3)
        XCTAssertEqual(ReplayGain(["REPLAYGAIN_TRACK_GAIN": "nan"]).decibels(.album, eqBoost: 0), 0)
        XCTAssertEqual(ReplayGain(["REPLAYGAIN_TRACK_GAIN": "-4 dB"]).decibels(.album, eqBoost: 0), -4)
    }

    @MainActor
    func testSmartPlaylistUpdatesAndPersistsAlongsideLegacyLists() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let legacy = try JSONDecoder().decode(
            Playlist.self, from: Data(#"{"id":"6904AB55-D070-4D4D-9AED-84E4B4D47DEE","name":"Manual","trackIDs":[]}"#.utf8))
        XCTAssertNil(legacy.rules)
        let store = LibraryStore(directory: folder, autoStart: false)
        store.playlists = [legacy]
        var jazz = Track(
            url: folder.appendingPathComponent("jazz.flac"), title: "Jazz", artist: "Artist", album: "Album",
            genre: "Jazz", year: "2020", duration: 10, format: "FLAC", sampleRate: 96_000, addedAt: .now)
        var pop = jazz
        pop.url = folder.appendingPathComponent("pop.flac")
        pop.genre = "Pop"
        var old = jazz
        old.url = folder.appendingPathComponent("old.flac")
        old.addedAt = nil
        store.tracks = [jazz, pop, old]
        let rules = SmartPlaylistRules(genre: "jazz", codec: "FLAC", sampleRate: 96_000, unplayed: true,
                                       addedThisMonth: true)
        store.createPlaylist("Mix", rules: rules)
        XCTAssertEqual(store.filtered.map(\.id), [jazz.id])
        jazz.playCount = 1
        store.tracks = [jazz, pop, old]
        XCTAssertTrue(store.filtered.isEmpty)
        store.save()
        try await store.flushSaving()
        let restored = LibraryStore(directory: folder, autoStart: false)
        XCTAssertEqual(restored.playlists.map(\.rules), [nil, rules])
        XCTAssertEqual(restored.tracks.first(where: { $0.id == jazz.id })?.addedAt, jazz.addedAt)
    }

    @MainActor
    func testConsecutiveMatchingFilesRenderWithoutSilenceAndMixedRatesFallback() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        func file(_ name: String, rate: Double, value: Float) throws -> AVAudioFile {
            let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: rate, channels: 2))
            let url = folder.appendingPathComponent(name + ".wav")
            let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4096))
            buffer.frameLength = buffer.frameCapacity
            for channel in 0..<2 {
                for frame in 0..<Int(buffer.frameLength) { buffer.floatChannelData![channel][frame] = value }
            }
            let writer = try AVAudioFile(forWriting: url, settings: format.settings)
            try writer.write(from: buffer)
            writer.close()
            return try AVAudioFile(forReading: url)
        }
        let first = try file("first", rate: 48_000, value: 0.2)
        let second = try file("second", rate: 48_000, value: -0.2)
        let mixed = try file("mixed", rate: 96_000, value: -0.2)
        let audio = try AudioPlayback(file: first, direct: true)
        let format = first.processingFormat
        try audio.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 256)
        XCTAssertTrue(audio.play())
        audio.scheduleSuccessor(id: "mixed", file: mixed, gain: nil) { _ in }
        XCTAssertNil(audio.queuedSuccessorID)
        audio.scheduleSuccessor(id: "second", file: second, gain: nil) { _ in }
        XCTAssertEqual(audio.queuedSuccessorID, "second")
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 256))
        var samples: [Float] = []
        for _ in 0..<36 {
            if try audio.engine.renderOffline(256, to: buffer) == .success {
                samples.append(contentsOf: UnsafeBufferPointer(
                    start: buffer.floatChannelData![0], count: Int(buffer.frameLength)))
            }
        }
        let boundary = try XCTUnwrap(samples.firstIndex { $0 < -0.19 })
        XCTAssertGreaterThan(boundary, 0)
        XCTAssertGreaterThan(samples[boundary - 1], 0.19)
        audio.stop()
        XCTAssertNil(audio.queuedSuccessorID)
    }
}
