// Logs tab: a list of saved session snapshots (one per server run, auto-saved
// when the server stops). Each row expands inline to show the log, and can be
// exported to a file or deleted. A "Clear all" button wipes every snapshot.
// The live, in-progress log lives on the Server tab.
import SwiftUI
import AppKit

struct LogsView: View {
    @EnvironmentObject private var snapshots: SnapshotStore
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    @State private var expanded: Set<String> = []
    @State private var showDeleteAll = false
    // Platform tab scope, matching the Server tab.
    @State private var platform: ServerPlatform = .macos
    // Server filter within the platform: nil = all of that platform's snapshots;
    // otherwise the id of the live server whose snapshots to show.
    @State private var filterID: UUID?
    // True while the scope picker's dropdown is open (raises it over the list).
    @State private var pickerOpen = false

    // Live servers of the selected platform (the dropdown's rows — same source as
    // the Bans/Config pickers, so the dropdown is a 1:1 match).
    private var platformServers: [ServerInstance] { servers.servers(for: platform) }
    // The server name the filter resolves to (nil ⇒ "All servers").
    private var filterName: String? {
        platformServers.first { $0.id == filterID }?.displayName
    }

    // Snapshots belonging to the selected platform. A snapshot is matched to a
    // platform by its server name (via the current server list); snapshots whose
    // server no longer exists ("unknown") are shown under every platform so they
    // aren't hidden.
    private func platformOf(_ name: String) -> ServerPlatform? {
        servers.servers.first { $0.displayName == name }?.platform
    }
    private var platformSnapshots: [LogSnapshot] {
        snapshots.snapshots.filter {
            let p = platformOf($0.server)
            return p == nil || p == platform
        }
    }

    private var visibleSnapshots: [LogSnapshot] {
        guard let name = filterName else { return platformSnapshots }
        return platformSnapshots.filter { $0.server == name }
    }

    var body: some View {
        PageScaffold(
            scopeFloating: true,
            scope: { filterBar },
            footer: {
                PageFooterBar(items: [
                    .init(title: "Delete all", icon: "trash", tint: Theme.bad,
                          enabled: !snapshots.snapshots.isEmpty,
                          action: { showDeleteAll = true }),
                ])
                .popover(isPresented: $showDeleteAll) { deleteAllConfirm }
            }
        ) {
            if snapshots.snapshots.isEmpty {
                empty
            } else if visibleSnapshots.isEmpty {
                emptyFilter
            } else {
                list
            }
        }
        // Reset the per-server filter when switching platform tabs.
        .onChange(of: platform) { _, _ in filterID = nil }
    }

    // Platform tabs + the SAME server-scope picker used on the Bans/Config tabs
    // (1:1) — with an extra "All servers" row at the top. Selecting "All" clears
    // the filter; selecting a server filters to its snapshots.
    private var filterBar: some View {
        VStack(spacing: 0) {
            FlushTabBar(
                tabs: ServerPlatform.allCases.map { ($0, $0.label) },
                selection: $platform)
            ConfigScopePicker(
                servers: platformServers,
                selectedID: $filterID,
                running: { inst in registry.controller(for: inst).isRunning },
                isOpen: $pickerOpen,
                flush: true,
                allLabel: "All servers")
            .frame(maxWidth: .infinity)
            .zIndex(100)   // float the open menu over the snapshot list below
        }
    }

    private var deleteAllConfirm: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Delete all snapshots?").font(.system(size: 13, weight: .bold))
            Text("This permanently removes every saved session log. This can’t be undone.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            HStack {
                Spacer()
                Button("Cancel") { showDeleteAll = false }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Delete all") {
                    snapshots.deleteAll(); expanded.removeAll(); showDeleteAll = false
                }
                .buttonStyle(PillButtonStyle(kind: .danger))
            }
        }
        .padding(16).frame(width: 300)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Theme.textDim)
            Text("No snapshots yet.").font(.system(size: 14, weight: .semibold))
            Text("A snapshot is saved automatically each time the server stops.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var emptyFilter: some View {
        VStack(spacing: 8) {
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Theme.textDim)
            Text("No snapshots for this server.").font(.system(size: 14, weight: .semibold))
            Button("Show all servers") { filterID = nil }
                .buttonStyle(PillButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(visibleSnapshots) { snap in
                    SnapshotRow(
                        snap: snap,
                        isExpanded: expanded.contains(snap.id),
                        toggle: {
                            if expanded.contains(snap.id) { expanded.remove(snap.id) }
                            else { expanded.insert(snap.id) }
                        },
                        lines: { snapshots.content(of: snap) },
                        onSave: { exportSnapshot(snap) },
                        onDelete: { expanded.remove(snap.id); snapshots.delete(snap) }
                    )
                }
            }
            .padding(18)
        }
    }

    private func exportSnapshot(_ snap: LogSnapshot) {
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "server-log-\(Self.fileStamp(snap.created)).txt"
        panel.canCreateDirectories = true
        if panel.runModal() == .OK, let url = panel.url {
            try? FileManager.default.copyItem(at: snap.url, to: url)
        }
    }

    static func fileStamp(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd_HH-mm"
        return f.string(from: d)
    }
}

private struct SnapshotRow: View {
    let snap: LogSnapshot
    let isExpanded: Bool
    let toggle: () -> Void
    let lines: () -> [String]
    let onSave: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 8) {
                        Text(snap.server.isEmpty ? "Unknown server" : snap.server)
                            .font(.system(size: 13, weight: .semibold))
                            .lineLimit(1)
                        Text(Self.title(snap.created))
                            .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                    }
                    Text("\(snap.lineCount) lines").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button("View") { toggle() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Save") { onSave() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                HoldToConfirmIcon(help: "Press and hold to delete this snapshot.") { onDelete() }
            }
            .contentShape(Rectangle())
            .pointerCursor()   // whole row is clickable to expand/collapse
            .onTapGesture { toggle() }

            if isExpanded {
                Divider().overlay(Theme.border).padding(.top, 10)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(Array(lines().enumerated()), id: \.offset) { _, line in
                            LogLine(line: line, size: 11)
                        }
                    }
                    .padding(10)
                }
                .frame(maxHeight: 320)
                .background(Color(hex: 0x10131A))
                .clipShape(RoundedRectangle(cornerRadius: 7))
                .padding(.top, 8)
            }
        }
        .padding(14)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }

    // Right-aligned dd-mm-yyyy + time, per the original TODO intent.
    static func title(_ d: Date) -> String {
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy  HH:mm"
        return f.string(from: d)
    }
}
