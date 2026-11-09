import Foundation

enum AlbumOrdering {
    static func number(_ raw: String?) -> Int? {
        guard let raw, let first = raw.split(separator: "/").first,
            let value = Int(first.trimmingCharacters(in: .whitespacesAndNewlines)), value > 0, value < 10000
        else { return nil }
        return value
    }
    static func mp4Number(_ data: Data) -> Int? {
        guard data.count >= 4 else { return nil }
        let bytes = Array(data)
        let value = Int(bytes[2]) * 256 + Int(bytes[3])
        return value > 0 ? value : nil
    }
    static func filenameNumber(_ url: URL) -> Int? {
        let name = url.deletingPathExtension().lastPathComponent
        return number(String(name.prefix { $0.isNumber }))
    }
    static func sorted(_ tracks: [Track]) -> [Track] {
        tracks.sorted { a, b in
            let ad = a.discNumber ?? 1
            let bd = b.discNumber ?? 1
            if ad != bd { return ad < bd }
            let at = a.trackNumber ?? filenameNumber(a.url)
            let bt = b.trackNumber ?? filenameNumber(b.url)
            if at != bt {
                if let at, let bt { return at < bt }
                return at != nil
            }
            return a.url.lastPathComponent.localizedStandardCompare(b.url.lastPathComponent) == .orderedAscending
        }
    }
}
enum AlbumIdentity {
    static func artist(_ track: Track) -> String {
        if let albumArtist = track.albumArtist?.trimmingCharacters(in: .whitespacesAndNewlines), !albumArtist.isEmpty {
            return albumArtist
        }
        return ArtistIdentity.names(track.artist).first ?? track.artist
    }
    static func key(_ track: Track) -> String { artist(track) + "\u{1f}" + track.album }
}
struct AlbumCollection {
    var title: String
    var artist: String
    var tracks: [Track]
    var indices: [String: Int]
    var duration: Double
    var year: String
    init(seed: Track, library: [Track]) {
        title = seed.album
        artist = AlbumIdentity.artist(seed)
        tracks = AlbumOrdering.sorted(library.filter { AlbumIdentity.key($0) == AlbumIdentity.key(seed) })
        indices = Dictionary(
            tracks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        duration = tracks.reduce(0) { $0 + $1.duration }
        year = tracks.map(\.year).first { !$0.isEmpty } ?? ""
    }
}
