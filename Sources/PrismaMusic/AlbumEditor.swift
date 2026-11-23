import SwiftUI
import UniformTypeIdentifiers

struct AlbumEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let id: String
    @State private var values: [TagField: String]
    @State private var savedValues: [TagField: String]
    @State private var selectingImage = false
    @State private var artworkBusy = false
    @State private var trackToEdit: Track?
    @State private var batchTracks: [Track] = []
    @State private var showBatch = false

    private static let fields: [TagField] = [.album, .albumArtist, .year]
    private var collection: AlbumCollection? { store.albumCollection(id) }
    private var changes: [TagField: String] {
        values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter {
            $0.value != savedValues[$0.key]
        }
    }

    init(id: String, album: AlbumCollection) {
        self.id = id
        let metadata: [TagField: String] = [.album: album.title, .albumArtist: album.artist, .year: album.year]
        _values = State(initialValue: metadata)
        _savedValues = State(initialValue: metadata)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("editAlbum"), systemImage: "pencil").font(.title2.bold())
            if let collection {
                HStack(alignment: .top, spacing: 20) {
                    ArtworkView(track: collection.tracks.first).frame(width: 110, height: 110)
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Self.fields) { field in
                            HStack {
                                Text(store.t(field.rawValue)).frame(width: 140, alignment: .leading)
                                TextField(
                                    store.t(field.rawValue),
                                    text: Binding(
                                        get: { values[field] ?? "" },
                                        set: { values[field] = $0 }
                                    )
                                ).labelsHidden().textFieldStyle(.roundedBorder)
                            }
                        }
                        Text(store.t("tagNote")).font(.caption).foregroundStyle(.secondary)
                        Button(store.t("saveAlbumInfo")) {
                            store.applyTagEdits(
                                ids: collection.tracks.map(\.id), changes: changes, carryAlbumArtwork: true)
                            savedValues = values.mapValues { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                        }.buttonStyle(.glassProminent)
                            .disabled(
                                changes.isEmpty || !changes.allSatisfy { $0.key.isValid($0.value) }
                                    || store.scanning || store.writingFileTags || artworkBusy)
                    }
                }
                HStack {
                    Button(store.t("chooseAlbumArtwork")) { selectingImage = true }
                    if collection.tracks.contains(where: { $0.albumArtworkURL != nil }) {
                        Button(store.t("restoreAlbumArtwork")) { setArtwork(nil) }
                    }
                    if artworkBusy { ProgressView().controlSize(.small) }
                }.buttonStyle(.glass).disabled(artworkBusy)

                Divider()
                HStack {
                    Text(store.t("songs")).font(.headline)
                    Spacer()
                    Button(store.t("batchTags")) {
                        batchTracks = collection.tracks
                        showBatch = true
                    }.disabled(store.scanning || store.writingFileTags)
                }
                ScrollView {
                    LazyVStack(spacing: 4) {
                        ForEach(collection.tracks) { track in
                            Button {
                                trackToEdit = track
                            } label: {
                                HStack {
                                    Text(track.trackNumber.map(String.init) ?? "—")
                                        .monospacedDigit().foregroundStyle(.secondary).frame(width: 26)
                                    VStack(alignment: .leading, spacing: 3) {
                                        Text(track.title).lineLimit(1)
                                        Text(store.displayArtist(track.artist)).font(.caption).foregroundStyle(
                                            .secondary)
                                    }
                                    Spacer()
                                    Image(systemName: "pencil")
                                }.padding(8).contentShape(Rectangle())
                            }.buttonStyle(.plain)
                                .accessibilityHint(store.t("editAlbumTrack"))
                        }
                    }
                }.frame(height: 210)
            }
            HStack {
                Spacer()
                Button(store.t("closeUpdate")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(width: 660)
            .interactiveDismissDisabled(artworkBusy)
            .fileImporter(isPresented: $selectingImage, allowedContentTypes: [.image]) { result in
                switch result {
                case .success(let url): setArtwork(url)
                case .failure(let error): store.error = error.localizedDescription
                }
            }
            .sheet(item: $trackToEdit) { TagEditor(track: $0).environmentObject(store) }
            .sheet(isPresented: $showBatch) { BatchTagEditor(tracks: batchTracks).environmentObject(store) }
    }

    private func setArtwork(_ url: URL?) {
        artworkBusy = true
        Task {
            await store.setAlbumArtwork(url, for: id)
            artworkBusy = false
        }
    }
}
