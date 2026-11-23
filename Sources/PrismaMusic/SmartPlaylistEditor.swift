import SwiftUI

struct SmartPlaylistDraft: Identifiable {
    let id = UUID()
    var playlist: Playlist? = nil
    var rules: SmartPlaylistRules
}

struct SmartPlaylistEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let draft: SmartPlaylistDraft
    @State private var name: String
    @State private var rules: SmartPlaylistRules

    init(draft: SmartPlaylistDraft) {
        self.draft = draft
        _name = State(initialValue: draft.playlist?.name ?? "")
        _rules = State(initialValue: draft.rules)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(
                store.t(draft.playlist == nil ? "newSmartPlaylist" : "editSmartPlaylist"),
                systemImage: "line.3.horizontal.decrease"
            ).font(.title2.bold())
            Form {
                TextField(store.t("playlistName"), text: $name)
                TextField(store.t("search"), text: $rules.search)
                TextField(store.t("artist"), text: $rules.artist)
                TextField(store.t("genre"), text: $rules.genre)
                TextField(store.t("year"), text: $rules.year)
                Picker(store.t("format"), selection: $rules.codec) {
                    Text(store.t("anyValue")).tag("")
                    ForEach(["FLAC", "ALAC", "PCM", "AAC", "MP3"], id: \.self) { Text($0).tag($0) }
                }
                Picker(store.t("sampleRate"), selection: $rules.sampleRate) {
                    Text(store.t("anyValue")).tag(0)
                    ForEach([44100, 48000, 88200, 96000, 176400, 192000], id: \.self) { rate in
                        Text((Double(rate) / 1000).formatted() + " kHz").tag(rate)
                    }
                }
                Toggle(store.t("smartUnplayed"), isOn: $rules.unplayed)
                Toggle(store.t("favorites"), isOn: $rules.favorites)
                Toggle(store.t("smartAddedThisMonth"), isOn: $rules.addedThisMonth)
            }
            Text(store.t("smartPlaylistHelp")).font(.caption).foregroundStyle(.secondary)
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t(draft.playlist == nil ? "create" : "save")) {
                    store.createPlaylist(name, rules: normalizedRules, replacing: draft.playlist?.id)
                    dismiss()
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalizedRules.isEmpty)
            }
        }.padding(28).frame(width: 450)
    }

    private var normalizedRules: SmartPlaylistRules {
        var result = rules
        for key in [\SmartPlaylistRules.search, \.artist, \.genre, \.year] {
            result[keyPath: key] = result[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
