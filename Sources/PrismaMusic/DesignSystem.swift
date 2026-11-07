import SwiftUI

struct PrismaBackdrop: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.colorScheme) var scheme
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                (scheme == .dark ? Color(red: 0.028, green: 0.032, blue: 0.055) : Color(red: 0.91, green: 0.93, blue: 0.97))
                Ellipse().fill(store.accent.color.opacity(0.36 * store.preferences.atmosphere)).frame(width: proxy.size.width * 0.75, height: proxy.size.height * 0.8).blur(radius: 110).offset(x: 120, y: -proxy.size.height * 0.4)
                Ellipse().fill(Color.cyan.opacity(0.20 * store.preferences.atmosphere)).frame(width: 500, height: 470).blur(radius: 100).offset(x: -proxy.size.width * 0.42, y: proxy.size.height * 0.4)
                Ellipse().fill(Color.pink.opacity(0.18 * store.preferences.atmosphere)).frame(width: 550, height: 400).blur(radius: 100).offset(x: proxy.size.width * 0.42, y: proxy.size.height * 0.27)
            }
        }.ignoresSafeArea().allowsHitTesting(false)
    }
}
struct GlassSurface: ViewModifier {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceTransparency) var reduceTransparency
    var radius: CGFloat
    var tinted: Bool
    func body(content: Content) -> some View {
        if reduceTransparency {
            content.background(.regularMaterial, in: RoundedRectangle(cornerRadius: radius)).overlay { RoundedRectangle(cornerRadius: radius).strokeBorder(.primary.opacity(0.10)) }
        } else {
            content.glassEffect(store.preferences.glassStyle == "clear" ? .clear.tint(tinted ? store.accent.color.opacity(0.12) : nil) : .regular.tint(tinted ? store.accent.color.opacity(0.09) : nil), in: RoundedRectangle(cornerRadius: radius))
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
        Button(action: action) { Image(systemName: icon).font(.system(size: 13, weight: .medium)).foregroundStyle(active ? store.accent.color : .primary.opacity(0.75)).frame(width: 35, height: 35) }.buttonStyle(.plain).glassEffect(.regular.tint(active ? store.accent.color.opacity(0.20) : nil).interactive(), in: Circle()).help(label).accessibilityLabel(label)
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
