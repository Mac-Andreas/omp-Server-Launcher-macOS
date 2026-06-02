// Reads/writes the open.mp `bans.json` in serverDir — a JSON array of
// { address, player, reason, time } objects (may be empty []).
import Foundation

struct BanEntry: Identifiable, Codable, Equatable {
    var id = UUID()
    var address: String
    var player: String
    var reason: String
    var time: String

    enum CodingKeys: String, CodingKey { case address, player, reason, time }
}

@MainActor
final class BansStore: ObservableObject {
    @Published private(set) var bans: [BanEntry] = []
    @Published private(set) var exists = false

    private var path: String { "\(ServerEnv.serverDir)/bans.json" }

    func load() {
        let fm = FileManager.default
        // Create an empty bans.json on first look so the server (and this view)
        // always have a file to work with — no "not found" state.
        if !fm.fileExists(atPath: path), !ServerEnv.serverDir.isEmpty {
            _ = save()
        }
        guard let data = fm.contents(atPath: path) else {
            exists = false
            bans = []
            return
        }
        exists = true
        bans = (try? JSONDecoder().decode([BanEntry].self, from: data)) ?? []
    }

    @discardableResult
    func removeBan(_ entry: BanEntry) -> String? {
        bans.removeAll { $0.id == entry.id }
        return save()
    }

    @discardableResult
    func save() -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted]
        guard let data = try? encoder.encode(bans) else {
            return "Could not serialize bans.json."
        }
        do {
            try data.write(to: URL(fileURLWithPath: path), options: .atomic)
            return nil
        } catch {
            return error.localizedDescription
        }
    }
}
