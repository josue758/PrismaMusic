import AppKit
import SwiftUI

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
    @State private var editing: Track?
    @State private var newPlaylist = false
    @State private var playlistName = ""
    private var inspectorVisible: Bool { store.showInfo || store.showLyrics || store.showQueue }
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
                                }.id(pageKey).transition(.opacity)
                            }.frame(maxWidth: .infinity, maxHeight: .infinity).clipped().animation(
                                motion ? .smooth(duration: 0.3) : nil, value: pageKey)
                        }.frame(maxWidth: .infinity, maxHeight: .infinity)
                        if store.showInfo {
                            TrackInfoView().frame(width: 278).prismaGlass(24).transition(
                                motion ? .move(edge: .trailing).combined(with: .opacity) : .opacity)
                        }
                        if store.showLyrics {
                            LyricsView().frame(width: 278).prismaGlass(24).transition(
                                motion ? .move(edge: .trailing).combined(with: .opacity) : .opacity)
                        }
                        if store.showQueue {
                            QueueView().frame(width: 278).prismaGlass(24).transition(
                                motion ? .move(edge: .trailing).combined(with: .opacity) : .opacity)
                        }
                    }.frame(maxHeight: .infinity).animation(
                        motion ? .smooth(duration: 0.3) : nil, value: inspectorVisible)
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
        .frame(minWidth: inspectorVisible ? 1230 : 1060, minHeight: 720)
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
                            Button {
                                newPlaylist = true
                            } label: {
                                Image(systemName: "plus").font(.system(size: 11))
                            }.buttonStyle(.plain).help(store.t("newPlaylist"))
                        }.padding(.trailing, 10)
                        ForEach(store.playlists) { playlist in
                            Button {
                                store.navigateTo("playlist:\(playlist.id)")
                            } label: {
                                HStack(spacing: 10) {
                                    Image(systemName: "music.note").foregroundStyle(store.effectiveAccent.opacity(0.7))
                                    Text(playlist.name).lineLimit(1)
                                    Spacer()
                                    Text("\(playlist.trackIDs.count)").foregroundStyle(.tertiary)
                                }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 7).background(
                                    store.section == "playlist:\(playlist.id)"
                                        ? store.effectiveAccent.opacity(0.13) : .clear,
                                    in: RoundedRectangle(cornerRadius: 9))
                            }.buttonStyle(.plain).contextMenu {
                                Button(store.t("deletePlaylist"), role: .destructive) { store.removePlaylist(playlist) }
                            }
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
                            HStack(spacing: 9) {
                                Image(
                                    systemName: source.url.path.hasPrefix("/Volumes")
                                        ? "externaldrive.connected.to.line.below" : "folder"
                                ).foregroundStyle(store.effectiveAccent.opacity(0.8))
                                Text(source.name).lineLimit(1)
                                Spacer()
                            }.font(.system(size: 11)).padding(.horizontal, 12).padding(.vertical, 4).contextMenu {
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
        }.padding(14).frame(width: 224).frame(maxHeight: .infinity).prismaGlass(24)
    }
    private func sidebarLabel(_ key: String) -> some View {
        Text(store.t(key).uppercased()).font(.system(size: 8, weight: .semibold)).tracking(1.5).foregroundStyle(
            .tertiary
        ).padding(.horizontal, 12).padding(.bottom, 4)
    }
    private func nav(_ key: String, _ icon: String) -> some View {
        let selected = store.section == key && !store.showVisualizer
        return Button {
            withAnimation(motion ? .smooth(duration: 0.3) : nil) {
                store.navigateTo(key)
            }
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
            }.padding(.horizontal, 13).frame(width: inspectorVisible ? 190 : 255, height: 36).prismaGlass(22)
            GlassEffectContainer(spacing: 7) {
                HStack(spacing: 7) {
                    GlassIconButton(icon: "waveform.path", label: store.t("visualizer"), active: store.showVisualizer) {
                        store.showVisualizer.toggle()
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
                            collectionStats
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
                    Task { await store.scan() }
                } label: {
                    Image(systemName: "arrow.clockwise").font(.system(size: 10))
                }.buttonStyle(.plain).disabled(store.scanning).help(store.t("scan"))
                Text("PRISMA / " + AppVersion.current).font(.system(size: 8, design: .monospaced)).tracking(1)
                    .foregroundStyle(.tertiary)
            }.padding(.horizontal, 4)
        }.frame(maxWidth: .infinity, maxHeight: .infinity)
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
            if !store.artist.isEmpty || !store.genre.isEmpty || !store.year.isEmpty {
                Button {
                    store.clearFilters()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }.buttonStyle(.plain).help(store.t("clear"))
            }
        }
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
            ForEach(Array(groups.prefix(limit ?? groups.count)), id: \.key) { group in
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
            ForEach(store.playlists) { playlist in Button(playlist.name) { store.add(track, to: playlist) } }
            if store.playlists.isEmpty { Text(store.t("playlistEmpty")) }
        }
        if store.section.hasPrefix("playlist:") {
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
struct QueueView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                SectionHeading(title: store.t("queue"))
                Spacer()
                Button {
                    store.showQueue = false
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain)
            }
            HStack {
                Text(store.t("upNext")).font(.system(size: 8, weight: .medium)).tracking(1.5)
                Spacer()
                Text("\(store.queue.count)").font(.system(size: 10, design: .monospaced))
            }.foregroundStyle(.secondary)
            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(store.queue, id: \.self) { id in
                        if let track = store.track(for: id), let index = store.queueIndex(id) {
                            VStack(spacing: 9) {
                                HStack(spacing: 10) {
                                    ArtworkView(track: track).frame(width: 38, height: 38)
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(track.title).font(.system(size: 11, weight: .medium)).foregroundStyle(
                                            track.id == store.currentID ? store.effectiveAccent : .primary)
                                        Text(track.artist).font(.system(size: 9)).foregroundStyle(.secondary)
                                    }.lineLimit(1)
                                    Spacer(minLength: 0)
                                    Button {
                                        store.play(track)
                                    } label: {
                                        Image(
                                            systemName: track.id == store.currentID && store.isPlaying
                                                ? "waveform" : "play.fill"
                                        ).font(.system(size: 10))
                                    }.buttonStyle(.plain).help(store.t("play"))
                                }
                                HStack(spacing: 15) {
                                    Text(String(format: "%02d / %@", index + 1, clockText(track.duration))).font(
                                        .system(size: 8, design: .monospaced)
                                    ).foregroundStyle(.tertiary)
                                    Spacer()
                                    Button {
                                        store.moveQueued(track, direction: -1)
                                    } label: {
                                        Image(systemName: "arrow.up")
                                    }.disabled(index == 0).help(store.t("moveUp"))
                                    Button {
                                        store.moveQueued(track, direction: 1)
                                    } label: {
                                        Image(systemName: "arrow.down")
                                    }.disabled(index == store.queue.count - 1).help(store.t("moveDown"))
                                    Button {
                                        store.removeQueued(track)
                                    } label: {
                                        Image(systemName: "xmark")
                                    }.disabled(track.id == store.currentID).help(store.t("remove"))
                                }.buttonStyle(.plain).font(.system(size: 9))
                            }.padding(12).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 15))
                        }
                    }
                }
            }.scrollIndicators(.hidden).clipped()
            if store.queue.isEmpty {
                Text(store.t("queueEmpty")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            }
            Button {
                store.openSettings("playback")
            } label: {
                Label(store.t("playback"), systemImage: "slider.horizontal.3").font(.caption)
            }.buttonStyle(.glass)
        }.padding(18).padding(.top, 5)
    }
}
