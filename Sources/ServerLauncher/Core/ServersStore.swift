// Multi-instance server model. The manager can run several distinct open.mp
// servers, each pointed at its own omp-server binary (native macOS) or
// omp-server.exe (Windows, via Wine). The same binary may only be added once.
//
// The list is persisted to Application Support so added servers survive
// relaunch. Each entry knows its platform, which decides how it is launched.
import Foundation
import Combine

/// Which runtime a server binary targets.
enum ServerPlatform: String, Codable, CaseIterable, Identifiable {
    case macos    // native arm64 `omp-server` (no extension)
    case windows  // `omp-server.exe`, run through Wine

    var id: String { rawValue }

    /// Conventional binary file name for this platform.
    var binaryName: String {
        switch self {
        case .macos:   return "omp-server"
        case .windows: return "omp-server.exe"
        }
    }

    var label: String {
        switch self {
        case .macos:   return "macOS"
        case .windows: return "Windows-32 (via Wine)"
        }
    }

    /// OS name only — no "(via Wine)". Used where the Wine detail is noise
    /// (e.g. the "Add a … server" button).
    var shortLabel: String {
        switch self {
        case .macos:   return "macOS"
        case .windows: return "Windows-32"
        }
    }

    /// The native dynamic-library extension a plugin must have to load on this
    /// platform's server (macOS: .dylib, Windows: .dll). A plugin with any other
    /// extension (.so/.dll on macOS, etc.) won't load.
    var pluginExtension: String {
        switch self {
        case .macos:   return "dylib"
        case .windows: return "dll"
        }
    }

    /// True if a plugin file name is loadable on this platform.
    func pluginLoads(_ fileName: String) -> Bool {
        fileName.lowercased().hasSuffix(".\(pluginExtension)")
    }
}

/// One configured server instance.
struct ServerInstance: Identifiable, Codable, Equatable {
    var id: UUID = UUID()
    /// Fallback name (used only if config.json has no "name"). The live display
    /// name comes from config.json — see `displayName`.
    var name: String
    /// Absolute path to the omp-server binary (the file the user linked).
    var binaryPath: String
    var platform: ServerPlatform
    /// True for servers the user imported (linked from an existing folder) rather
    /// than installed through the app. Optional for backward-compat with older
    /// servers.json files that predate this field.
    var imported: Bool? = nil
    /// Set when the engine is updated in place (the install-folder name keeps the
    /// original version, so this overrides it). Optional for backward-compat.
    var installedVersion: String? = nil

    /// Whether this server was imported (vs installed by the app).
    var isImported: Bool { imported ?? (versionTag == nil) }

    /// Folder the binary lives in — the server's working directory.
    var folder: String {
        (binaryPath as NSString).deletingLastPathComponent
    }

    var configPath: String { "\(folder)/config.json" }

    /// Server build version. First choice: the install-folder token
    /// "omp-server-<platform>-<version>" (present only for builds we installed).
    /// Fallback for imported servers: a semver found in a sibling README/version
    /// file. open.mp's binary has no --version flag and only prints its version at
    /// runtime, so for an arbitrary imported folder with no such file the version
    /// genuinely can't be known and this returns nil (the UI shows "imported").
    var versionTag: String? {
        // An explicit installedVersion (set by an in-place update) wins.
        if let v = installedVersion, !v.isEmpty { return v }
        let parts = folder.components(separatedBy: "/")
        for p in parts {
            if let r = p.range(of: #"omp-server-(macos|windows)-(.+)"#, options: .regularExpression) {
                let token = String(p[r])
                return token.components(separatedBy: "-").dropFirst(3).joined(separator: "-")
            }
        }
        return versionFromSiblingFiles()
    }

