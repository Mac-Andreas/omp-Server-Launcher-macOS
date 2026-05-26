// Starts/stops/restarts the Windows open.mp server under CrossOver's Wine and
// streams its combined stdout/stderr to `logLines` for the Logs view.
//
// Ported from the server-control parts of LauncherWindow.cpp. The Wine wrapper
// (run-omp-server-wine.sh) ships inside the bundle next to the executable; we
// run it with cwd = serverDir and OMP_SERVER_DIR set so omp-server.exe finds
// its config.
import Foundation
import Combine

@MainActor
final class ServerController: ObservableObject {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
    }

    @Published private(set) var state: State = .stopped
    /// Rolling log buffer (capped). Newest at the end.
    @Published private(set) var logLines: [String] = []

    private var process: Process?
    private let maxLines = 5_000

    /// Supplied by the app so the controller can find the installed wine binary
    /// + the Wine prefix WineManager manages.
    var wineBinaryProvider: () -> String? = { nil }
    var winePrefixProvider: () -> String = { ServerEnv.defaultPrefix }

    /// Called with the session's log lines when the server stops, so the app
    /// can persist a snapshot.
    var onSessionEnded: ([String]) -> Void = { _ in }

    var isRunning: Bool { state == .running || state == .starting }

    // MARK: Control

    func start() {
        guard state == .stopped else { return }
        guard let wine = wineBinaryProvider() else {
            append("ERROR: Wine runtime not installed. Install it from the Overview tab.")
            return
        }
        guard ServerEnv.filesPresent else {
            append("ERROR: missing \(ServerEnv.missingFiles.joined(separator: ", ")) in the server folder.")
            return
        }

        state = .starting
        // Preflight: kill any stray server so the port isn't double-bound.
        ServerEnv.killRunningServers()

        let serverDir = ServerEnv.serverDir
        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: wine)
        proc.arguments = ["\(serverDir)/omp-server.exe"]
        proc.currentDirectoryURL = URL(fileURLWithPath: serverDir)

        var env = ProcessInfo.processInfo.environment
        env["WINEPREFIX"] = winePrefixProvider()
        env["WINEDEBUG"] = "-all"
        proc.environment = env

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(text) }
        }

        proc.terminationHandler = { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.state = .stopped
                self.append("— server stopped —")
                // Persist this session's log as a snapshot.
                self.onSessionEnded(self.logLines)
            }
        }

        do {
            try proc.run()
            process = proc
            state = .running
            append("— server started —")
        } catch {
            state = .stopped
            append("ERROR: failed to launch: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        state = .stopping
        // Terminate our process, then sweep any lingering wine processes.
        process?.terminate()
        ServerEnv.killRunningServers()
        // terminationHandler flips state to .stopped.
    }

    func restart() {
        stop()
        // Give wineserver a moment to release the port before relaunching.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.start()
        }
    }

    func clearLog() { logLines.removeAll() }

    // MARK: Log buffer

    private func ingest(_ chunk: String) {
        for line in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let s = String(line)
            if s.isEmpty { continue }
            append(s)
        }
    }

    private func append(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLines {
            logLines.removeFirst(logLines.count - maxLines)
        }
    }
}
