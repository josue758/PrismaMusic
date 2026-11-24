import SwiftUI

struct PlaylistImportView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let preview: PlaylistImport
    @State private var name = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("importPlaylist"), systemImage: "text.badge.plus").font(.title2.bold())
            TextField(store.t("playlistName"), text: $name)
            Text("\(store.songCountText(preview.tracks.count)) · \(store.t("playlistRelocated")) \(preview.relocated) · \(store.t("playlistUnmatched")) \(preview.unmatched.count)")
                .font(.caption).foregroundStyle(.secondary)
            List {
                ForEach(preview.tracks) { track in
                    LabeledContent(track.title, value: store.displayArtist(track.artist))
                }
                ForEach(Array(preview.unmatched.enumerated()), id: \.offset) { row in
                    Label(row.element, systemImage: "exclamationmark.circle").foregroundStyle(.secondary)
                }
            }.frame(height: 230)
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("importPlaylist")) {
                    store.saveManualPlaylist(name, ids: preview.tracks.map(\.id))
                    dismiss()
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(preview.tracks.isEmpty || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 540)
            .onAppear { name = preview.name }
    }
}

struct PlaylistManagementView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let playlist: Playlist
    @State private var ids: [String] = []
    @State private var name = ""
    @State private var selected: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("managePlaylist"), systemImage: "music.note.list").font(.title2.bold())
            TextField(store.t("playlistName"), text: $name)
            List(ids, id: \.self, selection: $selected) { id in
                Text(store.track(for: id)?.title ?? URL(fileURLWithPath: id).lastPathComponent).tag(id)
            }.frame(height: 240)
            HStack {
                Button { move(-1) } label: { Label(store.t("moveUp"), systemImage: "chevron.up") }
                    .disabled(index.map { $0 == 0 } ?? true)
                Button { move(1) } label: { Label(store.t("moveDown"), systemImage: "chevron.down") }
                    .disabled(index.map { $0 == ids.count - 1 } ?? true)
                Button(store.t("removeFromPlaylist")) {
                    if let index { ids.remove(at: index) }
                    selected = nil
                }.disabled(index == nil)
            }
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("save")) {
                    store.saveManualPlaylist(name, ids: ids, replacing: playlist.id)
                    dismiss()
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 530)
            .onAppear { ids = playlist.trackIDs; name = playlist.name }
    }

    private var index: Int? { selected.flatMap { ids.firstIndex(of: $0) } }
    private func move(_ step: Int) {
        guard let index, ids.indices.contains(index + step) else { return }
        ids.swapAt(index, index + step)
    }
}
