import AppKit
import SwiftUI

@main
struct PrismaMusicApp: App {
    @NSApplicationDelegateAdaptor(PrismaAppDelegate.self) private var delegate
    @MainActor static let sharedStore = LibraryStore()
    @StateObject private var store = PrismaMusicApp.sharedStore

    init() {
        PrismaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup("Prisma Music") {
            ContentView().environmentObject(store).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
                .frame(minWidth: 1060, minHeight: 740)
                .onAppear { delegate.store = store }
                .onOpenURL { url in Task { await store.openAudioURL(url) } }
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button(store.t("welcome")) { store.openWelcome() }
                Button(store.t("settings")) { store.openSettings() }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button(store.t("findMusic")) { store.focusSearch() }.keyboardShortcut("f")
                Button(store.t("add")) { store.pickMusic() }.keyboardShortcut("o")
                Button(store.t("fileInfo")) {
                    store.showInfo.toggle()
                    store.showLyrics = false
                    store.showQueue = false
                }.keyboardShortcut("i")
                Button(store.t("scan")) { Task { await store.scan() } }.keyboardShortcut("r").disabled(store.scanning)
            }
            CommandMenu(store.t("play")) {
                Button(store.playbackControlLabel) { store.togglePlay() }.keyboardShortcut(
                    "p", modifiers: [.command, .shift])
                Button(store.t("next")) { store.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button(store.t("previous")) { store.next(back: true) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button(store.t("mini")) { store.miniPlayer() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button(store.t("full")) { store.fullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
            }
        }
        Settings {
            SettingsView().environmentObject(store).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
        }
    }
}

@MainActor
final class PrismaAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let store else { return .terminateNow }
        Task {
            do {
                try await store.prepareForTermination()
                sender.reply(toApplicationShouldTerminate: true)
            } catch {
                let alert = NSAlert()
                alert.messageText = "Prisma Music"
                alert.informativeText = error.localizedDescription
                alert.runModal()
                sender.reply(toApplicationShouldTerminate: false)
            }
        }
        return .terminateLater
    }
}
