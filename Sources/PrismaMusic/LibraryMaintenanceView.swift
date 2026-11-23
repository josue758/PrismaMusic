import AppKit
import SwiftUI

struct TagReviewView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var issues: [TagReviewIssue] = []
    @State private var kind = ""
    @State private var issueID: String?
    @State private var selected = Set<String>()
    @State private var reviewing = false
    @State private var editing = false
    @State private var refreshID = UUID()
    private var groups: [TagReviewIssue] { issues.filter { kind.isEmpty || $0.kind.rawValue == kind } }
    private var songs: [Track] { groups.first { $0.id == issueID }?.tracks ?? [] }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("tagReview"), systemImage: "checklist").font(.title2.bold())
            Text(store.t("tagReviewNote")).font(.callout).foregroundStyle(.secondary)
            Picker(store.t("reviewCategory"), selection: $kind) {
                Text(store.t("allIssues")).tag("")
                ForEach(TagIssueKind.allCases) { Text(store.t($0.rawValue)).tag($0.rawValue) }
            }.pickerStyle(.menu).frame(maxWidth: 300)
            HStack(spacing: 14) {
                List(groups, selection: $issueID) { issue in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(issue.title.isEmpty ? store.t(issue.kind.rawValue) : issue.title).lineLimit(2)
                        Text(store.songCountText(issue.tracks.count)).font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 5).tag(issue.id)
                }.frame(width: 250)
                Table(songs, selection: $selected) {
                    TableColumn(store.t("title"), value: \.title)
                    TableColumn(store.t("artist"), value: \.artist)
                    TableColumn(store.t("album"), value: \.album)
                    TableColumn(store.t("filePath")) { Text($0.url.path).font(.caption).help($0.url.path) }
                }
            }.frame(minHeight: 270)
            if reviewing {
                ProgressView(store.t("reviewingTags"))
            } else if groups.isEmpty {
                Text(store.t("reviewEmpty")).foregroundStyle(.secondary)
            }
            HStack {
                Button(store.t("refreshReview")) { refreshID = UUID() }.disabled(reviewing)
                Button(store.t("undoTags")) {
                    store.undoTagEdits()
                    refreshID = UUID()
                }
                .disabled(!store.canUndoTagEdits || store.scanning)
                Spacer()
                Button(store.t("closeUpdate")) { dismiss() }.keyboardShortcut(.cancelAction)
                Button(store.t("previewTags")) { editing = true }.buttonStyle(.glassProminent)
                    .disabled(selected.isEmpty || reviewing || store.scanning)
            }
        }.padding(24).frame(minWidth: 850, idealWidth: 960, minHeight: 500, idealHeight: 600)
            .background { PrismaBackdrop(reactive: false).ignoresSafeArea() }
            .onChange(of: kind) { _, _ in
                issueID = groups.first?.id
                selected = []
            }
            .onChange(of: issueID) { _, _ in selected = Set(songs.map(\.id)) }
            .task(id: refreshID) {
                reviewing = true
                let snapshot = store.tracks
                let result = await Task.detached(priority: .utility) { LibraryTagReview.find(snapshot) }.value
                guard !Task.isCancelled else { return }
                issues = result
                if !groups.contains(where: { $0.id == issueID }) { issueID = groups.first?.id }
                selected = Set(songs.map(\.id))
                reviewing = false
            }
            .sheet(isPresented: $editing, onDismiss: { refreshID = UUID() }) {
                BatchTagEditor(tracks: songs.filter { selected.contains($0.id) }).environmentObject(store)
            }
    }
}

