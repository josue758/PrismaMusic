import AppKit
import SwiftUI

struct ArtworkView: View {
    var track: Track?
    private var seed: Int { (track?.album ?? "Prisma").unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3 }
    private var palette: [Color] {
        seed == 0
            ? [Color(red: 0.10, green: 0.06, blue: 0.24), Color(red: 0.53, green: 0.32, blue: 0.80), .pink]
            : seed == 1
                ? [Color(red: 0.015, green: 0.16, blue: 0.19), .teal, Color(red: 0.61, green: 0.88, blue: 0.81)]
                : [
                    Color(red: 0.26, green: 0.06, blue: 0.11), Color(red: 0.93, green: 0.37, blue: 0.28),
                    Color(red: 1, green: 0.77, blue: 0.51),
                ]
    }
    var body: some View {
        GeometryReader { proxy in
            if let track, track.hasArtwork {
                BitmapArtwork(track: track, pixels: Int(proxy.size.width * 2)).frame(
                    width: proxy.size.width, height: proxy.size.height
                ).clipped()
            } else {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width * 0.57, y: size.height * 0.48)
                            let r = min(size.width, size.height) * 0.32
                            var glow = context
                            glow.addFilter(.blur(radius: r * 0.6))
                            glow.fill(
                                Path(ellipseIn: CGRect(x: center.x - r, y: center.y - r, width: r * 2, height: r * 2)),
                                with: .color(.white.opacity(0.24)))
                            if seed == 1 {
                                for layer in 0..<16 {
                                    var path = Path()
                                    for step in 0...100 {
                                        let x = Double(step) / 100 * size.width
                                        let y =
                                            size.height * 0.2 + Double(layer) * size.height * 0.047 + sin(
                                                Double(step) / 100 * 5 + Double(layer) * 0.16) * size.height * 0.16
                                        if step == 0 {
                                            path.move(to: CGPoint(x: x, y: y))
                                        } else {
                                            path.addLine(to: CGPoint(x: x, y: y))
                                        }
                                    }
                                    context.stroke(
                                        path, with: .color(.white.opacity(0.09 + Double(layer % 4) * 0.06)),
                                        lineWidth: layer % 4 == 0 ? 2 : 0.7)
                                }
                            } else {
                                for i in 0..<12 {
                                    var ring = context
                                    ring.translateBy(x: center.x, y: center.y)
                                    ring.rotate(by: .degrees(seed == 0 ? -28 : 30))
                                    let width = r * (0.6 + Double(i) * 0.17)
                                    ring.stroke(
                                        Path(
                                            ellipseIn: CGRect(
                                                x: -width, y: -width * 0.57, width: width * 2, height: width * 1.14)),
                                        with: .linearGradient(
                                            Gradient(colors: [
                                                .white.opacity(0.015), .white.opacity(0.6), .white.opacity(0.035),
                                            ]), startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x: r, y: r)),
                                        lineWidth: i % 3 == 0 ? 1.5 : 0.65)
                                }
                            }
                            let orb = CGRect(
                                x: center.x - r * 0.62, y: center.y - r * 0.62, width: r * 1.24, height: r * 1.24)
                            context.fill(
                                Path(ellipseIn: orb),
                                with: .radialGradient(
                                    Gradient(stops: [
                                        .init(color: .white.opacity(0.8), location: 0),
                                        .init(color: palette[2].opacity(0.8), location: 0.35),
                                        .init(color: palette[0].opacity(0.9), location: 1),
                                    ]), center: CGPoint(x: center.x - r * 0.22, y: center.y - r * 0.25), startRadius: 0,
                                    endRadius: r * 1.1))
                        }
                    }
                    .overlay(alignment: .topLeading) {
                        if proxy.size.width > 100 {
                            Text(
                                track?.isDemo == true ? "P R I S M A   S E S S I O N S" : "P R I S M A   /   A U D I O"
                            ).font(.system(size: max(6, proxy.size.width * 0.027), weight: .medium)).foregroundStyle(
                                .white.opacity(0.65)
                            ).lineLimit(1).padding(proxy.size.width * 0.08)
                        }
                    }
                    .overlay(alignment: .bottomLeading) {
                        if proxy.size.width > 130 {
                            Text(seed == 0 ? "A M E T H Y S T" : seed == 1 ? "T I D A L" : "S O L S T I C E").font(
                                .system(size: max(7, proxy.size.width * 0.035), weight: .light, design: .rounded)
                            ).foregroundStyle(.white.opacity(0.8)).padding(proxy.size.width * 0.08)
                        }
                    }
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14)).overlay {
            RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.6)
        }
    }
}
struct PlaybackArtistLink: View {
    @EnvironmentObject private var store: LibraryStore
    let track: Track
    var afterOpen: () -> Void = {}

