import Foundation

/// Resolves references only against files already in the current library.
struct LibraryPathResolver {
    private let byPath: [String: Track]
    private let byName: [String: [Track]]

    init(_ tracks: [Track]) {
        byPath = Dictionary(tracks.map { ($0.url.standardizedFileURL.path, $0) },
                            uniquingKeysWith: { first, _ in first })
        byName = Dictionary(grouping: tracks) { $0.url.lastPathComponent.lowercased() }
    }

    func resolve(_ entry: String, relativeTo directory: URL? = nil) -> (track: Track, relocated: Bool)? {
        let normalized = entry.replacingOccurrences(of: "\\", with: "/")
        let parsed = URL(string: normalized)
        let isDrive = normalized.range(of: #"^[a-zA-Z]:/"#, options: .regularExpression) != nil
        let path: String
        let remote: Bool
        if !isDrive, let scheme = parsed?.scheme?.lowercased() {
            guard ["file", "smb"].contains(scheme), let parsed,
                parsed.user == nil, parsed.password == nil, parsed.query == nil, parsed.fragment == nil
            else { return nil }
            path = parsed.path
            remote = scheme == "smb" || (parsed.host.map { !$0.isEmpty && $0 != "localhost" } ?? false)
        } else {
            path = normalized
            remote = normalized.hasPrefix("//")
        }
        if !isDrive, !remote, directory != nil || path.hasPrefix("/") {
            let local = URL(fileURLWithPath: path, relativeTo: directory).standardizedFileURL
            if let track = byPath[local.path] { return (track, false) }
        }
        let components = path.lowercased().split(separator: "/")
        guard let name = components.last, let candidates = byName[String(name)] else { return nil }
        let scored = candidates.map { track in
            let other = track.url.path.lowercased().split(separator: "/")
            let count = zip(components.reversed(), other.reversed()).prefix { $0.0 == $0.1 }.count
            return (track: track, count: count)
        }
        let best = scored.map(\.count).max() ?? 0
        let matches = scored.filter { $0.count == best }
        guard best >= 2, matches.count == 1, let match = matches.first else { return nil }
        return (match.track, true)
    }
}
