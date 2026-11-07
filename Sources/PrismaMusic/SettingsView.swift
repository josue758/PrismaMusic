import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack { VStack(alignment: .leading, spacing: 4) { Text(store.t("settings")).font(.title2.bold()); Text("Prisma Music").font(.caption).foregroundStyle(.secondary) }; Spacer(); Button { dismiss() } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain) }
            Form {
                Section(store.t("appearance")) {
                    HStack { ForEach(Accent.allCases) { accent in Button { store.accent = accent } label: { Circle().fill(accent.color).frame(width: 25, height: 25).overlay { if store.accent == accent { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(.black) } } }.buttonStyle(.plain).accessibilityLabel(accent.rawValue) }; Spacer() }.padding(.vertical, 5)
                    Picker(store.t("theme"), selection: $store.theme) { Text(store.t("system")).tag("system"); Text(store.t("dark")).tag("dark"); Text(store.t("light")).tag("light") }
                    Picker(store.t("language"), selection: $store.language) { ForEach(AppLanguage.allCases) { Text($0.name).tag($0) } }
                }
                Section(store.t("library")) {
                    Toggle(store.t("startScan"), isOn: $store.scanOnLaunch)
                    Text(store.t("autoTagNote")).font(.caption).foregroundStyle(.secondary)
                    Toggle(store.t("online"), isOn: $store.online)
                    Text(store.t("privacy")).font(.caption).foregroundStyle(.secondary)
                }
                Section(store.t("mini")) { Text(store.t("pipNote")).font(.caption).foregroundStyle(.secondary) }
            }.formStyle(.grouped)
            Text(store.t("version")).font(.caption2).foregroundStyle(.tertiary)
        }.padding(24).frame(width: 520, height: 610).preferredColorScheme(store.colorScheme)
    }
}
struct NASView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var address = "smb://"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("connect"), systemImage: "externaldrive.connected.to.line.below").font(.title2.bold())
            Text(store.t("nasHelp")).foregroundStyle(.secondary)
            TextField("smb://NAS/Music", text: $address).textFieldStyle(.roundedBorder)
            HStack { Button(store.t("cancel")) { dismiss() }; Spacer(); Button(store.t("connectButton")) { if let url = URL(string: address), ["smb", "afp", "nfs"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false { NSWorkspace.shared.open(url); dismiss() } }.buttonStyle(.glassProminent).disabled(!valid) }
        }.padding(28).frame(width: 460)
    }
    private var valid: Bool { guard let url = URL(string: address) else { return false }; return ["smb", "afp", "nfs"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false && url.user == nil && url.password == nil }
}
struct TagEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State var track: Track
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("edit")).font(.title2.bold())
            Form { TextField(store.t("title"), text: $track.title); TextField(store.t("artist"), text: $track.artist); TextField(store.t("album"), text: $track.album); TextField(store.t("genre"), text: $track.genre); TextField(store.t("year"), text: $track.year) }.textFieldStyle(.roundedBorder)
            Text(store.t("tagNote")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(store.t("cancel")) { dismiss() }; Spacer(); Button(store.t("save")) { store.update(track); dismiss() }.buttonStyle(.glassProminent).disabled(track.title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 450)
    }
}
