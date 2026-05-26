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

@MainActor
final class ConfigStore: ObservableObject {
    @Published var exists: Bool = false

    @Published var serverName = ""
    @Published var password = ""
    @Published var maxPlayers = 50
    @Published var port = 7777
    @Published var rconPassword = ""
    @Published var gamemode = ""        // bare name (first main_scripts entry)
    @Published var filterscript = ""    // bare name (first side_scripts entry)

    /// Available `*.amx` names for dropdowns.
    @Published private(set) var gamemodeOptions: [String] = []
    @Published private(set) var filterscriptOptions: [String] = []

    private var raw: [String: Any] = [:]

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
            return
        }
        raw = obj
        exists = true

        serverName  = (obj["name"] as? String) ?? ""
        password    = (obj["password"] as? String) ?? ""
        maxPlayers  = (obj["max_players"] as? Int) ?? 50

        if let network = obj["network"] as? [String: Any] {
            port = (network["port"] as? Int) ?? 7777
        }
        if let rcon = obj["rcon"] as? [String: Any] {
            rconPassword = (rcon["password"] as? String) ?? ""
        }
        if let pawn = obj["pawn"] as? [String: Any] {
            gamemode = firstScriptName(pawn["main_scripts"])
            filterscript = firstScriptName(pawn["side_scripts"])
        }
    }

    /// open.mp main_scripts entries are often "name 1" (script + RCON arg).
    /// Surface the bare leading token.
    private func firstScriptName(_ value: Any?) -> String {
        guard let arr = value as? [String], let first = arr.first else { return "" }
        return first.split(separator: " ").first.map(String.init) ?? first
    }

    private func scanScripts() {
        gamemodeOptions     = amxNames(in: "gamemodes")
        filterscriptOptions = amxNames(in: "filterscripts")
    }

    private func amxNames(in subdir: String) -> [String] {
        let dir = "\(ServerEnv.serverDir)/\(subdir)"
        let items = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        return items
            .filter { $0.hasSuffix(".amx") }
            .map { String($0.dropLast(4)) }
            .sorted()
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
        pawn["side_scripts"] = filterscript.isEmpty ? [] : [filterscript]
        obj["pawn"] = pawn

        guard let data = try? JSONSerialization.data(
            withJSONObject: obj, options: [.prettyPrinted, .sortedKeys])
        else { return "Could not serialize config.json." }

        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            raw = obj
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
