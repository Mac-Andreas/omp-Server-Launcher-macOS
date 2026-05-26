// First-launch telemetry consent. Shown once (gated on Telemetry.consentAsked).
// The user must actively choose — nothing is enabled or disabled by default,
// and nothing is sent until they pick. Choice is saved.
import SwiftUI

struct ConsentSheet: View {
    /// Called with the user's choice: true = enable telemetry, false = keep off.
    let onChoose: (Bool) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(Theme.accent).font(.system(size: 18))
                Text("Anonymous usage data").font(.system(size: 17, weight: .bold))
            }

            Text("Help us prioritise fixes. Nothing identifying you, your servers, or your configs is ever sent — just a random per-install ID so we can count unique users.\n\nYou can change this any time in Settings → Privacy.")
                .font(.system(size: 13))
                .foregroundStyle(Theme.textDim)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 12) {
                Spacer()
                Button("No thanks") { onChoose(false) }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                Button("Share anonymous data") { onChoose(true) }
                    .buttonStyle(PillButtonStyle(kind: .primary))
            }
        }
        .padding(24)
        .frame(width: 460)
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .focusEffectDisabled()          // no blue focus ring on the buttons
        .interactiveDismissDisabled()   // force an explicit choice
    }
}
