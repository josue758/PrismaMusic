import SwiftUI
import AppKit

@main
struct PrismaMusicApp: App {
    @StateObject private var store = LibraryStore()
    var body: some Scene {
        WindowGroup("Prisma Music") {
            ContentView().environmentObject(store).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
                .frame(minWidth: 1060, minHeight: 740)
                .onOpenURL { url in Task { await store.addSources([url]) } }
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) { Button(store.t("settings")) { store.openSettings() }.keyboardShortcut(",") }
            CommandGroup(after: .newItem) {
                Button(store.t("add")) { store.pickMusic() }.keyboardShortcut("o")
                Button(store.t("fileInfo")) { store.inspectedID = nil; store.showInfo.toggle(); store.showLyrics = false; store.showQueue = false }.keyboardShortcut("i")
                Button(store.t("scan")) { Task { await store.scan() } }.keyboardShortcut("r").disabled(store.scanning)
            }
            CommandMenu(store.t("play")) {
                Button(store.t(store.isPlaying ? "pause" : "play")) { store.togglePlay() }.keyboardShortcut(.space, modifiers: [])
                Button(store.t("next")) { store.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button(store.t("previous")) { store.next(back: true) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button(store.t("mini")) { store.miniPlayer() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button(store.t("full")) { store.fullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
        Settings { SettingsView().environmentObject(store).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme) }
    }
}
