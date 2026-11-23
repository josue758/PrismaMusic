import SwiftUI

struct AlbumDetailView: View {
    @EnvironmentObject var store: LibraryStore
    var id: String
    @State private var ordering = false
    @State private var editingAlbum = false
    private var album: AlbumCollection? { store.albumCollection(id) }
    private var reveal: LibraryStore.AlbumTrackReveal? {
        guard store.albumTrackReveal?.trackID == id else { return nil }
        return store.albumTrackReveal
    }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                if let album {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(alignment: .bottom, spacing: 26) {
                            ArtworkView(track: album.tracks.first).frame(width: 208, height: 208).shadow(
                                color: .black.opacity(0.18), radius: 18, y: 10)
                            VStack(alignment: .leading, spacing: 16) {
                                Text(store.t("albumInLibrary").uppercased()).font(
                                    .system(size: 9, weight: .semibold, design: .monospaced)
                                ).tracking(2).foregroundStyle(store.effectiveAccent)
                                HStack(spacing: 12) {
                                    Text(store.displayAlbum(album.title)).font(
                                        .system(size: 34, weight: .bold, design: .rounded)
                                    ).lineLimit(3).minimumScaleFactor(0.7)
                                    Button {
                                        editingAlbum = true
                                    } label: {
                                        Image(systemName: "pencil").frame(width: 20, height: 20)
                                    }.buttonStyle(.glass)
                                        .help(store.t("editAlbum"))
                                        .accessibilityLabel(store.t("editAlbum"))
                                }
                                HStack {
                                    ForEach(ArtistIdentity.names(album.artist), id: \.self) { name in
                                        Button(store.displayArtist(name)) { store.openArtist(name) }.buttonStyle(.plain)
                                            .foregroundStyle(store.effectiveAccent)
                                    }
                                }.font(.callout)
                                Text(
                                    [
                                        album.genres.joined(separator: ", "), album.year,
                                        store.songCountText(album.tracks.count),
                                        collectionTimeText(album.duration),
                                    ].filter { !$0.isEmpty }.joined(separator: " · ")
                                ).font(.caption).foregroundStyle(.secondary)
                                HStack {
                                    Button {
                                        if let first = album.tracks.first { store.playAlbum(first) }
                                    } label: {
                                        Label(store.t("play"), systemImage: "play.fill")
                                    }.buttonStyle(.glassProminent)
                                    Button {
                                        if let first = album.tracks.first { store.playAlbum(first, shuffled: true) }
                                    } label: {
                                        Label(store.t("shuffle"), systemImage: "shuffle")
                                    }.buttonStyle(.glass)
                                    Button {
                                        store.exportPlaylist(album.tracks)
                                    } label: {
                                        Image(systemName: "square.and.arrow.up")
                                    }.buttonStyle(.glass).help(store.t("exportPlaylist"))
                                        .accessibilityLabel(store.t("exportPlaylist"))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                        }.padding(24).frame(maxWidth: .infinity, alignment: .leading).prismaGlass(26, tinted: true)
                        HStack {
                            SectionHeading(title: store.t("songs"))
                            Spacer()
                            if ordering {
                                ProgressView().controlSize(.small)
                                Text(store.t("readingAlbumOrder")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                        if !ordering, album.tracks.contains(where: { $0.trackNumber == nil }) {
                            Text(store.t("albumOrderFallback")).font(.caption2).foregroundStyle(.secondary)
                        }
                        LibrarySongList(tracks: album.tracks, showAlbum: false, reveal: reveal) {
                            (album.indices[$0.id] ?? 0) + 1
                        }
                    }.padding(4).padding(.bottom, 24)
                } else {
                    ContentUnavailableView(store.t("albumUnavailable"), systemImage: "square.stack")
                    Button(store.t("albums")) {
                        store.navigateTo("albums")
                    }
                }
            }.scrollIndicators(.hidden)
                .onChange(of: reveal, initial: true) { _, request in
                    if let request { reader.scrollTo(request.trackID, anchor: .center) }
                }
        }
        .sheet(isPresented: $editingAlbum) {
            if let album { AlbumEditor(id: id, album: album).environmentObject(store) }
        }
        .task(id: id) {
            ordering = true
            await store.readAlbumOrder(id)
            if !Task.isCancelled { ordering = false }
        }
    }
}
