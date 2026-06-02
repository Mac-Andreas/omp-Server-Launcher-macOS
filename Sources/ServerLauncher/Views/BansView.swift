// Read-only-ish bans list with remove. Reads bans.json (array of
// {address, player, reason, time}). Layout mirrors the Server tab: platform
// tabs at the top, a config-style server dropdown below, and a flush "Reload
// bans" bar pinned to the bottom (matching the Server tab's Import bar).
import SwiftUI

struct BansView: View {
    @EnvironmentObject private var bans: BansStore
    @EnvironmentObject private var servers: ServersStore
    @State private var platform: ServerPlatform = .macos
    @State private var scoped: ServerInstance?

    var body: some View {
        PageScaffold(
            scopeFloating: true,
            scope: {
                // Platform tabs + server selector at the top (no page title).
                ServerScopeHeader(platform: $platform) { selectScope($0) }
            },
            footer: {
                // Reload the ban list.
                PageFooterBar(items: [
                    .init(title: "Reload ban list", icon: "arrow.clockwise",
                          tint: Theme.accent, action: { bans.load() }),
                ])
            }
        ) {
            if scoped == nil {
                VStack(spacing: 8) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36)).foregroundStyle(Theme.textDim)
                    Text("No \(platform.shortLabel) servers")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Add a \(platform.shortLabel) server to manage its bans.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if bans.bans.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36)).foregroundStyle(Theme.textDim)
                    Text("No bans.")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Banned players from this server will appear here.")
                        .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(bans.bans) { ban in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(ban.player.isEmpty ? ban.address : ban.player)
                                    .font(.system(size: 13, weight: .semibold))
                                Text("\(ban.address) · \(ban.reason)")
                                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            }
                            Spacer()
                            Text(ban.time).font(.system(size: 11)).foregroundStyle(Theme.textDim)
                            HoldToConfirmIcon(help: "Press and hold to remove this ban.") {
                                _ = bans.removeBan(ban)
                            }
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }

    private func selectScope(_ inst: ServerInstance?) {
        scoped = inst
        servers.selectedID = inst?.id   // drives ServerEnv.serverDir (no fallback)
        bans.load()
    }
}
