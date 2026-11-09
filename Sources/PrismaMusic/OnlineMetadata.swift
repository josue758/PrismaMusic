import Foundation

enum OnlineMetadata {
    static func request(_ url: URL, session: URLSession = .shared) async throws -> (Data, Int) {
        var request = URLRequest(url: url)
        request.timeoutInterval = 15
        request.setValue(
            "PrismaMusic/\(AppVersion.current) (https://github.com/josue758/PrismaMusic)",
            forHTTPHeaderField: "User-Agent")
        let (stream, response) = try await session.bytes(for: request)
        let limit = 8 * 1024 * 1024
        guard response.expectedContentLength <= Int64(limit) else { throw URLError(.dataLengthExceedsMaximum) }
        var data = Data()
        for try await byte in stream {
            try Task.checkCancellation()
            guard data.count < limit else { throw URLError(.dataLengthExceedsMaximum) }
            data.append(byte)
        }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 || code == 404 else { throw URLError(.badServerResponse) }
        return (data, code)
    }
    static func url(_ base: String, _ items: [String: String]) -> URL {
        var components = URLComponents(string: base)!
        components.queryItems = items.sorted { $0.key < $1.key }.map { URLQueryItem(name: $0.key, value: $0.value) }
        return components.url!
    }
    static func normalized(_ s: String) -> String {
        s.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "en_US_POSIX")).filter
        { $0.isLetter || $0.isNumber }
    }
    static func artwork(for track: Track) async throws -> (Data, String)? {
        guard track.artist != "—" else { return nil }
        let (data, code) = try await request(
            url(
                "https://itunes.apple.com/search",
                ["term": "\(track.artist) \(track.title)", "entity": "song", "limit": "8"]))
        guard code == 200 else { return nil }
        struct Response: Decodable { var results: [Result] }
        struct Result: Decodable {
            var artistName: String?
            var trackName: String?
            var artworkUrl100: String?
            var collectionViewUrl: String?
        }
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard
            let match = response.results.first(where: {
                normalized($0.artistName ?? "") == normalized(track.artist)
                    && normalized($0.trackName ?? "") == normalized(track.title)
            }),
            let imageURL = match.artworkUrl100.flatMap(URL.init(string:)), imageURL.scheme == "https"
        else { return nil }
        let (image, status) = try await request(imageURL)
        return status == 200 ? (image, match.collectionViewUrl ?? "iTunes") : nil
    }
    static func lyrics(for track: Track) async throws -> String? {
        guard track.artist != "—", track.duration.isFinite, track.duration > 0 else { return nil }
        let title = track.title.precomposedStringWithCanonicalMapping
        let artist = (ArtistIdentity.names(track.artist).first ?? track.artist).precomposedStringWithCanonicalMapping
        var items = ["track_name": title, "artist_name": artist, "duration": String(Int(track.duration.rounded()))]
        if track.album != "—" { items["album_name"] = track.album.precomposedStringWithCanonicalMapping }
        let (data, code) = try await request(url("https://lrclib.net/api/get", items))
        if code == 200 {
            let candidate = try JSONDecoder().decode(LyricsCandidate.self, from: data)
            if let match = LyricsMatching.best([candidate], for: track) { return match.text }
        }
        // Search without album metadata, then verify identity/version/duration locally.
        var searches = [["track_name": title, "artist_name": artist], ["track_name": title]]
        let base = LyricsMatching.baseTitle(title)
        if base != title { searches.append(["track_name": base, "artist_name": artist]) }
        for query in searches {
            try Task.checkCancellation()
            try await Task.sleep(for: .milliseconds(350))
            let (data, status) = try await request(url("https://lrclib.net/api/search", query))
            guard status == 200 else { continue }
            let candidates = try JSONDecoder().decode([LyricsCandidate].self, from: data)
            if let match = LyricsMatching.best(candidates, for: track) { return match.text }
        }
        return nil
    }
}
