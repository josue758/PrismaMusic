import SwiftUI

struct LibraryBackupsView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var backups: [LibraryBackupPreview] = []
    @State private var selection: String?
    @State private var trackCount: Int?
    @State private var failure: String?
    @State private var staged = false
    @State private var staging = false
    @State private var confirm = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Label(store.t("manageBackups"), systemImage: "clock.arrow.circlepath").font(.title2.bold())
            List(backups, selection: $selection) { backup in
                let date = backup.date?.formatted(date: .abbreviated, time: .shortened) ?? backup.id
                LabeledContent(date, value: ByteCountFormatter.string(fromByteCount: backup.size, countStyle: .file))
                    .tag(backup.id)
            }.frame(height: 190)
            if backups.isEmpty { Text(store.t("noBackups")).foregroundStyle(.secondary) }
            if let trackCount { Text(store.songCountText(trackCount)).font(.callout) }
            if let failure { Text(failure).foregroundStyle(.orange) }
            if staged { Text(store.t("backupStaged")).foregroundStyle(.secondary) }
            HStack {
                Button(store.t("closeUpdate")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(staging)
                Spacer()
                Button(store.t("restoreBackup")) { confirm = true }.buttonStyle(.glassProminent)
                    .disabled(selection == nil || trackCount == nil || staging || staged)
            }
        }.padding(24).frame(width: 510)
            .task {
                do {
                    backups = try await store.libraryBackups()
                    selection = backups.first?.id
                } catch { failure = error.localizedDescription }
            }
            .task(id: selection) {
                trackCount = nil
                guard let selection else { return }
                failure = nil
                do {
                    let count = try await store.backupTrackCount(selection)
                    if !Task.isCancelled { trackCount = count }
                } catch {
                    if !Task.isCancelled { failure = error.localizedDescription }
                }
            }
            .confirmationDialog(store.t("restoreBackup"), isPresented: $confirm, titleVisibility: .visible) {
                Button(store.t("restoreBackup"), role: .destructive) {
                    guard let selection else { return }
                    staging = true
                    Task {
                        defer { staging = false }
                        do {
                            try await store.stageLibraryRestore(selection)
                            staged = true
                        } catch { failure = error.localizedDescription }
                    }
                }
                Button(store.t("cancel"), role: .cancel) {}
            } message: {
                Text(store.t("restoreBackupHelp"))
            }
    }
}
