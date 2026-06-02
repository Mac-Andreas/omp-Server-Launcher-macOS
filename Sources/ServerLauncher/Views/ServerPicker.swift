// Compact header that lets Config/Bans choose which configured server they
// operate on. Hidden when there are fewer than two servers (nothing to pick).
import SwiftUI

struct ServerPicker: View {
    @EnvironmentObject private var servers: ServersStore

    var body: some View {
        if servers.servers.count > 1 {
            HStack(spacing: 8) {
                Image(systemName: "server.rack").foregroundStyle(Theme.textDim)
                Text("Editing").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                Picker("", selection: Binding(
                    get: { servers.selectedID ?? servers.servers.first?.id },
                    set: { servers.selectedID = $0 }
                )) {
                    ForEach(servers.servers) { s in
                        Text("\(s.name)  —  \(s.platform.label)").tag(Optional(s.id))
                    }
                }
                .labelsHidden()
                .frame(maxWidth: 320)
                Spacer()
            }
            .padding(.horizontal, 20).padding(.top, 16)
        }
    }
}

/// Server selector shaped as `<icon> <server name> <dropdown>`. Unlike
/// `ServerPicker` it always shows (even with a single server), and has no
/// "Editing" label. The picker is the server name itself.
struct ServerScopePicker: View {
    @EnvironmentObject private var servers: ServersStore

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "server.rack").foregroundStyle(Theme.textDim)
            Picker("", selection: Binding(
                get: { servers.selectedID ?? servers.servers.first?.id },
                set: { servers.selectedID = $0 }
            )) {
                ForEach(servers.servers) { s in
                    Text("\(s.displayName)  —  \(s.platform.label)").tag(Optional(s.id))
                }
            }
            .labelsHidden()
            .frame(maxWidth: 320)
            .disabled(servers.servers.count < 2)
            Spacer()
        }
    }
}

/// Shared header for the Config / Bans / Logs tabs: the same macOS / Windows-32
/// platform tab strip as the Server tab, plus a full-width app-rendered picker
/// to choose which server of that platform is in scope. The picker matches the
/// Config tab's rich field — `<indicator> <name> <version pill> <status> <chevron>`
/// — and the open list shows each server's version + creation date. The scoped
/// server (or nil when the platform has none) is reported through `onSelect`,
/// so a macOS server never leaks into the Windows-32 tab.
struct ServerScopeHeader: View {
    @Binding var platform: ServerPlatform
    let onSelect: (ServerInstance?) -> Void
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    // The chosen server within the current platform; nil ⇒ first of the platform.
    @State private var chosenID: UUID?
    // True while the picker's dropdown is open — raises it above content below.
    @State private var pickerOpen = false

    private var scoped: [ServerInstance] { servers.servers(for: platform) }
    private var current: ServerInstance? {
        scoped.first { $0.id == chosenID } ?? scoped.first
    }

    var body: some View {
        VStack(spacing: 0) {
            FlushTabBar(
                tabs: ServerPlatform.allCases.map { ($0, $0.label) },
                selection: $platform)

            if scoped.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "server.rack").foregroundStyle(Theme.textDim)
                    Text("No \(platform.shortLabel) servers")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                    Spacer()
                }
                .padding(.horizontal, 20).padding(.vertical, 12)
            } else {
                ConfigScopePicker(
                    servers: scoped,
                    selectedID: Binding(
                        get: { current?.id },
                        set: { chosenID = $0; report() }),
                    running: { inst in registry.controller(for: inst).isRunning },
                    isOpen: $pickerOpen,
                    flush: true)
                .frame(maxWidth: .infinity)
            }
        }
        .zIndex(pickerOpen ? 100 : 0)   // float the open menu over content below
        .onChange(of: platform) { _, _ in chosenID = scoped.first?.id; report() }
        .onAppear { chosenID = scoped.first?.id; report() }
    }

    // Tell the caller which server is in scope (nil when the platform is empty).
    private func report() { onSelect(current) }
}