    private func versionFromSiblingFiles() -> String? {
        let candidates = ["version.txt", "VERSION", "README.md", "README.txt"]
        for name in candidates {
            let p = (folder as NSString).appendingPathComponent(name)
            guard let text = try? String(contentsOfFile: p, encoding: .utf8),
                  let m = text.range(of: #"\d+\.\d+\.\d+(\.\d+)?"#, options: .regularExpression)
            else { continue }
            return String(text[m])
        }
        return nil
    }

    /// True if the linked binary still exists on disk.
    var exists: Bool {
        FileManager.default.fileExists(atPath: binaryPath)
    }

    /// When the server folder was created on disk (used to disambiguate servers
    /// with the same name in the scope picker). Nil if it can't be read.
    var createdAt: Date? {
        (try? FileManager.default.attributesOfItem(atPath: folder)[.creationDate]) as? Date
    }

    /// The name shown everywhere — config.json's "name" is the source of truth;
    /// fall back to the stored name, then the folder name.
    var displayName: String {
        let raw: String
        if let n = ConfigJSON.name(at: configPath), !n.isEmpty { raw = n }
        else if !name.isEmpty { raw = name }
        else {
            let f = (folder as NSString).lastPathComponent
            raw = f.isEmpty ? "open.mp server" : f
        }
        // Drop a trailing platform suffix like " (macOS arm64)".
        return raw.replacingOccurrences(
            of: #"\s*\((macos|macOS) arm64\)\s*$"#,
            with: "", options: .regularExpression)
    }
}

/// Pre-flight checks for whether a server is safe to start. A non-empty list of
/// problems means the Start button should be disabled, with the messages shown.
enum ServerReadiness {
    static let defaultRcon = "changeme"

    /// Problems blocking `inst` from starting. `runningPorts` maps each currently
    /// running OTHER server's display name → its port, used to flag IP+port
    /// clashes (open.mp binds 0.0.0.0, so a shared port is a conflict regardless
    /// of bind address).
    static func problems(for inst: ServerInstance,
                         runningPorts: [(name: String, port: Int)]) -> [String] {
        var out: [String] = []
        let cfg = inst.configPath

        // 1. A gamemode must be set (pawn.main_scripts non-empty).
        let mains = ConfigJSON.arrayValue(forNested: ["pawn", "main_scripts"], at: cfg) ?? []
        if mains.allSatisfy({ $0.trimmingCharacters(in: .whitespaces).isEmpty }) {
            out.append("No gamemode is set — choose one in the Config tab.")
        }

        // 2. RCON password must be set and not the public default.
        let rcon = (ConfigJSON.value(forNested: ["rcon", "password"], at: cfg) ?? "")
            .trimmingCharacters(in: .whitespaces)
        if rcon.isEmpty {
            out.append("RCON password is empty — set one in the Config tab.")
        } else if rcon.lowercased() == defaultRcon {
            out.append("RCON password is still the default “\(defaultRcon)” — change it in the Config tab.")
        }

        // 3. No other running server may share this port.
        if let port = ConfigJSON.intValue(forNested: ["network", "port"], at: cfg) {
            if let clash = runningPorts.first(where: { $0.port == port }) {
                out.append("Port \(port) is already in use by “\(clash.name)”, which is running — stop it or change this server's port.")
            }
        }
        return out
    }
}

/// Minimal read/write of the "name" key in an open.mp config.json, preserving
/// all other keys. Used to keep the server's display name in sync with the file.
enum ConfigJSON {
    static func name(at path: String) -> String? {
        guard let data = FileManager.default.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        return obj["name"] as? String
    }

    /// Read a nested string value, e.g. ["rcon","password"].
    static func value(forNested keys: [String], at path: String) -> String? {
        nested(keys, at: path) as? String
    }

    /// Read a nested integer value, e.g. ["network","port"].
    static func intValue(forNested keys: [String], at path: String) -> Int? {
        nested(keys, at: path) as? Int
    }

    /// Read a nested boolean value (accepts a real bool or 0/1), e.g. ["announce"].
    static func boolValue(forNested keys: [String], at path: String) -> Bool? {
        let v = nested(keys, at: path)
        if let b = v as? Bool { return b }
        if let i = v as? Int { return i == 1 }
        return nil
    }

    /// Read a nested string array, e.g. ["pawn","main_scripts"].
    static func arrayValue(forNested keys: [String], at path: String) -> [String]? {
        nested(keys, at: path) as? [String]
    }

    private static func nested(_ keys: [String], at path: String) -> Any? {
        guard let data = FileManager.default.contents(atPath: path),
              var obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }
        for key in keys.dropLast() {
            guard let next = obj[key] as? [String: Any] else { return nil }
            obj = next
        }
        return obj[keys.last ?? ""]
    }

    /// Set "name" in config.json, creating the file if missing. Preserves other keys.
    @discardableResult
    static func setName(_ name: String, at path: String) -> Bool {
        update(at: path) { $0["name"] = name }
    }

