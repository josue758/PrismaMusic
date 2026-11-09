import Darwin
import Foundation

/// Read FLAC headers and Vorbis comments without constructing an audiovisual asset for every track.
enum NativeFLACMetadata {
    static func read(_ url: URL, sidecars: ScannedAudioFile?) throws -> Track? {
        guard let header = try header(in: url) else { return nil }
        let duration = Double(header.samples) / Double(header.rate)
        let tags = header.comments
        func value(_ keys: [String]) -> String? { keys.compactMap { tags[$0] }.first { !$0.isEmpty } }
        var lyrics = value(["LYRICS", "UNSYNCEDLYRICS"])
        if lyrics?.isEmpty != false {
            if let sidecars, sidecars.sidecarsKnown {
                if let url = sidecars.lyricsURL { lyrics = try? String(contentsOf: url, encoding: .utf8) }
            } else {
                for ext in ["lrc", "txt"] {
                    if let text = try? String(
                        contentsOf: url.deletingPathExtension().appendingPathExtension(ext), encoding: .utf8)
                    {
                        lyrics = text
                        break
                    }
                }
            }
        }
        var artwork = header.artwork
        if artwork == nil {
            if let sidecars, sidecars.sidecarsKnown {
                if let cover = sidecars.coverURL { artwork = ArtworkCache.shared.data(at: cover) }
            } else {
                for name in ["cover.jpg", "folder.jpg", "cover.png", "Folder.jpg"] {
                    if let data = ArtworkCache.shared.data(
                        at: url.deletingLastPathComponent().appendingPathComponent(name, isDirectory: false))
                    {
                        artwork = data
                        break
                    }
                }
            }
        }
        let sourceIsNetwork =
            sidecars?.sourceIsNetwork
            ?? (try? url.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal).map { !$0 }
        let modified = Date(
            timeIntervalSince1970: Double(header.info.st_mtimespec.tv_sec) + Double(header.info.st_mtimespec.tv_nsec)
                / 1_000_000_000)
        let bitrate = Double(max(0, header.info.st_size - Int64(header.audioOffset))) * 8 / duration
        return Track(
            url: url, title: value(["TITLE"]) ?? url.deletingPathExtension().lastPathComponent,
            artist: value(["ARTIST", "ALBUMARTIST"]) ?? "—", album: value(["ALBUM"]) ?? "—",
            genre: value(["GENRE"]) ?? "—", year: String((value(["DATE", "YEAR", "CREATIONDATE"]) ?? "").prefix(4)),
            duration: duration, artwork: artwork, lyrics: lyrics, artworkCredit: artwork == nil ? nil : "Archivo local",
            lyricsCredit: lyrics == nil ? nil : "Archivo local", modified: modified, format: "FLAC", bitrate: bitrate,
            fileSize: header.info.st_size, sampleRate: Double(header.rate), channels: header.channels,
            bitDepth: header.bits, sourceIsNetwork: sourceIsNetwork,
            trackNumber: AlbumOrdering.number(value(["TRACKNUMBER", "TRACK"])),
            discNumber: AlbumOrdering.number(value(["DISCNUMBER", "DISC"])), albumOrderRead: true,
            albumArtist: value(["ALBUMARTIST", "ALBUM ARTIST", "ALBUM_ARTIST"]) ?? "")
    }
    private struct Header {
        var rate: Int
        var channels: Int
        var bits: Int
        var samples: UInt64
        var info: stat
        var audioOffset: UInt64 = 0
        var comments: [String: String] = [:]
        var artwork: Data?
    }
    private static func header(in url: URL) throws -> Header? {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        var info = stat()
        guard fstat(file.fileDescriptor, &info) == 0 else { return nil }
        var buffer = Data()
        var bufferOffset: UInt64 = 0
        func read(_ offset: UInt64, _ count: Int) throws -> Data? {
            guard offset <= UInt64(max(0, info.st_size)), count >= 0 else { return nil }
            if offset >= bufferOffset, offset + UInt64(count) <= bufferOffset + UInt64(buffer.count) {
                let start = Int(offset - bufferOffset)
                return buffer.subdata(in: start..<start + count)
            }
            let requested = min(max(count, 256 * 1024), Int(UInt64(max(0, info.st_size)) - offset))
            var value = Data(count: requested)
            var received = 0
            while received < requested {
                try Task.checkCancellation()
                let length = value.withUnsafeMutableBytes { bytes in
                    pread(
                        file.fileDescriptor, bytes.baseAddress!.advanced(by: received), requested - received,
                        off_t(offset + UInt64(received)))
                }
                if length < 0 {
                    if errno == EINTR { continue }
                    throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
                }
                if length == 0 { break }
                received += length
            }
            guard received >= count else { return nil }
            value.count = received
            buffer = value
            bufferOffset = offset
            return value.prefix(count)
        }
        guard let magic = try read(0, 4) else { throw CocoaError(.fileReadCorruptFile) }
        guard magic == Data([0x66, 0x4c, 0x61, 0x43]) else {
            if magic.allSatisfy({ $0 == 0 }) { throw CocoaError(.fileReadCorruptFile) }
            // An extension can be wrong: let AVFoundation identify other encoded audio.
            return nil
        }
        var offset: UInt64 = 4
        var result: Header?
        var frontCover = false
        for _ in 0..<128 {
            try Task.checkCancellation()
            guard let header = try read(offset, 4), header.count == 4 else { return nil }
            let bytes = [UInt8](header)
            let type = bytes[0] & 0x7f
            let length = Int(bytes[1]) << 16 | Int(bytes[2]) << 8 | Int(bytes[3])
            offset += 4
            guard offset + UInt64(length) <= UInt64(max(0, info.st_size)), offset + UInt64(length) <= 64 * 1024 * 1024
            else { return nil }
            if type == 0 {
                guard result == nil, length == 34, let block = try read(offset, length), block.count == length else {
                    return nil
                }
                let data = [UInt8](block)
                var packed: UInt64 = 0
                for byte in data[10..<18] { packed = (packed << 8) | UInt64(byte) }
                let rate = Int(packed >> 44)
                let channels = Int((packed >> 41) & 7) + 1
                let bits = Int((packed >> 36) & 31) + 1
                let samples = packed & 0xF_FFFF_FFFF
                guard rate > 0, bits >= 4, samples > 0 else { return nil }
                result = Header(rate: rate, channels: channels, bits: bits, samples: samples, info: info)
            } else if type == 4 {
                guard length <= 8 * 1024 * 1024, let data = try read(offset, length), data.count == length,
                    let comments = parseComments(data), result != nil
                else { return nil }
                result?.comments = comments
            } else if type == 6 && !frontCover {
                guard let data = try read(offset, length), data.count == length else { return nil }
                if let picture = picture(data) {
                    result?.artwork = picture.data
                    frontCover = picture.front
                }
            }
            offset += UInt64(length)
            if bytes[0] & 0x80 != 0 {
                guard result != nil, info.st_size > Int64(offset) + 2 else { return nil }
                guard let sync = try read(offset, 2), sync.count == 2, sync[0] == 0xff, sync[1] & 0xfe == 0xf8 else {
                    return nil
                }
                result?.audioOffset = offset
                return result
            }
        }
        return nil
    }
    private static func picture(_ data: Data) -> (data: Data, front: Bool)? {
        let bytes = [UInt8](data)
        var offset = 0
        func integer() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            let value =
                Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16 | Int(bytes[offset + 2]) << 8
                | Int(bytes[offset + 3])
            offset += 4
            return value
        }
        guard let type = integer(), let mime = integer(), mime <= bytes.count - offset else { return nil }
        offset += mime
        guard let description = integer(), description <= bytes.count - offset else { return nil }
        offset += description
        for _ in 0..<4 { guard integer() != nil else { return nil } }
        guard let size = integer(), size <= bytes.count - offset else { return nil }
        return (Data(bytes[offset..<offset + size]), type == 3)
    }
    static func parseComments(_ data: Data) -> [String: String]? {
        let bytes = [UInt8](data)
        var offset = 0
        func integer() -> Int? {
            guard offset + 4 <= bytes.count else { return nil }
            let result =
                Int(bytes[offset]) | Int(bytes[offset + 1]) << 8 | Int(bytes[offset + 2]) << 16 | Int(bytes[offset + 3])
                << 24
            offset += 4
            return result
        }
        guard let vendor = integer(), vendor <= bytes.count - offset else { return nil }
        offset += vendor
        guard let count = integer(), count <= 4096 else { return nil }
        var values: [String: String] = [:]
        for _ in 0..<count {
            guard let length = integer(), length <= bytes.count - offset,
                let comment = String(bytes: bytes[offset..<offset + length], encoding: .utf8)
            else { return nil }
            offset += length
            guard let separator = comment.firstIndex(of: "=") else { continue }
            let key = comment[..<separator].uppercased()
            if values[key] == nil { values[key] = String(comment[comment.index(after: separator)...]) }
        }
        return values
    }
}
