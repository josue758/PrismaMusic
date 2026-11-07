import SwiftUI
import AppKit

struct ArtworkView: View {
    var track: Track?
    private var seed: Int { (track?.album ?? "Prisma").unicodeScalars.reduce(0) { $0 + Int($1.value) } % 3 }
    private var palette: [Color] { seed == 0 ? [Color(red: 0.10, green: 0.06, blue: 0.24), Color(red: 0.53, green: 0.32, blue: 0.80), .pink] : seed == 1 ? [Color(red: 0.015, green: 0.16, blue: 0.19), .teal, Color(red: 0.61, green: 0.88, blue: 0.81)] : [Color(red: 0.26, green: 0.06, blue: 0.11), Color(red: 0.93, green: 0.37, blue: 0.28), Color(red: 1, green: 0.77, blue: 0.51)] }
    var body: some View {
        GeometryReader { proxy in
            if let data = track?.artwork {
                BitmapArtwork(data:data).frame(width:proxy.size.width,height:proxy.size.height).clipped()
            } else {
                LinearGradient(colors: palette, startPoint: .topLeading, endPoint: .bottomTrailing)
                    .overlay {
                        Canvas { context, size in
                            let center = CGPoint(x: size.width * 0.57, y: size.height * 0.48)
                            let r = min(size.width, size.height) * 0.32
                            var glow = context; glow.addFilter(.blur(radius: r * 0.6))
                            glow.fill(Path(ellipseIn: CGRect(x: center.x-r, y: center.y-r, width: r*2, height: r*2)), with: .color(.white.opacity(0.24)))
                            if seed == 1 {
                                for layer in 0..<16 {
                                    var path = Path()
                                    for step in 0...100 { let x = Double(step) / 100 * size.width; let y = size.height * 0.2 + Double(layer) * size.height * 0.047 + sin(Double(step) / 100 * 5 + Double(layer) * 0.16) * size.height * 0.16; if step == 0 { path.move(to: CGPoint(x:x,y:y)) } else { path.addLine(to: CGPoint(x:x,y:y)) } }
                                    context.stroke(path, with: .color(.white.opacity(0.09 + Double(layer % 4) * 0.06)), lineWidth: layer % 4 == 0 ? 2 : 0.7)
                                }
                            } else {
                                for i in 0..<12 {
                                    var ring = context; ring.translateBy(x: center.x, y: center.y); ring.rotate(by: .degrees(seed == 0 ? -28 : 30))
                                    let width = r * (0.6 + Double(i) * 0.17)
                                    ring.stroke(Path(ellipseIn: CGRect(x: -width, y: -width * 0.57, width: width*2, height: width*1.14)), with: .linearGradient(Gradient(colors: [.white.opacity(0.015), .white.opacity(0.6), .white.opacity(0.035)]), startPoint: CGPoint(x: -r, y: -r), endPoint: CGPoint(x:r,y:r)), lineWidth: i % 3 == 0 ? 1.5 : 0.65)
                                }
                            }
                            let orb = CGRect(x:center.x-r*0.62, y:center.y-r*0.62, width:r*1.24, height:r*1.24)
                            context.fill(Path(ellipseIn: orb), with: .radialGradient(Gradient(stops: [.init(color: .white.opacity(0.8), location: 0), .init(color: palette[2].opacity(0.8), location: 0.35), .init(color: palette[0].opacity(0.9), location: 1)]), center: CGPoint(x:center.x-r*0.22,y:center.y-r*0.25), startRadius: 0, endRadius: r*1.1))
                        }
                    }
                    .overlay(alignment: .topLeading) { if proxy.size.width > 100 { Text(track?.isDemo == true ? "P R I S M A   S E S S I O N S" : "P R I S M A   /   A U D I O").font(.system(size: max(6, proxy.size.width * 0.027), weight: .medium)).foregroundStyle(.white.opacity(0.65)).lineLimit(1).padding(proxy.size.width * 0.08) } }
                    .overlay(alignment: .bottomLeading) { if proxy.size.width > 130 { Text(seed == 0 ? "A M E T H Y S T" : seed == 1 ? "T I D A L" : "S O L S T I C E").font(.system(size: max(7, proxy.size.width * 0.035), weight: .light, design: .rounded)).foregroundStyle(.white.opacity(0.8)).padding(proxy.size.width * 0.08) } }
                    .frame(width: proxy.size.width, height: proxy.size.height).clipped()
            }
        }.clipShape(RoundedRectangle(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(0.12), lineWidth: 0.6) }
    }
}
struct PlayerBar: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        HStack(spacing: 25) {
            HStack(spacing: 13) {
                ArtworkView(track: store.current).frame(width: 55, height: 55).contentShape(Rectangle()).onTapGesture { store.showImmersive=true; store.showVisualizer=false }
                VStack(alignment: .leading, spacing: 5) {
                    Text(store.current?.title ?? store.t("choose")).font(.system(size: 13, weight: .semibold)).foregroundStyle(.primary)
                    Text(store.current?.artist ?? "Prisma Music").font(.system(size: 10)).foregroundStyle(.secondary)
                    if let track = store.current, store.preferences.showQuality { Text(track.qualitySummary).font(.system(size: 8, weight: .medium, design: .monospaced)).foregroundStyle(store.effectiveAccent.opacity(0.85)) }
                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading).contentShape(Rectangle()).onTapGesture { store.inspectedID = nil; store.showInfo.toggle(); store.showLyrics = false; store.showQueue = false }
                if let track = store.current { Button { store.favorite(track) } label: { Image(systemName: track.favorite ? "heart.fill" : "heart").font(.system(size: 12)).foregroundStyle(track.favorite ? store.effectiveAccent : .secondary) }.buttonStyle(.plain).help(store.t("favorites")) }
            }.frame(width: 275)
            VStack(spacing: 9) {
                HStack(spacing: 22) {
                    transport("shuffle", "shuffle", active: store.shuffle) { store.shuffle.toggle() }
                    transport("backward.end.fill", "previous") { store.next(back: true) }
                    Button { store.togglePlay() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").font(.system(size: 15, weight: .semibold)).frame(width: 43, height: 36) }.buttonStyle(.glassProminent).buttonBorderShape(.circle).help(store.t(store.isPlaying ? "pause" : "play"))
                    transport("forward.end.fill", "next") { store.next() }
                    transport(store.repeatMode == 2 ? "repeat.1" : "repeat", "repeat", active: store.repeatMode > 0) { store.repeatMode = (store.repeatMode + 1) % 3 }
                }
                HStack(spacing: 9) { Text(clockText(store.position)).frame(width: 32, alignment: .trailing); Slider(value: Binding(get: { store.position }, set: { store.seek($0) }), in: 0...max(1, store.current?.duration ?? 1)).controlSize(.mini).disabled(store.current == nil).accessibilityLabel(store.t("duration")); Text("−" + clockText(max(0, (store.current?.duration ?? 0) - store.position))).frame(width: 38, alignment: .leading) }.font(.system(size: 8, design: .monospaced)).foregroundStyle(.secondary)
            }.frame(maxWidth: .infinity)
            VStack(alignment: .trailing, spacing: 12) {
                HStack(spacing: 12) {
                    if store.sleepDeadline != nil { Button { store.openSettings("playback") } label: { Label(clockText(Double(store.sleepRemaining)), systemImage: "moon").font(.system(size: 8, design: .monospaced)) }.buttonStyle(.plain).foregroundStyle(store.effectiveAccent) }
                    Button { store.openSettings("sound") } label: { Text("EQ").font(.system(size: 9, weight: .semibold, design: .monospaced)).foregroundStyle(store.preferences.eqEnabled ? store.effectiveAccent : .secondary).padding(.horizontal, 7).padding(.vertical, 4).background(.primary.opacity(0.045), in: Capsule()) }.buttonStyle(.plain).help(store.t("equalizer"))
                    Button { store.miniPlayer() } label: { Image(systemName: "pip").font(.system(size: 12)) }.buttonStyle(.plain).help(store.t("mini"))
                    Button { store.fullScreen() } label: { Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 11)) }.buttonStyle(.plain).help(store.t("full"))
                }.foregroundStyle(.secondary)
                HStack(spacing: 9) { Image(systemName: store.volume == 0 ? "speaker.slash" : "speaker.wave.2").font(.system(size: 10)).foregroundStyle(.secondary); Slider(value: $store.volume, in: 0...1).controlSize(.mini).accessibilityLabel(store.t("volume")); Text("\(Int(store.volume * 100))").font(.system(size: 8, design: .monospaced)).foregroundStyle(.tertiary).frame(width: 22) }
            }.frame(width: 175)
        }
    }
    private func transport(_ icon: String, _ label: String, active: Bool = false, _ action: @escaping () -> Void) -> some View { Button(action: action) { Image(systemName: icon).font(.system(size: 12, weight: .medium)).foregroundStyle(active ? store.effectiveAccent : .primary.opacity(0.75)).frame(width: 19, height: 22) }.buttonStyle(.plain).help(store.t(label)) }
}
struct MiniPlayerView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ZStack { PrismaBackdrop(); VStack(spacing: 15) {
            ArtworkView(track: store.current).aspectRatio(1.2, contentMode: .fit)
            VStack(spacing: 5) { Text(store.current?.title ?? store.t("choose")).font(.system(size: 19, weight: .medium, design: .rounded)); Text(store.current?.artist ?? "Prisma Music").font(.caption).foregroundStyle(.secondary); if store.preferences.showQuality { Text(store.current?.qualitySummary ?? "").font(.system(size: 9, design: .monospaced)).foregroundStyle(store.effectiveAccent) } }.lineLimit(1)
            Slider(value: Binding(get: { store.position }, set: { store.seek($0) }), in: 0...max(1, store.current?.duration ?? 1)).controlSize(.mini).disabled(store.current == nil)
            HStack(spacing: 30) { Button { store.next(back: true) } label: { Image(systemName: "backward.end.fill") }; Button { store.togglePlay() } label: { Image(systemName: store.isPlaying ? "pause.fill" : "play.fill").frame(width: 40, height: 34) }.buttonStyle(.glassProminent).buttonBorderShape(.circle); Button { store.next() } label: { Image(systemName: "forward.end.fill") } }.buttonStyle(.plain)
        }.padding(22).padding(.top, 14) }.tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
    }
}
struct VisualizerView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        ZStack {
            Color(red: 0.01, green: 0.015, blue: 0.028)
            VisualizerCanvas(level: store.level, playing: store.isPlaying, color: store.effectiveAccent)
            VStack {
                HStack { HStack(spacing: 7) { Circle().fill(store.effectiveAccent).frame(width: 5, height: 5); Text("PRISMA / " + store.t(store.preferences.visualizerStyle).uppercased()).font(.system(size: 9, weight: .medium, design: .monospaced)).tracking(2) }; Spacer(); Menu { ForEach(["aurora", "orbit", "ribbons"], id: \.self) { mode in Button(store.t(mode)) { store.preferences.visualizerStyle = mode } } } label: { Image(systemName: "circle.hexagongrid").foregroundStyle(.white.opacity(0.6)) }.menuStyle(.borderlessButton).frame(width: 26) }.foregroundStyle(.white.opacity(0.55))
                Spacer()
                VStack(spacing: 10) { Text(store.t("now")).font(.system(size: 8, weight: .medium)).tracking(3).foregroundStyle(store.effectiveAccent); Text(store.current?.title ?? store.t("choose")).font(.system(size: 28, weight: .light, design: .rounded)); Text(store.current?.artist ?? "").font(.system(size: 11)).foregroundStyle(.white.opacity(0.5)) }.foregroundStyle(.white)
            }.padding(28)
        }.clipShape(RoundedRectangle(cornerRadius: 25)).overlay { RoundedRectangle(cornerRadius: 25).strokeBorder(.white.opacity(0.08)) }
    }
}
/// Audio-reactive geometry driven by measured post-DSP RMS. These are not FFT bins.
struct VisualizerCanvas: View {
    @EnvironmentObject var store: LibraryStore
    var level: Double
    var playing: Bool
    var color: Color
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    private var animated: Bool { playing && !reduceMotion && store.preferences.animateVisualizer }
    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / store.preferences.visualizerFPS, paused: !animated)) { timeline in
            Canvas { context, size in
                let time = animated ? timeline.date.timeIntervalSinceReferenceDate : 0
                let energy = min(1, pow(max(0, level), 0.55) * store.preferences.visualizerSensitivity)
                let center = CGPoint(x: size.width / 2, y: size.height * 0.43)
                let radius = min(size.width, size.height) * 0.22
                var haze = context; haze.addFilter(.blur(radius: radius * 0.55))
                haze.fill(Path(ellipseIn: CGRect(x: center.x-radius*1.3, y: center.y-radius, width: radius*2.6, height: radius*2)), with: .radialGradient(Gradient(colors: [color.opacity(0.20 + energy * 0.2), .clear]), center: center, startRadius: 0, endRadius: radius*1.5))
                for layer in 0..<14 {
                    var path = Path()
                    for point in 0...200 {
                        let fraction = Double(point) / 200
                        let angle = fraction * .pi * 2
                        let p: CGPoint
                        if store.preferences.visualizerStyle == "ribbons" {
                            p = CGPoint(x: fraction * size.width, y: center.y + Double(layer-7)*10 + sin(fraction*7+time*0.5+Double(layer)*0.2) * (25+energy*75) + cos(fraction*11-time*0.3)*energy*20)
                        } else {
                            let motion = store.preferences.visualizerStyle == "orbit" ? sin(angle*2+time*0.35)*energy*20 : sin(angle*3+time*0.55+Double(layer)*0.23)*(12+energy*45)+cos(angle*5-time*0.4)*energy*20
                            let r = radius + Double(layer)*5 + motion
                            p = CGPoint(x: center.x+cos(angle)*r*1.18, y:center.y+sin(angle)*r*(store.preferences.visualizerStyle == "orbit" ? 0.48 : 0.8))
                        }
                        if point == 0 { path.move(to: p) } else { path.addLine(to: p) }
                    }
                    if store.preferences.visualizerStyle != "ribbons" { path.closeSubpath() }
                    let tint = layer % 3 == 0 ? color : layer % 3 == 1 ? Color.cyan : Color.pink
                    if layer % 4 == 0 { var glow = context; glow.addFilter(.blur(radius: 6)); glow.stroke(path, with: .color(tint.opacity(0.40)), lineWidth: 5) }
                    context.stroke(path, with: .linearGradient(Gradient(colors: [tint.opacity(0.05), tint.opacity(0.65+energy*0.3), .white.opacity(0.5), tint.opacity(0.15)]), startPoint: .zero, endPoint: CGPoint(x:size.width,y:size.height)), lineWidth: layer % 3 == 0 ? 1.8 : 0.8)
                }
                for dot in 0..<45 {
                    let x = (Double(dot)*137.5).truncatingRemainder(dividingBy:max(1,size.width))
                    let y = (Double(dot)*71.1+time*Double(dot%3+1)*1.5).truncatingRemainder(dividingBy:max(1,size.height))
                    context.fill(Path(ellipseIn:CGRect(x:x,y:y,width:1.5,height:1.5)),with:.color(.white.opacity(0.12+energy*0.35)))
                }
            }
        }.accessibilityHidden(true)
    }
}
struct LyricsView: View {
    @EnvironmentObject var store: LibraryStore
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack { Text(store.t("lyrics")).font(.headline); Spacer(); Button { store.showLyrics = false } label: { Image(systemName: "xmark") }.buttonStyle(.plain) }
            if let track = store.current {
                ArtworkView(track: track).aspectRatio(1.6, contentMode: .fit)
                Text(track.title).font(.title3.bold()); Text(track.artist).font(.caption).foregroundStyle(.secondary)
                if let lyrics = track.lyrics, !lyrics.isEmpty {
                    let lines = LyricLine.parse(lyrics)
                    if lines.isEmpty { ScrollView { Text(lyrics).font(.system(size: store.preferences.lyricsFontSize, weight: .medium, design: .rounded)).lineSpacing(9).frame(maxWidth: .infinity, alignment: .leading) } }
                    else {
                        let active = lines.last { $0.time <= store.position + store.preferences.lyricsOffset }?.id
                        ScrollViewReader { proxy in
                            ScrollView { VStack(alignment: .leading, spacing: 20) { ForEach(lines) { line in Button { store.seek(line.time) } label: { Text(line.text.isEmpty ? "♪" : line.text).font(.system(size: store.preferences.lyricsFontSize, weight: .semibold, design: .rounded)).foregroundStyle(line.id == active ? store.effectiveAccent : Color.secondary.opacity(0.65)).frame(maxWidth: .infinity, alignment: .leading) }.buttonStyle(.plain).id(line.id) } }.padding(.vertical, 12) }
                                .onChange(of: active) { _, value in if store.preferences.autoScrollLyrics { withAnimation { proxy.scrollTo(value, anchor: .center) } } }
                        }
                    }
                    HStack { Text(track.lyricsCredit ?? "Archivo local"); Spacer(); if track.lyricsCredit == "LRCLIB" { Link("LRCLIB ↗", destination: URL(string: "https://lrclib.net")!) } }.font(.system(size: 9)).foregroundStyle(.tertiary)
                } else { Spacer(); Text(store.t("noLyrics")).font(.callout).foregroundStyle(.secondary); Spacer() }
                if !track.isDemo { Button { Task { await store.enrich(track) } } label: { if store.fetching { ProgressView().controlSize(.small) } else { Label(store.t("fetch"), systemImage: "sparkle.magnifyingglass") } }.disabled(store.fetching).font(.caption) }
                if let credit = track.artworkCredit, let url = URL(string: credit), url.scheme == "https" { Link("Artwork · iTunes ↗", destination: url).font(.system(size: 9)).foregroundStyle(.secondary) }
            } else { Spacer(); Text(store.t("choose")).foregroundStyle(.secondary); Spacer() }
        }.padding(20).padding(.top, 5)
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
                        ArtworkView(track: track).aspectRatio(1.6, contentMode: .fit)
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
        }.padding(20).padding(.top, 5)
    }
    private func detail(_ key: String, _ value: String?) -> some View {
        VStack(alignment: .leading, spacing: 5) { Text(store.t(key)).font(.system(size: 10)).foregroundStyle(.secondary); Text(value ?? store.t("unavailable")).font(.system(size: 13, weight: .medium, design: .rounded)).textSelection(.enabled) }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct BitmapArtwork: View {
    var data: Data
    @State private var image: NSImage?
    var body: some View {
        Group { if let image { Image(nsImage:image).resizable().scaledToFill() } else { Color.clear } }
            .task(id:data) { image = NSImage(data:data) }
    }
}