    /// Set rcon.password (nested), creating the file/section if missing.
    @discardableResult
    static func setRconPassword(_ password: String, at path: String) -> Bool {
        update(at: path) { obj in
            var rcon = (obj["rcon"] as? [String: Any]) ?? [:]
            rcon["password"] = password
            obj["rcon"] = rcon
        }
    }

    /// Read/modify/write helper preserving all other keys.
    @discardableResult
    static func update(at path: String, _ mutate: (inout [String: Any]) -> Void) -> Bool {
        var obj: [String: Any] = [:]
        if let data = FileManager.default.contents(atPath: path),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
            obj = existing
        }
        mutate(&obj)
        guard let out = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return false }
        return (try? out.write(to: URL(fileURLWithPath: path), options: .atomic)) != nil
    }
}

@MainActor
final class ServersStore: ObservableObject {
    @Published private(set) var servers: [ServerInstance] = []

    /// The server whose folder the Config/Bans tabs edit. Defaults to the first
    /// server. Kept mirrored into ServerEnv.serverDir so those stores resolve
    /// their config.json/bans.json paths against it.
    @Published var selectedID: UUID? {
        didSet { syncActiveDir() }
    }

    var selected: ServerInstance? {
        servers.first { $0.id == selectedID } ?? servers.first
    }

    /// The selected server WITHOUT the "fall back to the first server" behaviour
    /// of `selected`. Returns nil when `selectedID` is nil or unmatched, so a
    /// platform-scoped view can clear its data instead of leaking another
    /// platform's server in.
    var selectedExact: ServerInstance? {
        servers.first { $0.id == selectedID }
    }

    private func syncActiveDir() {
        ServerEnv.serverDir = selectedExact?.folder ?? ""
    }

    private var fileURL: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server Manager", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("servers.json")
    }

    func servers(for platform: ServerPlatform) -> [ServerInstance] {
        servers.filter { $0.platform == platform }
    }

    /// True if this exact binary path is already configured.
    func contains(path: String) -> Bool {
        let std = (path as NSString).standardizingPath
        return servers.contains { ($0.binaryPath as NSString).standardizingPath == std }
    }

    /// Add a server by binary path. Refuses duplicates of the same file.
    /// Returns the added instance, or nil if it was a duplicate.
    @discardableResult
    func add(path: String, platform: ServerPlatform, name: String? = nil,
             rconPassword: String? = nil, imported: Bool = false) -> ServerInstance? {
        guard !contains(path: path) else { return nil }
        let folderName = ((path as NSString).deletingLastPathComponent as NSString).lastPathComponent
        let inst = ServerInstance(
            name: name ?? (folderName.isEmpty ? "open.mp server" : folderName),
            binaryPath: (path as NSString).standardizingPath,
            platform: platform,
            imported: imported)
        servers.append(inst)
        // If the user gave a name, make config.json reflect it (so the running
        // server announces that name and the Config tab shows it).
        if let name, !name.isEmpty {
            ConfigJSON.setName(name, at: inst.configPath)
        }
        if let rconPassword, !rconPassword.isEmpty {
            ConfigJSON.setRconPassword(rconPassword, at: inst.configPath)
        }
        if selectedID == nil { selectedID = inst.id }
        syncActiveDir()
        save()
        return inst
    }

    func remove(_ inst: ServerInstance) {
        servers.removeAll { $0.id == inst.id }
        if selectedID == inst.id { selectedID = servers.first?.id }
        syncActiveDir()
        save()
    }

    /// Override the displayed version after an in-place engine update (nil clears
    /// it, e.g. on revert, falling back to the folder-parsed version).
    func setInstalledVersion(_ version: String?, for inst: ServerInstance) {
        guard let i = servers.firstIndex(where: { $0.id == inst.id }) else { return }
        servers[i].installedVersion = version
        save()
    }

    func rename(_ inst: ServerInstance, to name: String) {
        guard let i = servers.firstIndex(where: { $0.id == inst.id }) else { return }
        servers[i].name = name
        // config.json is the source of truth for the display name, so write it
        // there too (creates the file if needed).
        ConfigJSON.setName(name, at: servers[i].configPath)
        save()
    }

    /// Notify observers that an underlying config.json changed (e.g. the Config
    /// tab saved a new name), so views recompute `displayName`.
    func configChanged() { objectWillChange.send() }

    // MARK: Persistence

    func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let list = try? JSONDecoder().decode([ServerInstance].self, from: data)
        else { return }
        servers = list
        if selectedID == nil { selectedID = servers.first?.id }
        syncActiveDir()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(servers) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }
}
