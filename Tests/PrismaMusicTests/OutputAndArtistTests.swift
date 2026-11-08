import AVFoundation
import AudioToolbox
import XCTest

@testable import PrismaMusic

final class OutputAndArtistTests: XCTestCase {
    private func temporary() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }
    func testOutputPreferencesMigrateAndPreserveDSP() throws {
        var preferences = try JSONDecoder().decode(ListeningPreferences.self, from: Data("{}".utf8))
        XCTAssertEqual(preferences.outputDeviceUID, "")
        XCTAssertFalse(preferences.directOutput)
        XCTAssertFalse(preferences.exclusiveOutput)
        preferences.selectPreset("jazz")
        preferences.eqEnabled = true
        preferences.balance = 0.3
        preferences.playbackRate = 1.2
        preferences.outputDeviceUID = "stable-device-uid"
        preferences.directOutput = true
        preferences.exclusiveOutput = true
        let decoded = try JSONDecoder().decode(ListeningPreferences.self, from: JSONEncoder().encode(preferences))
        XCTAssertEqual(decoded, preferences)
        XCTAssertEqual(decoded.eqPreset, "jazz")
        XCTAssertEqual(decoded.balance, 0.3)
    }
    func testNativeRateEligibilityAndWirelessRejection() async throws {
        var device = AudioOutputDevice(
            id: 0, uid: "test", name: "Test DAC", sampleRate: 48000, channels: 2,
            transport: kAudioDeviceTransportTypeUSB, availableRates: [44100...44100, 48000...192000])
        XCTAssertTrue(device.supports(44100))
        XCTAssertTrue(device.supports(96000))
        XCTAssertFalse(device.supports(22050))
        XCTAssertFalse(device.supports(.nan))
        device.transport = kAudioDeviceTransportTypeAirPlay
        let controller = AudioDeviceController()
        do {
            _ = try await controller.prepare(device, direct: true, exclusive: true, rate: 48000)
            XCTFail("Wireless output must not claim direct mode")
        } catch { XCTAssertEqual(error.localizedDescription, "directUnsupported") }
        await controller.release()
    }
    func testArtistCollaborationsGroupingAndMatching() {
        let a = Track(
            url: URL(fileURLWithPath: "/a.flac"), title: "A", artist: "Jorge Drexler; Noga Erez;Jorge Drexler",
            album: "Album", genre: "Pop", year: "2022", duration: 12)
        let b = Track(
            url: URL(fileURLWithPath: "/b.flac"), title: "B", artist: "Noga Erez", album: "Other", genre: "Pop",
            year: "2024", duration: 15)
        XCTAssertEqual(ArtistIdentity.names(a.artist), ["Jorge Drexler", "Noga Erez"])
        XCTAssertEqual(LibraryQuery.filter([a, b], artist: "Noga Erez").count, 2)
        XCTAssertEqual(LibraryStatistics(tracks: [a, b]).artists, ["Jorge Drexler", "Noga Erez"])
        XCTAssertEqual(LibraryQueryCache(tracks: [a, b]).artists.first { $0.key == "Noga Erez" }?.value.count, 2)
        let collection = ArtistCollection(name: "Noga Erez", library: [a, b])
        XCTAssertEqual(collection.albums.count, 2)
        XCTAssertEqual(collection.duration, 27)
        XCTAssertEqual(ArtistIdentity.names("AC/DC"), ["AC/DC"])
        XCTAssertTrue(ArtistIdentity.titleMatches("Aitana (cantante)", name: "Aitana"))
        XCTAssertFalse(ArtistIdentity.titleMatches("Aitana Sánchez-Gijón", name: "Aitana"))
        XCTAssertTrue(ArtistProfileService.isMusical("Aitana es una cantante española."))
        XCTAssertFalse(ArtistProfileService.isMusical("Aitana es una montaña de España."))
    }
    @MainActor
    func testArtistCollectionCacheInvalidatesOnLibraryEdits() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(directory: root, autoStart: false)
        let track = Track(
            url: URL(fileURLWithPath: "/a.flac"), title: "A", artist: "Artist", album: "One", genre: "Jazz",
            year: "2026", duration: 1)
        store.tracks = [track]
        XCTAssertEqual(store.artistCollection("Artist").albums.count, 1)
        var second = track
        second.url = URL(fileURLWithPath: "/b.flac")
        second.album = "Two"
        store.tracks.append(second)
        XCTAssertEqual(store.artistCollection("Artist").albums.count, 2)
        XCTAssertEqual(store.artistCollection("Other").tracks.count, 0)
    }
    @MainActor
    func testDirectGraphPreservesDecoded24BitPCMSamplesWithDSPSettingsIgnored() throws {
        let root = try temporary()
        defer { try? FileManager.default.removeItem(at: root) }
        let url = root.appendingPathComponent("Source.wav")
        let format = AVAudioFormat(standardFormatWithSampleRate: 48000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 8192)!
        buffer.frameLength = 8192
        for c in 0..<2 {
            for i in 0..<8192 {
                buffer.floatChannelData![c][i] = Float(((i * 7919 + c * 101) % 8_000_001) - 4_000_000) / 8_388_608
            }
        }
        do {
            let writer = try AVAudioFile(
                forWriting: url,
                settings: [
                    AVFormatIDKey: kAudioFormatLinearPCM, AVSampleRateKey: 48000, AVNumberOfChannelsKey: 2,
                    AVLinearPCMBitDepthKey: 24, AVLinearPCMIsFloatKey: false, AVLinearPCMIsBigEndianKey: false,
                ], commonFormat: .pcmFormatFloat32, interleaved: false)
            try writer.write(from: buffer)
        }
        XCTAssertEqual(AudioFileFacts.read(url).bitDepth, 24)
        let source = try AVAudioFile(forReading: url)
        let reference = AVAudioPCMBuffer(pcmFormat: source.processingFormat, frameCapacity: 4096)!
        try source.read(into: reference, frameCount: 4096)
        let player = try AudioPlayback(file: AVAudioFile(forReading: url), direct: true)
        var prefs = ListeningPreferences()
        prefs.eqEnabled = true
        prefs.eqGains = Array(repeating: 12, count: 10)
        prefs.balance = 1
        prefs.playbackRate = 0.5
        player.apply(prefs)
        player.volume = 0.01
        XCTAssertEqual(player.volume, 1)
        try player.engine.enableManualRenderingMode(.offline, format: format, maximumFrameCount: 1024)
        let rendered = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 1024)!
        XCTAssertTrue(player.play())
        var samples = [[Float](), [Float]()]
        for _ in 0..<7 {
            if try player.engine.renderOffline(1024, to: rendered) == .success {
                for c in 0..<2 {
                    samples[c].append(
                        contentsOf: UnsafeBufferPointer(
                            start: rendered.floatChannelData![c], count: Int(rendered.frameLength)))
                }
            }
        }
        let expected = (0..<4096).map { reference.floatChannelData![0][$0] }
        let start = (0..<min(2048, max(0, samples[0].count - 4096))).first { index in
            (0..<8).allSatisfy { samples[0][index + $0].bitPattern == expected[$0].bitPattern }
        }
        let offset = try XCTUnwrap(start, "Direct graph must contain the unaltered source samples")
        for c in 0..<2 {
            for i in 0..<4096 {
                XCTAssertEqual(samples[c][offset + i].bitPattern, reference.floatChannelData![c][i].bitPattern)
            }
        }
        player.stop()
    }
    @MainActor
    func testLiveOutputDeviceBindingWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_AUDIO_HARDWARE"] == "1" else {
            throw XCTSkip("Opt-in read-only output inventory and engine binding")
        }
        let devices = await Task.detached { CoreAudioOutputs.devices() }.value
        XCTAssertFalse(devices.isEmpty)
        let id = CoreAudioOutputs.defaultDevice()
        let device = try XCTUnwrap(devices.first { $0.id == id })
        XCTAssertGreaterThan(device.channels, 0)
        XCTAssertGreaterThan(device.sampleRate, 0)
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let file = try await AudioFileLoader.shared.open(demo)
        let audio = try AudioPlayback(
            file: file.file, output: .init(deviceID: id, rate: device.sampleRate, exclusive: false, direct: false))
        var bound: AudioDeviceID = 0
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        XCTAssertEqual(
            AudioUnitGetProperty(
                audio.engine.outputNode.audioUnit!, kAudioOutputUnitProperty_CurrentDevice, kAudioUnitScope_Global, 0,
                &bound, &size), noErr)
        XCTAssertEqual(bound, id)
        print("PRISMA_OUTPUT devices=\(devices.count) binding-verified=true no-global-settings-changed=true")
    }
    @MainActor
    func testAirPlayTransportReplacementCannotPauseTheNewItem() async throws {
        let demo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let track = try await MetadataReader.read(demo)
        let shared = AVPlayer()
        shared.volume = 0
        let first = AirPlayPlayback(player: shared, track: track)
        let second = AirPlayPlayback(player: shared, track: track)
        var prefs = ListeningPreferences()
        prefs.playbackRate = 0.85
        second.apply(prefs)
        XCTAssertTrue(second.play())
        first.stop()
        XCTAssertTrue(second.isPlaying)
        XCTAssertEqual(shared.rate, 0.85, accuracy: 0.001)
        XCTAssertFalse(first.play())
        second.pause()
        XCTAssertFalse(second.isPlaying)
        second.stop()
        shared.replaceCurrentItem(with: nil)
    }
    @MainActor
    func testAirPlayCanPrepareNASFLACWhenRequested() async throws {
        guard let path = ProcessInfo.processInfo.environment["PRISMA_NAS_FILE"] else {
            throw XCTSkip("Opt-in NAS media preparation for AirPlay")
        }
        let track = try await MetadataReader.read(URL(fileURLWithPath: path))
        let shared = AVPlayer()
        shared.volume = 0
        let transport = AirPlayPlayback(player: shared, track: track)
        for _ in 0..<200 {
            if shared.currentItem?.status != .unknown { break }
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(shared.currentItem?.status, .readyToPlay, "\(String(describing:shared.currentItem?.error))")
        XCTAssertGreaterThan(transport.duration, 10)
        transport.stop()
        shared.replaceCurrentItem(with: nil)
        print("PRISMA_AIRPLAY nas-flac-prepared=true physical-receiver-not-tested=true")
    }
    func testLiveArtistBiographyAndLicensedPortraitWhenRequested() async throws {
        guard ProcessInfo.processInfo.environment["PRISMA_LIVE_NETWORK"] == "1" else {
            throw XCTSkip("Opt-in artist information")
        }
        let result = try await ArtistProfileService.shared.profile(name: "The Cardigans", language: "es")
        let profile = try XCTUnwrap(result)
        XCTAssertTrue(profile.biography.contains("banda"))
        XCTAssertEqual(profile.language, "es")
        XCTAssertEqual(profile.pageURL.host, "es.wikipedia.org")
        XCTAssertTrue(["upload.wikimedia.org", "thumb.wikimedia.org"].contains(profile.photoURL?.host ?? ""))
        XCTAssertNotNil(profile.photoCredit)
        XCTAssertNotNil(profile.photoLicense)
        XCTAssertNotNil(profile.photoPageURL)
        let soloResult = try await ArtistProfileService.shared.profile(name: "Adele", language: "es")
        let solo = try XCTUnwrap(soloResult)
        XCTAssertEqual(solo.language, "es")
        XCTAssertNotNil(solo.photoURL)
        if let url = solo.photoURL {
            let (data, status) = try await OnlineMetadata.request(url)
            XCTAssertEqual(status, 200)
            XCTAssertGreaterThan(data.count, 1000)
        }
        print(
            "PRISMA_ARTIST biography=true licensed-portrait=\(profile.photoURL != nil) language=\(profile.language) solo-spanish-photo=true"
        )
    }
}
