// Top-level layout: left sidebar nav (icon+label rows, Qawno-style) + right
// content pane + footer. Settings has its own inner top sub-tabs.
import SwiftUI
import AppKit

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case overview = "Overview"
        case server = "Server"
        case config = "Config"
        case bans = "Bans"
        case logs = "Logs"
        case settings = "Settings"
        case license = "License"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .overview: return "square.grid.2x2"
            case .server:   return "play.circle"
            case .config:   return "slider.horizontal.3"
            case .bans:     return "nosign"
            case .logs:     return "terminal"
            case .settings: return "gearshape"
            case .license:  return "doc.text"
            }
        }
    }

    @State private var section: Section = .overview

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider().overlay(Theme.border)
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .foregroundStyle(Theme.text)
        .focusEffectDisabled()
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            section = .settings
        }
    }

    // MARK: Sidebar (nav + footer at the bottom)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 4) {
            ForEach(Section.allCases) { s in
                SidebarRow(section: s, selected: section == s) { section = s }
            }
            Spacer()
            SidebarFooter()
        }
        .padding(.top, 14)
        .frame(width: 198)
        .background(Theme.card.opacity(0.4))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .overview: OverviewView()
        case .server:   ServerView()
        case .config:   ConfigView()
        case .bans:     BansView()
        case .logs:     LogsView()
        case .settings: SettingsView()
        case .license:  LicenseView()
        }
    }
}

// One sidebar row: icon + label, accent when selected.
struct SidebarRow: View {
    let section: ContentView.Section
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 11) {
                Image(systemName: section.icon)
                    .font(.system(size: 14))
                    .frame(width: 18)
                Text(section.rawValue)
                    .font(.system(size: 13, weight: .semibold))
                Spacer()
            }
            .foregroundStyle(selected ? Theme.accent : Theme.textDim)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(selected ? Theme.accent.opacity(0.14) : .clear)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .padding(.horizontal, 8)
    }
}
