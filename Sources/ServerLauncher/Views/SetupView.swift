// Setup: runtime readiness per platform. Adding/downloading servers lives in
// the Server tab now — Setup is purely about the runtimes.
//
//  • macOS    — native arm64 omp-server; nothing to install.
//  • Windows  — manages the 32-bit Wine runtime + prefix needed for
//               omp-server.exe.
import SwiftUI
import AppKit

struct SetupView: View {
    @EnvironmentObject private var wine: WineManager
    @State private var tab: ServerPlatform = .macos

    var body: some View {
        PageScaffold(
            header: {
                FlushTabBar(tabs: ServerPlatform.allCases.map { ($0, $0.label) },
                            selection: $tab)
            }
        ) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    switch tab {
                    case .macos:   MacOSSetup()
                    case .windows: WindowsSetup()
                    }
                }
                .padding(22)
            }
        }
        .onAppear { wine.refresh() }
    }
}

// MARK: macOS (native) tab

private struct MacOSSetup: View {
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry

    var body: some View {
        StatusCard(
            title: "Native macOS runtime",
            subtitle: "Runs the native arm64 omp-server.",
            indicator: indicator
        ) {
            // Dotted (orange) box: macOS servers need plugin extensions in
            // components/, with a button to open that folder.
            HStack(alignment: .center, spacing: 14) {
                Image(systemName: "puzzlepiece.extension")
                    .font(.system(size: 18)).foregroundStyle(Theme.warn)
                VStack(alignment: .leading, spacing: 3) {
                    Text("macOS servers need native plugin extensions (.dylib) in their components/ folder.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Bundled components are already inside each installed server.")
                        .font(.system(size: 10)).foregroundStyle(Theme.textDim)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Button {
                    if let folder = firstMacFolder {
                        NSWorkspace.shared.open(URL(fileURLWithPath: "\(folder)/components"))
                    }
                } label: {
                    Label("Open components", systemImage: "folder")
                        .font(.system(size: 12, weight: .semibold))
                        .fixedSize()
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 12).padding(.vertical, 7)
                .background(Theme.warn.opacity(firstMacFolder == nil ? 0.08 : 0.18))
                .foregroundStyle(firstMacFolder == nil ? Theme.textDim : Theme.warn)
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .disabled(firstMacFolder == nil)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(style: StrokeStyle(lineWidth: 1.4, dash: [5, 4]))
                    .foregroundStyle(Theme.warn.opacity(0.7))
            )
        }
    }

    private var macServers: [ServerInstance] { servers.servers(for: .macos) }
    private var runningCount: Int {
        macServers.filter { registry.controller(for: $0).isRunning }.count
    }

    private var indicator: StatusIndicator {
        if macServers.isEmpty {
            return .init(color: Theme.textDim, text: "No servers yet",
                         detail: "Install or import a macOS server from the Server tab.")
        }
        if runningCount > 0 {
            return .init(color: Theme.good,
                         text: "Running \(runningCount) server\(runningCount == 1 ? "" : "s")",
                         detail: "The native macOS runtime is in use.")
        }
        return .init(color: Theme.warn, text: "Idle",
                     detail: "\(macServers.count) macOS server\(macServers.count == 1 ? "" : "s") installed, none running.")
    }

    private var firstMacFolder: String? { macServers.first?.folder }
}

// MARK: Windows (Wine) tab

private struct WindowsSetup: View {
    @EnvironmentObject private var wine: WineManager

    var body: some View {
        wineCard
        prefixCard
    }