struct BatchTagEditor: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    let tracks: [Track]
    @State private var enabled = Set<TagField>()
    @State private var values: [TagField: String] = [:]
    @State private var numbering = false
    @State private var start = "1"
    private let fields: [TagField] = [.artist, .album, .albumArtist, .genre, .year, .discNumber]
    private var changes: [TagField: String] {
        Dictionary(
            uniqueKeysWithValues: enabled.map {
                ($0, (values[$0] ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            })
    }
    private var valid: Bool {
        (!enabled.isEmpty || numbering) && changes.allSatisfy { $0.key.isValid($0.value) }
            && (!numbering || Int(start).map { $0 > 0 && $0 <= 9999 && tracks.count <= 10000 - $0 } == true)
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Label(store.t("batchTags"), systemImage: "square.and.pencil").font(.title2.bold())
            Text(store.t("batchTagsNote")).font(.callout).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) {
                ForEach(fields) { field in
                    HStack {
                        Toggle(
                            store.t(field.rawValue),
                            isOn: Binding(
                                get: { enabled.contains(field) },
                                set: { if $0 { enabled.insert(field) } else { enabled.remove(field) } }
                            )
                        ).toggleStyle(.checkbox).frame(width: 180, alignment: .leading)
                        TextField(
                            store.t(field.rawValue),
                            text: Binding(get: { values[field] ?? "" }, set: { values[field] = $0 })
                        )
                        .labelsHidden().accessibilityLabel(store.t(field.rawValue))
                        .disabled(!enabled.contains(field)).textFieldStyle(.roundedBorder)
                    }
                }
                HStack {
                    Toggle(store.t("numberTracks"), isOn: $numbering).toggleStyle(.checkbox).frame(
                        width: 180, alignment: .leading)
                    TextField("1", text: $start).labelsHidden().accessibilityLabel(store.t("numberTracks")).disabled(
                        !numbering
                    ).textFieldStyle(.roundedBorder)
                }
            }
            Text(store.t("previewTags") + " · " + store.songCountText(tracks.count)).font(.headline)
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(Array(tracks.prefix(10).enumerated()), id: \.element.id) { index, track in
                        VStack(alignment: .leading, spacing: 3) {
                            Text(track.title).font(.callout.bold())
                            Text(track.url.lastPathComponent).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                                .help(track.url.path)
                            ForEach(fields.filter { enabled.contains($0) }) { field in
                                Text(
                                    store.t(field.rawValue) + ": " + display(field.value(in: track)) + " → "
                                        + display(changes[field] ?? "")
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                            if numbering, let number = Int(start), number > 0, number <= 9999 {
                                Text(
                                    store.t("trackNumber") + ": " + display(TagField.trackNumber.value(in: track))
                                        + " → \(number + index)"
                                )
                                .font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                }.frame(maxWidth: .infinity, alignment: .leading)
            }.frame(height: 150).padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
            Text(store.t(enabled.isEmpty && !numbering ? "chooseTagFields" : valid ? "tagNote" : "tagValidation")).font(
                .caption
            ).foregroundStyle(.secondary)
            HStack {
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button(store.t("applyTags")) {
                    store.applyTagEdits(
                        ids: tracks.map(\.id), changes: changes, numberingFrom: numbering ? Int(start) : nil)
                    dismiss()
                }.buttonStyle(.glassProminent).disabled(!valid || store.scanning || tracks.isEmpty)
            }
        }.padding(24).frame(width: 650).background { PrismaBackdrop(reactive: false).ignoresSafeArea() }
    }
    private func display(_ value: String) -> String { value.isEmpty ? "—" : value }
}

struct ScanReportView: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.dismiss) private var dismiss
    @State private var search = ""
    private var issues: [ScanIssue] {
        (store.scanAudit?.issues ?? []).filter {
            search.isEmpty || $0.url.path.localizedStandardContains(search)
                || $0.message.localizedStandardContains(search)
        }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("scanReport"), systemImage: "doc.text.magnifyingglass").font(.title2.bold())
            if let audit = store.scanAudit {
                Text(
                    "\(store.t("processedFiles")): \(audit.imported + audit.unchanged) · \(store.t("failedFiles")): \(audit.failed)"
                )
                .font(.callout).foregroundStyle(.secondary)
                if audit.unavailableSources > 0 {
                    Text(store.t("offlineSources") + ": \(audit.unavailableSources)").font(.callout).foregroundStyle(
                        .secondary)
                }
                if audit.cancelled || audit.unavailableSources > 0 {
                    Button(store.t("resumeScan")) { Task { await store.scanNewMusic() } }.disabled(store.scanning)
                }
            }
            TextField(store.t("searchScanReport"), text: $search).textFieldStyle(.roundedBorder)
            List(Array(issues.enumerated()), id: \.offset) { _, issue in
                VStack(alignment: .leading, spacing: 6) {
                    Text(issue.url.lastPathComponent).font(.headline)
                    Text(issue.url.path).font(.caption).textSelection(.enabled)
                    Text(issue.message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    HStack {
                        Button(store.t("copyPath")) {
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(issue.url.path, forType: .string)
                        }
                        if MetadataReader.extensions.contains(issue.url.pathExtension.lowercased()) {
                            Button(store.t("retryFile")) { Task { await store.retryFailedScan(only: issue.url) } }
                                .disabled(store.scanning)
                        }
                    }.buttonStyle(.borderless)
                }.padding(.vertical, 8)
            }.overlay {
                if issues.isEmpty { ContentUnavailableView(store.t("reportEmpty"), systemImage: "checkmark.circle") }
            }
            HStack {
                Button(store.t("showReportFile")) { store.showScanReport() }
                Button(store.t("retryFailed")) { Task { await store.retryFailedScan() } }
                    .disabled(
                        store.scanning
                            || store.scanAudit?.issues.contains {
                                MetadataReader.extensions.contains($0.url.pathExtension.lowercased())
                            } != true)
                Spacer()
                if store.scanning {
                    ProgressView().controlSize(.small)
                    Button(store.t("cancel")) { store.cancelScan() }
                }
                Button(store.t("closeUpdate")) { dismiss() }.keyboardShortcut(.cancelAction)
            }
        }.padding(24).frame(minWidth: 720, minHeight: 480).background {
            PrismaBackdrop(reactive: false).ignoresSafeArea()
        }
    }
}
