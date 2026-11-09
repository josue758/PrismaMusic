import AVKit
import SwiftUI

struct AirPlayRouteButton: NSViewRepresentable {
    @EnvironmentObject var store: LibraryStore
    func makeCoordinator() -> Coordinator { Coordinator(store) }
    func makeNSView(context: Context) -> AVRoutePickerView {
        let view = AVRoutePickerView()
        view.player = store.airPlayPlayer
        view.delegate = context.coordinator
        view.isRoutePickerButtonBordered = false
        view.setAccessibilityLabel("AirPlay")
        return view
    }
    func updateNSView(_ view: AVRoutePickerView, context: Context) { view.player = store.airPlayPlayer }
    final class Coordinator: NSObject, AVRoutePickerViewDelegate {
        weak var store: LibraryStore?
        init(_ store: LibraryStore) { self.store = store }
        func routePickerViewWillBeginPresentingRoutes(_ routePickerView: AVRoutePickerView) {
            Task { @MainActor in self.store?.enableAirPlay() }
        }
    }
}
struct PlaybackVolumeControl: View {
    @EnvironmentObject var store: LibraryStore
    var showsPercentage = false

    var body: some View {
        if store.directOutputActive {
            Button {
                store.preferences.directOutput = false
            } label: {
                Label(store.t("enableVolume"), systemImage: "lock")
                    .font(.caption2)
                    .lineLimit(1)
            }
            .buttonStyle(.glass)
            .help(store.t("enableVolumeHelp"))
            .accessibilityHint(store.t("enableVolumeHelp"))
        } else {
            HStack(spacing: 9) {
                Image(systemName: store.volume == 0 ? "speaker.slash" : "speaker.wave.2")
                    .font(.caption2).accessibilityHidden(true)
                Slider(value: store.outputVolume, in: 0...1)
                    .accessibilityLabel(store.t("volume"))
                if showsPercentage {
                    Text("\(Int(store.volume * 100))").font(.system(size: 8, design: .monospaced))
                        .foregroundStyle(.tertiary).frame(width: 22)
                }
            }.foregroundStyle(.secondary)
        }
    }
}

struct OutputToolbarButton: View {
    @EnvironmentObject var store: LibraryStore
    @State private var showing = false
    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Image(systemName: "hifispeaker").font(.system(size: 12)).frame(width: 24, height: 22).foregroundStyle(
                store.directOutputActive ? store.effectiveAccent : .secondary)
        }.buttonStyle(.plain).help(store.t("audioDevices")).accessibilityLabel(store.t("audioDevices"))
            .popover(isPresented: $showing) {
                ScrollView { OutputSettingsView().padding(22) }.frame(width: 450, height: 520).environmentObject(store)
                    .tint(store.effectiveAccent)
            }
    }
}
struct OutputSettingsView: View {
    @EnvironmentObject var store: LibraryStore
    private var device: AudioOutputDevice? { store.outputs.device(uid: store.preferences.outputDeviceUID) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(store.t("audioDevices"), systemImage: "hifispeaker").font(.headline)
                Spacer()
                Button {
                    store.outputs.refresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                }.buttonStyle(.glass).help(store.t("refreshDevices"))
            }
            Picker(
                store.t("outputDevice"),
                selection: Binding(get: { store.preferences.outputDeviceUID }, set: { store.selectOutput($0) })
            ) {
                Text(store.t("systemOutput")).tag("")
                ForEach(store.outputs.devices) { device in Text(device.name).tag(device.uid) }
                if !store.preferences.outputDeviceUID.isEmpty, device == nil {
                    Text(store.t("outputUnavailable")).tag(store.preferences.outputDeviceUID)
                }
            }
            if let device {
                HStack {
                    Text(device.name).font(.callout.weight(.medium))
                    Spacer()
                    Text(String(format: "%.1f kHz · %d ch", device.sampleRate / 1000, device.channels)).font(
                        .caption.monospacedDigit()
                    ).foregroundStyle(.secondary)
                }
            } else {
                Text(store.t("outputUnavailable")).font(.caption).foregroundStyle(.orange)
            }
            if store.usingAirPlay {
                Label(
                    store.t(store.airPlayReceiverActive ? "airPlayConnected" : "airPlayMode"),
                    systemImage: "airplay.audio"
                ).foregroundStyle(store.effectiveAccent)
                Button(store.t("returnLocal")) { store.useLocalOutput() }.buttonStyle(.glassProminent)
            } else {
                Toggle(store.t("directOutput"), isOn: $store.preferences.directOutput)
                Text(store.t("directNote")).font(.caption).foregroundStyle(.secondary)
                if store.preferences.directOutput {
                    Toggle(store.t("exclusiveOutput"), isOn: $store.preferences.exclusiveOutput)
                    Text(store.t("exclusiveNote")).font(.caption).foregroundStyle(.secondary)
                    Label(store.t("directVolume"), systemImage: "speaker.wave.2").font(.caption).foregroundStyle(
                        .orange)
                }
                if let prepared = store.preparedOutput {
                    Divider()
                    Label(
                        store.t(prepared.direct ? "directPath" : "processedPath"),
                        systemImage: prepared.direct ? "point.3.connected.trianglepath.dotted" : "slider.horizontal.3"
                    ).font(.callout.weight(.medium))
                    Text(
                        String(
                            format: "%.1f kHz → %.1f kHz", (store.current?.sampleRate ?? 0) / 1000, prepared.rate / 1000
                        )
                    ).font(.caption.monospacedDigit())
                    if prepared.exclusive {
                        Label(store.t("exclusiveAcquired"), systemImage: "lock.fill").font(.caption).foregroundStyle(
                            .mint)
                    }
                }
                Text(store.t("bitPerfectNote")).font(.caption2).foregroundStyle(.secondary)
            }
            Divider()
            HStack {
                AirPlayRouteButton().frame(width: 34, height: 28)
                Text("AirPlay").font(.callout)
                Spacer()
            }
            Text(store.t("airPlayNote")).font(.caption2).foregroundStyle(.secondary)
        }.task { store.outputs.refresh() }
    }
}