    private var wineCard: some View {
        StatusCard(
            title: "Wine runtime",
            subtitle: "32-bit Wine (\(WineManager.wineVersion)) to run the Windows omp-server.exe.",
            indicator: wineIndicator,
            inlineAction: true
        ) {
            // One right-aligned control reflecting the state: "Download and
            // Install" → progress → "Uninstall" (or a Retry on failure).
            switch wine.state {
            case .notInstalled, .downloaded:
                Button("Download and Install") { wine.downloadAndInstall() }
                    .buttonStyle(PillButtonStyle(kind: .success))

            case .downloading(let p):
                HStack(spacing: 8) {
                    ProgressView(value: p).tint(Theme.accent).frame(width: 140)
                    Text("\(Int(p * 100))%").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }

            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing…").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }

            case .installed:
                Button("Uninstall") { wine.uninstall() }
                    .buttonStyle(PillButtonStyle(kind: .danger))

            case .failed:
                Button("Retry") { wine.refresh(); wine.downloadAndInstall() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }

    private var wineIndicator: StatusIndicator {
        switch wine.state {
        case .installed:
            return .init(color: Theme.good, text: "Installed",
                         detail: "The Wine runtime is installed and ready to run Windows servers.")
        case .downloading:
            return .init(color: Theme.warn, text: "Downloading…",
                         detail: "Fetching the Wine runtime.")
        case .installing:
            return .init(color: Theme.warn, text: "Installing…",
                         detail: "Extracting the Wine runtime.")
        case .downloaded:
            return .init(color: Theme.warn, text: "Downloaded, not installed",
                         detail: "The archive is cached — click Download and Install to finish.")
        case .failed(let msg):
            return .init(color: Theme.bad, text: "Error", detail: msg)
        case .notInstalled:
            return .init(color: Theme.bad, text: "Not installed",
                         detail: "Windows servers can’t run until the Wine runtime is installed.")
        }
    }

    private var prefixCard: some View {
        StatusCard(
            title: "Wine prefix",
            subtitle: "The bottle the Windows server runs in. Created automatically on first start.",
            indicator: ServerEnv.prefixExists
                ? .init(color: Theme.good, text: "Created",
                        detail: "The Wine prefix exists and is ready.")
                : .init(color: Theme.warn, text: "Not yet",
                        detail: "It’s created automatically the first time you start a Windows server."),
            inlineAction: true
        ) {
            // Only show an action when there's something to do (reset).
            if ServerEnv.prefixExists {
                Button("Reset prefix") { ServerEnv.deletePrefix() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
        }
    }
}

// MARK: Shared card primitives (used across Setup + other views)

// `text` is the short hover label describing the state. `detail` (optional) adds
// a second line in the hover popover.
struct StatusIndicator { var color: Color; var text: String; var detail: String? = nil }

struct StatusCard<Content: View>: View {
    let title: String
    let subtitle: String
    let indicator: StatusIndicator
    /// When true, the action content sits right-aligned on the title row instead
    /// of spanning the full width beneath it (used for the simple button cards).
    var inlineAction: Bool = false
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center, spacing: 12) {
                // Left status dot: hover reveals what state we're in (and why).
                StatusDotHover(indicator: indicator)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(size: 14, weight: .bold))
                    Text(subtitle)
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                        .lineLimit(2).truncationMode(.middle)
                }
                if inlineAction {
                    Spacer(minLength: 12)
                    content
                }
            }
            // Full-width content (dotted boxes, progress, multi-button rows).
            if !inlineAction { content }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }
}

// A colored status dot whose hover popover explains the state (matches the
// server-row status dots). Red = not installed, orange = issue/working, green =
// ready/running, grey = neutral.
private struct StatusDotHover: View {
    let indicator: StatusIndicator
    @State private var hovering = false

    var body: some View {
        Circle().fill(indicator.color).frame(width: 11, height: 11)
            .overlay(Circle().stroke(indicator.color.opacity(0.35), lineWidth: 4))
            .onHover { hovering = $0 }
            .popover(isPresented: $hovering, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(indicator.text)
                        .font(.system(size: 12, weight: .bold)).foregroundStyle(indicator.color)
                    if let d = indicator.detail {
                        Text(d).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                }
                .padding(10).frame(width: 240)
            }
    }
}
