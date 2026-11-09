import Foundation

struct LibraryQueryKey: Hashable {
    var revision: Int
    var search: String
    var artist: String
    var genre: String
    var year: String
    var section: String
    var sort: String
}
final class LibraryQueryCache {
    let tracks: [Track]
    lazy var duration: Double = tracks.reduce(0) { $0 + $1.duration }
    let indices: [String: Int]
    private let albumSort: String
    lazy var albums: [(key: String, value: [Track])] = {
        let groups = Dictionary(grouping: tracks, by: AlbumIdentity.key)
        let entries = groups.map { key, tracks in
            let title = tracks[0].album
            let artist = AlbumIdentity.artist(tracks[0])
            let year = tracks.map(\.year).filter { !$0.isEmpty }.min() ?? ""
            return (key: key, value: tracks, title: title, artist: artist, year: year)
        }
        return entries.sorted { a, b in
            if albumSort == "year", a.year != b.year {
                if a.year.isEmpty || b.year.isEmpty { return !a.year.isEmpty }
                return a.year.localizedStandardCompare(b.year) == .orderedAscending
            }
            if albumSort == "artist" {
                let comparison = a.artist.localizedStandardCompare(b.artist)
                if comparison != .orderedSame { return comparison == .orderedAscending }
            }
            let comparison = a.title.localizedStandardCompare(b.title)
            return comparison == .orderedSame ? a.key < b.key : comparison == .orderedAscending
        }.map { ($0.key, $0.value) }
    }()
    lazy var artists: [(key: String, value: [Track])] = {
        var groups: [String: [Track]] = [:]
        for track in tracks {
            for name in ArtistIdentity.names(track.artist) { groups[name, default: []].append(track) }
        }
        return groups.sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
    }()
    init(tracks: [Track], albumSort: String = "album") {
        self.tracks = tracks
        self.albumSort = albumSort
        indices = Dictionary(
            tracks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
    }
}
struct LibraryStatistics {
    var albumCount: Int
    var artists: [String]
    var genres: [String]
    var years: [String]
    var bytes: Int64 = 0
    var duration: Double = 0
    var withArtwork = 0
    var withLyrics = 0
    init(tracks: [Track]) {
        var albums = Set<String>()
        var artistSet = Set<String>()
        var genreSet = Set<String>()
        var yearSet = Set<String>()
        for track in tracks {
            albums.insert(AlbumIdentity.key(track))
            artistSet.formUnion(ArtistIdentity.names(track.artist))
            genreSet.insert(track.genre)
            if !track.year.isEmpty { yearSet.insert(track.year) }
            bytes += track.fileSize ?? 0
            duration += track.duration
            if track.hasArtwork { withArtwork += 1 }
            if track.lyrics != nil { withLyrics += 1 }
        }
        albumCount = albums.count
        artists = artistSet.sorted()
        genres = genreSet.sorted()
        years = yearSet.sorted().reversed()
    }
}

struct ArtistCollection {
    var indices: [String: Int]
    var tracks: [Track]
    var albums: [(key: String, value: [Track])]
    var genres: String
    var years: String
    var cover: Track?
    var duration: Double
    init(name: String, library: [Track]) {
        tracks = library.filter { ArtistIdentity.contains($0.artist, name: name) }.sorted {
            $0.title.localizedStandardCompare($1.title) == .orderedAscending
        }
        indices = Dictionary(
            tracks.enumerated().map { ($0.element.id, $0.offset) }, uniquingKeysWith: { first, _ in first })
        albums = Dictionary(grouping: tracks) { AlbumIdentity.key($0) }.sorted {
            ($0.value.first?.album ?? "").localizedStandardCompare($1.value.first?.album ?? "") == .orderedAscending
        }
        genres = Array(Set(tracks.map(\.genre))).filter { $0 != "—" }.sorted().prefix(4).joined(separator: " · ")
        let dated = tracks.compactMap { Int($0.year) }.filter { $0 > 0 }
        if let first = dated.min(), let last = dated.max() {
            years = first == last ? String(first) : "\(first)–\(last)"
        } else {
            years = ""
        }
        cover = tracks.first(where: \.hasArtwork)
        duration = tracks.reduce(0) { $0 + $1.duration }
    }
}
