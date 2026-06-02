// Tails a text file (open.mp's log.txt), delivering newly-appended lines. Used
// to surface live output for servers we DIDN'T launch (started from a terminal),
// where we can't read the process's stdout directly.
//
// Implementation: poll the file size on a timer; when it grows, read the new
// bytes and split into lines. If the file shrinks (truncated/rotated on restart),
// start over from the beginning. Polling (vs. a dispatch source) keeps it simple
// and works across log rotation.
import Foundation

@MainActor
final class LogTailer {
    private let url: URL
    private let onLines: ([String]) -> Void
    private var offset: UInt64 = 0
    private var partial = ""        // carry an unterminated trailing line between reads
    private var timer: Timer?

    /// `fromEnd` true starts tailing from the current end (only new output);
    /// false reads the whole file first (the existing log, then new output).
    init(path: String, fromEnd: Bool, onLines: @escaping ([String]) -> Void) {
        self.url = URL(fileURLWithPath: path)
        self.onLines = onLines
        if fromEnd {
            offset = (try? FileManager.default.attributesOfItem(atPath: path)[.size] as? UInt64) ?? 0
        }
    }

    func start() {
        stop()
        read()   // immediate first read
        let t = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.read() }
        }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func read() {
        let fm = FileManager.default
        guard let size = (try? fm.attributesOfItem(atPath: url.path)[.size]) as? UInt64 else {
            return  // file not there (yet)
        }
        // Truncated/rotated → restart from the top.
        if size < offset { offset = 0; partial = "" }
        guard size > offset else { return }

        guard let handle = try? FileHandle(forReadingFrom: url) else { return }
        defer { try? handle.close() }
        do {
            try handle.seek(toOffset: offset)
            guard let data = try handle.read(upToCount: Int(size - offset)), !data.isEmpty else { return }
            offset += UInt64(data.count)
            let chunk = partial + (String(data: data, encoding: .utf8) ?? "")
            var lines = chunk.components(separatedBy: "\n")
            partial = lines.removeLast()   // keep the trailing (possibly unfinished) line
            let complete = lines.filter { !$0.isEmpty }
            if !complete.isEmpty { onLines(complete) }
        } catch {
            // Ignore transient read errors; next tick retries.
        }
    }
}
