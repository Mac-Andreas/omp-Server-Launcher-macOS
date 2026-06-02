// Settings pane: a section title + inner top sub-tabs (Privacy / Updates /
// About), each a full settings area on the right. Mirrors the Qawno settings
// design (grouped cards, polished copy).
import SwiftUI
import AppKit

struct SettingsView: View {
    enum Sub: String, CaseIterable, Identifiable {
        case storage = "Storage"
        case privacy = "Privacy"
        case updates = "Updates"
        case about = "About"
        var id: String { rawValue }
    }
    @State private var sub: Sub = .storage

    var body: some View {
        PageScaffold(
            header: {
                // Full-width flush sub-tabs (same style as Server / Setup).
                FlushTabBar(tabs: Sub.allCases.map { ($0, $0.rawValue) }, selection: $sub)
            }
        ) {
            // Updates is a full-page pane; the others scroll.
            Group {
                switch sub {
                case .storage: ScrollView { StoragePane().padding(22) }
                case .privacy: ScrollView { PrivacyPane().padding(22) }
                case .updates: UpdatesPane()
                case .about:   ScrollView { AboutPane().padding(22) }
                }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            sub = .about
        }
    }
}

// MARK: Storage (Wine/Windows-related caches + downloads)

private struct StoragePane: View {
    @EnvironmentObject private var wine: WineManager
    @EnvironmentObject private var snapshots: SnapshotStore
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    @State private var flash: String?
    // Which destructive "delete all servers" confirm popover is open (if any).
    @State private var confirming: ServerPlatform?

    private var macCount: Int { servers.servers(for: .macos).count }
    private var winCount: Int { servers.servers(for: .windows).count }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Storage") {
                Text("Most disk usage here is Windows/Wine-related. The Wine runtime + cached installer used for Windows servers can be re-fetched any time from the Setup tab. App cache (log snapshots + the Wine prefix) is regenerated automatically.")
                    .settingsBody()

                // Cleanup actions — all destructive (free disk space), so red.
                HStack(spacing: 10) {
                    Button("Clear Wine downloads") {
                        wine.removeCachedDownload()
                        flashMsg("Wine downloads cleared")
                    }
                    .buttonStyle(PillButtonStyle(kind: .danger))

                    Button("Uninstall Wine") {
                        wine.uninstall()
                        flashMsg("Wine uninstalled")
                    }
                    .buttonStyle(PillButtonStyle(kind: .danger))
                    .disabled(!wine.isInstalled)
                    .opacity(wine.isInstalled ? 1 : 0.45)

                    Button("Clear app cache") {
                        snapshots.deleteAll()
                        ServerEnv.deletePrefix()
                        flashMsg("App cache cleared")
                    }
                    .buttonStyle(PillButtonStyle(kind: .danger))
                    Spacer(minLength: 0)
                }

                if let f = flash {
                    Label(f, systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good).font(.system(size: 12))
                }
            }

