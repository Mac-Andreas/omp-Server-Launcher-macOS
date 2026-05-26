// Persists one log snapshot per server session. A snapshot is written when the
// server stops (see ServerController). The Logs tab lists snapshots newest-
// first and can view / export / delete them.
//
// Files live in ~/Library/Application Support/open.mp Server Launcher/snapshots
// named "<epoch-ms>.log". The filename's epoch is the creation time, shown in
// the user's locale.
import Foundation
import Combine

struct LogSnapshot: Identifiable, Equatable {
    let id: String          // filename without extension (epoch ms)
    let created: Date
    let url: URL
    let lineCount: Int
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
                guard let ms = Double(name) else { return nil }
                let lines = (try? String(contentsOf: url, encoding: .utf8))?
                    .split(separator: "\n", omittingEmptySubsequences: false).count ?? 0
                return LogSnapshot(
                    id: name,
                    created: Date(timeIntervalSince1970: ms / 1000),
                    url: url,
                    lineCount: lines
                )
            }
            .sorted { $0.created > $1.created }   // newest first
    }

    /// Write a snapshot from the given lines. No-op if empty.
    func save(lines: [String]) {
        guard !lines.isEmpty else { return }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let ms = Int(Date().timeIntervalSince1970 * 1000)
        let url = dir.appendingPathComponent("\(ms).log")
        let text = lines.joined(separator: "\n") + "\n"
        try? text.write(to: url, atomically: true, encoding: .utf8)
        reload()
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
