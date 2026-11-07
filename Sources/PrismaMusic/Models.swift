import Foundation
import AVFoundation

struct Track: Identifiable, Codable, Equatable, Sendable {
    var id: String { url.path }
    var url: URL
    var title: String
    var artist: String
    var album: String
    var genre: String
    var year: String
    var duration: Double
    var artwork: Data?
    var lyrics: String?
    var artworkCredit: String?
    var lyricsCredit: String?
    var favorite = false
    var modified: Date?
    var format: String? = nil
    var bitrate: Double? = nil
    var fileSize: Int64? = nil
    var sampleRate: Double? = nil
    var channels: Int? = nil
    var bitDepth: Int? = nil
    var qualitySummary: String { [format, bitrate.map { "≈\(Int(($0 / 1000).rounded())) kb/s" }].compactMap { $0 }.joined(separator: " · ") }
    var isDemo: Bool { url.path.contains("/Demo/") }
}
struct MusicSource: Identifiable, Codable {
    var id = UUID()
    var url: URL
    var bookmark: Data?
    var name: String { url.lastPathComponent }
}
enum LibraryQuery {
    static func filter(_ tracks: [Track], search: String = "", artist: String = "", genre: String = "", year: String = "", favorites: Bool = false) -> [Track] {
        let words = search.split(whereSeparator: { $0.isWhitespace }).map(String.init)
        return tracks.filter { track in
            let haystack = [track.title, track.artist, track.album, track.genre, track.year].joined(separator: " ")
            return words.allSatisfy { haystack.localizedStandardContains($0) }
                && (artist.isEmpty || track.artist == artist)
                && (genre.isEmpty || track.genre == genre)
                && (year.isEmpty || track.year == year)
                && (!favorites || track.favorite)
        }
    }
}
struct LyricLine: Identifiable {
    var id: Int
    var time: Double
    var text: String
    static func parse(_ text: String) -> [LyricLine] {
        let regex = try! NSRegularExpression(pattern: #"\[(\d+):(\d+(?:\.\d+)?)\]"#)
        var lines: [(Double, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let ns = line as NSString
            let matches = regex.matches(in: line, range: NSRange(location: 0, length: ns.length))
            guard let last = matches.last else { continue }
            let body = ns.substring(from: last.range.location + last.range.length).trimmingCharacters(in: .whitespaces)
            for match in matches {
                if let min = Double(ns.substring(with: match.range(at: 1))), let sec = Double(ns.substring(with: match.range(at: 2))) { lines.append((min * 60 + sec, body)) }
            }
        }
        return lines.sorted { $0.0 < $1.0 }.enumerated().map { LyricLine(id: $0.offset, time: $0.element.0, text: $0.element.1) }
    }
}
enum MetadataReader {
    static let extensions: Set<String> = ["mp3", "m4a", "aac", "aiff", "aif", "wav", "flac", "caf", "mp4", "alac"]
    static func files(in source: URL) -> [URL] {
        if !source.hasDirectoryPath, extensions.contains(source.pathExtension.lowercased()) { return [source] }
        guard let enumerator = FileManager.default.enumerator(at: source, includingPropertiesForKeys: [.isRegularFileKey], options: [.skipsHiddenFiles, .skipsPackageDescendants]) else { return [] }
        return enumerator.compactMap { $0 as? URL }.filter { extensions.contains($0.pathExtension.lowercased()) && ((try? $0.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile) == true) }.sorted { $0.path < $1.path }
    }
    static func read(_ url: URL) async throws -> Track {
        let asset = AVURLAsset(url: url)
        let duration = try await asset.load(.duration).seconds
        guard duration.isFinite, duration > 0 else { throw NSError(domain: "Prisma", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid audio: \(url.lastPathComponent)"]) }
        let metadata = (try? await asset.load(.metadata)) ?? []
        var values: [String: String] = [:]
        var artwork: Data?
        for item in metadata {
            let key = item.commonKey?.rawValue ?? item.identifier?.rawValue ?? ""
            if key.lowercased().contains("artwork") || key.contains("APIC") || key.contains("covr") {
                if let data = try? await item.load(.dataValue) { artwork = data }
            }
            if let value = try? await item.load(.stringValue), !value.isEmpty {
                values[key] = value
                if let raw = item.identifier?.rawValue {
                    let identifier = raw.replacingOccurrences(of: "%A9", with: "©")
                    values[identifier.removingPercentEncoding ?? identifier] = value
                }
            }
        }
        func value(_ keys: [String]) -> String? { for key in keys { if let v = values[key] { return v } }; return nil }
        var lyrics = try? await asset.load(.lyrics)
        if lyrics?.isEmpty != false { lyrics = value(["id3/USLT", "itsk/©lyr"]) }
        if lyrics?.isEmpty != false {
            for ext in ["lrc", "txt"] {
                if let local = try? String(contentsOf: url.deletingPathExtension().appendingPathExtension(ext), encoding: .utf8) { lyrics = local; break }
            }
        }
        if artwork == nil {
            for name in ["cover.jpg", "folder.jpg", "cover.png", "Folder.jpg"] {
                if let data = try? Data(contentsOf: url.deletingLastPathComponent().appendingPathComponent(name)) { artwork = data; break }
            }
        }
        let date = value(["creationDate", "year", "id3/TDRC", "id3/TYER", "itsk/©day"]) ?? ""
        let audio = try? AVAudioFile(forReading: url)
        let stream = audio?.fileFormat.streamDescription.pointee
        let audioTrack = try? await asset.loadTracks(withMediaType: .audio).first
        let rate = try? await audioTrack?.load(.estimatedDataRate)
        let codec: String
        switch stream?.mFormatID {
        case kAudioFormatMPEG4AAC: codec = "AAC"
        case kAudioFormatAppleLossless: codec = "ALAC"
        case kAudioFormatLinearPCM: codec = "PCM"
        case kAudioFormatMPEGLayer3: codec = "MP3"
        case kAudioFormatFLAC: codec = "FLAC"
        default: codec = ""
        }
        let container = url.pathExtension.uppercased()
        let format = codec.isEmpty || codec == container ? container : container + " · " + codec
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize
        return Track(url: url, title: value(["title", "id3/TIT2", "itsk/©nam"]) ?? url.deletingPathExtension().lastPathComponent,
                     artist: value(["artist", "id3/TPE1", "itsk/©ART"]) ?? "—", album: value(["albumName", "id3/TALB", "itsk/©alb"]) ?? "—",
                     genre: value(["type", "genre", "id3/TCON", "itsk/©gen", "itsk/gnre"]) ?? "—", year: String(date.prefix(4)),
                     duration: duration, artwork: artwork, lyrics: lyrics, artworkCredit: artwork == nil ? nil : "Archivo local", lyricsCredit: lyrics == nil ? nil : "Archivo local",
                     modified: (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                     format: format, bitrate: rate.flatMap { $0 > 0 ? Double($0) : nil }, fileSize: size.map(Int64.init),
                     sampleRate: stream?.mSampleRate, channels: stream.map { Int($0.mChannelsPerFrame) },
                     bitDepth: stream.flatMap { $0.mBitsPerChannel > 0 ? Int($0.mBitsPerChannel) : nil })
    }
}
func clockText(_ seconds: Double) -> String {
    guard seconds.isFinite else { return "0:00" }
    let s = max(0, Int(seconds)); return String(format: "%d:%02d", s / 60, s % 60)
}
