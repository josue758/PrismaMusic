import AppKit
import SwiftUI

struct LibrarySongList: View {
    @EnvironmentObject var store: LibraryStore
    var tracks: [Track]
    var showAlbum = true
    var subtitleAlbum = false
    var reveal: LibraryStore.AlbumTrackReveal? = nil
    var number: (Track) -> Int
    @State private var hasColumnSpace = true
    private var showsAlbumColumns: Bool { showAlbum && hasColumnSpace }
    private struct RowBounds: PreferenceKey {
        static var defaultValue: [String: CGRect] = [:]
        static func reduce(value: inout [String: CGRect], nextValue: () -> [String: CGRect]) {
            value.merge(nextValue(), uniquingKeysWith: { _, latest in latest })
        }
    }
    @Namespace private var selectionSpace
    @State private var rowBounds: [String: CGRect] = [:]
    @State private var rangeAnchor: String?
    @State private var dragAnchor: String?
    @State private var selectedID: String?
    @State private var editing: Track?
    @State private var selectedIDs = Set<String>()
    @State private var batchEditing = false
    @FocusState private var keyboardFocused: Bool
    var body: some View {
        ScrollViewReader { proxy in
            LazyVStack(spacing: 3) {
                HStack(spacing: 10) {
                    Text("#").frame(width: 22)
                    Color.clear.frame(width: 40, height: 1)
                    Text(store.t("title")).frame(maxWidth: .infinity, alignment: .leading)
                    if showsAlbumColumns {
                        Text(store.t("album")).frame(width: 140, alignment: .leading)
                        Text(store.t("year")).frame(width: 38)
                    }
                    Image(systemName: "clock").frame(width: 38)
                    Color.clear.frame(width: 54, height: 1)
                }.font(.system(size: 9, weight: .medium)).foregroundStyle(.secondary).padding(.horizontal, 12).padding(
                    .bottom, 9
                ).accessibilityHidden(true)
                ForEach(tracks) { track in row(track) }
            }
            .onGeometryChange(for: Bool.self) { proxy in
                proxy.size.width >= 600
            } action: {
                hasColumnSpace = $0
            }
            .focusable().focused($keyboardFocused).focusEffectDisabled()
            .coordinateSpace(name: selectionSpace)
            .onPreferenceChange(RowBounds.self) { rowBounds = $0 }
            .onKeyPress(keys: [.upArrow, .downArrow], phases: [.down, .repeat]) { press in
                guard press.modifiers.isEmpty || press.modifiers == .shift else { return .ignored }
                return moveSelection(press.key == .upArrow ? -1 : 1, extending: press.modifiers == .shift, proxy: proxy)
            }
            .onKeyPress("a", phases: .down) { press in
                guard press.modifiers == .command, !tracks.isEmpty else { return .ignored }
                selectedIDs = Set(tracks.map(\.id))
                selectedID = selectedID.flatMap { selectedIDs.contains($0) ? $0 : nil } ?? tracks.first?.id
                rangeAnchor = selectedID
                return .handled
            }
            .onKeyPress(.return, phases: .down) { press in
                guard press.modifiers.isEmpty, let track = tracks.first(where: { $0.id == selectedID }) else {
                    return .ignored
                }
                store.play(track, in: tracks)
                return .handled
            }
            .accessibilityHint(store.t("listKeyboardHelp"))
            .onChange(of: reveal, initial: true) { _, request in
                guard let request else { return }
                rangeAnchor = request.trackID
                selectedID = request.trackID
                selectedIDs = [request.trackID]
            }
        }.sheet(item: $editing) { TagEditor(track: $0).environmentObject(store) }
            .sheet(isPresented: $batchEditing) {
                BatchTagEditor(tracks: tracks.filter { selectedIDs.contains($0.id) }).environmentObject(store)
            }
    }
    private func row(_ track: Track) -> some View {
        HStack(spacing: 10) {
            Button {
                store.play(track, in: tracks)
            } label: {
                Group {
                    if store.loadingTrackID == track.id {
                        ProgressView().controlSize(.mini)
                    } else if store.currentID == track.id && store.isPlaying {
                        Image(systemName: "waveform").foregroundStyle(store.effectiveAccent)
                    } else {
                        Text(String(format: "%02d", number(track))).foregroundStyle(.secondary)
                    }
                }.font(.system(size: 10, design: .monospaced)).frame(width: 22, height: 34)
            }.buttonStyle(.plain).help(store.t("play")).accessibilityLabel(store.t("play") + ": " + track.title)
            ArtworkView(track: track).frame(width: 40, height: 40)
            songTitle(track).contentShape(Rectangle())
                .simultaneousGesture(
                    DragGesture(minimumDistance: 6, coordinateSpace: .named(selectionSpace))
                        .onChanged { value in selectDrag(from: track.id, to: value.location.y) }
                        .onEnded { _ in dragAnchor = nil }
                )
            if showsAlbumColumns {
                Text(store.displayAlbum(track.album)).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                    .frame(width: 140, alignment: .leading)
                Text(track.year).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary).frame(
                    width: 38)
            }
            Text(clockText(track.duration)).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                .frame(width: 38)
            FavoriteControl(track: track).frame(width: 22)
            Button {
                store.inspectedID = track.id
                store.showInfo = true
                store.showLyrics = false
                store.showQueue = false
            } label: {
                Image(systemName: "info.circle").frame(width: 22, height: 28)
            }.buttonStyle(.plain).foregroundStyle(.secondary).help(store.t("fileInfo"))
        }.padding(.horizontal, 12).padding(.vertical, store.preferences.compactRows ? 5 : 9)
            .background(
                selectedIDs.contains(track.id)
                    ? store.effectiveAccent.opacity(0.13) : number(track) % 2 == 1 ? .primary.opacity(0.03) : .clear,
                in: RoundedRectangle(cornerRadius: 12)
            )
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(
                        key: RowBounds.self, value: [track.id: proxy.frame(in: .named(selectionSpace))])
                }
            }
            .id(track.id)
            .overlay {
                RoundedRectangle(cornerRadius: 12).strokeBorder(
                    selectedIDs.contains(track.id) && keyboardFocused ? store.effectiveAccent.opacity(0.65) : .clear,
                    lineWidth: 1)
            }
            .contentShape(Rectangle()).onTapGesture(count: 2) { store.play(track, in: tracks) }.onTapGesture {
                let modifiers = NSEvent.modifierFlags
                if modifiers.contains(.shift), let anchor = rangeAnchor ?? selectedID {
                    selectRange(from: anchor, to: track.id)
                } else if modifiers.contains(.command) {
                    if !selectedIDs.insert(track.id).inserted { selectedIDs.remove(track.id) }
                    rangeAnchor = track.id
                } else {
                    rangeAnchor = track.id
                    selectedIDs = [track.id]
                }
                selectedID = track.id
                store.inspectedID = track.id
                keyboardFocused = true
            }
            .accessibilityElement(children: .contain)
            .accessibilityLabel(track.title + ", " + store.displayArtist(track.artist))
            .accessibilityAddTraits(selectedIDs.contains(track.id) ? [.isSelected] : [])
            .accessibilityAction(named: store.t("openAlbum")) { store.openAlbum(track) }
            .accessibilityAction(named: store.t("play")) { store.play(track, in: tracks) }
            .contextMenu {
                if selectedIDs.count > 1 && selectedIDs.contains(track.id) {
                    Button(store.t("batchTags")) { batchEditing = true }.disabled(store.scanning)
                } else {
                    TrackContextMenu(track: track) { editing = track }
                }
            }
    }
    private func songTitle(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Text(track.title).font(.system(size: 12, weight: .medium)).foregroundStyle(
                    store.currentID == track.id ? store.effectiveAccent : .primary)
                if store.preferences.showQuality && showsAlbumColumns { QualityBadge(track: track) }
            }
            Text(
                (subtitleAlbum ? store.displayAlbum(track.album) : store.displayArtist(track.artist))
                    + (store.preferences.showQuality && !track.qualitySummary.isEmpty
                        ? " · " + track.qualitySummary : "")
            ).font(.system(size: 9)).foregroundStyle(.secondary)
            if showAlbum && !showsAlbumColumns {
                Text([store.displayAlbum(track.album), track.year].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.caption2).foregroundStyle(.secondary)
            }
        }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
    }
    private func selectDrag(from id: String, to y: CGFloat) {
        if dragAnchor == nil {
            dragAnchor = id
            rangeAnchor = id
            keyboardFocused = true
        }
        guard let anchor = dragAnchor,
            let end = rowBounds.min(by: { abs($0.value.midY - y) < abs($1.value.midY - y) })?.key,
            selectedID != end || selectedIDs.count <= 1
        else { return }
        selectRange(from: anchor, to: end)
        selectedID = end
        store.inspectedID = end
    }

    private func selectRange(from anchor: String, to end: String) {
        guard let first = tracks.firstIndex(where: { $0.id == anchor }),
            let last = tracks.firstIndex(where: { $0.id == end })
        else {
            selectedIDs = [end]
            return
        }
        selectedIDs = Set(tracks[min(first, last)...max(first, last)].map(\.id))
    }

    private func moveSelection(_ direction: Int, extending: Bool, proxy: ScrollViewProxy) -> KeyPress.Result {
        guard let id = SongSelection.moved(from: selectedID, in: tracks.map(\.id), by: direction) else {
            return .ignored
        }
        if extending {
            let anchor = rangeAnchor ?? selectedID ?? id
            rangeAnchor = anchor
            selectRange(from: anchor, to: id)
        } else {
            rangeAnchor = id
            selectedIDs = [id]
        }
        selectedID = id
        store.inspectedID = id
        proxy.scrollTo(id)
        return .handled
    }
}
