import SwiftUI
import AppKit
import AVFoundation
import MediaPlayer
import UniformTypeIdentifiers

@MainActor
final class LibraryStore: NSObject, ObservableObject, AVAudioPlayerDelegate {
    @Published var tracks: [Track] = []
    @Published var sources: [MusicSource] = []
    @Published var currentID: String?
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
    @Published var section = "songs"
    @Published var sort = "title"
    @Published var showVisualizer = false
    @Published var showLyrics = false
    @Published var showInfo = false
    @Published var inspectedID: String?
    @Published var fetching = false
    @Published var shuffle = false
    @Published var repeatMode = 0 // 0 off, 1 all, 2 one
    @Published var volume: Float = 0.7 { didSet { player?.volume = volume; UserDefaults.standard.set(volume, forKey: "volume") } }
    @Published var language: AppLanguage = .es { didSet { UserDefaults.standard.set(language.rawValue, forKey: "language") } }
    @Published var accent: Accent = .violet { didSet { UserDefaults.standard.set(accent.rawValue, forKey: "accent") } }
    @Published var theme = "dark" { didSet { UserDefaults.standard.set(theme, forKey: "theme") } }
    @Published var online = true { didSet { UserDefaults.standard.set(online, forKey: "online") } }
    @Published var scanOnLaunch = true { didSet { UserDefaults.standard.set(scanOnLaunch, forKey: "scanOnLaunch") } }
    private var player: AVAudioPlayer?
    private var timer: Timer?
    private var queue: [String] = []
    private var scopeURLs: [URL] = []
    private var panel: NSPanel?
    private var attempted: Set<String> = []
    private var enrichmentTask: Task<Void, Never>?
    private var edited: Set<String> = []
    private let dataDirectory: URL
    var current: Track? { tracks.first { $0.id == currentID } }
    var colorScheme: ColorScheme? { theme == "dark" ? .dark : theme == "light" ? .light : nil }
    var filtered: [Track] {
        let result = LibraryQuery.filter(tracks, search: search, artist: artist, genre: genre, year: year, favorites: section == "favorites")
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
            tracks = saved.tracks; sources = saved.sources; edited = Set(saved.edited)
        } else if autoStart, let demo = Bundle.module.url(forResource: "Demo", withExtension: nil) {
            sources = [MusicSource(url: demo)]
        }
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
        Task { if scanOnLaunch || tracks.isEmpty { await scan() } }
        }
    }
    private struct SavedLibrary: Codable { var tracks: [Track]; var sources: [MusicSource]; var edited: [String] }
    func save() {
        do { let data = try JSONEncoder().encode(SavedLibrary(tracks: tracks, sources: sources, edited: Array(edited))); try data.write(to: dataDirectory.appendingPathComponent("library.json"), options: .atomic) }
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
    func scan() async {
        guard !scanning else { return }; scanning = true; defer { scanning = false }
        var failures = 0; var unavailable = 0
        let scanSources = sources
        for source in scanSources {
            let available = await Task.detached(priority: .utility) { FileManager.default.fileExists(atPath: source.url.path) }.value
            guard available else { unavailable += 1; continue }
            let files = await Task.detached(priority: .utility) { MetadataReader.files(in: source.url) }.value
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
                if let cached = tracks.first(where: { $0.id == url.path }), cached.modified == modified, cached.format != nil, cached.genre != "—", !cached.year.isEmpty { continue }
                do {
                    var track = try await MetadataReader.read(url)
                    if let existing = tracks.firstIndex(where: { $0.id == track.id }) {
                        let old = tracks[existing]; track.favorite = old.favorite
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
        if let id = currentID, !tracks.contains(where: { $0.id == id }) { player?.stop(); currentID = nil; isPlaying = false; position = 0 }
        save()
    }
    func update(_ track: Track) {
        if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i] = track; edited.insert(track.id); save(); updateNowPlaying() }
    }
    func favorite(_ track: Track) { if let i = tracks.firstIndex(where: { $0.id == track.id }) { tracks[i].favorite.toggle(); save() } }
    func play(_ track: Track, in list: [Track]? = nil) {
        if let list { queue = list.map(\.id) }
        if queue.isEmpty { queue = filtered.map(\.id) }
        do {
            let audio = try AVAudioPlayer(contentsOf: track.url)
            audio.delegate = self; audio.volume = volume; audio.isMeteringEnabled = true; audio.prepareToPlay()
            guard audio.play() else { throw NSError(domain: "Prisma", code: 2, userInfo: [NSLocalizedDescriptionKey: "Cannot play \(track.url.lastPathComponent)"]) }
            player = audio; currentID = track.id; isPlaying = true; position = 0
            updateNowPlaying()
            if online && !track.isDemo && !attempted.contains(track.id) && (track.lyrics == nil || track.artwork == nil) {
                attempted.insert(track.id)
                enrichmentTask?.cancel()
                enrichmentTask = Task { await enrich(track) }
            }
        } catch { self.error = "\(error.localizedDescription)\n\(t("offline"))" }
    }
    func togglePlay() {
        guard let player else { if let first = filtered.first { play(first, in: filtered) }; return }
        if isPlaying { player.pause(); isPlaying = false } else { isPlaying = player.play() }
        updateNowPlaying()
    }
    func seek(_ seconds: Double) { player?.currentTime = min(max(0, seconds), player?.duration ?? 0); position = player?.currentTime ?? 0; updateNowPlaying() }
    func next(back: Bool = false, automatic: Bool = false) {
        guard !tracks.isEmpty else { return }
        if back && position > 3 { seek(0); return }
        let list = queue.compactMap { id in tracks.first { $0.id == id } }
        guard !list.isEmpty else { return }
        if automatic && repeatMode == 2, let current { play(current); return }
        if shuffle, let track = list.filter({ $0.id != currentID }).randomElement() { play(track); return }
        let i = list.firstIndex { $0.id == currentID } ?? -1
        let nextIndex = i + (back ? -1 : 1)
        if nextIndex >= list.count && automatic && repeatMode == 0 { isPlaying = false; position = player?.duration ?? 0; updateNowPlaying(); return }
        play(list[(nextIndex + list.count) % list.count])
    }
    nonisolated func audioPlayerDidFinishPlaying(_ player: AVAudioPlayer, successfully flag: Bool) { Task { @MainActor in next(automatic: true) } }
    nonisolated func audioPlayerDecodeErrorDidOccur(_ player: AVAudioPlayer, error: Error?) { Task { @MainActor in self.isPlaying = false; self.error = error?.localizedDescription ?? "Audio decoding failed" } }
    private func tick() {
        guard let player else { return }
        position = player.currentTime
        if isPlaying { player.updateMeters(); level = Double(pow(10, player.averagePower(forChannel: 0) / 30)) }
        else { level *= 0.85 }
    }
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
        guard let track = current else { MPNowPlayingInfoCenter.default().nowPlayingInfo = nil; return }
        var info: [String: Any] = [MPMediaItemPropertyTitle: track.title, MPMediaItemPropertyArtist: track.artist, MPMediaItemPropertyAlbumTitle: track.album, MPMediaItemPropertyPlaybackDuration: track.duration, MPNowPlayingInfoPropertyElapsedPlaybackTime: position, MPNowPlayingInfoPropertyPlaybackRate: isPlaying ? 1.0 : 0.0]
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
        window.center(); window.makeKeyAndOrderFront(nil); panel = window
    }
    func fullScreen() { NSApp.windows.first(where: { !($0 is NSPanel) && $0.isVisible })?.toggleFullScreen(nil) }
    func enrich(_ track: Track) async {
        guard !fetching else { return }; fetching = true; defer { fetching = false }
        var artwork: Data?; var credit: String?; var lyrics: String?; var hadError = false
        if track.artwork == nil {
            do { let result = try await OnlineMetadata.artwork(for: track); artwork = result?.0; credit = result?.1 } catch { if !Task.isCancelled { hadError = true } }
        }
        guard !Task.isCancelled else { return }
        if track.lyrics == nil {
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
