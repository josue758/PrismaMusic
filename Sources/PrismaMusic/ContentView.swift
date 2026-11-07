import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.colorScheme) var scheme
    @State private var settings = false
    @State private var nas = false
    @State private var editing: Track?
    var body: some View {
        ZStack {
            (scheme == .dark ? Color(red: 0.045, green: 0.045, blue: 0.075) : Color(red: 0.95, green: 0.95, blue: 0.98)).ignoresSafeArea()
            GeometryReader { proxy in
                Ellipse().fill(store.accent.color.opacity(scheme == .dark ? 0.16 : 0.12)).frame(width: 600, height: 450).blur(radius: 120).offset(x: proxy.size.width * 0.45, y: -200)
            }.allowsHitTesting(false)
            VStack(spacing: 0) {
                HStack(spacing: 0) {
                    sidebar
                    VStack(spacing: 0) {
                        toolbar
                        if store.showVisualizer {
                            VisualizerView().padding(22)
                        } else {
                            library
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity)
                    if store.showInfo { TrackInfoView().frame(width: 282).background(.ultraThinMaterial) }
                    if store.showLyrics { LyricsView().frame(width: 282).background(.ultraThinMaterial) }
                }
                PlayerBar().padding(14).glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24)).padding(.horizontal, 14).padding(.bottom, 14)
            }
        }
        .sheet(isPresented: $settings) { SettingsView().environmentObject(store).frame(width: 520) }
        .sheet(isPresented: $nas) { NASView().environmentObject(store) }
        .sheet(item: $editing) { track in TagEditor(track: track).environmentObject(store) }
        .alert("Prisma Music", isPresented: Binding(get: { store.error != nil }, set: { if !$0 { store.error = nil } })) { Button("OK") { store.error = nil } } message: { Text(store.error ?? "") }
    }
    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 26) {
            HStack(spacing: 10) {
                Image(systemName: "waveform.path").font(.system(size: 23, weight: .bold)).foregroundStyle(store.accent.color)
                VStack(alignment: .leading, spacing: 0) { Text("PRISMA").font(.system(size: 17, weight: .heavy, design: .rounded)).tracking(3); Text("MUSIC").font(.system(size: 9, weight: .medium)).tracking(5).foregroundStyle(.secondary) }
            }.padding(.top, 50).padding(.leading, 12)
            VStack(alignment: .leading, spacing: 6) {
                Text(store.t("library").uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary).padding(.horizontal, 14).padding(.bottom, 8)
                nav("songs", "music.note.list")
                nav("albums", "square.stack")
                nav("artists", "person.2")
                nav("favorites", "heart")
            }
            VStack(alignment: .leading, spacing: 10) {
                HStack { Text(store.t("sources").uppercased()).font(.system(size: 10, weight: .semibold)).tracking(2).foregroundStyle(.secondary); Spacer(); Button { store.pickMusic() } label: { Image(systemName: "plus") }.buttonStyle(.plain).help(store.t("add")).disabled(store.scanning) }.padding(.horizontal, 14)
                ForEach(store.sources) { source in
                    HStack(spacing: 9) { Image(systemName: source.url.path.hasPrefix("/Volumes") ? "externaldrive.connected.to.line.below" : "folder").foregroundStyle(store.accent.color); Text(source.name).lineLimit(1).font(.system(size: 12)); Spacer() }
                        .padding(.horizontal, 14).padding(.vertical, 5)
                        .contextMenu { Button(store.t("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([source.url]) }; Button(store.t("removeSource"), role: .destructive) { store.removeSource(source) }.disabled(store.scanning) }
                }
                Button { nas = true } label: { Label(store.t("connect"), systemImage: "network").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(.secondary).padding(.horizontal, 14)
            }
            Spacer()
            VStack(alignment: .leading, spacing: 9) {
                HStack(spacing: 6) { Circle().fill(store.scanning ? .orange : .mint).frame(width: 5, height: 5); Text(store.scanning ? store.t("reading") : store.t("localAudio")).font(.system(size: 9, weight: .semibold)).tracking(1) }
                Button { settings = true } label: { Label(store.t("settings"), systemImage: "slider.horizontal.3").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(.secondary)
            }.padding(14)
        }.padding(.horizontal, 12).padding(.bottom, 8).frame(width: 202).background(.ultraThinMaterial)
    }
    private func nav(_ key: String, _ icon: String) -> some View {
        Button { store.section = key; store.showVisualizer = false; store.clearFilters() } label: {
            HStack(spacing: 12) { Image(systemName: icon).frame(width: 18); Text(store.t(key)).font(.system(size: 13, weight: store.section == key ? .semibold : .regular)); Spacer(); if key == "songs" { Text("\(store.tracks.count)").font(.system(size: 11)).foregroundStyle(.secondary) } }.padding(.horizontal, 14).padding(.vertical, 11)
                .background(store.section == key && !store.showVisualizer ? store.accent.color.opacity(0.17) : .clear, in: RoundedRectangle(cornerRadius: 12))
                .foregroundStyle(store.section == key ? store.accent.color : .primary)
        }.buttonStyle(.plain)
    }
    private var toolbar: some View {
        HStack(spacing: 12) {
            HStack { Image(systemName: "magnifyingglass").foregroundStyle(.secondary); TextField(store.t("search"), text: $store.search).textFieldStyle(.plain); if !store.search.isEmpty { Button { store.search = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) } }.padding(10).background(.quaternary.opacity(0.45), in: Capsule()).frame(maxWidth: 400)
            Spacer(minLength: 0)
            iconButton("arrow.clockwise", store.t("scan")) { Task { await store.scan() } }.disabled(store.scanning)
            iconButton("waveform.path", store.t("visualizer"), selected: store.showVisualizer) { store.showVisualizer.toggle() }
            iconButton("quote.bubble", store.t("lyrics"), selected: store.showLyrics) { store.showLyrics.toggle(); store.showInfo = false }
            iconButton("info.circle", store.t("fileInfo"), selected: store.showInfo) { store.inspectedID = nil; store.showInfo.toggle(); store.showLyrics = false }
            iconButton("pip", store.t("mini")) { store.miniPlayer() }
            iconButton("arrow.up.left.and.arrow.down.right", store.t("full")) { store.fullScreen() }
        }.padding(.horizontal, 28).padding(.top, 30).padding(.bottom, 20)
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(store.t("tagline")).font(.system(size: 10, weight: .semibold)).tracking(2.5).foregroundStyle(store.accent.color)
                    Text(store.t(store.section)).font(.system(size: 34, weight: .bold, design: .rounded))
                    Text("\(store.filtered.count) \(store.t("count")) · \(clockText(store.filtered.reduce(0) { $0 + $1.duration }))").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Button { store.pickMusic() } label: { Label(store.t("add"), systemImage: "plus").padding(.horizontal, 5).padding(.vertical, 3) }.buttonStyle(.glassProminent).disabled(store.scanning)
            }
            filterBar
            if store.tracks.isEmpty {
                ContentUnavailableView { Label(store.t("empty"), systemImage: "music.note.house") } description: { Text(store.t("emptyNote")) } actions: { Button(store.t("add")) { store.pickMusic() }.buttonStyle(.glassProminent) }.frame(maxHeight: .infinity)
            } else if store.filtered.isEmpty {
                ContentUnavailableView { Label(store.t("noResults"), systemImage: "magnifyingglass") } actions: { Button(store.t("clear")) { store.clearFilters() } }.frame(maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 22) {
                        if store.section == "songs" && store.search.isEmpty && store.artist.isEmpty && store.genre.isEmpty && store.year.isEmpty {
                            if store.tracks.allSatisfy(\.isDemo) {
                                VStack(alignment: .leading, spacing: 5) { Text(store.t("demo")).font(.system(size: 13, weight: .semibold)); Text(store.t("demoNote")).font(.system(size: 11)).foregroundStyle(.secondary) }
                            }
                            albumGrid(limit: 3)
                        }
                        if store.section == "albums" { albumGrid(limit: nil) }
                        else if store.section == "artists" { artistGrid }
                        else { songList }
                    }.padding(.bottom, 10)
                }
            }
            HStack(spacing: 7) { if store.scanning { ProgressView().controlSize(.mini) }; Text(store.status).lineLimit(2).font(.system(size: 10)).foregroundStyle(.secondary); Spacer(); Text("PRISMA / 01").font(.system(size: 9, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary) }.frame(minHeight: 14)
        }.padding(.horizontal, 28).padding(.bottom, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
    private var filterBar: some View {
        HStack(spacing: 8) {
            filterMenu("allArtists", selection: $store.artist, values: Array(Set(store.tracks.map(\.artist))).sorted())
            filterMenu("allGenres", selection: $store.genre, values: Array(Set(store.tracks.map(\.genre))).sorted())
            filterMenu("allYears", selection: $store.year, values: Array(Set(store.tracks.map(\.year).filter { !$0.isEmpty })).sorted().reversed())
            Spacer(minLength: 0)
            Menu { Picker(store.t("sort"), selection: $store.sort) { ForEach(["title", "artist", "album", "year"], id: \.self) { Text(store.t($0)).tag($0) } } } label: { Image(systemName: "arrow.up.arrow.down") }.menuStyle(.borderlessButton).fixedSize().help(store.t("sort"))
            if !store.artist.isEmpty || !store.genre.isEmpty || !store.year.isEmpty { Button { store.clearFilters() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).help(store.t("clear")) }
        }
    }
    private func filterMenu(_ label: String, selection: Binding<String>, values: [String]) -> some View {
        Menu { Button(store.t(label)) { selection.wrappedValue = "" }; Divider(); ForEach(values, id: \.self) { value in Button(value) { selection.wrappedValue = value } } } label: { HStack(spacing: 6) { Text(selection.wrappedValue.isEmpty ? store.t(label) : selection.wrappedValue).lineLimit(1); Image(systemName: "chevron.down").font(.system(size: 8, weight: .bold)) }.font(.system(size: 11)).padding(.horizontal, 11).padding(.vertical, 8).background(selection.wrappedValue.isEmpty ? Color.primary.opacity(0.045) : store.accent.color.opacity(0.15), in: Capsule()) }.menuStyle(.borderlessButton).fixedSize(horizontal: false, vertical: true)
    }
    private func albumGrid(limit: Int?) -> some View {
        let groups = Dictionary(grouping: store.filtered) { $0.artist + "\u{1f}" + $0.album }.sorted { $0.key < $1.key }
        return LazyVGrid(columns: limit == nil ? [GridItem(.adaptive(minimum: 160), spacing: 18)] : Array(repeating: GridItem(.flexible(), spacing: 18), count: min(3, max(1, groups.count))), alignment: .leading, spacing: 20) {
            ForEach(Array(groups.prefix(limit ?? groups.count)), id: \.key) { group in
                if let track = group.value.first {
                    Button { store.play(track, in: group.value.sorted { $0.title < $1.title }) } label: {
                        VStack(alignment: .leading, spacing: 10) {
                            ArtworkView(track: track).aspectRatio(limit == nil ? 1 : 1.5, contentMode: .fit).overlay(alignment: .bottomTrailing) { Image(systemName: "play.fill").font(.system(size: 14)).padding(13).glassEffect(.regular, in: Circle()).padding(12) }
                            Text(track.album).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                            Text(track.artist + (track.year.isEmpty ? "" : " · " + track.year)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                        }.contentShape(Rectangle())
                    }.buttonStyle(.plain).contextMenu { Button(store.t("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([track.url]) } }
                }
            }
        }
    }
    private var artistGrid: some View {
        let groups = Dictionary(grouping: store.filtered, by: \.artist).sorted { $0.key < $1.key }
        return LazyVGrid(columns: [GridItem(.adaptive(minimum: 160))], spacing: 20) {
            ForEach(groups, id: \.key) { group in
                Button { store.artist = group.key; store.section = "songs" } label: {
                    VStack(spacing: 12) { ArtworkView(track: group.value.first).clipShape(Circle()).frame(width: 110, height: 110); Text(group.key).font(.headline); Text("\(group.value.count) \(store.t("count"))").font(.caption).foregroundStyle(.secondary) }.padding(20).frame(maxWidth: .infinity)
                }.buttonStyle(.plain)
            }
        }
    }
    private var songList: some View {
        LazyVStack(spacing: 0) {
            HStack { Text("#").frame(width: 24); Text(store.t("title")).frame(maxWidth: .infinity, alignment: .leading); Text(store.t("album")).frame(width: 130, alignment: .leading); Text(store.t("year")).frame(width: 45); Image(systemName: "clock").frame(width: 44); Text("").frame(width: 24) }.font(.system(size: 10, weight: .medium)).foregroundStyle(.tertiary).padding(.horizontal, 10).padding(.bottom, 10)
            ForEach(Array(store.filtered.enumerated()), id: \.element.id) { index, track in
                HStack(spacing: 10) {
                    Button { store.play(track, in: store.filtered) } label: { Group { if store.currentID == track.id && store.isPlaying { Image(systemName: "waveform").foregroundStyle(store.accent.color) } else { Text(String(format: "%02d", index + 1)).foregroundStyle(.tertiary) } }.font(.system(size: 11, design: .monospaced)).frame(width: 24, height: 40) }.buttonStyle(.plain).help(store.t("play"))
                    ArtworkView(track: track).frame(width: 36, height: 36).clipShape(RoundedRectangle(cornerRadius: 7))
                    VStack(alignment: .leading, spacing: 4) { Text(track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(store.currentID == track.id ? store.accent.color : .primary); Text(track.artist + (track.qualitySummary.isEmpty ? "" : " · " + track.qualitySummary)).font(.system(size: 10)).foregroundStyle(.secondary) }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                    Text(track.album).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(width: 130, alignment: .leading)
                    Text(track.year).font(.system(size: 10)).foregroundStyle(.tertiary).frame(width: 45)
                    Text(clockText(track.duration)).monospacedDigit().font(.system(size: 10)).foregroundStyle(.secondary).frame(width: 44)
                    Button { store.favorite(track) } label: { Image(systemName: track.favorite ? "heart.fill" : "heart").foregroundStyle(track.favorite ? store.accent.color : Color.secondary.opacity(0.5)) }.buttonStyle(.plain).frame(width: 24).help(store.t("favorites"))
                }.padding(.horizontal, 10).padding(.vertical, 8).background(index % 2 == 0 ? Color.primary.opacity(0.025) : .clear, in: RoundedRectangle(cornerRadius: 10)).contentShape(Rectangle())
                    .onTapGesture(count: 2) { store.play(track, in: store.filtered) }
                    .contextMenu { Button(store.t("play")) { store.play(track, in: store.filtered) }; Button(store.t("fileInfo")) { store.inspectedID = track.id; store.showInfo = true; store.showLyrics = false }; Button(store.t("edit")) { editing = track }; Button(store.t("fetch")) { Task { await store.enrich(track) } }; Button(store.t("reveal")) { NSWorkspace.shared.activateFileViewerSelecting([track.url]) } }
            }
        }
    }
    private func iconButton(_ icon: String, _ help: String, selected: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13)).foregroundStyle(selected ? store.accent.color : .secondary).frame(width: 26, height: 28) }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }
}
