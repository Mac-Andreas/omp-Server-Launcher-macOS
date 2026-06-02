// Persists one log snapshot per server session. A snapshot is written when the
// server stops (see ServerController). The Logs tab lists snapshots newest-
// first and can view / export / delete them.
//
// Files live in ~/Library/Application Support/open.mp Server Launcher/snapshots
// named "<epoch-ms>__<server>.log": the epoch is the creation time and the
// suffix records which server the session belonged to (so the Logs tab can
// filter by server). Legacy files without the "__<server>" suffix are still
// read and shown as an unknown server.
import Foundation
import Combine

struct LogSnapshot: Identifiable, Equatable {
    let id: String          // filename without extension
    let created: Date
    let url: URL
    let lineCount: Int
    let server: String      // display name of the server, or "" if unknown
}

@MainActor
final class SnapshotStore: ObservableObject {
    @Published private(set) var snapshots: [LogSnapshot] = []

    private var dir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("open.mp Server Launcher/snapshots", isDirectory: true)
    }

    init() { reload() }

    func reload() {
        let fm = FileManager.default
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let files = (try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? []
        snapshots = files
            .filter { $0.pathExtension == "log" }
            .compactMap { url -> LogSnapshot? in
                let name = url.deletingPathExtension().lastPathComponent
                // "<epoch-ms>__<server>" (server optional, may itself contain "_").
                let parts = name.components(separatedBy: "__")
                guard let ms = Double(parts[0]) else { return nil }
                let server = parts.count > 1
                    ? Self.decode(parts[1...].joined(separator: "__")) : ""
                let lines = (try? String(contentsOf: url, encoding: .utf8))?
                    .split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
                return LogSnapshot(
                    id: name,
                    created: Date(timeIntervalSince1970: ms / 1000),
                    url: url,
                    lineCount: lines,
                    server: server
                )
            }
            .sorted { $0.created > $1.created }   // newest first
    }

    /// Write a snapshot from the given lines, tagged with the server's name.
    /// No-op if empty.
    func save(lines: [String], server: String) {
        guard !lines.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let tag = server.isEmpty ? "" : "__\(Self.encode(server))"
        let url = dir.appendingPathComponent("\(ms)\(tag).log")
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
        reload()
    }

    /// File-name-safe encoding for the server tag. We percent-escape so the
    /// name survives the "__" separator and the filesystem, then decode on read.
    private static func encode(_ s: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-. ")
        return s.addingPercentEncoding(withAllowedCharacters: allowed) ?? s
    }
    private static func decode(_ s: String) -> String {
        s.removingPercentEncoding ?? s
    }

    /// Full text of a snapshot (for inline view).
    func content(of snap: LogSnapshot) -> [String] {
        guard let text = try? String(contentsOf: snap.url, encoding: .utf8) else { return [] }
        return text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    func delete(_ snap: LogSnapshot) {
        try? FileManager.default.removeItem(at: snap.url)
        reload()
    }

    func deleteAll() {
        for s in snapshots { try? FileManager.default.removeItem(at: s.url) }
        reload()
    }
}
