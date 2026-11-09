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
    private var albumPlayTask: Task<Void, Never>?
    @Published private(set) var preparingAlbumID: String?
    private var playbackRequest = UUID()
    private let openAudioFile: @Sendable (URL) async throws -> OpenedAudioFile
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var level = 0.0
    @Published private(set) var loading = true
    @Published private(set) var scanning = false
    @Published private(set) var scanDiscovered = 0
    @Published private(set) var scanProcessed = 0
    @Published private(set) var scanAudit: ScanAudit?
    @Published private(set) var sourceStates: [UUID: String] = [:]
    @Published var status = ""
    @Published var error: String?
    @Published var search = ""
    @Published private(set) var searchFocusRequest = 0
    func focusSearch() { searchFocusRequest &+= 1 }
    @Published var artist = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var section = "home"
    @Published var sort = "title"
    @Published var feedback: FeedbackNotice?
    private var feedbackTask: Task<Void, Never>?
    @Published var showImmersive = true
    @Published var artworkPalette = ArtworkPalette.fallback()
    @Published var ambientEnergy = 0.0
    @Published var showVisualizer = false
    @Published var showLyrics = false
    @Published var showQueue = false
    @Published var showInfo = false
    @Published var inspectedID: String?
    @Published var fetching = false
    @Published var playlists: [Playlist] = [] { didSet { queryCache = nil } }
    @Published var sleepDeadline: Date?
    @Published var sleepRemaining = 0
    @Published var stopAfterCurrent = false
    @Published var peak = 0.0
    @Published var preferences = ListeningPreferences() { didSet { preferencesChanged(previous: oldValue) } }
    @Published var settingsPage = "sound"
    @Published var showWelcome = false
    private var welcomeAfterSettings = false
    @Published var showSettings = false
    @Published var shuffle = false {
        didSet {
            if shuffle {
                let rest = queue.filter { $0 != currentID }.shuffled()
                queue = currentID.map { [$0] + rest } ?? rest
            }
        }
    }
    @Published var repeatMode = 0  // 0 off, 1 all, 2 one
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
    private var trackIndex: [String: Int]?
    private var queueIndexCache: [String: Int]?
    private var statisticsCache: LibraryStatistics?
    private var queryCache: LibraryQueryCache?
    private var albumCollectionCache: (revision: Int, id: String, value: AlbumCollection)?
    func albumCollection(_ id: String) -> AlbumCollection? {
        if let cached = albumCollectionCache, cached.revision == revision, cached.id == id { return cached.value }
        guard let seed = track(for: id) else { return nil }
        let value = AlbumCollection(seed: seed, library: tracks)
        albumCollectionCache = (revision, id, value)
        return value
    }
    func navigateTo(_ destination: String) {
        selectedAlbumID = nil
        selectedArtist = nil
        showVisualizer = false
        showImmersive = destination == "immersive"
        if destination != "immersive" {
            section = destination
            clearFilters()
        }
    }
    func openAlbum(_ track: Track) {
        selectedAlbumID = track.id
        inspectedID = track.id
        showImmersive = false
        showVisualizer = false
        if section != "artists" || selectedArtist == nil {
            section = "albums"
            selectedArtist = nil
        }
    }
    func openArtist(_ name: String) {
        selectedAlbumID = nil
        selectedArtist = name
        section = "artists"
        showImmersive = false
        showVisualizer = false
    }
    func readAlbumOrder(_ id: String) async {
        guard let album = albumCollection(id) else { return }
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
        guard !positions.isEmpty, !Task.isCancelled else { return }
        var updated = tracks
        for i in updated.indices {
            if let value = positions[updated[i].id] {
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
        let value = ArtistCollection(name: name, library: tracks)
        artistCollectionCache = (revision, name, value)
        return value
    }
    private var revision = 0
    private var lastQueryKey: LibraryQueryKey?
    private var player: (any MusicPlayback)?
    private var timer: Timer?
    @Published var queue: [String] = [] { didSet { queueIndexCache = nil } }
    private var activity: NSObjectProtocol?
    private var lastRememberedSecond = -1
    private var savedPlayback: (String, Double)?
    private var scopeURLs: [URL] = []
    private var panel: NSPanel?
    private var attempted: Set<String> = []
    private var enrichmentTask: Task<Void, Never>?
    private var edited: Set<String> = []
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
        queryCache = nil
    }
    var statistics: LibraryStatistics {
        if let statisticsCache { return statisticsCache }
        let value = LibraryStatistics(tracks: tracks)
        statisticsCache = value
        return value
    }
    var hasActiveFilters: Bool { !search.isEmpty || !artist.isEmpty || !genre.isEmpty || !year.isEmpty }
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
        let key = LibraryQueryKey(
            revision: revision, search: search, artist: artist, genre: genre, year: year, section: section, sort: sort)
        if let queryCache, lastQueryKey == key { return queryCache }
        var base = tracks
        if section == "lossless" { base = base.filter(\.isLossless) }
        if section.hasPrefix("playlist:"), let id = UUID(uuidString: String(section.dropFirst(9))),
            let list = playlists.first(where: { $0.id == id })
        {
            base = list.trackIDs.compactMap { track(for: $0) }
        }
        var value = LibraryQuery.filter(
            base, search: search, artist: artist, genre: genre, year: year, favorites: section == "favorites")
        if section == "recent" {
            value = value.filter { $0.lastPlayed != nil }.sorted {
                ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast)
            }
        } else if !section.hasPrefix("playlist:") {
            value.sort { a, b in
                let x: String
                let y: String
                switch sort {
                case "artist":
                    x = a.artist + a.album + a.title
                    y = b.artist + b.album + b.title
                case "album":
                    x = a.album + a.title
                    y = b.album + b.title
                case "year":
                    x = a.year + a.title
                    y = b.year + b.title
                default:
                    x = a.title
                    y = b.title
                }
                return x.localizedStandardCompare(y) == .orderedAscending
            }
        }
        let cache = LibraryQueryCache(tracks: value)
        queryCache = cache
        lastQueryKey = key
        return cache
    }
    var filtered: [Track] { results.tracks }
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
        section = preferences.startSection == "immersive" ? "home" : preferences.startSection
        showImmersive = preferences.startSection == "immersive"
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
            setupRemoteCommands()
            readyTask = Task { [weak self] in
                guard let self else { return }
                do {
                    let persistence = self.persistence
                    let snapshot = try await Task.detached(priority: .utility) { try persistence.load() }.value
                    applyLoaded(snapshot, includeDemo: true)
                } catch {
                    saveBlocked = true
                    self.error = error.localizedDescription
                }
                loading = false
                guard !quitting else { return }
                restorePlaybackIfNeeded()
                if !preferences.hasCompletedWelcome {
                    showWelcome = true
                    return
                }
                if !saveBlocked && (scanOnLaunch || tracks.isEmpty) { await scan() }
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
        currentID = id
        position = min(track.duration, max(0, time))
        queue = filtered.map(\.id)
        updateNowPlaying()
    }

    private func applyLoaded(_ snapshot: LibrarySnapshot?, includeDemo: Bool) {
        if let snapshot {
            tracks = snapshot.tracks
            sources = snapshot.sources
            edited = Set(snapshot.edited)
            playlists = snapshot.playlists ?? []
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
    private func remapSource(_ old: URL, to new: URL) {
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
            ids[track.id] = value.id
            return value
        }
        playlists = playlists.map { list in
            var value = list
            value.trackIDs = value.trackIDs.map { ids[$0] ?? $0 }
            return value
        }
        edited = Set(edited.map { ids[$0] ?? $0 })
        queue = queue.map { ids[$0] ?? $0 }
        if let id = currentID { currentID = ids[id] ?? id }
        if let (id, time) = savedPlayback { savedPlayback = (ids[id] ?? id, time) }
    }
    func save() {
        guard !saveBlocked else { return }
        persistence.save(.init(tracks: tracks, sources: sources, edited: Array(edited), playlists: playlists))
    }
    func flushSaving() async throws { try await persistence.flush() }
    func prepareForTermination() async throws {
        quitting = true
        defer { quitting = false }
        cancelScan()
        if loading { await readyTask?.value }
        await scanTask?.value
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
        for url in scopeURLs { url.stopAccessingSecurityScopedResource() }
        scopeURLs.removeAll()
    }
    func waitUntilReady() async { await readyTask?.value }
    func clearFilters() {
        search = ""
        artist = ""
        genre = ""
        year = ""
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
        await scan()
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
        section = preferences.startSection == "immersive" ? "home" : preferences.startSection
        showImmersive = preferences.startSection == "immersive"
        if scanAfter && scanOnLaunch && !scanning { Task { await scan() } }
    }
    func retryFailedScan() async {
        guard let audit = scanAudit, !audit.issues.isEmpty else { return }
        await scan(force: true, retrying: audit)
    }
    func scan(force: Bool = false, retrying: ScanAudit? = nil) async {
        if loading { await readyTask?.value }
        guard !scanning, !saveBlocked else { return }
        scanning = true
        scanDiscovered = 0
        scanProcessed = 0
        scanCancellation = ScanCancellation()
        let task = Task { await performScan(force: force, retrying: retrying) }
        scanTask = task
        await task.value
        scanTask = nil
        scanning = false
    }
    private func performScan(force: Bool, retrying: ScanAudit?) async {
        var failures = 0
        var unavailable = 0
        var audit = ScanAudit()
        var recovered = Set<URL>()
        let cancellation = scanCancellation
        for source in sources {
            if Task.isCancelled || cancellation.isCancelled { break }
            sourceStates[source.id] = "reading"
            status = "\(t("discovering")) · \(source.name)"
            scanDiscovered = 0
            scanProcessed = 0
            let recursive = preferences.recursiveScan
            let report: SourceScanReport
            if let retrying {
                let root = source.url
                let selected = retrying.issues.map(\.url).filter {
                    MetadataReader.extensions.contains($0.pathExtension.lowercased())
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
                report = await Task.detached(priority: .utility) { [weak self] in
                    SourceScanner.enumerate(
                        source.url, recursive: recursive, cancellation: cancellation, readModificationDates: false
                    ) { [weak self] count in
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
            audit.discovered += report.files.count
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
                    group.addTask { await ScannedTrackResult.read(file, cached: cached, force: force) }
                }
                @MainActor func fillSlots() {
                    while next < files.count, running < maximumScanWorkers, !cancellation.isCancelled, !Task.isCancelled
                    { submit() }
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
                        status = "\(t("reading")) \(processed)/\(report.files.count) · \(source.name)"
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
                SourceScanner.canReconcile(report, cancelled: cancellation.isCancelled)
            }.value
            if retrying != nil {
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
            save()
        }
        save()
        do { try await persistence.flush() } catch { self.error = error.localizedDescription }
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
    private func upsertTracks(_ values: [Track]) {
        var updated = tracks
        var indices = Dictionary(updated.indices.map { (updated[$0].id, $0) }, uniquingKeysWith: { _, last in last })
        for var track in values {
            if let index = indices[track.id] {
                let old = updated[index]
                track.favorite = old.favorite
                track.lastPlayed = old.lastPlayed
                track.playCount = old.playCount
                if edited.contains(old.id) {
                    track.title = old.title
                    track.artist = old.artist
                    track.album = old.album
                    track.genre = old.genre
                    track.year = old.year
                }
                if !track.hasArtwork {
                    track.artworkURL = old.artworkURL
                    track.artworkCredit = old.artworkCredit
                }
                if !track.hasLyrics {
                    track.lyrics = old.lyrics
                    track.lyricsCredit = old.lyricsCredit
                }
                updated[index] = track
            } else {
                indices[track.id] = updated.count
                updated.append(track)
            }
        }
        tracks = updated
    }
    func removeSource(_ source: MusicSource) {
        guard !scanning else { return }
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
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            tracks[i] = track
            edited.insert(track.id)
            save()
            updateNowPlaying()
        }
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
            var restored = previous.filter { id in tracks.contains { $0.id == id } }
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
    }
    func play(_ track: Track, in list: [Track]? = nil, from start: Double = 0) {
        if let list {
            queue = shuffle ? [track.id] + list.filter { $0.id != track.id }.map(\.id).shuffled() : list.map(\.id)
        }
        if queue.isEmpty { queue = filtered.map(\.id) }
        cancelPlaybackLoad()
        let token = playbackRequest
        loadingTrackID = track.id
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
                try Task.checkCancellation()
                guard self.playbackRequest == token, !self.quitting, self.track(for: track.id) != nil else { return }
                let previous = self.player
                previous?.pause()
                self.isPlaying = false
                var output: OutputPreparation?
                if !airPlay, let opened {
                    if self.outputs.devices.isEmpty && !self.outputs.refreshing { self.outputs.refresh() }
                    await self.outputs.waitForRefresh()
                    guard let device = self.outputs.device(uid: self.preferences.outputDeviceUID) else {
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
                }
                try Task.checkCancellation()
                guard self.playbackRequest == token else { return }
                let audio = try self.makePlayer(track, file: opened?.file, output: output)
                audio.currentTime = start.isFinite ? max(0, start) : 0
                guard audio.play() else {
                    throw NSError(
                        domain: "Prisma", code: 2, userInfo: [NSLocalizedDescriptionKey: self.t("audioLoadFailed")])
                }
                self.preparedOutput = output
                previous?.stop()
                self.player = audio
                self.currentID = track.id
                self.isPlaying = true
                self.position = airPlay ? min(track.duration, max(0, start.isFinite ? start : 0)) : audio.currentTime
                self.loadingTrackID = nil
                self.playbackLoadTask = nil
                if let i = self.tracks.firstIndex(where: { $0.id == track.id }) {
                    self.tracks[i].lastPlayed = Date()
                    self.tracks[i].playCount = (self.tracks[i].playCount ?? 0) + 1
                    self.save()
                }
                self.updateActivity()
                self.updateNowPlaying()
                self.rememberPlayback()
                if self.online && !track.isDemo && !self.attempted.contains(track.id)
                    && (!track.hasLyrics || !track.hasArtwork)
                {
                    self.attempted.insert(track.id)
                    self.enrichmentTask?.cancel()
                    self.enrichmentTask = Task { await self.enrich(track) }
                }
            } catch {
                guard let self, self.playbackRequest == token, !Task.isCancelled else { return }
                self.loadingTrackID = nil
                self.playbackLoadTask = nil
                self.error = "\(self.t("audioLoadFailed")) · \(track.title)\n\(self.t(error.localizedDescription))"
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
        let list = queue.compactMap { track(for: $0) }
        guard !list.isEmpty else { return }
        if automatic && repeatMode == 2, let current {
            play(current)
            return
        }
        let selected = loadingTrackID ?? currentID
        let i = list.firstIndex { $0.id == selected } ?? -1
        let nextIndex = i + (back ? -1 : 1)
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
        if Int(position) % 5 == 0 && Int(position) != lastRememberedSecond {
            lastRememberedSecond = Int(position)
            rememberPlayback()
        }
    }
    private func makePlayer(_ track: Track, file: AVAudioFile?, output: OutputPreparation?) throws -> any MusicPlayback
    {
        let audio: any MusicPlayback
        if usingAirPlay {
            audio = AirPlayPlayback(player: airPlayPlayer, track: track)
        } else if let file {
            audio = try AudioPlayback(file: file, output: output)
        } else {
            throw URLError(.cannotOpenFile)
        }
        audio.volume = volume
        audio.apply(preferences)
        audio.onFinish = { [weak self] in self?.playbackDidFinish() }
        audio.onError = { [weak self, weak audio] error in
            guard let self, let audio, self.player === audio else { return }
            self.isPlaying = false
            self.position = audio.currentTime
            self.error = self.t(error.localizedDescription)
            if self.directOutputActive {
                audio.stop()
                self.player = nil
                self.preparedOutput = nil
            }
            self.updateActivity()
            self.updateNowPlaying()
        }
        return audio
    }
    func playbackDidFinish() {
        isPlaying = false
        position = player?.duration ?? current?.duration ?? position
        updateActivity()
        updateNowPlaying()
        rememberPlayback()
        if !playbackLoading { next(automatic: true) }
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
        guard preferences.rememberPosition, let currentID else { return }
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
        player?.apply(preferences)
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
    func createPlaylist(_ name: String) {
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        playlists.append(Playlist(name: name))
        save()
        postFeedback("playlistCreated", detail: name, icon: "music.note.list")
    }
    func add(_ track: Track, to playlist: Playlist) {
        if let i = playlists.firstIndex(where: { $0.id == playlist.id }), !playlists[i].trackIDs.contains(track.id) {
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
    func removeFromPlaylist(_ track: Track) {
        if let i = playlists.firstIndex(where: { section == "playlist:\($0.id)" }) {
            playlists[i].trackIDs.removeAll { $0 == track.id }
            save()
        }
    }
    func enqueue(_ track: Track, next: Bool = false) {
        guard track.id != currentID else { return }
        let previous = queue
        queue.removeAll { $0 == track.id && $0 != currentID }
        if next, let index = queue.firstIndex(where: { $0 == currentID }) {
            queue.insert(track.id, at: index + 1)
        } else {
            queue.append(track.id)
        }
        postFeedback(next ? "queuedNext" : "queued", detail: track.title, icon: "list.bullet", undo: .queue(previous))
    }
    func removeQueued(_ track: Track) {
        guard track.id != currentID else { return }
        queue.removeAll { $0 == track.id }
    }
    func moveQueued(_ track: Track, direction: Int) {
        guard let index = queue.firstIndex(of: track.id), queue.indices.contains(index + direction) else { return }
        queue.swapAt(index, index + direction)
    }
    func exportPlaylist() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]
        panel.nameFieldStringValue = "Prisma Music.m3u8"
        let list = section == "home" ? tracks : filtered
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
                    tracks: self.tracks, sources: self.sources, edited: Array(self.edited), playlists: self.playlists)
                do {
                    try await Task.detached(priority: .utility) {
                        var portable = snapshot
                        for index in portable.tracks.indices {
                            portable.tracks[index].artwork = portable.tracks[index].artworkData
                            portable.tracks[index].artworkURL = nil
                        }
                        try JSONEncoder().encode(portable).write(to: url, options: .atomic)
                    }.value
                } catch { self.error = error.localizedDescription }
            }
        }
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
        if let window = listeningWindow.window, NSApp.keyWindow === window {
            listeningWindow.close()
        } else {
            listeningWindow.show(store: self)
        }
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
                    if let index = tracks.firstIndex(where: { $0.id == value.id }) { tracks[index] = value }
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
