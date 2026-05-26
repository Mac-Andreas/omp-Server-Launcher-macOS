// Read-only-ish bans list with remove. Reads bans.json (array of
// {address, player, reason, time}).
import SwiftUI

struct BansView: View {
    @EnvironmentObject private var bans: BansStore

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Bans").font(.system(size: 16, weight: .bold))
                Spacer()
                Button("Reload") { bans.load() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            }
            .padding(20)

            if bans.bans.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.shield")
                        .font(.system(size: 36)).foregroundStyle(Theme.textDim)
                    Text(bans.exists ? "No bans." : "bans.json not found.")
                        .foregroundStyle(Theme.textDim)
                }
                Spacer()
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
                            Button(role: .destructive) {
                                _ = bans.removeBan(ban)
                            } label: { Image(systemName: "trash") }
                            .buttonStyle(.plain)
                            .foregroundStyle(Theme.bad)
                        }
                        .listRowBackground(Theme.card)
                    }
                }
                .scrollContentBackground(.hidden)
            }
        }
    }
}
