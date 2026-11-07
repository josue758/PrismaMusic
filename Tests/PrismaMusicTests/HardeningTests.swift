import XCTest
import AppKit
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
}
