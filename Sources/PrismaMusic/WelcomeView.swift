import SwiftUI

struct WelcomeView: View {
    @EnvironmentObject var store: LibraryStore
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var page = 0
    @State private var nas = false
    @State private var editing: Track?
    private let titles = ["welcomeLanguage", "welcomeLibrary", "welcomeLook", "welcomeReady"]
    private let symbols = ["globe", "music.note.house", "sparkles", "headphones"]
    var body: some View {
        ZStack {
            PrismaBackdrop(reactive: false)
            HStack(spacing: 28) {
                VStack(alignment: .leading, spacing: 24) {
                    Image(systemName: "waveform.path").font(.system(size: 48, weight: .ultraLight)).foregroundStyle(
                        store.effectiveAccent)
                    Text("PRISMA\nMUSIC").font(.system(size: 30, weight: .semibold, design: .rounded)).tracking(4)
                    Text(store.t("welcomeNote")).font(.callout).foregroundStyle(.secondary)
                    Spacer()
                    ForEach(0..<4, id: \.self) { index in
                        Button {
                            move(to: index)
                        } label: {
                            HStack(spacing: 12) {
                                Image(systemName: symbols[index]).frame(width: 22)
                                Text(store.t(titles[index])).font(.callout)
                            }.foregroundStyle(page == index ? store.effectiveAccent : .secondary).padding(.vertical, 7)
                        }.buttonStyle(.plain)
                    }
                    Text("01 — 04 / PRISMA").font(.system(size: 9, design: .monospaced)).foregroundStyle(.secondary)
                }.padding(26).frame(width: 238).prismaGlass(26)
                VStack(alignment: .leading, spacing: 22) {
                    Text(String(format: "%02d / 04", page + 1)).font(.system(size: 10, design: .monospaced)).tracking(2)
                        .foregroundStyle(store.effectiveAccent)
                    Text(store.t(titles[page])).font(.system(size: 30, weight: .bold, design: .rounded))
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            switch page {
                            case 0: language
                            case 1: library
                            case 2: appearance
                            default: essentials
                            }
                        }.padding(3).frame(maxWidth: .infinity, alignment: .leading)
                    }.scrollIndicators(.hidden)
                    Divider()
                    HStack {
                        if page > 0 { Button(store.t("welcomeBack")) { move(to: page - 1) }.buttonStyle(.glass) }
                        Spacer()
                        Button(store.t("welcomeLater")) { store.finishWelcome(scanAfter: false) }.buttonStyle(.plain)
                            .foregroundStyle(.secondary)
                        Button(store.t(page == 3 ? "welcomeStart" : "welcomeNext")) {
                            if page == 3 { store.finishWelcome() } else { move(to: page + 1) }
                        }.buttonStyle(.glassProminent).keyboardShortcut(.defaultAction)
                    }
                }.padding(.vertical, 12).frame(maxWidth: .infinity)
            }.padding(26)
        }.frame(width: 880, height: 680).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
            .interactiveDismissDisabled()
            .sheet(isPresented: $nas) { NASView().environmentObject(store) }
            .sheet(item: $editing) { TagEditor(track: $0).environmentObject(store) }
    }
    private func move(to index: Int) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { page = index }
    }
    private var language: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(store.t("welcomeLanguageNote")).foregroundStyle(.secondary)
            ForEach(AppLanguage.allCases) { language in
                Button {
                    store.language = language
                } label: {
                    HStack {
                        Text(language.name).font(.title3.weight(.medium))
                        Spacer()
                        Image(systemName: store.language == language ? "checkmark.circle.fill" : "circle")
                            .foregroundStyle(store.language == language ? store.effectiveAccent : .secondary)
                    }.padding(20).frame(maxWidth: .infinity).prismaGlass(18)
                }.buttonStyle(.plain).accessibilityAddTraits(store.language == language ? .isSelected : [])
            }
        }
    }
    private var library: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t("welcomeLibraryNote")).foregroundStyle(.secondary)
            HStack {
                Button {
                    store.pickMusic()
                } label: {
                    Label(store.t("add"), systemImage: "folder.badge.plus")
                }.buttonStyle(.glassProminent).disabled(store.scanning)
                Button {
                    nas = true
                } label: {
                    Label(store.t("connect"), systemImage: "externaldrive.connected.to.line.below")
                }.buttonStyle(.glass)
            }
            Text("\(store.tracks.count) \(store.t("count")) · \(store.sources.count) \(store.t("sources"))").font(
                .caption
            ).foregroundStyle(.secondary)
            if store.scanning {
                ProgressView(value: Double(store.scanProcessed), total: Double(max(1, store.scanDiscovered)))
                Text(store.status).font(.caption).lineLimit(2)
                Button(store.t("cancel")) { store.cancelScan() }.buttonStyle(.glass)
            }
            Toggle(store.t("recursive"), isOn: $store.preferences.recursiveScan)
            Toggle(store.t("startScan"), isOn: $store.scanOnLaunch)
            Divider()
            Text(store.t("welcomeTagsNote")).font(.caption).foregroundStyle(.secondary)
            Button(store.t("edit")) { editing = store.visualTrack ?? store.tracks.first }.buttonStyle(.glass).disabled(
                store.tracks.isEmpty)
            Toggle(store.t("online"), isOn: $store.online)
            Text(store.t("privacy")).font(.caption).foregroundStyle(.secondary)
        }
    }
    private var appearance: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text(store.t("welcomeLookNote")).foregroundStyle(.secondary)
            HStack(spacing: 10) {
                preset("glass", "drop.halffull")
                preset("calm", "moon")
                preset("contrast", "circle.lefthalf.filled")
            }
            Picker(store.t("theme"), selection: $store.theme) {
                ForEach(["system", "dark", "light"], id: \.self) { Text(store.t($0)).tag($0) }
            }.pickerStyle(.segmented)
            HStack {
                ForEach(Accent.allCases) { accent in
                    Button {
                        store.accent = accent
                        store.preferences.adaptiveArtwork = false
                    } label: {
                        Circle().fill(accent.color.gradient).frame(width: 30, height: 30).overlay {
                            if store.accent == accent {
                                Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(.white)
                            }
                        }
                    }.buttonStyle(.plain).accessibilityLabel(store.t(accent.rawValue))
                }
            }
            Toggle(store.t("adaptiveArtwork"), isOn: $store.preferences.adaptiveArtwork)
            Text(store.t("glassTransparency")).font(.caption)
            Slider(value: $store.preferences.glassTransparency, in: 0...1)
            Toggle(store.t("ambientMotion"), isOn: $store.preferences.ambientMotion)
            Toggle(store.t("microInteractions"), isOn: $store.preferences.microInteractions)
        }
    }
    private func preset(_ name: String, _ symbol: String) -> some View {
        Button {
            store.preferences.applyAppearancePreset(name)
        } label: {
            VStack(spacing: 10) {
                Image(systemName: symbol).font(.title2)
                Text(store.t("welcomePreset_" + name)).font(.caption)
            }.frame(maxWidth: .infinity).padding(.vertical, 18).prismaGlass(16)
        }.buttonStyle(.plain)
    }
    private var essentials: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text(store.t("welcomeReadyNote")).foregroundStyle(.secondary)
            Picker(store.t("startPage"), selection: $store.preferences.startSection) {
                ForEach(["immersive", "home", "songs", "albums", "favorites", "recent"], id: \.self) {
                    Text(store.t($0)).tag($0)
                }
            }
            Toggle(store.t("rememberPosition"), isOn: $store.preferences.rememberPosition)
            Toggle(store.t("autoArtwork"), isOn: $store.preferences.autoArtwork)
            Toggle(store.t("autoLyrics"), isOn: $store.preferences.autoLyrics)
            Picker(store.t("scanWorkers"), selection: $store.preferences.scanWorkers) {
                Text("2").tag(2)
                Text("4").tag(4)
                Text("8").tag(8)
            }.pickerStyle(.segmented)
            Text(store.t("scanWorkersNote")).font(.caption).foregroundStyle(.secondary)
            Label(store.t("welcomeSaved"), systemImage: "checkmark.shield").font(.callout).padding(18).frame(
                maxWidth: .infinity, alignment: .leading
            ).prismaGlass(18)
        }
    }
}
