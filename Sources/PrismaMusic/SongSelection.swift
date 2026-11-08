import Foundation

/// Browsing never starts playback or wraps to the other end of the collection.
enum SongSelection {
    static func moved(from current: String?, in ids: [String], by direction: Int) -> String? {
        guard !ids.isEmpty else { return nil }
        guard let current, let index = ids.firstIndex(of: current) else { return direction < 0 ? ids.last : ids.first }
        let next = direction < 0 ? max(0, index - 1) : min(ids.count - 1, index + 1)
        return ids[next]
    }
}
