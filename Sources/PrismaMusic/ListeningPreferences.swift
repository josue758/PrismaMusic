import Foundation

struct ListeningPreferences: Codable, Equatable {
    var outputDeviceUID = ""
    var directOutput = false
    var exclusiveOutput = false
    var hasCompletedWelcome = false
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
    var adaptiveArtwork = true
    var ambientMotion = true
    var artworkPulse = true
    var glassTransparency = 0.65
    var microInteractions = true
    var hoverDepth = true
    var showFeedback = true
    var compactRows = false
    var showQuality = true
    var albumSize = "medium"
    var autoArtwork = true
    var autoLyrics = true
    var recursiveScan = true
    var scanWorkers = 4
    var lyricsFontSize = 21.0
    var lyricsOffset = 0.0
    var autoScrollLyrics = true
    var translateLyrics = true
    var visualizerStyle = "aurora"
    var visualizerSensitivity = 1.0
    var visualizerFPS = 30.0
    var animateVisualizer = true
    var miniAlwaysOnTop = true
    var miniAllSpaces = true
    init() {}
    private enum CodingKeys: String, CodingKey {
        case outputDeviceUID, directOutput, exclusiveOutput, hasCompletedWelcome, eqEnabled, eqGains, eqPreset, preamp,
            autoHeadroom, balance, playbackRate, continueQueue, keepAwake, rememberPosition, startSection, glassStyle,
            atmosphere, adaptiveArtwork, ambientMotion, artworkPulse, glassTransparency, microInteractions, hoverDepth,
            showFeedback, compactRows, showQuality, albumSize, autoArtwork, autoLyrics, recursiveScan, scanWorkers,
            lyricsFontSize, lyricsOffset, autoScrollLyrics, translateLyrics, visualizerStyle, visualizerSensitivity,
            visualizerFPS,
            animateVisualizer, miniAlwaysOnTop, miniAllSpaces
    }
    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        outputDeviceUID = try values.decodeIfPresent(String.self, forKey: .outputDeviceUID) ?? ""
        directOutput = try values.decodeIfPresent(Bool.self, forKey: .directOutput) ?? false
        exclusiveOutput = try values.decodeIfPresent(Bool.self, forKey: .exclusiveOutput) ?? false
        hasCompletedWelcome = try values.decodeIfPresent(Bool.self, forKey: .hasCompletedWelcome) ?? false
        eqEnabled = try values.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? eqEnabled
        eqGains = try values.decodeIfPresent([Float].self, forKey: .eqGains) ?? eqGains
        eqPreset = try values.decodeIfPresent(String.self, forKey: .eqPreset) ?? eqPreset
        preamp = try values.decodeIfPresent(Float.self, forKey: .preamp) ?? preamp
        autoHeadroom = try values.decodeIfPresent(Bool.self, forKey: .autoHeadroom) ?? autoHeadroom
        balance = try values.decodeIfPresent(Float.self, forKey: .balance) ?? balance
        playbackRate = try values.decodeIfPresent(Float.self, forKey: .playbackRate) ?? playbackRate
        continueQueue = try values.decodeIfPresent(Bool.self, forKey: .continueQueue) ?? continueQueue
        keepAwake = try values.decodeIfPresent(Bool.self, forKey: .keepAwake) ?? keepAwake
        rememberPosition = try values.decodeIfPresent(Bool.self, forKey: .rememberPosition) ?? rememberPosition
        let savedSection = try values.decodeIfPresent(String.self, forKey: .startSection)
        if let savedSection, savedSection != "immersive" { startSection = savedSection }
        glassStyle = try values.decodeIfPresent(String.self, forKey: .glassStyle) ?? glassStyle
        atmosphere = try values.decodeIfPresent(Double.self, forKey: .atmosphere) ?? atmosphere
        adaptiveArtwork = try values.decodeIfPresent(Bool.self, forKey: .adaptiveArtwork) ?? adaptiveArtwork
        ambientMotion = try values.decodeIfPresent(Bool.self, forKey: .ambientMotion) ?? ambientMotion
        artworkPulse = try values.decodeIfPresent(Bool.self, forKey: .artworkPulse) ?? artworkPulse
        glassTransparency = try values.decodeIfPresent(Double.self, forKey: .glassTransparency) ?? glassTransparency
        microInteractions = try values.decodeIfPresent(Bool.self, forKey: .microInteractions) ?? microInteractions
        hoverDepth = try values.decodeIfPresent(Bool.self, forKey: .hoverDepth) ?? hoverDepth
        showFeedback = try values.decodeIfPresent(Bool.self, forKey: .showFeedback) ?? showFeedback
        compactRows = try values.decodeIfPresent(Bool.self, forKey: .compactRows) ?? compactRows
        showQuality = try values.decodeIfPresent(Bool.self, forKey: .showQuality) ?? showQuality
        albumSize = try values.decodeIfPresent(String.self, forKey: .albumSize) ?? albumSize
        autoArtwork = try values.decodeIfPresent(Bool.self, forKey: .autoArtwork) ?? autoArtwork
        autoLyrics = try values.decodeIfPresent(Bool.self, forKey: .autoLyrics) ?? autoLyrics
        recursiveScan = try values.decodeIfPresent(Bool.self, forKey: .recursiveScan) ?? recursiveScan
        scanWorkers = try values.decodeIfPresent(Int.self, forKey: .scanWorkers) ?? scanWorkers
        lyricsFontSize = try values.decodeIfPresent(Double.self, forKey: .lyricsFontSize) ?? lyricsFontSize
        lyricsOffset = try values.decodeIfPresent(Double.self, forKey: .lyricsOffset) ?? lyricsOffset
        autoScrollLyrics = try values.decodeIfPresent(Bool.self, forKey: .autoScrollLyrics) ?? autoScrollLyrics
        translateLyrics = try values.decodeIfPresent(Bool.self, forKey: .translateLyrics) ?? translateLyrics
        visualizerStyle = try values.decodeIfPresent(String.self, forKey: .visualizerStyle) ?? visualizerStyle
        visualizerSensitivity =
            try values.decodeIfPresent(Double.self, forKey: .visualizerSensitivity) ?? visualizerSensitivity
        visualizerFPS = try values.decodeIfPresent(Double.self, forKey: .visualizerFPS) ?? visualizerFPS
        animateVisualizer = try values.decodeIfPresent(Bool.self, forKey: .animateVisualizer) ?? animateVisualizer
        miniAlwaysOnTop = try values.decodeIfPresent(Bool.self, forKey: .miniAlwaysOnTop) ?? miniAlwaysOnTop
        miniAllSpaces = try values.decodeIfPresent(Bool.self, forKey: .miniAllSpaces) ?? miniAllSpaces
        sanitize()
    }
    mutating func applyAppearancePreset(_ preset: String) {
        glassStyle = preset == "contrast" ? "regular" : "clear"
        glassTransparency = preset == "contrast" ? 0.15 : preset == "calm" ? 0.55 : 0.85
        atmosphere = preset == "contrast" ? 0.25 : preset == "calm" ? 0.45 : 0.9
        adaptiveArtwork = true
        ambientMotion = preset == "glass"
        artworkPulse = preset == "glass"
        microInteractions = preset != "calm"
        hoverDepth = preset == "glass"
    }
    static let frequencies: [Float] = [31, 62, 125, 250, 500, 1000, 2000, 4000, 8000, 16000]
    static let presets: [String: [Float]] = [
        "flat": [0, 0, 0, 0, 0, 0, 0, 0, 0, 0],
        "rock": [4, 3, 2, 0, -1, -1, 1, 3, 4, 4],
        "jazz": [2, 2, 1, 1, -1, -1, 0, 2, 3, 3],
        "classical": [3, 2, 1, 0, -1, 0, 0, 1, 2, 3],
        "electronic": [5, 4, 2, 0, -2, 0, 2, 3, 4, 5],
        "vocal": [-2, -2, -1, 0, 2, 3, 3, 2, 0, -1],
    ]
    var effectivePreamp: Float { eqEnabled ? preamp - (autoHeadroom ? max(0, eqGains.max() ?? 0) : 0) : 0 }
    mutating func selectPreset(_ name: String) {
        eqGains = Self.presets[name] ?? Self.presets["flat"]!
        eqPreset = name
    }
    mutating func sanitize() {
        scanWorkers = min(8, max(1, scanWorkers))
        if eqGains.count != 10 { eqGains = Array(repeating: 0, count: 10) }
        eqGains = eqGains.map { $0.isFinite ? min(12, max(-12, $0)) : 0 }
        preamp = preamp.isFinite ? min(6, max(-12, preamp)) : 0
        balance = balance.isFinite ? min(1, max(-1, balance)) : 0
        playbackRate = playbackRate.isFinite ? min(1.5, max(0.5, playbackRate)) : 1
        lyricsFontSize = min(32, max(14, lyricsFontSize))
        lyricsOffset = min(10, max(-10, lyricsOffset))
        visualizerFPS = [24.0, 30, 60].contains(visualizerFPS) ? visualizerFPS : 30
        atmosphere = atmosphere.isFinite ? min(1, max(0, atmosphere)) : 0.75
        glassTransparency = glassTransparency.isFinite ? min(1, max(0, glassTransparency)) : 0.65
    }
}
struct Playlist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
}