    private var artists: [String] {
        ArtistIdentity.names(track.artist).filter { $0 != "—" }
    }

    var body: some View {
        if artists.count > 1 {
            Menu {
                ForEach(artists, id: \.self) { artist in
                    Button(artist) { open(artist) }
                }
            } label: {
                Text(artists.joined(separator: " · ")).lineLimit(1)
            }.menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize(horizontal: false, vertical: true)
                .help(store.t("openArtistProfile"))
        } else if let artist = artists.first {
            Button {
                open(artist)
            } label: {
                Text(artist).lineLimit(1)
            }
            .buttonStyle(.plain).help(store.t("openArtistProfile"))
        } else {
            Text(store.displayArtist(track.artist))
        }
    }

    private func open(_ artist: String) {
        store.openArtist(artist)
        afterOpen()
    }
}

struct PlayerBar: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        HStack(spacing: 25) {
            HStack(spacing: 13) {
                Button {
                    store.fullScreen()
                } label: {
                    ChangingArtwork(track: store.current).frame(width: 55, height: 55).contentShape(Rectangle())
                }.buttonStyle(.plain).help(store.t("full")).accessibilityLabel(store.t("full"))
                VStack(alignment: .leading, spacing: 5) {
                    if let track = store.current {
                        Button {
                            store.openAlbum(track, revealTrack: true)
                        } label: {
                            Text(track.title).foregroundStyle(.primary)
                        }.buttonStyle(.plain).font(.system(size: 13, weight: .semibold))
                            .help(store.t("openAlbum"))
                        PlaybackArtistLink(track: track).font(.system(size: 10)).foregroundStyle(.secondary)
                    } else {
                        Text(store.t("choose")).font(.system(size: 13, weight: .semibold))
                        Text("Prisma Music").font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    if let track = store.current, store.preferences.showQuality {
                        Text(track.qualitySummary).font(.system(size: 8, weight: .medium, design: .monospaced))
                            .foregroundStyle(store.effectiveAccent.opacity(0.85))
                    }
                }.lineLimit(1).id(store.currentID).transition(.opacity).animation(
                    reduceMotion || !store.preferences.microInteractions ? nil : .smooth(duration: 0.25),
                    value: store.currentID
                ).frame(maxWidth: .infinity, alignment: .leading)
                if let track = store.current { FavoriteControl(track: track, size: 12) }
            }.frame(width: 275)
            VStack(spacing: 9) {
                HStack(spacing: 22) {
                    transport("shuffle", "shuffle", active: store.shuffle) { store.shuffle.toggle() }
                    transport("backward.end.fill", "previous") { store.next(back: true) }
                    Button {
                        store.togglePlay()
                    } label: {
                        PlaybackControlSymbol().contentTransition(
                            reduceMotion || !store.preferences.microInteractions ? .identity : .symbolEffect(.replace)
                        ).animation(
                            reduceMotion || !store.preferences.microInteractions ? nil : .smooth(duration: 0.2),
                            value: store.isPlaying
                        ).font(.system(size: 15, weight: .semibold)).frame(width: 43, height: 36)
                    }.buttonStyle(.glassProminent).buttonBorderShape(.circle).help(store.playbackControlLabel)
                        .accessibilityLabel(store.playbackControlLabel)
                    transport("forward.end.fill", "next") { store.next() }
                    transport(store.repeatMode == 2 ? "repeat.1" : "repeat", "repeat", active: store.repeatMode > 0) {
                        store.repeatMode = (store.repeatMode + 1) % 3
                    }
                }
                HStack(spacing: 9) {
                    Text(clockText(store.position)).frame(width: 32, alignment: .trailing)
                    ScrubTimeline(
                        value: Binding(get: { store.position }, set: { store.seek($0) }),
                        duration: store.current?.duration ?? 0, enabled: store.current != nil)
                    Text("−" + clockText(max(0, (store.current?.duration ?? 0) - store.position))).frame(
                        width: 38, alignment: .leading)
                }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    if store.sleepDeadline != nil {
                        Button {
                            store.openSettings("playback")
                        } label: {
                            Label(clockText(Double(store.sleepRemaining)), systemImage: "moon").font(
                                .system(size: 8, design: .monospaced))
                        }.buttonStyle(.plain).foregroundStyle(store.effectiveAccent)
                    }
                    Button {
                        store.openSettings("sound")
                    } label: {
                        Text("EQ").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(
                            store.preferences.eqEnabled ? store.effectiveAccent : .secondary
                        ).padding(.horizontal, 7).padding(.vertical, 4).background(
                            .primary.opacity(0.045), in: Capsule())
                    }.buttonStyle(.plain).help(store.t("equalizer")).accessibilityLabel(store.t("equalizer"))
                    OutputToolbarButton()
                    AirPlayRouteButton().frame(width: 24, height: 22).help("AirPlay")
                    Button {
                        store.miniPlayer()
                    } label: {
                        Image(systemName: "pip").font(.system(size: 12))
                    }.buttonStyle(.plain).help(store.t("mini")).accessibilityLabel(store.t("mini"))
                    Button {
                        store.fullScreen()
                    } label: {
                        Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11))
                    }.buttonStyle(.plain).help(store.t("full")).accessibilityLabel(store.t("full"))
                }.foregroundStyle(.secondary)
                PlaybackVolumeControl(showsPercentage: true).controlSize(.mini)
            }.frame(width: 215)
        }
    }
    private func transport(_ icon: String, _ label: String, active: Bool = false, _ action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(
                active ? store.effectiveAccent : .primary.opacity(0.75)
            ).frame(width: 19, height: 22)
        }.buttonStyle(PrismaPressStyle()).help(store.t(label)).accessibilityLabel(store.t(label))
            .accessibilityValue(store.transportAccessibilityValue(label))
    }
}
extension LibraryStore {
    func transportAccessibilityValue(_ key: String) -> String {
        switch key {
        case "shuffle": return t(shuffle ? "on" : "off")
        case "repeat": return t(repeatMode == 2 ? "repeatOne" : repeatMode == 1 ? "repeatAll" : "off")
        default: return ""
        }
    }
}
struct MiniPlayerView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ZStack {
            PrismaBackdrop()
            VStack(spacing: 15) {
                ChangingArtwork(track: store.current).aspectRatio(1.2, contentMode: .fit)
                VStack(spacing: 5) {
                    Text(store.current?.title ?? store.t("choose")).font(
                        .system(size: 19, weight: .medium, design: .rounded))
                    Text(store.current?.artist ?? "Prisma Music").font(.caption).foregroundStyle(.secondary)
                    if store.preferences.showQuality {
                        Text(store.current?.qualitySummary ?? "").font(.system(size: 9, design: .monospaced))
                            .foregroundStyle(store.effectiveAccent)
                    }
                }.lineLimit(1)
                ScrubTimeline(
                    value: Binding(get: { store.position }, set: { store.seek($0) }),
                    duration: store.current?.duration ?? 0, enabled: store.current != nil)
                HStack(spacing: 30) {
                    Button {
                        store.next(back: true)
                    } label: {
                        Image(systemName: "backward.end.fill")
                    }
                    Button {
                        store.togglePlay()
                    } label: {
                        PlaybackControlSymbol().contentTransition(
                            reduceMotion || !store.preferences.microInteractions ? .identity : .symbolEffect(.replace)
                        ).animation(
                            reduceMotion || !store.preferences.microInteractions ? nil : .smooth(duration: 0.2),
                            value: store.isPlaying
                        ).frame(width: 40, height: 34)
                    }.buttonStyle(.glassProminent).buttonBorderShape(.circle)
                    Button {
                        store.next()
                    } label: {
                        Image(systemName: "forward.end.fill")
                    }
                }.buttonStyle(.plain)
            }.padding(22).padding(.top, 14)
        }.tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
    }
}
struct VisualizerView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.015, blue: 0.028)
            VisualizerCanvas(level: store.level, playing: store.isPlaying, color: store.effectiveAccent)
            VStack {
                HStack {
                    HStack(spacing: 7) {
                        Circle().fill(store.effectiveAccent).frame(width: 5, height: 5)
                        Text("PRISMA / " + store.t(store.preferences.visualizerStyle).uppercased()).font(
                            .system(size: 9, weight: .medium, design: .monospaced)
                        ).tracking(2)
                    }
                    Spacer()
                    VisualizerOptionsButton()
                }.foregroundStyle(.white.opacity(0.55))
                Spacer()
                VStack(spacing: 10) {
                    Text(store.t("now")).font(.system(size: 8, weight: .medium)).tracking(3).foregroundStyle(
                        store.effectiveAccent)
                    Text(store.current?.title ?? store.t("choose")).font(
                        .system(size: 28, weight: .light, design: .rounded))
                    Text(store.current?.artist ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5))
                }.foregroundStyle(.white)
            }.padding(28)
        }.clipShape(RoundedRectangle(cornerRadius: 25)).overlay {
            RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.08))
        }
    }
}
/// Audio-reactive geometry with post-DSP RMS and optional measured spectrum data.
struct VisualizerCanvas: View {
    @EnvironmentObject var store: LibraryStore
    var level: Double
    var playing: Bool
    var color: Color
    var bands: [Float] = []
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private var animated: Bool { playing && !reduceMotion && store.preferences.animateVisualizer }
    var body: some View {
        TimelineView(.animation(minimumInterval: store.preferences.visualizerFrameInterval, paused: !animated)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                let energy = reduceMotion || !store.preferences.animateVisualizer ? 0.18 :
                    min(1, pow(max(0, level), 0.55) * store.preferences.visualizerSensitivity)
                let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
                let radius = min(size.width, size.height) * 0.22
                let style = store.preferences.visualizerStyle
                var haze = context
                haze.addFilter(.blur(radius: radius * 0.55))
                haze.fill(
                    Path(
                        ellipseIn: CGRect(
                            x: center.x - radius * 1.3, y: center.y - radius, width: radius * 2.6, height: radius * 2)),
                    with: .radialGradient(
                        Gradient(colors: [color.opacity(0.20 + energy * 0.2), .clear]), center: center, startRadius: 0,
                        endRadius: radius * 1.5))
                switch style {
                case "bars", "mirror", "centered":
                    drawBars(in: context, size: size, style: style, time: time, energy: energy)
                    return
                case "nebula":
                    drawNebula(in: context, size: size, time: time, energy: energy)
                    return
                case "orbit":
                    drawOrbit(in: context, center: center, radius: radius, time: time, energy: energy)
                    return
                default:
                    break
                }
                for layer in 0..<14 {
                    var path = Path()
                    for point in 0...200 {
                        let fraction = Double(point) / 200
                        let angle = fraction * .pi * 2
                        let p: CGPoint
                        if style == "ribbons" {
                            p = CGPoint(
                                x: fraction * size.width,
                                y: center.y + Double(layer - 7) * 10 + sin(
                                    fraction * 7 + time * 0.5 + Double(layer) * 0.2) * (25 + energy * 75) + cos(
                                        fraction * 11 - time * 0.3) * energy * 20)
                        } else {
                            let motion = sin(angle * 3 + time * 0.55 + Double(layer) * 0.23) * (12 + energy * 45) + cos(
                                    angle * 5 - time * 0.4) * energy * 20
                            let r = radius + Double(layer) * 5 + motion
                            p = CGPoint(
                                x: center.x + cos(angle) * r * 1.18,
                                y: center.y + sin(angle) * r * 0.8)
                        }
                        if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    if style != "ribbons" { path.closeSubpath() }
                    let tint = layer % 3 == 0 ? color : layer % 3 == 1 ? Color.cyan : Color.pink
                    if layer % 4 == 0 {
                        var glow = context
                        glow.addFilter(.blur(radius: 6))
                        glow.stroke(path, with: .color(tint.opacity(0.40)), lineWidth: 5)
                    }
                    context.stroke(
                        path,
                        with: .linearGradient(
                            Gradient(colors: [
                                tint.opacity(0.05), tint.opacity(0.65 + energy * 0.3), .white.opacity(0.5),
                                tint.opacity(0.15),
                            ]), startPoint: .zero, endPoint: CGPoint(x: size.width, y: size.height)),
                        lineWidth: layer % 3 == 0 ? 1.8 : 0.8)
                }
                for dot in 0..<45 {
                    let x = (Double(dot) * 137.5).truncatingRemainder(dividingBy: max(1, size.width))
                    let y = (Double(dot) * 71.1 + time * Double(dot % 3 + 1) * 1.5).truncatingRemainder(
                        dividingBy: max(1, size.height))
                    context.fill(
                        Path(ellipseIn: CGRect(x: x, y: y, width: 1.5, height: 1.5)),
                        with: .color(.white.opacity(0.12 + energy * 0.35)))
                }
            }
        }.id(store.preferences.visualizerFPS).accessibilityHidden(true)
    }
    private func drawBars(in context: GraphicsContext, size: CGSize, style: String, time: Double, energy: Double) {
        let count = size.width < 350 ? 28 : 72
        let step = size.width * 0.91 / Double(count)
        for index in 0..<count {
            let fraction = Double(index) / Double(max(1, count - 1))
            let phase = style == "mirror" ? abs(fraction - 0.5) * 2 : fraction
            let wave = abs(sin(phase * 18 - time * 2) * cos(phase * 8 + time * 0.6))
            let strength = bandStrength(at: phase, fallback: (0.08 + wave * 0.49) * energy)
            let height = max(2, size.height * (0.015 + strength * 0.49))
            let y = style == "bars" ? size.height * 0.69 - height : size.height * 0.43 - height / 2
            let rect = CGRect(x: size.width * 0.045 + Double(index) * step, y: y, width: step * 0.62, height: height)
            context.fill(
                Path(roundedRect: rect, cornerRadius: min(5, step * 0.3)),
                with: .linearGradient(
                    Gradient(colors: [.cyan.opacity(0.28), color.opacity(0.8), .white.opacity(0.8)]),
                    startPoint: CGPoint(x: rect.midX, y: rect.maxY), endPoint: CGPoint(x: rect.midX, y: rect.minY)))
        }
    }
    private func drawNebula(in context: GraphicsContext, size: CGSize, time: Double, energy: Double) {
        for index in 0..<135 {
            let seed = Double(index)
            let dx = abs(sin(seed * 12.9898) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let dy = abs(sin(seed * 78.233) * 43758.5453).truncatingRemainder(dividingBy: 1)
            let x = size.width * dx + sin(time * 0.18 + seed) * (4 + energy * 26)
            let y = size.height * dy + cos(time * 0.18 + seed) * (4 + energy * 18)
            let radius = 0.8 + Double(index % 5) * (0.3 + energy * 0.65)
            let tint: Color = index % 3 == 0 ? color : index % 3 == 1 ? .cyan : .purple
            let glow = CGRect(x: x - radius * 3, y: y - radius * 3, width: radius * 6, height: radius * 6)
            context.fill(Path(ellipseIn: glow), with: .radialGradient(
                Gradient(colors: [tint.opacity(0.32 + energy * 0.30), .clear]),
                center: CGPoint(x: x, y: y), startRadius: 0, endRadius: radius * 3))
            context.fill(Path(ellipseIn: CGRect(x: x - radius / 2, y: y - radius / 2, width: radius, height: radius)),
                         with: .color(.white.opacity(0.4 + energy * 0.4)))
        }
    }
    private func drawOrbit(in context: GraphicsContext, center: CGPoint, radius: Double, time: Double, energy: Double) {
        let ring = CGRect(x: center.x - radius, y: center.y - radius, width: 2 * radius, height: 2 * radius)
        context.stroke(Path(ellipseIn: ring), with: .color(color.opacity(0.53)), lineWidth: 2)
        for index in 0..<96 {
            let angle = Double(index) / 96 * 2 * .pi
            let wave = abs(sin(angle * 5 - time) * cos(angle * 4)) * energy
            let length = 2 + radius * (0.05 + bandStrength(at: Double(index % 48) / 47, fallback: wave) * 0.65)
            var ray = Path()
            ray.move(to: CGPoint(x: center.x + cos(angle) * radius, y: center.y + sin(angle) * radius))
            ray.addLine(to: CGPoint(x: center.x + cos(angle) * (radius + length),
                                    y: center.y + sin(angle) * (radius + length)))
            context.stroke(ray, with: .color((index % 4 == 0 ? Color.cyan : color).opacity(0.62)), lineWidth: 2)
        }
    }
    private func bandStrength(at position: Double, fallback: Double) -> Double {
        guard !bands.isEmpty, !reduceMotion, store.preferences.animateVisualizer else { return fallback }
        let index = min(bands.count - 1, max(0, Int(position * Double(bands.count - 1))))
        return min(1, Double(bands[index]) * store.preferences.visualizerSensitivity)
    }
}
struct LyricsView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.t("lyrics")).font(.headline)
                Spacer()
                Button {
                    store.showLyrics = false
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain).help(store.t("close"))
            }
            if let track = store.current {
                Text(track.title).font(.title3.bold()).lineLimit(2)
                Text(store.displayArtist(track.artist)).font(.caption).foregroundStyle(.secondary)
                BilingualLyricsView(track: track).frame(maxHeight: .infinity)
            } else {
                ContentUnavailableView { Label(store.t("choose"), systemImage: "music.note") }
            }
        }.padding(20).padding(.top, 5)
    }
}

