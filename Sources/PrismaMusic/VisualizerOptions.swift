import SwiftUI

struct VisualizerOptionsButton: View {
    @EnvironmentObject private var store: LibraryStore
    @State private var showing = false

    var body: some View {
        Button {
            showing.toggle()
        } label: {
            Label("\(store.t(store.preferences.visualizerStyle)) · \(Int(store.preferences.visualizerFPS)) FPS",
                  systemImage: "slider.horizontal.3")
        }.buttonStyle(.glass)
            .help(store.t("visualizerOptions"))
            .accessibilityLabel(store.t("visualizerOptions"))
            .accessibilityValue("\(store.t(store.preferences.visualizerStyle)), \(Int(store.preferences.visualizerFPS)) FPS")
            .popover(isPresented: $showing, arrowEdge: .top) {
                VStack(alignment: .leading, spacing: 16) {
                    HStack {
                        Text(store.t("visualizerOptions")).font(.headline)
                        Spacer()
                        Button {
                            showing = false
                        } label: {
                            Image(systemName: "xmark")
                        }.buttonStyle(.glass)
                            .accessibilityLabel(store.t("closeUpdate"))
                            .keyboardShortcut(.cancelAction)
                    }
                    VisualizerOptions()
                }.padding(20).frame(width: 428).tint(store.effectiveAccent)
            }
    }
}

struct VisualizerOptions: View {
    @EnvironmentObject private var store: LibraryStore
    var showsPreview = false
    private let symbols = [
        "aurora": "waveform.path", "bars": "chart.bar", "mirror": "chart.bar.xaxis", "centered": "waveform",
        "nebula": "sparkles", "orbit": "sun.max", "ribbons": "waveform.path.ecg",
    ]

    var body: some View {
        VStack(alignment: .leading, spacing: 13) {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 115), spacing: 8)], spacing: 8) {
                ForEach(ListeningPreferences.visualizerStyles, id: \.self) { style in
                    let selected = store.preferences.visualizerStyle == style
                    Button {
                        store.preferences.visualizerStyle = style
                    } label: {
                        Label(store.t(style), systemImage: symbols[style] ?? "waveform")
                            .font(.callout).lineLimit(1).padding(.vertical, 7)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }.buttonStyle(.glass)
                        .tint(selected ? store.effectiveAccent : .secondary)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }.accessibilityLabel(store.t("visualStyle"))
            if showsPreview {
                VisualizerCanvas(level: max(0.1, store.level), playing: store.preferences.animateVisualizer,
                                 color: store.effectiveAccent)
                    .frame(height: 145)
                    .background(.black)
                    .clipShape(.rect(cornerRadius: 14))
            }
            HStack {
                Text(store.t("sensitivity")).font(.caption)
                Slider(value: $store.preferences.visualizerSensitivity, in: 0.5...3)
                    .accessibilityLabel(store.t("sensitivity"))
                Text(store.preferences.visualizerSensitivity.formatted(.number.precision(.fractionLength(1))) + "×")
                    .monospacedDigit().font(.caption).foregroundStyle(.secondary)
            }
            Text(store.t("frameRate")).font(.caption)
            Picker(store.t("frameRate"), selection: $store.preferences.visualizerFPS) {
                ForEach(ListeningPreferences.visualizerFrameRates, id: \.self) { rate in
                    Text("\(Int(rate)) FPS").tag(rate)
                }
            }.pickerStyle(.segmented).labelsHidden()
            Toggle(store.t("animations"), isOn: $store.preferences.animateVisualizer).toggleStyle(.switch)
        }
    }
}
