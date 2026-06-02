// Reads/writes the open.mp `config.json` in serverDir, editing a known subset
// of fields while PRESERVING every other key (open.mp configs carry many keys
// we don't surface). Uses JSONSerialization on a mutable dictionary so unknown
// keys round-trip untouched.
//
// Field → JSON path (verified against a real open.mp config):
//   Server name   -> name
//   Password      -> password
//   Max players   -> max_players
//   Port          -> network.port
//   RCON password -> rcon.password
//   Gamemode      -> pawn.main_scripts[]   (array of names)
//   Filterscript  -> pawn.side_scripts[]
import Foundation

/// One legacy plugin discovered in the server's `plugins/` folder, with whether
/// it's currently enabled (listed in pawn.legacy_plugins).
struct PluginToggle: Identifiable, Equatable {
    var id: String { name }
    var name: String        // file name as listed in config (e.g. "mysql.so")
    var enabled: Bool
}

/// One filterscript (an `*.amx` in `filterscripts/`, or one listed in the config
/// but missing from disk), with whether it's enabled (in pawn.side_scripts).
struct FilterscriptToggle: Identifiable, Equatable {
    var id: String { name }
    var name: String        // bare script name (no .amx)
    var enabled: Bool
    var missing: Bool = false   // listed in config but no .amx on disk
}

@MainActor
final class ConfigStore: ObservableObject {
    @Published var exists: Bool = false

    @Published var serverName = ""
    @Published var password = ""
    @Published var maxPlayers = 50
    @Published var port = 7777
    @Published var rconPassword = ""
    @Published var announce = false     // list this server on the open.mp master list
    @Published var gamemode = ""        // bare name (first main_scripts entry)
    @Published var filterscripts: [FilterscriptToggle] = []  // pawn.side_scripts toggles
    @Published var plugins: [PluginToggle] = []   // pawn.legacy_plugins toggles

    /// Available `*.amx` gamemode names for the gamemode selector.
    @Published private(set) var gamemodeOptions: [String] = []

    private var raw: [String: Any] = [:]
    /// Snapshot of the editable fields as last loaded/saved, to detect edits.
    private var clean = Snapshot()

    private struct Snapshot: Equatable {
        var serverName = ""
        var password = ""
        var maxPlayers = 50
        var port = 7777
        var rconPassword = ""
        var announce = false
        var gamemode = ""
        var filterscripts: [FilterscriptToggle] = []
        var plugins: [PluginToggle] = []
    }

    private var current: Snapshot {
        Snapshot(serverName: serverName, password: password, maxPlayers: maxPlayers,
                 port: port, rconPassword: rconPassword, announce: announce,
                 gamemode: gamemode, filterscripts: filterscripts, plugins: plugins)
    }

    /// True when the editor has unsaved changes versus the last load/save.
    var isDirty: Bool { exists && current != clean }

    private var path: String { "\(ServerEnv.serverDir)/config.json" }

    // MARK: Load

    func load() {
        scanScripts()
        let fm = FileManager.default
        guard fm.fileExists(atPath: path),
              let data = fm.contents(atPath: path),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            exists = false
            clearFields()
            return
        }
        raw = obj
        exists = true

        serverName  = (obj["name"] as? String) ?? ""
        password    = (obj["password"] as? String) ?? ""
        maxPlayers  = (obj["max_players"] as? Int) ?? 50
        // announce may be stored as a bool or 0/1.
        announce    = (obj["announce"] as? Bool) ?? ((obj["announce"] as? Int) == 1)

        if let network = obj["network"] as? [String: Any] {
            port = (network["port"] as? Int) ?? 7777
        }
        if let rcon = obj["rcon"] as? [String: Any] {
            rconPassword = (rcon["password"] as? String) ?? ""
        }
        var enabledPlugins: [String] = []
        var enabledFilters: [String] = []
        if let pawn = obj["pawn"] as? [String: Any] {
            gamemode = firstScriptName(pawn["main_scripts"])
            enabledFilters = scriptNames(pawn["side_scripts"])
            enabledPlugins = (pawn["legacy_plugins"] as? [String]) ?? []
        }
        // Gamemode reconciliation: drop a gamemode whose .amx is gone (→ none),
        // then auto-pick the first available gamemode only when none is set, so a
        // newly-added gamemode becomes the default but an explicit choice is kept.
        if !gamemode.isEmpty && !gamemodeOptions.contains(gamemode) { gamemode = "" }
        if gamemode.isEmpty { gamemode = gamemodeOptions.first ?? "" }
        // Merge discovered plugin files with those enabled in the config (a
        // config can reference a plugin whose file isn't present, and vice versa).
        // Sorted strictly A–Z so the list is stable across refreshes.
        let discovered = scanPlugins()
        let names = Array(Set(discovered + enabledPlugins))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        plugins = names.map { PluginToggle(name: $0, enabled: enabledPlugins.contains($0)) }

