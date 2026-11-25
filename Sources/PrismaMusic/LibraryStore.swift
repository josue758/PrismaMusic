import AVFoundation
import AppKit
import Combine
import MediaPlayer
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: NSObject, ObservableObject {
    let outputs = AudioOutputCatalog(autoStart: false)
    let airPlayPlayer = AVPlayer()
    private let outputController = AudioDeviceController()
    private var outputSubscriptions = Set<AnyCancellable>()
    private var outputResumeIntent = false
    @Published private(set) var airPlayReceiverActive = false
    private var airPlayRouteObserver: NSKeyValueObservation?
    @Published private(set) var usingAirPlay = false
    @Published private(set) var playbackBuffering = false
    @Published private(set) var preparedOutput: OutputPreparation?
    struct AlbumTrackReveal: Equatable {
        let trackID: String
        private let requestID = UUID()
    }
    @Published private(set) var albumTrackReveal: AlbumTrackReveal?
    @Published var selectedAlbumID: String?
    @Published var selectedArtist: String?
    @Published var tracks: [Track] = [] {
        didSet {
            invalidateLibraryCaches()
            refreshArtworkPalette()
        }
    }
    @Published var sources: [MusicSource] = []
    @Published var currentID: String? { didSet { refreshArtworkPalette() } }
    @Published private(set) var loadingTrackID: String?
    private var playbackLoadTask: Task<Void, Never>?
    private var successorTask: Task<Void, Never>?
    private var successorAttempt: String?
    private var gainTask: Task<Void, Never>?
    private let successorLoader = AudioFileLoader()
    private var albumPlayTask: Task<Void, Never>?
    @Published private(set) var preparingAlbumID: String?
    private var playbackRequest = UUID()
    private let openAudioFile: @Sendable (URL) async throws -> OpenedAudioFile
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var level = 0.0
    @Published private(set) var loading = true
    @Published private(set) var scanning = false
    @Published private(set) var writingFileTags = false
    @Published private(set) var scanDiscovered = 0
    @Published private(set) var scanProcessed = 0
    @Published private(set) var scanAudit: ScanAudit?
    @Published private(set) var relocatingSource = false
    @Published private(set) var relocationProcessed = 0
    @Published private(set) var relocationTotal = 0
    private var relocationCancellation = ScanCancellation()
    func cancelSourceRelocation() { relocationCancellation.cancel() }
    @Published private(set) var sourceStates: [UUID: String] = [:]
    @Published var status = ""
    @Published var error: String?
    struct NASRetry: Identifiable {
        let id = UUID()
        let sourceID: UUID
        let trackID: String
        let position: Double
        let request: UUID
    }
    @Published var nasRetry: NASRetry? {
        didSet {
            nasProbeTask?.cancel()
            nasRecoveryReady = false
            guard let nasRetry else { return }
            nasProbeTask = Task { [weak self] in
                while !Task.isCancelled {
                    let readable = await Task.detached(priority: .utility) {
                        FileManager.default.isReadableFile(atPath: nasRetry.trackID)
                    }.value
                    if let self, !Task.isCancelled, self.nasRetry?.id == nasRetry.id {
                        if self.nasRecoveryReady != readable { self.nasRecoveryReady = readable }
                    } else {
                        return
                    }
                    try? await Task.sleep(for: .seconds(5))
                }
            }
        }
    }
    @Published private(set) var nasRecoveryReady = false
    private var nasProbeTask: Task<Void, Never>?
    @Published var search = ""
    @Published private(set) var searchFocusRequest = 0
    func focusSearch() { searchFocusRequest &+= 1 }
    @Published var artist = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var sourceFilter: LibrarySourceFilter?
    @Published var section = "home"
    @Published var sort = "title"
    @Published var feedback: FeedbackNotice?
    private var feedbackTask: Task<Void, Never>?
    @Published var artworkPalette = ArtworkPalette.fallback()
    @Published var ambientEnergy = 0.0
    @Published var showVisualizer = false
    @Published private(set) var fullScreenVisualizer = false
    @Published private(set) var visualizerBands: [Float] = []
    private var spectrumActive = false
    func setVisualizerSpectrumActive(_ active: Bool) {
        spectrumActive = active
        (player as? AudioPlayback)?.setSpectrumEnabled(active)
        if !active { visualizerBands = [] }
    }
    @Published var showLyrics = false
    @Published var showQueue = false
    @Published var showInfo = false
    @Published var inspectedID: String?
    @Published var fetching = false
    @Published var playlists: [Playlist] = [] { didSet { sectionQueries["playlist:"] = nil } }
    @Published var sleepDeadline: Date?
    @Published var sleepRemaining = 0
    @Published var stopAfterCurrent = false { didSet { if stopAfterCurrent != oldValue { verifySuccessor() } } }
    @Published var peak = 0.0
    @Published var preferences = ListeningPreferences() { didSet { preferencesChanged(previous: oldValue) } }
    @Published var settingsPage = "sound"
    @Published var showWelcome = false
    private var welcomeAfterSettings = false
    @Published var showSettings = false
    @Published var shuffle = false {
        didSet {
            guard !restoringQueue else { return }
            if shuffle && !oldValue {
                let rest = queue.filter { $0 != currentID }.shuffled()
                queue = currentID.map { [$0] + rest } ?? rest
            }
            if shuffle != oldValue { scheduleQueueSave() }
        }
    }
    @Published var repeatMode = 0 {  // 0 off, 1 all, 2 one
        didSet {
            if repeatMode != oldValue {
                scheduleQueueSave()
                verifySuccessor()
            }
        }
    }
    @Published var volume: Float = 0.7 {
        didSet {
            player?.volume = volume
            UserDefaults.standard.set(volume, forKey: "volume")
        }
    }
    @Published var language: AppLanguage = .es {
        didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") }
    }
    @Published var accent: Accent = .violet { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    @Published var theme = "dark" { didSet { UserDefaults.standard.set(theme, forKey: "theme") } }
    @Published var online = true { didSet { UserDefaults.standard.set(online, forKey: "online") } }
    @Published var scanOnLaunch = true { didSet { UserDefaults.standard.set(scanOnLaunch, forKey: "scanOnLaunch") } }
    private var paletteTask: Task<Void, Never>?
    private var paletteTrackID: String?
    private var paletteArtworkID: String?
    private let scanWorkerOverride: Int?
    private var maximumScanWorkers: Int { min(8, max(1, scanWorkerOverride ?? preferences.scanWorkers)) }
    private let persistence: LibraryPersistence
    private var saveBlocked = false
    private var quitting = false
    private var readyTask: Task<Void, Never>?
    private var scanTask: Task<Void, Never>?
    private var scanCancellation = ScanCancellation()
    private var automaticScanTimer: Timer?
    private var automaticRetryAfter: [String: Date] = [:]
    private var trackIndex: [String: Int]?
    private var queueIndexCache: [String: Int]?
    private var cachedUpcoming: (revision: Int, currentID: String?, ids: [String])?
    private var statisticsCache: LibraryStatistics?
    private var sectionQueries: [String: (key: LibraryQueryKey, result: LibraryQueryCache)] = [:]
    private var orderedTracks: (sort: String, tracks: [Track])?
    private var recentTracks: [Track]?
    private var recentImports: [Track]?
    private var volumeUnmountObserver: AnyCancellable?
    private var wakeObserver: AnyCancellable?
    private var albumCollectionCache: (revision: Int, id: String, source: LibrarySourceFilter?, value: AlbumCollection)?
    func albumCollection(_ id: String) -> AlbumCollection? {
        if let cached = albumCollectionCache, cached.revision == revision, cached.id == id,
            cached.source == activeSourceFilter
        { return cached.value }
        guard let seed = track(for: id) else { return nil }
        let source = activeSourceFilter
        let folder = selectedLibrarySource?.url
        let filterApplies = Self.matchesSource(seed, filter: source, folder: folder)
        let value = AlbumCollection(seed: seed, library: tracks.filter {
            ($0.hiddenDuplicate != true || $0.id == seed.id)
                && (!filterApplies || Self.matchesSource($0, filter: source, folder: folder))
        })
        albumCollectionCache = (revision, id, activeSourceFilter, value)
        return value
    }
    private struct DetailOrigin {
        let section: String
        let artist: String?
        let albumID: String?
    }
    private var detailHistory: [DetailOrigin] = []
    var backDestination: String? {
        guard let origin = detailHistory.last else { return nil }
        if let id = origin.albumID, let track = track(for: id) { return displayAlbum(track.album) }
        if let artist = origin.artist { return displayArtist(artist) }
        if let playlist = playlists.first(where: { "playlist:\($0.id)" == origin.section }) { return playlist.name }
        return t(origin.section)
    }
    private func rememberDetailOrigin() {
        detailHistory.append(.init(section: section, artist: selectedArtist, albumID: selectedAlbumID))
    }
    func goBack() {
        if showVisualizer {
            showVisualizer = false
            return
        }
        guard let origin = detailHistory.popLast() else { return }
        albumTrackReveal = nil
        section = origin.section
        selectedArtist = origin.artist
        selectedAlbumID = origin.albumID
    }
    func navigateTo(_ destination: String, preservingSearch: Bool = false) {
        if albumTrackReveal != nil { albumTrackReveal = nil }
        detailHistory.removeAll()
        if selectedAlbumID != nil { selectedAlbumID = nil }
        if selectedArtist != nil { selectedArtist = nil }
        if showVisualizer { showVisualizer = false }
        if section != destination { section = destination }
        if !preservingSearch && !search.isEmpty { search = "" }
        clearMetadataFilters()
    }
    func openAlbum(_ track: Track, revealTrack: Bool = false) {
        if revealTrack {
            albumTrackReveal = AlbumTrackReveal(trackID: track.id)
            inspectedID = track.id
        } else if albumTrackReveal != nil {
            albumTrackReveal = nil
        }
        guard selectedAlbumID != track.id || showVisualizer else { return }
        if selectedAlbumID == track.id {
            showVisualizer = false
            return
        }
        rememberDetailOrigin()
        selectedAlbumID = track.id
        inspectedID = track.id
        showVisualizer = false
        if section != "artists" || selectedArtist == nil {
            section = "albums"
            selectedArtist = nil
        }
    }
    func openArtist(_ name: String) {
        guard selectedArtist != name || selectedAlbumID != nil else { return }
        rememberDetailOrigin()
        albumTrackReveal = nil
        selectedAlbumID = nil
        selectedArtist = name
        section = "artists"
        showVisualizer = false
    }
    func readAlbumOrder(_ id: String) async {
        guard !writingFileTags, let album = albumCollection(id) else { return }
        let pending = album.tracks.filter { $0.albumOrderRead != true }
        var positions: [String: (Int?, Int?)] = [:]
        await withTaskGroup(of: (String, Int?, Int?)?.self) { group in
            var next = 0
            func submit() {
                guard next < pending.count, !Task.isCancelled else { return }
                let file = pending[next].url
                next += 1
                group.addTask {
                    guard
                        let value = try? await MetadataReader.read(
                            file, sidecars: ScannedAudioFile(url: file, modified: nil, sidecarsKnown: true)),
                        !Task.isCancelled
                    else { return nil }
                    return (file.path, value.trackNumber, value.discNumber)
                }
            }
            for _ in 0..<min(2, pending.count) { submit() }
            while let value = await group.next() {
                if Task.isCancelled {
                    group.cancelAll()
                    break
                }
                if let value { positions[value.0] = (value.1, value.2) }
                submit()
            }
        }
        guard !writingFileTags, !positions.isEmpty, !Task.isCancelled else { return }
        var updated = tracks
        for i in updated.indices {
            if updated[i].albumOrderRead != true, let value = positions[updated[i].id] {
                updated[i].trackNumber = value.0
                updated[i].discNumber = value.1
                updated[i].albumOrderRead = true
            }
        }
        tracks = updated
        save()
    }
    private var artistCollectionCache: (revision: Int, name: String, value: ArtistCollection)?
    func artistCollection(_ name: String) -> ArtistCollection {
        if let cached = artistCollectionCache, cached.revision == revision, cached.name == name { return cached.value }
        let value = ArtistCollection(name: name, library: tracks.filter { $0.hiddenDuplicate != true })
        artistCollectionCache = (revision, name, value)
        return value
    }
    private var revision = 0
    @Published private(set) var appliedReplayGain: Float?
    private var player: (any MusicPlayback)? { didSet { refreshAppliedReplayGain() } }
    private var timer: Timer?
    @Published var queue: [String] = [] {
        didSet {
            queueIndexCache = nil
            cachedUpcoming = nil
            if queue != oldValue {
                scheduleQueueSave()
                verifySuccessor()
            }
        }
    }
    private struct QueueBookmark: Codable, Equatable {
        var ids: [String]
        var shuffle: Bool
        var repeatMode: Int
    }
    private var savedQueue: QueueBookmark?
    private var lastStoredQueue: QueueBookmark?
    private var restoringQueue = false
    private var queueSaveTask: Task<Void, Never>?
    private var activity: NSObjectProtocol?
    private var lastPlaybackCheckpoint = ContinuousClock.now
    private var savedPlayback: (String, Double)?
    private var scopeURLs: [URL] = []
    private var panel: NSPanel?
    private var attempted: Set<String> = []
    private var enrichmentTask: Task<Void, Never>?
    private var edited: Set<String> = []
    private var tagEdits: [String: TrackTagEdits] = [:]
    private struct TagUndo {
        var before: Track
        var after: Track
        var previous: TrackTagEdits?
        var applied: TrackTagEdits
        var carriedAlbumArtwork = false
    }
    private var tagUndo: [TagUndo] = []
    @Published private(set) var canUndoTagEdits = false

    lazy var artistPhotoStore = ArtistPhotoStore(directory: dataDirectory)
    private let dataDirectory: URL
    func track(for id: String) -> Track? {
        if trackIndex == nil {
            trackIndex = Dictionary(tracks.indices.map { (tracks[$0].id, $0) }, uniquingKeysWith: { _, last in last })
        }
        guard let index = trackIndex?[id], tracks.indices.contains(index) else { return nil }
        return tracks[index]
    }
    var current: Track? { currentID.flatMap { track(for: $0) } }
    var visualTrack: Track? { current ?? tracks.first }
    var effectiveAccent: Color {
        guard preferences.adaptiveArtwork, visualTrack != nil else { return accent.color }
        let dark =
            colorScheme == .dark
            || (colorScheme == nil && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        return artworkPalette.primary.readable(onDark: dark).color
    }
    private func refreshArtworkPalette() {
        let track = visualTrack
        let artworkID = track?.hasArtwork == true ? track?.artworkIdentity : nil
        guard paletteTrackID != track?.id || paletteArtworkID != artworkID else { return }
        paletteTrackID = track?.id
        paletteArtworkID = artworkID
        paletteTask?.cancel()
        let fallback = ArtworkPalette.fallback(album: track?.album ?? "Prisma")
        guard let track, track.hasArtwork else {
            artworkPalette = fallback
            return
        }
        paletteTask = Task { [weak self] in
            let palette = await Task.detached(priority: .utility) {
                track.artworkData.map { ArtworkPalette.extract($0, fallback: fallback) } ?? fallback
            }.value
            guard !Task.isCancelled, let self, self.paletteTrackID == track.id, self.paletteArtworkID == artworkID
            else { return }
            self.artworkPalette = palette
        }
    }
    var colorScheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    var queuedTracks: [Track] { queue.compactMap { track(for: $0) } }
    func queueIndex(_ id: String) -> Int? {
        if queueIndexCache == nil {
            queueIndexCache = Dictionary(
                queue.enumerated().map { ($0.element, $0.offset) }, uniquingKeysWith: { first, _ in first })
        }
        return queueIndexCache?[id]
    }
    private func invalidateLibraryCaches() {
        revision += 1
        trackIndex = nil
        statisticsCache = nil
        sectionQueries.removeAll(keepingCapacity: true)
        orderedTracks = nil
        recentTracks = nil
        recentImports = nil
    }
    var statistics: LibraryStatistics {
        if let statisticsCache { return statisticsCache }
        let value = LibraryStatistics(tracks: tracks.filter { $0.hiddenDuplicate != true })
        statisticsCache = value
        return value
    }
    var hasActiveFilters: Bool { !search.isEmpty || !artist.isEmpty || !genre.isEmpty || !year.isEmpty || activeSourceFilter != nil }
    var activeSourceFilter: LibrarySourceFilter? {
        guard section == "songs" || section == "albums" else { return nil }
        if case .folder(let id) = sourceFilter, !sources.contains(where: { $0.id == id }) { return nil }
        return sourceFilter
    }
    var selectedLibrarySource: MusicSource? {
        guard case .folder(let id) = activeSourceFilter else { return nil }
        return sources.first { $0.id == id }
    }
    private static func matchesSource(_ track: Track, filter: LibrarySourceFilter?, folder: URL?) -> Bool {
        switch filter {
        case .network: return track.sourceIsNetwork == true
        case .local: return track.sourceIsNetwork != true
        case .folder: return folder.map { SourceScanner.isWithin(track.url, source: $0) } ?? false
        case nil: return true
        }
    }
    var sectionSummary: String {
        let songs = songCountText(filtered.count)
        if section == "albums" {
            return
                "\(groupedAlbums.count) \(t(groupedAlbums.count == 1 ? "albumSingular" : "albums").lowercased()) · \(songs)"
        }
        if section == "artists" {
            return
                "\(groupedArtists.count) \(t(groupedArtists.count == 1 ? "artistSingular" : "artists").lowercased()) · \(songs)"
        }
        return songs + " · " + collectionTimeText(results.duration)
    }
    var albumCount: Int { statistics.albumCount }
    var artistCount: Int { statistics.artists.count }
    var libraryBytes: Int64 { statistics.bytes }
    var totalDuration: Double { statistics.duration }
    private var results: LibraryQueryCache {
        let playlist = activePlaylist
        let isPlaylist = section.hasPrefix("playlist:")
        let source = activeSourceFilter
        let sourceURL = selectedLibrarySource?.url
        let key = LibraryQueryKey(
            revision: revision, search: search, artist: artist, genre: genre, year: year, section: section, sort: sort,
            smartPlaylistMonth: playlist?.rules?.addedThisMonth == true
                ? Calendar.current.dateInterval(of: .month, for: .now)?.start : nil,
            source: source, sourcePath: sourceURL?.path)
        let cacheSlot = isPlaylist ? "playlist:" : section
        if let cached = sectionQueries[cacheSlot], cached.key == key { return cached.result }

        let base: [Track]
        if isPlaylist {
            if let rules = playlist?.rules {
                base = rules.filter(tracksInCurrentOrder)
            } else {
                base = playlist?.trackIDs.compactMap { track(for: $0) } ?? []
            }
        } else if section == "recent" {
            if let recentTracks {
                base = recentTracks
            } else {
                base = tracks.filter { $0.lastPlayed != nil }.sorted {
                    ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
                }
                recentTracks = base
            }
        } else {
            let ordered = tracksInCurrentOrder
            base = section == "lossless" ? ordered.filter(\.isLossless) : ordered
        }
        let visible = playlist?.rules == nil && isPlaylist ? base : base.filter {
            $0.hiddenDuplicate != true && Self.matchesSource($0, filter: source, folder: sourceURL)
        }
        let value = LibraryQuery.filter(
            visible, search: search, artist: artist, genre: genre, year: year, favorites: section == "favorites")
        let cache = LibraryQueryCache(tracks: value, albumSort: sort)
        if sectionQueries[cacheSlot] == nil && sectionQueries.count >= 8 {
            sectionQueries.removeAll(keepingCapacity: true)
        }
        sectionQueries[cacheSlot] = (key, cache)
        return cache
    }

    private var tracksInCurrentOrder: [Track] {
        if let orderedTracks, orderedTracks.sort == sort { return orderedTracks.tracks }
        let order = sort
        let sorted = tracks.map { track -> (Track, String) in
            switch order {
            case "artist": return (track, track.artist + track.album + track.title)
            case "album": return (track, track.album + track.title)
            case "year": return (track, track.year + track.title)
            default: return (track, track.title)
            }
        }.sorted { $0.1.localizedStandardCompare($1.1) == .orderedAscending }.map { $0.0 }
        orderedTracks = (order, sorted)
        return sorted
    }
    var filtered: [Track] { results.tracks }
    var recentlyAdded: [Track] {
        if let recentImports { return recentImports }
        let value = Array(tracks.filter { $0.addedAt != nil && $0.hiddenDuplicate != true }
            .sorted { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }.prefix(8))
        recentImports = value
        return value
    }
    var groupedAlbums: [(key: String, value: [Track])] { results.albums }
    var groupedArtists: [(key: String, value: [Track])] { results.artists }
    func displayIndex(_ id: String) -> Int { results.indices[id] ?? 0 }
    func displayArtist(_ value: String) -> String {
        value.isEmpty || value == "—" ? t("unknownArtist") : ArtistIdentity.names(value).joined(separator: " · ")
    }
    func displayAlbum(_ value: String) -> String { value.isEmpty || value == "—" ? t("unknownAlbum") : value }
    func songCountText(_ count: Int) -> String { "\(count) \(t(count == 1 ? "songSingular" : "count"))" }
    func t(_ key: String) -> String { translations[key]?[language == .es ? 0 : language == .en ? 1 : 2] ?? key }
    init(
        directory: URL? = nil, autoStart: Bool = true, scanWorkers: Int? = nil,
        openAudioFile: (@Sendable (URL) async throws -> OpenedAudioFile)? = nil
    ) {
        dataDirectory =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrismaMusic")
        self.openAudioFile = openAudioFile ?? { url in try await AudioFileLoader.shared.open(url) }
        scanWorkerOverride = scanWorkers
        persistence = LibraryPersistence(directory: dataDirectory)
        super.init()
        let defaults = UserDefaults.standard
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "es") ?? .es
        accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "violet") ?? .violet
        theme = defaults.string(forKey: "theme") ?? "dark"
        online = defaults.object(forKey: "online") as? Bool ?? true
        scanOnLaunch = defaults.object(forKey: "scanOnLaunch") as? Bool ?? true
        volume = defaults.object(forKey: "volume") as? Float ?? 0.7
        if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("preferences.json")),
            var prefs = try? JSONDecoder().decode(ListeningPreferences.self, from: data)
        {
            prefs.sanitize()
            preferences = prefs
        }
        if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("scan-report.json")) {
            scanAudit = try? JSONDecoder().decode(ScanAudit.self, from: data)
        }
        section = preferences.startSection
        if preferences.rememberPosition,
            let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("playback.json")),
            let saved = try? JSONDecoder().decode(PlaybackBookmark.self, from: data)
        {
            savedPlayback = (saved.id, saved.position)
        }
        persistence.setErrorHandler { [weak self] message in Task { @MainActor in self?.error = message } }
        if autoStart {
            airPlayRouteObserver = airPlayPlayer.observe(\.isExternalPlaybackActive, options: [.new]) {
                [weak self] player, _ in
                let active = player.isExternalPlaybackActive
                Task { @MainActor in self?.airPlayReceiverActive = active }
            }
            outputs.start()
            outputs.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() }.store(
                in: &outputSubscriptions)
            outputs.$devices.dropFirst().sink { [weak self] devices in
                guard let self, !self.usingAirPlay, !self.preferences.outputDeviceUID.isEmpty, self.player != nil,
                    !devices.contains(where: { $0.uid == self.preferences.outputDeviceUID })
                else { return }
                if !self.directOutputActive, let prepared = self.preparedOutput,
                    !devices.contains(where: { $0.id == prepared.deviceID })
                {
                    self.restartOutput()
                    return
                }
                if !self.directOutputActive { return }
                self.pausePlayback()
                self.player?.stop()
                self.player = nil
                self.preparedOutput = nil
                self.status = self.t("outputUnavailable")
            }.store(in: &outputSubscriptions)
            outputs.$defaultID.dropFirst().removeDuplicates().sink { [weak self] _ in
                guard let self, self.preferences.outputDeviceUID.isEmpty, !self.usingAirPlay, self.player != nil else {
                    return
                }
                self.restartOutput()
            }.store(in: &outputSubscriptions)
            timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 15, repeats: true) { [weak self] _ in
                Task { @MainActor in self?.tick() }
            }
            automaticScanTimer = Timer.scheduledTimer(withTimeInterval: 90, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.checkForNewMusicInBackground() }
            }
            automaticScanTimer?.tolerance = 10
            volumeUnmountObserver = NSWorkspace.shared.notificationCenter
                .publisher(for: NSWorkspace.didUnmountNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] message in
                    guard let url = message.userInfo?[NSWorkspace.volumeURLUserInfoKey] as? URL else { return }
                    self?.volumeUnmounted(url)
                }
            wakeObserver = NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)
                .receive(on: DispatchQueue.main)
                .sink { [weak self] _ in self?.checkPlayingNASAfterWake() }
            setupRemoteCommands()
            readyTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let persistence = self.persistence
                    let snapshot = try await Task.detached(priority: .utility) { try persistence.load() }.value
                    if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("queue.json")),
                        let queue = try? JSONDecoder().decode(QueueBookmark.self, from: data)
                    {
                        savedQueue = queue
                    }
                    applyLoaded(snapshot, includeDemo: true)
                } catch {
                    saveBlocked = true
                    self.error = error.localizedDescription
                }
                loading = false
                guard !quitting else { return }
                restorePlaybackIfNeeded()
                restoreSavedQueue()
                if !preferences.hasCompletedWelcome {
                    showWelcome = true
                    return
                }
                if !saveBlocked && (scanOnLaunch || tracks.isEmpty) { await scanNewMusic() }
                restorePlaybackIfNeeded()
            }
        } else {
            do { applyLoaded(try persistence.load(), includeDemo: false) } catch {
                saveBlocked = true
                self.error = error.localizedDescription
            }
            loading = false
        }
    }
    private func restorePlaybackIfNeeded() {
        guard player == nil, currentID == nil, !isPlaying, let (id, time) = savedPlayback, let track = track(for: id)
        else { return }
        // Restoring the selection must not contact a sleeping or unavailable NAS.
        restoringQueue = true
        defer { restoringQueue = false }
        currentID = id
        position = min(track.duration, max(0, time))
        if queue.isEmpty && savedQueue == nil { queue = filtered.map(\.id) }
        updateNowPlaying()
    }

    private func restoreSavedQueue() {
        guard let savedQueue else { return }
        self.savedQueue = nil
        restoringQueue = true
        defer { restoringQueue = false }
        shuffle = savedQueue.shuffle
        repeatMode = max(0, min(2, savedQueue.repeatMode))
        var seen = Set<String>()
        queue = savedQueue.ids.filter { track(for: $0) != nil && seen.insert($0).inserted }
    }

    private func scheduleQueueSave() {
        guard !loading, !restoringQueue, !saveBlocked else { return }
        queueSaveTask?.cancel()
        queueSaveTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(300)) } catch { return }
            self?.storeQueue()
        }
    }

    private func storeQueue() {
        guard !saveBlocked else { return }
        queueSaveTask?.cancel()
        queueSaveTask = nil
        do {
            let snapshot = QueueBookmark(ids: queue, shuffle: shuffle, repeatMode: repeatMode)
            guard snapshot != lastStoredQueue else { return }
            persistence.writeSmallFile("queue.json", data: try JSONEncoder().encode(snapshot))
            lastStoredQueue = snapshot
        } catch { status = error.localizedDescription }
    }

    private func applyLoaded(_ snapshot: LibrarySnapshot?, includeDemo: Bool) {
        if let snapshot {
            tracks = snapshot.tracks
            sources = snapshot.sources
            edited = Set(snapshot.edited)
            tagEdits = snapshot.tagEdits ?? [:]
            for track in snapshot.tracks where edited.contains(track.id) && tagEdits[track.id] == nil {
                tagEdits[track.id] = .legacy(track)
            }
            playlists = snapshot.playlists ?? []
            if let backup = persistence.recoveredBackup { error = t("libraryRecovered") + " " + backup }
            if persistence.restoredManually { status = t("backupRestored") }
        } else if includeDemo, let demo = Bundle.module.url(forResource: "Demo", withExtension: nil) {
            sources = [MusicSource(url: demo)]
        }
        if let demo = Bundle.module.url(forResource: "Demo", withExtension: nil) {
            for index in sources.indices where sources[index].url.path.contains("PrismaMusic_PrismaMusic.bundle") {
                let previous = sources[index].url
                sources[index].url = demo
                if previous != demo {
                    var remapped = tracks
                    for i in remapped.indices
                    where remapped[i].url.deletingLastPathComponent().standardizedFileURL
                        == previous.standardizedFileURL
                    { remapped[i].url = demo.appendingPathComponent(remapped[i].url.lastPathComponent) }
                    tracks = remapped
                }
            }
        }
        for index in sources.indices {
            if let data = sources[index].bookmark {
                var stale = false
                if let url = try? URL(
                    resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI, .withoutMounting],
                    relativeTo: nil, bookmarkDataIsStale: &stale)
                {
                    let previous = sources[index].url
                    sources[index].url = url
                    if previous.path != url.path { remapSource(previous, to: url) }
                    if url.startAccessingSecurityScopedResource() { scopeURLs.append(url) }
                    if stale {
                        sources[index].bookmark = try? url.bookmarkData(
                            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
                    }
                }
            }
        }
    }
    private func remapSource(_ old: URL, to new: URL, isNetwork: Bool? = nil) {
        let prefix = old.path.hasSuffix("/") ? old.path : old.path + "/"
        func relocated(_ url: URL) -> URL? {
            if url.path == old.path { return new }
            guard url.path.hasPrefix(prefix) else { return nil }
            return new.appendingPathComponent(String(url.path.dropFirst(prefix.count)))
        }
        var ids: [String: String] = [:]
        tracks = tracks.map { track in
            guard let url = relocated(track.url) else { return track }
            var value = track
            value.url = url
            if let isNetwork { value.sourceIsNetwork = isNetwork }
            ids[track.id] = value.id
            return value
        }
        playlists = playlists.map { list in
            var value = list
            value.trackIDs = value.trackIDs.map { ids[$0] ?? $0 }
            return value
        }
        edited = Set(edited.map { ids[$0] ?? $0 })
        tagEdits = Dictionary(tagEdits.map { (ids[$0.key] ?? $0.key, $0.value) }, uniquingKeysWith: { _, last in last })
        tagUndo = []
        canUndoTagEdits = false
        queue = queue.map { ids[$0] ?? $0 }
        if let id = currentID { currentID = ids[id] ?? id }
        if let id = inspectedID { inspectedID = ids[id] ?? id }
        if let id = selectedAlbumID { selectedAlbumID = ids[id] ?? id }
        detailHistory = detailHistory.map { origin in
            .init(section: origin.section, artist: origin.artist, albumID: origin.albumID.map { ids[$0] ?? $0 })
        }
        if let (id, time) = savedPlayback { savedPlayback = (ids[id] ?? id, time) }
        if let old = savedQueue?.ids { savedQueue?.ids = old.map { ids[$0] ?? $0 } }
    }
    func save() {
        guard !saveBlocked else { return }
        persistence.save(
            .init(tracks: tracks, sources: sources, edited: Array(edited), playlists: playlists, tagEdits: tagEdits))
    }
    func flushSaving() async throws { try await persistence.flush() }
    func prepareForTermination() async throws {
        guard !writingFileTags else { throw PersistenceFailure(message: t("writingFileTags")) }
        quitting = true
        defer { quitting = false }
        cancelScan()
        cancelSourceRelocation()
        if loading { await readyTask?.value }
        await scanTask?.value
        storeQueue()
        pausePlayback()
        player?.stop()
        player = nil
        airPlayPlayer.replaceCurrentItem(with: nil)
        await outputController.release()
        paletteTask?.cancel()
        enrichmentTask?.cancel()
        save()
        try await persistence.flush()
        timer?.invalidate()
        timer = nil
        automaticScanTimer?.invalidate()
        automaticScanTimer = nil
        for url in scopeURLs { url.stopAccessingSecurityScopedResource() }
        scopeURLs.removeAll()
    }
    func waitUntilReady() async { await readyTask?.value }
    func clearFilters() {
        if !search.isEmpty { search = "" }
        sourceFilter = nil
        clearMetadataFilters()
    }

    private func clearMetadataFilters() {
        if !artist.isEmpty { artist = "" }
        if !genre.isEmpty { genre = "" }
        if !year.isEmpty { year = "" }
    }
    func pickMusic() {
        let open = NSOpenPanel()
        open.canChooseDirectories = true
        open.canChooseFiles = true
        open.allowsMultipleSelection = true
        open.allowedContentTypes = [.audio, .folder]
        open.prompt = t("add")
        open.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.addSources(open.urls) }
        }
    }
    func addSources(_ urls: [URL]) async {
        if loading { await readyTask?.value }
        if scanning { await scanTask?.value }
        guard !saveBlocked else { return }
        for url in urls
        where url.isFileURL && !sources.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            if url.startAccessingSecurityScopedResource() { scopeURLs.append(url) }
            sources.append(
                MusicSource(
                    url: url,
                    bookmark: try? url.bookmarkData(
                        options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)))
        }
        save()
        await scanNewMusic()
    }
    func pickReplacement(for source: MusicSource) {
        let panel = NSOpenPanel()
        let isFile =
            (try? source.url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile)
            ?? tracks.contains { $0.id == source.url.path }
        panel.canChooseDirectories = !isFile
        panel.canChooseFiles = isFile
        panel.allowedContentTypes = isFile ? [.audio] : [.folder]
        panel.prompt = t("relocateSource")
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in await self?.relocateSource(source, to: url.standardizedFileURL) }
        }
    }

    func relocateSource(_ source: MusicSource, to destination: URL) async {
        guard !loading, !scanning, !writingFileTags, !relocatingSource, !quitting, !saveBlocked,
            let index = sources.firstIndex(of: source),
            destination.isFileURL, destination.path != source.url.path
        else { return }
        guard
            !sources.contains(where: {
                $0.id != source.id
                    && (SourceScanner.isWithin(destination, source: $0.url)
                        || SourceScanner.isWithin($0.url, source: destination))
            })
        else {
            error = t("relocateConflict")
            return
        }
        let sourceTracks = tracks.filter { SourceScanner.isWithin($0.url, source: source.url) }
        let prefix = source.url.path.hasSuffix("/") ? source.url.path : source.url.path + "/"
        let destinations = sourceTracks.map {
            $0.id == source.url.path
                ? destination : destination.appendingPathComponent(String($0.id.dropFirst(prefix.count)))
        }
        let accessible = destination.startAccessingSecurityScopedResource()
        var keepAccess = false
        defer { if accessible && !keepAccess { destination.stopAccessingSecurityScopedResource() } }
        let originalSources = sources
        let cancellation = ScanCancellation()
        relocationCancellation = cancellation
        relocatingSource = true
        relocationProcessed = 0
        relocationTotal = destinations.count
        defer { relocatingSource = false }
        let (exists, isNetwork) = await Task.detached(priority: .utility) { [weak self] in
            let identity = SourceIdentity.read(destination)
            guard identity != nil, FileManager.default.isReadableFile(atPath: destination.path) else {
                return (false, false)
            }
            for (offset, url) in destinations.enumerated() {
                guard !cancellation.isCancelled, FileManager.default.isReadableFile(atPath: url.path) else {
                    return (false, false)
                }
                if (offset + 1) % 32 == 0 || offset + 1 == destinations.count {
                    Task { @MainActor [weak self] in
                        guard let self, self.relocatingSource, self.relocationCancellation === cancellation else {
                            return
                        }
                        self.relocationProcessed = offset + 1
                    }
                }
            }
            let isNetwork = (try? destination.resourceValues(forKeys: [.volumeIsLocalKey]).volumeIsLocal) == false
            return (SourceIdentity.read(destination) == identity, isNetwork)
        }.value
        guard !cancellation.isCancelled, !loading, !scanning, !quitting, !saveBlocked, sources == originalSources,
            tracks.filter({ SourceScanner.isWithin($0.url, source: source.url) }).map(\.id) == sourceTracks.map(\.id)
        else { return }
        let originalIDs = Set(sourceTracks.map(\.id))
        let destinationIDs = Set(destinations.map(\.path))
        guard !tracks.contains(where: { !originalIDs.contains($0.id) && destinationIDs.contains($0.id) }) else {
            error = t("relocateConflict")
            return
        }
        guard exists else {
            error = t("relocateMissing")
            return
        }
        let affected = [currentID, loadingTrackID].compactMap { $0 }.contains {
            SourceScanner.isWithin(URL(fileURLWithPath: $0), source: source.url)
        }
        if affected {
            pausePlayback()
            player?.stop()
            player = nil
            preparedOutput = nil
        }
        var replacement = source
        replacement.url = destination
        replacement.bookmark = try? destination.bookmarkData(
            options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)
        replacement.serverAddress = nil
        if accessible {
            scopeURLs.append(destination)
            keepAccess = true
        }
        sources[index] = replacement
        remapSource(source.url, to: destination, isNetwork: isNetwork)
        sourceStates[source.id] = "ready"
        save()
        do {
            try await flushSaving()
            rememberPlayback()
            updateNowPlaying()
        } catch { self.error = error.localizedDescription }
    }

    func rememberedServer(for retry: NASRetry) -> URL? {
        sources.first { $0.id == retry.sourceID }?.serverAddress
    }

    func resumeNASPlayback(_ retry: NASRetry) async throws {
        guard playbackRequest == retry.request, let song = track(for: retry.trackID),
            sources.contains(where: { $0.id == retry.sourceID })
        else { throw CancellationError() }
        let available = await Task.detached(priority: .utility) {
            FileManager.default.isReadableFile(atPath: song.url.path)
        }.value
        try Task.checkCancellation()
        guard playbackRequest == retry.request, let latest = track(for: retry.trackID), latest.url == song.url,
            sources.contains(where: { $0.id == retry.sourceID })
        else { throw CancellationError() }
        guard available else { throw URLError(.fileDoesNotExist) }
        finishNASRecovery(retry, song: latest)
    }

    private func finishNASRecovery(_ retry: NASRetry, song: Track) {
        sourceStates[retry.sourceID] = "ready"
        nasRetry = nil
        play(song, from: retry.position)
    }

    func reconnect(_ retry: NASRetry, server: URL) async throws {
        guard playbackRequest == retry.request, let song = track(for: retry.trackID),
            let index = sources.firstIndex(where: { $0.id == retry.sourceID }),
            NSWorkspace.shared.open(server)
        else { throw URLError(.cannotConnectToHost) }
        for _ in 0..<60 {
            try Task.checkCancellation()
            guard playbackRequest == retry.request else { throw CancellationError() }
            let available = await Task.detached(priority: .utility) {
                FileManager.default.isReadableFile(atPath: song.url.path)
            }.value
            try Task.checkCancellation()
            guard playbackRequest == retry.request else { throw CancellationError() }
            if available {
                guard sources.indices.contains(index), sources[index].id == retry.sourceID else {
                    throw URLError(.fileDoesNotExist)
                }
                sources[index].serverAddress = server
                save()
                finishNASRecovery(retry, song: song)
                return
            }
            try await Task.sleep(for: .milliseconds(500))
        }
        throw URLError(.timedOut)
    }

    private func reconnectRequest(for track: Track, position: Double) -> NASRetry? {
        guard track.sourceIsNetwork == true,
            let source = sources.filter({ SourceScanner.isWithin(track.url, source: $0.url) })
                .max(by: { $0.url.path.count < $1.url.path.count })
        else { return nil }
        return NASRetry(sourceID: source.id, trackID: track.id, position: position, request: playbackRequest)
    }

    func volumeUnmounted(_ url: URL) {
        guard isPlaying, !playbackLoading, let current,
            SourceScanner.isWithin(current.url, source: url),
            let retry = reconnectRequest(for: current, position: position)
        else { return }
        offerPlaybackRecovery(retry)
    }

    private func offerPlaybackRecovery(_ retry: NASRetry) {
        cancelSuccessor()
        player?.stop()
        player = nil
        preparedOutput = nil
        playbackBuffering = false
        isPlaying = false
        position = retry.position
        rememberPlayback()
        sourceStates[retry.sourceID] = "offline"
        nasRetry = retry
        updateActivity()
        updateNowPlaying()
    }

    private func checkPlayingNASAfterWake() {
        guard isPlaying, !playbackLoading, let current,
            let retry = reconnectRequest(for: current, position: position)
        else { return }
        Task { [weak self] in
            let readable = await Task.detached(priority: .utility) {
                FileManager.default.isReadableFile(atPath: retry.trackID)
            }.value
            guard let self, !readable, self.playbackRequest == retry.request,
                self.currentID == retry.trackID, self.isPlaying, self.nasRetry == nil
            else { return }
            self.offerPlaybackRecovery(retry)
        }
    }

    func openAudioURL(_ url: URL) async {
        await addSources([url])
        if let track = track(for: url.path) {
            let list = filtered
            play(track, in: list.contains(where: { $0.id == track.id }) ? list : [track] + list)
        }
    }
    func cancelScan() {
        if scanning { status = t("cancellingScan") }
        scanCancellation.cancel()
        scanTask?.cancel()
    }
    func openWelcome() {
        if showSettings {
            welcomeAfterSettings = true
            showSettings = false
        } else {
            showWelcome = true
        }
    }
    func settingsDismissed() {
        if welcomeAfterSettings {
            welcomeAfterSettings = false
            showWelcome = true
        }
    }
    func finishWelcome(scanAfter: Bool = true) {
        preferences.hasCompletedWelcome = true
        showWelcome = false
        navigateTo(preferences.startSection)
        if scanAfter && scanOnLaunch && !scanning { Task { await scanNewMusic() } }
    }
    func retryFailedScan(only url: URL? = nil) async {
        guard let audit = scanAudit, !audit.issues.isEmpty else { return }
        await scan(force: true, retrying: audit, retryURL: url)
    }
    func scanNewMusic() async { await scan(newOnly: true) }

    func checkForNewMusicInBackground() async {
        guard preferences.watchMusicFolders, preferences.hasCompletedWelcome,
            !loading, !scanning, !relocatingSource, !quitting, !sources.isEmpty
        else { return }
        automaticRetryAfter = automaticRetryAfter.filter { $0.value > Date() }
        await scan(newOnly: true, automatic: true)
    }

    func scan(
        force: Bool = false, retrying: ScanAudit? = nil, newOnly: Bool = false, automatic: Bool = false,
        retryURL: URL? = nil, sourceID: UUID? = nil
    ) async {
        if loading { await readyTask?.value }
        guard !scanning, !writingFileTags, !relocatingSource, !quitting, !saveBlocked,
            sourceID == nil || sources.contains(where: { $0.id == sourceID })
        else { return }
        scanning = true
        scanDiscovered = 0
        scanProcessed = 0
        scanCancellation = ScanCancellation()
        let task = Task {
            await performScan(
                force: force, retrying: retrying, newOnly: newOnly, automatic: automatic, retryURL: retryURL,
                sourceID: sourceID)
        }
        scanTask = task
        await task.value
        scanTask = nil
        scanning = false
    }
    private func performScan(
        force: Bool, retrying: ScanAudit?, newOnly: Bool, automatic: Bool, retryURL: URL?, sourceID: UUID?
    ) async {
        var failures = 0
        var unavailable = 0
        var audit = ScanAudit()
        var recovered = Set<URL>()
        let cancellation = scanCancellation
        let workers = automatic ? min(2, maximumScanWorkers) : maximumScanWorkers
        for source in sources where sourceID == nil || source.id == sourceID {
            if Task.isCancelled || cancellation.isCancelled { break }
            if !automatic {
                sourceStates[source.id] = "reading"
                status = "\(t("discovering")) · \(source.name)"
            }
            scanDiscovered = 0
            scanProcessed = 0
            let recursive = preferences.recursiveScan
            let report: SourceScanReport
            if let retrying {
                let root = source.url
                let selected = retrying.issues.map(\.url).filter {
                    (retryURL == nil || $0 == retryURL)
                        && MetadataReader.extensions.contains($0.pathExtension.lowercased())
                        && SourceScanner.isWithin($0, source: root, recursive: recursive)
                }
                if selected.isEmpty { continue }
                report = await Task.detached(priority: .utility) {
                    let identity = SourceIdentity.read(root)
                    return SourceScanReport(
                        source: root, identity: identity,
                        files: identity == nil
                            ? [] : Array(Set(selected)).map { ScannedAudioFile(url: $0, modified: nil) },
                        complete: identity != nil, errors: [])
                }.value
            } else {
                var excludedPaths: Set<String> = newOnly ? Set(tracks.map(\.id)) : []
                if automatic { excludedPaths.formUnion(automaticRetryAfter.keys) }
                let knownPaths = excludedPaths
                report = await Task.detached(priority: .utility) { [weak self] in
                    SourceScanner.enumerate(
                        source.url, recursive: recursive, cancellation: cancellation, readModificationDates: false,
                        excludingKnownPaths: knownPaths
                    ) { [weak self] count in
                        guard !automatic else { return }
                        Task { @MainActor in
                            guard let self, self.scanning, self.scanCancellation === cancellation,
                                !cancellation.isCancelled
                            else { return }
                            self.scanDiscovered = count
                            self.status = "\(self.t("discovering")) · \(source.name) · \(count) \(self.t("count"))"
                        }
                    }
                }.value
            }
            audit.discovered += report.files.count + report.knownFiles
            audit.unchanged += report.knownFiles
            if !report.complete {
                unavailable += 1
                for message in report.errors where audit.issues.count < 500 {
                    audit.issues.append(.init(url: source.url, message: message))
                }
            }
            scanDiscovered = report.files.count
            let files = report.files
            scanProcessed = 0
            var pending: [Track] = []
            pending.reserveCapacity(32)
            var lastBatch = Date()
            await withTaskGroup(of: ScannedTrackResult.self) { group in
                var next = 0
                var running = 0
                @MainActor func submit() {
                    guard next < files.count, !cancellation.isCancelled, !Task.isCancelled else { return }
                    let file = files[next]
                    next += 1
                    running += 1
                    let cached = track(for: file.url.path)
                    group.addTask(priority: automatic ? .utility : nil) {
                        await ScannedTrackResult.read(file, cached: cached, force: force)
                    }
                }
                @MainActor func fillSlots() {
                    while next < files.count, running < workers, !cancellation.isCancelled, !Task.isCancelled {
                        submit()
                    }
                }
                fillSlots()
                var processed = 0
                while let result = await group.next() {
                    if Task.isCancelled || cancellation.isCancelled {
                        group.cancelAll()
                        break
                    }
                    running -= 1
                    processed += 1
                    if result.unchanged {
                        audit.unchanged += 1
                        recovered.insert(result.file.url)
                    } else if var value = result.track {
                        do {
                            value = try await persistence.normalized(value)
                            pending.append(value)
                            audit.imported += 1
                            recovered.insert(result.file.url)
                        } catch {
                            failures += 1
                            if audit.issues.count < 500 {
                                audit.issues.append(.init(url: result.file.url, message: error.localizedDescription))
                            }
                        }
                    } else {
                        failures += 1
                        if audit.issues.count < 500 {
                            audit.issues.append(.init(url: result.file.url, message: result.error ?? t("unavailable")))
                        }
                        let expected = report.identity
                        let root = source.url
                        let sameSource = await Task.detached(priority: .utility) {
                            expected != nil && SourceIdentity.read(root) == expected
                        }.value
                        if !sameSource {
                            group.cancelAll()
                            break
                        }
                    }
                    if pending.count >= 32 || Date().timeIntervalSince(lastBatch) >= 1 {
                        if !pending.isEmpty {
                            upsertTracks(pending)
                            pending.removeAll(keepingCapacity: true)
                            save()
                        }
                        scanProcessed = processed
                        if !automatic {
                            status = "\(t("reading")) \(processed)/\(report.files.count) · \(source.name)"
                        }
                        lastBatch = Date()
                    }
                    fillSlots()
                }
                scanProcessed = processed
            }
            if !pending.isEmpty {
                upsertTracks(pending)
                save()
            }
            guard !Task.isCancelled, !cancellation.isCancelled else {
                sourceStates[source.id] = "scanCancelled"
                break
            }
            let reconciled = await Task.detached(priority: .utility) {
                if newOnly {
                    return report.complete && !cancellation.isCancelled && report.identity != nil
                        && SourceIdentity.read(report.source) == report.identity
                }
                return SourceScanner.canReconcile(report, cancelled: cancellation.isCancelled)
            }.value
            if retrying != nil || newOnly {
                sourceStates[source.id] = reconciled ? "ready" : "offline"
                if !reconciled && report.complete { unavailable += 1 }
            } else if reconciled && !Task.isCancelled {
                let found = Set(report.files.map { $0.url.path })
                tracks.removeAll {
                    SourceScanner.isWithin($0.url, source: source.url, recursive: recursive) && !found.contains($0.id)
                }
                sourceStates[source.id] = "ready"
            } else {
                sourceStates[source.id] = "offline"
                if report.complete { unavailable += 1 }
            }
            if !automatic { save() }
        }
        if !automatic { save() }
        if !automatic || audit.imported > 0 {
            do { try await persistence.flush() } catch { self.error = error.localizedDescription }
        }
        for url in recovered { automaticRetryAfter[url.path] = nil }
        let retryAt = Date().addingTimeInterval(5 * 60)
        for issue in audit.issues where MetadataReader.extensions.contains(issue.url.pathExtension.lowercased()) {
            automaticRetryAfter[issue.url.path] = retryAt
        }
        if automatic {
            if audit.imported > 0 {
                postFeedback("newSongsImported", detail: songCountText(audit.imported), icon: "music.note")
            }
            return
        }
        audit.failed = failures
        audit.unavailableSources = unavailable
        audit.cancelled = cancellation.isCancelled || Task.isCancelled
        audit.finishedAt = Date()
        if var previous = retrying {
            let messages = Dictionary(audit.issues.map { ($0.url, $0.message) }, uniquingKeysWith: { _, last in last })
            previous.issues = previous.issues.filter { !recovered.contains($0.url) }.map {
                .init(url: $0.url, message: messages[$0.url] ?? $0.message)
            }
            previous.imported += recovered.count
            previous.failed = max(0, previous.failed - recovered.count)
            previous.finishedAt = audit.finishedAt
            previous.unavailableSources = max(previous.unavailableSources, audit.unavailableSources)
            previous.cancelled = audit.cancelled
            audit = previous
            failures = audit.failed
        }
        scanAudit = audit
        let reportURL = dataDirectory.appendingPathComponent("scan-report.json")
        do {
            try await Task.detached(priority: .utility) {
                try JSONEncoder().encode(audit).write(to: reportURL, options: .atomic)
            }.value
        } catch { self.error = error.localizedDescription }
        status =
            cancellation.isCancelled
            ? t("scanCancelled")
            : unavailable > 0 ? t("offline") : failures > 0 ? "\(t("scanErrors")): \(failures)" : t("ready")
    }
    private var customAlbumArtwork: [String: URL] {
        tracks.reduce(into: [:]) { covers, track in
            if let url = track.albumArtworkURL { covers[AlbumIdentity.key(track)] = url }
        }
    }

    func setAlbumArtwork(_ image: URL?, for trackID: String) async {
        guard !saveBlocked, let seed = track(for: trackID) else { return }
        let album = AlbumIdentity.key(seed)
        do {
            var asset: URL?
            if let image {
                guard let imported = try await persistence.importAlbumArtwork(from: image) else {
                    error = t("albumArtworkInvalid")
                    return
                }
                asset = imported
            }
            guard let current = track(for: trackID), AlbumIdentity.key(current) == album else { return }
            tracks = tracks.map { track in
                guard AlbumIdentity.key(track) == album else { return track }
                var updated = track
                updated.albumArtworkURL = asset
                return updated
            }
            save()
            try await persistence.flush()
            updateNowPlaying()
            postFeedback(image == nil ? "albumArtworkRestored" : "albumArtworkSaved", detail: displayAlbum(seed.album))
        } catch { self.error = error.localizedDescription }
    }

    private func upsertTracks(_ values: [Track]) {
        let covers = customAlbumArtwork
        var updated = tracks
        var indices = Dictionary(updated.indices.map { (updated[$0].id, $0) }, uniquingKeysWith: { _, last in last })
        let importedAt = Date()
        for var track in values {
            if let index = indices[track.id] {
                let old = updated[index]
                track.favorite = old.favorite
                track.lastPlayed = old.lastPlayed
                track.playCount = old.playCount
                track.addedAt = old.addedAt
                track.hiddenDuplicate = old.hiddenDuplicate
                if let correction = tagEdits[old.id] { track = correction.applying(to: track) }
                if !track.hasArtwork {
                    track.artworkURL = old.artworkURL
                    track.artworkCredit = old.artworkCredit
                }
                if !track.hasLyrics {
                    track.lyrics = old.lyrics
                    track.lyricsCredit = old.lyricsCredit
                }
                track.albumArtworkURL = covers[AlbumIdentity.key(track)]
                updated[index] = track
            } else {
                indices[track.id] = updated.count
                track.addedAt = importedAt
                track.albumArtworkURL = covers[AlbumIdentity.key(track)]
                updated.append(track)
            }
        }
        tracks = updated
    }
    func removeSource(_ source: MusicSource) {
        guard !scanning, !writingFileTags, !relocatingSource else { return }
        if let id = loadingTrackID, SourceScanner.isWithin(URL(fileURLWithPath: id), source: source.url) {
            cancelPlaybackLoad()
        }
        sources.removeAll { $0.id == source.id }
        let prefix = source.url.path.hasSuffix("/") ? source.url.path : source.url.path + "/"
        tracks.removeAll { track in
            (track.url == source.url || track.url.path.hasPrefix(prefix))
                && !sources.contains { SourceScanner.isWithin(track.url, source: $0.url) }
        }
        sourceStates.removeValue(forKey: source.id)
        if let id = currentID, !tracks.contains(where: { $0.id == id }) {
            player?.stop()
            currentID = nil
            isPlaying = false
            position = 0
            updateActivity()
            updateNowPlaying()
        }
        save()
    }
    func update(_ track: Track) {
        guard let current = self.track(for: track.id) else { return }
        let changes = Dictionary(
            uniqueKeysWithValues: TagField.allCases.compactMap { field -> (TagField, String)? in
                let value = field.value(in: track).trimmingCharacters(in: .whitespacesAndNewlines)
                return value != field.value(in: current) ? (field, value) : nil
            })
        applyTagEdits(ids: [track.id], changes: changes)
        if track.duration.isFinite, track.duration > 0, track.duration != current.duration,
            let index = tracks.firstIndex(where: { $0.id == track.id })
        {
            tracks[index].duration = track.duration
            save()
        }
    }
    func applyTagEdits(
        ids: [String], changes: [TagField: String], numberingFrom: Int? = nil, carryAlbumArtwork: Bool = false
    ) {
        guard !saveBlocked, !writingFileTags, !changes.isEmpty || numberingFrom != nil,
            changes.allSatisfy({ $0.key.isValid($0.value) }),
            numberingFrom.map({ $0 > 0 && $0 <= 9999 && ids.count <= 10000 - $0 }) ?? true
        else { return }
        var updated = tracks
        let indices = Dictionary(tracks.indices.map { (tracks[$0].id, $0) }, uniquingKeysWith: { _, last in last })
        let covers = customAlbumArtwork
        let existingAlbums = carryAlbumArtwork ? Set(tracks.map(AlbumIdentity.key)) : []
        var batch: [TagUndo] = []
        var seen = Set<String>()
        for (offset, id) in ids.enumerated() where seen.insert(id).inserted {
            guard let index = indices[id] else { continue }
            let old = updated[index]
            var edit = tagEdits[id] ?? TrackTagEdits()
            for (field, value) in changes where field.value(in: old) != value {
                edit.values[field.rawValue] = value.trimmingCharacters(in: .whitespacesAndNewlines)
            }
            if let start = numberingFrom { edit.values[TagField.trackNumber.rawValue] = String(start + offset) }
            var after = edit.applying(to: old)
            let destination = AlbumIdentity.key(after)
            var carriedArtwork = false
            if destination != AlbumIdentity.key(old) {
                carriedArtwork =
                    carryAlbumArtwork && !existingAlbums.contains(destination) && old.albumArtworkURL != nil
                after.albumArtworkURL = carriedArtwork ? old.albumArtworkURL : covers[destination]
            }
            guard after != old else { continue }
            batch.append(
                .init(
                    before: old, after: after, previous: tagEdits[id], applied: edit,
                    carriedAlbumArtwork: carriedArtwork))
            updated[index] = after
            tagEdits[id] = edit
            edited.insert(id)
        }
        guard !batch.isEmpty else { return }
        tagUndo = batch
        canUndoTagEdits = true
        tracks = updated
        save()
        updateNowPlaying()
        postFeedback("tagsSaved", detail: songCountText(batch.count))
    }
    func undoTagEdits() {
        guard !scanning, !writingFileTags, !saveBlocked, !tagUndo.isEmpty else { return }
        // Compare only tags so playback statistics and favorites remain live.
        guard
            tagUndo.allSatisfy({ item in
                guard let current = track(for: item.before.id), tagEdits[item.before.id] == item.applied else {
                    return false
                }
                return TagField.allCases.allSatisfy { $0.value(in: current) == $0.value(in: item.after) }
            })
        else {
            tagUndo = []
            canUndoTagEdits = false
            return
        }
        var updated = tracks
        let covers = customAlbumArtwork
        let before = Dictionary(uniqueKeysWithValues: tagUndo.map { ($0.before.id, $0) })
        for index in updated.indices {
            guard let item = before[updated[index].id] else { continue }
            let album = AlbumIdentity.key(updated[index])
            for field in TagField.allCases { field.set(field.value(in: item.before), in: &updated[index]) }
            if AlbumIdentity.key(updated[index]) != album {
                updated[index].albumArtworkURL =
                    covers[AlbumIdentity.key(updated[index])]
                    ?? (item.carriedAlbumArtwork ? updated[index].albumArtworkURL : nil)
            }
            tagEdits[item.before.id] = item.previous
            if item.previous == nil { edited.remove(item.before.id) }
        }
        tracks = updated
        tagUndo = []
        canUndoTagEdits = false
        save()
        updateNowPlaying()
    }
    func canWriteFileTags(_ track: Track) -> Bool {
        track.format == "FLAC" && !track.isDemo && track.url.isFileURL
    }

    /// Each replacement is atomic. A failed file leaves that file intact and does not stop the other tracks.
    func writeFileTags(ids: [String], changes: [TagField: String], numberingFrom: Int? = nil) async -> String? {
        guard !scanning, !relocatingSource, !quitting, !saveBlocked, !writingFileTags else {
            return t("fileTagsBusy")
        }
        guard changes.allSatisfy({ $0.key.isValid($0.value) }),
            numberingFrom.map({ $0 > 0 && $0 <= 9999 && ids.count <= 10000 - $0 }) ?? true
        else { return t("tagValidation") }
        let selected = ids.compactMap { track(for: $0) }
        guard !selected.isEmpty, selected.count == ids.count, selected.allSatisfy(canWriteFileTags) else {
            return t("fileTagsFLACOnly")
        }
        writingFileTags = true
        defer { writingFileTags = false }
        var refreshed: [Track] = []
        var failures = 0
        var firstFailure: String?
        for (index, track) in selected.enumerated() {
            var tags = changes.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if let start = numberingFrom { tags[.trackNumber] = String(start + index) }
            guard !tags.isEmpty else { continue }
            let request = tags
            do {
                var result = try await Task.detached(priority: .utility) {
                    try FLACTagWriter.write(request, to: track.url)
                }.value
                result.artwork = nil
                result.sourceIsNetwork = track.sourceIsNetwork
                var remaining = tagEdits[track.id]?.values ?? [:]
                for field in tags.keys { remaining[field.rawValue] = nil }
                if remaining.isEmpty {
                    tagEdits[track.id] = nil
                    edited.remove(track.id)
                } else {
                    tagEdits[track.id] = TrackTagEdits(values: remaining)
                }
                refreshed.append(result)
            } catch {
                failures += 1
                if firstFailure == nil {
                    let reason: String
                    if let space = error as? FLACTagWriter.InsufficientSpace {
                        let needed = ByteCountFormatter.string(fromByteCount: space.required, countStyle: .file)
                        if let available = space.available, available < space.required {
                            let free = ByteCountFormatter.string(fromByteCount: available, countStyle: .file)
                            reason = String(format: t("fileTagsNotEnoughSpace"), free, needed)
                        } else {
                            reason = String(format: t("fileTagsStorageFull"), needed)
                        }
                    } else {
                        reason = error.localizedDescription
                    }
                    firstFailure = track.url.lastPathComponent + " — " + reason
                }
            }
        }
        if !refreshed.isEmpty {
            upsertTracks(refreshed)
            tagUndo = []
            canUndoTagEdits = false
            save()
            updateNowPlaying()
            do { try await persistence.flush() } catch {
                return t("fileTagsRefreshFailed") + " " + error.localizedDescription
            }
            postFeedback("fileTagsSaved", detail: songCountText(refreshed.count))
        }
        if let firstFailure {
            return "\(t("fileTagsSaved")): \(refreshed.count) · \(t("failedFiles")): \(failures)\n\(firstFailure)"
        }
        return nil
    }

    func locallyEditedFields(for track: Track) -> [TagField] {
        guard let values = tagEdits[track.id]?.values else { return [] }
        return TagField.allCases.filter { values[$0.rawValue] != nil }
    }

    func restoreFileTags(_ track: Track) async throws {
        guard !scanning, !writingFileTags, !saveBlocked else { return }
        let expected = tagEdits[track.id]
        let original = try await Task.detached(priority: .utility) { try await MetadataReader.read(track.url) }.value
        guard !scanning, tagEdits[track.id] == expected, self.track(for: track.id) != nil else { return }
        tagEdits[track.id] = nil
        edited.remove(track.id)
        upsertTracks([original])
        tagUndo = []
        canUndoTagEdits = false
        save()
        updateNowPlaying()
    }
    func favorite(_ track: Track) {
        guard let i = tracks.firstIndex(where: { $0.id == track.id }) else { return }
        let old = tracks[i].favorite
        tracks[i].favorite.toggle()
        save()
        postFeedback(
            old ? "favoriteRemoved" : "favoriteAdded", detail: track.title, icon: old ? "heart" : "heart.fill",
            undo: .favorite(track.id, old))
    }
    func postFeedback(_ key: String, detail: String = "", icon: String = "checkmark", undo: FeedbackUndo? = nil) {
        guard preferences.showFeedback else { return }
        feedbackTask?.cancel()
        let notice = FeedbackNotice(title: t(key), detail: detail, icon: icon, undo: undo)
        feedback = notice
        feedbackTask = Task { [weak self] in
            do { try await Task.sleep(nanoseconds: 3_800_000_000) } catch { return }
            guard let self, self.feedback?.id == notice.id else { return }
            self.feedback = nil
        }
    }
    func dismissFeedback(id: UUID? = nil) {
        guard id == nil || feedback?.id == id else { return }
        feedbackTask?.cancel()
        feedback = nil
    }
    func undoFeedback(id: UUID? = nil) {
        guard id == nil || feedback?.id == id else { return }
        guard let undo = feedback?.undo else { return }
        switch undo {
        case .favorite(let id, let value):
            if let i = tracks.firstIndex(where: { $0.id == id }) {
                tracks[i].favorite = value
                save()
            }
        case .queue(let previous):
            let currentIndex = currentID.flatMap { queue.firstIndex(of: $0) } ?? 0
            var restored = previous.filter { track(for: $0) != nil }
            if let currentID, !restored.contains(currentID), tracks.contains(where: { $0.id == currentID }) {
                restored.insert(currentID, at: min(currentIndex, restored.count))
            }
            queue = restored
        case .playlistAddition(let id, let track):
            if let i = playlists.firstIndex(where: { $0.id == id }) {
                playlists[i].trackIDs.removeAll { $0 == track }
                save()
            }
        case .playlistRemoval(let playlist, let index):
            if !playlists.contains(where: { $0.id == playlist.id }) {
                playlists.insert(playlist, at: min(index, playlists.count))
                save()
            }
        }
        postFeedback("undone", icon: "arrow.uturn.backward")
    }
    var directOutputActive: Bool { preferences.directOutput && !usingAirPlay }
    var effectiveVolume: Float { directOutputActive ? 1 : volume }
    var outputVolume: Binding<Float> {
        Binding(get: { self.effectiveVolume }, set: { if !self.directOutputActive { self.volume = $0 } })
    }
    func selectOutput(_ uid: String) {
        if usingAirPlay {
            usingAirPlay = false
            let previous = preferences.outputDeviceUID
            preferences.outputDeviceUID = uid
            if previous == uid { restartOutput() }
        } else if preferences.outputDeviceUID != uid {
            preferences.outputDeviceUID = uid
        }
    }
    func enableAirPlay() {
        guard !usingAirPlay else { return }
        usingAirPlay = true
        restartOutput()
    }
    func useLocalOutput() {
        guard usingAirPlay else { return }
        usingAirPlay = false
        restartOutput()
    }
    private func restartOutput() {
        let resume = isPlaying || outputResumeIntent || playbackLoading
        let pending = loadingTrackID
        let time = pending != nil && pending != currentID ? 0 : position
        let track = pending.flatMap { self.track(for: $0) } ?? current
        cancelPlaybackLoad()
        outputResumeIntent = resume
        player?.stop()
        player = nil
        isPlaying = false
        preparedOutput = nil
        playbackBuffering = false
        let token = playbackRequest
        if resume { loadingTrackID = track?.id }
        playbackLoadTask = Task { [weak self] in
            guard let self else { return }
            await self.outputController.release()
            guard !Task.isCancelled, self.playbackRequest == token else { return }
            self.outputResumeIntent = false
            self.loadingTrackID = nil
            self.playbackLoadTask = nil
            if resume, let track {
                self.play(track, from: time)
            } else if self.usingAirPlay, let track {
                do {
                    let audio = try self.makePlayer(track, file: nil, output: nil)
                    audio.currentTime = time
                    self.player = audio
                } catch { self.error = error.localizedDescription }
            }
            self.updateNowPlaying()
            self.updateActivity()
        }
    }
    func playAlbum(_ seed: Track, shuffled: Bool = false) {
        cancelPlaybackLoad()
        let token = playbackRequest
        preparingAlbumID = seed.id
        albumPlayTask = Task { [weak self] in
            defer {
                if let self, self.playbackRequest == token {
                    self.albumPlayTask = nil
                    self.preparingAlbumID = nil
                }
            }
            guard let self else { return }
            await self.readAlbumOrder(seed.id)
            guard !Task.isCancelled, self.playbackRequest == token, let album = self.albumCollection(seed.id),
                !album.tracks.isEmpty
            else { return }
            self.albumPlayTask = nil
            self.preparingAlbumID = nil
            self.shuffle = shuffled
            if let first = shuffled ? album.tracks.randomElement() : album.tracks.first {
                self.play(first, in: album.tracks)
            }
        }
    }
    var playbackLoading: Bool { loadingTrackID != nil || preparingAlbumID != nil }
    var playbackControlLabel: String { t(playbackLoading ? "cancelAudioLoad" : isPlaying ? "pause" : "play") }
    func waitForPlaybackLoad() async {
        await albumPlayTask?.value
        await playbackLoadTask?.value
    }
    private func cancelPlaybackLoad() {
        outputResumeIntent = false
        albumPlayTask?.cancel()
        albumPlayTask = nil
        preparingAlbumID = nil
        playbackRequest = UUID()
        playbackLoadTask?.cancel()
        playbackLoadTask = nil
        loadingTrackID = nil
        cancelSuccessor()
        (player as? AudioPlayback)?.clearSuccessor()
        if nasRetry != nil { nasRetry = nil }
    }
    func play(_ track: Track, in list: [Track]? = nil, from start: Double = 0) {
        if let list {
            queue = shuffle ? [track.id] + list.filter { $0.id != track.id }.map(\.id).shuffled() : list.map(\.id)
        }
        if queue.isEmpty { queue = filtered.map(\.id) }
        cancelPlaybackLoad()
        let token = playbackRequest
        loadingTrackID = track.id
        nasRetry = nil
        let opener = openAudioFile
        playbackLoadTask = Task { [weak self] in
            defer {
                if let self, self.playbackRequest == token {
                    self.loadingTrackID = nil
                    self.playbackLoadTask = nil
                }
            }
            do {
                guard let self else { return }
                let airPlay = self.usingAirPlay
                let opened = airPlay ? nil : try await opener(track.url)
                let readsGain = !airPlay && !self.directOutputActive && self.preferences.replayGain != .off
                let gain = readsGain ? await Self.readReplayGain(track) : nil
                try Task.checkCancellation()
                guard self.playbackRequest == token, !self.quitting, self.track(for: track.id) != nil else { return }
                let previous = self.player
                previous?.pause()
                self.isPlaying = false
                var output: OutputPreparation?
                if !airPlay, let opened {
                    if self.outputs.devices.isEmpty && !self.outputs.refreshing { self.outputs.refresh() }
                    await self.outputs.waitForRefresh()
                    let selected = self.outputs.device(uid: self.preferences.outputDeviceUID)
                    let fallback = self.directOutputActive ? nil : self.outputs.device(uid: "")
                    guard let device = selected ?? fallback else {
                        throw NSError(
                            domain: "PrismaOutput", code: 3,
                            userInfo: [NSLocalizedDescriptionKey: self.t("outputUnavailable")])
                    }
                    if self.directOutputActive, Int(opened.file.processingFormat.channelCount) > device.channels {
                        throw NSError(
                            domain: "PrismaOutput", code: 4, userInfo: [NSLocalizedDescriptionKey: "channelMismatch"])
                    }
                    output = try await self.outputController.prepare(
                        device, direct: self.directOutputActive, exclusive: self.preferences.exclusiveOutput,
                        rate: opened.file.processingFormat.sampleRate)
                    if selected == nil { self.status = self.t("outputFallback") }
                }
                try Task.checkCancellation()
                guard self.playbackRequest == token else { return }
                let audio = try self.makePlayer(track, file: opened?.file, output: output, gain: gain)
                audio.currentTime = start.isFinite ? max(0, start) : 0
                guard audio.play() else {
                    throw NSError(
                        domain: "Prisma", code: 2, userInfo: [NSLocalizedDescriptionKey: self.t("audioLoadFailed")])
                }
                self.preparedOutput = output
                previous?.stop()
                self.player = audio
                self.gainTask?.cancel()
                self.gainTask = nil
                self.currentID = track.id
                self.isPlaying = true
                self.position = airPlay ? min(track.duration, max(0, start.isFinite ? start : 0)) : audio.currentTime
                self.loadingTrackID = nil
                self.playbackLoadTask = nil
                self.didStartTrack(track)
                if !readsGain { self.updateReplayGain() }
            } catch {
                guard let self, self.playbackRequest == token, !Task.isCancelled else { return }
                let unavailable = await Task.detached(priority: .utility) {
                    track.sourceIsNetwork == true && !FileManager.default.isReadableFile(atPath: track.id)
                }.value
                guard self.playbackRequest == token, !Task.isCancelled else { return }
                if unavailable, let retry = self.reconnectRequest(for: track, position: start) {
                    self.sourceStates[retry.sourceID] = "offline"
                    self.nasRetry = retry
                } else {
                    self.error = "\(self.t("audioLoadFailed")) · \(track.title)\n\(self.t(error.localizedDescription))"
                }
                self.updateActivity()
                self.updateNowPlaying()
            }
        }
    }
    func togglePlay() {
        if playbackLoading {
            cancelPlaybackLoad()
            return
        }
        guard let player else {
            if let first = current ?? queuedTracks.first ?? filtered.first {
                play(first, in: queue.isEmpty ? filtered : nil, from: currentID == first.id ? position : 0)
            }
            return
        }
        if isPlaying {
            cancelSuccessor()
            player.pause()
            isPlaying = false
        } else {
            isPlaying = player.play()
        }
        updateNowPlaying()
        updateActivity()
        rememberPlayback()
    }
    func seek(_ seconds: Double) {
        guard seconds.isFinite else { return }
        cancelPlaybackLoad()
        let target = min(max(0, seconds), player?.duration ?? current?.duration ?? 0)
        if let player {
            player.currentTime = target
            position = player.currentTime
        } else {
            position = target
        }
        updateNowPlaying()
        rememberPlayback()
    }
    func next(back: Bool = false, automatic: Bool = false) {
        guard !tracks.isEmpty else { return }
        if automatic && (stopAfterCurrent || !preferences.continueQueue) {
            stopAfterCurrent = false
            pausePlayback()
            return
        }
        if back && !playbackLoading && position > 3 {
            seek(0)
            return
        }
        let selected = loadingTrackID ?? currentID
        let step = back ? -1 : 1
        if !automatic || repeatMode != 2, let selected, track(for: selected) != nil,
            let index = queueIndex(selected), queue.indices.contains(index + step),
            let adjacentTrack = track(for: queue[index + step])
        {
            play(adjacentTrack)
            return
        }
        let list = queue.compactMap { track(for: $0) }
        guard !list.isEmpty else { return }
        if automatic && repeatMode == 2, let current {
            play(current)
            return
        }
        let i = list.firstIndex { $0.id == selected } ?? -1
        let nextIndex = i + step
        if nextIndex >= list.count && automatic && repeatMode == 0 {
            isPlaying = false
            position = min(current?.duration ?? player?.duration ?? 0, player?.duration ?? 0)
            player?.pause()
            updateNowPlaying()
            updateActivity()
            rememberPlayback()
            return
        }
        play(list[(nextIndex + list.count) % list.count])
    }
    private func tick() {
        if let deadline = sleepDeadline {
            let remaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if remaining != sleepRemaining { sleepRemaining = remaining }
            if deadline <= Date() {
                sleepDeadline = nil
                pausePlayback()
            }
        }
        let targetEnergy = isPlaying ? min(1, pow(max(0, level), 0.55) * 1.8) : 0
        let energy = ambientEnergy + (targetEnergy - ambientEnergy) * (targetEnergy > ambientEnergy ? 0.20 : 0.075)
        if abs(energy - ambientEnergy) > 0.0005 {
            ambientEnergy = energy
        } else if targetEnergy == 0 && ambientEnergy != 0 {
            ambientEnergy = 0
        }
        guard let player else { return }
        if let audio = player as? AudioPlayback { prepareSuccessor(for: audio) }
        if spectrumActive {
            let bands = isPlaying ? ((player as? AudioPlayback)?.spectrum ?? []) : []
            if bands != visualizerBands { visualizerBands = bands }
        }
        if playbackBuffering != player.isBuffering { playbackBuffering = player.isBuffering }
        let time = min(current?.duration ?? player.duration, player.currentTime)
        if abs(time - position) >= 0.09 || position > (current?.duration ?? player.duration) { position = time }
        if isPlaying {
            let meters = player.levels
            level = Double(meters.rms)
            peak = Double(meters.peak)
        } else {
            if level != 0 { level = level < 0.0001 ? 0 : level * 0.85 }
            if peak != 0 { peak = peak < 0.0001 ? 0 : peak * 0.85 }
        }
        if isPlaying, lastPlaybackCheckpoint.duration(to: .now) >= .seconds(5) {
            rememberPlayback()
            storeQueue()
        }
    }
    private func makePlayer(
        _ track: Track, file: AVAudioFile?, output: OutputPreparation?, gain: ReplayGain? = nil
    ) throws -> any MusicPlayback
    {
        let audio: any MusicPlayback
        if usingAirPlay {
            audio = AirPlayPlayback(player: airPlayPlayer, track: track)
        } else if let file {
            let local = try AudioPlayback(file: file, output: output, replayGain: gain)
            local.setSpectrumEnabled(spectrumActive)
            audio = local
        } else {
            throw URLError(.cannotOpenFile)
        }
        audio.volume = volume
        audio.apply(preferences)
        audio.onFinish = { [weak self, weak audio] in
            guard let self, let audio, self.player === audio else { return }
            self.playbackDidFinish()
        }
        audio.onError = { [weak self, weak audio] error in
            guard let self, let audio, self.player === audio else { return }
            let track = self.current ?? track
            self.isPlaying = false
            self.position = audio.currentTime
            if self.directOutputActive {
                audio.stop()
                self.player = nil
                self.preparedOutput = nil
            }
            self.updateActivity()
            self.updateNowPlaying()
            let message = self.t(error.localizedDescription)
            guard !self.playbackLoading,
                let retry = self.reconnectRequest(for: track, position: self.position)
            else {
                self.error = message
                return
            }
            Task { [weak self] in
                let readable = await Task.detached(priority: .utility) {
                    FileManager.default.isReadableFile(atPath: track.id)
                }.value
                guard let self, self.playbackRequest == retry.request,
                    self.currentID == retry.trackID, !self.isPlaying, self.nasRetry == nil
                else { return }
                if readable {
                    self.error = message
                } else {
                    self.offerPlaybackRecovery(retry)
                }
            }
        }
        return audio
    }
    func playbackDidFinish() {
        cancelSuccessor()
        isPlaying = false
        position = player?.duration ?? current?.duration ?? position
        updateActivity()
        updateNowPlaying()
        rememberPlayback()
        if !playbackLoading { next(automatic: true) }
    }
    private func didStartTrack(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            var updated = tracks[i]
            updated.lastPlayed = Date()
            updated.playCount = (updated.playCount ?? 0) + 1
            tracks[i] = updated
            save()
        }
        updateActivity()
        updateNowPlaying()
        rememberPlayback()
        if online && !track.isDemo && !attempted.contains(track.id) && (!track.hasLyrics || !track.hasArtwork) {
            attempted.insert(track.id)
            enrichmentTask?.cancel()
            enrichmentTask = Task { await enrich(track) }
        }
    }
    private func updateReplayGain() {
        gainTask?.cancel()
        gainTask = nil
        guard preferences.replayGain != .off, let track = current, track.codecLabel == "FLAC",
            let audio = player as? AudioPlayback, !audio.direct
        else { return }
        gainTask = Task { [weak self, weak audio] in
            let gain = await Self.readReplayGain(track)
            guard let self, let audio, !Task.isCancelled, self.player === audio, self.currentID == track.id else {
                return
            }
            self.cancelSuccessor()
            audio.clearSuccessor()
            audio.setReplayGain(gain)
            self.refreshAppliedReplayGain()
            self.gainTask = nil
        }
    }
    private func refreshAppliedReplayGain() {
        let gain = player.map { ($0 as? AudioPlayback)?.appliedReplayGain ?? 0 }
        if gain != appliedReplayGain { appliedReplayGain = gain }
    }
    private nonisolated static func readReplayGain(_ track: Track) async -> ReplayGain? {
        guard track.codecLabel == "FLAC" else { return nil }
        return await Task.detached(priority: .utility) {
            try? NativeFLACMetadata.replayGain(track.url)
        }.value
    }
    private func successorTrack() -> Track? {
        guard !stopAfterCurrent, preferences.continueQueue, preferences.gaplessPlayback, let current else { return nil }
        if repeatMode == 2 { return current }
        if let index = queueIndex(current.id) {
            for id in queue.dropFirst(index + 1) {
                if let track = track(for: id) { return track }
            }
        }
        if repeatMode == 1 { return queue.lazy.compactMap { self.track(for: $0) }.first }
        return nil
    }
    private func cancelSuccessor() {
        successorTask?.cancel()
        successorTask = nil
        successorAttempt = nil
    }
    private func verifySuccessor() {
        guard successorAttempt != nil || (player as? AudioPlayback)?.queuedSuccessorID != nil else { return }
        let nextID = successorTrack()?.id
        if successorAttempt != nextID { cancelSuccessor() }
        if let audio = player as? AudioPlayback, let pending = audio.queuedSuccessorID, pending != nextID {
            audio.clearSuccessor()
        }
    }
    private func prepareSuccessor(for audio: AudioPlayback) {
        guard isPlaying, !playbackLoading, !quitting, gainTask == nil, successorTask == nil,
            audio.queuedSuccessorID == nil, audio.duration - audio.currentTime <= 12,
            let currentID, let track = successorTrack(), successorAttempt != track.id
        else { return }
        successorAttempt = track.id
        let request = playbackRequest
        let loader = successorLoader
        let normalize = preferences.replayGain != .off && !audio.direct
        successorTask = Task { [weak self, weak audio] in
            defer {
                if !Task.isCancelled { self?.successorTask = nil }
            }
            guard let opened = try? await loader.open(track.url) else { return }
            let gain = normalize ? await Self.readReplayGain(track) : nil
            guard let self, let audio, !Task.isCancelled, self.playbackRequest == request, self.currentID == currentID,
                self.player === audio, self.isPlaying, self.successorTrack()?.id == track.id
            else { return }
            audio.scheduleSuccessor(id: track.id, file: opened.file, gain: gain) { [weak self, weak audio] id in
                guard let self, let audio, self.player === audio, let next = self.track(for: id) else { return }
                self.cancelSuccessor()
                self.currentID = id
                self.position = audio.currentTime
                self.didStartTrack(next)
            }
        }
    }
    func pausePlayback() {
        outputResumeIntent = false
        cancelPlaybackLoad()
        playbackBuffering = false
        player?.pause()
        isPlaying = false
        updateNowPlaying()
        updateActivity()
        rememberPlayback()
    }
    private struct PlaybackBookmark: Codable {
        var id: String
        var position: Double
    }
    private func rememberPlayback() {
        lastPlaybackCheckpoint = .now
        guard !saveBlocked, preferences.rememberPosition, let currentID else { return }
        do {
            persistence.writeSmallFile(
                "playback.json", data: try JSONEncoder().encode(PlaybackBookmark(id: currentID, position: position)))
        } catch { status = error.localizedDescription }
    }
    private func preferencesChanged(previous: ListeningPreferences) {
        if previous.outputDeviceUID != preferences.outputDeviceUID || previous.directOutput != preferences.directOutput
            || previous.exclusiveOutput != preferences.exclusiveOutput
        {
            restartOutput()
        }
        if !preferences.showFeedback { dismissFeedback() }
        if previous.replayGain != preferences.replayGain || previous.eqEnabled != preferences.eqEnabled
            || previous.eqGains != preferences.eqGains || previous.effectivePreamp != preferences.effectivePreamp
        {
            cancelSuccessor()
            (player as? AudioPlayback)?.clearSuccessor()
        }
        player?.apply(preferences)
        refreshAppliedReplayGain()
        if previous.continueQueue != preferences.continueQueue || previous.gaplessPlayback != preferences.gaplessPlayback {
            verifySuccessor()
        }
        if previous.replayGain != preferences.replayGain { updateReplayGain() }
        updateActivity()
        configureMiniPlayer()
        do { persistence.writeSmallFile("preferences.json", data: try JSONEncoder().encode(preferences)) } catch {
            self.error = error.localizedDescription
        }
    }
    private func updateActivity() {
        if isPlaying && preferences.keepAwake {
            if activity == nil {
                activity = ProcessInfo.processInfo.beginActivity(
                    options: [.idleSystemSleepDisabled], reason: "Prisma Music playback")
            }
        } else if let activity {
            ProcessInfo.processInfo.endActivity(activity)
            self.activity = nil
        }
    }
    func setSleepTimer(minutes: Int?) {
        sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }
        sleepRemaining = (minutes ?? 0) * 60
    }
    func openSettings(_ page: String = "sound") {
        settingsPage = page
        showSettings = true
    }
    var activePlaylist: Playlist? {
        guard section.hasPrefix("playlist:"), let id = UUID(uuidString: String(section.dropFirst(9))) else {
            return nil
        }
        return playlists.first { $0.id == id }
    }
    func saveManualPlaylist(_ name: String, ids: [String], replacing id: UUID? = nil, navigate: Bool = true) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var seen = Set<String>()
        let ids = ids.filter { seen.insert($0).inserted }
        if let id {
            guard let index = playlists.firstIndex(where: { $0.id == id && $0.rules == nil }) else { return }
            playlists[index].name = name
            playlists[index].trackIDs = ids
        } else {
            let playlist = Playlist(name: name, trackIDs: ids)
            playlists.append(playlist)
            if navigate { navigateTo("playlist:\(playlist.id)") }
        }
        save()
    }
    func setDuplicateVisibility(_ ids: Set<String>, hidden: Bool, in group: [Track]) {
        guard !ids.isEmpty else { return }
        let candidates = Set(group.map(\.id))
        if hidden {
            guard tracks.contains(where: {
                candidates.contains($0.id) && !ids.contains($0.id) && $0.hiddenDuplicate != true
            }) else { return }
        }
        let affected = ids.intersection(candidates)
        tracks = tracks.map { track in
            guard affected.contains(track.id) else { return track }
            var updated = track
            updated.hiddenDuplicate = hidden ? true : nil
            return updated
        }
        save()
    }
    func createPlaylist(_ name: String, rules: SmartPlaylistRules? = nil, replacing id: UUID? = nil) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, rules?.isEmpty != true else { return }
        if let id {
            guard let index = playlists.firstIndex(where: { $0.id == id }), playlists[index].rules != nil,
                let rules
            else { return }
            playlists[index].name = name
            playlists[index].rules = rules
        } else {
            let playlist = Playlist(name: name, rules: rules)
            playlists.append(playlist)
            if rules != nil { navigateTo("playlist:\(playlist.id)") }
        }
        save()
        postFeedback("playlistCreated", detail: name, icon: "music.note.list")
    }
    func add(_ track: Track, to playlist: Playlist) {
        if let i = playlists.firstIndex(where: { $0.id == playlist.id }), playlists[i].rules == nil,
            !playlists[i].trackIDs.contains(track.id)
        {
            playlists[i].trackIDs.append(track.id)
            save()
            postFeedback(
                "playlistAdded", detail: playlist.name, icon: "text.badge.plus",
                undo: .playlistAddition(playlist.id, track.id))
        }
    }
    func removePlaylist(_ playlist: Playlist) {
        guard let index = playlists.firstIndex(where: { $0.id == playlist.id }) else { return }
        playlists.removeAll { $0.id == playlist.id }
        if section == "playlist:\(playlist.id)" { section = "home" }
        save()
        postFeedback("playlistDeleted", detail: playlist.name, icon: "trash", undo: .playlistRemoval(playlist, index))
    }
    func duplicatePlaylist(_ playlist: Playlist) {
        let name = playlist.name + " · " + t("playlistCopy")
        let copy = Playlist(name: name, trackIDs: playlist.trackIDs, rules: playlist.rules)
        playlists.append(copy)
        save()
        navigateTo("playlist:\(copy.id)")
    }
    func tracks(in playlist: Playlist) -> [Track] {
        if let rules = playlist.rules { return rules.filter(tracksInCurrentOrder).filter { $0.hiddenDuplicate != true } }
        return playlist.trackIDs.compactMap { track(for: $0) }
    }
    func removeFromPlaylist(_ track: Track) {
        if let i = playlists.firstIndex(where: { section == "playlist:\($0.id)" && $0.rules == nil }) {
            playlists[i].trackIDs.removeAll { $0 == track.id }
            save()
        }
    }
    func enqueue(_ track: Track, next: Bool = false) {
        guard track.id != currentID else { return }
        let previous = queue
        var updated = queue.filter { $0 != track.id }
        if next {
            if let currentID, self.track(for: currentID) != nil {
                let currentIndex: Int
                if let index = updated.firstIndex(of: currentID) {
                    currentIndex = index
                } else {
                    updated.insert(currentID, at: 0)
                    currentIndex = 0
                }
                updated.insert(track.id, at: currentIndex + 1)
            } else {
                updated.insert(track.id, at: 0)
            }
        } else {
            updated.append(track.id)
        }
        queue = updated
        postFeedback(next ? "queuedNext" : "queued", detail: track.title, icon: "list.bullet", undo: .queue(previous))
    }
    func removeQueued(_ track: Track) {
        removeQueued(ids: [track.id])
    }
    var upcomingIDs: [String] {
        if let cachedUpcoming, cachedUpcoming.revision == revision, cachedUpcoming.currentID == currentID {
            return cachedUpcoming.ids
        }
        let start = currentID.flatMap { queueIndex($0) }.map { $0 + 1 } ?? 0
        let ids = queue.dropFirst(start).filter { track(for: $0) != nil }
        cachedUpcoming = (revision, currentID, ids)
        return ids
    }
    func removeQueued(ids: Set<String>) {
        let removable = ids.intersection(upcomingIDs)
        guard !removable.isEmpty else { return }
        let previous = queue
        queue.removeAll { removable.contains($0) }
        postFeedback("queueRemoved", detail: songCountText(removable.count), icon: "minus.circle", undo: .queue(previous))
    }
    @discardableResult
    func moveUpcoming(_ ids: Set<String>, before destination: String?) -> Bool {
        let upcoming = upcomingIDs
        let moving = upcoming.filter { ids.contains($0) }
        guard !moving.isEmpty, moving.count == ids.count,
            destination.map({ upcoming.contains($0) && !ids.contains($0) }) ?? true
        else { return false }
        var reordered = queue.filter { !ids.contains($0) }
        let offset = destination.flatMap { reordered.firstIndex(of: $0) } ?? reordered.count
        reordered.insert(contentsOf: moving, at: offset)
        guard reordered != queue else { return false }
        let previous = queue
        queue = reordered
        postFeedback("queueReordered", detail: songCountText(moving.count), icon: "arrow.up.arrow.down",
                     undo: .queue(previous))
        return true
    }
    @discardableResult
    func saveUpcomingPlaylist(_ name: String) -> Bool {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let ids = upcomingIDs
        guard !name.isEmpty, !ids.isEmpty, !saveBlocked else { return false }
        saveManualPlaylist(name, ids: ids, navigate: false)
        postFeedback("playlistCreated", detail: name, icon: "music.note.list")
        return true
    }
    func moveQueued(_ track: Track, direction: Int) {
        guard let index = queue.firstIndex(of: track.id), queue.indices.contains(index + direction) else { return }
        queue.swapAt(index, index + direction)
    }
    func exportPlaylist(_ selection: [Track]? = nil) {
        let list = selection ?? (section == "home" ? tracks : filtered)
        guard !list.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.nameFieldStringValue = "Prisma Music.m3u8"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let body =
                "#EXTM3U\n"
                + list.map { "#EXTINF:\(Int($0.duration)),\($0.artist) - \($0.title)\n\($0.url.path)" }.joined(
                    separator: "\n") + "\n"
            do { try body.write(to: url, atomically: true, encoding: .utf8) } catch {
                Task { @MainActor in self?.error = error.localizedDescription }
            }
        }
    }
    func exportLibraryBackup() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.json]
        panel.nameFieldStringValue = "Prisma Library.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                guard let self else { return }
                let snapshot = LibrarySnapshot(
                    tracks: self.tracks, sources: self.sources, edited: Array(self.edited), playlists: self.playlists,
                    tagEdits: self.tagEdits)
                do {
                    try await Task.detached(priority: .utility) {
                        var portable = snapshot
                        for index in portable.tracks.indices {
                            portable.tracks[index].artwork = portable.tracks[index].artworkData
                            portable.tracks[index].artworkURL = nil
                            portable.tracks[index].albumArtworkURL = nil
                        }
                        try JSONEncoder().encode(portable).write(to: url, options: .atomic)
                    }.value
                } catch { self.error = error.localizedDescription }
            }
        }
    }
    var canImportLibraryMigration: Bool { !loading && !scanning && !relocatingSource && !writingFileTags && !saveBlocked }
    @discardableResult
    func importLibraryMigration(_ migration: LibraryMigration) -> Bool {
        guard canImportLibraryMigration, !quitting, !migration.isEmpty else { return false }
        let known = Set(tracks.map(\.id))
        let covers = customAlbumArtwork
        var changed = false
        var updatedEdits = tagEdits
        var updatedEdited = edited
        let updatedTracks = tracks.map { track in
            var updated = track
            if migration.favorites.contains(track.id) { updated.favorite = true }
            if let incoming = migration.edits[track.id] {
                var edit = updatedEdits[track.id] ?? TrackTagEdits()
                let original = edit
                edit.values.merge(incoming.values) { local, _ in local }
                if edit != original {
                    updatedEdits[track.id] = edit
                    updatedEdited.insert(track.id)
                    updated = edit.applying(to: updated)
                    if AlbumIdentity.key(updated) != AlbumIdentity.key(track) {
                        updated.albumArtworkURL = covers[AlbumIdentity.key(updated)]
                    }
                    changed = true
                }
            }
            if updated != track { changed = true }
            return updated
        }
        var updatedPlaylists = playlists
        for var list in migration.playlists {
            let name = list.name.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { continue }
            let retained = list.trackIDs.filter(known.contains)
            if list.rules == nil, !list.trackIDs.isEmpty, retained.isEmpty { continue }
            list.trackIDs = retained
            list.id = UUID()
            let importedName = name + " · " + t("migrationCopy")
            let names = updatedPlaylists.filter {
                $0.name.caseInsensitiveCompare(name) == .orderedSame
                    || $0.name.lowercased().hasPrefix(importedName.lowercased())
            }
            if names.contains(where: { $0.rules == list.rules && $0.trackIDs == list.trackIDs }) { continue }
            var candidate = name
            if !names.isEmpty { candidate = importedName }
            var suffix = 2
            while updatedPlaylists.contains(where: { $0.name.caseInsensitiveCompare(candidate) == .orderedSame }) {
                candidate = "\(importedName) \(suffix)"
                suffix += 1
            }
            list.name = candidate
            updatedPlaylists.append(list)
            changed = true
        }
        if changed {
            tracks = updatedTracks
            tagEdits = updatedEdits
            edited = updatedEdited
            playlists = updatedPlaylists
            save()
            updateNowPlaying()
        }
        return true
    }
    func libraryBackups() async throws -> [LibraryBackupPreview] {
        let directory = dataDirectory
        return try await Task.detached(priority: .utility) { try LibraryDatabaseBackups.list(in: directory) }.value
    }
    func backupTrackCount(_ id: String) async throws -> Int {
        let directory = dataDirectory
        return try await Task.detached(priority: .utility) {
            try LibraryDatabaseBackups.trackCount(id, in: directory)
        }.value
    }
    func stageLibraryRestore(_ id: String) async throws {
        try await persistence.stageRestore(id)
    }
    func showScanReport() {
        NSWorkspace.shared.activateFileViewerSelecting([dataDirectory.appendingPathComponent("scan-report.json")])
    }
    func showDataFolder() { NSWorkspace.shared.open(dataDirectory) }
    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in
            Task { @MainActor in if self?.isPlaying == false && self?.playbackLoading == false { self?.togglePlay() } }
            return .success
        }
        commands.pauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.pausePlayback() }
            return .success
        }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.togglePlay() }
            return .success
        }
        commands.nextTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next() }
            return .success
        }
        commands.previousTrackCommand.addTarget { [weak self] _ in
            Task { @MainActor in self?.next(back: true) }
            return .success
        }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }
            return .success
        }
    }
    private func updateNowPlaying() {
        refreshArtworkPalette()
        guard let track = current else {
            MPNowPlayingInfoCenter.default().nowPlayingInfo = nil
            return
        }
        var info: [String: Any] = [
            MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist,
            MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: track.duration,
            MPNowPlayingInfoPropertyElapsedPlaybackTime: position,
            MPNowPlayingInfoPropertyPlaybackRate: isPlaying
                ? Double(directOutputActive ? 1 : preferences.playbackRate) : 0.0,
        ]
        if track.hasArtwork, let image = ArtworkCache.shared.image(for: track, pixels: 512) {
            info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image }
        }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    func miniPlayer() {
        if let panel {
            panel.makeKeyAndOrderFront(nil)
            return
        }
        let window = NSPanel(
            contentRect: NSRect(x: 120, y: 120, width: 360, height: 430),
            styleMask: [.titled, .closable, .fullSizeContentView, .resizable, .nonactivatingPanel], backing: .buffered,
            defer: false)
        window.title = "Prisma Music"
        window.titlebarAppearsTransparent = true
        window.isFloatingPanel = true
        window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        window.isReleasedWhenClosed = false
        window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 320, height: 390)
        window.contentView = NSHostingView(rootView: MiniPlayerView().environmentObject(self))
        panel = window
        configureMiniPlayer()
        window.center()
        window.makeKeyAndOrderFront(nil)
    }
    private func configureMiniPlayer() {
        panel?.level = preferences.miniAlwaysOnTop ? .floating : .normal
        panel?.collectionBehavior =
            preferences.miniAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }
    private let listeningWindow = ListeningWindowController()
    func fullScreen() {
        if !fullScreenVisualizer, let window = listeningWindow.window, NSApp.keyWindow === window {
            listeningWindow.close()
        } else {
            fullScreenVisualizer = false
            listeningWindow.show(store: self)
        }
    }
    func openVisualizerStage() {
        fullScreenVisualizer = true
        listeningWindow.show(store: self)
    }
    func closeListeningWindow() { listeningWindow.close() }
    func enrich(_ track: Track) async {
        guard !fetching else { return }
        fetching = true
        defer { fetching = false }
        var artwork: Data?
        var credit: String?
        var lyrics: String?
        var hadError = false
        if !track.hasArtwork && preferences.autoArtwork {
            do {
                let result = try await OnlineMetadata.artwork(for: track)
                artwork = result?.0
                credit = result?.1
            } catch { if !Task.isCancelled { hadError = true } }
        }
        guard !Task.isCancelled else { return }
        if !track.hasLyrics && preferences.autoLyrics {
            do { lyrics = try await OnlineMetadata.lyrics(for: track) } catch {
                if !Task.isCancelled { hadError = true }
            }
        }
        guard !Task.isCancelled else { return }
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            if let artwork, !tracks[i].hasArtwork {
                var value = tracks[i]
                value.artwork = artwork
                value.artworkCredit = credit
                do {
                    value = try await persistence.normalized(value)
                    if let index = tracks.firstIndex(where: { $0.id == value.id }), !tracks[index].hasArtwork {
                        tracks[index].artworkURL = value.artworkURL
                        tracks[index].artworkCredit = value.artworkCredit
                    }
                } catch { hadError = true }
            }
            if let lyrics, let index = tracks.firstIndex(where: { $0.id == track.id }), !tracks[index].hasLyrics {
                tracks[index].lyrics = lyrics
                tracks[index].lyricsCredit = "LRCLIB"
            }
            save()
            updateNowPlaying()
        }
        if !scanning {
            status = hadError ? t("networkError") : (artwork != nil || lyrics != nil) ? t("finished") : t("notFound")
        }
    }
}
