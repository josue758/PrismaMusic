import Foundation
import SQLite3

struct LibraryBackupPreview: Identifiable, Sendable {
    let id: String
    let date: Date?
    let size: Int64
}

/// Uses SQLite's online backup API so WAL transactions are included in each snapshot.
enum LibraryDatabaseBackups {
    private static let stagedName = "pending-library-restore.sqlite"

    static func list(in directory: URL) throws -> [LibraryBackupPreview] {
        let folder = directory.appendingPathComponent("Backups")
        guard FileManager.default.fileExists(atPath: folder.path) else { return [] }
        return try FileManager.default.contentsOfDirectory(
            at: folder, includingPropertiesForKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey],
            options: .skipsHiddenFiles
        ).compactMap { file in
            let name = file.lastPathComponent
            guard name.range(of: #"^library-[0-9]{4}-[0-9]{2}-[0-9]{2}\.sqlite$"#, options: .regularExpression) != nil
            else { return nil }
            let info = try file.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey, .fileSizeKey])
            guard info.isRegularFile == true else { return nil }
            return LibraryBackupPreview(id: name, date: info.contentModificationDate, size: Int64(info.fileSize ?? 0))
        }.sorted { $0.id > $1.id }
    }

    static func trackCount(_ id: String, in directory: URL) throws -> Int {
        let file = try snapshot(id, in: directory)
        return try withReadOnly(file) { db in
            var statement: OpaquePointer?
            guard sqlite3_prepare_v2(db, "SELECT count(*) FROM tracks", -1, &statement, nil) == SQLITE_OK
            else { throw error(sqlite3_errcode(db)) }
            defer { sqlite3_finalize(statement) }
            guard sqlite3_step(statement) == SQLITE_ROW else { throw error(sqlite3_errcode(db)) }
            return Int(sqlite3_column_int64(statement, 0))
        }
    }

    static func stage(_ id: String, in directory: URL) throws {
        let source = try snapshot(id, in: directory)
        let fm = FileManager.default
        let temp = directory.appendingPathComponent(UUID().uuidString + ".restore")
        let staged = directory.appendingPathComponent(stagedName)
        defer { try? fm.removeItem(at: temp) }
        try fm.copyItem(at: source, to: temp)
        try withReadOnly(temp) { try validate($0) }
        if fm.fileExists(atPath: staged.path) {
            _ = try fm.replaceItemAt(staged, withItemAt: temp)
        } else {
            try fm.moveItem(at: temp, to: staged)
        }
    }

    private static func snapshot(_ id: String, in directory: URL) throws -> URL {
        guard try list(in: directory).contains(where: { $0.id == id }) else { throw CocoaError(.fileNoSuchFile) }
        return directory.appendingPathComponent("Backups", isDirectory: true).appendingPathComponent(id)
    }

    private static func withReadOnly<T>(_ file: URL, _ operation: (OpaquePointer?) throws -> T) throws -> T {
        var db: OpaquePointer?
        let opened = sqlite3_open_v2(file.path, &db, SQLITE_OPEN_READONLY, nil)
        defer { if let db { sqlite3_close(db) } }
        guard opened == SQLITE_OK else { throw error(opened) }
        return try operation(db)
    }

    static func applyPending(in directory: URL) throws -> Bool {
        let staged = directory.appendingPathComponent(stagedName)
        guard FileManager.default.fileExists(atPath: staged.path) else { return false }
        try withReadOnly(staged) { try validate($0) }
        try install(staged, in: directory, preservingPrefix: "BeforeRestore-")
        return true
    }
    static func validate(_ db: OpaquePointer?) throws {
        var statement: OpaquePointer?
        let code = sqlite3_prepare_v2(db, "PRAGMA quick_check", -1, &statement, nil)
        guard code == SQLITE_OK else { throw error(code) }
        defer { sqlite3_finalize(statement) }
        let step = sqlite3_step(statement)
        guard step == SQLITE_ROW else { throw error(step) }
        guard let text = sqlite3_column_text(statement, 0), String(cString: text) == "ok"
        else { throw error(SQLITE_CORRUPT) }
    }
    private static func error(_ code: Int32) -> NSError {
        NSError(
            domain: "Prisma.SQLite", code: Int(code),
            userInfo: [NSLocalizedDescriptionKey: String(cString: sqlite3_errstr(code))])
    }
    static func create(from db: OpaquePointer?, directory: URL, date: Date = Date()) throws {
        let folder = directory.appendingPathComponent("Backups", isDirectory: true)
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        let target = folder.appendingPathComponent("library-\(formatter.string(from: date)).sqlite")
        guard !FileManager.default.fileExists(atPath: target.path) else { return }
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let temp = folder.appendingPathComponent(UUID().uuidString + ".tmp")
        defer {
            for path in [temp.path, temp.path + "-wal", temp.path + "-shm", temp.path + "-journal"] {
                try? FileManager.default.removeItem(atPath: path)
            }
        }
        var destination: OpaquePointer?
        let opened = sqlite3_open_v2(temp.path, &destination, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, nil)
        guard opened == SQLITE_OK else {
            if destination != nil { sqlite3_close(destination) }
            throw error(opened)
        }
        defer { if destination != nil { sqlite3_close(destination) } }
        guard let backup = sqlite3_backup_init(destination, "main", db, "main") else {
            throw error(sqlite3_errcode(destination))
        }
        let copied = sqlite3_backup_step(backup, -1)
        let finished = sqlite3_backup_finish(backup)
        guard copied == SQLITE_DONE, finished == SQLITE_OK else {
            throw error(copied == SQLITE_DONE ? finished : copied)
        }
        try validate(destination)
        // Finish and checkpoint the backup before moving its main file.
        let journal = sqlite3_exec(destination, "PRAGMA journal_mode=DELETE", nil, nil, nil)
        guard journal == SQLITE_OK else { throw error(journal) }
        let closed = sqlite3_close(destination)
        guard closed == SQLITE_OK else { throw error(closed) }
        destination = nil
        try FileManager.default.moveItem(at: temp, to: target)
        let snapshots = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent }
        for old in snapshots.dropFirst(7) { try FileManager.default.removeItem(at: old) }
    }
    static func restore(in directory: URL) throws -> String? {
        let fm = FileManager.default
        let folder = directory.appendingPathComponent("Backups")
        let candidates =
            (try? fm.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil))?
            .filter { $0.lastPathComponent.hasPrefix("library-") && $0.pathExtension == "sqlite" }
            .sorted { $0.lastPathComponent > $1.lastPathComponent } ?? []
        for candidate in candidates {
            var db: OpaquePointer?
            let opened = sqlite3_open_v2(candidate.path, &db, SQLITE_OPEN_READONLY, nil)
            let valid = opened == SQLITE_OK && (try? validate(db)) != nil
            if db != nil { sqlite3_close(db) }
            guard valid else { continue }
            let replacement = directory.appendingPathComponent(UUID().uuidString + ".restore")
            try fm.copyItem(at: candidate, to: replacement)
            defer { try? fm.removeItem(at: replacement) }
            try install(replacement, in: directory, preservingPrefix: "Damaged-")
            return candidate.lastPathComponent
        }
        return nil
    }
    private static func install(_ replacement: URL, in directory: URL, preservingPrefix: String) throws {
        let fm = FileManager.default
        let preserved = directory.appendingPathComponent(preservingPrefix + UUID().uuidString, isDirectory: true)
        try fm.createDirectory(at: preserved, withIntermediateDirectories: true)
        var moved: [String] = []
        do {
            for name in ["library.sqlite", "library.sqlite-wal", "library.sqlite-shm"] {
                let original = directory.appendingPathComponent(name)
                if fm.fileExists(atPath: original.path) {
                    try fm.moveItem(at: original, to: preserved.appendingPathComponent(name))
                    moved.append(name)
                }
            }
            try fm.moveItem(at: replacement, to: directory.appendingPathComponent("library.sqlite"))
        } catch {
            for name in moved {
                try? fm.moveItem(at: preserved.appendingPathComponent(name), to: directory.appendingPathComponent(name))
            }
            throw error
        }
    }
}
