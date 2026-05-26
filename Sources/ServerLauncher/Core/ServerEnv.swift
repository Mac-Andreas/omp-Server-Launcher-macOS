// Server-folder + process helpers, independent of any specific Wine install.
// The Wine runtime itself is managed by WineManager (downloaded build), so this
// no longer knows about CrossOver. The Wine "bottle" is just a WINEPREFIX
// directory under Application Support.
import Foundation

enum ServerEnv {
    // MARK: Server folder + files

    /// The open.mp server folder = the folder containing the .app. The .app is
    /// dropped INTO the server folder, so server files are its siblings.
    static var serverDir: String {
        let appURL = URL(fileURLWithPath: Bundle.main.bundlePath)
        if appURL.pathExtension == "app" {
            return appURL.deletingLastPathComponent().path
        }
        return FileManager.default.currentDirectoryPath
    }

    /// Files the launcher needs in serverDir().
    static let requiredFiles = ["omp-server.exe"]

    static var missingFiles: [String] {
        let dir = serverDir
        return requiredFiles.filter { !FileManager.default.fileExists(atPath: "\(dir)/\($0)") }
    }

    static var filesPresent: Bool { missingFiles.isEmpty }

    // MARK: Wine prefix (the "bottle")

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("open.mp Server Launcher", isDirectory: true)
    }

    /// Default WINEPREFIX directory (created by wine on first run).
    static var defaultPrefix: String {
        appSupport.appendingPathComponent("prefix", isDirectory: true).path
    }

    static var prefixExists: Bool {
        FileManager.default.fileExists(atPath: "\(defaultPrefix)/system.reg")
    }

    /// Delete the prefix (clean slate). The next server start recreates it.
    static func deletePrefix() {
        try? FileManager.default.removeItem(atPath: defaultPrefix)
    }

    // MARK: Running-server detection / cleanup

    static var serverRunning: Bool {
        let r = Shell.run("/usr/bin/pgrep", ["-i", "-f", "omp-server.exe"], timeout: 5)
        return r.exitCode == 0 && !r.stdout.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Kill any running omp-server.exe, then any wineserver. Blocking.
    static func killRunningServers() {
        for pat in ["omp-server.exe", "wineserver"] {
            _ = Shell.run("/usr/bin/pkill", ["-i", "-f", pat], timeout: 5)
        }
    }
}
