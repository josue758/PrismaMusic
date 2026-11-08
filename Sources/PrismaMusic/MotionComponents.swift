import Foundation
import SwiftUI

/// Accumulates active animation time so pausing never resets the visual phase.
struct MotionClock {
    private var accumulated: TimeInterval = 0
    private var startedAt: Date?
    func elapsed(at date: Date) -> TimeInterval {
        accumulated + (startedAt.map { max(0, date.timeIntervalSince($0)) } ?? 0)
    }
    mutating func setRunning(_ running: Bool, at date: Date) {
        if running && startedAt == nil {
            startedAt = date
        } else if !running && startedAt != nil {
            accumulated = elapsed(at: date)
            startedAt = nil
        }
    }
}
struct PrismaPressStyle: ButtonStyle {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.scaleEffect(
            configuration.isPressed && !reduced && store.preferences.microInteractions ? 0.95 : 1
        )
        .brightness(configuration.isPressed ? 0.035 : 0)
        .animation(
            reduced || !store.preferences.microInteractions ? nil : .spring(duration: 0.22, bounce: 0.16),
            value: configuration.isPressed)
    }
}
struct InteractiveDepth: ViewModifier {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @State private var size = CGSize(width: 1, height: 1)
    @State private var point = CGPoint.zero
    @State private var hover = false
    var radius: CGFloat
    var tilt: Double
    private var enabled: Bool { !reduced && store.preferences.microInteractions && store.preferences.hoverDepth }
    func body(content: Content) -> some View {
        content
            .overlay {
                RoundedRectangle(cornerRadius: radius).fill(
                    RadialGradient(
                        colors: [.white.opacity(hover ? 0.09 : 0), .clear],
                        center: UnitPoint(x: point.x + 0.5, y: point.y + 0.5), startRadius: 0,
                        endRadius: max(size.width, size.height) * 0.8)
                ).allowsHitTesting(false)
            }
            .rotation3DEffect(
                .degrees(enabled && hover ? -Double(point.y) * tilt : 0), axis: (x: 1, y: 0, z: 0), perspective: 0.35
            )
            .rotation3DEffect(
                .degrees(enabled && hover ? Double(point.x) * tilt : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.35
            )
            .scaleEffect(enabled && hover ? 1.012 : 1)
            .onGeometryChange(for: CGSize.self) {
                $0.size
            } action: {
                size = $0
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let location):
                    hover = true
                    point = CGPoint(
                        x: min(0.5, max(-0.5, location.x / max(1, size.width) - 0.5)),
                        y: min(0.5, max(-0.5, location.y / max(1, size.height) - 0.5)))
                case .ended:
                    hover = false
                    point = .zero
                }
            }
            .animation(enabled ? .spring(duration: 0.34, bounce: 0.12) : nil, value: hover)
            .animation(enabled ? .smooth(duration: 0.16) : nil, value: point)
    }
}
extension View {
    func interactiveDepth(radius: CGFloat = 20, tilt: Double = 5) -> some View {
        modifier(InteractiveDepth(radius: radius, tilt: tilt))
    }
}
struct FavoriteControl: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    var track: Track
    var size: CGFloat = 13
    var body: some View {
        Button {
            store.favorite(track)
        } label: {
            Image(systemName: track.favorite ? "heart.fill" : "heart").font(.system(size: size))
                .foregroundStyle(track.favorite ? store.effectiveAccent : .secondary.opacity(0.7))
                .contentTransition(
                    reduced || !store.preferences.microInteractions ? .identity : .symbolEffect(.replace)
                )
                .scaleEffect(track.favorite && !reduced && store.preferences.microInteractions ? 1.08 : 1)
                .animation(
                    reduced || !store.preferences.microInteractions ? nil : .spring(duration: 0.3, bounce: 0.32),
                    value: track.favorite
                )
                .frame(minWidth: 24, minHeight: 26)
        }.buttonStyle(PrismaPressStyle()).help(store.t("favorites")).accessibilityLabel(
            store.t(track.favorite ? "unfavoriteAction" : "favoriteAction"))
    }
}
struct FeedbackNotice: Identifiable {
    var id = UUID()
    var title: String
    var detail: String
    var icon: String
    var undo: FeedbackUndo?
}
enum FeedbackUndo {
    case favorite(String, Bool)
    case queue([String])
    case playlistAddition(UUID, String)
    case playlistRemoval(Playlist, Int)
}
struct FeedbackToast: View {
    @EnvironmentObject private var store: LibraryStore
    var notice: FeedbackNotice
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: notice.icon).font(.system(size: 16, weight: .medium)).foregroundStyle(
                store.effectiveAccent
            ).frame(width: 29, height: 29).background(store.effectiveAccent.opacity(0.10), in: Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(notice.title).font(.system(size: 11, weight: .semibold))
                if !notice.detail.isEmpty {
                    Text(notice.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            if notice.undo != nil {
                Button(store.t("undo")) { store.undoFeedback(id: notice.id) }.font(.system(size: 10, weight: .medium))
                    .buttonStyle(.glass)
            }
            Button {
                store.dismissFeedback(id: notice.id)
            } label: {
                Image(systemName: "xmark").font(.system(size: 9)).frame(width: 20, height: 26)
            }.buttonStyle(.plain).help(store.t("dismiss"))
        }.padding(.horizontal, 15).padding(.vertical, 12).frame(maxWidth: 440).prismaGlass(20, tinted: true).shadow(
            color: .black.opacity(0.18), radius: 20, y: 8
        ).accessibilityElement(children: .contain)
    }
}
struct ScrubTimeline: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    @Binding var value: Double
    var duration: Double
    var enabled = true
    @State private var hover = false
    @State private var preview: Double?
    @State private var draft: Double?
    @FocusState private var focused: Bool
    private var safeDuration: Double { duration.isFinite && duration > 0 ? duration : 1 }
    private var display: Double { min(safeDuration, max(0, draft ?? value)) }
    var body: some View {
        GeometryReader { geo in
            let width = max(1, geo.size.width)
            let fraction = display / safeDuration
            ZStack(alignment: .leading) {
                Capsule().fill(.primary.opacity(0.10)).frame(height: 3)
                Capsule().fill(
                    LinearGradient(
                        colors: [store.effectiveAccent.opacity(0.65), store.effectiveAccent], startPoint: .leading,
                        endPoint: .trailing)
                ).frame(width: max(0, width * fraction), height: hover || draft != nil ? 5 : 3)
                Circle().fill(store.effectiveAccent).frame(
                    width: hover || draft != nil || focused ? 10 : 5, height: hover || draft != nil || focused ? 10 : 5
                ).shadow(color: store.effectiveAccent.opacity(0.30), radius: 5).offset(
                    x: min(width - 5, max(0, width * fraction - 4)))
                if let time = draft ?? preview, enabled {
                    Text(clockText(time)).font(.system(size: 9, weight: .medium, design: .monospaced)).padding(
                        .horizontal, 8
                    ).padding(.vertical, 5).background(.regularMaterial, in: Capsule()).offset(
                        x: min(max(0, width - 52), max(0, width * time / safeDuration - 26)), y: -24
                    ).allowsHitTesting(false)
                }
            }.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).contentShape(Rectangle())
                .onContinuousHover { phase in
                    guard enabled else { return }
                    switch phase {
                    case .active(let point):
                        hover = true
                        preview = min(safeDuration, max(0, point.x / width * safeDuration))
                    case .ended:
                        hover = false
                        preview = nil
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 0).onChanged { gesture in
                        guard enabled else { return }
                        draft = min(safeDuration, max(0, gesture.location.x / width * safeDuration))
                    }.onEnded { gesture in
                        guard enabled else { return }
                        value = min(safeDuration, max(0, gesture.location.x / width * safeDuration))
                        draft = nil
                        focused = true
                    })
        }.frame(height: 16).opacity(enabled ? 1 : 0.3)
            .focusable(enabled).focused($focused).focusEffectDisabled()
            .onKeyPress(.leftArrow, phases: [.down, .repeat]) { press in
                guard enabled && press.modifiers.isEmpty else { return .ignored }
                value = max(0, value - 5)
                return .handled
            }
            .onKeyPress(.rightArrow, phases: [.down, .repeat]) { press in
                guard enabled && press.modifiers.isEmpty else { return .ignored }
                value = min(safeDuration, value + 5)
                return .handled
            }
            .accessibilityElement().accessibilityLabel(store.t("seekTime"))
            .accessibilityValue("\(clockText(value)) / \(clockText(duration))")
            .accessibilityAdjustableAction { direction in
                guard enabled else { return }
                switch direction {
                case .increment: value = min(safeDuration, value + 5)
                case .decrement: value = max(0, value - 5)
                @unknown default: break
                }
            }
            .help(store.t("scrubHelp"))
            .animation(reduced || !store.preferences.microInteractions ? nil : .smooth(duration: 0.16), value: hover)
    }
}

struct ChangingArtwork: View {
    @EnvironmentObject private var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduced
    var track: Track?
    var body: some View {
        ZStack {
            ArtworkView(track: track).id((track?.id ?? "empty") + ":" + (track?.artworkIdentity ?? ""))
                .transition(
                    reduced || !store.preferences.microInteractions
                        ? .opacity
                        : .asymmetric(
                            insertion: .opacity.combined(with: .scale(scale: 0.97)),
                            removal: .opacity.combined(with: .scale(scale: 1.025))))
        }.animation(reduced || !store.preferences.microInteractions ? nil : .smooth(duration: 0.5), value: track?.id)
    }
}
