import SwiftUI

struct PrismaBackdrop: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.colorScheme) var scheme
    @Environment(\.accessibilityReduceMotion) var reduceMotion
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @State private var clock=MotionClock()
    var reactive = true
    private var moving: Bool { reactive && store.isPlaying && store.preferences.ambientMotion && !reduceMotion && !reduceTransparency }
    private var colors: [Color] { store.preferences.adaptiveArtwork ? store.artworkPalette.colors : [store.accent.color, .cyan, .pink] }
    var body: some View {
        GeometryReader { geo in
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !moving)) { timeline in
                let time = clock.elapsed(at:timeline.date)*0.13
                let energy = reactive && store.preferences.ambientMotion && !reduceMotion ? store.ambientEnergy : 0
                let light = store.preferences.atmosphere * (reactive ? 1 : 0.45)
                ZStack {
                    (scheme == .dark ? Color(red:0.025,green:0.025,blue:0.04) : Color(red:0.93,green:0.94,blue:0.97))
                    if !reduceTransparency {
                        MeshGradient(width: 3, height: 3, points: [
                            .init(0,0), .init(0.5,0), .init(1,0),
                            .init(0,0.5), .init(Float(0.5+sin(time)*0.12),Float(0.5+cos(time*0.8)*0.12)), .init(1,0.5),
                            .init(0,1), .init(0.5,1), .init(1,1)
                        ], colors: [colors[2],colors[0],colors[1], colors[0],colors[1],colors[2], colors[2],colors[0],colors[1]])
                        .opacity(light * (scheme == .dark ? 0.53 : 0.23) + energy * light * 0.08)
                        if reactive, store.preferences.adaptiveArtwork, let track = store.visualTrack, track.hasArtwork {
                            ArtworkView(track: track).frame(width:geo.size.width,height:geo.size.height).scaleEffect(1.35+energy*0.025).rotationEffect(.degrees(sin(time*0.6)*3)).offset(x:sin(time)*14,y:cos(time*0.7)*12).blur(radius:65).opacity(light * (scheme == .dark ? 0.24 : 0.12)).accessibilityHidden(true)
                        }
                        Ellipse().fill(colors[1].opacity(light*0.20)).frame(width:geo.size.width*0.7,height:geo.size.height*0.6).blur(radius:95).scaleEffect(1+energy*0.12).offset(x:geo.size.width*0.22+sin(time)*25,y:geo.size.height*0.25)
                    }
                    if scheme == .dark && !reduceTransparency { Color.black.opacity(0.22) }
                    LinearGradient(colors: scheme == .dark ? [.black.opacity(0.12),.clear,.black.opacity(0.62)] : [.white.opacity(0.22),.clear,.white.opacity(0.60)], startPoint:.top,endPoint:.bottom)
                }.frame(width:geo.size.width,height:geo.size.height).clipped()
            }
        }.ignoresSafeArea().allowsHitTesting(false).onAppear { clock.setRunning(moving,at:Date()) }.onChange(of:moving) { _,running in clock.setRunning(running,at:Date()) }.animation(reduceMotion ? nil : .easeInOut(duration:1.1),value:store.artworkPalette)
    }
}
struct GlassSurface: ViewModifier {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    @Environment(\.colorScheme) var scheme
    var radius: CGFloat
    var tinted: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius)).overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.10)) }
        } else {
            content
                .background((scheme == .dark ? Color.black : Color.white).opacity((1-store.preferences.glassTransparency)*0.20),in:RoundedRectangle(cornerRadius:radius))
                .glassEffect(store.preferences.glassStyle == "clear" || (store.showImmersive && store.preferences.glassTransparency > 0.55) ? .clear.tint(tinted ? store.effectiveAccent.opacity(0.10) : nil) : .regular.tint(tinted ? store.effectiveAccent.opacity(0.08) : nil), in: RoundedRectangle(cornerRadius: radius))
                .overlay { RoundedRectangle(cornerRadius:radius).strokeBorder(LinearGradient(colors:[.white.opacity(scheme == .dark ? 0.20 : 0.48),.white.opacity(0.025)],startPoint:.topLeading,endPoint:.bottomTrailing),lineWidth:0.65).allowsHitTesting(false) }
        }
    }
}
extension View {
    func prismaGlass(_ radius: CGFloat = 22, tinted: Bool = false) -> some View { modifier(GlassSurface(radius: radius, tinted: tinted)) }
}
struct GlassIconButton: View {
    @EnvironmentObject var store: LibraryStore
    var icon: String
    var label: String
    var active = false
    var action: () -> Void
    var body: some View {
        Button(action: action) { Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(active ? store.effectiveAccent : .primary.opacity(0.75)).frame(width: 35, height: 35) }.buttonStyle(PrismaPressStyle()).glassEffect(.regular.tint(active ? store.effectiveAccent.opacity(0.20) : nil).interactive(), in: Circle()).help(label).accessibilityLabel(label)
    }
}
struct QualityBadge: View {
    var track: Track
    var body: some View {
        HStack(spacing: 4) { Image(systemName: track.isLossless ? "waveform.badge.magnifyingglass" : "waveform"); Text(track.isLossless ? "LOSSLESS" : track.url.pathExtension.uppercased()) }.font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(0.5).padding(.horizontal, 7).padding(.vertical, 4).background(.primary.opacity(0.06), in: Capsule()).foregroundStyle(.secondary)
    }
}
struct SectionHeading: View {
    var title: String
    var subtitle: String? = nil
    var body: some View { VStack(alignment: .leading, spacing: 5) { Text(title).font(.system(size: 17, weight: .semibold, design: .rounded)); if let subtitle { Text(subtitle).font(.system(size: 11)).foregroundStyle(.secondary) } } }
}
