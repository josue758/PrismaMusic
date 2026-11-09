import AppKit
import SwiftUI

@MainActor
final class ListeningWindowController: NSObject, NSWindowDelegate {
    private(set) var window: NSWindow?
    private weak var libraryWindow: NSWindow?
    private var entering = false
    private var closeAfterExit = false
    func show(store: LibraryStore) {
        if let window {
            window.makeKeyAndOrderFront(nil)
            if !entering && !window.styleMask.contains(.fullScreen) {
                entering = true
                window.toggleFullScreen(nil)
            }
            return
        }
        libraryWindow = NSApp.keyWindow
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 1200, height: 820),
            styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView], backing: .buffered,
            defer: false)
        window.title = "Prisma Music · " + store.t("listeningStage")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.backgroundColor = .black
        window.appearance = NSAppearance(named: .darkAqua)
        window.minSize = NSSize(width: 920, height: 680)
        window.collectionBehavior = [.fullScreenPrimary]
        window.isReleasedWhenClosed = false
        window.delegate = self
        let hostingView = NSHostingView(
            rootView: ListeningStageView().environmentObject(store).tint(store.effectiveAccent))
        hostingView.sizingOptions = []
        hostingView.autoresizingMask = [.width, .height]
        window.contentView = hostingView
        self.window = window
        window.center()
        window.makeKeyAndOrderFront(nil)
        entering = true
        Task { @MainActor [weak self, weak window] in
            await Task.yield()
            guard let self, let window, self.window === window else { return }
            window.toggleFullScreen(nil)
        }
    }
    func close() {
        guard let window else { return }
        if entering {
            closeAfterExit = true
            return
        }
        if window.styleMask.contains(.fullScreen) {
            closeAfterExit = true
            window.toggleFullScreen(nil)
        } else {
            window.close()
        }
    }
    func windowDidEnterFullScreen(_ notification: Notification) {
        entering = false
        if closeAfterExit { window?.toggleFullScreen(nil) }
    }
    func windowDidFailToEnterFullScreen(_ window: NSWindow) {
        entering = false
        if closeAfterExit { window.close() }
    }
    func windowDidExitFullScreen(_ notification: Notification) {
        if closeAfterExit { window?.close() }
    }
    func windowWillClose(_ notification: Notification) {
        window = nil
        entering = false
        closeAfterExit = false
        libraryWindow?.makeKeyAndOrderFront(nil)
    }
}

struct ListeningStageView: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showLyrics = true
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                PrismaBackdrop()
                VStack(spacing: 28) {
                    header
                    if let track = store.visualTrack {
                        HStack(spacing: max(36, geometry.size.width * 0.06)) {
                            artworkColumn(
                                track,
                                size: min(
                                    geometry.size.width * (showLyrics ? 0.38 : 0.5),
                                    max(190, geometry.size.height - 420))
                            )
                            .frame(maxWidth: .infinity)
                            if showLyrics {
                                BilingualLyricsView(track: track, large: true)
                                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                            }
                        }.frame(maxHeight: .infinity)
                        transport.padding(22).prismaGlass(24, tinted: true)
                    } else {
                        ContentUnavailableView { Label(store.t("empty"), systemImage: "music.note") }
                    }
                }.padding(.horizontal, max(32, geometry.size.width * 0.05)).padding(.top, 48).padding(.bottom, 30)
            }.frame(width: geometry.size.width, height: geometry.size.height).background(Color.black)
        }
        .ignoresSafeArea()
        .background(Color.black)
        .environment(\.colorScheme, .dark)
        .preferredColorScheme(.dark)
        .tint(store.artworkPalette.primary.readable(onDark: true).color)
        .onExitCommand { store.closeListeningWindow() }
    }
    private var header: some View {
        HStack {
            Button {
                store.closeListeningWindow()
            } label: {
                Label(store.t("backToLibrary"), systemImage: "arrow.down.right.and.arrow.up.left")
            }.buttonStyle(.glass)
            Spacer()
            Text("PRISMA / " + store.t("listeningStage").uppercased()).font(
                .system(size: 10, weight: .medium, design: .monospaced)
            ).tracking(2).foregroundStyle(.secondary)
            Spacer()
            Button {
                showLyrics.toggle()
            } label: {
                Label(store.t("lyrics"), systemImage: "quote.bubble")
            }.buttonStyle(.glass)
                .accessibilityValue(store.t(showLyrics ? "lyricsShown" : "off"))
        }
    }
    private func artworkColumn(_ track: Track, size: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 20) {
            ReactiveArtwork(track: track).frame(width: size, height: size)
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(track.title).font(.system(size: 29, weight: .semibold, design: .rounded)).lineLimit(2)
                    Button {
                        store.openArtist(track.artist)
                        store.closeListeningWindow()
                    } label: {
                        Text(store.displayArtist(track.artist)).font(.title3).foregroundStyle(store.effectiveAccent)
                            .lineLimit(1)
                    }.buttonStyle(.plain)
                    Text(store.displayAlbum(track.album)).font(.callout).foregroundStyle(.secondary).lineLimit(1)
                    QualityBadge(track: track, showsFormatDetails: true)
                }
                Spacer(minLength: 12)
                FavoriteControl(track: track, size: 18)
            }.frame(width: size, alignment: .leading)
        }
    }
    private var transport: some View {
        HStack(spacing: 28) {
            HStack(spacing: 18) {
                control("shuffle", "shuffle") { store.shuffle.toggle() }
                control("backward.end.fill", "previous") { store.next(back: true) }
                Button {
                    store.togglePlay()
                } label: {
                    PlaybackControlSymbol().font(.system(size: 25)).frame(width: 48, height: 48)
                }.buttonStyle(.glass).help(store.playbackControlLabel).accessibilityLabel(store.playbackControlLabel)
                control("forward.end.fill", "next") { store.next() }
                control(store.repeatMode == 2 ? "repeat.1" : "repeat", "repeat") {
                    store.repeatMode = (store.repeatMode + 1) % 3
                }
            }
            HStack(spacing: 10) {
                Text(clockText(store.position))
                ScrubTimeline(
                    value: Binding(get: { store.position }, set: { store.seek($0) }),
                    duration: store.current?.duration ?? 0, enabled: store.current != nil)
                Text("−" + clockText(max(0, (store.current?.duration ?? 0) - store.position)))
            }.font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
            OutputToolbarButton()
            AirPlayRouteButton().frame(width: 26, height: 26).help("AirPlay")
            PlaybackVolumeControl().frame(width: 116)
        }
    }
    private func control(_ image: String, _ key: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: image).font(.system(size: 16)).frame(width: 26, height: 38) }
            .buttonStyle(.plain).help(store.t(key)).accessibilityLabel(store.t(key))
    }
}