struct TrackInfoView: View {
    @EnvironmentObject var store: LibraryStore
    private var track: Track? { store.inspectedID.flatMap { store.track(for: $0) } ?? store.current }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(store.t("fileInfo")).font(.headline)
                Spacer()
                Button {
                    store.showInfo = false
                } label: {
                    Image(systemName: "xmark")
                }.buttonStyle(.plain)
            }
            if let track {
                ScrollView {
                    VStack(alignment: .leading, spacing: 17) {
                        ArtworkView(track: track).aspectRatio(1.6, contentMode: .fit)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(track.title).font(.title3.bold())
                            Text(track.artist).font(.caption).foregroundStyle(.secondary)
                        }
                        Divider()
                        detail("format", track.format)
                        detail("bitrate", track.bitrate.map { "≈ \(Int(($0 / 1000).rounded())) kb/s" })
                        detail(
                            "fileSize",
                            track.fileSize.map { ByteCountFormatter.string(fromByteCount: $0, countStyle: .file) })
                        if let bytes = track.fileSize {
                            Text("\(bytes.formatted()) bytes").font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.tertiary).textSelection(.enabled).padding(.top, -10)
                        }
                        detail("sampleRate", track.sampleRate.map { String(format: "%g kHz", $0 / 1000) })
                        detail(
                            "channels",
                            track.channels.map { $0 == 1 ? "1 · Mono" : $0 == 2 ? "2 · Stereo" : String($0) })
                        if let bits = track.bitDepth { detail("bitDepth", "\(bits) bit") }
                        detail("duration", clockText(track.duration))
                        let edited = store.locallyEditedFields(for: track)
                        if !edited.isEmpty {
                            Divider()
                            detail("localTagCorrections", edited.map { store.t($0.rawValue) }.joined(separator: " · "))
                        }
                        Divider()
                        Text(store.t("bitrateNote")).font(.system(size: 10)).foregroundStyle(.secondary)
                        Text(store.t("location")).font(.system(size: 10, weight: .medium)).foregroundStyle(.secondary)
                        Text(track.url.path).font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary)
                            .textSelection(.enabled).lineLimit(6)
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([track.url])
                        } label: {
                            Label(store.t("reveal"), systemImage: "folder")
                        }.font(.caption)
                    }.padding(.bottom, 15)
                }
            } else {
                Spacer()
                Text(store.t("choose")).foregroundStyle(.secondary)
                Spacer()
            }
        }.padding(20).padding(.top, 5)
    }
    private func detail(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(store.t(key)).font(.system(size: 10)).foregroundStyle(.secondary)
            Text(value ?? store.t("unavailable")).font(.system(size: 13, weight: .medium, design: .rounded))
                .textSelection(.enabled)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BitmapArtwork: View {
    var track: Track
    var pixels: Int
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage: image).resizable().scaledToFill() } else { Color.clear } }
            .task(id: track.artworkIdentity + String(pixels)) {
                let value = await Task.detached(priority: .utility) {
                    ArtworkCache.shared.image(for: track, pixels: pixels)
                }.value
                guard !Task.isCancelled else { return }
                image = value
            }.onDisappear { image = nil }
    }
}

struct PlaybackControlSymbol: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        Group {
            if store.playbackLoading || store.playbackBuffering {
                ProgressView().controlSize(.small)
            } else {
                Image(systemName: store.isPlaying ? "pause.fill" : "play.fill")
            }
        }.accessibilityLabel(store.playbackControlLabel)
    }
}
