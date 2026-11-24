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
    @State private var matches: [Track] = []
    @State private var matchCount = 0
    @State private var codecs: [String] = []
    @State private var rates: [Int] = []

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
                choice("artist", selection: $rules.artist, values: store.statistics.artists)
                choice("genre", selection: $rules.genre, values: store.statistics.genres)
                TextField(store.t("year"), text: $rules.year)
                Picker(store.t("format"), selection: $rules.codec) {
                    Text(store.t("anyValue")).tag("")
                    ForEach(codecs, id: \.self) { Text($0).tag($0) }
                }
                Picker(store.t("sampleRate"), selection: $rules.sampleRate) {
                    Text(store.t("anyValue")).tag(0)
                    ForEach(rates, id: \.self) { rate in
                        Text((Double(rate) / 1000).formatted() + " kHz").tag(rate)
                    }
                }
                Toggle(store.t("smartUnplayed"), isOn: $rules.unplayed)
                Toggle(store.t("favorites"), isOn: $rules.favorites)
                Toggle(store.t("smartAddedThisMonth"), isOn: $rules.addedThisMonth)
            }
            Text(store.t("smartPlaylistHelp")).font(.caption).foregroundStyle(.secondary)
            Text(store.songCountText(matchCount)).font(.callout.bold())
            ForEach(matches) { track in
                LabeledContent(track.title, value: store.displayArtist(track.artist)).font(.caption).lineLimit(1)
            }
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t(draft.playlist == nil ? "create" : "save")) {
                    store.createPlaylist(name, rules: normalizedRules, replacing: draft.playlist?.id)
                    dismiss()
                }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || normalizedRules.isEmpty)
            }
        }.padding(28).frame(width: 470)
            .onAppear {
                let tracks = store.tracks
                codecs = Array(Set(tracks.map(\.codecLabel) + [rules.codec]).subtracting([""])).sorted()
                rates = Array(Set(tracks.compactMap { track -> Int? in
                    guard let rate = track.sampleRate, rate.isFinite, rate >= 1, rate <= 1_000_000 else { return nil }
                    return Int(rate.rounded())
                } + [rules.sampleRate]).subtracting([0])).sorted()
            }
            .task(id: normalizedRules) {
                do { try await Task.sleep(for: .milliseconds(140)) } catch { return }
                let rules = normalizedRules
                let tracks = store.tracks
                let result = await Task.detached(priority: .userInitiated) {
                    let matches = rules.isEmpty ? [] : rules.filter(tracks).filter { $0.hiddenDuplicate != true }
                    return (count: matches.count, tracks: Array(matches.prefix(5)))
                }.value
                if !Task.isCancelled {
                    matchCount = result.count
                    matches = result.tracks
                }
            }
    }
    private func choice(_ key: String, selection: Binding<String>, values: [String]) -> some View {
        let options = Set(values).subtracting(["", "—"]).union(
            selection.wrappedValue.isEmpty ? [] : [selection.wrappedValue])
        return Picker(store.t(key), selection: selection) {
            Text(store.t("anyValue")).tag("")
            ForEach(options.sorted(), id: \.self) { Text($0).tag($0) }
        }
    }

    private var normalizedRules: SmartPlaylistRules {
        var result = rules
        for key in [\SmartPlaylistRules.search, \.artist, \.genre, \.year] {
            result[keyPath: key] = result[keyPath: key].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return result
    }
}
