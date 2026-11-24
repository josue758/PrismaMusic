import AppKit
import SwiftUI

@main
struct PrismaMusicApp: App {
    @NSApplicationDelegateAdaptor(PrismaAppDelegate.self) private var delegate
    @MainActor static let sharedStore = LibraryStore()
    @StateObject private var store = PrismaMusicApp.sharedStore

    @State private var showUpdates = false

    init() {
        PrismaShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup("Prisma Music") {
            ContentView().environmentObject(store).tint(store.effectiveAccent).preferredColorScheme(store.colorScheme)
                .frame(minWidth: 900, minHeight: 680)
                .onAppear {
                    delegate.store = store
                    delegate.refreshMenu()
                }
                .onChange(of: store.language) { _, _ in delegate.refreshMenu() }
                .sheet(isPresented: $showUpdates) { AppUpdateView().environmentObject(store) }
                .onOpenURL { url in Task { await store.openAudioURL(url) } }
        }
        .defaultSize(width: 1360, height: 900)
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(after: .appInfo) {
                Button(store.t("checkUpdates")) { showUpdates = true }
            }
            CommandGroup(replacing: .appSettings) {
                Button(store.t("welcome")) { store.openWelcome() }
                Button {
                    store.openSettings()
                } label: {
                    Label(store.t("settings"), systemImage: "gearshape").labelStyle(.titleAndIcon)
                }.keyboardShortcut(",")
            }
            CommandGroup(after: .newItem) {
                Button(store.t("findMusic")) { store.focusSearch() }.keyboardShortcut("f")
                Button(store.t("add")) { store.pickMusic() }.keyboardShortcut("o")
                Button(store.t("fileInfo")) {
                    store.showInfo.toggle()
                    store.showLyrics = false
                    store.showQueue = false
                }.keyboardShortcut("i")
                Button(store.t("scan")) { Task { await store.scanNewMusic() } }.keyboardShortcut("r").disabled(
                    store.scanning)
            }
            CommandMenu(store.t("play")) {
                Button(store.playbackControlLabel) { store.togglePlay() }.keyboardShortcut(
                    "p", modifiers: [.command, .shift])
                Button(store.t("next")) { store.next() }.keyboardShortcut(.rightArrow, modifiers: .command)
                Button(store.t("previous")) { store.next(back: true) }.keyboardShortcut(.leftArrow, modifiers: .command)
                Button(store.t("mini")) { store.miniPlayer() }.keyboardShortcut("m", modifiers: [.command, .shift])
                Button(store.t("full")) { store.fullScreen() }.keyboardShortcut("f", modifiers: [.command, .control])
                Button(store.t("visualizer")) { store.openVisualizerStage() }
                    .keyboardShortcut("v", modifiers: [.command, .shift])
            }
        }
    }
}

@MainActor
final class PrismaAppDelegate: NSObject, NSApplicationDelegate {
    weak var store: LibraryStore?

    func applicationWillFinishLaunching(_ notification: Notification) {
        for name in [
            NSMenu.didBeginTrackingNotification, NSMenu.didAddItemNotification, NSMenu.didChangeItemNotification,
        ] {
            NotificationCenter.default.addObserver(self, selector: #selector(menuChanged), name: name, object: nil)
        }
    }

    private var localizingMenu = false
    private var menuRefreshScheduled = false

    func applicationDidBecomeActive(_ notification: Notification) { refreshMenu() }

    func refreshMenu() {
        // SwiftUI installs commands after the scene updates.
        guard !localizingMenu, !menuRefreshScheduled else { return }
        menuRefreshScheduled = true
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.menuRefreshScheduled = false
            self.localizeMenu()
        }
    }

    @objc private func menuChanged(_ notification: Notification) {
        guard let menu = notification.object as? NSMenu, let main = NSApp.mainMenu,
            menu === main || menu.supermenu === main
        else { return }
        if notification.name == NSMenu.didBeginTrackingNotification {
            localizeMenu()
        } else {
            refreshMenu()
        }
    }

    private func localizeMenu() {
        guard !localizingMenu, let store, let menu = NSApp.mainMenu else { return }
        localizingMenu = true
        defer { localizingMenu = false }
        MenuLocalization.apply(to: menu, language: store.language)
    }

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
