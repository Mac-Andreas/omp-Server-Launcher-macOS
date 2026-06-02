// Per-instance server runner. The manager keeps one InstanceController per
// configured ServerInstance, so several servers can run concurrently, each
// with its own process and live log.
//
// Native (macOS) servers run the omp-server binary directly. Windows servers
// run omp-server.exe through the downloaded Wine runtime with a shared
// WINEPREFIX. Either way the working directory is the binary's folder so the
// server finds its config/components.
import Foundation
import Combine

@MainActor
final class InstanceController: ObservableObject, Identifiable {
    enum State: Equatable {
        case stopped
        case starting
        case running
        case stopping
        case crashed   // exited unexpectedly (non-zero) without a user stop
    }

    let instance: ServerInstance
    nonisolated let id: UUID

    @Published private(set) var state: State = .stopped
    /// True when "running" was detected for a process WE didn't launch (started
    /// from a terminal or another tool). We can show it online and stop it, but
    /// can't capture its live log (its stdout belongs to whoever spawned it).
    @Published private(set) var isExternal = false
    /// Rolling log buffer (capped). Newest at the end.
    @Published private(set) var logLines: [String] = []
    /// Live resource usage of the running server process, or nil when stopped.
    @Published private(set) var usage: ResourceUsage?

    struct ResourceUsage: Equatable {
        var cpuPercent: Double      // %, can exceed 100 across cores
        var rssBytes: Int64         // resident memory
        var ramPercent: Double      // rss as a % of physical RAM
    }

    private var process: Process?
    /// Pipe feeding the server's stdin, so we can send console commands (e.g.
    /// loadfs/unloadfs) to a running server.
    private var stdinPipe: Pipe?
    /// Tails the server's log.txt for output we can't get from stdout (adopted
    /// external servers).
    private var tailer: LogTailer?
    /// open.mp writes its console log here by default.
    private var logFilePath: String { "\(instance.folder)/log.txt" }
    private let maxLines = 5_000
    /// Set true when the user asks to stop, so a clean stop isn't flagged crash.
    private var userStopped = false

    /// Resolves the installed wine binary (only needed for Windows instances).
    var wineBinaryProvider: () -> String? = { nil }
    var winePrefixProvider: () -> String = { ServerEnv.defaultPrefix }
    /// Called with the session's log lines and the server's name when it stops.
    var onSessionEnded: ([String], String) -> Void = { _, _ in }

    init(instance: ServerInstance) {
        self.instance = instance
        self.id = instance.id
    }

    var isRunning: Bool { state == .running || state == .starting }

    // MARK: Control

    func start() {
        guard state == .stopped || state == .crashed else { return }
        guard instance.exists else {
            append("ERROR: \(instance.binaryPath) no longer exists.")
            return
        }
        // Refuse to launch a second copy if this server is already running
        // outside the app — adopt that one instead.
        if ServerEnv.isRunningExternally(binaryPath: instance.binaryPath) {
            adoptExternal()
            return
        }
        userStopped = false

        let proc = Process()
        var env = ProcessInfo.processInfo.environment

        switch instance.platform {
        case .macos:
            proc.executableURL = URL(fileURLWithPath: instance.binaryPath)
            proc.arguments = []
        case .windows:
            guard let wine = wineBinaryProvider() else {
                append("ERROR: Wine runtime not installed. Install it from the Setup tab.")
                return
            }
            proc.executableURL = URL(fileURLWithPath: wine)
            proc.arguments = [instance.binaryPath]
            env["WINEPREFIX"] = winePrefixProvider()
            env["WINEDEBUG"] = "-all"
        }

        proc.currentDirectoryURL = URL(fileURLWithPath: instance.folder)
        proc.environment = env

        state = .starting

        let pipe = Pipe()
        proc.standardOutput = pipe
        proc.standardError = pipe
        // stdin pipe lets us push console commands (loadfs/unloadfs, etc.).
        let inPipe = Pipe()
        proc.standardInput = inPipe
        stdinPipe = inPipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            Task { @MainActor in self?.ingest(text) }
        }

        proc.terminationHandler = { [weak self] p in
            let code = p.terminationStatus
            let reason = p.terminationReason
            Task { @MainActor in
                guard let self else { return }
                self.process = nil
                self.stdinPipe = nil
                // Crash = exited on its own (we didn't stop it) with a non-zero
                // code or via an uncaught signal.
                let crashed = !self.userStopped
                    && (code != 0 || reason == .uncaughtSignal)
                if crashed {
                    self.state = .crashed
                    self.append("— server exited unexpectedly (code \(code)) —")
                } else {
                    self.state = .stopped
                    self.append("— server stopped —")
                }
                self.stopUsageSampling()
                self.onSessionEnded(self.logLines, self.instance.displayName)
            }
        }