        // Filterscripts: every *.amx in filterscripts/ + any enabled in the config
        // that's missing from disk. Each gets an on/off toggle.
        filterscripts = buildFilterscripts(enabled: enabledFilters)

        clean = current   // mark freshly-loaded state as clean
    }

    /// Build the filterscript toggle list: discovered .amx (enabled if listed in
    /// the config) plus any config-listed script with no .amx on disk (flagged
    /// missing). Sorted strictly A–Z so the list is stable across refreshes.
    private func buildFilterscripts(enabled: [String]) -> [FilterscriptToggle] {
        let onDisk = amxNames(in: "filterscripts")
        let names = Array(Set(onDisk + enabled))
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        return names.map {
            FilterscriptToggle(name: $0, enabled: enabled.contains($0),
                               missing: !onDisk.contains($0))
        }
    }

    /// Discard in-memory edits and restore the last loaded/saved values.
    func reset() {
        serverName = clean.serverName
        password = clean.password
        maxPlayers = clean.maxPlayers
        port = clean.port
        rconPassword = clean.rconPassword
        announce = clean.announce
        gamemode = clean.gamemode
        filterscripts = clean.filterscripts
        plugins = clean.plugins
    }

    private func clearFields() {
        serverName = ""; password = ""; maxPlayers = 50; port = 7777
        rconPassword = ""; announce = false; gamemode = ""; filterscripts = []; plugins = []
        clean = current
    }

    /// open.mp main_scripts entries are often "name 1" (script + RCON arg).
    /// Surface the bare leading token.
    private func firstScriptName(_ value: Any?) -> String {
        guard let arr = value as? [String], let first = arr.first else { return "" }
        return first.split(separator: " ").first.map(String.init) ?? first
    }

    /// Bare leading token of every entry in a scripts array (e.g. side_scripts).
    private func scriptNames(_ value: Any?) -> [String] {
        guard let arr = value as? [String] else { return [] }
        return arr.map { $0.split(separator: " ").first.map(String.init) ?? $0 }
    }

    private func scanScripts() {
        gamemodeOptions = amxNames(in: "gamemodes")
    }

    private func amxNames(in subdir: String) -> [String] {
        let dir = "\(ServerEnv.serverDir)/\(subdir)"
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items
            .filter { $0.hasSuffix(".amx") }
            .map { String($0.dropLast(4)) }
            .sorted()
    }

    /// Plugin binaries found in the server's plugins/ folder (.so/.dll/.dylib).
    /// open.mp lists them by file name in pawn.legacy_plugins.
    private func scanPlugins() -> [String] {
        let dir = "\(ServerEnv.serverDir)/plugins"
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items.filter { $0.hasSuffix(".so") || $0.hasSuffix(".dll") || $0.hasSuffix(".dylib") }
    }

    // MARK: Save

    /// Write edited fields back, preserving all other keys. Returns nil on
    /// success or an error message.
    @discardableResult
    func save() -> String? {
        var obj = raw

        obj["name"] = serverName
        obj["password"] = password
        obj["max_players"] = maxPlayers
        obj["announce"] = announce

        var network = (obj["network"] as? [String: Any]) ?? [:]
        network["port"] = port
        obj["network"] = network

        var rcon = (obj["rcon"] as? [String: Any]) ?? [:]
        rcon["password"] = rconPassword
        obj["rcon"] = rcon

        var pawn = (obj["pawn"] as? [String: Any]) ?? [:]
        // Preserve any RCON-arg suffix style by writing the bare name; open.mp
        // accepts a plain "name" entry.
        pawn["main_scripts"] = gamemode.isEmpty ? [] : [gamemode]
        pawn["side_scripts"] = filterscripts.filter(\.enabled).map(\.name)
        pawn["legacy_plugins"] = plugins.filter(\.enabled).map(\.name)
        obj["pawn"] = pawn

        guard let data = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return "Could not serialize config.json." }

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            raw = obj
            clean = current   // saved state is now the clean baseline
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
