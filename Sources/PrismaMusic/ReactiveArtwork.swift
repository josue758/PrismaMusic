import SwiftUI

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
