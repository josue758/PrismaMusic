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
    var replayGain: ReplayGainMode = .off
    var balance: Float = 0
    var playbackRate: Float = 1
    var continueQueue = true
    var gaplessPlayback = true
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
    var watchMusicFolders = true
    var recursiveScan = true
    var scanWorkers = 4
    var lyricsFontSize = 21.0
    var lyricsOffset = 0.0
    var autoScrollLyrics = true
    var translateLyrics = true
    var lyricsTargetLanguage = "es"
    var visualizerStyle = "aurora"
    var visualizerSensitivity = 1.0
    var visualizerFPS = 30.0
    var animateVisualizer = true
    var miniAlwaysOnTop = true
    var miniAllSpaces = true
    init() {}
    private enum CodingKeys: String, CodingKey {
        case outputDeviceUID, directOutput, exclusiveOutput, hasCompletedWelcome, eqEnabled, eqGains, eqPreset, preamp,
            autoHeadroom, replayGain, balance, playbackRate, continueQueue, gaplessPlayback, keepAwake, rememberPosition,
            startSection, glassStyle,
            atmosphere, adaptiveArtwork, ambientMotion, artworkPulse, glassTransparency, microInteractions, hoverDepth,
            showFeedback, compactRows, showQuality, albumSize, autoArtwork, autoLyrics, watchMusicFolders,
            recursiveScan, scanWorkers,
            lyricsFontSize, lyricsOffset, autoScrollLyrics, translateLyrics, lyricsTargetLanguage, visualizerStyle,
            visualizerSensitivity,
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
        replayGain = try values.decodeIfPresent(ReplayGainMode.self, forKey: .replayGain) ?? .off
        balance = try values.decodeIfPresent(Float.self, forKey: .balance) ?? balance
        playbackRate = try values.decodeIfPresent(Float.self, forKey: .playbackRate) ?? playbackRate
        continueQueue = try values.decodeIfPresent(Bool.self, forKey: .continueQueue) ?? continueQueue
        gaplessPlayback = try values.decodeIfPresent(Bool.self, forKey: .gaplessPlayback) ?? gaplessPlayback
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
        watchMusicFolders = try values.decodeIfPresent(Bool.self, forKey: .watchMusicFolders) ?? watchMusicFolders
        recursiveScan = try values.decodeIfPresent(Bool.self, forKey: .recursiveScan) ?? recursiveScan
        scanWorkers = try values.decodeIfPresent(Int.self, forKey: .scanWorkers) ?? scanWorkers
        lyricsFontSize = try values.decodeIfPresent(Double.self, forKey: .lyricsFontSize) ?? lyricsFontSize
        lyricsOffset = try values.decodeIfPresent(Double.self, forKey: .lyricsOffset) ?? lyricsOffset
        autoScrollLyrics = try values.decodeIfPresent(Bool.self, forKey: .autoScrollLyrics) ?? autoScrollLyrics
        translateLyrics = try values.decodeIfPresent(Bool.self, forKey: .translateLyrics) ?? translateLyrics
        lyricsTargetLanguage =
            try values.decodeIfPresent(String.self, forKey: .lyricsTargetLanguage) ?? lyricsTargetLanguage
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
    static let visualizerStyles = ["aurora", "bars", "mirror", "centered", "nebula", "orbit", "ribbons"]
    static let visualizerFrameRates = [24.0, 30.0, 60.0]
    var visualizerFrameInterval: TimeInterval { 1 / visualizerFPS }
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
    mutating func reset(section: String) {
        let initial = Self()
        switch section {
        case "sound":
            outputDeviceUID = initial.outputDeviceUID
            directOutput = initial.directOutput
            exclusiveOutput = initial.exclusiveOutput
            balance = initial.balance
            eqEnabled = initial.eqEnabled
            selectPreset(initial.eqPreset)
            preamp = initial.preamp
            autoHeadroom = initial.autoHeadroom
            replayGain = initial.replayGain
        case "playback":
            playbackRate = initial.playbackRate
            continueQueue = initial.continueQueue
            gaplessPlayback = initial.gaplessPlayback
            keepAwake = initial.keepAwake
            rememberPosition = initial.rememberPosition
            miniAlwaysOnTop = initial.miniAlwaysOnTop
            miniAllSpaces = initial.miniAllSpaces
        case "library":
            watchMusicFolders = initial.watchMusicFolders
            recursiveScan = initial.recursiveScan
            scanWorkers = initial.scanWorkers
        case "metadata":
            autoArtwork = initial.autoArtwork
            autoLyrics = initial.autoLyrics
        case "appearance":
            glassStyle = initial.glassStyle
            atmosphere = initial.atmosphere
            adaptiveArtwork = initial.adaptiveArtwork
            ambientMotion = initial.ambientMotion
            artworkPulse = initial.artworkPulse
            glassTransparency = initial.glassTransparency
            microInteractions = initial.microInteractions
            hoverDepth = initial.hoverDepth
            showFeedback = initial.showFeedback
            compactRows = initial.compactRows
            showQuality = initial.showQuality
            albumSize = initial.albumSize
            startSection = initial.startSection
        case "experience":
            lyricsFontSize = initial.lyricsFontSize
            lyricsOffset = initial.lyricsOffset
            autoScrollLyrics = initial.autoScrollLyrics
            translateLyrics = initial.translateLyrics
            lyricsTargetLanguage = initial.lyricsTargetLanguage
            visualizerStyle = initial.visualizerStyle
            visualizerSensitivity = initial.visualizerSensitivity
            visualizerFPS = initial.visualizerFPS
            animateVisualizer = initial.animateVisualizer
        default:
            break
        }
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
        if !Self.visualizerFrameRates.contains(visualizerFPS) { visualizerFPS = Self().visualizerFPS }
        if !Self.visualizerStyles.contains(visualizerStyle) { visualizerStyle = "aurora" }
        atmosphere = atmosphere.isFinite ? min(1, max(0, atmosphere)) : 0.75
        glassTransparency = glassTransparency.isFinite ? min(1, max(0, glassTransparency)) : 0.65
    }
}
struct Playlist: Identifiable, Codable, Equatable {
    var id = UUID()
    var name: String
    var trackIDs: [String] = []
    var rules: SmartPlaylistRules?
}
