// Top-level layout: left sidebar nav (icon+label rows, Qawno-style) + right
// content pane + footer. Settings has its own inner top sub-tabs.
import SwiftUI
import AppKit

struct ContentView: View {
    enum Section: String, CaseIterable, Identifiable {
        case server = "Server"
        case setup = "Setup"
        case config = "Config"
        case bans = "Bans"
        case logs = "Snapshots"
        case settings = "Settings"
        case license = "License"
        var id: String { rawValue }

        var icon: String {
            switch self {
            case .server:   return "play.circle"
            case .setup:    return "square.grid.2x2"
            case .config:   return "slider.horizontal.3"
            case .bans:     return "nosign"
            case .logs:     return "terminal"
            case .settings: return "gearshape"
            case .license:  return "doc.text"
            }
        }
    }

    @State private var section: Section = .server
    @EnvironmentObject private var telemetry: Telemetry
    @State private var showConsent = false

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
        // First launch: ask for telemetry consent. Nothing is sent until the
        // user chooses; we never default it on or off for them.
        .onAppear { showConsent = !telemetry.consentAsked }
        .sheet(isPresented: $showConsent) {
            ConsentSheet { enable in
                telemetry.enabled = enable
                telemetry.consentAsked = true
                showConsent = false
            }
        }
    }

    // MARK: Sidebar (nav + footer at the bottom)

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 0) {
            SidebarBrand()
            Divider().overlay(Theme.border)
                .padding(.horizontal, 14).padding(.bottom, 8)
            // Nav rows are flush against each other (no gaps) so a selected row
            // reads as one full-bleed block edge-to-edge, like the macOS tab.
            VStack(alignment: .leading, spacing: 0) {
                ForEach(Section.allCases) { s in
                    SidebarRow(section: s, selected: section == s) {
                        section = s
                        telemetry.recordTab(s.rawValue)   // local daily aggregate
                    }
                }
            }
            Spacer()
            SidebarFooter()
        }
        .frame(width: 206)
        .background(Theme.card.opacity(0.4))
    }

    @ViewBuilder private var content: some View {
        switch section {
        case .server:   ServerView()
        case .setup:    SetupView()
        case .config:   ConfigView()
        case .bans:     BansView()
        case .logs:     LogsView()
        case .settings: SettingsView()
        case .license:  LicenseView()
        }
    }
}

// Top-of-sidebar branding: the app icon next to two stacked lines —
// "Open Multiplayer" (bold) over "Server Launcher" (dim). The icon is the app's
// own bundled artwork, falling back to the running app's icon image.
struct SidebarBrand: View {
    private var logo: NSImage? {
        for bundle in [Bundle.main, Bundle.module] {
            if let url = bundle.url(forResource: "icon", withExtension: "png"),
               let img = NSImage(contentsOf: url) { return img }
        }
        return NSApp.applicationIconImage
    }

    var body: some View {
        HStack(spacing: 10) {
            Group {
                if let logo {
                    Image(nsImage: logo).resizable().interpolation(.high)
                } else {
                    Image(systemName: "server.rack").resizable()
                }
            }
            .scaledToFit()
            .frame(width: 34, height: 34)
            .clipShape(RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 1) {
                Text("Open Multiplayer")
                    .font(.system(size: 13, weight: .bold)).foregroundStyle(Theme.text)
                Text("Server Launcher")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16).padding(.bottom, 14)
    }
}

// One sidebar row: a left accent bar marks selection (matching the FlushTab
// strip used on Setup/Server), with hover, select and selected effects. The
// selected/hover background is full-bleed (edge-to-edge, no gaps) like a tab.
struct SidebarRow: View {
    let section: ContentView.Section
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    // Fixed row height so the accent bar reliably spans the whole row.
    private let rowHeight: CGFloat = 46

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                // Left accent bar spanning the full row height when selected.
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(selected ? Theme.accent
                          : (hovering ? Theme.accent.opacity(0.4) : .clear))
                    .frame(width: 3, height: rowHeight)
                Image(systemName: section.icon)
                    .font(.system(size: 17))
                    .frame(width: 22)
                // Reserve the bold width always (hidden bold copy underneath) so
                // toggling weight on selection can't change the row's width.
                Text(section.rawValue)
                    .font(.system(size: 15, weight: selected ? .semibold : .regular))
                    .background(
                        Text(section.rawValue)
                            .font(.system(size: 15, weight: .semibold))
                            .hidden())
                Spacer(minLength: 0)
            }
            .foregroundStyle(selected || hovering ? Theme.text : Theme.textDim)
            .padding(.leading, 11)
            .frame(height: rowHeight)
            .frame(maxWidth: .infinity, alignment: .leading)
            // Selected: the content area's own colour (Theme.bg) with a rounded
            // RIGHT edge, so the tab reads as flush/connected to the pane on the
            // right. Kept fully within the row's bounds (no negative padding) so
            // switching tabs can't jitter the sidebar layout. Hover: faint tint.
            .background {
                if selected {
                    Theme.bg.clipShape(UnevenRoundedRectangle(
                        bottomTrailingRadius: Theme.corner, topTrailingRadius: Theme.corner))
                } else if hovering {
                    Theme.cardHi.opacity(0.28)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable(false)
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}
