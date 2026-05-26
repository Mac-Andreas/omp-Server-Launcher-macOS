// Server control: status indicator + Start / Stop / Restart / Launch tiles +
// embedded live log. Setup warnings (wine, server files) live in Overview.
import SwiftUI
import AppKit

struct ServerView: View {
    @EnvironmentObject private var server: ServerController
    @EnvironmentObject private var telemetry: Telemetry
    @EnvironmentObject private var wine: WineManager

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            statusCard
            controls
            logPanel
        }
        .padding(20)
    }

    private var statusCard: some View {
        Card {
            HStack(spacing: 12) {
                Circle().fill(statusColor).frame(width: 12, height: 12)
                Text(statusText).font(.system(size: 16, weight: .bold))
                Spacer()
            }
        }
    }

    // Start / Stop / Restart / Launch open.mp as four equal full-width tiles.
    // Start green (grey when running), Stop red, Restart orange, Launch purple.
    private var controls: some View {
        HStack(spacing: 12) {
            Button {
                server.start()
                telemetry.send("server_start")
            } label: { Label("Start", systemImage: "play.fill") }
            .buttonStyle(ActionTileStyle(fill: Theme.good))
            .disabled(server.isRunning || !wine.isInstalled || !ServerEnv.filesPresent)

            Button {
                server.stop()
                telemetry.send("server_stop")
            } label: { Label("Stop", systemImage: "stop.fill") }
            .buttonStyle(ActionTileStyle(fill: Theme.bad))
            .disabled(!server.isRunning)

            Button {
                server.restart()
                telemetry.send("server_restart")
            } label: { Label("Restart", systemImage: "arrow.clockwise") }
            .buttonStyle(ActionTileStyle(fill: Theme.warn))
            .disabled(!server.isRunning)

            Button {
                NSWorkspace.shared.open(URL(string: "omp://")!)
                telemetry.send("launch_openmp")
            } label: { Label("Launch", systemImage: "gamecontroller") }
            .buttonStyle(ActionTileStyle(fill: Theme.accent))
            .help("Open the open.mp multiplayer client (if installed).")
        }
    }

    // Live server log embedded below the buttons. Header carries the
    // folder / save / clear actions on the right.
    private var logPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Image(systemName: "terminal").foregroundStyle(Theme.accent)
                Text("Server log").font(.system(size: 13, weight: .semibold))
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: ServerEnv.serverDir))
                } label: { Label("Open server folder", systemImage: "folder") }
                .buttonStyle(PillButtonStyle(kind: .secondary))

                Button("Clear") { server.clearLog() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))

                Button("Save") { saveLog() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                    .disabled(server.logLines.isEmpty)
            }
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(server.logLines.enumerated()), id: \.offset) { idx, line in
                            LogLine(line: line, size: 11).id(idx)
                        }
                    }
                    .padding(10)
                }
                .background(Color(hex: 0x10131A))
                .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
                .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
                .onChange(of: server.logLines.count) { _, count in
                    if count > 0 { proxy.scrollTo(count - 1, anchor: .bottom) }
                }
            }
            .frame(maxHeight: .infinity)
        }
    }

    // Save the current log buffer to a file via the standard save panel.
    private func saveLog() {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "server-log.txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            let text = server.logLines.joined(separator: "\n") + "\n"
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    // Red (not running) / orange (starting/stopping) / green (running).
    private var statusColor: Color {
        switch server.state {
        case .running:             return Theme.good
        case .starting, .stopping: return Theme.warn
        case .stopped:             return Theme.bad
        }
    }
    private var statusText: String {
        switch server.state {
        case .running:  return "Running"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .stopped:  return "Not running"
        }
    }
}
