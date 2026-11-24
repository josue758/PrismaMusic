import Foundation

enum TagField: String, CaseIterable, Identifiable, Codable, Sendable {
    case title, artist, album, albumArtist, genre, year, discNumber, trackNumber
    var id: String { rawValue }
    func value(in track: Track) -> String {
        switch self {
        case .title: track.title
        case .artist: track.artist
        case .album: track.album
        case .albumArtist: track.albumArtist ?? ""
        case .genre: track.genre
        case .year: track.year
        case .discNumber: track.discNumber.map(String.init) ?? ""
        case .trackNumber: track.trackNumber.map(String.init) ?? ""
        }
    }
    func set(_ value: String, in track: inout Track) {
        switch self {
        case .title: track.title = value
        case .artist: track.artist = value
        case .album: track.album = value
        case .albumArtist: track.albumArtist = value
        case .genre: track.genre = value
        case .year: track.year = value
        case .discNumber: track.discNumber = Int(value)
        case .trackNumber: track.trackNumber = Int(value)
        }
    }
    func isValid(_ value: String) -> Bool {
        let value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        if self == .title { return !value.isEmpty }
        if [.year, .discNumber, .trackNumber].contains(self) {
            return value.isEmpty || (value.allSatisfy(\.isNumber) && Int(value).map { (1...9999).contains($0) } == true)
        }
        return true
    }
}
struct TrackTagEdits: Codable, Equatable, Sendable {
    var values: [String: String] = [:]
    func applying(to track: Track) -> Track {
        var result = track
        for field in TagField.allCases {
            if let value = values[field.rawValue] { field.set(value, in: &result) }
        }
        return result
    }
    static func legacy(_ track: Track) -> Self {
        .init(
            values: Dictionary(
                uniqueKeysWithValues: [TagField.title, .artist, .album, .genre, .year].map {
                    ($0.rawValue, $0.value(in: track))
                }))
    }
}
enum TagIssueKind: String, CaseIterable, Identifiable, Sendable {
    case missingArtist, missingAlbum, splitAlbum, possibleDuplicate, hiddenCopies
    var id: String { rawValue }
}
struct TagReviewIssue: Identifiable, Sendable {
    let id: String
    let kind: TagIssueKind
    let title: String
    let tracks: [Track]
}
enum LibraryTagReview {
    static func key(_ value: String) -> String {
        value.precomposedStringWithCompatibilityMapping.split(whereSeparator: \.isWhitespace)
            .joined(separator: " ").uppercased()
    }
    static func find(_ tracks: [Track]) -> [TagReviewIssue] {
        let unknownArtists: Set<String> = ["", "—", "UNKNOWN ARTIST", "ARTISTA DESCONOCIDO", "ARTISTA DESCONHECIDO"]
        let unknownAlbums: Set<String> = [
            "", "—", "UNKNOWN ALBUM", "SIN ÁLBUM", "SEM ÁLBUM", "UNTITLED ALBUM", "ÁLBUM SIN TÍTULO",
            "ÁLBUM SEM TÍTULO",
        ]
        var issues: [TagReviewIssue] = []
        let hidden = tracks.filter { $0.hiddenDuplicate == true }
        if !hidden.isEmpty {
            issues.append(.init(id: "hiddenCopies", kind: .hiddenCopies, title: "", tracks: hidden))
        }
        let missingArtist = tracks.filter { unknownArtists.contains(key($0.artist)) }
        let missingAlbum = tracks.filter { unknownAlbums.contains(key($0.album)) }
        if !missingArtist.isEmpty {
            issues.append(.init(id: "missingArtist", kind: .missingArtist, title: "", tracks: missingArtist))
        }
        if !missingAlbum.isEmpty {
            issues.append(.init(id: "missingAlbum", kind: .missingAlbum, title: "", tracks: missingAlbum))
        }
        let tagged = tracks.filter {
            !unknownArtists.contains(key($0.artist)) && !unknownAlbums.contains(key($0.album))
        }
        struct AlbumKey: Hashable {
            let album: String
            let owner: String
        }
        let albums = Dictionary(grouping: tagged) { track in
            AlbumKey(
                album: key(track.album),
                owner: key(track.albumArtist?.isEmpty == false ? track.albumArtist! : track.artist))
        }
        for group in albums.values {
            let variants = Set(
                group.map { $0.album + "\u{0}" + ($0.albumArtist?.isEmpty == false ? $0.albumArtist! : $0.artist) })
            if variants.count > 1 {
                let ordered = group.sorted { $0.id < $1.id }
                issues.append(
                    .init(
                        id: "album:" + ordered[0].id, kind: .splitAlbum,
                        title: ordered[0].album + " · " + ordered[0].artist, tracks: ordered))
            }
        }
        struct SongKey: Hashable {
            let artist: String
            let album: String
            let title: String
            let disc: Int
            let number: Int
        }
        let songs = Dictionary(grouping: tagged.filter { !$0.title.isEmpty && $0.duration.isFinite && $0.duration > 0 })
        {
            SongKey(
                artist: key($0.artist), album: key($0.album), title: key($0.title), disc: $0.discNumber ?? 0,
                number: $0.trackNumber ?? 0)
        }
        for group in songs.values where group.count > 1 {
            let sorted = Dictionary(grouping: group, by: \.id).values.compactMap(\.first).sorted {
                $0.duration == $1.duration ? $0.id < $1.id : $0.duration < $1.duration
            }
            var start = 0
            while start < sorted.count {
                var end = start + 1
                while end < sorted.count && sorted[end].duration - sorted[start].duration <= 2 { end += 1 }
                if end - start > 1 {
                    let matched = Array(sorted[start..<end])
                    issues.append(
                        .init(
                            id: "duplicate:" + matched[0].id, kind: .possibleDuplicate,
                            title: matched[0].title + " · " + matched[0].artist, tracks: matched))
                }
                start = end
            }
        }
        return issues.sorted { $0.kind == $1.kind ? $0.id < $1.id : $0.kind.rawValue < $1.kind.rawValue }
    }
}
