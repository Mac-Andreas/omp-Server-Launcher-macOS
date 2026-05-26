// Sidebar footer (bottom of the left bar): divider, credit line, repository
// link, and a dim version at the very bottom. Spaced for breathing room.
import SwiftUI
import AppKit

struct SidebarFooter: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Divider().overlay(Theme.border)
                .padding(.bottom, 4)

            // Single line: "Made with ♥ by Mac Andreas Team" (small, no wrap).
            (
                Text("Made with ")
                + Text(Image(systemName: "heart.fill")).foregroundColor(Theme.accent)
                + Text(" by Mac Andreas Team")
            )
            .font(.system(size: 9.5))
            .foregroundStyle(Theme.textDim)
            .lineLimit(1)
            .minimumScaleFactor(0.8)

            // Repository · version on one line.
            HStack(spacing: 6) {
                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "chevron.left.forwardslash.chevron.right")
                        Text("Repository")
                    }
                    .font(.system(size: 10, weight: .semibold))
                }
                .buttonStyle(.plain)
                .foregroundStyle(Color(hex: 0x4C8DFF))

                Text("·").foregroundStyle(Theme.textDim)
                Text("v\(AppInfo.version)")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }
}
