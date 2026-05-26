// open.mp-styled dark palette, matching the original Qt app's stylesheet.
import SwiftUI

enum Theme {
    static let bg        = Color(hex: 0x20242C)
    static let card      = Color(hex: 0x171A20)
    static let cardHi    = Color(hex: 0x262B34)
    static let border    = Color(hex: 0x333A45)
    static let accent    = Color(hex: 0x7B5CFF)   // purple
    static let text      = Color(hex: 0xE6E9EE)
    static let textDim   = Color(hex: 0x9AA1AD)
    static let good      = Color(hex: 0x3FB950)   // green
    static let bad       = Color(hex: 0xE5534B)   // red
    static let warn      = Color(hex: 0xE0922F)   // orange
    static let disabled  = Color(hex: 0x3A4250)   // grey (inactive button)

    static let corner: CGFloat = 9
}

extension Color {
    init(hex: UInt32) {
        self.init(
            .sRGB,
            red:   Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue:  Double(hex & 0xFF) / 255,
            opacity: 1
        )
    }
}

// A rounded card container used across tabs.
struct Card<Content: View>: View {
    @ViewBuilder var content: Content
    var body: some View {
        content
            .padding(16)
            .background(Theme.card)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(Theme.border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
    }
}

// Big colored action tile — explicit fill, greys out when disabled. Used for
// the Start / Stop / Restart row.
struct ActionTileStyle: ButtonStyle {
    var fill: Color
    @Environment(\.isEnabled) private var isEnabled

    func makeBody(configuration: Configuration) -> some View {
        let bg = isEnabled ? fill : Theme.disabled
        return configuration.label
            .font(.system(size: 14, weight: .bold))
            .lineLimit(1)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(isEnabled ? .white : Theme.textDim)
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
    }
}

// Primary / secondary pill buttons.
struct PillButtonStyle: ButtonStyle {
    var kind: Kind = .secondary
    enum Kind { case primary, secondary, danger }

    func makeBody(configuration: Configuration) -> some View {
        let (bg, fg): (Color, Color) = {
            switch kind {
            case .primary: return (Theme.accent, .white)
            case .secondary: return (Theme.card, Theme.text)
            case .danger: return (Theme.bad, .white)
            }
        }()
        return configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 16).padding(.vertical, 9)
            .background(bg.opacity(configuration.isPressed ? 0.8 : 1))
            .foregroundStyle(fg)
            .overlay(
                RoundedRectangle(cornerRadius: Theme.corner)
                    .stroke(kind == .secondary ? Theme.border : .clear, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
            .contentShape(Rectangle())
    }
}
