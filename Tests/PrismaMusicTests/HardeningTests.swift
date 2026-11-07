import XCTest
import AppKit
import AVFoundation
import Synchronization
@testable import PrismaMusic

final class HardeningTests:XCTestCase {
    func temporary() throws -> URL {
        let root=FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true); return root
    }
    func testIncompleteCancelledAndReplacedSourcesCannotPrune() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let source=root.appendingPathComponent("Music")
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        let report=SourceScanner.enumerate(source,recursive:true)
        XCTAssertTrue(SourceScanner.canReconcile(report,cancelled:false))
        XCTAssertFalse(SourceScanner.canReconcile(report,cancelled:true))
        var incomplete=report; incomplete.complete=false
        XCTAssertFalse(SourceScanner.canReconcile(incomplete,cancelled:false))
        try FileManager.default.moveItem(at:source,to:root.appendingPathComponent("Old"))
        try FileManager.default.createDirectory(at:source,withIntermediateDirectories:true)
        XCTAssertFalse(SourceScanner.canReconcile(report,cancelled:false))
        XCTAssertFalse(SourceScanner.enumerate(root.appendingPathComponent("Missing"),recursive:true).complete)
        XCTAssertFalse(SourceScanner.isWithin(URL(fileURLWithPath:"/Music2/a.mp3"),source:URL(fileURLWithPath:"/Music")))
        XCTAssertFalse(SourceScanner.isWithin(URL(fileURLWithPath:"/Music/Album/a.mp3"),source:URL(fileURLWithPath:"/Music"),recursive:false))
    }
    func testMigrationDeduplicatesArtworkAndIncrementalWritesOneRecord() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let bitmap=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:8,pixelsHigh:8,bitsPerSample:8,samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
        let art=bitmap.representation(using:.png,properties:[:])!
        var tracks=(0..<100).map { Track(url:URL(fileURLWithPath:"/\($0).m4a"),title:"Song \($0)",artist:"Artist",album:"Album",genre:"Jazz",year:"2026",duration:120) }
        for i in tracks.indices { tracks[i].artwork=art }
        let snapshot=LibrarySnapshot(tracks:tracks,sources:[],edited:[],playlists:[])
        let original=try JSONEncoder().encode(snapshot)
        try original.write(to:root.appendingPathComponent("library.json"))
        let persistence=LibraryPersistence(directory:root)
        var loaded=try XCTUnwrap(persistence.load())
        XCTAssertTrue(loaded.tracks.allSatisfy { $0.artwork == nil && $0.artworkURL != nil })
        XCTAssertEqual(Set(loaded.tracks.compactMap(\.artworkURL)).count,1)
        XCTAssertEqual(try Data(contentsOf:root.appendingPathComponent("library-v0.4-backup.json")),original)
        loaded.tracks[0].favorite=true
        persistence.save(loaded); try persistence.flushSync()
        XCTAssertEqual(persistence.lastChangedRows,1)
        XCTAssertEqual(try LibraryPersistence(directory:root).load()?.tracks.filter(\.favorite).count,1)
    }
    func testCorruptLegacyLibraryIsReportedAndPreserved() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let original=Data("{broken".utf8); let url=root.appendingPathComponent("library.json")
        try original.write(to:url)
        XCTAssertThrowsError(try LibraryPersistence(directory:root).load())
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    func testTenThousandRecordsAndCoalescedLatestSave() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let persistence=LibraryPersistence(directory:root)
        var tracks=(0..<10000).map { Track(url:URL(fileURLWithPath:"/Music/\($0).flac"),title:"Song \($0)",artist:"Artist \($0 % 100)",album:"Album \($0 % 1000)",genre:"Jazz",year:"2026",duration:120) }
        let start=Date()
        persistence.save(.init(tracks:tracks,sources:[],edited:[],playlists:[])); try persistence.flushSync()
        let first=Date().timeIntervalSince(start)
        for i in 0..<20 {
            tracks[0].title="Revision \(i)"
            persistence.save(.init(tracks:tracks,sources:[],edited:[],playlists:[]))
        }
        try persistence.flushSync()
        let loaded=try XCTUnwrap(LibraryPersistence(directory:root).load())
        XCTAssertEqual(loaded.tracks.count,10000)
        XCTAssertEqual(loaded.tracks.first { $0.id == tracks[0].id }?.title,"Revision 19")
        print("PRISMA_BENCH 10000 records initial persistence seconds=\(first)")
    }
    private var demo:URL {
        URL(fileURLWithPath:#filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Sources/PrismaMusic/Resources/Demo/01-Orbita.m4a")
    }
    func testUnreadableChildMakesScanIncompleteAndRecoverySucceeds() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let folder=root.appendingPathComponent("Album",isDirectory:true)
        try FileManager.default.createDirectory(at:folder,withIntermediateDirectories:true)
        try FileManager.default.copyItem(at:demo,to:folder.appendingPathComponent("song.m4a"))
        try FileManager.default.setAttributes([.posixPermissions:0],ofItemAtPath:folder.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:folder.path) }
        let inaccessible=SourceScanner.enumerate(root,recursive:true)
        XCTAssertFalse(inaccessible.complete)
        XCTAssertFalse(inaccessible.errors.isEmpty)
        XCTAssertFalse(SourceScanner.canReconcile(inaccessible,cancelled:false))
        try FileManager.default.setAttributes([.posixPermissions:0o755],ofItemAtPath:folder.path)
        let recovered=SourceScanner.enumerate(root,recursive:true)
        XCTAssertTrue(recovered.complete)
        XCTAssertEqual(recovered.files.count,1)
        XCTAssertTrue(SourceScanner.canReconcile(recovered,cancelled:false))
    }
    @MainActor
    func testOverlappingSourcesAndFailedAudioReadKeepExistingTracks() async throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let music=root.appendingPathComponent("Music",isDirectory:true)
        let album=music.appendingPathComponent("Album",isDirectory:true)
        try FileManager.default.createDirectory(at:album,withIntermediateDirectories:true)
        let audio=album.appendingPathComponent("song.m4a")
        try FileManager.default.copyItem(at:demo,to:audio)
        let directory=root.appendingPathComponent("State")
        let store=LibraryStore(directory:directory,autoStart:false)
        await store.addSources([music,album])
        XCTAssertEqual(store.tracks.count,1,"Overlapping folders must not duplicate a song")
        let outer=try XCTUnwrap(store.sources.first { $0.url == music })
        store.removeSource(outer)
        XCTAssertEqual(store.tracks.count,1,"The remaining album source still owns the song")
        store.favorite(store.tracks[0])
        let old=store.tracks[0]
        try Data("damaged audio".utf8).write(to:audio,options:.atomic)
        await store.scan(force:true)
        XCTAssertEqual(store.tracks,[old],"A metadata read failure must retain the previous song and favorite")
        XCTAssertTrue(store.status.contains(store.t("scanErrors")))
        try await store.flushSaving()
        let restored=LibraryStore(directory:directory,autoStart:false)
        XCTAssertEqual(restored.tracks,[old])
        XCTAssertEqual(restored.sources.count,1)
    }
    @MainActor
    func testCorruptDatabasePreventsAutomaticReplacement() async throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("library.sqlite")
        let original=Data("corrupt database bytes".utf8)
        try original.write(to:url)
        let store=LibraryStore(directory:root,autoStart:false)
        XCTAssertNotNil(store.error)
        await store.addSources([demo])
        XCTAssertTrue(store.sources.isEmpty)
        XCTAssertTrue(store.tracks.isEmpty)
        store.save()
        do { try await store.flushSaving(); XCTFail("A corrupt database must report an error") } catch { }
        XCTAssertEqual(try Data(contentsOf:url),original)
    }
    @MainActor
    func testQueryAndStatisticsRefreshAfterEditsAndPlaylistChanges() async throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let store=LibraryStore(directory:root,autoStart:false)
        var a=Track(url:URL(fileURLWithPath:"/a.flac"),title:"Álbum azul",artist:"Uno",album:"Noche",genre:"Jazz",year:"2025",duration:30)
        let b=Track(url:URL(fileURLWithPath:"/b.flac"),title:"Sol",artist:"Dos",album:"Día",genre:"Rock",year:"2026",duration:60)
        store.tracks=[a,b]
        XCTAssertEqual(store.totalDuration,90)
        XCTAssertEqual(store.groupedAlbums.count,2)
        store.section="favorites"; XCTAssertTrue(store.filtered.isEmpty)
        store.favorite(a); XCTAssertEqual(store.filtered.map(\.id),[a.id])
        a=try XCTUnwrap(store.track(for:a.id)); a.artist="Tres"; a.duration=45; store.update(a)
        XCTAssertEqual(store.statistics.artists,["Dos","Tres"])
        XCTAssertEqual(store.totalDuration,105)
        store.createPlaylist("Prueba")
        let playlist=try XCTUnwrap(store.playlists.first)
        store.section="playlist:\(playlist.id)"; XCTAssertTrue(store.filtered.isEmpty)
        store.add(b,to:playlist); XCTAssertEqual(store.filtered.map(\.id),[b.id])
        store.removeFromPlaylist(b); XCTAssertTrue(store.filtered.isEmpty)
        store.section="songs"; store.search="album azul"; XCTAssertEqual(store.filtered.map(\.id),[a.id])
        try await store.flushSaving()
    }

    func testLosslessSourceDepthAndBitrateAreReadFromEncodedFile() async throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        let url=root.appendingPathComponent("24-bit.flac")
        let format=AVAudioFormat(standardFormatWithSampleRate:48000,channels:2)!
        do {
            let file=try AVAudioFile(forWriting:url,settings:[AVFormatIDKey:kAudioFormatFLAC,AVSampleRateKey:48000,AVNumberOfChannelsKey:2,AVEncoderBitDepthHintKey:24])
            let buffer=AVAudioPCMBuffer(pcmFormat:format,frameCapacity:24000)!
            buffer.frameLength=24000
            for channel in 0..<2 { for i in 0..<24000 { buffer.floatChannelData![channel][i]=sin(Float(i)*2 * .pi * 440 / 48000)*0.1 } }
            try file.write(from:buffer)
        }
        let track=try await MetadataReader.read(url)
        XCTAssertEqual(track.format,"FLAC")
        XCTAssertEqual(track.bitDepth,24)
        XCTAssertGreaterThan(track.bitrate ?? 0,0)
        XCTAssertEqual(track.sampleRate,48000)
        XCTAssertEqual(track.channels,2)
    }
    func testProgressReportsFinalCountAndCancellationStopsEnumeration() throws {
        let root=try temporary(); defer { try? FileManager.default.removeItem(at:root) }
        for i in 0..<100 { try Data().write(to:root.appendingPathComponent("\(i).flac")) }
        let count=Atomic<Int>(-1)
        let report=SourceScanner.enumerate(root,recursive:true) { count.store($0,ordering:.relaxed) }
        XCTAssertTrue(report.complete)
        XCTAssertEqual(count.load(ordering:.relaxed),100)
        let cancellation=ScanCancellation(); cancellation.cancel()
        let stopped=SourceScanner.enumerate(root,recursive:true,cancellation:cancellation)
        XCTAssertFalse(stopped.complete)
        XCTAssertTrue(stopped.files.isEmpty)
    }

}
