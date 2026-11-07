import SwiftUI
import AppKit

struct ArtworkView: View {
    var track: Track?
    var palette: [Color] {
        let seed = (track?.album ?? "Prisma").unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3
        return seed == 0 ? [Color(red: 0.24, green: 0.09, blue: 0.48), .purple, .pink] : seed == 1 ? [Color(red: 0.025, green: 0.20, blue: 0.26), .teal, .cyan] : [Color(red: 0.43, green: 0.12, blue: 0.14), .orange, .pink]
    }
    var body: some View {
        GeometryReader { proxy in
            if let data = track?.artwork, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill().frame(width: proxy.size.width, height: proxy.size.height).clipped()
            } else {
                ZStack {
                    LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    Circle().fill(.white.opacity(0.17)).frame(width: proxy.size.width * 0.8).blur(radius: proxy.size.width * 0.15).offset(x: proxy.size.width * 0.28, y: -proxy.size.height * 0.2)
                    ForEach(0..<7) { i in
                        Ellipse().stroke(.white.opacity(0.12 + Double(i) * 0.025), lineWidth: max(1, proxy.size.width / 170)).frame(width: proxy.size.width * (0.5 + Double(i) * 0.13), height: proxy.size.height * (0.3 + Double(i) * 0.10)).rotationEffect(.degrees(-35)).offset(y: proxy.size.height * 0.04)
                    }
                    Image(systemName: "waveform.path").font(.system(size: proxy.size.width * 0.24, weight: .ultraLight)).foregroundStyle(.white.opacity(0.8))
                    if proxy.size.width > 100 { VStack { HStack { Text("PRISMA SESSIONS").font(.system(size: max(7, proxy.size.width * 0.035), weight: .medium)).tracking(2); Spacer() }; Spacer(); HStack { Spacer(); Text("◌").font(.system(size: proxy.size.width * 0.15, weight: .ultraLight)) } }.padding(proxy.size.width * 0.10).foregroundStyle(.white.opacity(0.6)) }
                }.frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
struct PlayerBar: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        HStack(spacing: 16) {
            HStack(spacing: 12) {
                ArtworkView(track: store.current).frame(width: 49, height: 49).clipShape(RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 5) { Text(store.current?.title ?? store.t("choose")).font(.system(size: 12, weight: .semibold)); Text((store.current.map { $0.artist + ($0.qualitySummary.isEmpty ? "" : " · " + $0.qualitySummary) }) ?? "Prisma Music").font(.system(size: 10)).foregroundStyle(.secondary) }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if let track = store.current { Button { store.favorite(track) } label: { Image(systemName: track.favorite ? "heart.fill" : "heart").foregroundStyle(track.favorite ? store.accent.color : .secondary) }.buttonStyle(.plain).help(store.t("favorites")) }
            }.frame(width: 225)
            VStack(spacing: 5) {
                HStack(spacing: 22) {
                    Button { store.shuffle.toggle() } label: { Image(systemName: "shuffle").foregroundStyle(store.shuffle ? store.accent.color : .secondary) }.help(store.t("shuffle"))
                    Button { store.next(back: true) } label: { Image(systemName: "backward.end.fill") }.help(store.t("previous"))
                    Button { store.togglePlay() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 16, weight: .semibold)).frame(width: 36, height: 32) }.buttonStyle(.glassProminent).help(store.t(store.isPlaying ? "pause" : "play"))
                    Button { store.next() } label: { Image(systemName: "forward.end.fill") }.help(store.t("next"))
                    Button { store.repeatMode = (store.repeatMode + 1) % 3 } label: { Image(systemName: store.repeatMode == 2 ? "repeat.1" : "repeat").foregroundStyle(store.repeatMode > 0 ? store.accent.color : .secondary) }.help(store.t("repeat"))
                }.buttonStyle(.plain).font(.system(size: 12))
                HStack(spacing: 8) { Text(clockText(store.position)).frame(width: 34, alignment: .trailing); Slider(value: Binding(get: { store.position }, set: { store.seek($0) }), in: 0...max(1, store.current?.duration ?? 1)).controlSize(.mini).disabled(store.current == nil).accessibilityLabel("Playback position"); Text(clockText(store.current?.duration ?? 0)).frame(width: 34, alignment: .leading) }.font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            HStack(spacing: 8) { Image(systemName: store.volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 11)).foregroundStyle(.secondary); Slider(value: $store.volume, in: 0...1).controlSize(.mini).accessibilityLabel(store.t("volume")) }.frame(width: 110)
        }.padding(.horizontal, 6)
    }
}
struct MiniPlayerView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(spacing: 15) {
            ArtworkView(track: store.current).aspectRatio(1, contentMode: .fit).overlay { if store.showVisualizer { VisualizerCanvas(level: store.level, playing: store.isPlaying, color: store.accent.color).clipShape(RoundedRectangle(cornerRadius: 14)).opacity(0.6) } }
            VStack(spacing: 4) { Text(store.current?.title ?? store.t("choose")).font(.headline); Text(store.current?.artist ?? "Prisma Music").font(.caption).foregroundStyle(.secondary) }.lineLimit(1)
            Slider(value: Binding(get: { store.position }, set: { store.seek($0) }), in: 0...max(1, store.current?.duration ?? 1)).controlSize(.mini).disabled(store.current == nil)
            HStack(spacing: 30) { Button { store.next(back: true) } label: { Image(systemName: "backward.end.fill") }; Button { store.togglePlay() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").frame(width: 38, height: 32) }.buttonStyle(.glassProminent); Button { store.next() } label: { Image(systemName: "forward.end.fill") } }.buttonStyle(.plain)
        }.padding(22).padding(.top, 16).background(.ultraThinMaterial).tint(store.accent.color).preferredColorScheme(store.colorScheme)
    }
}
struct VisualizerView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ZStack {
            Color.black
            VisualizerCanvas(level: store.level, playing: store.isPlaying, color: store.accent.color)
            VStack {
                HStack { Text(store.t("visualizer").uppercased()).font(.system(size: 10, weight: .medium)).tracking(3); Spacer(); Text("PRISMA / AURORA").font(.system(size: 9, design: .monospaced)).tracking(2) }.foregroundStyle(.white.opacity(0.45))
                Spacer()
                VStack(spacing: 8) { Text(store.current?.title ?? store.t("choose")).font(.system(size: 28, weight: .light, design: .rounded)); Text(store.current?.artist ?? "").font(.system(size: 12)).foregroundStyle(.white.opacity(0.55)) }.foregroundStyle(.white)
            }.padding(30)
        }.clipShape(RoundedRectangle(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(.white.opacity(0.08)) }
    }
}
// The geometry reacts to the audio player's measured RMS level; it is not an FFT spectrum.
struct VisualizerCanvas: View {
    var level: Double
    var playing: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !playing || reduceMotion)) { timeline in
            Canvas { context, size in
                let time = reduceMotion ? 0 : timeline.date.timeIntervalSinceReferenceDate
                let energy = min(1, max(0, level))
                let center = CGPoint(x: size.width / 2, y: size.height * 0.45)
                for layer in 0..<9 {
                    var path = Path()
                    for point in 0...220 {
                        let angle = Double(point) / 220 * Double.pi * 2
                        let movement = sin(angle * 3 + time * 0.65 + Double(layer) * 0.3) * (10 + energy * 45) + cos(angle * 5 - time * 0.4) * energy * 22
                        let radius = min(size.width, size.height) * 0.20 + Double(layer) * 9 + movement
                        let p = CGPoint(x: center.x + cos(angle) * radius * 1.25, y: center.y + sin(angle) * radius * 0.78)
                        if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    path.closeSubpath()
                    var glow = context; glow.addFilter(.blur(radius: layer < 3 ? 14 : 2))
                    let tint = layer % 3 == 0 ? color : layer % 3 == 1 ? Color.cyan : Color.pink
                    glow.stroke(path, with: .color(tint.opacity(0.20 + energy * 0.20)), lineWidth: layer < 3 ? 6 : 1.5)
                }
                for dot in 0..<55 {
                    let x = (Double(dot) * 137.5).truncatingRemainder(dividingBy: max(1, size.width))
                    let y = (Double(dot) * 71.1 + (playing && !reduceMotion ? time * Double(dot % 3 + 1) * 2 : 0)).truncatingRemainder(dividingBy: max(1, size.height))
                    context.fill(Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)), with: .color(.white.opacity(0.15 + energy * 0.3)))
                }
            }
        }.accessibilityLabel("Audio reactive visualizer").accessibilityHidden(true)
    }
}
struct LyricsView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(store.t("lyrics")).font(.headline); Spacer(); Button { store.showLyrics = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            if let track = store.current {
                ArtworkView(track: track).aspectRatio(1, contentMode: .fit)
                Text(track.title).font(.title3.bold()); Text(track.artist).font(.caption).foregroundStyle(.secondary)
                if let lyrics = track.lyrics, !lyrics.isEmpty {
                    let lines = LyricLine.parse(lyrics)
                    if lines.isEmpty { ScrollView { Text(lyrics).font(.system(size: 17, weight: .medium, design: .rounded)).lineSpacing(9).frame(maxWidth: .infinity, alignment: .leading) } }
                    else {
                        let active = lines.last { $0.time <= store.position }?.id
                        ScrollViewReader { proxy in
                            ScrollView { VStack(alignment: .leading, spacing: 20) { ForEach(lines) { line in Button { store.seek(line.time) } label: { Text(line.text.isEmpty ? "♪" : line.text).font(.system(size: 20, weight: .semibold, design: .rounded)).foregroundStyle(line.id == active ? store.accent.color : Color.secondary.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).id(line.id) } }.padding(.vertical, 12) }
                                .onChange(of: active) { _, value in withAnimation { proxy.scrollTo(value, anchor: .center) } }
                        }
                    }
                    HStack { Text(track.lyricsCredit ?? "Archivo local"); Spacer(); if track.lyricsCredit == "LRCLIB" { Link("LRCLIB ↗", destination: URL(string: "https://lrclib.net")!) } }.font(.system(size: 9)).foregroundStyle(.tertiary)
                } else { Spacer(); Text(store.t("noLyrics")).font(.callout).foregroundStyle(.secondary); Spacer() }
                if !track.isDemo { Button { Task { await store.enrich(track) } } label: { if store.fetching { ProgressView().controlSize(.small) } else { Label(store.t("fetch"), systemImage: "sparkle.magnifyingglass") } }.disabled(store.fetching).font(.caption) }
                if let credit = track.artworkCredit, let url = URL(string: credit), url.scheme == "https" { Link("Artwork · iTunes ↗", destination: url).font(.system(size: 9)).foregroundStyle(.secondary) }
            } else { Spacer(); Text(store.t("choose")).foregroundStyle(.secondary); Spacer() }
        }.padding(22).padding(.top, 26)
    }
}

