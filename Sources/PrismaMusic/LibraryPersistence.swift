import Foundation
import SQLite3

struct LibrarySnapshot: Codable, Sendable {
    var tracks:[Track]
    var sources:[MusicSource]
    var edited:[String]
    var playlists:[Playlist]?
}
private struct LibraryHeader: Codable, Equatable {
    var sources:[MusicSource]
    var edited:[String]
    var playlists:[Playlist]?
}
struct PersistenceFailure: LocalizedError {
    var message:String
    var errorDescription:String? { message }
}
/// A serial, incremental SQLite writer. Only the latest pending snapshot is retained.
final class LibraryPersistence: @unchecked Sendable {
    let directory:URL
    private let queue=DispatchQueue(label:"music.prisma.persistence",qos:.utility)
    private let lock=NSLock()
    private var pending:LibrarySnapshot?
    private var pendingFiles:[String:Data]=[:]
    private var writerScheduled=false
    private var db:OpaquePointer?
    private var assets:ArtworkAssetStore?
    private var openingError:Error?
    private var lastError:Error?
    private var previous:[String:Track]=[:]
    private var previousHeader:LibraryHeader?
    private var errorHandler:((String)->Void)?
    private(set) var lastChangedRows=0
    init(directory:URL) {
        self.directory=directory
        queue.sync {
            do {
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true)
                assets=try ArtworkAssetStore(directory:directory.appendingPathComponent("Artwork",isDirectory:true))
                guard sqlite3_open_v2(directory.appendingPathComponent("library.sqlite").path,&db,SQLITE_OPEN_READWRITE|SQLITE_OPEN_CREATE|SQLITE_OPEN_FULLMUTEX,nil) == SQLITE_OK else { throw failure("Open database") }
                sqlite3_busy_timeout(db,3000)
                try execute("PRAGMA journal_mode=WAL; PRAGMA synchronous=FULL; CREATE TABLE IF NOT EXISTS tracks (id TEXT PRIMARY KEY NOT NULL, payload BLOB NOT NULL); CREATE TABLE IF NOT EXISTS metadata (id INTEGER PRIMARY KEY CHECK(id=1), payload BLOB NOT NULL);")
            } catch { openingError=error }
        }
    }
    deinit { if let db { sqlite3_close_v2(db) } }
    func setErrorHandler(_ handler:@escaping (String)->Void) { lock.lock(); errorHandler=handler; lock.unlock() }
    private func failure(_ operation:String) -> PersistenceFailure { .init(message:"\(operation): \(db.map { String(cString:sqlite3_errmsg($0)) } ?? "SQLite unavailable")") }
    private func execute(_ sql:String) throws { guard sqlite3_exec(db,sql,nil,nil,nil) == SQLITE_OK else { throw failure("Database transaction") } }
    private func bind(_ data:Data,to statement:OpaquePointer?,index:Int32) throws {
        let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
        let result=data.withUnsafeBytes { bytes in sqlite3_bind_blob(statement,index,bytes.baseAddress,Int32(bytes.count),transient) }
        guard result == SQLITE_OK else { throw failure("Bind record") }
    }
    private func blob(_ statement:OpaquePointer?,column:Int32) -> Data {
        let count=Int(sqlite3_column_bytes(statement,column))
        guard count > 0,let bytes=sqlite3_column_blob(statement,column) else { return Data() }
        return Data(bytes:bytes,count:count)
    }
    func load() throws -> LibrarySnapshot? { try queue.sync { try loadOnQueue() } }
    private func loadOnQueue() throws -> LibrarySnapshot? {
        if let openingError { throw openingError }
        var headerStatement:OpaquePointer?
        guard sqlite3_prepare_v2(db,"SELECT payload FROM metadata WHERE id=1",-1,&headerStatement,nil) == SQLITE_OK else { throw failure("Read library header") }
        defer { sqlite3_finalize(headerStatement) }
        let step=sqlite3_step(headerStatement)
        if step == SQLITE_ROW {
            let header=try JSONDecoder().decode(LibraryHeader.self,from:blob(headerStatement,column:0))
            var statement:OpaquePointer?
            guard sqlite3_prepare_v2(db,"SELECT payload FROM tracks ORDER BY rowid",-1,&statement,nil) == SQLITE_OK else { throw failure("Read library") }
            defer { sqlite3_finalize(statement) }
            var tracks:[Track]=[]
            var result=sqlite3_step(statement)
            while result == SQLITE_ROW { tracks.append(try JSONDecoder().decode(Track.self,from:blob(statement,column:0))); result=sqlite3_step(statement) }
            guard result == SQLITE_DONE else { throw failure("Read library records") }
            previous=Dictionary(tracks.map { ($0.id,$0) },uniquingKeysWith:{ _,last in last }); previousHeader=header
            return .init(tracks:tracks,sources:header.sources,edited:header.edited,playlists:header.playlists)
        }
        guard step == SQLITE_DONE else { throw failure("Read library header") }
        let legacy=directory.appendingPathComponent("library.json")
        guard FileManager.default.fileExists(atPath:legacy.path) else { return nil }
        // Decode failure is an error, never a signal to create an empty/demo library.
        var snapshot=try JSONDecoder().decode(LibrarySnapshot.self,from:Data(contentsOf:legacy))
        for index in snapshot.tracks.indices { snapshot.tracks[index]=try normalizeOnQueue(snapshot.tracks[index]) }
        try apply(snapshot)
        let backup=directory.appendingPathComponent("library-v0.4-backup.json")
        if !FileManager.default.fileExists(atPath:backup.path) { try FileManager.default.copyItem(at:legacy,to:backup) }
        return snapshot
    }
    func normalized(_ track:Track) async throws -> Track {
        try await withCheckedThrowingContinuation { continuation in queue.async { do { continuation.resume(returning:try self.normalizeOnQueue(track)) } catch { continuation.resume(throwing:error) } } }
    }
    private func normalizeOnQueue(_ track:Track) throws -> Track {
        if let openingError { throw openingError }
        guard let assets else { throw failure("Artwork cache") }
        return try assets.externalize(track)
    }
    func save(_ snapshot:LibrarySnapshot) {
        lock.lock(); pending=snapshot; scheduleLocked(); lock.unlock()
    }
    func writeSmallFile(_ name:String,data:Data) {
        guard ["preferences.json","playback.json"].contains(name) else { return }
        lock.lock(); pendingFiles[name]=data; scheduleLocked(); lock.unlock()
    }
    private func scheduleLocked() {
        guard !writerScheduled else { return }; writerScheduled=true
        queue.async { [weak self] in self?.drain() }
    }
    private func drain() {
        while true {
            lock.lock()
            guard pending != nil || !pendingFiles.isEmpty else { writerScheduled=false; lock.unlock(); return }
            let snapshot=pending; pending=nil; let files=pendingFiles; pendingFiles.removeAll(keepingCapacity:true)
            lock.unlock()
            do {
                if let openingError { throw openingError }
                if let snapshot { try apply(snapshot) }
                for (name,data) in files { try data.write(to:directory.appendingPathComponent(name),options:.atomic) }
                if snapshot != nil { lastError=nil }
            } catch {
                lastError=error
                lock.lock(); let handler=errorHandler; lock.unlock(); handler?(error.localizedDescription)
            }
        }
    }
    func flush() async throws {
        try await withCheckedThrowingContinuation { (continuation:CheckedContinuation<Void,Error>) in
            queue.async { self.drain(); if let error=self.openingError ?? self.lastError { continuation.resume(throwing:error) } else { continuation.resume(returning:()) } }
        }
    }
    func flushSync() throws { try queue.sync { drain(); if let error=openingError ?? lastError { throw error } } }
    private func apply(_ snapshot:LibrarySnapshot) throws {
        if let openingError { throw openingError }
        var current:[String:Track]=[:]; current.reserveCapacity(snapshot.tracks.count)
        for track in snapshot.tracks { current[track.id]=try normalizeOnQueue(track) }
        let header=LibraryHeader(sources:snapshot.sources,edited:snapshot.edited,playlists:snapshot.playlists)
        let changed=current.values.filter { previous[$0.id] != $0 }
        let deleted=previous.keys.filter { current[$0] == nil }
        lastChangedRows=changed.count+deleted.count
        guard !changed.isEmpty || !deleted.isEmpty || previousHeader != header else { return }
        try execute("BEGIN IMMEDIATE")
        do {
            var upsert:OpaquePointer?,remove:OpaquePointer?,metadata:OpaquePointer?
            defer { sqlite3_finalize(upsert); sqlite3_finalize(remove); sqlite3_finalize(metadata) }
            guard sqlite3_prepare_v2(db,"INSERT INTO tracks(id,payload) VALUES(?,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",-1,&upsert,nil) == SQLITE_OK,sqlite3_prepare_v2(db,"DELETE FROM tracks WHERE id=?",-1,&remove,nil) == SQLITE_OK,sqlite3_prepare_v2(db,"INSERT INTO metadata(id,payload) VALUES(1,?) ON CONFLICT(id) DO UPDATE SET payload=excluded.payload",-1,&metadata,nil) == SQLITE_OK else { throw failure("Prepare library write") }
            let encoder=JSONEncoder(); let transient=unsafeBitCast(-1,to:sqlite3_destructor_type.self)
            for track in changed {
                sqlite3_reset(upsert); sqlite3_clear_bindings(upsert)
                guard sqlite3_bind_text(upsert,1,track.id,-1,transient) == SQLITE_OK else { throw failure("Bind track id") }
                try bind(encoder.encode(track),to:upsert,index:2)
                guard sqlite3_step(upsert) == SQLITE_DONE else { throw failure("Write track") }
            }
            for id in deleted {
                sqlite3_reset(remove); sqlite3_clear_bindings(remove); sqlite3_bind_text(remove,1,id,-1,transient)
                guard sqlite3_step(remove) == SQLITE_DONE else { throw failure("Remove library entry") }
            }
            try bind(encoder.encode(header),to:metadata,index:1)
            guard sqlite3_step(metadata) == SQLITE_DONE else { throw failure("Write library header") }
            try execute("COMMIT")
            previous=current; previousHeader=header
        } catch { try? execute("ROLLBACK"); throw error }
    }
}