            // Destructive: delete every server of a platform. Each is gated behind
            // a countdown-then-hold confirmation popover.
            SettingsCard(title: "Danger zone") {
                Text("These permanently delete servers — their folders are moved to the Trash. This can’t be undone from here.")
                    .settingsBody()

                HStack(spacing: 10) {
                    deleteAllButton(platform: .macos, label: "Delete all macOS servers",
                                    count: macCount)
                    deleteAllButton(platform: .windows, label: "Delete all Windows servers",
                                    count: winCount)
                    Spacer(minLength: 0)
                }
            }
        }
    }

    private func deleteAllButton(platform: ServerPlatform, label: String, count: Int) -> some View {
        Button("\(label)\(count > 0 ? "  (\(count))" : "")") {
            confirming = platform
        }
        .buttonStyle(PillButtonStyle(kind: .danger))
        .disabled(count == 0)
        .opacity(count == 0 ? 0.45 : 1)
        .popover(isPresented: Binding(
            get: { confirming == platform },
            set: { if !$0 && confirming == platform { confirming = nil } })) {
            DangerConfirmPopover(
                title: "Delete all \(platform.shortLabel) servers?",
                message: "This moves all \(count) \(platform.shortLabel) server folder\(count == 1 ? "" : "s") to the Trash. Running servers are stopped first.",
                countdown: 10,
                holdTitle: "Hold to delete",
                onCancel: { confirming = nil },
                onConfirm: { deleteAll(platform); confirming = nil })
        }
    }

    // Stop + delete (to Trash) every server of a platform.
    private func deleteAll(_ platform: ServerPlatform) {
        for inst in servers.servers(for: platform) {
            registry.discard(inst.id)
            if !inst.isImported {
                try? FileManager.default.trashItem(
                    at: URL(fileURLWithPath: inst.folder), resultingItemURL: nil)
            }
            servers.remove(inst)
        }
        flashMsg("Deleted all \(platform.shortLabel) servers")
    }

    private func flashMsg(_ s: String) {
        flash = s
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { flash = nil }
    }
}

// MARK: Privacy

private struct PrivacyPane: View {
    @EnvironmentObject private var telemetry: Telemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Anonymous usage data", trailing: {
                // Green = telemetry backend reachable, red = not. (No label.)
                Circle()
                    .fill(telemetry.backendReachable == true ? Theme.good
                          : telemetry.backendReachable == false ? Theme.bad
                          : Theme.textDim)
                    .frame(width: 9, height: 9)
            }) {
                Text("Help us prioritise fixes. Nothing identifying you, your servers, or your configs is ever sent. A random per-install ID counts unique users without revealing who they are.")
                    .settingsBody()

                // iOS-style toggle, right-aligned: green = on, red = off.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share anonymous usage data").font(.system(size: 13, weight: .semibold))
                        Text("Toggle anytime; takes effect immediately.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    IOSToggle(isOn: Binding(
                        get: { telemetry.enabled },
                        set: { telemetry.enabled = $0; telemetry.consentAsked = true }
                    ))
                }
            }

        }
        .onAppear { telemetry.checkBackend() }
    }
}

// MARK: Updates

private struct UpdatesPane: View {
    @EnvironmentObject private var updater: Updater

