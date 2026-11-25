import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var navigationSelection
    private var motion: Bool { store.preferences.microInteractions && !reduceMotion }
    private var pageKey: String {
        if store.showVisualizer { return "visualizer" }
        if let id = store.selectedAlbumID { return "album:" + id }
        return store.selectedArtist.map { "artist:" + $0 } ?? store.section
    }
    @FocusState private var searchFocused: Bool
    @State private var nas = false
    @State private var nasReconnectSheet: LibraryStore.NASRetry?
    @State private var editing: Track?
    @State private var newPlaylist = false
    @State private var playlistName = ""
    @State private var smartPlaylistDraft: SmartPlaylistDraft?
    @State private var managingPlaylist: Playlist?
    @State private var playlistImport: PlaylistImport?
    @State private var sourceReport: MusicSource?
    @State private var compactInspector = true
    @State private var narrowLibrary = false
    private var inspectorVisible: Bool { store.showInfo || store.showLyrics || store.showQueue }
    private var inspectorWidth: CGFloat { store.current == nil && !store.showInfo ? 224 : 278 }
    @ViewBuilder private var inspector: some View {
        if store.showInfo {
            TrackInfoView()
        } else if store.showLyrics {
            LyricsView()
        } else if store.showQueue {
            QueueView()
        }
    }
    private func dismissInspector() {
        store.showInfo = false
        store.showLyrics = false
        store.showQueue = false
    }
    private var sectionTitle: String {
        if store.section.hasPrefix("playlist:"),
            let playlist = store.playlists.first(where: { store.section == "playlist:\($0.id)" })
        {
            return playlist.name
        }
        if let id = store.selectedAlbumID, let album = store.albumCollection(id) {
            return store.displayAlbum(album.title)
        }
        return store.section == "artists" ? store.selectedArtist ?? store.t("artists") : store.t(store.section)
    }
    var body: some View {
        ZStack {
            PrismaBackdrop()
            Group {
                VStack(spacing: 16) {
                    HStack(alignment: .top, spacing: 20) {
                        sidebar
                        VStack(spacing: 20) {
                            toolbar
                            NASRecoveryBanner { nasReconnectSheet = $0 }
                            ZStack(alignment: .topLeading) {
                                Group {
                                    if let id = store.selectedAlbumID, !store.showVisualizer {
                                        AlbumDetailView(id: id)
                                    } else if let name = store.selectedArtist, store.section == "artists",
                                        !store.showVisualizer
                                    {
                                        ArtistDetailView(name: name)
                                    } else if store.showVisualizer {
                                        VisualizerView()
                                    } else {
                                        library
                                    }
                                }.id(pageKey).transition(.asymmetric(insertion: .opacity, removal: .identity))
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().animation(
                                motion ? .easeOut(duration: 0.12) : nil, value: pageKey)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if inspectorVisible && !compactInspector {
                            Color.clear.frame(width: inspectorWidth).accessibilityHidden(true)
                        }
                    }.frame(maxHeight: .infinity)
                        .overlay(alignment: .trailing) {
                            if inspectorVisible {
                                if compactInspector {
                                    Button(action: dismissInspector) {
                                        Color.black.opacity(0.24).contentShape(Rectangle())
                                    }.buttonStyle(.plain)
                                        .accessibilityLabel(store.t("closeUpdate"))
                                        .keyboardShortcut(.cancelAction)
                                }
                                inspector.frame(width: inspectorWidth).prismaGlass(24)
                                    .transition(motion ? .move(edge: .trailing).combined(with: .opacity) : .opacity)
                            }
                        }
                        .animation(motion ? .smooth(duration: 0.18) : nil, value: inspectorVisible)
                    PlayerBar().padding(.horizontal, 20).padding(.vertical, 14).prismaGlass(26, tinted: true)
                }.padding(16).padding(.top, 24).prismaCursorLighting()
            }
        }
        .overlay(alignment: .bottom) {
            if let notice = store.feedback {
                FeedbackToast(notice: notice).id(notice.id).padding(.horizontal, 24).padding(.bottom, 124)
                    .transition(
                        motion
                            ? .move(edge: .bottom).combined(with: .opacity).combined(
                                with: .scale(scale: 0.96, anchor: .bottom)) : .opacity)
            }
        }.animation(motion ? .spring(duration: 0.34, bounce: 0.13) : nil, value: store.feedback?.id)
        .frame(minWidth: 900, minHeight: 680)
        .onGeometryChange(for: Bool.self) { $0.size.width < 1120 } action: { narrowLibrary = $0 }
        .onGeometryChange(for: Bool.self) {
            $0.size.width < 1260
        } action: {
            compactInspector = $0
        }
        .onChange(of: store.searchFocusRequest) { _, _ in searchFocused = true }
        .onChange(of: store.search) { _, text in
            if !text.isEmpty
                && (store.section == "home" || store.selectedAlbumID != nil || store.selectedArtist != nil
                    || store.showVisualizer)
            {
                store.navigateTo("songs", preservingSearch: true)
            }
        }
        .sheet(isPresented: $store.showWelcome) { WelcomeView().environmentObject(store) }
        .sheet(isPresented: $store.showSettings, onDismiss: { store.settingsDismissed() }) {
            SettingsView().environmentObject(store)
        }
        .sheet(isPresented: $nas) { NASView().environmentObject(store) }
        .sheet(item: $nasReconnectSheet) { retry in
            NASView(retry: retry, initialAddress: store.rememberedServer(for: retry)?.absoluteString ?? "smb://")
                .environmentObject(store)
        }
        .onChange(of: store.nasRetry?.id) { _, id in
            if nasReconnectSheet?.id != id { nasReconnectSheet = nil }
        }
        .sheet(item: $editing) { track in TagEditor(track: track).environmentObject(store) }
        .sheet(isPresented: $newPlaylist) {
            VStack(alignment: .leading, spacing: 20) {
                Label(store.t("newPlaylist"), systemImage: "music.note.list").font(.title2.bold())
                TextField(store.t("playlistName"), text: $playlistName).textFieldStyle(.roundedBorder).onSubmit {
                    createPlaylist()
                }
                Text(store.t("playlistEmpty")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(store.t("cancel")) { newPlaylist = false }
                    Spacer()
                    Button(store.t("create")) { createPlaylist() }.buttonStyle(.glassProminent).disabled(
                        playlistName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }.padding(30).frame(width: 420)
        }
        .sheet(item: $smartPlaylistDraft) { draft in
            SmartPlaylistEditor(draft: draft).environmentObject(store)
        }
        .sheet(item: $playlistImport) { PlaylistImportView(preview: $0).environmentObject(store) }
        .sheet(item: $managingPlaylist) { PlaylistManagementView(playlist: $0).environmentObject(store) }
        .sheet(item: $sourceReport) { ScanReportView(sourceID: $0.id).environmentObject(store) }
        .alert("Prisma Music", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } }))
        {
            Button("OK") { store.error = nil }
        } message: {
            Text(store.error ?? "")
        }
    }
    private func createPlaylist() {
        store.createPlaylist(playlistName)
        playlistName = ""
        newPlaylist = false
    }
    private func openPlaylistImport() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = ["m3u", "m3u8"].compactMap { UTType(filenameExtension: $0) }
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            let tracks = store.tracks
            Task {
                do {
                    playlistImport = try await Task.detached(priority: .userInitiated) {
                        try PlaylistImport.read(url, tracks: tracks)
                    }.value
                } catch { store.error = error.localizedDescription }
            }
        }
    }
    private func editPlaylist(_ playlist: Playlist) {
        if let rules = playlist.rules {
            smartPlaylistDraft = .init(playlist: playlist, rules: rules)
        } else {
            managingPlaylist = playlist
        }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 11) {
                Image(systemName: "waveform.path").font(.system(size: 27, weight: .light)).foregroundStyle(
                    store.effectiveAccent
                ).frame(width: 38, height: 38).background(
                    store.effectiveAccent.opacity(0.10), in: RoundedRectangle(cornerRadius: 12))
                VStack(alignment: .leading, spacing: 3) {
                    Text("PRISMA").font(.system(size: 17, weight: .semibold, design: .rounded)).tracking(3)
                    Text("M U S I C").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(.secondary)
                }
            }.padding(.horizontal, 7).padding(.top, 10)
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    VStack(spacing: 4) {
                        nav("home", "square.grid.2x2")
                        nav("songs", "music.note.list")
                        nav("albums", "square.stack")
                        nav("artists", "person.2")
                    }
                    VStack(alignment: .leading, spacing: 5) {
                        sidebarLabel("library")
                        nav("favorites", "heart")
                        nav("recent", "clock.arrow.circlepath")
                        nav("lossless", "waveform.badge.magnifyingglass")
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            sidebarLabel("playlists")
                            Spacer()
                            Menu {
                                Button(store.t("newPlaylist")) { newPlaylist = true }
                                Button(store.t("newSmartPlaylist")) {
                                    smartPlaylistDraft = .init(
                                        rules: .init(search: store.search, artist: store.artist, genre: store.genre,
                                                     year: store.year, favorites: store.section == "favorites"))
                                }
                                Button(store.t("importPlaylist")) { openPlaylistImport() }
                            } label: {
                                Image(systemName: "plus").font(.system(size: 11))
                            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                                .help(store.t("newPlaylist")).accessibilityLabel(store.t("newPlaylist"))
                        }.padding(.trailing, 10)
                        ForEach(store.playlists) { playlist in
                            Button {
                                store.navigateTo("playlist:\(playlist.id)")
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: playlist.rules == nil ? "music.note" : "line.3.horizontal.decrease")
                                        .foregroundStyle(store.effectiveAccent.opacity(0.7))
                                    Text(playlist.name).lineLimit(1)
                                    Spacer()
                                    if playlist.rules == nil {
                                        Text("\(playlist.trackIDs.count)").foregroundStyle(.tertiary)
                                    }
                                }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 7).background(
                                    store.section == "playlist:\(playlist.id)"
                                        ? store.effectiveAccent.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain)
                                .accessibilityAddTraits(store.activePlaylist?.id == playlist.id ? .isSelected : [])
                                .contextMenu { playlistActions(playlist) }
                        }
                        if store.playlists.isEmpty {
                            Text(store.t("playlistEmpty")).font(.system(size: 10)).foregroundStyle(.tertiary)
                                .lineSpacing(4).padding(.horizontal, 12)
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            sidebarLabel("sources")
                            Spacer()
                            Button {
                                store.pickMusic()
                            } label: {
                                Image(systemName: "plus").font(.system(size: 11))
                            }.buttonStyle(.plain).help(store.t("add")).disabled(store.scanning)
                        }.padding(.trailing, 10)
                        ForEach(store.sources) { source in
                            sourceRow(source).contextMenu {
                                Button(store.t("scanSelectedLocation")) {
                                    Task { await store.scan(newOnly: true, sourceID: source.id) }
                                }.disabled(store.scanning)
                                Button(store.t("scanReport")) { sourceReport = source }
                                Divider()
                                Button(store.t("reveal")) {
                                    NSWorkspace.shared.activateFileViewerSelecting([source.url])
                                }
                                Button(store.t("removeSource"), role: .destructive) { store.removeSource(source) }
                                    .disabled(store.scanning)
                            }
                        }
                        Button {
                            nas = true
                        } label: {
                            Label(store.t("connect"), systemImage: "network").font(.system(size: 10)).foregroundStyle(
                                .secondary)
                        }.buttonStyle(.plain).padding(.horizontal, 12).padding(.top, 4)
                    }
                }
            }.scrollIndicators(.hidden).clipped()
            VStack(spacing: 13) {
                HStack(spacing: 10) {
                    Image(systemName: "slider.vertical.3").font(.system(size: 18, weight: .light)).foregroundStyle(
                        store.effectiveAccent)
                    VStack(alignment: .leading, spacing: 4) {
                        Text(store.t("listeningRoom")).font(.system(size: 11, weight: .medium))
                        Text(
                            store.preferences.eqEnabled
                                ? store.t(store.preferences.eqPreset) + " · EQ" : store.t("bypass")
                        ).font(.system(size: 9)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Image(systemName: "chevron.right").font(.system(size: 9)).foregroundStyle(.secondary)
                }.padding(13).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 14)).contentShape(
                    Rectangle()
                ).onTapGesture { store.openSettings("sound") }
                HStack {
                    Button {
                        store.openSettings("appearance")
                    } label: {
                        Label(store.t("settings"), systemImage: "gearshape").font(.system(size: 11))
                    }.buttonStyle(.plain)
                    Spacer()
                    HStack(spacing: 4) {
                        Circle().fill(.mint).frame(width: 4, height: 4)
                        Text(store.current?.sourceIsNetwork == true ? "NAS" : "LOCAL").font(
                            .system(size: 8, weight: .medium, design: .monospaced)
                        ).tracking(1)
                    }.foregroundStyle(.secondary)
                }.padding(.horizontal, 7)
            }
        }.padding(14).frame(width: narrowLibrary ? 180 : 224).frame(maxHeight: .infinity).prismaGlass(24)
            .animation(motion ? .smooth(duration: 0.14) : nil, value: store.section)
    }
    private func sourceRow(_ source: MusicSource) -> some View {
        let selected = store.activeSourceFilter == .folder(source.id)
        let state = store.sourceStates[source.id]
        return Button {
            store.navigateTo("songs")
            store.sourceFilter = .folder(source.id)
        } label: {
            HStack(spacing: 9) {
                Image(systemName: source.url.path.hasPrefix("/Volumes")
                      ? "externaldrive.connected.to.line.below" : "folder")
                    .foregroundStyle(store.effectiveAccent)
                Text(source.name).lineLimit(1)
                Spacer(minLength: 0)
                if state == "reading" {
                    ProgressView().controlSize(.mini)
                } else if state == "offline" {
                    Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
                }
            }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 7)
                .background(selected ? store.effectiveAccent.opacity(0.15) : .clear,
                            in: RoundedRectangle(cornerRadius: 9))
                .contentShape(Rectangle())
        }.buttonStyle(.plain)
            .help(source.url.path)
            .accessibilityValue(state.map(store.t) ?? "")
            .accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func sidebarLabel(_ key: String) -> some View {
        Text(store.t(key).uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(
            .tertiary
        ).padding(.horizontal, 12).padding(.bottom, 4)
    }
    private func nav(_ key: String, _ icon: String) -> some View {
        let selected = store.section == key && !store.showVisualizer
        return Button {
            store.navigateTo(key)
        } label: {
            HStack(spacing: 11) {
                Image(systemName: icon).font(.system(size: 13)).frame(width: 18)
                Text(store.t(key == "recent" ? "recentNav" : key)).font(
                    .system(size: 12, weight: selected ? .semibold : .regular)
                ).lineLimit(1)
                Spacer(minLength: 0)
                if key == "songs" { Text("\(store.tracks.count)").font(.system(size: 9)).foregroundStyle(.tertiary) }
            }.padding(.horizontal, 12).padding(.vertical, 10).background {
                if selected {
                    RoundedRectangle(cornerRadius: 11).fill(store.effectiveAccent.opacity(0.16)).matchedGeometryEffect(
                        id: "navigationSelection", in: navigationSelection)
                }
            }.foregroundStyle(selected ? store.effectiveAccent : .primary.opacity(0.65))
        }.buttonStyle(.plain)
    }
    private var toolbar: some View {
        HStack(spacing: 10) {
            if let destination = store.showVisualizer ? store.t("back") : store.backDestination {
                Button {
                    store.goBack()
                } label: {
                    Label(destination, systemImage: "chevron.backward").lineLimit(1).frame(
                        maxWidth: 140, alignment: .leading)
                }.buttonStyle(.glass).help(store.t("back"))
                    .keyboardShortcut("[", modifiers: .command)
            }
            VStack(alignment: .leading, spacing: 5) {
                Text("PRISMA / LIBRARY").font(.system(size: 8, weight: .medium, design: .monospaced)).tracking(1.5)
                    .foregroundStyle(.tertiary)
                Text(store.showVisualizer ? store.t("visualizer") : sectionTitle)
                    .font(.system(size: 15, weight: .medium, design: .rounded)).lineLimit(1)
            }
            Spacer(minLength: 8)
            HStack(spacing: 7) {
                Image(systemName: "magnifyingglass").font(.system(size: 12)).foregroundStyle(.secondary)
                TextField(store.t("search"), text: $store.search).focused($searchFocused).onExitCommand {
                    store.search = ""
                    searchFocused = false
                }.textFieldStyle(.plain).font(.system(size: 11))
                if !store.search.isEmpty {
                    Button {
                        store.search = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                    }.buttonStyle(.plain).help(store.t("clearSearch")).accessibilityLabel(store.t("clearSearch"))
                }
            }.padding(.horizontal, 13).frame(width: narrowLibrary ? 170 : inspectorVisible ? 190 : 255, height: 36)
                .prismaGlass(22)
            GlassEffectContainer(spacing: 7) {
                HStack(spacing: 7) {
                    GlassIconButton(icon: "waveform.path", label: store.t("visualizer"), active: store.showVisualizer) {
                        store.openVisualizerStage()
                    }
                    GlassIconButton(icon: "quote.bubble", label: store.t("lyrics"), active: store.showLyrics) {
                        store.showLyrics.toggle()
                        store.showInfo = false
                        store.showQueue = false
                    }
                    GlassIconButton(icon: "list.bullet", label: store.t("queue"), active: store.showQueue) {
                        store.showQueue.toggle()
                        store.showLyrics = false
                        store.showInfo = false
                    }
                    GlassIconButton(icon: "info", label: store.t("fileInfo"), active: store.showInfo) {
                        store.showInfo.toggle()
                        store.showLyrics = false
                        store.showQueue = false
                    }
                }
            }
        }.padding(.horizontal, 2).frame(height: 42)
    }
    private var library: some View {
        VStack(spacing: 12) {
            if store.tracks.isEmpty {
                ContentUnavailableView {
                    Label(store.t("empty"), systemImage: "music.note.house")
                } description: {
                    Text(store.t("emptyNote"))
                } actions: {
                    Button(store.t("add")) { store.pickMusic() }.buttonStyle(.glassProminent)
                }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 24) {
                        if store.section == "home" && store.search.isEmpty {
                            hero
                            if let track = store.current {
                                resumeCard(track)
                            }
                            collectionStats
                            if !store.playlists.isEmpty { homePlaylists }
                            if !store.recentlyAdded.isEmpty {
                                SectionHeading(title: store.t("recentImports"))
                                songList(store.recentlyAdded)
                            }
                            HStack {
                                SectionHeading(title: store.t("featured"))
                                Spacer()
                                Button(store.t("seeAll") + " ↗") { store.navigateTo("albums") }.buttonStyle(.plain)
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            albumGrid(limit: 3)
                            HStack {
                                SectionHeading(
                                    title: store.t("songs"),
                                    subtitle: store.tracks.allSatisfy(\.isDemo) ? store.t("demoNote") : nil)
                                Spacer()
                                Button(store.t("allSongs") + " ↗") { store.navigateTo("songs") }.buttonStyle(.plain)
                                    .font(.system(size: 10)).foregroundStyle(.secondary)
                            }
                            songList(Array(store.filtered.prefix(8)))
                        } else {
                            HStack(alignment: .bottom) {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(sectionTitle).font(.system(size: 30, weight: .semibold, design: .rounded))
                                    Text(store.sectionSummary).font(.system(size: 11)).foregroundStyle(.secondary)
                                }
                                Spacer()
                                if let playlist = store.activePlaylist {
                                    Menu {
                                        playlistActions(playlist)
                                    } label: {
                                        Label(store.t("managePlaylist"), systemImage: "ellipsis.circle").labelStyle(.iconOnly)
                                    }.menuStyle(.borderlessButton).fixedSize()
                                        .help(store.t("managePlaylist")).accessibilityLabel(store.t("managePlaylist"))
                                }
                                Button {
                                    store.pickMusic()
                                } label: {
                                    Label(store.t("add"), systemImage: "plus").font(.system(size: 11)).padding(
                                        .vertical, 3)
                                }.buttonStyle(.glassProminent).disabled(store.scanning)
                            }.padding(.top, 10)
                            filterBar
                            if store.filtered.isEmpty {
                                ContentUnavailableView {
                                    Label(store.t("noResults"), systemImage: "music.note")
                                } description: {
                                    Text(store.section.hasPrefix("playlist:") ? store.t("playlistEmpty") : "")
                                } actions: {
                                    if store.hasActiveFilters {
                                        Button(store.t("clear")) { store.clearFilters() }
                                    } else {
                                        Button(store.t("browseSongs")) {
                                            store.navigateTo("songs")
                                        }
                                    }
                                }.frame(minHeight: 240)
                            } else if store.section == "albums" {
                                albumGrid(limit: nil)
                            } else if store.section == "artists" {
                                artistGrid
                            } else {
                                if store.section == "songs" && !store.search.trimmingCharacters(in: .whitespaces).isEmpty {
                                    groupedSearch
                                    SectionHeading(title: store.t("songs"))
                                }
                                songList(store.filtered)
                            }
                        }
                    }.padding(3).padding(.bottom, 20)
                }.scrollIndicators(.hidden).clipped()
            }
            HStack(spacing: 6) {
                if store.scanning {
                    ProgressView().controlSize(.mini)
                    Button {
                        store.cancelScan()
                    } label: {
                        Image(systemName: "stop.circle")
                    }.buttonStyle(.plain).help(store.t("cancel"))
                }
                Text(
                    store.loadingTrackID.flatMap { store.track(for: $0) }.map {
                        store.t("loadingAudio") + " " + $0.title
                    } ?? (store.status.isEmpty ? store.t("ready") : store.status)
                ).font(.system(size: 9)).lineLimit(1).foregroundStyle(.tertiary)
                Spacer()
                Button {
                    Task { await store.scanNewMusic() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain).disabled(store.scanning).help(store.t("scan"))
                Text("PRISMA / " + AppVersion.current).font(.system(size: 8, design: .monospaced)).tracking(1)
                    .foregroundStyle(.tertiary)
            }.padding(.horizontal, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    private var homePlaylists: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeading(title: store.t("playlists"))
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 150))], alignment: .leading) {
                ForEach(store.playlists.prefix(8)) { playlist in
                    Button {
                        store.navigateTo("playlist:\(playlist.id)")
                    } label: {
                        Label(playlist.name, systemImage: playlist.rules == nil ? "music.note.list" : "line.3.horizontal.decrease")
                            .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.glass)
                }
            }
        }
    }
    @ViewBuilder
    private func playlistActions(_ playlist: Playlist) -> some View {
        Button(store.t(playlist.rules == nil ? "managePlaylist" : "editSmartPlaylist")) { editPlaylist(playlist) }
        Button(store.t("duplicatePlaylist")) { store.duplicatePlaylist(playlist) }
        Button(store.t("exportPlaylist")) { store.exportPlaylist(store.tracks(in: playlist)) }
        Divider()
        Button(store.t("deletePlaylist"), role: .destructive) { store.removePlaylist(playlist) }
    }
    private func resumeCard(_ track: Track) -> some View {
        HStack(spacing: 14) {
            ArtworkView(track: track).frame(width: 58, height: 58).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(store.t("continueListening")).font(.caption).foregroundStyle(.secondary)
                Text(track.title).font(.headline).lineLimit(1)
                Text(store.displayArtist(track.artist)).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer()
            Text(clockText(store.position)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            Button {
                store.togglePlay()
            } label: {
                PlaybackControlSymbol().frame(width: 24, height: 24)
            }.buttonStyle(.glassProminent).accessibilityLabel(store.playbackControlLabel)
        }.padding(14).prismaGlass(20)
    }
    private var groupedSearch: some View {
        VStack(alignment: .leading, spacing: 14) {
            if !store.groupedArtists.isEmpty {
                SectionHeading(title: store.t("artists"))
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 145))], alignment: .leading) {
                    ForEach(store.groupedArtists.prefix(6), id: \.key) { group in
                        Button {
                            store.openArtist(group.key)
                        } label: {
                            Label(store.displayArtist(group.key), systemImage: "person.crop.circle")
                                .lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                        }.buttonStyle(.glass)
                    }
                }
            }
            if !store.groupedAlbums.isEmpty {
                SectionHeading(title: store.t("albums"))
                albumGrid(limit: 3)
            }
        }
    }
    private var hero: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 13) {
                HStack(spacing: 6) {
                    Circle().fill(store.effectiveAccent).frame(width: 4, height: 4)
                    Text(store.t("collection")).font(.system(size: 8, weight: .semibold)).tracking(2)
                }.foregroundStyle(store.effectiveAccent)
                Text(store.t("heroTitle")).font(
                    .system(size: inspectorVisible ? 30 : 39, weight: .light, design: .rounded)
                ).tracking(-1).fixedSize(horizontal: false, vertical: true)
                Text(store.t("heroSubtitle")).font(.system(size: 11)).foregroundStyle(.secondary)
                HStack(spacing: 10) {
                    Button {
                        if let first = store.filtered.first { store.play(first, in: store.filtered) }
                    } label: {
                        Label(store.t("listen"), systemImage: "play.fill").font(.system(size: 11, weight: .medium))
                            .padding(.horizontal, 4).padding(.vertical, 3)
                    }.buttonStyle(.glassProminent)
                    Button {
                        store.pickMusic()
                    } label: {
                        Image(systemName: "plus").frame(width: 22, height: 25)
                    }.buttonStyle(.glass).help(store.t("add")).disabled(store.scanning)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !inspectorVisible {
                ZStack {
                    ForEach(Array(store.tracks.prefix(3).enumerated().reversed()), id: \.element.id) { i, track in
                        ArtworkView(track: track).frame(width: 164, height: 164).rotationEffect(
                            .degrees(i == 0 ? -7 : i == 1 ? 8 : 19)
                        ).offset(x: CGFloat(i) * 27 - 25, y: CGFloat(i) * -2).shadow(
                            color: .black.opacity(0.25), radius: 15, y: 10)
                    }
                }.frame(width: 235, height: 185).accessibilityHidden(true)
            }
        }.padding(26).frame(maxWidth: .infinity, minHeight: 225).background {
            LinearGradient(
                colors: [store.effectiveAccent.opacity(0.08), .clear], startPoint: .topLeading,
                endPoint: .bottomTrailing
            ).clipShape(RoundedRectangle(cornerRadius: 26))
        }.prismaGlass(26, tinted: true)
    }
    private var collectionStats: some View {
        HStack(spacing: 12) {
            stat("square.stack", "\(store.albumCount)", store.t("albums"))
            stat("person.2", "\(store.artistCount)", store.t("artists"))
            stat("waveform", collectionTimeText(store.totalDuration), store.t("duration"))
            stat(
                "externaldrive", ByteCountFormatter.string(fromByteCount: store.libraryBytes, countStyle: .file),
                store.t("fileSize"))
        }
    }
    private func stat(_ icon: String, _ value: String, _ label: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 16, weight: .light)).foregroundStyle(
                store.effectiveAccent.opacity(0.8))
            VStack(alignment: .leading, spacing: 5) {
                Text(value).font(.system(size: 19, weight: .medium, design: .rounded)).lineLimit(1).minimumScaleFactor(
                    0.7)
                Text(label).font(.system(size: 9)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }.padding(15).frame(maxWidth: .infinity).prismaGlass(17)
    }
    private var filterBar: some View {
        HStack(spacing: 8) {
            filterMenu("allArtists", selection: $store.artist, values: store.statistics.artists)
            filterMenu("allGenres", selection: $store.genre, values: store.statistics.genres)
            filterMenu("allYears", selection: $store.year, values: store.statistics.years)
            if store.section == "songs" || store.section == "albums" {
                sourceMenu
            }
            Spacer(minLength: 0)
            if store.section != "artists" && store.section != "recent" && !store.section.hasPrefix("playlist:") {
                let isAlbums = store.section == "albums"
                let selection = Binding(
                    get: { isAlbums && store.sort == "title" ? "album" : store.sort },
                    set: { store.sort = $0 })
                Menu {
                    Picker(store.t("sort"), selection: selection) {
                        ForEach(
                            isAlbums ? ["album", "artist", "year"] : ["title", "artist", "album", "year"], id: \.self
                        ) {
                            Text(store.t($0)).tag($0)
                        }
                    }
                } label: {
                    Image(systemName: "arrow.up.arrow.down")
                }.menuStyle(.borderlessButton).fixedSize().help(store.t("sort"))
            }
            if !store.artist.isEmpty || !store.genre.isEmpty || !store.year.isEmpty || store.activeSourceFilter != nil {
                Button {
                    store.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain).help(store.t("clear"))
            }
        }
    }
    private var sourceMenu: some View {
        Menu {
            Picker(store.t("sources"), selection: $store.sourceFilter) {
                Text(store.t("allLocations")).tag(nil as LibrarySourceFilter?)
                Text(store.t("nasLocations")).tag(LibrarySourceFilter.network as LibrarySourceFilter?)
                Text(store.t("localLocations")).tag(LibrarySourceFilter.local as LibrarySourceFilter?)
                ForEach(store.sources) { source in
                    Text(source.name).tag(LibrarySourceFilter.folder(source.id) as LibrarySourceFilter?)
                }
            }
            if let source = store.selectedLibrarySource {
                Button(store.t("scanSelectedLocation")) {
                    Task { await store.scan(newOnly: true, sourceID: source.id) }
                }.disabled(store.scanning)
            }
        } label: {
            let label = switch store.activeSourceFilter {
            case .network: store.t("nasLocations")
            case .local: store.t("localLocations")
            case .folder: store.selectedLibrarySource?.name ?? store.t("allLocations")
            case nil: store.t("allLocations")
            }
            Label(label, systemImage: "folder").font(.system(size: 10)).lineLimit(1)
                .frame(maxWidth: 112).padding(.horizontal, 10).padding(.vertical, 9)
        }.menuStyle(.borderlessButton).prismaGlass(18)
    }
    private func filterMenu(_ key: String, selection: Binding<String>, values: [String]) -> some View {
        Menu {
            Button(store.t(key)) { selection.wrappedValue = "" }
            Divider()
            ForEach(values, id: \.self) { value in Button(value) { selection.wrappedValue = value } }
        } label: {
            Text(selection.wrappedValue.isEmpty ? store.t(key) : selection.wrappedValue).font(.system(size: 10))
                .lineLimit(1).padding(.horizontal, 12).padding(.vertical, 9)
        }.menuStyle(.borderlessButton).prismaGlass(18).fixedSize()
    }
    private func albumGrid(limit: Int?) -> some View {
        let groups = store.groupedAlbums
        let width: CGFloat =
            store.preferences.albumSize == "small" ? 140 : store.preferences.albumSize == "large" ? 240 : 185
        return LazyVGrid(
            columns: limit == nil
                ? [GridItem(.adaptive(minimum: width), spacing: 16)]
                : Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 18
        ) {
            ForEach(groups.prefix(limit ?? groups.count), id: \.key) { group in
                if let track = group.value.first {
                    AlbumCard(
                        track: track, wide: limit != nil, action: { store.openAlbum(track) },
                        play: { store.playAlbum(track) }
                    ).contextMenu {
                        Button(store.t("openAlbum")) { store.openAlbum(track) }
                        Button(store.t("play")) { store.playAlbum(track) }
                        Button(store.t("reveal")) {
                            NSWorkspace.shared.activateFileViewerSelecting([track.url.deletingLastPathComponent()])
                        }
                    }
                }
            }
        }
    }
    private var artistGrid: some View {
        let groups = store.groupedArtists
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 18) {
            ForEach(groups, id: \.key) { group in
                ArtistGridTile(name: group.key, count: group.value.count, cover: group.value.first(where: \.hasArtwork))
            }
        }
    }
    private func songList(_ list: [Track]) -> some View {
        LibrarySongList(tracks: list) { store.displayIndex($0.id) + 1 }
    }

}
struct AlbumCard: View {
    @EnvironmentObject var store: LibraryStore
    var track: Track
    var wide = false
    var action: () -> Void
    var play: () -> Void
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: action) { ArtworkView(track: track).aspectRatio(1, contentMode: .fit) }.buttonStyle(.plain)
                .help(store.t("openAlbum"))
                .overlay(alignment: .bottomTrailing) {
                    Button(action: play) {
                        Image(systemName: "play.fill").font(.system(size: 12)).frame(width: 34, height: 34)
                    }.buttonStyle(.glass).buttonBorderShape(.circle).padding(10).help(store.t("play"))
                }
            Button(action: action) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.displayAlbum(track.album)).font(.system(size: 12, weight: .semibold))
                    HStack {
                        Text(store.displayArtist(AlbumIdentity.artist(track))).font(.system(size: 10)).foregroundStyle(
                            .secondary)
                        Spacer(minLength: 2)
                        Text(track.year).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                    }
                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle())
            }.buttonStyle(.plain)
        }.padding(10).prismaGlass(20).interactiveDepth()
    }
}
struct TrackContextMenu: View {
    @EnvironmentObject var store: LibraryStore
    var track: Track
    var edit: () -> Void
    var body: some View {
        Button(store.t("play")) { store.play(track, in: store.filtered) }
        Button(store.t("playNext")) { store.enqueue(track, next: true) }.disabled(track.id == store.currentID)
        Button(store.t("addQueue")) { store.enqueue(track) }.disabled(track.id == store.currentID)
        Divider()
        Menu(store.t("addToPlaylist")) {
            let manual = store.playlists.filter { $0.rules == nil }
            ForEach(manual) { playlist in Button(playlist.name) { store.add(track, to: playlist) } }
            if manual.isEmpty { Text(store.t("playlistEmpty")) }
        }
        if let playlist = store.activePlaylist, playlist.rules == nil {
            Button(store.t("removeFromPlaylist")) { store.removeFromPlaylist(track) }
        }
        Button(store.t("favorites")) { store.favorite(track) }
        Divider()
        Button(store.t("fileInfo")) {
            store.inspectedID = track.id
            store.showInfo = true
            store.showLyrics = false
            store.showQueue = false
        }
        Button(store.t("edit"), action: edit)
        Button(store.t("fetch")) { Task { await store.enrich(track) } }.disabled(store.fetching)
        Button(store.t("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([track.url]) }
    }
}