struct TrackInfoView: View {
    @EnvironmentObject var store: LibraryStore
    private var track: Track? { store.inspectedID.flatMap { id in store.tracks.first { $0.id == id } } ?? store.current }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(store.t("fileInfo")).font(.headline); Spacer(); Button { store.showInfo = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        ArtworkView(track: track).aspectRatio(1, contentMode: .fit)
                        VStack(alignment: .leading, spacing: 5) { Text(track.title).font(.title3.bold()); Text(track.artist).font(.caption).foregroundStyle(.secondary) }
                        Divider()
                        detail("format", track.format)
                        detail("bitrate", track.bitrate.map { "≈ \(Int(($0 / 1000).rounded())) kb/s" })
                        detail("fileSize", track.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                        if let bytes = track.fileSize { Text("\(bytes.formatted()) bytes").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary).textSelection(.enabled).padding(.top, -10) }
                        detail("sampleRate", track.sampleRate.map { String(format: "%g kHz", $0 / 1000) })
                        detail("channels", track.channels.map { $0 == 1 ? "1 · Mono" : $0 == 2 ? "2 · Stereo" : String($0) })
                        if let bits = track.bitDepth { detail("bitDepth", "\(bits) bit") }
                        detail("duration", clockText(track.duration))
                        Divider()
                        Text(store.t("bitrateNote")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(store.t("location")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text(track.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary).textSelection(.enabled).lineLimit(6)
                        Button { NSWorkspace.shared.activateFileViewerSelecting([track.url]) } label: { Label(store.t("reveal"), systemImage: "folder") }.font(.caption)
                    }.padding(.bottom, 15)
                }
            } else { Spacer(); Text(store.t("choose")).foregroundStyle(.secondary); Spacer() }
        }.padding(22).padding(.top, 26)
    }
    private func detail(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(store.t(key)).font(.system(size: 10)).foregroundStyle(.secondary); Text(value ?? store.t("unavailable")).font(.system(size: 13, weight: .medium, design: .rounded)).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}
