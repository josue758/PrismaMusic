import AppKit
import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var showTagReview = false
    @State private var showScanReport = false
    private let pages = ["sound", "playback", "library", "metadata", "appearance", "experience", "shortcuts"]
    private let icons = [
        "sound": "slider.vertical.3", "playback": "play.circle", "library": "square.stack", "metadata": "sparkles",
        "appearance": "paintpalette", "experience": "waveform.path", "shortcuts": "command",
    ]
    var body: some View {
        ZStack {
            PrismaBackdrop(reactive: false)
                .sheet(isPresented: $showTagReview) { TagReviewView().environmentObject(store) }
                .sheet(isPresented: $showScanReport) { ScanReportView().environmentObject(store) }
            Group {
                HStack(spacing: 24) {
                    VStack(alignment: .leading, spacing: 24) {
                        HStack(spacing: 9) {
                            Image(systemName: "waveform.path").font(.system(size: 24)).foregroundStyle(
                                store.effectiveAccent)
                            VStack(alignment: .leading, spacing: 3) {
                                Text("PRISMA").font(.system(size: 15, weight: .bold, design: .rounded)).tracking(3)
                                Text("CONTROL ROOM").font(.system(size: 8, weight: .medium)).tracking(2)
                                    .foregroundStyle(.secondary)
                            }
                        }.padding(.top, 15).padding(.leading, 8)
                        VStack(spacing: 5) {
                            ForEach(pages, id: \.self) { page in
                                Button {
                                    store.settingsPage = page
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: icons[page]!).frame(width: 18)
                                        Text(store.t(page)).font(
                                            .system(size: 12, weight: store.settingsPage == page ? .semibold : .regular)
                                        )
                                        Spacer(minLength: 0)
                                    }.padding(.horizontal, 11).padding(.vertical, 12).frame(maxWidth: .infinity)
                                        .background(
                                            store.settingsPage == page ? store.effectiveAccent.opacity(0.16) : .clear,
                                            in: RoundedRectangle(cornerRadius: 12)
                                        ).foregroundStyle(
                                            store.settingsPage == page ? store.effectiveAccent : .primary.opacity(0.7))
                                }.buttonStyle(.plain)
                            }
                        }.animation(
                            reduceMotion || !store.preferences.microInteractions ? nil : .easeOut(duration: 0.12),
                            value: store.settingsPage)
                        Spacer()
                        Button(store.t("welcome")) {
                            store.openWelcome()
                            dismiss()
                        }.buttonStyle(.glass)
                        VStack(alignment: .leading, spacing: 7) {
                            HStack(spacing: 5) {
                                Circle().fill(.mint).frame(width: 5, height: 5)
                                Text("PRISMA ENGINE").font(.system(size: 8, weight: .semibold, design: .monospaced))
                                    .tracking(1)
                            }
                            Text(AppVersion.current + " / macOS").font(.system(size: 10, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }.padding(10)
                    }.padding(14).frame(width: 203).prismaGlass(24)
                    VStack(alignment: .leading, spacing: 20) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 7) {
                                Text(store.t(store.settingsPage)).font(
                                    .system(size: 30, weight: .bold, design: .rounded))
                                Text(store.t(store.settingsPage + "Sub")).font(.system(size: 12)).foregroundStyle(
                                    .secondary)
                            }
                            Spacer()
                            Button {
                                store.showSettings = false
                                dismiss()
                            } label: {
                                Image(systemName: "xmark").font(.system(size: 11, weight: .medium)).frame(
                                    width: 28, height: 28)
                            }.buttonStyle(.glass).help(store.t("done"))
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
                        }.id(store.settingsPage).scrollIndicators(.hidden).clipped()
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark.circle.fill").foregroundStyle(.mint)
                            Text(store.t("settingsSaved"))
                            Spacer()
                            Text("PRISMA / " + AppVersion.current).font(.system(size: 8, design: .monospaced)).tracking(
                                1)
                        }.font(.system(size: 10)).foregroundStyle(.secondary)
                    }.frame(maxWidth: .infinity)
                }.padding(20)
            }
        }.frame(width: 920, height: 740).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
            .alert(
                "Prisma Music",
                isPresented: Binding(
                    get: { store.error != nil },
                    set: {
                        if !$0 { store.error = nil }
                    })
            ) {
                Button("OK") { store.error = nil }
            } message: {
                Text(store.error ?? "")
            }
    }
    private var sound: some View {
        VStack(spacing: 16) {
            card {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Label(store.t("equalizer"), systemImage: "slider.vertical.3").font(
                            .system(size: 15, weight: .semibold))
                        Text(store.t("eqDescription")).font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Toggle(store.t("equalizer"), isOn: $store.preferences.eqEnabled).labelsHidden().toggleStyle(.switch)
                        .controlSize(.small).disabled(store.directOutputActive || store.usingAirPlay)
                }
                HStack {
                    Picker(
                        store.t("preset"),
                        selection: Binding(
                            get: { store.preferences.eqPreset },
                            set: {
                                store.preferences.selectPreset($0)
                                store.preferences.eqEnabled = true
                            })
                    ) {
                        ForEach(["flat", "rock", "jazz", "classical", "electronic", "vocal", "custom"], id: \.self) {
                            Text(store.t($0)).tag($0)
                        }
                    }.frame(width: 210)
                    Spacer()
                    Button(store.t("resetEQ")) {
                        store.preferences.selectPreset("flat")
                        store.preferences.preamp = 0
                    }.buttonStyle(.plain).font(.system(size: 10)).foregroundStyle(store.effectiveAccent)
                }
                EqualizerGraph(gains: store.preferences.eqGains, color: store.effectiveAccent).frame(height: 65)
                    .opacity(store.preferences.eqEnabled ? 1 : 0.35)
                HStack(spacing: 0) {
                    ForEach(0..<10, id: \.self) { i in
                        VStack(spacing: 7) {
                            Text(String(format: "%+.0f", store.preferences.eqGains[i])).font(
                                .system(size: 10, design: .monospaced)
                            ).foregroundStyle(store.effectiveAccent)
                            Slider(
                                value: Binding(
                                    get: { Double(store.preferences.eqGains[i]) },
                                    set: {
                                        store.preferences.eqGains[i] = Float($0)
                                        store.preferences.eqPreset = "custom"
                                    }), in: -12...12, step: 0.5
                            ).frame(width: 115).rotationEffect(.degrees(-90)).frame(width: 26, height: 120)
                                .accessibilityLabel("EQ \(Int(ListeningPreferences.frequencies[i])) Hz").disabled(
                                    !store.preferences.eqEnabled)
                            Text(
                                ListeningPreferences.frequencies[i] >= 1000
                                    ? String(format: "%gk", ListeningPreferences.frequencies[i] / 1000)
                                    : String(Int(ListeningPreferences.frequencies[i]))
                            ).font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                        }.frame(maxWidth: .infinity)
                    }
                }
                Divider().opacity(0.5)
                HStack {
                    Text(store.t("preamp")).font(.system(size: 12))
                    Slider(value: $store.preferences.preamp, in: -12...6, step: 0.5).frame(maxWidth: 230)
                    Text(String(format: "%+.1f dB", store.preferences.preamp)).font(
                        .system(size: 10, design: .monospaced)
                    ).frame(width: 65)
                }.disabled(!store.preferences.eqEnabled || store.directOutputActive || store.usingAirPlay)
                toggle("headroom", $store.preferences.autoHeadroom)
                Text(store.t("headroomNote")).font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Text(store.t("effectiveGain"))
                    Spacer()
                    Text(String(format: "%+.1f dB", store.preferences.effectivePreamp)).monospacedDigit()
                }.font(.system(size: 10)).foregroundStyle(.secondary)
            }.disabled(store.directOutputActive || store.usingAirPlay)
            card {
                HStack {
                    Text(store.t("balance")).font(.system(size: 14, weight: .semibold))
                    Spacer()
                    Button(store.t("center")) { store.preferences.balance = 0 }.buttonStyle(.plain).foregroundStyle(
                        store.effectiveAccent
                    ).font(.caption)
                }
                HStack {
                    Text("L")
                    Slider(value: $store.preferences.balance, in: -1...1).disabled(
                        store.directOutputActive || store.usingAirPlay)
                    Text("R")
                }.font(.system(size: 10, design: .monospaced))
                HStack {
                    Text(store.t("signal")).font(.system(size: 9, weight: .medium)).tracking(1)
                    Spacer()
                    Text(String(format: "%.1f dBFS", 20 * log10(max(0.00001, store.peak)))).font(
                        .system(size: 10, design: .monospaced)
                    ).foregroundStyle(store.peak >= 1 ? .red : .secondary)
                }
                GeometryReader { geo in
                    Capsule().fill(.primary.opacity(0.06)).overlay(alignment: .leading) {
                        Capsule().fill(
                            LinearGradient(
                                colors: [.mint, store.effectiveAccent], startPoint: .leading, endPoint: .trailing)
                        ).frame(width: geo.size.width * min(1, store.peak * 2))
                    }
                }.frame(height: 5)
            }.disabled(store.directOutputActive || store.usingAirPlay)
            card { OutputSettingsView() }
        }
    }
    private var playback: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("speed"), subtitle: store.t("speedNote"))
                HStack {
                    Slider(value: $store.preferences.playbackRate, in: 0.5...1.5, step: 0.05).disabled(
                        store.directOutputActive)
                    Text(String(format: "%.2f×", store.preferences.playbackRate)).font(
                        .system(size: 16, weight: .medium, design: .rounded)
                    ).frame(width: 60)
                    Button("1×") { store.preferences.playbackRate = 1 }.buttonStyle(.glass)
                }
                Divider()
                toggle("continueQueue", $store.preferences.continueQueue)
                toggle("rememberPosition", $store.preferences.rememberPosition)
                Text(store.t("rememberNote")).font(.caption).foregroundStyle(.secondary)
                toggle("keepAwake", $store.preferences.keepAwake)
            }
            card {
                HStack {
                    SectionHeading(title: store.t("sleepTimer"), subtitle: store.t("sleepNote"))
                    Spacer()
                    Image(systemName: "moon.zzz").font(.system(size: 28, weight: .ultraLight)).foregroundStyle(
                        store.effectiveAccent)
                }
                HStack(spacing: 10) {
                    ForEach([15, 30, 60, 90], id: \.self) { minutes in
                        Button("\(minutes) min") { store.setSleepTimer(minutes: minutes) }.buttonStyle(.glass).frame(
                            maxWidth: .infinity)
                    }
                }
                if store.sleepDeadline != nil {
                    HStack {
                        Label(
                            "\(clockText(Double(store.sleepRemaining))) \(store.t("remaining"))", systemImage: "timer")
                        Spacer()
                        Button(store.t("cancelTimer")) { store.setSleepTimer(minutes: nil) }.buttonStyle(.plain)
                            .foregroundStyle(store.effectiveAccent)
                    }.font(.caption)
                }
                Divider()
                toggle("stopAfter", $store.stopAfterCurrent)
            }
            card {
                SectionHeading(title: store.t("mini"))
                toggle("alwaysOnTop", $store.preferences.miniAlwaysOnTop)
                toggle("allSpaces", $store.preferences.miniAllSpaces)
                Text(store.t("pipNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private var library: some View {
        VStack(spacing: 16) {
            card {
                HStack {
                    SectionHeading(title: store.t("sources"))
                    Spacer()
                    Button {
                        store.pickMusic()
                    } label: {
                        Image(systemName: "plus")
                    }.buttonStyle(.glass).disabled(store.scanning)
                }
                ForEach(store.sources) { source in
                    HStack(spacing: 10) {
                        Image(
                            systemName: source.url.path.hasPrefix("/Volumes")
                                ? "externaldrive.connected.to.line.below" : "folder"
                        ).foregroundStyle(store.effectiveAccent)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(source.name).font(.system(size: 12, weight: .medium))
                            Text(store.t(store.sourceStates[source.id] ?? "ready")).font(.system(size: 9))
                                .foregroundStyle(.secondary)
                            Text(source.url.path).font(.system(size: 9)).foregroundStyle(.secondary).lineLimit(1)
                                .truncationMode(.middle)
                        }
                        Spacer()
                        Button {
                            NSWorkspace.shared.activateFileViewerSelecting([source.url])
                        } label: {
                            Image(systemName: "arrow.up.forward")
                        }.buttonStyle(.plain).help(store.t("reveal"))
                        Button {
                            store.pickReplacement(for: source)
                        } label: {
                            Image(systemName: "folder.badge.gearshape")
                        }.buttonStyle(.plain).disabled(store.scanning || store.relocatingSource).help(
                            store.t("relocateSource")
                        )
                        .accessibilityLabel(store.t("relocateSource"))
                        Button {
                            store.removeSource(source)
                        } label: {
                            Image(systemName: "minus.circle")
                        }.buttonStyle(.plain).foregroundStyle(.secondary).disabled(
                            store.scanning || store.relocatingSource
                        ).help(
                            store.t("removeSource"))
                    }.padding(.vertical, 4)
                }
                Divider()
                if store.relocatingSource {
                    ProgressView(value: Double(store.relocationProcessed), total: Double(max(1, store.relocationTotal)))
                    HStack {
                        Text(
                            store.t("verifyingLocation") + " · \(store.relocationProcessed) / \(store.relocationTotal)"
                        )
                        .font(.caption.monospacedDigit())
                        Spacer()
                        Button(store.t("cancel")) { store.cancelSourceRelocation() }
                    }
                }
                toggle("startScan", $store.scanOnLaunch)
                toggle("watchMusicFolders", $store.preferences.watchMusicFolders)
                Text(store.t("watchMusicFoldersNote")).font(.caption).foregroundStyle(.secondary)
                toggle("recursive", $store.preferences.recursiveScan)
                Text(store.t("scanWorkers")).font(.caption)
                Picker(store.t("scanWorkers"), selection: $store.preferences.scanWorkers) {
                    Text("2").tag(2)
                    Text("4").tag(4)
                    Text("8").tag(8)
                }.pickerStyle(.segmented)
                Text(store.t("scanWorkersNote")).font(.caption).foregroundStyle(.secondary)
                Button {
                    Task { await store.scan(force: true) }
                } label: {
                    Label(store.scanning ? store.t("reading") : store.t("rescan"), systemImage: "arrow.clockwise")
                }.buttonStyle(.glass).disabled(store.scanning)
                if store.scanning {
                    Button {
                        store.cancelScan()
                    } label: {
                        Label(store.t("cancel"), systemImage: "stop.circle")
                    }.buttonStyle(.glass)
                }
                if store.scanning && store.scanDiscovered > 0 {
                    ProgressView(value: Double(store.scanProcessed), total: Double(store.scanDiscovered))
                    Text("\(store.scanProcessed) / \(store.scanDiscovered)").font(.caption.monospacedDigit())
                }
                if !store.scanning, let audit = store.scanAudit {
                    HStack(spacing: 24) {
                        metric(String(audit.discovered), store.t("scanSummary"))
                        metric(String(audit.imported + audit.unchanged), store.t("processedFiles"))
                        metric(String(audit.failed), store.t("failedFiles"))
                    }
                    Text(
                        audit.cancelled
                            ? store.t("scanCancelled")
                            : audit.unavailableSources > 0
                                ? store.t("offline") : audit.failed > 0 ? store.t("scanErrors") : store.t("finished")
                    ).font(.caption).foregroundStyle(.secondary)
                    HStack {
                        Button(store.t("scanReport")) { showScanReport = true }.buttonStyle(.glass)
                        if audit.issues.contains(where: {
                            MetadataReader.extensions.contains($0.url.pathExtension.lowercased())
                        }) {
                            Button(store.t("retryFailed")) { Task { await store.retryFailedScan() } }.buttonStyle(
                                .glass)
                        }
                    }
                }
                Text(store.t("rescanNote")).font(.caption).foregroundStyle(.secondary)
            }
            card {
                SectionHeading(title: store.t("tagReview"), subtitle: store.t("tagReviewNote"))
                HStack {
                    Button(store.t("tagReview")) { showTagReview = true }.buttonStyle(.glass)
                    Button(store.t("undoTags")) { store.undoTagEdits() }.buttonStyle(.glass)
                        .disabled(!store.canUndoTagEdits || store.scanning)
                }
            }
            card {
                SectionHeading(title: store.t("backup"), subtitle: store.t("backupNote"))
                Text(store.t("dailyBackupsNote")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Button(store.t("backup")) { store.exportLibraryBackup() }.buttonStyle(.glass)
                    Button(store.t("exportPlaylist")) { store.exportPlaylist() }.buttonStyle(.glass)
                }
                Button(store.t("dataFolder")) { store.showDataFolder() }.buttonStyle(.plain).foregroundStyle(
                    store.effectiveAccent
                ).font(.caption)
            }
        }
    }
    private var metadata: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("online"))
                toggle("online", $store.online)
                toggle("autoArtwork", $store.preferences.autoArtwork)
                toggle("autoLyrics", $store.preferences.autoLyrics)
                Divider()
                Text(store.t("privacy")).font(.caption).foregroundStyle(.secondary)
                HStack {
                    Link("iTunes ↗", destination: URL(string: "https://performance-partners.apple.com/search-api")!)
                    Link("LRCLIB ↗", destination: URL(string: "https://lrclib.net/docs")!)
                }.font(.caption)
            }
            card {
                Label(store.t("localFirst"), systemImage: "checkmark.shield").font(.system(size: 14, weight: .semibold))
                Text(store.t("localFirstNote")).font(.caption).foregroundStyle(.secondary)
            }
            card {
                SectionHeading(title: store.t("cache"))
                HStack(spacing: 30) {
                    metric("\(store.statistics.withArtwork)", store.t("withArtwork"))
                    metric("\(store.statistics.withLyrics)", store.t("withLyrics"))
                    metric("\(store.playlists.count)", store.t("playlists"))
                }
                Button(store.t("dataFolder")) { store.showDataFolder() }.buttonStyle(.glass)
            }
        }
    }
    private var appearance: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("interfaceFeel"), subtitle: store.t("interfaceFeelNote"))
                toggle("microInteractions", $store.preferences.microInteractions)
                toggle("hoverDepth", $store.preferences.hoverDepth)
                toggle("showFeedback", $store.preferences.showFeedback)
            }
            card {
                SectionHeading(title: store.t("artworkAtmosphere"), subtitle: store.t("artworkAtmosphereNote"))
                toggle("adaptiveArtwork", $store.preferences.adaptiveArtwork)
                toggle("ambientMotion", $store.preferences.ambientMotion)
                toggle("artworkPulse", $store.preferences.artworkPulse)
                HStack(spacing: 8) {
                    ForEach(Array(store.artworkPalette.colors.enumerated()), id: \.offset) { _, color in
                        RoundedRectangle(cornerRadius: 8).fill(color.gradient).frame(height: 27)
                    }
                    Text(store.t(store.artworkPalette.extracted ? "paletteFromArtwork" : "paletteGenerated")).font(
                        .system(size: 9)
                    ).foregroundStyle(.secondary).frame(width: 125)
                }
                Divider()
                SectionHeading(title: store.t("accentColor"))
                HStack(spacing: 14) {
                    ForEach(Accent.allCases) { accent in
                        Button {
                            store.accent = accent
                            store.preferences.adaptiveArtwork = false
                        } label: {
                            VStack(spacing: 8) {
                                Circle().fill(accent.color.gradient).frame(width: 34, height: 34).overlay {
                                    if store.accent == accent {
                                        Image(systemName: "checkmark").font(.system(size: 12, weight: .bold))
                                            .foregroundStyle(.white)
                                    }
                                }.overlay { Circle().strokeBorder(.white.opacity(0.35), lineWidth: 1) }
                                Text(store.t(accent.rawValue)).font(.system(size: 8)).foregroundStyle(.secondary)
                            }
                        }.buttonStyle(.plain).help(store.t(accent.rawValue))
                    }
                }.frame(maxWidth: .infinity)
                Divider()
                Picker(store.t("theme"), selection: $store.theme) {
                    ForEach(["system", "dark", "light"], id: \.self) { Text(store.t($0)).tag($0) }
                }.pickerStyle(.segmented)
                Picker(store.t("glassMaterial"), selection: $store.preferences.glassStyle) {
                    Text(store.t("regularGlass")).tag("regular")
                    Text(store.t("clearGlass")).tag("clear")
                }
                HStack {
                    Text(store.t("glassTransparency")).font(.caption)
                    Slider(value: $store.preferences.glassTransparency, in: 0...1)
                }
                HStack {
                    Text(store.t("atmosphere")).font(.caption)
                    Slider(value: $store.preferences.atmosphere, in: 0...1)
                }
            }
            card {
                Picker(store.t("density"), selection: $store.preferences.compactRows) {
                    Text(store.t("comfortable")).tag(false)
                    Text(store.t("compact")).tag(true)
                }
                toggle("qualityBadges", $store.preferences.showQuality)
                Picker(store.t("albumSize"), selection: $store.preferences.albumSize) {
                    ForEach(["small", "medium", "large"], id: \.self) { Text(store.t($0)).tag($0) }
                }
                Picker(store.t("language"), selection: $store.language) {
                    ForEach(AppLanguage.allCases) { Text($0.name).tag($0) }
                }
                Picker(store.t("startPage"), selection: $store.preferences.startSection) {
                    ForEach(["home", "songs", "albums", "favorites", "recent"], id: \.self) {
                        Text(store.t($0)).tag($0)
                    }
                }
            }
        }
    }
    private var experience: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("lyrics"))
                HStack {
                    Text(store.t("lyricsSize")).font(.caption)
                    Slider(value: $store.preferences.lyricsFontSize, in: 14...32, step: 1)
                    Text("\(Int(store.preferences.lyricsFontSize)) pt").font(.system(size: 11, design: .monospaced))
                        .frame(width: 45)
                }
                Text("♪  Prisma Music").font(
                    .system(size: store.preferences.lyricsFontSize, weight: .semibold, design: .rounded)
                ).foregroundStyle(store.effectiveAccent).frame(maxWidth: .infinity, alignment: .leading).padding(
                    .vertical, 8)
                toggle("autoScroll", $store.preferences.autoScrollLyrics)
                toggle("bilingualLyrics", $store.preferences.translateLyrics)
                Text(store.t("translationDownloadNote")).font(.caption2).foregroundStyle(.secondary)
                HStack {
                    Text(store.t("lyricOffset")).font(.caption)
                    Slider(value: $store.preferences.lyricsOffset, in: -10...10, step: 0.1)
                    Text(String(format: "%+.1f s", store.preferences.lyricsOffset)).font(
                        .system(size: 11, design: .monospaced)
                    ).frame(width: 55)
                }
                Text(store.t("offsetNote")).font(.caption).foregroundStyle(.secondary)
            }
            card {
                SectionHeading(title: store.t("visualizer"))
                Picker(store.t("visualStyle"), selection: $store.preferences.visualizerStyle) {
                    ForEach(["aurora", "orbit", "ribbons"], id: \.self) { Text(store.t($0)).tag($0) }
                }.pickerStyle(.segmented)
                VisualizerCanvas(
                    level: max(0.1, store.level), playing: store.preferences.animateVisualizer,
                    color: store.effectiveAccent
                ).frame(height: 145).background(.black, in: RoundedRectangle(cornerRadius: 14)).clipped()
                HStack {
                    Text(store.t("sensitivity")).font(.caption)
                    Slider(value: $store.preferences.visualizerSensitivity, in: 0.5...3)
                }
                Picker(store.t("frameRate"), selection: $store.preferences.visualizerFPS) {
                    ForEach([24.0, 30, 60], id: \.self) { Text("\(Int($0)) fps").tag($0) }
                }
                toggle("animations", $store.preferences.animateVisualizer)
            }
        }
    }
    private var shortcuts: some View {
        VStack(spacing: 16) {
            card {
                SectionHeading(title: store.t("keyboard"))
                ForEach(
                    [
                        ("findMusic", "⌘ F"), ("add", "⌘ O"), ("fileInfo", "⌘ I"), ("scan", "⌘ R"), ("play", "⇧ ⌘ P"),
                        ("next", "⌘ →"), ("previous", "⌘ ←"), ("mini", "⇧ ⌘ M"), ("full", "⌃ ⌘ F"), ("settings", "⌘ ,"),
                    ], id: \.0
                ) { item in
                    HStack {
                        Text(store.t(item.0)).font(.system(size: 12))
                        Spacer()
                        Text(item.1).font(.system(size: 11, design: .monospaced)).padding(.horizontal, 9).padding(
                            .vertical, 5
                        ).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
            card { Text(store.t("listKeyboardHelp")).font(.caption).foregroundStyle(.secondary) }
            card {
                Text("PRISMA MUSIC").font(.system(size: 20, weight: .light, design: .rounded)).tracking(4)
                Text("Prisma Music " + AppVersion.current + " · beta (" + AppVersion.build + ")").font(.caption)
                    .foregroundStyle(.secondary)
                Text(store.t("engine")).font(.caption).foregroundStyle(.secondary)
                Text(store.t("tagNote")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
    private func toggle(_ key: String, _ binding: Binding<Bool>) -> some View {
        Toggle(store.t(key), isOn: binding).toggleStyle(.switch).controlSize(.small).font(.system(size: 12)).padding(
            .vertical, 3)
    }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 15, content: content).padding(20).frame(
            maxWidth: .infinity, alignment: .leading
        ).prismaGlass(20)
    }
    private func metric(_ value: String, _ title: String) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(.system(size: 26, weight: .light, design: .rounded))
            Text(title).font(.system(size: 9)).foregroundStyle(.secondary)
        }
    }
}
struct EqualizerGraph: View {
    var gains: [Float]
    var color: Color
    var body: some View {
        Canvas { context, size in
            for i in 0...4 {
                var line = Path()
                let y = CGFloat(i) * size.height / 4
                line.move(to: CGPoint(x: 0, y: y))
                line.addLine(to: CGPoint(x: size.width, y: y))
                context.stroke(
                    line, with: .color(.primary.opacity(0.07)), style: StrokeStyle(lineWidth: 1, dash: [3, 5]))
            }
            let points = gains.enumerated().map {
                CGPoint(
                    x: Double($0.offset) / 9 * size.width,
                    y: size.height / 2 - Double($0.element) / 12 * size.height * 0.45)
            }
            var path = Path()
            path.addLines(points)
            var fill = path
            fill.addLine(to: CGPoint(x: size.width, y: size.height))
            fill.addLine(to: CGPoint(x: 0, y: size.height))
            fill.closeSubpath()
            context.fill(
                fill,
                with: .linearGradient(
                    Gradient(colors: [color.opacity(0.23), color.opacity(0)]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 2, lineJoin: .round))
            for point in points {
                context.fill(
                    Path(ellipseIn: CGRect(x: point.x - 2.5, y: point.y - 2.5, width: 5, height: 5)),
                    with: .color(color))
            }
        }
    }
}
struct NASView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let retry: LibraryStore.NASRetry?
    @State private var address: String
    @State private var job: Task<Void, Never>?
    @State private var failed = false

    init(retry: LibraryStore.NASRetry? = nil, initialAddress: String = "smb://") {
        self.retry = retry
        _address = State(initialValue: initialAddress)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Label(
                store.t(retry == nil ? "connect" : "reconnectNAS"), systemImage: "externaldrive.connected.to.line.below"
            )
            .font(.title2.bold())
            Text(store.t(retry == nil ? "nasHelp" : "reconnectHelp")).foregroundStyle(.secondary)
            TextField("smb://NAS/Music", text: $address).textFieldStyle(.roundedBorder).disabled(job != nil)
            if job != nil {
                HStack {
                    ProgressView().controlSize(.small)
                    Text(store.t("reconnectWaiting"))
                }
            }
            if failed { Text(store.t("reconnectFailed")).foregroundStyle(.secondary) }
            HStack {
                Button(store.t("cancel")) { dismiss() }
                Spacer()
                if let retry {
                    Button(store.t("resumeNASTrack")) {
                        failed = false
                        job = Task {
                            defer { job = nil }
                            do { try await store.resumeNASPlayback(retry) } catch {
                                if !Task.isCancelled { failed = true }
                            }
                        }
                    }.buttonStyle(.glass).disabled(job != nil)
                }
                Button(store.t(retry == nil ? "connectButton" : "reconnectNAS")) {
                    guard let server else { return }
                    if let retry {
                        failed = false
                        job = Task {
                            defer { job = nil }
                            do { try await store.reconnect(retry, server: server) } catch {
                                if !Task.isCancelled { failed = true }
                            }
                        }
                    } else if NSWorkspace.shared.open(server) {
                        dismiss()
                    } else {
                        failed = true
                    }
                }.buttonStyle(.glassProminent).disabled(server == nil || job != nil)
            }
        }.padding(28).frame(width: 480)
            .onDisappear { job?.cancel() }
    }

    private var server: URL? {
        guard let url = URL(string: address.trimmingCharacters(in: .whitespacesAndNewlines)),
            ["smb", "afp", "nfs"].contains(url.scheme?.lowercased() ?? ""), url.host?.isEmpty == false,
            url.user == nil, url.password == nil, url.query == nil, url.fragment == nil
        else { return nil }
        return url
    }
}
struct TagEditor: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.dismiss) var dismiss
    let track: Track
    @State private var values: [TagField: String]
    init(track: Track) {
        self.track = track
        _values = State(
            initialValue: Dictionary(uniqueKeysWithValues: TagField.allCases.map { ($0, $0.value(in: track)) }))
    }
    @State private var restoring = false
    @State private var writeToFile = false
    @State private var failure: String?
    @State private var fileSaveFailed = false
    private var valid: Bool { TagField.allCases.allSatisfy { $0.isValid(values[$0] ?? "") } }
    private var changes: [TagField: String] {
        values.filter { $0.value.trimmingCharacters(in: .whitespacesAndNewlines) != $0.key.value(in: track) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("edit")).font(.title2.bold())
            Form {
                ForEach(TagField.allCases) { field in
                    TextField(
                        store.t(field.rawValue),
                        text: Binding(
                            get: { values[field] ?? "" },
                            set: { values[field] = $0 }))
                }
            }.textFieldStyle(.roundedBorder).disabled(restoring)
            if store.canWriteFileTags(track) {
                Toggle(store.t("writeFileTags"), isOn: $writeToFile).disabled(restoring)
            }
            Text(store.t(valid ? writeToFile ? "writeFileTagsNote" : "tagNote" : "tagValidation")).font(.caption)
                .foregroundStyle(.secondary)
            if let failure {
                Text(failure).font(.caption).foregroundStyle(.red).textSelection(.enabled)
                if fileSaveFailed {
                    Button(store.t("saveTagsInLibrary")) {
                        store.applyTagEdits(ids: [track.id], changes: changes)
                        dismiss()
                    }.buttonStyle(.glass).disabled(!valid || changes.isEmpty || restoring || store.writingFileTags)
                }
            }
            HStack {
                Button(store.t("restoreFileTags")) {
                    restoring = true
                    Task {
                        do {
                            try await store.restoreFileTags(track)
                            dismiss()
                        } catch {
                            fileSaveFailed = false
                            failure = error.localizedDescription
                            restoring = false
                        }
                    }
                }.disabled(store.scanning || restoring)
                Spacer()
                if restoring { ProgressView().controlSize(.small) }
                Button(store.t("cancel")) { dismiss() }.keyboardShortcut(.cancelAction).disabled(restoring)
                Button(store.t("save")) {
                    if writeToFile {
                        restoring = true
                        Task {
                            failure = await store.writeFileTags(ids: [track.id], changes: changes)
                            fileSaveFailed = failure != nil
                            restoring = false
                            if failure == nil { dismiss() }
                        }
                    } else {
                        store.applyTagEdits(ids: [track.id], changes: changes)
                        dismiss()
                    }
                }.buttonStyle(.glassProminent)
                    .disabled(!valid || changes.isEmpty || store.scanning || store.writingFileTags || restoring)
            }
        }.padding(28).frame(width: 530).interactiveDismissDisabled(restoring)
    }
}
