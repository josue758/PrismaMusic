import SwiftUI

struct ImmersivePlayerView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    private var accent: Color { store.artworkPalette.primary.readable(onDark: true).color }
    var body: some View {
        GeometryReader { geo in
            if let track = store.visualTrack {
                ZStack {
                    Color(red: 0.035, green: 0.035, blue: 0.045)
                    if !reduceTransparency {
                        ArtworkView(track: track).frame(width: geo.size.width, height: geo.size.height).scaleEffect(1.5)
                            .blur(radius: 70).opacity(0.55)
                        LinearGradient(
                            colors: [.black.opacity(0.12), .black.opacity(0.35), .black.opacity(0.75)],
                            startPoint: .topLeading, endPoint: .bottomTrailing)
                    }
                    VStack(alignment: .leading, spacing: 20) {
                        header(track)
                        Spacer(minLength: 0)
                        if geo.size.width > 770 {
                            HStack(alignment: .center, spacing: 42) {
                                cover(track, size: min(geo.size.width * 0.43, geo.size.height * 0.65))
                                details(track).frame(maxWidth: .infinity, alignment: .leading)
                            }
                        } else {
                            VStack(spacing: 26) {
                                cover(track, size: min(geo.size.width * 0.64, geo.size.height * 0.42))
                                details(track)
                            }
                        }
                        Spacer(minLength: 0)
                        footer(track)
                    }.padding(32)
                }.frame(width: geo.size.width, height: geo.size.height).clipShape(RoundedRectangle(cornerRadius: 28))
                    .overlay {
                        RoundedRectangle(cornerRadius: 28).strokeBorder(
                            LinearGradient(
                                colors: [.white.opacity(0.22), .white.opacity(0.02)], startPoint: .topLeading,
                                endPoint: .bottomTrailing), lineWidth: 0.7)
                    }
            } else {
                ContentUnavailableView {
                    Label(store.t("empty"), systemImage: "opticaldisc")
                } description: {
                    Text(store.t("emptyNote"))
                } actions: {
                    Button(store.t("add")) { store.pickMusic() }.buttonStyle(.glassProminent)
                }
            }
        }.environment(\.colorScheme, .dark)
    }
    private func header(_ track: Track) -> some View {
        HStack {
            HStack(spacing: 8) {
                Circle().fill(accent).frame(width: 5, height: 5)
                Text(store.t(store.current == nil ? "readyToListen" : "now")).font(.system(size: 9, weight: .semibold))
                    .tracking(2.5)
            }.foregroundStyle(.white.opacity(0.75))
            Spacer()
            Button {
                store.showImmersive = false
                store.section = "albums"
            } label: {
                Label(store.t("backToLibrary"), systemImage: "square.stack").font(.system(size: 10))
            }.buttonStyle(.glass).tint(.white.opacity(0.7))
        }
    }
    private func cover(_ track: Track, size: CGFloat) -> some View {
        ReactiveArtwork(track: track)
            .frame(width: size, height: size)
            .overlay(alignment: .bottomTrailing) {
                Button {
                    if store.playbackLoading || store.currentID == track.id {
                        store.togglePlay()
                    } else {
                        store.play(track, in: store.filtered)
                    }
                } label: {
                    PlaybackControlSymbol().font(.system(size: 18, weight: .medium)).foregroundStyle(.white).frame(
                        width: 52, height: 52)
                }.buttonStyle(.plain).glassEffect(.clear.interactive(), in: Circle()).padding(18).help(
                    store.playbackControlLabel
                ).accessibilityLabel(store.playbackControlLabel)
            }
    }
    private func details(_ track: Track) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 8) {
                QualityBadge(track: track)
                if let rate = track.sampleRate {
                    Text(
                        [track.bitDepth.map { "\($0) bit" }, String(format: "%g kHz", rate / 1000)].compactMap { $0 }
                            .joined(separator: " / ")
                    ).font(.system(size: 8, design: .monospaced)).foregroundStyle(.white.opacity(0.45))
                }
            }
            Text(track.title).id(track.id).transition(.opacity).animation(
                reduceMotion || !store.preferences.microInteractions ? nil : .smooth(duration: 0.3), value: track.id
            ).font(.system(size: 36, weight: .bold, design: .rounded)).tracking(-0.8).foregroundStyle(.white).lineLimit(
                2
            ).minimumScaleFactor(0.65)
            Button {
                store.artist = track.artist
                store.section = "songs"
                store.showImmersive = false
                store.showVisualizer = false
            } label: {
                HStack(spacing: 8) {
                    Text(track.artist).font(.system(size: 20, weight: .medium))
                    Image(systemName: "chevron.right").font(.system(size: 10, weight: .semibold))
                }
            }.buttonStyle(.plain).foregroundStyle(accent).lineLimit(1)
            Text(track.album + (track.year.isEmpty ? "" : " · " + track.year)).font(.system(size: 12)).foregroundStyle(
                .white.opacity(0.5)
            ).lineLimit(2)
            HStack(spacing: 12) {
                FavoriteControl(track: track, size: 14).frame(width: 34, height: 32).glassEffect(
                    .regular, in: RoundedRectangle(cornerRadius: 10))
                Button {
                    store.inspectedID = track.id
                    store.showInfo.toggle()
                    store.showLyrics = false
                    store.showQueue = false
                } label: {
                    Image(systemName: "info.circle").font(.system(size: 14)).frame(width: 34, height: 32)
                }.buttonStyle(.glass).help(store.t("fileInfo"))
                Button {
                    store.showLyrics.toggle()
                    store.showInfo = false
                    store.showQueue = false
                } label: {
                    Image(systemName: "quote.bubble").font(.system(size: 14)).frame(width: 34, height: 32)
                }.buttonStyle(.glass).help(store.t("lyrics"))
            }.padding(.top, 4).tint(.white.opacity(0.6))
            if track.isDemo {
                Divider().overlay(.white.opacity(0.10)).padding(.vertical, 8)
                Label(store.t("instrumentalSession"), systemImage: "waveform").font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
                Text(store.t("immersiveDescription")).font(.system(size: 13, weight: .light, design: .rounded))
                    .lineSpacing(5).foregroundStyle(.white.opacity(0.4)).fixedSize(horizontal: false, vertical: true)
            } else if let lyrics = track.lyrics, !lyrics.isEmpty {
                lyricPreview(lyrics).padding(.top, 12)
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
    private func lyricPreview(_ lyrics: String) -> some View {
        let synced = LyricLine.parse(lyrics)
        let active = synced.lastIndex { $0.time <= store.position + store.preferences.lyricsOffset } ?? 0
        let lines =
            synced.isEmpty
            ? Array(lyrics.components(separatedBy: .newlines).filter { !$0.isEmpty }.prefix(3))
            : Array(synced.dropFirst(active).prefix(3).map(\.text))
        return VStack(alignment: .leading, spacing: 11) {
            ForEach(Array(lines.enumerated()), id: \.offset) { i, line in
                Text(line.isEmpty ? "♪" : line).font(
                    .system(size: i == 0 ? 23 : 19, weight: .semibold, design: .rounded)
                ).foregroundStyle(.white.opacity(i == 0 ? 0.9 : 0.25)).lineLimit(2).contentTransition(.opacity)
            }
        }.accessibilityLabel(store.t("lyrics"))
    }
    private func footer(_ track: Track) -> some View {
        HStack(spacing: 9) {
            HStack(spacing: 5) {
                ForEach(0..<5, id: \.self) { i in
                    Capsule().fill(accent.opacity(0.65)).frame(
                        width: 2,
                        height: 3
                            + (!reduceMotion && store.isPlaying && store.preferences.ambientMotion
                                ? store.ambientEnergy * Double([13, 24, 18, 28, 11][i]) : 3))
                }
            }.frame(height: 20).accessibilityHidden(true)
            Text(store.t(store.artworkPalette.extracted ? "paletteFromArtwork" : "paletteGenerated")).font(
                .system(size: 8, weight: .medium)
            ).tracking(1).foregroundStyle(.white.opacity(0.35))
            Spacer()
            Button {
                store.openSettings("appearance")
            } label: {
                Label(store.t("atmosphere"), systemImage: "slider.horizontal.3").font(.system(size: 9)).foregroundStyle(
                    .white.opacity(0.5))
            }.buttonStyle(.plain)
        }
    }
}
struct ReactiveArtwork: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var track: Track
    @State private var clock = MotionClock()
    private var moving: Bool { store.isPlaying && store.preferences.artworkPulse && !reduceMotion }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { timeline in
            let time = clock.elapsed(at: timeline.date) * 0.3
            let energy = store.preferences.artworkPulse && !reduceMotion ? store.ambientEnergy : 0
            ChangingArtwork(track: track)
                .scaleEffect(1 + energy * 0.018)
                .rotation3DEffect(.degrees(sin(time) * 0.9), axis: (x: 0, y: 1, z: 0))
                .shadow(
                    color: store.artworkPalette.primary.color.opacity(0.22 + energy * 0.14), radius: 24 + energy * 16,
                    y: 14
                )
                .overlay {
                    RoundedRectangle(cornerRadius: 14).strokeBorder(
                        LinearGradient(
                            colors: [.white.opacity(0.30), .white.opacity(0.025)], startPoint: .topLeading,
                            endPoint: .bottomTrailing), lineWidth: 0.8
                    ).allowsHitTesting(false)
                }
        }.onAppear { clock.setRunning(moving, at: Date()) }.onChange(of: moving) { _, running in
            clock.setRunning(running, at: Date())
        }
        .animation(reduceMotion ? nil : .easeOut(duration: 0.6), value: store.isPlaying).interactiveDepth(
            radius: 14, tilt: 6)
    }
}
