import SwiftUI
import AppKit

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    private let pages = ["sound", "playback", "library", "metadata", "appearance", "experience", "shortcuts"]
    private let icons = ["sound": "slider.vertical.3", "playback": "play.circle", "library": "square.stack", "metadata": "sparkles", "appearance": "paintpalette", "experience": "waveform.path", "shortcuts": "command"]
    var body: some View {
        ZStack {
            PrismaBackdrop()
            Group {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 9) { Image(systemName: "waveform.path").font(.system(size: 24)).foregroundStyle(store.accent.color); VStack(alignment: .leading, spacing: 3) { Text("PRISMA").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(3); Text("CONTROL ROOM").font(.system(size: 8, weight: .medium)).tracking(2).foregroundStyle(.secondary) } }.padding(.top, 15).padding(.leading, 8)
                        VStack(spacing: 5) {
                            ForEach(pages, id: \.self) { page in
                                Button { withAnimation(.easeInOut(duration: 0.18)) { store.settingsPage = page } } label: {
                                    HStack(spacing: 10) { Image(systemName: icons[page]!).frame(width: 18); Text(store.t(page)).font(.system(size: 12, weight: store.settingsPage == page ? .semibold : .regular)); Spacer(minLength: 0) }.padding(.horizontal, 11).padding(.vertical, 12).frame(maxWidth: .infinity).background(store.settingsPage == page ? store.accent.color.opacity(0.16) : .clear, in: RoundedRectangle(cornerRadius: 12)).foregroundStyle(store.settingsPage == page ? store.accent.color : .primary.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 7) { HStack(spacing: 5) { Circle().fill(.mint).frame(width: 5, height: 5); Text("PRISMA ENGINE").font(.system(size: 8, weight: .semibold, design: .monospaced)).tracking(1) }; Text("0.2 / macOS").font(.system(size: 10, design: .monospaced)).foregroundStyle(.secondary) }.padding(10)
                    }.padding(14).frame(width: 203).prismaGlass(24)
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) { Text(store.t(store.settingsPage)).font(.system(size: 30, weight: .bold, design: .rounded)); Text(store.t(store.settingsPage + "Sub")).font(.system(size: 12)).foregroundStyle(.secondary) }
                            Spacer()
                            Button { store.showSettings = false; dismiss() } label: { Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(width: 28, height: 28) }.buttonStyle(.glass).help(store.t("done"))
                        }.padding(.top, 9)
                        ScrollView {
                            VStack(alignment: .leading, spacing: 16) {
                                switch store.settingsPage {
                                case "sound": sound
                                case "playback": playback
                                case "library": library
                                case "metadata": metadata
                                case "appearance": appearance
                                case "experience": experience
                                default: shortcuts
                                }
                            }.padding(2).padding(.bottom, 16)
                        }.scrollIndicators(.hidden).clipped()
                        HStack(spacing: 6) { Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint); Text(store.t("settingsSaved")); Spacer(); Text("PRISMA / 02").font(.system(size: 8, design: .monospaced)).tracking(1) }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.padding(20)
            }
        }.frame(width: 920, height: 740).tint(store.accent.color).preferredColorScheme(store.colorScheme)
    }
    private var sound: some View {
        VStack(spacing: 16) {
            card {
                HStack { VStack(alignment: .leading, spacing: 4) { Label(store.t("equalizer"), systemImage: "slider.vertical.3").font(.system(size: 15, weight: .semibold)); Text(store.t("eqDescription")).font(.system(size: 10)).foregroundStyle(.secondary) }; Spacer(); Toggle(store.t("equalizer"), isOn: $store.preferences.eqEnabled).labelsHidden().toggleStyle(.switch).controlSize(.small) }
                HStack {
                    Picker(store.t("preset"), selection: Binding(get: { store.preferences.eqPreset }, set: { store.preferences.selectPreset($0); store.preferences.eqEnabled = true })) { ForEach(["flat", "rock", "jazz", "classical", "electronic", "vocal", "custom"], id: \.self) { Text(store.t($0)).tag($0) } }.frame(width: 210)
                    Spacer(); Button(store.t("resetEQ")) { store.preferences.selectPreset("flat"); store.preferences.preamp = 0 }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(store.accent.color)
                }
                EqualizerGraph(gains: store.preferences.eqGains, color: store.accent.color).frame(height: 65).opacity(store.preferences.eqEnabled ? 1 : 0.35)
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        VStack(spacing: 7) {
                            Text(String(format: "%+.0f", store.preferences.eqGains[i])).font(.system(size: 10, design: .monospaced)).foregroundStyle(store.accent.color)
                            Slider(value: Binding(get: { Double(store.preferences.eqGains[i]) }, set: { store.preferences.eqGains[i] = Float($0); store.preferences.eqPreset = "custom" }), in: -12...12, step: 0.5).frame(width: 115).rotationEffect(.degrees(-90)).frame(width: 26, height: 120).accessibilityLabel("EQ \(Int(ListeningPreferences.frequencies[i])) Hz").disabled(!store.preferences.eqEnabled)
                            Text(ListeningPreferences.frequencies[i] >= 1000 ? String(format: "%gk", ListeningPreferences.frequencies[i] / 1000) : String(Int(ListeningPreferences.frequencies[i]))).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
                Divider().opacity(0.5)
                HStack { Text(store.t("preamp")).font(.system(size: 12)); Slider(value: $store.preferences.preamp, in: -12...6, step: 0.5).frame(maxWidth: 230); Text(String(format: "%+.1f dB", store.preferences.preamp)).font(.system(size: 10, design: .monospaced)).frame(width: 65) }.disabled(!store.preferences.eqEnabled)
                toggle("headroom", $store.preferences.autoHeadroom)
                Text(store.t("headroomNote")).font(.system(size: 10)).foregroundStyle(.secondary)
                HStack { Text(store.t("effectiveGain")); Spacer(); Text(String(format: "%+.1f dB", store.preferences.effectivePreamp)).monospacedDigit() }.font(.system(size: 10)).foregroundStyle(.secondary)
            }
            card {
                HStack { Text(store.t("balance")).font(.system(size: 14, weight: .semibold)); Spacer(); Button(store.t("center")) { store.preferences.balance = 0 }.buttonStyle(.plain).foregroundStyle(store.accent.color).font(.caption) }
                HStack { Text("L"); Slider(value: $store.preferences.balance, in: -1...1); Text("R") }.font(.system(size: 10, design: .monospaced))
                HStack { Text(store.t("signal")).font(.system(size: 9, weight: .medium)).tracking(1); Spacer(); Text(String(format: "%.1f dBFS", 20 * log10(max(0.00001, store.peak)))).font(.system(size: 10, design: .monospaced)).foregroundStyle(store.peak >= 1 ? .red : .secondary) }
                GeometryReader { geo in Capsule().fill(.primary.opacity(0.06)).overlay(alignment: .leading) { Capsule().fill(LinearGradient(colors: [.mint, store.accent.color], startPoint: .leading, endPoint: .trailing)).frame(width: geo.size.width * min(1, store.peak * 2)) } }.frame(height: 5)
            }
            card { SectionHeading(title: store.t("output"), subtitle: store.t("systemOutput")); Text(store.t("outputNote")).font(.caption).foregroundStyle(.secondary); Button { NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.Sound-Settings.extension")!) } label: { Label(store.t("openSound"), systemImage: "arrow.up.forward.app") }.buttonStyle(.glass) }
        }
    }
    private var playback: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("speed"), subtitle: store.t("speedNote"))
                HStack { Slider(value: $store.preferences.playbackRate, in: 0.5...1.5, step: 0.05); Text(String(format: "%.2f×", store.preferences.playbackRate)).font(.system(size: 16, weight: .medium, design: .rounded)).frame(width: 60); Button("1×") { store.preferences.playbackRate = 1 }.buttonStyle(.glass) }
                Divider(); toggle("continueQueue", $store.preferences.continueQueue); toggle("rememberPosition", $store.preferences.rememberPosition); Text(store.t("rememberNote")).font(.caption).foregroundStyle(.secondary); toggle("keepAwake", $store.preferences.keepAwake)
            }
            card {
                HStack { SectionHeading(title: store.t("sleepTimer"), subtitle: store.t("sleepNote")); Spacer(); Image(systemName: "moon.zzz").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(store.accent.color) }
                HStack(spacing: 10) { ForEach([15, 30, 60, 90], id: \.self) { minutes in Button("\(minutes) min") { store.setSleepTimer(minutes: minutes) }.buttonStyle(.glass).frame(maxWidth: .infinity) } }
                if store.sleepDeadline != nil { HStack { Label("\(clockText(Double(store.sleepRemaining))) \(store.t("remaining"))", systemImage: "timer"); Spacer(); Button(store.t("cancelTimer")) { store.setSleepTimer(minutes: nil) }.buttonStyle(.plain).foregroundStyle(store.accent.color) }.font(.caption) }
                Divider(); toggle("stopAfter", $store.stopAfterCurrent)
            }
            card { SectionHeading(title: store.t("mini")); toggle("alwaysOnTop", $store.preferences.miniAlwaysOnTop); toggle("allSpaces", $store.preferences.miniAllSpaces); Text(store.t("pipNote")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private var library: some View {
        VStack(spacing: 16) {
            card {
                HStack { SectionHeading(title: store.t("sources")); Spacer(); Button { store.pickMusic() } label: { Image(systemName: "plus") }.buttonStyle(.glass).disabled(store.scanning) }
                ForEach(store.sources) { source in
                    HStack(spacing: 10) { Image(systemName: source.url.path.hasPrefix("/Volumes") ? "externaldrive.connected.to.line.below" : "folder").foregroundStyle(store.accent.color); VStack(alignment: .leading, spacing: 4) { Text(source.name).font(.system(size: 12, weight: .medium)); Text(source.url.path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1).truncationMode(.middle) }; Spacer(); Button { NSWorkspace.shared.activateFileViewerSelecting([source.url]) } label: { Image(systemName: "arrow.up.forward") }.buttonStyle(.plain).help(store.t("reveal")); Button { store.removeSource(source) } label: { Image(systemName: "minus.circle") }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(store.scanning).help(store.t("removeSource")) }.padding(.vertical, 4)
                }
                Divider(); toggle("startScan", $store.scanOnLaunch); toggle("recursive", $store.preferences.recursiveScan)
                Button { Task { await store.scan(force: true) } } label: { Label(store.scanning ? store.t("reading") : store.t("rescan"), systemImage: "arrow.clockwise") }.buttonStyle(.glass).disabled(store.scanning)
                Text(store.t("rescanNote")).font(.caption).foregroundStyle(.secondary)
            }
            card {
                SectionHeading(title: store.t("backup"), subtitle: store.t("backupNote"))
                HStack { Button(store.t("backup")) { store.exportLibraryBackup() }.buttonStyle(.glass); Button(store.t("exportPlaylist")) { store.exportPlaylist() }.buttonStyle(.glass) }
                Button(store.t("dataFolder")) { store.showDataFolder() }.buttonStyle(.plain).foregroundStyle(store.accent.color).font(.caption)
            }
        }
    }
    private var metadata: some View {
        VStack(spacing: 16) {
            card { SectionHeading(title: store.t("online")); toggle("online", $store.online); toggle("autoArtwork", $store.preferences.autoArtwork); toggle("autoLyrics", $store.preferences.autoLyrics); Divider(); Text(store.t("privacy")).font(.caption).foregroundStyle(.secondary); HStack { Link("iTunes ↗", destination: URL(string: "https://performance-partners.apple.com/search-api")!); Link("LRCLIB ↗", destination: URL(string: "https://lrclib.net/docs")!) }.font(.caption) }
            card { Label(store.t("localFirst"), systemImage: "checkmark.shield").font(.system(size: 14, weight: .semibold)); Text(store.t("localFirstNote")).font(.caption).foregroundStyle(.secondary) }
            card { SectionHeading(title: store.t("cache")); HStack(spacing: 30) { metric("\(store.tracks.filter { $0.artwork != nil }.count)", store.t("withArtwork")); metric("\(store.tracks.filter { $0.lyrics != nil }.count)", store.t("withLyrics")); metric("\(store.playlists.count)", store.t("playlists")) }; Button(store.t("dataFolder")) { store.showDataFolder() }.buttonStyle(.glass) }
        }
    }
    private var appearance: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("accentColor"))
                HStack(spacing: 14) { ForEach(Accent.allCases) { accent in Button { store.accent = accent } label: { VStack(spacing: 8) { Circle().fill(accent.color.gradient).frame(width: 34, height: 34).overlay { if store.accent == accent { Image(systemName: "checkmark").font(.system(size: 12, weight: .bold)).foregroundStyle(.white) } }.overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }; Text(store.t(accent.rawValue)).font(.system(size: 8)).foregroundStyle(.secondary) } }.buttonStyle(.plain).help(store.t(accent.rawValue)) } }.frame(maxWidth: .infinity)
                Divider()
                Picker(store.t("theme"), selection: $store.theme) { ForEach(["system", "dark", "light"], id: \.self) { Text(store.t($0)).tag($0) } }.pickerStyle(.segmented)
                Picker(store.t("glassMaterial"), selection: $store.preferences.glassStyle) { Text(store.t("regularGlass")).tag("regular"); Text(store.t("clearGlass")).tag("clear") }
                HStack { Text(store.t("atmosphere")).font(.caption); Slider(value: $store.preferences.atmosphere, in: 0...1) }
            }
            card {
                Picker(store.t("density"), selection: $store.preferences.compactRows) { Text(store.t("comfortable")).tag(false); Text(store.t("compact")).tag(true) }
                toggle("qualityBadges", $store.preferences.showQuality)
                Picker(store.t("albumSize"), selection: $store.preferences.albumSize) { ForEach(["small", "medium", "large"], id: \.self) { Text(store.t($0)).tag($0) } }
                Picker(store.t("language"), selection: $store.language) { ForEach(AppLanguage.allCases) { Text($0.name).tag($0) } }
                Picker(store.t("startPage"), selection: $store.preferences.startSection) { ForEach(["home", "songs", "albums", "favorites", "recent"], id: \.self) { Text(store.t($0)).tag($0) } }
            }
        }
    }
    private var experience: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("lyrics"))
                HStack { Text(store.t("lyricsSize")).font(.caption); Slider(value: $store.preferences.lyricsFontSize, in: 14...32, step: 1); Text("\(Int(store.preferences.lyricsFontSize)) pt").font(.system(size: 11, design: .monospaced)).frame(width: 45) }
                Text("♪  Prisma Music").font(.system(size: store.preferences.lyricsFontSize, weight: .semibold, design: .rounded)).foregroundStyle(store.accent.color).frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
                toggle("autoScroll", $store.preferences.autoScrollLyrics)
                HStack { Text(store.t("lyricOffset")).font(.caption); Slider(value: $store.preferences.lyricsOffset, in: -10...10, step: 0.1); Text(String(format: "%+.1f s", store.preferences.lyricsOffset)).font(.system(size: 11, design: .monospaced)).frame(width: 55) }
                Text(store.t("offsetNote")).font(.caption).foregroundStyle(.secondary)
            }
            card {
                SectionHeading(title: store.t("visualizer"))
                Picker(store.t("visualStyle"), selection: $store.preferences.visualizerStyle) { ForEach(["aurora", "orbit", "ribbons"], id: \.self) { Text(store.t($0)).tag($0) } }.pickerStyle(.segmented)
                VisualizerCanvas(level: max(0.1, store.level), playing: store.preferences.animateVisualizer, color: store.accent.color).frame(height: 145).background(.black, in: RoundedRectangle(cornerRadius: 14)).clipped()
                HStack { Text(store.t("sensitivity")).font(.caption); Slider(value: $store.preferences.visualizerSensitivity, in: 0.5...3) }
                Picker(store.t("frameRate"), selection: $store.preferences.visualizerFPS) { ForEach([24.0, 30, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) } }
                toggle("animations", $store.preferences.animateVisualizer)
            }
        }
    }
    private var shortcuts: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("keyboard"))
                ForEach([("add", "⌘ O"), ("fileInfo", "⌘ I"), ("scan", "⌘ R"), ("play", "Space"), ("next", "⌘ →"), ("previous", "⌘ ←"), ("mini", "⇧ ⌘ M"), ("full", "⌃ ⌘ F"), ("settings", "⌘ ,")], id: \.0) { item in HStack { Text(store.t(item.0)).font(.system(size: 12)); Spacer(); Text(item.1).font(.system(size: 11, design: .monospaced)).padding(.horizontal, 9).padding(.vertical, 5).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6)) } }
            }
            card { Text("PRISMA MUSIC").font(.system(size: 20, weight: .light, design: .rounded)).tracking(4); Text(store.t("versionNew")).font(.caption).foregroundStyle(.secondary); Text(store.t("engine")).font(.caption).foregroundStyle(.secondary); Text(store.t("tagNote")).font(.caption).foregroundStyle(.secondary) }
        }
    }
    private func toggle(_ key: String, _ binding: Binding<Bool>) -> some View { Toggle(store.t(key), isOn: binding).toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).padding(.vertical, 3) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View { VStack(alignment: .leading, spacing: 15, content: content).padding(20).frame(maxWidth: .infinity, alignment: .leading).prismaGlass(20) }
    private func metric(_ value: String, _ title: String) -> some View { VStack(alignment: .leading, spacing: 5) { Text(value).font(.system(size: 26, weight: .light, design: .rounded)); Text(title).font(.system(size: 9)).foregroundStyle(.secondary) } }
}
struct EqualizerGraph: View {
    var gains: [Float]
    var color: Color
    var body: some View {
        Canvas { context, size in
            for i in 0...4 { var line = Path(); let y = CGFloat(i) * size.height / 4; line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(line, with: .color(.primary.opacity(0.07)), style: StrokeStyle(lineWidth: 1, dash: [3,5])) }
            let points = gains.enumerated().map { CGPoint(x: Double($0.offset) / 9 * size.width, y: size.height / 2 - Double($0.element) / 12 * size.height * 0.45) }
            var path = Path(); path.addLines(points)
            var fill = path; fill.addLine(to: CGPoint(x: size.width, y: size.height)); fill.addLine(to: CGPoint(x: 0, y: size.height)); fill.closeSubpath()
            context.fill(fill, with: .linearGradient(Gradient(colors: [color.opacity(0.23), color.opacity(0)]), startPoint: .zero, endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            for point in points { context.fill(Path(ellipseIn: CGRect(x: point.x-2.5, y: point.y-2.5, width: 5, height: 5)), with: .color(color)) }
        }
    }
}
struct NASView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State private var address = "smb://"
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(store.t("connect"), systemImage: "externaldrive.connected.to.line.below").font(.title2.bold())
            Text(store.t("nasHelp")).foregroundStyle(.secondary)
            TextField("smb://NAS/Music", text: $address).textFieldStyle(.roundedBorder)
            HStack { Button(store.t("cancel")) { dismiss() }; Spacer(); Button(store.t("connectButton")) { if let url = URL(string: address), ["smb", "afp", "nfs"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false { NSWorkspace.shared.open(url); dismiss() } }.buttonStyle(.glassProminent).disabled(!valid) }
        }.padding(28).frame(width: 460)
    }
    private var valid: Bool { guard let url = URL(string: address) else { return false }; return ["smb", "afp", "nfs"].contains(url.scheme?.lowercased() ?? "") && url.host?.isEmpty == false && url.user == nil && url.password == nil }
}
struct TagEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @State var track: Track
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("edit")).font(.title2.bold())
            Form { TextField(store.t("title"), text: $track.title); TextField(store.t("artist"), text: $track.artist); TextField(store.t("album"), text: $track.album); TextField(store.t("genre"), text: $track.genre); TextField(store.t("year"), text: $track.year) }.textFieldStyle(.roundedBorder)
            Text(store.t("tagNote")).font(.caption).foregroundStyle(.secondary)
            HStack { Button(store.t("cancel")) { dismiss() }; Spacer(); Button(store.t("save")) { store.update(track); dismiss() }.buttonStyle(.glassProminent).disabled(track.title.trimmingCharacters(in: .whitespaces).isEmpty) }
        }.padding(28).frame(width: 450)
    }
}
