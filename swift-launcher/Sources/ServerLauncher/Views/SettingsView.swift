// Settings pane: a section title + inner top sub-tabs (Privacy / Updates /
// About), each a full settings area on the right. Mirrors the Qawno settings
// design (grouped cards, polished copy).
import SwiftUI
import AppKit

struct SettingsView: View {
    enum Sub: String, CaseIterable, Identifiable {
        case privacy = "Privacy"
        case updates = "Updates"
        case about = "About"
        var id: String { rawValue }
    }
    @State private var sub: Sub = .privacy

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section title + sub-tab pills on top.
            HStack(spacing: 8) {
                ForEach(Sub.allCases) { s in
                    Button(s.rawValue) { sub = s }
                        .buttonStyle(TopTabStyle(selected: sub == s))
                        .focusable(false)
                }
                Spacer()
            }
            .padding(.horizontal, 22)
            .padding(.top, 18)
            .padding(.bottom, 12)

            Divider().overlay(Theme.border)

            ScrollView {
                Group {
                    switch sub {
                    case .privacy: PrivacyPane()
                    case .updates: UpdatesPane()
                    case .about:   AboutPane()
                    }
                }
                .padding(22)
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .showAbout)) { _ in
            sub = .about
        }
    }
}

// MARK: Privacy

private struct PrivacyPane: View {
    @EnvironmentObject private var telemetry: Telemetry

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Anonymous usage data") {
                Text("Help us prioritise fixes. Nothing identifying you, your servers, or your configs is ever sent. A random per-install ID counts unique users without revealing who they are.")
                    .settingsBody()

                // iOS-style toggle, right-aligned: green = on, red = off.
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Share anonymous usage data").font(.system(size: 13, weight: .semibold))
                        Text("Toggle anytime; takes effect immediately.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                    Spacer()
                    IOSToggle(isOn: Binding(
                        get: { telemetry.enabled },
                        set: { telemetry.enabled = $0; telemetry.consentAsked = true }
                    ))
                }
            }
        }
    }
}

// iOS-style pill switch: green track when on, red when off.
private struct IOSToggle: View {
    @Binding var isOn: Bool
    var body: some View {
        Button {
            withAnimation(.easeInOut(duration: 0.15)) { isOn.toggle() }
        } label: {
            ZStack(alignment: isOn ? .trailing : .leading) {
                Capsule().fill(isOn ? Theme.good : Theme.bad)
                    .frame(width: 46, height: 28)
                Circle().fill(.white).frame(width: 22, height: 22).padding(3)
            }
        }
        .buttonStyle(.plain)
        .focusable(false)
    }
}

// MARK: Updates

private struct UpdatesPane: View {
    @EnvironmentObject private var updater: Updater

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "Updates") {
                HStack(alignment: .top) {
                    Text(status).settingsBody()
                    Spacer()
                    HStack(spacing: 10) {
                        if updater.result.available, let url = updater.result.htmlURL {
                            Button("Open release \(updater.result.latestVersion)") {
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(PillButtonStyle(kind: .primary))
                        }
                        // Check now — right-aligned.
                        Button("Check now") { updater.check() }
                            .buttonStyle(PillButtonStyle(kind: .secondary))
                    }
                }
            }
        }
    }
    private var status: String {
        updater.result.available
            ? "Update available: \(updater.result.latestVersion). You're on v\(AppInfo.version)."
            : "You're on the latest version (v\(AppInfo.version))."
    }
}

// MARK: About

private struct AboutPane: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            SettingsCard(title: "About") {
                Text("\(AppInfo.displayName) v\(AppInfo.version)")
                    .font(.system(size: 14, weight: .bold))
                Text("Made by the Mac Andreas Team.")
                    .font(.system(size: 13, weight: .semibold)).foregroundStyle(Theme.text)
                Text("Runs the Windows open.mp server on macOS using a downloaded 32-bit-capable Wine runtime. Free software under the GNU GPL v3 or later.")
                    .settingsBody()
                Button {
                    NSWorkspace.shared.open(AppInfo.repositoryURL)
                } label: { Label("Repository", systemImage: "chevron.left.forwardslash.chevron.right") }
                .buttonStyle(PillButtonStyle(kind: .secondary))
            }

            SettingsCard(title: "Credits") {
                creditRow("Wine runtime",
                          "Gcenx · macOS_Wine_builds (wine-staging, wine32on64)",
                          "https://github.com/Gcenx/macOS_Wine_builds")
                creditRow("Wine",
                          "WineHQ — the Wine project",
                          "https://www.winehq.org")
                creditRow("open.mp",
                          "open.mp — open multiplayer server",
                          "https://open.mp")
                Text("CrossOver / Game Porting Toolkit techniques (wine32on64) make 32-bit Windows binaries runnable on Apple Silicon.")
                    .settingsBody()
            }
        }
    }

    private func creditRow(_ title: String, _ detail: String, _ url: String) -> some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(detail).font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
            Spacer()
            Button {
                if let u = URL(string: url) { NSWorkspace.shared.open(u) }
            } label: { Image(systemName: "arrow.up.right.square") }
            .buttonStyle(.plain).foregroundStyle(Color(hex: 0x4C8DFF))
        }
    }
}

// MARK: Shared bits

private struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title).font(.system(size: 14, weight: .bold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }
}

private extension Text {
    func settingsBody() -> some View {
        self.font(.system(size: 12))
            .foregroundStyle(Theme.textDim)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// Compact top sub-tab pill (used inside Settings).
struct TopTabStyle: ButtonStyle {
    var selected: Bool
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14).padding(.vertical, 6)
            .background(selected ? Theme.accent : .clear)
            .foregroundStyle(selected ? .white : Theme.textDim)
            .clipShape(RoundedRectangle(cornerRadius: 7))
            .contentShape(Rectangle())
    }
}
