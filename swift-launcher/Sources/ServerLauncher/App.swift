// @main entry. Sets up shared state, fixes the working directory (Finder
// launches with cwd "/"), fires the launch telemetry event, and shows the
// single window.
//
// Ported from main.cpp. Close ≠ quit is handled by the window delegate.
import SwiftUI
import AppKit

@main
struct ServerLauncherApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    @StateObject private var server = ServerController()
    @StateObject private var config = ConfigStore()
    @StateObject private var bans = BansStore()
    @StateObject private var telemetry = Telemetry()
    @StateObject private var updater = Updater()
    @StateObject private var wine = WineManager()
    @StateObject private var snapshots = SnapshotStore()

    var body: some Scene {
        Window(AppInfo.displayName, id: "main") {
            ContentView()
                .environmentObject(server)
                .environmentObject(config)
                .environmentObject(bans)
                .environmentObject(telemetry)
                .environmentObject(updater)
                .environmentObject(wine)
                .environmentObject(snapshots)
                .frame(minWidth: 820, minHeight: 580)
                .background(Theme.bg)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Let the server controller find the installed wine runtime.
                    let wineRef = wine
                    server.wineBinaryProvider = { wineRef.wineBinary }
                    server.winePrefixProvider = { ServerEnv.defaultPrefix }
                    // Auto-save a snapshot of each session when the server stops.
                    let snapRef = snapshots
                    server.onSessionEnded = { lines in snapRef.save(lines: lines) }
                    wine.refresh()
                    config.load()
                    bans.load()
                    updater.check()
                    if telemetry.enabled {
                        telemetry.send("app_launched")
                    }
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .commands {
            // Strip the default File / Edit / View / Window / Help menu groups.
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .undoRedo) {}
            CommandGroup(replacing: .pasteboard) {}
            CommandGroup(replacing: .textEditing) {}
            CommandGroup(replacing: .help) {}
            // "About <App>" opens the in-app About section instead of the
            // default panel.
            CommandGroup(replacing: .appInfo) {
                Button("About \(AppInfo.displayName)") {
                    NotificationCenter.default.post(name: .showAbout, object: nil)
                }
            }
        }
    }
}

extension Notification.Name {
    static let showAbout = Notification.Name("ShowAboutSection")
}

// Handles "close hides, doesn't quit", dock-reopen, and trims the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Finder launches with cwd "/". Server config/components live beside the
        // .app, so set cwd to the server folder.
        FileManager.default.changeCurrentDirectoryPath(ServerEnv.serverDir)
        NSApp.setActivationPolicy(.regular)
        // Intercept the window's close button so closing hides instead of
        // destroying the window (the server keeps running). Run after the
        // SwiftUI window exists.
        DispatchQueue.main.async { [weak self] in
            for w in NSApp.windows { w.delegate = self }
            self?.trimMenu()
        }
    }

    // Keep only the app menu (Quit etc.); drop File/Edit/View/Window/Help.
    @MainActor private func trimMenu() {
        guard let main = NSApp.mainMenu else { return }
        for item in main.items where item.title != ProcessInfo.processInfo.processName
            && item != main.items.first {
            // Remove everything except the leftmost (app) menu.
            main.removeItem(item)
        }
    }

    // Close button hides the window rather than closing it.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        sender.orderOut(nil)
        return false
    }

    // Keep the app (and the running server) alive when the window is closed.
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    // Reshow the window when the dock icon is clicked while hidden.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            for w in sender.windows { w.makeKeyAndOrderFront(nil) }
            NSApp.activate(ignoringOtherApps: true)
        }
        return true
    }
}
