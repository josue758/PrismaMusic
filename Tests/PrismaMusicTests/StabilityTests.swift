import AVFoundation
import XCTest

@testable import PrismaMusic

final class StabilityTests: XCTestCase {
    @MainActor
    func testPlayNextAnchorsTheCurrentTrackAndCanSaveTheUpcomingQueue() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let items = (0...2).map { index in
            Track(url: directory.appendingPathComponent("\(index).flac"), title: "\(index)", artist: "Artist",
                  album: "Album", genre: "", year: "", duration: 30)
        }
        store.tracks = items
        store.queue = [items[1].id]
        store.enqueue(items[2], next: true)
        XCTAssertEqual(store.queue, [items[2].id, items[1].id])
        store.currentID = items[0].id
        store.enqueue(items[1], next: true)
        XCTAssertEqual(store.queue, items.map(\.id))
        XCTAssertTrue(store.saveUpcomingPlaylist(" Próximas "))
        XCTAssertEqual(store.playlists.first?.name, "Próximas")
        XCTAssertEqual(store.playlists.first?.trackIDs, [items[1].id, items[2].id])
        XCTAssertEqual(store.section, "home")
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.playlists, store.playlists)
    }
    @MainActor
    func testUpcomingBatchMoveAndUndoKeepPastAndCurrentTracks() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let tracks = (0..<6).map { index in
            Track(url: directory.appendingPathComponent("\(index).flac"), title: "\(index)", artist: "Artist",
                  album: "Album", genre: "", year: "", duration: 30)
        }
        store.tracks = tracks
        store.queue = tracks.map(\.id)
        store.currentID = tracks[1].id
        XCTAssertFalse(store.moveUpcoming([tracks[1].id, tracks[3].id], before: tracks[2].id))
        XCTAssertTrue(store.moveUpcoming([tracks[3].id, tracks[5].id], before: tracks[2].id))
        XCTAssertEqual(store.queue, [0, 1, 3, 5, 2, 4].map { tracks[$0].id })
        store.undoFeedback()
        XCTAssertEqual(store.queue, tracks.map(\.id))
        XCTAssertTrue(store.moveUpcoming([tracks[3].id, tracks[5].id], before: tracks[2].id))
        store.removeQueued(ids: [tracks[1].id, tracks[3].id, tracks[5].id])
        XCTAssertEqual(store.queue, [0, 1, 2, 4].map { tracks[$0].id })
        store.undoFeedback()
        XCTAssertEqual(store.queue, [0, 1, 3, 5, 2, 4].map { tracks[$0].id })
    }

    @MainActor
    func testFolderFilterScopesAlbumAndIncrementalScan() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let local = directory.appendingPathComponent("Local", isDirectory: true)
        let remote = directory.appendingPathComponent("Remote", isDirectory: true)
        try FileManager.default.createDirectory(at: local, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: remote, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let a = local.appendingPathComponent("A.m4a")
        let b = remote.appendingPathComponent("B.m4a")
        try FileManager.default.copyItem(at: demo, to: a)
        try FileManager.default.copyItem(at: demo, to: b)
        let store = LibraryStore(directory: directory.appendingPathComponent("State"), autoStart: false)
        let one = MusicSource(url: local)
        let two = MusicSource(url: remote)
        store.sources = [one, two]
        await store.scan(newOnly: true, sourceID: one.id)
        XCTAssertEqual(store.tracks.map(\.id), [a.path])
        await store.scan(newOnly: true, sourceID: two.id)
        XCTAssertEqual(Set(store.tracks.map(\.id)), [a.path, b.path])
        store.section = "albums"
        store.sourceFilter = .folder(one.id)
        XCTAssertEqual(store.filtered.map(\.id), [a.path])
        XCTAssertEqual(store.albumCollection(a.path)?.tracks.map(\.id), [a.path])
        store.clearFilters()
        XCTAssertEqual(store.filtered.count, 2)
    }

    @MainActor
    func testWindowsMigrationMergesLocallyAndCanBeRepeated() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let track = Track(url: URL(fileURLWithPath: "/Volumes/Music/Artist/Album/Test.flac"), title: "Original",
                          artist: "Artist", album: "Album", genre: "", year: "", duration: 10)
        let input = Data(#"""
            {
              "Tracks":[{"Path":"Z:\\Artist\\Album\\Test.flac"}],
              "Favorites":["Z:\\Artist\\Album\\Test.flac", "C:\\Unknown\\Missing.flac"],
              "Playlists":{"List":["Z:\\Artist\\Album\\Test.flac"]},
              "SmartPlaylists":{"Jazz":{"Genre":"Jazz","SampleRate":96000}},
              "TagEdits":{"Z:\\Artist\\Album\\Test.flac":{"Title":"Incoming","Genre":"Jazz","Number":2}}
            }
            """#.utf8)
        let preview = try LibraryMigration.resolve(input, tracks: [track])
        XCTAssertEqual(preview.relocated, 1)
        XCTAssertEqual(preview.unmatched.count, 1)
        let store = LibraryStore(directory: folder, autoStart: false)
        store.tracks = [track]
        store.applyTagEdits(ids: [track.id], changes: [.title: "Local"])
        store.createPlaylist("List")
        XCTAssertTrue(store.importLibraryMigration(preview))
        XCTAssertTrue(store.importLibraryMigration(preview))
        XCTAssertEqual(store.playlists.count, 3)
        XCTAssertEqual(store.playlists.first { $0.rules != nil }?.rules?.sampleRate, 96_000)
        try await store.flushSaving()
        let restored = LibraryStore(directory: folder, autoStart: false)
        XCTAssertEqual(restored.tracks.first?.title, "Local")
        XCTAssertEqual(restored.tracks.first?.genre, "Jazz")
        XCTAssertEqual(restored.tracks.first?.trackNumber, 2)
        XCTAssertEqual(restored.tracks.first?.favorite, true)
    }

    func testVisualizerFrameRatesPersistAndUseTheirTargetIntervals() throws {
        for rate in [24.0, 30.0, 60.0] {
            var preferences = ListeningPreferences()
            preferences.visualizerFPS = rate
            let data = try JSONEncoder().encode(preferences)
            let restored = try JSONDecoder().decode(ListeningPreferences.self, from: data)
            XCTAssertEqual(restored.visualizerFPS, rate)
            XCTAssertEqual(restored.visualizerFrameInterval, 1 / rate, accuracy: 0.00001)
        }
        let invalid = try JSONDecoder().decode(ListeningPreferences.self, from: Data(#"{"visualizerFPS":0}"#.utf8))
        XCTAssertEqual(invalid.visualizerFPS, 30)
    }

    func testPlaylistImportResolvesLocalAndUniqueNetworkPathsButRejectsAmbiguity() {
        let url = URL(fileURLWithPath: "/library/mix.m3u")
        func track(_ path: String) -> Track {
            Track(url: URL(fileURLWithPath: path), title: "Track", artist: "Artist", album: "Album", genre: "",
                  year: "", duration: 1)
        }
        let local = track("/library/local.flac")
        let moved = track("/Volumes/Music/Artist/Album/remote.flac")
        let first = track("/Volumes/One/Album/ambiguous.flac")
        let second = track("/Volumes/Two/Album/ambiguous.flac")
        let entries = """
            #EXTM3U
            local.flac
            Z:\\Artist\\Album\\remote.flac
            smb://server/Artist/Album/remote.flac
            Z:\\Album\\ambiguous.flac
            https://example.org/track
            """
        let preview = PlaylistImport.resolve(entries, from: url, tracks: [local, moved, first, second])
        XCTAssertEqual(preview.tracks.map(\.id), [local.id, moved.id])
        XCTAssertEqual(preview.relocated, 1)
        XCTAssertEqual(preview.unmatched.count, 2)
    }

    func testSpectrumFindsTheBandWithTheTestTone() throws {
        let format = try XCTUnwrap(AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 1))
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024))
        let spectrum = try XCTUnwrap(PlaybackSpectrum())
        buffer.frameLength = buffer.frameCapacity
        let bin = 24
        for sample in 0..<1024 {
            buffer.floatChannelData![0][sample] = Float(sin(2 * Double.pi * Double(bin * sample) / 1024) * 0.7)
        }
        spectrum.measure(buffer) { bands in
            XCTAssertEqual(bands.count, 48)
            let strongest = bands.enumerated().max { $0.element < $1.element }
            XCTAssertTrue((24...28).contains(strongest?.offset ?? -1))
            XCTAssertGreaterThan(strongest?.element ?? 0, 0.8)
            XCTAssertLessThan(bands.last ?? 1, 0.1)
        }
    }

    @MainActor
    func testManualSnapshotRestorePreservesCurrentLibraryBeforeApplying() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let track = Track(url: directory.appendingPathComponent("song.flac"), title: "Original",
                          artist: "Artist", album: "Album", genre: "", year: "", duration: 1)
        do {
            let store = LibraryStore(directory: directory, autoStart: false)
            store.tracks = [track]
            store.save()
            try await store.flushSaving()
            let backups = try await store.libraryBackups()
            let backup = try XCTUnwrap(backups.first)
            let count = try await store.backupTrackCount(backup.id)
            XCTAssertEqual(count, 1)
            store.tracks[0].title = "New title"
            store.save()
            try await store.flushSaving()
            try await store.stageLibraryRestore(backup.id)
            XCTAssertEqual(store.tracks.first?.title, "New title")
        }
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.tracks.first?.title, "Original")
        let preserved = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            .first { $0.hasPrefix("BeforeRestore-") }
        XCTAssertNotNil(preserved)
    }

    @MainActor
    func testDuplicateHidingKeepsOneVisibleAndRestoresAfterReload() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let first = Track(url: directory.appendingPathComponent("first.flac"), title: "Song",
                          artist: "Artist", album: "Album", genre: "", year: "", duration: 90)
        var second = first
        second.url = directory.appendingPathComponent("copy.flac")
        let store = LibraryStore(directory: directory, autoStart: false)
        store.tracks = [first, second]
        store.setDuplicateVisibility([first.id, second.id], hidden: true, in: [first, second])
        XCTAssertEqual(store.filtered.count, 2)
        store.setDuplicateVisibility([second.id], hidden: true, in: [first, second])
        XCTAssertEqual(store.filtered.map(\.id), [first.id])
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.filtered.map(\.id), [first.id])
        let hidden = try XCTUnwrap(LibraryTagReview.find(restored.tracks).first { $0.kind == .hiddenCopies })
        restored.setDuplicateVisibility([second.id], hidden: false, in: hidden.tracks)
        XCTAssertEqual(restored.filtered.count, 2)
        try await restored.flushSaving()
    }

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
    func testAppliedReplayGainReportsOnlyTheActualContributionToTheAudioGraph() throws {
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let gain = ReplayGain([
            "REPLAYGAIN_TRACK_GAIN": "+24 dB", "REPLAYGAIN_TRACK_PEAK": "0.01",
            "REPLAYGAIN_ALBUM_GAIN": "-7 dB",
        ])
        let audio = try AudioPlayback(file: AVAudioFile(forReading: demo), replayGain: gain)
        var preferences = ListeningPreferences()
        preferences.eqEnabled = true
        preferences.preamp = 6
        preferences.replayGain = .track
        audio.apply(preferences)
        XCTAssertEqual(audio.equalizer.globalGain, 24)
        XCTAssertEqual(audio.appliedReplayGain, 18)
        preferences.replayGain = .album
        audio.apply(preferences)
        XCTAssertEqual(audio.appliedReplayGain, -7)
        audio.setReplayGain(nil)
        XCTAssertEqual(audio.appliedReplayGain, 0)
        let direct = try AudioPlayback(file: AVAudioFile(forReading: demo), direct: true, replayGain: gain)
        direct.apply(preferences)
        XCTAssertEqual(direct.appliedReplayGain, 0)
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
