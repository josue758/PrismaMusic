import AVFoundation
import XCTest

@testable import PrismaMusic

final class ListeningTests: XCTestCase {
    func testHeadroomAndPresetValidation() throws {
        var p = ListeningPreferences()
        p.eqEnabled = true
        p.selectPreset("electronic")
        p.preamp = -2
        XCTAssertEqual(p.effectivePreamp, -7)
        p.autoHeadroom = false
        XCTAssertEqual(p.effectivePreamp, -2)
        p.eqEnabled = false
        XCTAssertEqual(p.effectivePreamp, 0)
        p.eqGains = [Float.nan]
        p.playbackRate = 99
        p.balance = -3
        p.sanitize()
        XCTAssertEqual(p.eqGains.count, 10)
        XCTAssertEqual(p.playbackRate, 1.5)
        XCTAssertEqual(p.balance, -1)
        XCTAssertEqual(try JSONDecoder().decode(ListeningPreferences.self, from: JSONEncoder().encode(p)), p)
    }
    @MainActor
    func testPlaylistsQueueAndPreferencesPersist() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        let store = LibraryStore(directory: directory, autoStart: false)
        let a = Track(
            url: URL(fileURLWithPath: "/a.flac"), title: "A", artist: "Artist", album: "Album", genre: "Jazz",
            year: "2026", duration: 12, format: "FLAC")
        let b = Track(
            url: URL(fileURLWithPath: "/b.mp3"), title: "B", artist: "Artist", album: "Album", genre: "Rock",
            year: "2026", duration: 14, format: "MP3")
        store.tracks = [a, b]
        store.createPlaylist("Noches")
        let playlist = store.playlists[0]
        store.add(a, to: playlist)
        store.add(a, to: playlist)
        store.add(b, to: playlist)
        XCTAssertEqual(store.playlists[0].trackIDs.count, 2)
        store.section = "playlist:\(playlist.id)"
        XCTAssertEqual(store.filtered.map(\.id), [a.id, b.id])
        store.removeFromPlaylist(a)
        XCTAssertEqual(store.filtered.map(\.id), [b.id])
        store.preferences.eqEnabled = true
        store.preferences.selectPreset("jazz")
        store.preferences.lyricsOffset = 1.2
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.preferences.eqGains, ListeningPreferences.presets["jazz"])
        XCTAssertEqual(restored.preferences.lyricsOffset, 1.2)
        XCTAssertEqual(restored.playlists[0].trackIDs, [b.id])
        store.currentID = a.id
        store.queue = [a.id, b.id]
        store.enqueue(b, next: true)
        XCTAssertEqual(store.queue, [a.id, b.id])
        store.removeQueued(a)
        XCTAssertEqual(store.queue.count, 2)
        store.moveQueued(b, direction: -1)
        XCTAssertEqual(store.queue, [b.id, a.id])
        store.shuffle = true
        XCTAssertEqual(store.queue.first, a.id)
        XCTAssertEqual(Set(store.queue), Set([a.id, b.id]))
        store.shuffle = false
        store.section = "lossless"
        XCTAssertEqual(store.filtered.map(\.id), [a.id])
        store.setSleepTimer(minutes: 15)
        XCTAssertNotNil(store.sleepDeadline)
        XCTAssertEqual(store.sleepRemaining, 900)
        store.setSleepTimer(minutes: nil)
        XCTAssertNil(store.sleepDeadline)
    }
    @MainActor
    func testVersionOneLibraryMigratesWithoutLosingTags() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: directory) }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var original = Track(
            url: URL(fileURLWithPath: "/old.m4a"), title: "Título editado", artist: "Artista", album: "Álbum",
            genre: "Jazz", year: "1997", duration: 123)
        original.favorite = true
        var object = try JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as! [String: Any]
        object.removeValue(forKey: "playCount")
        object.removeValue(forKey: "lastPlayed")
        let old: [String: Any] = ["tracks": [object], "sources": [], "edited": [original.id]]
        try JSONSerialization.data(withJSONObject: old).write(to: directory.appendingPathComponent("library.json"))
        let store = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(store.tracks.count, 1)
        XCTAssertEqual(store.tracks[0].title, original.title)
        XCTAssertTrue(store.tracks[0].favorite)
        XCTAssertTrue(store.playlists.isEmpty)
        store.createPlaylist("Nueva")
        try await store.flushSaving()
        let restored = LibraryStore(directory: directory, autoStart: false)
        XCTAssertEqual(restored.tracks[0].genre, "Jazz")
        XCTAssertEqual(restored.playlists[0].name, "Nueva")
    }
    @MainActor
    func testCompressedDemoPlaybackSeekAndStereoBalance() throws {
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let audio = try AudioPlayback(contentsOf: demo)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try audio.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        var prefs = ListeningPreferences()
        prefs.balance = 1
        prefs.playbackRate = 1.25
        prefs.eqEnabled = true
        prefs.selectPreset("jazz")
        audio.apply(prefs)
        XCTAssertTrue(audio.play())
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        var left = 0.0
        var right = 0.0
        for iteration in 0..<80 {
            if try audio.engine.renderOffline(1024, to: buffer) == .success && iteration > 20 {
                for i in 0..<Int(buffer.frameLength) {
                    left += pow(Double(buffer.floatChannelData![0][i]), 2)
                    right += pow(Double(buffer.floatChannelData![1][i]), 2)
                }
            }
        }
        XCTAssertGreaterThan(right, 0.01)
        XCTAssertGreaterThan(right, left * 2, "Stereo balance must affect the actual audio output")
        XCTAssertGreaterThan(audio.currentTime, 0)
        audio.currentTime = 5
        XCTAssertEqual(audio.currentTime, 5, accuracy: 0.1)
        audio.pause()
        XCTAssertFalse(audio.isPlaying)
        XCTAssertTrue(audio.play())
        audio.stop()
        XCTAssertEqual(audio.currentTime, 0)
    }
    @MainActor
    func testRealEqualizerRendersAndAttenuatesOneKilohertz() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".wav")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        do {
            let file = try AVAudioFile(forWriting: url, settings: format.settings)
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 96000)!
            buffer.frameLength = 96000
            for channel in 0..<2 {
                for i in 0..<96000 {
                    buffer.floatChannelData![channel][i] = sin(Float(i) * 2 * .pi * 1000 / 48000) * 0.1
                }
            }
            try file.write(from: buffer)
        }
        func render(attenuated: Bool) throws -> Double {
            let player = try AudioPlayback(contentsOf: url)
            try player.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
            var prefs = ListeningPreferences()
            prefs.eqEnabled = attenuated
            prefs.eqGains[5] = -12
            player.apply(prefs)
            XCTAssertEqual(player.equalizer.bands[5].gain, -12)
            XCTAssertTrue(player.play())
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
            var sum = 0.0
            var count = 0
            for iteration in 0..<60 {
                let status = try player.engine.renderOffline(1024, to: buffer)
                if status == .success && iteration > 12 {
                    for i in 0..<Int(buffer.frameLength) {
                        let x = Double(buffer.floatChannelData![0][i])
                        sum += x * x
                        count += 1
                    }
                }
            }
            XCTAssertGreaterThan(count, 1000)
            player.pause()
            XCTAssertFalse(player.isPlaying)
            player.currentTime = 0.5
            XCTAssertEqual(player.currentTime, 0.5, accuracy: 0.001)
            return sqrt(sum / Double(max(1, count)))
        }
        let flat = try render(attenuated: false)
        let eq = try render(attenuated: true)
        XCTAssertGreaterThan(flat, 0.01)
        XCTAssertLessThan(eq, flat * 0.5, "The actual processed audio must change, not just the sliders")
    }
    @MainActor
    func testMountedNASStreamsAndSeeksWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["PRISMA_NAS_FILE"] else {
            throw XCTSkip("Opt-in mounted NAS streaming check")
        }
        let url = URL(fileURLWithPath: path)
        let track = try await MetadataReader.read(url)
        XCTAssertEqual(track.sourceIsNetwork, true)
        XCTAssertGreaterThan(track.duration, 10)
        XCTAssertGreaterThan(track.fileSize ?? 0, 1000)
        XCTAssertGreaterThan(track.bitrate ?? 0, 0)
        let openedAt = Date()
        let opened = try await AudioFileLoader.shared.open(url)
        XCTAssertFalse(opened.openedOnMainThread)
        let openSeconds = Date().timeIntervalSince(openedAt)
        let player = try AudioPlayback(file: opened.file)
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        try player.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        func renderEnergy() throws -> Double {
            var energy = 0.0
            for _ in 0..<60 {
                if try player.engine.renderOffline(1024, to: buffer) == .success {
                    for channel in 0..<2 {
                        for index in 0..<Int(buffer.frameLength) {
                            energy += pow(Double(buffer.floatChannelData![channel][index]), 2)
                        }
                    }
                }
            }
            return energy
        }
        XCTAssertTrue(player.play())
        XCTAssertGreaterThan(try renderEnergy(), 0.01, "Actual audio must decode from the network file")
        let target = min(30, track.duration / 2)
        player.currentTime = target
        XCTAssertEqual(player.currentTime, target, accuracy: 0.1)
        XCTAssertGreaterThan(try renderEnergy(), 0.01, "Audio must also decode after a seek")
        player.pause()
        XCTAssertFalse(player.isPlaying)
        XCTAssertTrue(player.play())
        XCTAssertGreaterThan(try renderEnergy(), 0.01)
        player.stop()
        print(
            "PRISMA_NAS format=\(track.format ?? "?") rate=\(track.sampleRate ?? 0) bits=\(track.bitDepth ?? 0) bitrate=\(track.bitrate ?? 0) decoded-and-seeked=true background-open-seconds=\(openSeconds)"
        )
    }

}
