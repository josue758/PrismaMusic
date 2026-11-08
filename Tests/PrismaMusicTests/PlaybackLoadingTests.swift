import XCTest
import AVFoundation
@testable import PrismaMusic

private actor SuspendedAudioOpen {
    private var pending:[String:CheckedContinuation<OpenedAudioFile,Error>]=[:]
    private var observed:Set<String>=[]
    private var observers:[(String,CheckedContinuation<Void,Never>)]=[]
    func open(_ url:URL) async throws -> OpenedAudioFile {
        try await withCheckedThrowingContinuation { continuation in
            pending[url.path]=continuation; observed.insert(url.path)
            let ready=observers.filter { observed.contains($0.0) }
            observers.removeAll { observed.contains($0.0) }
            for item in ready { item.1.resume() }
        }
    }
    func waitForOpen(_ url:URL) async {
        if observed.contains(url.path) { return }
        await withCheckedContinuation { observers.append((url.path,$0)) }
    }
    func fail(_ url:URL) { pending.removeValue(forKey:url.path)?.resume(throwing:NSError(domain:"TestAudio",code:1,userInfo:[NSLocalizedDescriptionKey:url.lastPathComponent])) }
    func succeed(_ url:URL,file:OpenedAudioFile) { pending.removeValue(forKey:url.path)?.resume(returning:file) }
}
final class PlaybackLoadingTests:XCTestCase {
    func testM4AWithFLACExtensionUsesRealCodecAndIsNotLossless() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let demo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let renamed=root.appendingPathComponent("WrongExtension.flac")
        try FileManager.default.copyItem(at:demo,to:renamed)
        let read=try await MetadataReader.read(renamed)
        XCTAssertEqual(read.format,"M4A · AAC")
        XCTAssertFalse(read.isLossless)
        XCTAssertEqual(read.codecLabel,"AAC")
        XCTAssertGreaterThan(read.duration,1)
        var legacy=read; legacy.format="FLAC · AAC"
        XCTAssertFalse(legacy.isLossless)
        legacy.format="M4A · ALAC"; XCTAssertTrue(legacy.isLossless)
        if let path=ProcessInfo.processInfo.environment["PRISMA_MISNAMED_AUDIO_FILE"] {
            let actual=try await MetadataReader.read(URL(fileURLWithPath:path))
            XCTAssertEqual(actual.format,"M4A · AAC")
            XCTAssertFalse(actual.isLossless)
            XCTAssertGreaterThan(actual.duration,1)
            print("PRISMA_MISNAMED actual-container=M4A codec=AAC lossless=false verified=true")
        }
    }
    @MainActor
    func testEndOfTrackThenFailedNextDoesNotLeavePlayingStateStuck() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let gate=SuspendedAudioOpen()
        let store=LibraryStore(directory:root,autoStart:false,openAudioFile:{ try await gate.open($0) })
        let a=track("Ended"),b=track("UnavailableNext")
        store.tracks=[a,b]; store.currentID=a.id; store.queue=[a.id,b.id]; store.isPlaying=true
        store.playbackDidFinish(); await gate.waitForOpen(b.url)
        XCTAssertFalse(store.isPlaying)
        XCTAssertEqual(store.position,a.duration)
        await gate.fail(b.url); await store.waitForPlaybackLoad()
        XCTAssertFalse(store.isPlaying); XCTAssertFalse(store.playbackLoading)
        XCTAssertEqual(store.currentID,a.id)
        XCTAssertNotNil(store.error)
    }
    private func directory() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); return root
    }
    private func track(_ name:String)->Track { Track(url:URL(fileURLWithPath:"/test/\(name).m4a"),title:name,artist:"Artist",album:"Album",genre:"Jazz",year:"2026",duration:120) }
    @MainActor
    func testSlowOpenLeavesInterfaceResponsiveAndLatestRequestOwnsError() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let gate=SuspendedAudioOpen()
        let store=LibraryStore(directory:root,autoStart:false,openAudioFile:{ try await gate.open($0) })
        let a=track("First"),b=track("Second")
        store.tracks=[a,b]
        store.play(a,in:[a,b]); await gate.waitForOpen(a.url)
        XCTAssertEqual(store.loadingTrackID,a.id)
        // A main-actor interaction must complete while the file open remains suspended.
        store.search="Second"; XCTAssertEqual(store.filtered.map(\.id),[b.id])
        store.play(b); await gate.waitForOpen(b.url)
        await gate.fail(a.url)
        await gate.fail(b.url)
        await store.waitForPlaybackLoad()
        XCTAssertFalse(store.playbackLoading)
        XCTAssertNil(store.currentID)
        XCTAssertTrue(store.error?.contains("Second.m4a") == true)
        XCTAssertFalse(store.error?.contains("First.m4a") == true)
    }
    @MainActor
    func testCancelAndQuitRejectLateSuccessfulOpen() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let gate=SuspendedAudioOpen()
        let store=LibraryStore(directory:root,autoStart:false,openAudioFile:{ try await gate.open($0) })
        let a=track("Cancelled")
        store.tracks=[a]
        store.play(a); await gate.waitForOpen(a.url)
        store.togglePlay()
        XCTAssertFalse(store.playbackLoading)
        let demo=URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
        let opened=try await AudioFileLoader.shared.open(demo)
        XCTAssertFalse(opened.openedOnMainThread,"The actual file open must run away from the UI thread")
        await gate.succeed(a.url,file:opened)
        await Task.yield()
        XCTAssertNil(store.currentID); XCTAssertFalse(store.isPlaying); XCTAssertNil(store.error)
        let b=track("Quit"); store.tracks.append(b)
        store.play(b); await gate.waitForOpen(b.url)
        try await store.prepareForTermination()
        await gate.succeed(b.url,file:opened)
        await Task.yield()
        XCTAssertFalse(store.playbackLoading); XCTAssertFalse(store.isPlaying)
        XCTAssertNil(store.currentID)
    }
    @MainActor
    func testRapidNextUsesPendingSelectionAndPauseCancelsLoad() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let gate=SuspendedAudioOpen()
        let store=LibraryStore(directory:root,autoStart:false,openAudioFile:{ try await gate.open($0) })
        let a=track("A"),b=track("B"),c=track("C")
        store.tracks=[a,b,c]; store.currentID=a.id; store.queue=[a.id,b.id,c.id]
        store.next(); await gate.waitForOpen(b.url)
        store.next(); await gate.waitForOpen(c.url)
        XCTAssertEqual(store.loadingTrackID,c.id)
        store.pausePlayback()
        await gate.fail(b.url); await gate.fail(c.url)
        await Task.yield()
        XCTAssertFalse(store.playbackLoading); XCTAssertNil(store.error); XCTAssertEqual(store.currentID,a.id)
        store.seek(40); XCTAssertEqual(store.position,40)
        store.seek(.nan); XCTAssertEqual(store.position,40)
    }
    @MainActor
    func testSessionRestoreDoesNotOpenAudioUntilRequested() async throws {
        let root=try directory(); defer { try? FileManager.default.removeItem(at:root) }
        let a=track("Offline")
        let persistence=LibraryPersistence(directory:root)
        persistence.save(.init(tracks:[a],sources:[],edited:[],playlists:[])); try persistence.flushSync()
        var preferences=ListeningPreferences(); preferences.hasCompletedWelcome=true
        try JSONEncoder().encode(preferences).write(to:root.appendingPathComponent("preferences.json"))
        struct Bookmark:Encodable { var id:String; var position:Double }
        try JSONEncoder().encode(Bookmark(id:a.id,position:37)).write(to:root.appendingPathComponent("playback.json"))
        let gate=SuspendedAudioOpen()
        let store=LibraryStore(directory:root,autoStart:true,openAudioFile:{ try await gate.open($0) })
        await store.waitUntilReady()
        XCTAssertEqual(store.currentID,a.id); XCTAssertEqual(store.position,37)
        XCTAssertFalse(store.playbackLoading); XCTAssertFalse(store.isPlaying)
        store.togglePlay(); await gate.waitForOpen(a.url)
        XCTAssertTrue(store.playbackLoading)
        store.pausePlayback(); await gate.fail(a.url)
        try await store.prepareForTermination()
    }
}
