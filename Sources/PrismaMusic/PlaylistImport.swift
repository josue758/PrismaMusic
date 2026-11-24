import Foundation

struct PlaylistImport: Identifiable, Sendable {
    let id = UUID()
    var name: String
    var tracks: [Track]
    var unmatched: [String]
    var relocated: Int

    static func read(_ url: URL, tracks: [Track]) throws -> Self {
        let file = try FileHandle(forReadingFrom: url)
        defer { try? file.close() }
        let limit = 4_194_304
        let data = try file.read(upToCount: limit + 1) ?? Data()
        guard data.count <= limit, let text = String(data: data, encoding: .utf8)
            ?? String(data: data, encoding: .windowsCP1252)
        else { throw CocoaError(.fileReadCorruptFile) }
        return resolve(text, from: url, tracks: tracks)
    }

    static func resolve(_ text: String, from url: URL, tracks: [Track]) -> Self {
        let resolver = LibraryPathResolver(tracks)
        var result = Self(name: url.deletingPathExtension().lastPathComponent, tracks: [], unmatched: [], relocated: 0)
        var seen = Set<String>()
        for row in text.split(whereSeparator: \.isNewline) {
            let entry = row.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\u{FEFF}")))
            if entry.isEmpty || entry.hasPrefix("#") { continue }
            guard let match = resolver.resolve(entry, relativeTo: url.deletingLastPathComponent()) else {
                result.unmatched.append(entry)
                continue
            }
            if seen.insert(match.track.id).inserted {
                result.tracks.append(match.track)
                if match.relocated { result.relocated += 1 }
            }
        }
        return result
    }
}
