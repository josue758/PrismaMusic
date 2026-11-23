import Darwin
import Foundation

enum FLACTagWriter {
    private static let keys: [TagField: [String]] = [
        .title: ["TITLE"], .artist: ["ARTIST"], .album: ["ALBUM"],
        .albumArtist: ["ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST"],
        .genre: ["GENRE"], .year: ["DATE", "YEAR", "CREATIONDATE"],
        .discNumber: ["DISCNUMBER", "DISC"], .trackNumber: ["TRACKNUMBER", "TRACK"],
    ]
    private static let magic = Data([0x66, 0x4c, 0x61, 0x43])

    struct InsufficientSpace: Error {
        let required: Int64
        let available: Int64?
    }

    static func requireStagingSpace(_ bytes: Int64, available: Int64?) throws {
        if let available, available < bytes {
            throw InsufficientSpace(required: bytes, available: available)
        }
    }

    private static func availableBytes(in directory: URL) -> Int64? {
        let values = try? directory.resourceValues(forKeys: [.volumeAvailableCapacityKey])
        return values?.volumeAvailableCapacity.map(Int64.init)
    }

    static func isStorageFull(_ error: NSError) -> Bool {
        var current: NSError? = error
        for _ in 0..<8 {
            guard let candidate = current else { break }
            if candidate.domain == NSPOSIXErrorDomain && [Int(ENOSPC), Int(EDQUOT)].contains(candidate.code)
                || candidate.domain == NSCocoaErrorDomain && candidate.code == CocoaError.fileWriteOutOfSpace.rawValue
            {
                return true
            }
            current = candidate.userInfo[NSUnderlyingErrorKey] as? NSError
        }
        return false
    }

