// Logs tab: a list of saved session snapshots (one per server run, auto-saved
// when the server stops). Each row expands inline to show the log, and can be
// exported to a file or deleted. A "Clear all" button wipes every snapshot.
// The live, in-progress log lives on the Server tab.
import SwiftUI
import AppKit

struct LogsView: View {
    @EnvironmentObject private var snapshots: SnapshotStore
    @State private var expanded: Set<String> = []

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(Theme.border)
            if snapshots.snapshots.isEmpty {
                empty
            } else {
                list
            }
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "clock.arrow.circlepath").foregroundStyle(Theme.accent)
            Text("Session snapshots").font(.system(size: 15, weight: .bold))
            Spacer()
            Button("Reload") { snapshots.reload() }
                .buttonStyle(PillButtonStyle(kind: .secondary))
            Button("Clear all") { snapshots.deleteAll(); expanded.removeAll() }
                .buttonStyle(PillButtonStyle(kind: .danger))
                .disabled(snapshots.snapshots.isEmpty)
        }
        .padding(.horizontal, 18).padding(.vertical, 12)
    }

    private var empty: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "tray").font(.system(size: 36)).foregroundStyle(Theme.textDim)
            Text("No snapshots yet.").foregroundStyle(Theme.textDim)
            Text("A snapshot is saved automatically each time the server stops.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var list: some View {
        ScrollView {
            LazyVStack(spacing: 10) {
                ForEach(snapshots.snapshots) { snap in
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
                    Text(Self.title(snap.created)).font(.system(size: 13, weight: .semibold))
                    Text("\(snap.lineCount) lines").font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }
                Spacer()
                Button("View") { toggle() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Save") { onSave() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button(role: .destructive) { onDelete() } label: { Image(systemName: "trash") }
                    .buttonStyle(.plain).foregroundStyle(Theme.bad)
            }
            .contentShape(Rectangle())
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
