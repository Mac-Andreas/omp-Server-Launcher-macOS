// Server-folder + process helpers, independent of any specific Wine install.
// The Wine runtime itself is managed by WineManager (downloaded build), so this
// no longer knows about CrossOver. The Wine "bottle" is just a WINEPREFIX
// directory under Application Support.
import Foundation

enum ServerEnv {
    // Server binaries are now linked explicitly per instance (see ServersStore),
    // so this no longer assumes server files live beside the .app. It owns the
    // shared Wine prefix, running-process cleanup, and the folder of the
    // currently-selected server (which Config/Bans operate on).

    // MARK: Active server folder

    /// Folder of the server currently being edited in Config/Bans. Set by the
    /// app when the selected server changes; empty until a server is added.
    /// Main-actor isolated: only the UI stores read/write it.
    @MainActor static var serverDir: String = ""

    // MARK: Wine prefix (the "bottle")

    private static var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server Manager", isDirectory: true)
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

    // MARK: External-process detection (servers we didn't launch)

    /// PIDs of any running process whose command line contains the given binary
    /// path — i.e. that exact server, launched from a terminal or another tool.
    /// Each server lives in its own folder, so the full path uniquely identifies
    /// the instance. Excludes this manager's own PID.
    static func externalPIDs(forBinaryPath path: String) -> [Int32] {
        // pgrep -f treats its pattern as a REGEX, so a path containing regex
        // metacharacters (e.g. "[MacOS]", ".", "(") wouldn't match literally.
        // Escape every metacharacter so the path matches as plain text.
        let pattern = regexEscaped(path)
        let r = Shell.run("/usr/bin/pgrep", ["-f", pattern], timeout: 5)
        guard r.exitCode == 0 else { return [] }
        let me = ProcessInfo.processInfo.processIdentifier
        return r.stdout
            .split(whereSeparator: \.isNewline)
            .compactMap { Int32($0.trimmingCharacters(in: .whitespaces)) }
            .filter { $0 != me }
    }

    /// Backslash-escape characters that are special in a basic/extended regex so
    /// an arbitrary file path matches literally with `pgrep -f`.
    private static func regexEscaped(_ s: String) -> String {
        let specials = Set("\\.^$|?*+()[]{}")
        var out = ""
        for ch in s {
            if specials.contains(ch) { out.append("\\") }
            out.append(ch)
        }
        return out
    }

    /// True if that server binary is currently running outside this app.
    static func isRunningExternally(binaryPath path: String) -> Bool {
        !externalPIDs(forBinaryPath: path).isEmpty
    }

    /// Terminate the external processes running the given server binary.
    static func killExternal(binaryPath path: String) {
        for pid in externalPIDs(forBinaryPath: path) {
            kill(pid, SIGTERM)
        }
    }
}
