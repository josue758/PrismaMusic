import SwiftUI
import AppKit
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: NSObject, ObservableObject {
    @Published var tracks: [Track] = [] { didSet { refreshArtworkPalette() } }
    @Published var sources: [MusicSource] = []
    @Published var currentID: String? { didSet { refreshArtworkPalette() } }
    @Published var isPlaying = false
    @Published var position = 0.0
    @Published var level = 0.0
    @Published var scanning = false
    @Published var status = ""
    @Published var error: String?
    @Published var search = ""
    @Published var artist = ""
    @Published var genre = ""
    @Published var year = ""
    @Published var section = "home"
    @Published var sort = "title"
    @Published var showImmersive = true
    @Published var artworkPalette = ArtworkPalette.fallback()
    @Published var ambientEnergy = 0.0
    @Published var showVisualizer = false
    @Published var showLyrics = false
    @Published var showQueue = false
    @Published var showInfo = false
    @Published var inspectedID: String?
    @Published var fetching = false
    @Published var playlists: [Playlist] = []
    @Published var sleepDeadline: Date?
    @Published var sleepRemaining = 0
    @Published var stopAfterCurrent = false
    @Published var peak = 0.0
    @Published var preferences = ListeningPreferences() { didSet { preferencesChanged() } }
    @Published var settingsPage = "sound"
    @Published var showSettings = false
    @Published var shuffle = false { didSet { if shuffle { let rest = queue.filter { $0 != currentID }.shuffled(); queue = currentID.map { [$0] + rest } ?? rest } } }
    @Published var repeatMode = 0 // 0 off, 1 all, 2 one
    @Published var volume: Float = 0.7 { didSet { player?.volume = volume; UserDefaults.standard.set(volume, forKey: "volume") } }
    @Published var language: AppLanguage = .es { didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") } }
    @Published var accent: Accent = .violet { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    @Published var theme = "dark" { didSet { UserDefaults.standard.set(theme, forKey: "theme") } }
    @Published var online = true { didSet { UserDefaults.standard.set(online, forKey: "online") } }
    @Published var scanOnLaunch = true { didSet { UserDefaults.standard.set(scanOnLaunch, forKey: "scanOnLaunch") } }
    private var paletteTask: Task<Void, Never>?
    private var paletteTrackID: String?
    private var paletteArtwork: Data?
    private var player: AudioPlayback?
    private var timer: Timer?
    @Published var queue: [String] = []
    private var activity: NSObjectProtocol?
    private var lastRememberedSecond = -1
    private var savedPlayback: (String, Double)?
    private var scopeURLs: [URL] = []
    private var panel: NSPanel?
    private var attempted: Set<String> = []
    private var enrichmentTask: Task<Void, Never>?
    private var edited: Set<String> = []
    private let dataDirectory: URL
    var current: Track? { tracks.first { $0.id == currentID } }
    var visualTrack: Track? { current ?? tracks.first }
    var effectiveAccent: Color {
        guard preferences.adaptiveArtwork, visualTrack != nil else { return accent.color }
        let dark = colorScheme == .dark || (colorScheme == nil && NSApp.effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua)
        return artworkPalette.primary.readable(onDark: dark).color
    }
    private func refreshArtworkPalette() {
        let track = visualTrack
        guard paletteTrackID != track?.id || paletteArtwork != track?.artwork else { return }
        paletteTrackID = track?.id; paletteArtwork = track?.artwork; paletteTask?.cancel()
        let fallback = ArtworkPalette.fallback(album: track?.album ?? "Prisma")
        guard let data = track?.artwork else { artworkPalette = fallback; return }
        let id = track?.id
        paletteTask = Task { [weak self] in
            let palette = await Task.detached(priority: .utility) { ArtworkPalette.extract(data, fallback: fallback) }.value
            guard !Task.isCancelled, let self, self.paletteTrackID == id, self.paletteArtwork == data else { return }
            self.artworkPalette = palette
        }
    }
    var colorScheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    var queuedTracks: [Track] { queue.compactMap { id in tracks.first { $0.id == id } } }
    var albumCount: Int { Set(tracks.map { $0.artist + "|" + $0.album }).count }
    var artistCount: Int { Set(tracks.map(\.artist)).count }
    var libraryBytes: Int64 { tracks.reduce(0) { $0 + ($1.fileSize ?? 0) } }
    var totalDuration: Double { tracks.reduce(0) { $0 + $1.duration } }
    var filtered: [Track] {
        var base = tracks
        if section == "lossless" { base = base.filter(\.isLossless) }
        if section.hasPrefix("playlist:"), let id = UUID(uuidString: String(section.dropFirst(9))), let list = playlists.first(where: { $0.id == id }) { base = list.trackIDs.compactMap { id in tracks.first { $0.id == id } } }
        let result = LibraryQuery.filter(base, search: search, artist: artist, genre: genre, year: year, favorites: section == "favorites")
        if section == "recent" { return result.filter { $0.lastPlayed != nil }.sorted { ($0.lastPlayed ?? .distantPast) > ($1.lastPlayed ?? .distantPast) } }
        if section.hasPrefix("playlist:") { return result }
        return result.sorted { a, b in
            let x: String; let y: String
            switch sort { case "artist": x = a.artist + a.album + a.title; y = b.artist + b.album + b.title
            case "album": x = a.album + a.title; y = b.album + b.title
            case "year": x = a.year + a.title; y = b.year + b.title
            default: x = a.title; y = b.title }
            return x.localizedStandardCompare(y) == .orderedAscending
        }
    }
    func t(_ key: String) -> String { translations[key]?[language == .es ? 0 : language == .en ? 1 : 2] ?? key }
    init(directory: URL? = nil, autoStart: Bool = true) {
        dataDirectory = directory ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("PrismaMusic")
        super.init()
        let defaults = UserDefaults.standard
        language = AppLanguage(rawValue: defaults.string(forKey: "language") ?? "es") ?? .es
        accent = Accent(rawValue: defaults.string(forKey: "accent") ?? "violet") ?? .violet
        theme = defaults.string(forKey: "theme") ?? "dark"
        online = defaults.object(forKey: "online") as? Bool ?? true
        scanOnLaunch = defaults.object(forKey: "scanOnLaunch") as? Bool ?? true
        volume = defaults.object(forKey: "volume") as? Float ?? 0.7
        do { try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true) } catch { self.error = error.localizedDescription }
        if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("library.json")), let saved = try? JSONDecoder().decode(SavedLibrary.self, from: data) {
            tracks = saved.tracks; sources = saved.sources; edited = Set(saved.edited); playlists = saved.playlists ?? []
        } else if autoStart, let demo = Bundle.module.url(forResource: "Demo", withExtension: nil) {
            sources = [MusicSource(url: demo)]
        }
        if let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("preferences.json")), var prefs = try? JSONDecoder().decode(ListeningPreferences.self, from: data) {
            prefs.sanitize(); preferences = prefs
        }
        section = preferences.startSection == "immersive" ? "home" : preferences.startSection
        showImmersive = preferences.startSection == "immersive"
        if preferences.rememberPosition, let data = try? Data(contentsOf: dataDirectory.appendingPathComponent("playback.json")), let saved = try? JSONDecoder().decode(PlaybackBookmark.self, from: data) { savedPlayback = (saved.id, saved.position) }
        if let demo = Bundle.module.url(forResource: "Demo", withExtension: nil) {
            for index in sources.indices where sources[index].url.path.contains("PrismaMusic_PrismaMusic.bundle") {
                let previous = sources[index].url
                sources[index].url = demo
                if previous != demo {
                    for i in tracks.indices where tracks[i].url.deletingLastPathComponent().standardizedFileURL == previous.standardizedFileURL {
                        tracks[i].url = demo.appendingPathComponent(tracks[i].url.lastPathComponent)
                    }
                }
            }
        }
        for index in sources.indices {
            if let data = sources[index].bookmark {
                var stale = false
                if let url = try? URL(resolvingBookmarkData: data, options: [.withSecurityScope, .withoutUI], relativeTo: nil, bookmarkDataIsStale: &stale) {
                    sources[index].url = url
                    if url.startAccessingSecurityScopedResource() { scopeURLs.append(url) }
                    if stale { sources[index].bookmark = try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil) }
                }
            }
        }
        if autoStart {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.tick() }
        }
        setupRemoteCommands()
        Task {
            if scanOnLaunch || tracks.isEmpty { await scan() }
            if let (id, time) = savedPlayback, let track = tracks.first(where: { $0.id == id }) {
                do { let audio = try makePlayer(track); audio.currentTime = time; player = audio; currentID = id; position = audio.currentTime; queue = filtered.map(\.id); updateNowPlaying() } catch { status = t("offline") }
            }
        }
        }
    }
    private struct SavedLibrary: Codable { var tracks: [Track]; var sources: [MusicSource]; var edited: [String]; var playlists: [Playlist]? }
    func save() {
        do { let data = try JSONEncoder().encode(SavedLibrary(tracks: tracks, sources: sources, edited: Array(edited), playlists: playlists)); try data.write(to: dataDirectory.appendingPathComponent("library.json"), options: .atomic) }
        catch { self.error = error.localizedDescription }
    }
    func clearFilters() { search = ""; artist = ""; genre = ""; year = "" }
    func pickMusic() {
        let open = NSOpenPanel(); open.canChooseDirectories = true; open.canChooseFiles = true; open.allowsMultipleSelection = true
        open.allowedContentTypes = [.audio, .folder]; open.prompt = t("add")
        open.begin { [weak self] response in
            guard response == .OK else { return }
            Task { @MainActor in await self?.addSources(open.urls) }
        }
    }
    func addSources(_ urls: [URL]) async {
        guard !scanning else { return }
        for url in urls where !sources.contains(where: { $0.url.standardizedFileURL == url.standardizedFileURL }) {
            if url.startAccessingSecurityScopedResource() { scopeURLs.append(url) }
            sources.append(MusicSource(url: url, bookmark: try? url.bookmarkData(options: .withSecurityScope, includingResourceValuesForKeys: nil, relativeTo: nil)))
        }
        save(); await scan()
    }
    func scan(force: Bool = false) async {
        guard !scanning else { return }; scanning = true; defer { scanning = false }
        var failures = 0; var unavailable = 0
        let scanSources = sources
        for source in scanSources {
            let available = await Task.detached(priority: .utility) { FileManager.default.fileExists(atPath: source.url.path) }.value
            guard available else { unavailable += 1; continue }
            let recursive = preferences.recursiveScan
            let files = await Task.detached(priority: .utility) { MetadataReader.files(in: source.url, recursive: recursive) }.value
            let fileIDs = Set(files.map(\.path))
            // Remove deleted local files only when the source is actually available.
            tracks.removeAll { track in
                let isWithin = track.url == source.url || track.url.path.hasPrefix(source.url.path.hasSuffix("/") ? source.url.path : source.url.path + "/")
                return isWithin && !fileIDs.contains(track.id)
            }
            for (index, url) in files.enumerated() {
                if Task.isCancelled { break }
                status = "\(t("reading")) \(index + 1)/\(files.count) · \(source.name)"
                let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
                if !force, let cached = tracks.first(where: { $0.id == url.path }), cached.modified == modified, cached.format != nil, cached.genre != "—", !cached.year.isEmpty { continue }
                do {
                    var track = try await MetadataReader.read(url)
                    if let existing = tracks.firstIndex(where: { $0.id == track.id }) {
                        let old = tracks[existing]; track.favorite = old.favorite; track.lastPlayed = old.lastPlayed; track.playCount = old.playCount
                        if edited.contains(old.id) { track.title = old.title; track.artist = old.artist; track.album = old.album; track.genre = old.genre; track.year = old.year }
                        if track.artwork == nil { track.artwork = old.artwork; track.artworkCredit = old.artworkCredit }
                        if track.lyrics == nil { track.lyrics = old.lyrics; track.lyricsCredit = old.lyricsCredit }
                        tracks[existing] = track
                    } else { tracks.append(track) }
                } catch { failures += 1 }
            }
        }
        save()
        status = unavailable > 0 ? t("offline") : failures > 0 ? "\(t("scanErrors")): \(failures)" : t("ready")
    }
    func removeSource(_ source: MusicSource) {
        guard !scanning else { return }
        sources.removeAll { $0.id == source.id }
        let prefix = source.url.path.hasSuffix("/") ? source.url.path : source.url.path + "/"
        tracks.removeAll { $0.url == source.url || $0.url.path.hasPrefix(prefix) }
        if let id = currentID, !tracks.contains(where: { $0.id == id }) { player?.stop(); currentID = nil; isPlaying = false; position = 0; updateActivity(); updateNowPlaying() }
        save()
    }
    func update(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i] = track; edited.insert(track.id); save(); updateNowPlaying() }
    }
    func favorite(_ track: Track) { if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].favorite.toggle(); save() } }
    func play(_ track: Track, in list: [Track]? = nil) {
        if let list { queue = shuffle ? [track.id] + list.filter { $0.id != track.id }.map(\.id).shuffled() : list.map(\.id) }
        if queue.isEmpty { queue = filtered.map(\.id) }
        do {
            let audio = try makePlayer(track)
            guard audio.play() else { throw NSError(domain: "Prisma", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot play \(track.url.lastPathComponent)"]) }
            player?.stop(); player = audio; currentID = track.id; isPlaying = true; position = 0
            if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].lastPlayed = Date(); tracks[i].playCount = (tracks[i].playCount ?? 0) + 1; save() }
            updateActivity()
            updateNowPlaying()
            if online && !track.isDemo && !attempted.contains(track.id) && (track.lyrics == nil || track.artwork == nil) {
                attempted.insert(track.id)
                enrichmentTask?.cancel()
                enrichmentTask = Task { await enrich(track) }
            }
        } catch { self.error = "\(error.localizedDescription)\n\(t("offline"))" }
    }
    func togglePlay() {
        guard let player else { if let first = queuedTracks.first ?? filtered.first { play(first, in: queue.isEmpty ? filtered : nil) }; return }
        if isPlaying { player.pause(); isPlaying = false } else { isPlaying = player.play() }
        updateNowPlaying(); updateActivity(); rememberPlayback()
    }
    func seek(_ seconds: Double) { player?.currentTime = min(max(0, seconds), player?.duration ?? 0); position = player?.currentTime ?? 0; updateNowPlaying(); rememberPlayback() }
    func next(back: Bool = false, automatic: Bool = false) {
        guard !tracks.isEmpty else { return }
        if automatic && (stopAfterCurrent || !preferences.continueQueue) { stopAfterCurrent = false; pausePlayback(); return }
        if back && position > 3 { seek(0); return }
        let list = queue.compactMap { id in tracks.first { $0.id == id } }
        guard !list.isEmpty else { return }
        if automatic && repeatMode == 2, let current { play(current); return }
        let i = list.firstIndex { $0.id == currentID } ?? -1
        let nextIndex = i + (back ? -1 : 1)
        if nextIndex >= list.count && automatic && repeatMode == 0 { isPlaying = false; position = player?.duration ?? 0; player?.pause(); updateNowPlaying(); updateActivity(); rememberPlayback(); return }
        play(list[(nextIndex + list.count) % list.count])
    }
    private func tick() {
        if let deadline = sleepDeadline {
            sleepRemaining = max(0, Int(ceil(deadline.timeIntervalSinceNow)))
            if deadline <= Date() { sleepDeadline = nil; pausePlayback() }
        }
        let targetEnergy = isPlaying ? min(1, pow(max(0, level), 0.55) * 1.8) : 0
        ambientEnergy += (targetEnergy - ambientEnergy) * (targetEnergy > ambientEnergy ? 0.20 : 0.075)
        guard let player else { return }
        position = player.currentTime
        if isPlaying { let meters = player.levels; level = Double(meters.rms); peak = Double(meters.peak) }
        else { level *= 0.85; peak *= 0.85 }
        if Int(position) % 5 == 0 && Int(position) != lastRememberedSecond { lastRememberedSecond = Int(position); rememberPlayback() }
    }
    private func makePlayer(_ track: Track) throws -> AudioPlayback {
        let audio = try AudioPlayback(contentsOf: track.url)
        audio.volume = volume; audio.apply(preferences)
        audio.onFinish = { [weak self] in self?.next(automatic: true) }
        audio.onError = { [weak self] error in self?.isPlaying = false; self?.error = error.localizedDescription; self?.updateActivity() }
        return audio
    }
    func pausePlayback() { player?.pause(); isPlaying = false; updateNowPlaying(); updateActivity(); rememberPlayback() }
    private struct PlaybackBookmark: Codable { var id: String; var position: Double }
    private func rememberPlayback() {
        guard preferences.rememberPosition, let currentID else { return }
        do { try JSONEncoder().encode(PlaybackBookmark(id: currentID, position: position)).write(to: dataDirectory.appendingPathComponent("playback.json"), options: .atomic) } catch { status = error.localizedDescription }
    }
    private func preferencesChanged() {
        player?.apply(preferences); updateActivity(); configureMiniPlayer()
        do { try JSONEncoder().encode(preferences).write(to: dataDirectory.appendingPathComponent("preferences.json"), options: .atomic) } catch { self.error = error.localizedDescription }
    }
    private func updateActivity() {
        if isPlaying && preferences.keepAwake {
            if activity == nil { activity = ProcessInfo.processInfo.beginActivity(options: [.idleSystemSleepDisabled], reason: "Prisma Music playback") }
        } else if let activity { ProcessInfo.processInfo.endActivity(activity); self.activity = nil }
    }
    func setSleepTimer(minutes: Int?) { sleepDeadline = minutes.map { Date().addingTimeInterval(Double($0) * 60) }; sleepRemaining = (minutes ?? 0) * 60 }
    func openSettings(_ page: String = "sound") { settingsPage = page; showSettings = true }
    func createPlaylist(_ name: String) { let name = name.trimmingCharacters(in: .whitespacesAndNewlines); guard !name.isEmpty else { return }; playlists.append(Playlist(name: name)); save() }
    func add(_ track: Track, to playlist: Playlist) { if let i = playlists.firstIndex(where: { $0.id == playlist.id }), !playlists[i].trackIDs.contains(track.id) { playlists[i].trackIDs.append(track.id); save() } }
    func removePlaylist(_ playlist: Playlist) { playlists.removeAll { $0.id == playlist.id }; if section == "playlist:\(playlist.id)" { section = "home" }; save() }
    func removeFromPlaylist(_ track: Track) { if let i = playlists.firstIndex(where: { section == "playlist:\($0.id)" }) { playlists[i].trackIDs.removeAll { $0 == track.id }; save() } }
    func enqueue(_ track: Track, next: Bool = false) {
        guard track.id != currentID else { return }
        queue.removeAll { $0 == track.id && $0 != currentID }
        if next, let index = queue.firstIndex(where: { $0 == currentID }) { queue.insert(track.id, at: index + 1) }
        else { queue.append(track.id) }
    }
    func removeQueued(_ track: Track) { guard track.id != currentID else { return }; queue.removeAll { $0 == track.id } }
    func moveQueued(_ track: Track, direction: Int) {
        guard let index = queue.firstIndex(of: track.id), queue.indices.contains(index + direction) else { return }
        queue.swapAt(index, index + direction)
    }
    func exportPlaylist() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [UTType(filenameExtension: "m3u8") ?? .plainText]; panel.nameFieldStringValue = "Prisma Music.m3u8"
        let list = section == "home" ? tracks : filtered
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            let body = "#EXTM3U\n" + list.map { "#EXTINF:\(Int($0.duration)),\($0.artist) - \($0.title)\n\($0.url.path)" }.joined(separator: "\n") + "\n"
            do { try body.write(to: url, atomically: true, encoding: .utf8) } catch { Task { @MainActor in self?.error = error.localizedDescription } }
        }
    }
    func exportLibraryBackup() {
        let panel = NSSavePanel(); panel.allowedContentTypes = [.json]; panel.nameFieldStringValue = "Prisma Library.json"
        panel.begin { [weak self] response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in guard let self else { return }; do { let data = try JSONEncoder().encode(SavedLibrary(tracks: self.tracks, sources: self.sources, edited: Array(self.edited), playlists: self.playlists)); try data.write(to: url, options: .atomic) } catch { self.error = error.localizedDescription } }
        }
    }
    func showDataFolder() { NSWorkspace.shared.open(dataDirectory) }
    private func setupRemoteCommands() {
        let commands = MPRemoteCommandCenter.shared()
        commands.playCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == false { self?.togglePlay() } }; return .success }
        commands.pauseCommand.addTarget { [weak self] _ in Task { @MainActor in if self?.isPlaying == true { self?.togglePlay() } }; return .success }
        commands.togglePlayPauseCommand.addTarget { [weak self] _ in Task { @MainActor in self?.togglePlay() }; return .success }
        commands.nextTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next() }; return .success }
        commands.previousTrackCommand.addTarget { [weak self] _ in Task { @MainActor in self?.next(back: true) }; return .success }
        commands.changePlaybackPositionCommand.addTarget { [weak self] event in
            guard let event = event as? MPChangePlaybackPositionCommandEvent else { return .commandFailed }
            Task { @MainActor in self?.seek(event.positionTime) }; return .success
        }
    }
    private func updateNowPlaying() {
        refreshArtworkPalette()
        guard let track = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: track.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? Double(preferences.playbackRate) : 0.0]
        if let data = track.artwork, let image = NSImage(data: data) { info[MPMediaItemPropertyArtwork] = MPMediaItemArtwork(boundsSize: image.size) { _ in image } }
        MPNowPlayingInfoCenter.default().nowPlayingInfo = info
        MPNowPlayingInfoCenter.default().playbackState = isPlaying ? .playing : .paused
    }
    func miniPlayer() {
        if let panel { panel.makeKeyAndOrderFront(nil); return }
        let window = NSPanel(contentRect: NSRect(x: 120, y: 120, width: 360, height: 430), styleMask: [.titled, .closable, .fullSizeContentView, .resizable, .nonactivatingPanel], backing: .buffered, defer: false)
        window.title = "Prisma Music"; window.titlebarAppearsTransparent = true; window.isFloatingPanel = true; window.level = .floating
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]; window.isReleasedWhenClosed = false; window.hidesOnDeactivate = false
        window.minSize = NSSize(width: 320, height: 390)
        window.contentView = NSHostingView(rootView: MiniPlayerView().environmentObject(self))
        panel = window; configureMiniPlayer(); window.center(); window.makeKeyAndOrderFront(nil)
    }
    private func configureMiniPlayer() {
        panel?.level = preferences.miniAlwaysOnTop ? .floating : .normal
        panel?.collectionBehavior = preferences.miniAllSpaces ? [.canJoinAllSpaces, .fullScreenAuxiliary] : [.fullScreenAuxiliary]
    }
    func fullScreen() { NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible })?.toggleFullScreen(nil) }
    func enrich(_ track: Track) async {
        guard !fetching else { return }; fetching = true; defer { fetching = false }
        var artwork: Data?; var credit: String?; var lyrics: String?; var hadError = false
        if track.artwork == nil && preferences.autoArtwork {
            do { let result = try await OnlineMetadata.artwork(for: track); artwork = result?.0; credit = result?.1 } catch { if !Task.isCancelled { hadError = true } }
        }
        guard !Task.isCancelled else { return }
        if track.lyrics == nil && preferences.autoLyrics {
            do { lyrics = try await OnlineMetadata.lyrics(for: track) } catch { if !Task.isCancelled { hadError = true } }
        }
        guard !Task.isCancelled else { return }
        if let i = tracks.firstIndex(where: { $0.id == track.id }) {
            if let artwork, tracks[i].artwork == nil { tracks[i].artwork = artwork; tracks[i].artworkCredit = credit }
            if let lyrics, tracks[i].lyrics == nil { tracks[i].lyrics = lyrics; tracks[i].lyricsCredit = "LRCLIB" }
            save(); updateNowPlaying()
        }
        status = hadError ? t("networkError") : (artwork != nil || lyrics != nil) ? t("finished") : t("notFound")
    }
}
