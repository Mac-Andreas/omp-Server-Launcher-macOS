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

    @StateObject private var servers = ServersStore()
    @StateObject private var registry = ControllerRegistry()
    @StateObject private var releases = ReleasesStore()
    @StateObject private var config = ConfigStore()
    @StateObject private var bans = BansStore()
    @StateObject private var telemetry = Telemetry()
    @StateObject private var updater = Updater()
    @StateObject private var wine = WineManager()
    @StateObject private var snapshots = SnapshotStore()

    var body: some Scene {
        Window(AppInfo.displayName, id: "main") {
            ContentView()
                .environmentObject(servers)
                .environmentObject(registry)
                .environmentObject(releases)
                .environmentObject(config)
                .environmentObject(bans)
                .environmentObject(telemetry)
                .environmentObject(updater)
                .environmentObject(wine)
                .environmentObject(snapshots)
                .frame(width: 940, height: 680)
                .background(Theme.bg)
                .preferredColorScheme(.dark)
                .onAppear {
                    // Central wiring so every per-server controller can find the
                    // wine runtime + prefix and persists a snapshot on stop.
                    let wineRef = wine
                    registry.wineBinaryProvider = { wineRef.wineBinary }
                    registry.winePrefixProvider = { ServerEnv.defaultPrefix }
                    let snapRef = snapshots
                    registry.onSessionEnded = { lines, server in
                        snapRef.save(lines: lines, server: server)
                    }
                    wine.refresh()
                    servers.load()
                    config.load()
                    bans.load()
                    updater.check()
                    // Detect servers launched outside the app (terminal/other tool)
                    // and reflect them as online; poll so state stays in sync.
                    let serversRef = servers
                    registry.serversProvider = { serversRef.servers }
                    registry.startMonitoring()
                    if telemetry.enabled {
                        telemetry.send("app_launched")
                        telemetry.recordLaunch()
                        // Push yesterday's rolled-up aggregate (once per day),
                        // including today's server-count snapshot. Stores are
                        // loaded above, so the counts are accurate.
                        telemetry.flushDailyIfNeeded(serverCounts: [
                            "macos":   serversRef.servers(for: .macos).count,
                            "windows": serversRef.servers(for: .windows).count,
                        ])
                    }
                    // Track foreground time for the daily average.
                    ForegroundTimer.shared.attach(telemetry)
                }
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentSize)
        .commands {
            // Strip File/Help, but KEEP Edit (undo/redo, cut/copy/paste, and
            // Select All) so ⌘A/⌘C/⌘V/⌘X work in text fields.
            CommandGroup(replacing: .newItem) {}
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

// Accumulates how long the app is in the foreground and feeds it to Telemetry
// for the daily session-time average. Times the interval between becoming and
// resigning active (and on terminate), so background time isn't counted.
@MainActor
final class ForegroundTimer {
    static let shared = ForegroundTimer()
    private weak var telemetry: Telemetry?
    private var activeSince: Date?

    func attach(_ telemetry: Telemetry) {
        guard self.telemetry == nil else { return }   // attach once
        self.telemetry = telemetry
        activeSince = Date()   // we're active at launch
        let nc = NotificationCenter.default
        nc.addObserver(self, selector: #selector(didBecomeActive),
                       name: NSApplication.didBecomeActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(willResignActive),
                       name: NSApplication.willResignActiveNotification, object: nil)
        nc.addObserver(self, selector: #selector(willTerminate),
                       name: NSApplication.willTerminateNotification, object: nil)
    }

    @objc private func didBecomeActive() { activeSince = Date() }
    @objc private func willResignActive() { flush() }
    @objc private func willTerminate() { flush() }

    private func flush() {
        guard let start = activeSince else { return }
        telemetry?.addForegroundTime(Date().timeIntervalSince(start))
        activeSince = nil
    }
}

// Handles "close hides, doesn't quit", dock-reopen, and trims the menu bar.
final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Refuse to run from a disk image / read-only or translocated location.
        // Launching directly from the mounted .dmg means macOS can force-unmount
        // the volume out from under us, leaving the app's code pages unbacked →
        // SIGBUS ("Object has no pager because the backing vnode was force
        // unmounted"). Tell the user to install it first, then quit.
        if Self.isRunningFromUninstalledLocation() {
            Self.warnMustInstallThenQuit()
            return
        }
        // Each server sets its own working directory (its binary's folder) when
        // launched, so no global cwd change is needed here.
        NSApp.setActivationPolicy(.regular)
        // Intercept the window's close button so closing hides instead of
        // destroying the window (the server keeps running). Run after the
        // SwiftUI window exists.
        DispatchQueue.main.async { [weak self] in
            for w in NSApp.windows {
                w.delegate = self
                Self.styleTitleBar(w)
            }
            self?.trimMenu()
        }
    }

    // A normal titled bar showing the app name (with its icon), tinted to match
    // the app background so it reads as one piece. Content begins right below it,
    // so there's no empty strip at the top. Window stays fixed-size.
    @MainActor static func styleTitleBar(_ w: NSWindow) {
        w.titleVisibility = .visible
        w.title = AppInfo.displayName
        w.titlebarAppearsTransparent = true     // tint the bar with our bg color
        w.styleMask.remove(.fullSizeContentView)
        // Fixed-size window: no drag-to-resize, and the zoom (green) button
        // can't maximise it.
        w.styleMask.remove(.resizable)
        w.isMovableByWindowBackground = false
        w.standardWindowButton(.zoomButton)?.isEnabled = false
        w.backgroundColor = NSColor(red: 0x20/255.0, green: 0x24/255.0,
                                    blue: 0x2C/255.0, alpha: 1)  // Theme.bg
    }

    // True when the .app is on a read-only volume (mounted DMG), is
    // app-translocated by Gatekeeper, or otherwise lives somewhere it must not
    // be run from. Running from /Applications or ~/Applications is fine.
    static func isRunningFromUninstalledLocation() -> Bool {
        let path = Bundle.main.bundlePath
        // App translocation puts the bundle under a randomized
        // /private/var/folders/.../AppTranslocation/ path.
        if path.contains("/AppTranslocation/") { return true }
        // Mounted disk images live under /Volumes (the startup disk is not).
        if path.hasPrefix("/Volumes/") { return true }
        // Read-only backing volume (the DMG) — the definitive check.
        if let values = try? URL(fileURLWithPath: path)
            .resourceValues(forKeys: [.volumeIsReadOnlyKey]),
           values.volumeIsReadOnly == true {
            return true
        }
        return false
    }

    static func warnMustInstallThenQuit() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Move Server Manager to Applications"
        alert.informativeText = """
            Server Manager is running from a disk image or download folder. It \
            must be installed first, otherwise macOS can unmount the volume and \
            the app will crash.

            Drag “Server Manager” into your Applications folder, eject the disk \
            image, then open it from Applications.
            """
        alert.addButton(withTitle: "Quit")
        alert.runModal()
        NSApp.terminate(nil)
    }

    // Keep the app menu (Quit etc.) AND the Edit menu (so ⌘A/⌘C/⌘V/⌘X/undo work
    // in text fields); drop File/View/Window/Help.
    @MainActor private func trimMenu() {
        guard let main = NSApp.mainMenu else { return }
        let keep: Set<String> = [ProcessInfo.processInfo.processName, "Edit"]
        for item in main.items where item != main.items.first && !keep.contains(item.title) {
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