    // Whether an install is in progress (download/unpack/install).
    private var busy: Bool {
        switch updater.phase {
        case .downloading, .unpacking, .installing: return true
        default: return false
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            if busy {
                progress
            } else {
                status
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // Idle status: up-to-date / update-available with actions.
    @ViewBuilder private var status: some View {
        Image(systemName: updater.result.available ? "arrow.down.circle.fill" : "checkmark.circle.fill")
            .font(.system(size: 46))
            .foregroundStyle(updater.result.available ? Theme.accent : Theme.good)
        Text(updater.result.available ? "Update available" : "Up to date")
            .font(.system(size: 20, weight: .bold))
        Text(updater.result.available
             ? "Version \(updater.result.latestVersion) is available — you're on v\(AppInfo.version)."
             : "You're on the latest version (v\(AppInfo.version)).")
            .font(.system(size: 13)).foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center)

        if case .failed(let msg) = updater.phase {
            Text(msg).font(.system(size: 12)).foregroundStyle(Theme.bad)
                .multilineTextAlignment(.center).frame(maxWidth: 360)
        }

        if updater.result.available {
            // Auto-install when the release ships an installable .zip; otherwise
            // fall back to opening the release page in the browser.
            if updater.canAutoInstall {
                Button("Download & install \(updater.result.latestVersion)") {
                    updater.downloadAndInstall()
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
            } else if let url = updater.result.htmlURL {
                Button("Open release \(updater.result.latestVersion)") {
                    NSWorkspace.shared.open(url)
                }
                .buttonStyle(PillButtonStyle(kind: .primary))
            }
        }
        Button("Check for updates") { updater.check() }
            .buttonStyle(PillButtonStyle(kind: .secondary))
            .padding(.top, 4)
    }

    // Active install: a labelled progress bar with % and download speed.
    @ViewBuilder private var progress: some View {
        Image(systemName: "arrow.down.circle.fill")
            .font(.system(size: 46)).foregroundStyle(Theme.accent)
        Text(phaseTitle).font(.system(size: 20, weight: .bold))

        if case .downloading(let p, let speed) = updater.phase {
            VStack(spacing: 6) {
                ProgressView(value: p)
                    .tint(Theme.accent)
                    .frame(width: 320)
                HStack {
                    Text("\(Int(p * 100))%")
                    Spacer()
                    Text(Self.speedText(speed))
                }
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                .frame(width: 320)
            }
        } else {
            ProgressView().controlSize(.small).padding(.top, 4)
        }
        Text("The app will relaunch automatically when the update finishes.")
            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            .multilineTextAlignment(.center).frame(maxWidth: 360)
    }

    private var phaseTitle: String {
        switch updater.phase {
        case .downloading: return "Downloading…"
        case .unpacking:   return "Updating…"
        case .installing:  return "Installing…"
        default:           return ""
        }
    }

    private static func speedText(_ bytesPerSec: Double) -> String {
        guard bytesPerSec > 0 else { return "—" }
        let f = ByteCountFormatter()
        f.countStyle = .file
        return f.string(fromByteCount: Int64(bytesPerSec)) + "/s"
    }
}

// MARK: About

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "About") {
                Text("\(AppInfo.displayName) v\(AppInfo.version)")
                    .font(.system(size: 14, weight: .bold))
                Text("Made by the Mac Andreas Team.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Run and manage open.mp servers on Apple Silicon. macOS servers run natively as arm64 — no Wine, no Docker. Windows (32-bit) servers run through a downloaded Wine runtime. Free software under the GNU GPL v3 or later.")
                    .settingsBody()
                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: { Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(PillButtonStyle(kind: .secondary))
            }

            SettingsCard(title: "Credits") {
                creditRow("open.mp",
                          "open.mp — open multiplayer server",
                          "https://open.mp")
                creditRow("Native macOS server",
                          "Xyranaut · Mac Andreas — omp-server-macos (arm64 build)",
                          "https://github.com/Mac-Andreas/omp-server-macos")
                creditRow("Qawno (macOS)",
                          "Xyranaut · Mac Andreas — Qawno-macOS (native PAWN compiler/editor)",
                          "https://github.com/Mac-Andreas/Qawno-macOS")
                creditRow("Wine runtime",
                          "Gcenx · macOS_Wine_builds (wine-staging, wine32on64)",
                          "https://github.com/Gcenx/macOS_Wine_builds")
                creditRow("Wine",
                          "WineHQ — the Wine project",
                          "https://www.winehq.org")
                Text("Windows-32 servers use Wine with the wine32on64 technique to run 32-bit Windows binaries on Apple Silicon.")
                    .settingsBody()
            }
        }
    }

    private func creditRow(_ title: String, _ detail: String, _ url: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: { Image(systemName: "arrow.up.right.square") }
            .buttonStyle(.plain).foregroundStyle(Color(hex: 0x4C8DFF))
        }
    }
}

// MARK: Shared bits

private struct SettingsCard<Content: View, Trailing: View>: View {
    let title: String
    @ViewBuilder var trailing: () -> Trailing
    @ViewBuilder var content: Content

    init(title: String,
         @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() },
         @ViewBuilder content: () -> Content) {
        self.title = title
        self.trailing = trailing
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(title).font(.system(size: 14, weight: .bold))
                Spacer()
                trailing()
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }
}

private extension Text {
    func settingsBody() -> some View {
        self.font(.system(size: 12))
            .foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Compact top sub-tab pill (used inside Settings).
struct TopTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(selected ? Theme.accent : .clear)
            .foregroundStyle(selected ? .white : Theme.textDim)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}
