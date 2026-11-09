import AppKit
import SwiftUI

struct ArtistDetailView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let name: String
    @State private var profile: ArtistProfile?
    @State private var portrait: NSImage?
    @State private var artistPalette = ArtworkPalette.fallback()
    @State private var fetching = false
    @State private var failed = false
    @State private var retry = 0
    @State private var changingPhoto = false
    private var collection: ArtistCollection { store.artistCollection(name) }
    private var tracks: [Track] { collection.tracks }
    private var albums: [(key: String, value: [Track])] { collection.albums }
    private var songs: [Track] { tracks }
    private var requestKey: String {
        name + ":" + store.language.rawValue + ":" + String(store.online) + ":" + String(retry)
    }
    var body: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 24) {
                    HStack {
                        Spacer()
                        if fetching { ProgressView().controlSize(.small) }
                        if (profile?.photos?.count ?? 0) > 1 {
                            Button {
                                changingPhoto = true
                            } label: {
                                Label(store.t("changePhoto"), systemImage: "photo.on.rectangle.angled")
                            }.buttonStyle(.glass)
                        }
                    }
                    hero
                    HStack(spacing: 12) {
                        metric(String(albums.count), "albums")
                        metric(String(tracks.count), "songs")
                        metric(collectionTimeText(collection.duration), "duration")
                    }
                    biography
                    if !albums.isEmpty {
                        SectionHeading(title: store.t("artistAlbums"))
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 16)], spacing: 16) {
                            ForEach(albums, id: \.key) { album in
                                VStack(alignment: .leading, spacing: 10) {
                                    Button {
                                        if let first = album.value.first { store.openAlbum(first) }
                                    } label: {
                                        ArtworkView(track: album.value.first).aspectRatio(1, contentMode: .fit)
                                    }.buttonStyle(.plain).help(store.t("viewAlbumSongs")).accessibilityLabel(
                                        store.t("viewAlbumSongs") + ": "
                                            + store.displayAlbum(album.value.first?.album ?? ""))
                                    HStack {
                                        VStack(alignment: .leading, spacing: 4) {
                                            Button {
                                                if let first = album.value.first { store.openAlbum(first) }
                                            } label: {
                                                Text(store.displayAlbum(album.value.first?.album ?? "")).font(
                                                    .system(size: 12, weight: .semibold)
                                                ).lineLimit(2)
                                            }.buttonStyle(.plain)
                                            Text(
                                                [album.value.first?.year ?? "", store.songCountText(album.value.count)]
                                                    .filter { !$0.isEmpty }.joined(separator: " · ")
                                            ).font(.caption2).foregroundStyle(.secondary)
                                        }
                                        Spacer(minLength: 0)
                                        Button {
                                            if let first = album.value.first { store.playAlbum(first) }
                                        } label: {
                                            Image(systemName: "play.fill").frame(width: 24, height: 24)
                                        }.buttonStyle(.glass).help(store.t("play"))
                                    }
                                }.padding(12).prismaGlass(20)
                            }
                        }
                    }
                    HStack {
                        SectionHeading(title: store.t("artistSongs"))
                    }.id("artist-songs")
                    LibrarySongList(tracks: songs, showAlbum: false, subtitleAlbum: true) { track in
                        (collection.indices[track.id] ?? 0) + 1
                    }

                }.padding(4).padding(.bottom, 20)
            }.scrollIndicators(.hidden)
                .task(id: requestKey) { await load() }
                .sheet(isPresented: $changingPhoto) {
                    ArtistPhotoPicker(name: name, photos: profile?.photos ?? [], selected: profile?.photoURL) {
                        await choosePhoto($0)
                    }.environmentObject(store)
                }
        }
    }
    private var hero: some View {
        GeometryReader { geo in
            ZStack(alignment: .bottomLeading) {
                LinearGradient(
                    colors: [
                        artistPalette.colors[0].opacity(0.9), artistPalette.colors[1].opacity(0.5), .black.opacity(0.6),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                if let portrait {
                    Image(nsImage: portrait).resizable().scaledToFill().frame(width: geo.size.width, height: 320).blur(
                        radius: 24
                    ).opacity(0.6).clipped().accessibilityHidden(true)
                    HStack(spacing: 0) {
                        Spacer(minLength: 0)
                        Image(nsImage: portrait).resizable().aspectRatio(contentMode: .fit)
                            .frame(
                                width: min(
                                    max(260, geo.size.width * 0.54),
                                    320 * portrait.size.width / max(1, portrait.size.height)), height: 320
                            ).clipped()
                            .mask(
                                LinearGradient(
                                    stops: [
                                        .init(color: .clear, location: 0), .init(color: .white, location: 0.2),
                                        .init(color: .white, location: 0.85), .init(color: .clear, location: 1),
                                    ], startPoint: .leading, endPoint: .trailing))
                    }.accessibilityLabel(name)
                } else if let cover = collection.cover {
                    ArtworkView(track: cover)
                        .frame(width: 270, height: 270)
                        .frame(maxWidth: .infinity, alignment: .trailing)
                        .padding(.trailing, 25)
                        .accessibilityHidden(true)
                } else {
                    Text(name.split(separator: " ").prefix(2).compactMap(\.first).map(String.init).joined()).font(
                        .system(size: 150, weight: .ultraLight, design: .rounded)
                    ).foregroundStyle(.white.opacity(0.12)).frame(maxWidth: .infinity, alignment: .trailing).padding(
                        .trailing, 36
                    ).accessibilityHidden(true)
                }
                LinearGradient(
                    stops: [
                        .init(color: .black.opacity(0.72), location: 0),
                        .init(color: .black.opacity(0.35), location: 0.5), .init(color: .clear, location: 0.9),
                    ], startPoint: .leading, endPoint: .trailing)
                LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom)
                VStack(alignment: .leading, spacing: 16) {
                    Text(store.t("artistProfile").uppercased()).font(
                        .system(size: 9, weight: .semibold, design: .monospaced)
                    ).tracking(2).foregroundStyle(.white.opacity(0.75))
                    Text(store.displayArtist(name)).font(.system(size: 44, weight: .bold, design: .rounded))
                        .foregroundStyle(.white).lineLimit(2).minimumScaleFactor(0.65)
                    Text(collection.genres).font(.callout).foregroundStyle(.white.opacity(0.75)).lineLimit(2)
                    HStack(spacing: 12) {
                        Button {
                            store.shuffle = false
                            if let first = tracks.first { store.play(first, in: tracks) }
                        } label: {
                            Label(store.t("play"), systemImage: "play.fill").padding(.horizontal, 6).padding(
                                .vertical, 4)
                        }.buttonStyle(.glassProminent).disabled(tracks.isEmpty)
                        Button {
                            store.shuffle = true
                            if let first = tracks.randomElement() { store.play(first, in: tracks) }
                        } label: {
                            Label(store.t("shuffle"), systemImage: "shuffle").padding(.horizontal, 4).padding(
                                .vertical, 4)
                        }.buttonStyle(.glass).disabled(tracks.isEmpty)
                    }.tint(artistPalette.primary.readable(onDark: true).color)
                }.padding(28).frame(width: geo.size.width * 0.68, alignment: .leading)
            }.frame(width: geo.size.width, height: 320).clipped().clipShape(RoundedRectangle(cornerRadius: 28))
                .overlay(alignment: .topTrailing) {
                    if portrait != nil, let url = profile?.photoPageURL {
                        Link(destination: url) {
                            Label("Wikimedia", systemImage: "camera").font(.system(size: 9)).foregroundStyle(
                                .white.opacity(0.8)
                            ).padding(8).background(.black.opacity(0.3), in: Capsule())
                        }.padding(16)
                    } else if portrait == nil, collection.cover != nil {
                        Label(store.t("artistCoverFallback"), systemImage: "square.stack")
                            .font(.caption2).padding(8).background(.black.opacity(0.6), in: Capsule())
                            .foregroundStyle(.white).padding(16)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 28).strokeBorder(.white.opacity(0.14), lineWidth: 0.7) }
        }.frame(height: 320).prismaGlass(28)
            .animation(
                reduceMotion || !store.preferences.microInteractions ? nil : .easeInOut(duration: 0.45),
                value: portrait != nil)
    }
    private func metric(_ value: String, _ key: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(value).font(.system(size: 21, weight: .medium, design: .rounded))
            Text(store.t(key)).font(.caption).foregroundStyle(.secondary)
        }.padding(18).frame(maxWidth: .infinity, alignment: .leading).prismaGlass(18)
    }
    private var biography: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeading(title: store.t("biography"))
            if let profile {
                Text(profile.biography).font(.system(size: 13)).lineSpacing(5).textSelection(.enabled)
                HStack {
                    Link("Wikipedia · \(profile.language.uppercased()) ↗", destination: profile.pageURL)
                    Link("CC BY-SA ↗", destination: URL(string: "https://creativecommons.org/licenses/by-sa/4.0/")!)
                }.font(.caption)
                if let url = profile.photoPageURL, portrait != nil {
                    Link(
                        "\(store.t("photoCredit")): \(String((profile.photoCredit ?? "Wikimedia Commons").prefix(180))) · \(profile.photoLicense ?? "") ↗",
                        destination: url
                    ).font(.caption2)
                }
            } else {
                Text(
                    store.t(
                        !store.online
                            ? "artistOffline"
                            : fetching ? "artistFetching" : failed ? "artistFetchFailed" : "artistNoMatch")
                ).font(.callout).foregroundStyle(.secondary)
                if !collection.years.isEmpty {
                    LabeledContent(store.t("artistLibraryYears"), value: collection.years).font(.caption)
                }
                if store.online && !fetching { Button(store.t("retry")) { retry += 1 }.buttonStyle(.glass) }
                if !store.online { Button(store.t("settings")) { store.openSettings("metadata") }.buttonStyle(.glass) }
            }
            Text(store.t("artistPrivacy")).font(.caption2).foregroundStyle(.secondary)
        }.padding(22).frame(maxWidth: .infinity, alignment: .leading).prismaGlass(22)
    }
    @MainActor private func load() async {
        let request = requestKey
        profile = nil
        portrait = nil
        failed = false
        guard store.online else {
            fetching = false
            return
        }
        fetching = true
        defer { if requestKey == request { fetching = false } }
        do {
            var result = try await ArtistProfileService.shared.profile(name: name, language: store.language.rawValue)
            if let saved = await store.artistPhotoStore.choice(for: name) { result?.usePhoto(saved) }
            try Task.checkCancellation()
            profile = result
            if let url = result?.photoURL { try await renderPhoto(url) }
        } catch { if !Task.isCancelled { failed = true } }
    }
    @MainActor private func renderPhoto(_ url: URL, source: URL? = nil) async throws {
        let data = try await ArtistPhotoNetwork.data(url)
        let album = name
        let result = await Task.detached(priority: .utility) { ArtistPortraitRenderer.prepare(data, album: album) }
            .value
        try Task.checkCancellation()
        if let result {
            portrait = result.image
            artistPalette = result.palette
            ArtistPortraitCache.shared.remember(name, image: result.thumbnail, source: source ?? profile?.photoPageURL)
        }
    }
    @MainActor private func choosePhoto(_ photo: ArtistPhotoChoice) async {
        do {
            try await renderPhoto(photo.url, source: photo.pageURL)
            profile?.usePhoto(photo)
            try await store.artistPhotoStore.select(photo, for: name)
        } catch { if !Task.isCancelled { store.error = error.localizedDescription } }
    }

}
