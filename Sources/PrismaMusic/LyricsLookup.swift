import Foundation

struct LyricsCandidate: Decodable {
    let id: Int
    let trackName: String
    let artistName: String
    let albumName: String?
    let duration: Double
    let instrumental: Bool
    let plainLyrics: String?
    let syncedLyrics: String?
    var text: String? {
        if let syncedLyrics, !syncedLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return syncedLyrics
        }
        if let plainLyrics, !plainLyrics.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return plainLyrics }
        return nil
    }
}
enum LyricsMatching {
    /// Normalize Latin accents but preserve Japanese voicing marks and other scripts.
    static func key(_ raw: String) -> String {
        let text = raw.precomposedStringWithCanonicalMapping.folding(
            options: [.caseInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
        return text.map { character in
            let latin = character.unicodeScalars.allSatisfy { $0.value <= 0x024F }
            return latin
                ? String(character).folding(options: .diacriticInsensitive, locale: Locale(identifier: "en_US_POSIX"))
                : String(character)
        }.joined().filter { $0.isLetter || $0.isNumber }
    }
    static func baseTitle(_ raw: String) -> String {
        raw.precomposedStringWithCanonicalMapping.replacingOccurrences(
            of: #"(?i)\s*[\(\[]album\s+(?:version|edit)[\)\]]\s*$"#, with: "", options: .regularExpression)
    }
    private static func performance(_ text: String) -> Set<String> {
        var markers = Set<String>()
        for (name, pattern) in [
            ("live", #"(?i)\blive\b|\bao vivo\b|\ben vivo\b|ライブ"#), ("remix", #"(?i)\bremix(?:ed)?\b"#),
            ("acoustic", #"(?i)\bacoustic\b|\bunplugged\b|\bacústico\b"#),
            ("karaoke", #"(?i)\bkaraoke\b|\binstrumental\b"#),
        ] {
            if text.range(of: pattern, options: .regularExpression) != nil { markers.insert(name) }
        }
        return markers
    }
    static func best(_ values: [LyricsCandidate], for track: Track) -> LyricsCandidate? {
        guard track.duration.isFinite, track.duration > 0 else { return nil }
        let title = key(baseTitle(track.title))
        let artists = Set([track.artist, ArtistIdentity.names(track.artist).first ?? track.artist].map(key))
        let version = performance(track.title + " " + track.album)
        return values.filter {
            !$0.instrumental && $0.text != nil && !$0.trackName.isEmpty && !title.isEmpty
                && key(baseTitle($0.trackName)) == title && artists.contains(key($0.artistName))
                && $0.duration.isFinite && abs($0.duration - track.duration) <= 2
                && performance($0.trackName + " " + ($0.albumName ?? "")) == version
        }.max { a, b in
            func score(_ candidate: LyricsCandidate) -> Double {
                (key(candidate.albumName ?? "") == key(track.album) ? 10 : 0)
                    + (candidate.syncedLyrics?.isEmpty == false ? 4 : 0) - abs(candidate.duration - track.duration)
            }
            return score(a) < score(b)
        }
    }
}
