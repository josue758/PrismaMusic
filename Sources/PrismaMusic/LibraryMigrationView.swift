import SwiftUI

struct LibraryMigrationView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let preview: LibraryMigration

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("importLibraryMigration"), systemImage: "arrow.trianglehead.swap")
                .font(.title2.bold())
            Text(store.t("migrationHelp")).foregroundStyle(.secondary)
            LabeledContent(store.t("favorites"), value: preview.favorites.count.formatted())
            LabeledContent(store.t("playlists"), value: preview.playlists.count.formatted())
            LabeledContent(store.t("tagEdits"), value: preview.edits.count.formatted())
            LabeledContent(store.t("playlistRelocated"), value: preview.relocated.formatted())
            if !preview.unmatched.isEmpty {
                LabeledContent(store.t("playlistUnmatched"), value: preview.unmatched.count.formatted())
                List(Array(preview.unmatched.prefix(200).enumerated()), id: \.offset) { item in
                    Text(item.element).font(.caption).lineLimit(1).truncationMode(.middle).help(item.element)
                }.frame(height: 120)
            }
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("importLibraryMigration")) {
                    if store.importLibraryMigration(preview) { dismiss() }
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(preview.isEmpty || !store.canImportLibraryMigration)
            }
        }.padding(24).frame(width: 520)
    }
}
