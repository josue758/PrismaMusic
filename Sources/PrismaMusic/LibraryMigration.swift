import Foundation

struct LibraryMigration: Identifiable, Sendable {
    let id = UUID()
    var favorites: Set<String>
    var playlists: [Playlist]
    var edits: [String: TrackTagEdits]
    var relocated: Int
    var unmatched: [String]

    var isEmpty: Bool { favorites.isEmpty && playlists.isEmpty && edits.isEmpty }

    static func read(_ url: URL, tracks: [Track]) throws -> Self {
        let input = try Data(contentsOf: url, options: .mappedIfSafe)
        return try resolve(input, tracks: tracks)
    }

    static func resolve(_ input: Data, tracks: [Track]) throws -> Self {
        let decoder = JSONDecoder()
        let payload: MigrationPayload
        if let windows = try? decoder.decode(WindowsArchive.self, from: input) {
            payload = windows.payload
        } else {
            payload = try decoder.decode(MacArchive.self, from: input).payload
        }
        let paths = Set(payload.favorites + payload.playlists.flatMap(\.trackIDs) + Array(payload.edits.keys))
        let resolver = LibraryPathResolver(tracks)
        var mapping: [String: String] = [:]
        var relocated = 0
        var unmatched: [String] = []
        for path in paths.sorted() {
            if let match = resolver.resolve(path) {
                mapping[path] = match.track.id
                if match.relocated { relocated += 1 }
            } else {
                unmatched.append(path)
            }
        }
        let playlists = payload.playlists.compactMap { list -> Playlist? in
            var seen = Set<String>()
            let ids = list.trackIDs.compactMap { mapping[$0] }.filter { seen.insert($0).inserted }
            guard list.rules != nil || list.trackIDs.isEmpty || !ids.isEmpty else { return nil }
            return Playlist(name: list.name, trackIDs: ids, rules: list.rules)
        }
        var edits: [String: TrackTagEdits] = [:]
        for path in payload.edits.keys.sorted() {
            guard let id = mapping[path], let edit = payload.edits[path] else { continue }
            let valid = edit.values.filter { raw, value in TagField(rawValue: raw)?.isValid(value) == true }
            if !valid.isEmpty {
                edits[id, default: TrackTagEdits()].values.merge(valid) { first, _ in first }
            }
        }
        return Self(favorites: Set(payload.favorites.compactMap { mapping[$0] }), playlists: playlists,
                    edits: edits, relocated: relocated, unmatched: unmatched)
    }
}

private struct MigrationPayload {
    var favorites: [String]
    var playlists: [Playlist]
    var edits: [String: TrackTagEdits]
}

private struct MacArchive: Decodable {
    struct Entry: Decodable {
        let url: URL
        let favorite: Bool?
        let title: String?
        let artist: String?
        let album: String?
        let genre: String?
        let year: String?
        var legacyEdit: TrackTagEdits {
            TrackTagEdits(values: [
                "title": title, "artist": artist, "album": album, "genre": genre, "year": year,
            ].compactMapValues { $0 })
        }
    }
    let tracks: [Entry]
    let edited: [String]?
    let playlists: [Playlist]?
    let tagEdits: [String: TrackTagEdits]?

    var payload: MigrationPayload {
        let legacy = Set(edited ?? [])
        var edits = tagEdits ?? [:]
        var favorites: [String] = []
        for track in tracks where track.url.isFileURL {
            let path = track.url.path
            if track.favorite == true { favorites.append(path) }
            if legacy.contains(path), edits[path] == nil { edits[path] = track.legacyEdit }
        }
        return MigrationPayload(favorites: favorites, playlists: playlists ?? [], edits: edits)
    }
}

private struct WindowsArchive: Decodable {
    struct Entry: Decodable {
        let Path: String
    }
    struct Rules: Decodable {
        let Search: String?
        let Artist: String?
        let Genre: String?
        let Codec: String?
        let SampleRate: Int?
        let Favorites: Bool?
        let Unplayed: Bool?
        let AddedThisMonth: Bool?

        var converted: SmartPlaylistRules {
            SmartPlaylistRules(search: Search ?? "", artist: Artist ?? "", genre: Genre ?? "",
                               codec: Codec?.uppercased() ?? "", sampleRate: max(0, SampleRate ?? 0),
                               unplayed: Unplayed ?? false, favorites: Favorites ?? false,
                               addedThisMonth: AddedThisMonth ?? false)
        }
    }
    struct Edit: Decodable {
        let Title: String?
        let Artist: String?
        let Album: String?
        let AlbumArtist: String?
        let Genre: String?
        let Year: Int?
        let Disc: Int?
        let Number: Int?

        var converted: TrackTagEdits {
            func number(_ value: Int?) -> String? { value.map { $0 == 0 ? "" : String($0) } }
            return TrackTagEdits(values: [
                "title": Title, "artist": Artist, "album": Album, "albumArtist": AlbumArtist, "genre": Genre,
                "year": number(Year), "discNumber": number(Disc), "trackNumber": number(Number),
            ].compactMapValues { $0 })
        }
    }
    let Tracks: [Entry]
    let Favorites: [String]?
    let Playlists: [String: [String]]?
    let SmartPlaylists: [String: Rules]?
    let TagEdits: [String: Edit]?

    var payload: MigrationPayload {
        let ordered = (Playlists ?? [:]).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        let intelligent = (SmartPlaylists ?? [:]).sorted { $0.key.localizedStandardCompare($1.key) == .orderedAscending }
        return MigrationPayload(
            favorites: Favorites ?? [],
            playlists: ordered.map { Playlist(name: $0.key, trackIDs: $0.value) }
                + intelligent.map { Playlist(name: $0.key, rules: $0.value.converted) },
            edits: (TagEdits ?? [:]).mapValues(\.converted)
        )
    }
}
