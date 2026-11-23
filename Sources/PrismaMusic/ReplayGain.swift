import Foundation

enum ReplayGainMode: String, Codable, CaseIterable {
    case off, track, album
}

struct ReplayGain: Equatable, Sendable {
    let trackGain: Float?
    let trackPeak: Float?
    let albumGain: Float?
    let albumPeak: Float?

    init(_ tags: [String: String]) {
        func number(_ key: String) -> Float? {
            guard let field = tags[key]?.split(whereSeparator: \.isWhitespace).first,
                let value = Float(field), value.isFinite
            else { return nil }
            return value
        }
        trackGain = number("REPLAYGAIN_TRACK_GAIN")
        trackPeak = number("REPLAYGAIN_TRACK_PEAK")
        albumGain = number("REPLAYGAIN_ALBUM_GAIN")
        albumPeak = number("REPLAYGAIN_ALBUM_PEAK")
    }

    func decibels(_ mode: ReplayGainMode, eqBoost: Float) -> Float {
        guard mode != .off else { return 0 }
        let useAlbum = mode == .album && albumGain != nil
        guard let gain = useAlbum ? albumGain : trackGain else { return 0 }
        let peak = useAlbum ? (albumPeak ?? trackPeak) : trackPeak
        // Assume a full-scale peak when the file provides gain without a peak.
        let maximum = -20 * log10(peak.flatMap { $0 > 0 ? $0 : nil } ?? 1) - max(0, eqBoost)
        return max(-96, min(24, gain, maximum))
    }
}
