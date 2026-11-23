import Foundation

struct SmartPlaylistRules: Codable, Equatable {
    var search = ""
    var artist = ""
    var genre = ""
    var year = ""
    var codec = ""
    var sampleRate = 0
    var unplayed = false
    var favorites = false
    var addedThisMonth = false

    var isEmpty: Bool { self == Self() }

    func filter(_ tracks: [Track], now: Date = .now, calendar: Calendar = .current) -> [Track] {
        let month = addedThisMonth ? calendar.dateInterval(of: .month, for: now) : nil
        return LibraryQuery.filter(
            tracks, search: search, artist: artist, year: year, favorites: favorites
        ).filter { track in
            (genre.isEmpty || track.genre.caseInsensitiveCompare(genre) == .orderedSame)
                && (codec.isEmpty || track.codecLabel == codec)
                && (sampleRate == 0 || track.sampleRate == Double(sampleRate))
                && (!unplayed || ((track.playCount ?? 0) == 0 && track.lastPlayed == nil))
                && (!addedThisMonth || track.addedAt.map { month?.contains($0) == true && $0 <= now } == true)
        }
    }
}