        do {
            try proc.run()
            process = proc
            state = .running
            append("— server started —")
            startUsageSampling()
        } catch {
            state = .stopped
            append("ERROR: failed to launch: \(error.localizedDescription)")
        }
    }

    func stop() {
        guard isRunning else { return }
        userStopped = true
        state = .stopping
        // An adopted external server has no child process of ours — terminate it
        // by PID (matched on its binary path).
        if isExternal {
            ServerEnv.killExternal(binaryPath: instance.binaryPath)
            if instance.platform == .windows { ServerEnv.killRunningServers() }
            stopTailing()
            stopUsageSampling()
            append("— stopped external server —")
            isExternal = false
            state = .stopped
            return
        }
        process?.terminate()
        // Windows servers can leave a wineserver/omp-server.exe behind; native
        // ones don't, so only sweep for Windows instances.
        if instance.platform == .windows {
            ServerEnv.killRunningServers()
        }
    }

    // MARK: External adoption

    /// Mark this server as running because a matching process was found that we
    /// didn't launch. We can't read its stdout, so we tail its log.txt instead.
    private func adoptExternal() {
        guard !isExternal else { return }
        isExternal = true
        state = .running
        startUsageSampling()
        append("— adopted a server already running outside the app —")
        if FileManager.default.fileExists(atPath: logFilePath) {
            append("(tailing log.txt for output)")
            startTailing(fromEnd: true)
        } else {
            append("(no log.txt found — start it through the app to capture full output)")
        }
    }

    /// Begin tailing the server's log.txt into the live log buffer.
    private func startTailing(fromEnd: Bool) {
        tailer?.stop()
        tailer = LogTailer(path: logFilePath, fromEnd: fromEnd) { [weak self] lines in
            for l in lines { self?.append(l) }
        }
        tailer?.start()
    }

    private func stopTailing() {
        tailer?.stop()
        tailer = nil
    }

    // MARK: Resource usage (CPU / RAM) sampling

    private var usageTimer: Timer?

    /// The PID of the running server process: our own child if we launched it,
    /// otherwise the first matching external process.
    private var runningPID: Int32? {
        if let p = process { return p.processIdentifier }
        return ServerEnv.externalPIDs(forBinaryPath: instance.binaryPath).first
    }

    /// Start sampling CPU/RAM every couple of seconds while running.
    func startUsageSampling() {
        usageTimer?.invalidate()
        sampleUsage()
        let t = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sampleUsage() }
        }
        RunLoop.main.add(t, forMode: .common)
        usageTimer = t
    }

    func stopUsageSampling() {
        usageTimer?.invalidate()
        usageTimer = nil
        usage = nil
    }

    private func sampleUsage() {
        guard isRunning, let pid = runningPID else { usage = nil; return }
        // `ps` reports %cpu and RSS (KiB). Empty headers (=) so we get raw values.
        let r = Shell.run("/bin/ps", ["-o", "%cpu=,rss=", "-p", String(pid)], timeout: 4)
        let parts = r.stdout.trimmingCharacters(in: .whitespacesAndNewlines)
            .split(whereSeparator: \.isWhitespace)
        guard parts.count >= 2,
              let cpu = Double(parts[0]),
              let rssKiB = Int64(parts[1]) else { usage = nil; return }
        let rss = rssKiB * 1024
        let total = Int64(ProcessInfo.processInfo.physicalMemory)
        let ramPct = total > 0 ? Double(rss) / Double(total) * 100 : 0
        usage = ResourceUsage(cpuPercent: cpu, rssBytes: rss, ramPercent: ramPct)
    }

    /// Reconcile our state with reality. Called periodically by the registry.
    /// Adopts a newly-detected external server, and clears the running state if an
    /// adopted external server has since exited.
    func reconcileExternal() {
        // Only touch state when WE aren't the one running it.
        if process != nil { return }
        let externallyUp = ServerEnv.isRunningExternally(binaryPath: instance.binaryPath)
        if externallyUp {
            if state == .stopped || state == .crashed { adoptExternal() }
        } else if isExternal {
            // The external process is gone.
            stopTailing()
            stopUsageSampling()
            isExternal = false
            state = .stopped
            append("— external server stopped —")
        }
    }

    func restart() {
        stop()
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            self?.start()
        }
    }

    func clearLog() { logLines.removeAll() }

    /// Send a console command (without trailing newline) to the running server's
    /// stdin — e.g. "loadfs map_arenas". No-op if the server isn't running.
    @discardableResult
    func sendCommand(_ command: String) -> Bool {
        guard isRunning, let handle = stdinPipe?.fileHandleForWriting else { return false }
        guard let data = (command + "\n").data(using: .utf8) else { return false }
        do {
            try handle.write(contentsOf: data)
            append("> \(command)")
            return true
        } catch {
            append("ERROR: couldn’t send “\(command)”: \(error.localizedDescription)")
            return false
        }
    }

    // MARK: Log buffer

    private static let entryStart = try! NSRegularExpression(
        pattern: #"(?=\[\d{4}-\d{2}-\d{2}T)"#)

    private func ingest(_ chunk: String) {
        for raw in chunk.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = String(raw)
            if line.isEmpty { continue }
            let ns = line as NSString
            let matches = Self.entryStart.matches(in: line, range: NSRange(location: 0, length: ns.length))
            if matches.count <= 1 {
                append(line)
                continue
            }
            var starts = matches.map { $0.range.location }
            starts.append(ns.length)
            if starts.first! > 0 { append(ns.substring(to: starts.first!)) }
            for i in 0..<(starts.count - 1) where starts[i] < starts[i + 1] {
                let piece = ns.substring(with: NSRange(location: starts[i], length: starts[i + 1] - starts[i]))
                if !piece.isEmpty { append(piece) }
            }
        }
    }

    private func append(_ line: String) {
        logLines.append(line)
        if logLines.count > maxLines {
            logLines.removeFirst(logLines.count - maxLines)
        }
        detectFatal(line)
    }

    // Some fatal conditions (e.g. the legacy network failing to bind the port)
    // are logged as an [Error] but the process keeps running, so a process-exit
    // check alone won't catch them. Flip to .crashed when we see such a line so
    // the status reflects that the server didn't actually come up.
    private func detectFatal(_ line: String) {
        guard state == .running || state == .starting else { return }
        let l = line.lowercased()
        let fatal = (l.contains("[error]") && (l.contains("port in use") || l.contains("unable to start")))
            || l.contains("the server will now stop")
            || l.hasSuffix("exiting")
        if fatal {
            state = .crashed
        }
    }
}