    /// Rewrite metadata beside the original, stream the audio unchanged, then atomically rename.
    static func write(_ changes: [TagField: String], to url: URL) throws -> Track {
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var original = stat()
        guard fstat(input.fileDescriptor, &original) == 0,
            original.st_mode & S_IFMT == S_IFREG, original.st_nlink == 1
        else { throw CocoaError(.fileWriteNoPermission) }
        guard FileManager.default.isWritableFile(atPath: url.path) else { throw CocoaError(.fileWriteNoPermission) }
        guard try input.read(upToCount: 4) == magic else { throw CocoaError(.fileReadCorruptFile) }

        var blocks: [(type: UInt8, data: Data)] = []
        var foundLast = false
        var foundComments = false
        while !foundLast {
            guard blocks.count < 128, let header = try input.read(upToCount: 4), header.count == 4 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let type = header[0] & 127
            let size = Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])
            guard try input.offset() + UInt64(size) <= 64 * 1024 * 1024 else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = size == 0 ? Data() : try input.read(upToCount: size) ?? Data()
            guard data.count == size, type < 127,
                blocks.isEmpty ? (type == 0 && size == 34) : type != 0
            else { throw CocoaError(.fileReadCorruptFile) }
            if type == 4 {
                guard !foundComments else { throw CocoaError(.fileReadCorruptFile) }
                blocks.append((type, try updatedComments(data, changes: changes)))
                foundComments = true
            } else {
                blocks.append((type, data))
            }
            foundLast = header[0] & 128 != 0
        }
        if !foundComments {
            blocks.insert((4, try updatedComments(Data(repeating: 0, count: 8), changes: changes)), at: 1)
        }
        let audioOffset = try input.offset()
        guard let sync = try input.read(upToCount: 2), sync.count == 2, sync[0] == 255, sync[1] & 254 == 248 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        try input.seek(toOffset: audioOffset)

        let directory = url.deletingLastPathComponent()
        let metadataSize = blocks.reduce(4) { $0 + 4 + $1.data.count }
        let required = original.st_size - Int64(audioOffset) + Int64(metadataSize)
        try requireStagingSpace(required, available: availableBytes(in: directory))
        do {
            // A private staging directory on the same volume keeps replacement atomic on local disks and SMB.
            let staging = directory.appendingPathComponent(".prisma-tags-" + UUID().uuidString)
            try FileManager.default.createDirectory(
                at: staging, withIntermediateDirectories: false,
                attributes: [.posixPermissions: 0o700])
            defer { try? FileManager.default.removeItem(at: staging) }
            let temp = staging.appendingPathComponent(url.lastPathComponent)
            guard FileManager.default.createFile(atPath: temp.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            let output = try FileHandle(forWritingTo: temp)
            defer { try? output.close() }
            try output.write(contentsOf: magic)
            for (index, block) in blocks.enumerated() {
                let size = block.data.count
                let type = block.type | (index == blocks.count - 1 ? 128 : 0)
                try output.write(
                    contentsOf: Data([type, UInt8(size >> 16), UInt8((size >> 8) & 255), UInt8(size & 255)]))
                try output.write(contentsOf: block.data)
            }
            while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
                try Task.checkCancellation()
                try output.write(contentsOf: chunk)
            }
            try output.synchronize()
            try output.close()
            guard
                var refreshed = try NativeFLACMetadata.read(
                    temp, sidecars: ScannedAudioFile(url: temp, modified: nil, sidecarsKnown: true))
            else { throw CocoaError(.fileReadCorruptFile) }

            var current = stat()
            guard lstat(url.path, &current) == 0, current.st_dev == original.st_dev,
                current.st_ino == original.st_ino, current.st_size == original.st_size,
                current.st_mtimespec.tv_sec == original.st_mtimespec.tv_sec,
                current.st_mtimespec.tv_nsec == original.st_mtimespec.tv_nsec,
                current.st_ctimespec.tv_sec == original.st_ctimespec.tv_sec,
                current.st_ctimespec.tv_nsec == original.st_ctimespec.tv_nsec,
                current.st_mode & S_IFMT == S_IFREG
            else { throw CocoaError(.fileWriteUnknown) }
            guard copyfile(url.path, temp.path, nil, copyfile_flags_t(COPYFILE_SECURITY | COPYFILE_XATTR)) == 0 else {
                throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
            }
            try Task.checkCancellation()
            guard rename(temp.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
            refreshed.url = url
            return refreshed
        } catch {
            let available = availableBytes(in: directory)
            // Some SMB servers return access errors when a volume fills during a copy.
            if isStorageFull(error as NSError) || (available.map { $0 < required } ?? false) {
                throw InsufficientSpace(required: required, available: available)
            }
            throw error
        }
    }

    static func updatedComments(_ data: Data, changes: [TagField: String]) throws -> Data {
        var offset = 0
        func readLength() throws -> Int {
            guard offset + 4 <= data.count else { throw CocoaError(.fileReadCorruptFile) }
            let result = data[offset..<offset + 4].enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
            offset += 4
            return result
        }
        func readBytes(_ count: Int) throws -> Data {
            guard count <= data.count - offset else { throw CocoaError(.fileReadCorruptFile) }
            defer { offset += count }
            return data.subdata(in: offset..<offset + count)
        }
        func append(_ number: Int, to result: inout Data) {
            var little = UInt32(number).littleEndian
            withUnsafeBytes(of: &little) { result.append(contentsOf: $0) }
        }
        let vendorSize = try readLength()
        let vendor = try readBytes(vendorSize)
        let count = try readLength()
        guard count <= 4096 else { throw CocoaError(.fileReadCorruptFile) }
        let replaced = Set(changes.keys.flatMap { keys[$0] ?? [] })
        var comments: [Data] = []
        for _ in 0..<count {
            let length = try readLength()
            let comment = try readBytes(length)
            let key = comment.firstIndex(of: 61).flatMap { String(data: comment.prefix($0), encoding: .utf8) }
            if key.map({ replaced.contains($0.uppercased()) }) != true { comments.append(comment) }
        }
        for field in TagField.allCases {
            if let value = changes[field], !value.isEmpty, let key = keys[field]?.first {
                comments.append(Data((key + "=" + value).utf8))
            }
        }
        var result = Data()
        append(vendor.count, to: &result)
        result.append(vendor)
        append(comments.count, to: &result)
        for comment in comments {
            append(comment.count, to: &result)
            result.append(comment)
        }
        guard comments.count <= 4096, result.count <= 8 * 1024 * 1024 else {
            throw CocoaError(.fileWriteUnknown)
        }
        return result
    }
}
