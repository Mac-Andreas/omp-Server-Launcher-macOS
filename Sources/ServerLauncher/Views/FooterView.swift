// Sidebar footer (bottom of the left bar): divider, credit line, repository
// link, and a dim version at the very bottom. Spaced for breathing room.
import SwiftUI
import AppKit

struct SidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.border)
                .padding(.bottom, 4)

            // "Made with ♥ by Mac Andreas" (small, no wrap).
            (
                Text("Made with ")
                + Text(Image(systemName: "heart.fill")).foregroundColor(Theme.accent)
                + Text(" by Mac Andreas")
            )
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            // Version on the LEFT, Repository link on the RIGHT.
            HStack(spacing: 6) {
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
                // Show a BETA pill when the version string is a pre-release.
                if AppInfo.version.lowercased().contains("beta") {
                    Pill(text: "Beta", color: Theme.warn)
                }
                Spacer()
                RepositoryLink()
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}

// Repository link with a pointing-hand cursor and a hover/press highlight.
private struct RepositoryLink: View {
    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button {
            NSWorkspace.shared.open(AppInfo.repositoryURL)
        } label: {
            HStack(spacing: 4) {
                Image(systemName: "chevron.left.forwardslash.chevron.right")
                Text("Repository")
            }
            .font(.system(size: 10, weight: .semibold))
            .foregroundStyle(Color(hex: 0x4C8DFF).opacity(pressing ? 0.6 : 1))
            .brightness(hovering ? 0.12 : 0)
            .padding(.horizontal, 6).padding(.vertical, 3)
            .background(Color(hex: 0x4C8DFF).opacity(hovering ? 0.12 : 0))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in pressing = true }
                .onEnded { _ in pressing = false }
        )
    }
}