/// Vends and retains one InstanceController per server id. Wiring (wine
/// provider, prefix, session-ended) is applied centrally so the views don't
/// have to.
@MainActor
final class ControllerRegistry: ObservableObject {
    private var controllers: [UUID: InstanceController] = [:]

    var wineBinaryProvider: () -> String? = { nil }
    var winePrefixProvider: () -> String = { ServerEnv.defaultPrefix }
    var onSessionEnded: ([String], String) -> Void = { _, _ in }

    /// Supplies the current server list so monitoring can poll every instance
    /// (including ones no view has touched yet).
    var serversProvider: () -> [ServerInstance] = { [] }
    private var monitorTimer: Timer?

    func controller(for instance: ServerInstance) -> InstanceController {
        if let c = controllers[instance.id] { return c }
        let c = InstanceController(instance: instance)
        c.wineBinaryProvider = wineBinaryProvider
        c.winePrefixProvider = winePrefixProvider
        c.onSessionEnded = onSessionEnded
        controllers[instance.id] = c
        return c
    }

    /// Start periodically reconciling every server's state with the OS, so a
    /// server launched from a terminal (or one that exits on its own) is picked
    /// up and shown online/offline automatically. Runs an immediate sweep too.
    func startMonitoring() {
        monitorTimer?.invalidate()
        // First sweep on the next runloop tick so launch isn't blocked by the
        // per-server pgrep calls (auto-detects anything already running).
        Task { @MainActor in self.sweepExternal() }
        let t = Timer(timeInterval: 4, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.sweepExternal() }
        }
        RunLoop.main.add(t, forMode: .common)
        monitorTimer = t
    }

    /// Ensure a controller exists for every server, then reconcile each with the
    /// OS (adopt external runs, clear ones that exited).
    private func sweepExternal() {
        for inst in serversProvider() {
            controller(for: inst).reconcileExternal()
        }
    }

    /// Whether any managed server is currently running.
    var anyRunning: Bool { controllers.values.contains { $0.isRunning } }

    /// The instances of every currently-running server (used for port-clash
    /// checks). Excludes the given id so a server doesn't conflict with itself.
    func runningInstances(excluding id: UUID? = nil) -> [ServerInstance] {
        controllers.values
            .filter { $0.isRunning && $0.id != id }
            .map(\.instance)
    }

    /// Drop a controller when its server is removed (after stopping it).
    func discard(_ id: UUID) {
        controllers[id]?.stop()
        controllers[id] = nil
    }
}
