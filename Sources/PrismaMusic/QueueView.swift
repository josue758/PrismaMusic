import CoreTransferable
import SwiftUI
import UniformTypeIdentifiers

private struct QueueDrag: Codable, Transferable {
    let ids: Set<String>
    static var transferRepresentation: some TransferRepresentation {
        CodableRepresentation(contentType: UTType(exportedAs: "local.prisma.music.queue-selection"))
    }
}

struct QueueView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var selected = Set<String>()
    @State private var dropTarget: String?
    private var upcoming: [String] { store.upcomingIDs }
    private var selection: Set<String> { selected.intersection(upcoming) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                SectionHeading(title: store.t("queue"))
                Spacer()
                Button { store.showQueue = false } label: { Image(systemName: "xmark") }
                    .buttonStyle(.plain).accessibilityLabel(store.t("closeUpdate"))
            }
            if let current = store.current {
                VStack(alignment: .leading, spacing: 6) {
                    Text(store.t("now")).font(.caption).foregroundStyle(store.effectiveAccent)
                    HStack {
                        trackLabel(current)
                        Button { store.togglePlay() } label: { PlaybackControlSymbol() }
                            .buttonStyle(.plain).accessibilityLabel(store.playbackControlLabel)
                    }
                }.padding(10).background(store.effectiveAccent.opacity(0.11), in: RoundedRectangle(cornerRadius: 12))
            }
            HStack {
                Text(store.t("upNext")).font(.caption.weight(.semibold))
                Spacer()
                Text("\(upcoming.count)").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
            if upcoming.isEmpty {
                Text(store.t("queueEmpty")).font(.caption).foregroundStyle(.secondary)
                Spacer()
            } else {
                List(selection: $selected) {
                    ForEach(upcoming, id: \.self) { id in
                        if let track = store.track(for: id) {
                            HStack {
                                trackLabel(track)
                                Button { store.play(track) } label: { Image(systemName: "play.fill") }
                                    .buttonStyle(.plain).accessibilityLabel(store.t("play"))
                            }.tag(id)
                                .contentShape(Rectangle())
                                .draggable(QueueDrag(ids: selected.contains(id) ? selection : [id]))
                                .dropDestination(for: QueueDrag.self) { items, _ in
                                    guard let drag = items.first else { return false }
                                    return store.moveUpcoming(drag.ids, before: id)
                                } isTargeted: { targeted in
                                    if targeted { dropTarget = id }
                                    else if dropTarget == id { dropTarget = nil }
                                }
                                .overlay(alignment: .top) {
                                    if dropTarget == id { Rectangle().fill(store.effectiveAccent).frame(height: 2) }
                                }
                        }
                    }
                    Text(store.t("dropAtEnd")).font(.caption).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 24)
                        .dropDestination(for: QueueDrag.self) { items, _ in
                            guard let drag = items.first else { return false }
                            return store.moveUpcoming(drag.ids, before: nil)
                        }
                }.listStyle(.plain).scrollContentBackground(.hidden)
                    .onDeleteCommand { store.removeQueued(ids: selection) }
                HStack {
                    Button { move(up: true) } label: { Image(systemName: "arrow.up") }
                        .help(store.t("moveUp")).accessibilityLabel(store.t("moveUp"))
                    Button { move(up: false) } label: { Image(systemName: "arrow.down") }
                        .help(store.t("moveDown")).accessibilityLabel(store.t("moveDown"))
                    Spacer()
                    Button(store.t("remove")) { store.removeQueued(ids: selection) }
                }.buttonStyle(.glass).disabled(selection.isEmpty)
            }
            Button {
                store.openSettings("playback")
            } label: {
                Label(store.t("playback"), systemImage: "slider.horizontal.3").font(.caption)
            }.buttonStyle(.glass)
        }.padding(18)
            .onChange(of: upcoming) { _, next in selected.formIntersection(next) }
    }

    private func trackLabel(_ track: Track) -> some View {
        HStack(spacing: 8) {
            ArtworkView(track: track).frame(width: 30, height: 30).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 3) {
                Text(track.title).font(.callout.weight(.medium))
                Text(store.displayArtist(track.artist)).font(.caption).foregroundStyle(.secondary)
            }.lineLimit(1)
            Spacer(minLength: 0)
        }
    }

    private func move(up: Bool) {
        let ids = upcoming
        if up {
            guard let first = ids.firstIndex(where: selection.contains), first > 0 else { return }
            store.moveUpcoming(selection, before: ids[first - 1])
        } else {
            guard let last = ids.lastIndex(where: selection.contains), last + 1 < ids.count else { return }
            store.moveUpcoming(selection, before: ids.indices.contains(last + 2) ? ids[last + 2] : nil)
        }
    }
}
