import Foundation

struct ListeningPreferences: Codable, Equatable {
    var eqEnabled = false
    var eqGains: [Float] = Array(repeating: 0, count: 10)
    var eqPreset = "flat"
    var preamp: Float = 0
    var autoHeadroom = true
    var balance: Float = 0
    var playbackRate: Float = 1
    var continueQueue = true
    var keepAwake = false
    var rememberPosition = true
    var startSection = "home"
    var glassStyle = "regular"
    var atmosphere = 0.75
    var compactRows = false
    var showQuality = true
    var albumSize = "medium"
    var autoArtwork = true
    var autoLyrics = true
    var recursiveScan = true
    var lyricsFontSize = 21.0
    var lyricsOffset = 0.0
    var autoScrollLyrics = true
    var visualizerStyle = "aurora"
    var visualizerSensitivity = 1.0
    var visualizerFPS = 30.0
    var animateVisualizer = true
    var miniAlwaysOnTop = true
    var miniAllSpaces = true
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let presets: [String: [Float]] = [
        "flat": [0,0,0,0,0,0,0,0,0,0],
        "rock": [4,3,2,0,-1,-1,1,3,4,4],
        "jazz": [2,2,1,1,-1,-1,0,2,3,3],
        "classical": [3,2,1,0,-1,0,0,1,2,3],
        "electronic": [5,4,2,0,-2,0,2,3,4,5],
        "vocal": [-2,-2,-1,0,2,3,3,2,0,-1]
    ]
    var effectivePreamp: Float { eqEnabled ? preamp - (autoHeadroom ? max(0, eqGains.max() ?? 0) : 0) : 0 }
    mutating func selectPreset(_ name: String) { eqGains = Self.presets[name] ?? Self.presets["flat"]!; eqPreset = name }
    mutating func sanitize() {
        if eqGains.count != 10 { eqGains = Array(repeating: 0, count: 10) }
        eqGains = eqGains.map { $0.isFinite ? min(12, max(-12, $0)) : 0 }
        preamp = preamp.isFinite ? min(6, max(-12, preamp)) : 0
        balance = balance.isFinite ? min(1, max(-1, balance)) : 0
        playbackRate = playbackRate.isFinite ? min(1.5, max(0.5, playbackRate)) : 1
        lyricsFontSize = min(32, max(14, lyricsFontSize)); lyricsOffset = min(10, max(-10, lyricsOffset))
        visualizerFPS = [24.0, 30, 60].contains(visualizerFPS) ? visualizerFPS : 30
        atmosphere = min(1, max(0, atmosphere))
    }
}
struct Playlist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
}
