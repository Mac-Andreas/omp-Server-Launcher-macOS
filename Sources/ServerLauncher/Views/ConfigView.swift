// config.json editor. OS tabs + a server scope picker (name · version · running
// state, with a dropdown listing each server's version and creation date) and
// Refresh/Save on the right. Paired tiles for name/password, rcon/port and
// gamemode/max-players, then iOS-style on/off toggles for filterscripts and
// plugins. Guardrails: no negatives, scroll-wheel does NOT change number fields,
// port bounded. Shows a "config.json not detected" state instead of empty fields.
import SwiftUI
import AppKit

struct ConfigView: View {
    @EnvironmentObject private var config: ConfigStore
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    @EnvironmentObject private var telemetry: Telemetry
    @State private var saveError: String?
    @State private var savedFlash = false
    @State private var revealRcon = false
    @State private var platform: ServerPlatform = .macos
    // The server actually in scope for the current platform tab (nil ⇒ none).
    @State private var scoped: ServerInstance?
    // True while the scope dropdown is open — used to raise the scope bar above
    // the editor below it so the menu isn't drawn behind the server boxes.
    @State private var pickerOpen = false

    private var scopedServers: [ServerInstance] { servers.servers(for: platform) }

    var body: some View {
        PageScaffold(
            scopeFloating: pickerOpen,
            header: {
                FlushTabBar(tabs: ServerPlatform.allCases.map { ($0, $0.label) },
                            selection: $platform)
            },
            scope: { scopeBar },
            footer: {
                // Open in Finder · Refresh · Save, as one global footer tile.
                PageFooterBar(items: [
                    .init(title: "Open in Finder", icon: "folder",
                          tint: Theme.accent, enabled: scoped != nil) {
                        if let f = scoped?.folder {
                            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: f)])
                        }
                    },
                    .init(title: "Refresh", icon: "arrow.clockwise",
                          tint: Theme.accent, enabled: config.exists) {
                        config.load()
                    },
                    .init(title: "Save", icon: "checkmark",
                          tint: Theme.good, enabled: config.exists && config.isDirty) {
                        saveError = config.save()
                        if saveError == nil {
                            flashSaved(); servers.configChanged()
                            telemetry.recordAction("config_save")
                        }
                    },
                ])
            }
        ) {
            if scoped == nil {
                noServerState
            } else if config.exists {
                ScrollView { editor }
            } else {
                missingState
            }
        }
        .onChange(of: platform) { _, _ in selectScope(scopedServers.first) }
        .onAppear {
            if let sel = servers.selectedExact { platform = sel.platform }
            selectScope(scopedServers.first { $0.id == servers.selectedID } ?? scopedServers.first)
        }
    }

    // Scope band: the server picker (full width), with a save error / "saved"
    // flash on the right. The Finder/Refresh/Save actions live in the footer.
    private var scopeBar: some View {
        HStack(spacing: 16) {
            // The server picker (or an empty-state label).
            Group {
                if scopedServers.isEmpty {
                    Label("No \(platform.shortLabel) servers", systemImage: "server.rack")
                        .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 20).padding(.vertical, 12)
                } else {
                    ConfigScopePicker(
                        servers: scopedServers,
                        selectedID: Binding(get: { scoped?.id },
                                            set: { id in selectScope(scopedServers.first { $0.id == id }) }),
                        running: { inst in registry.controller(for: inst).isRunning },
                        isOpen: $pickerOpen,
                        flush: true)
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)

            // Save error / "saved" flash, right-aligned.
            if let e = saveError {
                Text(e).foregroundStyle(Theme.bad).font(.system(size: 12)).lineLimit(1)
                    .padding(.trailing, 20)
            } else if savedFlash {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good).font(.system(size: 14))
                    .padding(.trailing, 20)
            }
        }
    }

    // Point the config store at the scoped server's folder (or nowhere) and
    // reload — so the editor only ever reflects a server of the current platform.
    private func selectScope(_ inst: ServerInstance?) {
        // No-op if the same server is already in scope, so a stray re-render can't
        // reload config.json and discard in-progress edits (e.g. the port field).
        if inst?.id == scoped?.id && servers.selectedID == inst?.id { return }
        scoped = inst
        servers.selectedID = inst?.id   // drives ServerEnv.serverDir (no fallback)
        config.load()
    }

    private var noServerState: some View {
        VStack(spacing: 12) {
            Image(systemName: "server.rack").font(.system(size: 40)).foregroundStyle(Theme.textDim)
            Text("No server selected").font(.system(size: 15, weight: .semibold))
            Text("Add a server in the Server or Setup tab to edit its config.")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity).padding(40)
    }

    private var missingState: some View {
        VStack(spacing: 12) {
            Image(systemName: "doc.badge.gearshape")
                .font(.system(size: 40)).foregroundStyle(Theme.textDim)
            Text("config.json not detected in the server folder")
                .font(.system(size: 15, weight: .semibold))
            Text(ServerEnv.serverDir)
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Button("Reload") { config.load() }
                .buttonStyle(PillButtonStyle(kind: .secondary))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 16) {
            // Paired tiles, two per row.
            pairRow(
                field("Server name") { InputBox(corner: 5) { TextField("", text: $config.serverName) } },
                field("Server Password") { InputBox(corner: 5) { SecureField("", text: $config.password) } })

            pairRow(
                field("RCON password") {
                    InputBox(corner: 5) {
                        HStack(spacing: 0) {
                            if revealRcon { TextField("", text: $config.rconPassword) }
                            else { SecureField("", text: $config.rconPassword) }
                            Button { revealRcon.toggle() } label: {
                                Image(systemName: revealRcon ? "eye.slash" : "eye")
                                    .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                            }
                            .buttonStyle(.plain).focusable(false).pointerCursor()
                        }
                    }
                },
                field("Port") { InputBox(corner: 5) { NumberBox(value: $config.port, range: 1...65535) } })

            pairRow(
                field("Max players") { InputBox(corner: 5) { NumberBox(value: $config.maxPlayers, range: 2...1000) } },
                field("List server on open.mp") {
                    AnnounceToggle(isOn: $config.announce)
                })

            // Gamemode gets a full-width row (the selector benefits from width).
            Card {
                field("Gamemode") {
                    GamemodeSelector(selection: $config.gamemode, options: config.gamemodeOptions)
                }
            }

            // Filterscripts: an iOS-style toggle per script (red off / green on).
            // The section pill notes these can be (un)loaded live; toggling a
            // script on/off both edits the config AND, if the server is running,
            // sends a loadfs/unloadfs console command immediately.
            toggleSection(
                title: "Filterscripts",
                empty: "No filterscripts found in the server’s filterscripts/ folder.",
                isEmpty: config.filterscripts.isEmpty,
                // The "live load/unload" pill only makes sense while the server is
                // running (that's when toggles send loadfs/unloadfs).
                accessory: isScopedRunning
                    ? AnyView(Pill(text: "live load / unload", color: Theme.good))
                    : nil) {
                ForEach($config.filterscripts) { $fs in
                    ToggleRow(label: fs.name + (fs.missing ? "  (missing)" : ""),
                              isOn: $fs.enabled,
                              disabled: fs.missing,
                              warning: fs.missing
                                ? "“\(fs.name)” is listed in the config but its .amx isn’t in filterscripts/ — compile or add it first."
                                : nil,
                              onToggle: { on in liveFilterscript(fs.name, enabled: on) },
                              // A missing filterscript only exists in the config, so
                              // removing it just drops it from the list (Save persists).
                              onRemove: fs.missing ? { removeFilterscript(fs.name) } : nil,
                              removeHelp: "Remove “\(fs.name)” from the config")
                }
            }

            // Plugins: same iOS-style toggle per discovered plugin. A plugin whose
            // file can't load on this platform (e.g. a .dll/.so under a macOS
            // server) is flagged and its toggle disabled.
            toggleSection(
                title: "Plugins",
                empty: "No plugins found in the server’s plugins/ folder.",
                isEmpty: config.plugins.isEmpty) {
                ForEach($config.plugins) { $plugin in
                    let loads = platform.pluginLoads(plugin.name)
                    ToggleRow(label: plugin.name, isOn: $plugin.enabled,
                              disabled: !loads,
                              warning: loads ? nil
                                : "“\(plugin.name)” is a \(pluginKind(plugin.name)) library, which a \(platform.shortLabel) server can’t load — plugins are native code compiled per-OS. A \(platform.shortLabel) server needs a .\(platform.pluginExtension) build of this plugin.")
                }
            }
        }
        .padding(20)
    }

    // Two labelled fields side by side, each taking half the width.
    private func pairRow<L: View, R: View>(_ left: L, _ right: R) -> some View {
        HStack(alignment: .top, spacing: 16) {
            Card { left }.frame(maxWidth: .infinity)
            Card { right }.frame(maxWidth: .infinity)
        }
    }

    @ViewBuilder
    private func toggleSection<Content: View>(title: String, empty: String, isEmpty: Bool,
                                              accessory: AnyView? = nil,
                                              @ViewBuilder content: () -> Content) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Text(title).font(.system(size: 13, weight: .bold))
                    if let accessory { accessory }
                    Spacer(minLength: 0)
                }
                if isEmpty {
                    Text(empty).font(.system(size: 12)).foregroundStyle(Theme.textDim)
                } else {
                    content()
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // Toggle a filterscript live: if the scoped server is running, send the
    // loadfs/unloadfs console command. (The config edit itself is handled by the
    // ToggleRow's binding; Save persists it.)
    private func liveFilterscript(_ name: String, enabled: Bool) {
        guard let inst = scoped, registry.controller(for: inst).isRunning else { return }
        registry.controller(for: inst).sendCommand("\(enabled ? "loadfs" : "unloadfs") \(name)")
    }

    // Drop a (missing) filterscript from the list. It only lived in the config, so
    // removing the entry is enough; Save then rewrites pawn.side_scripts without it.
    private func removeFilterscript(_ name: String) {
        config.filterscripts.removeAll { $0.name == name }
    }

    // Whether the scoped server is currently running (gates the live-load pill).
    private var isScopedRunning: Bool {
        guard let inst = scoped else { return false }
        return registry.controller(for: inst).isRunning
    }

    private func field<V: View>(_ label: String, @ViewBuilder _ control: () -> V) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(label).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            control()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // Human label for a plugin file's platform, from its extension.
    private func pluginKind(_ name: String) -> String {
        let n = name.lowercased()
        if n.hasSuffix(".dll") { return "Windows (.dll)" }
        if n.hasSuffix(".so") { return "Linux (.so)" }
        if n.hasSuffix(".dylib") { return "macOS (.dylib)" }
        return "non-native"
    }

    private func flashSaved() {
        savedFlash = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { savedFlash = false }
    }
}

// Config server picker: the closed field shows the selected server's name, its
// version pill and a running dot; the open list shows every server of the
// platform with its version + folder creation date/time, so servers that share a
// name are still distinguishable. Fully app-rendered (no native menu).
struct ConfigScopePicker: View {
    let servers: [ServerInstance]
    @Binding var selectedID: UUID?
    let running: (ServerInstance) -> Bool
    @Binding var isOpen: Bool
    /// Flush style: the closed field is a borderless, full-bleed strip (no card
    /// background, no outline) that reads as part of the header — only the
    /// surrounding divider separates it from the content. The open list keeps its
    /// rounded, outlined dropdown look. Used on the Bans/Logs/Config headers.
    var flush: Bool = false
    /// When set, an "All" row is shown at the top of the list and selecting it
    /// sets `selectedID` to nil (no specific server). The closed field then shows
    /// this label. Used by the Snapshots filter ("All servers"). When nil, the
    /// picker always resolves to a concrete server (Config/Bans behaviour).
    var allLabel: String? = nil

    // Flush fields match the Config tab's header strip height (40pt field + the
    // 12pt vertical padding on each side = 64pt) so Bans/Logs read identically.
    private var fieldHeight: CGFloat { flush ? 64 : 40 }
    @State private var hovering = false

    // With an "All" option, nil selection is a real, sticky state (don't fall back
    // to the first server). Without it, nil falls back to the first server.
    private var current: ServerInstance? {
        if allLabel != nil { return servers.first { $0.id == selectedID } }
        return servers.first { $0.id == selectedID } ?? servers.first
    }
    private var showingAll: Bool { allLabel != nil && current == nil }

    var body: some View {
        // Closed: just the field. Open: the open list hangs off the field as a
        // single unified control — one border wraps field + list (a divider, not
        // a second outline, separates them), and the list auto-sizes to content.
        field
            .overlay(alignment: .topLeading) {
                if isOpen { menu.offset(y: fieldHeight).zIndex(100) }
            }
            .animation(.easeOut(duration: 0.12), value: isOpen)
    }

    @ViewBuilder private var field: some View {
        if flush { flushField } else { boxedField }
    }

    // Borderless full-bleed strip: only a hover/open highlight, no outline.
    private var flushField: some View {
        fieldContent
            .frame(maxWidth: .infinity)
            .frame(height: fieldHeight)
            .background((isOpen ? Theme.accent.opacity(0.10)
                         : (hovering ? Theme.cardHi.opacity(0.28) : .clear)))
            .contentShape(Rectangle())
            .pointerCursor()
            .onHover { hovering = $0 }
            .onTapGesture { isOpen.toggle() }
    }

    // Original bordered tile (used on the standalone Config scope bar).
    private var boxedField: some View {
        fieldContent
            .frame(height: fieldHeight)
            .background(Theme.card)
            // Square off the bottom corners while open so the list joins seamlessly.
            .clipShape(UnevenRoundedRectangle(
                topLeadingRadius: Theme.corner, bottomLeadingRadius: isOpen ? 0 : Theme.corner,
                bottomTrailingRadius: isOpen ? 0 : Theme.corner, topTrailingRadius: Theme.corner))
            // When open, the field's bottom edge sits at the same y as the list's top
            // edge (the list is offset by exactly fieldHeight), so the two strokes
            // coincide into a single divider — one continuous outline overall.
            .overlay(UnevenRoundedRectangle(
                topLeadingRadius: Theme.corner, bottomLeadingRadius: isOpen ? 0 : Theme.corner,
                bottomTrailingRadius: isOpen ? 0 : Theme.corner, topTrailingRadius: Theme.corner)
                .stroke(isOpen ? Theme.accent : Theme.border, lineWidth: isOpen ? 1.6 : 1))
            .contentShape(Rectangle())
            .pointerCursor()
            .onTapGesture { isOpen.toggle() }
    }

    // Closed-field layout: <indicator> <name> <version>, left-aligned, with the
    // chevron pushed to the right. The indicator is the running/stopped status
    // dot (no status text). In flush mode the leading server icon is dropped.
    private var fieldContent: some View {
        HStack(spacing: 8) {
            if showingAll, let label = allLabel {
                Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            } else if let s = current {
                // Indicator: status dot to the LEFT of the name.
                Circle().fill(running(s) ? Theme.good : Theme.bad).frame(width: 7, height: 7)
                if !flush {
                    Image(systemName: "server.rack").foregroundStyle(Theme.textDim).font(.system(size: 12))
                }
                Text(s.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                if let v = s.versionTag { Pill(text: "v\(v)", color: Theme.accent) }
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim)
                .rotationEffect(.degrees(isOpen ? 180 : 0))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
    }

    private var menu: some View {
        // Auto-sized list (no fixed row height) that scrolls only past a cap.
        ScrollView {
            VStack(spacing: 0) {
                // Optional "All" row (Snapshots filter): same height as a server
                // row so every row in the list is uniform.
                if let label = allLabel {
                    Button {
                        selectedID = nil; isOpen = false
                    } label: {
                        ScopeAllRow(label: label, selected: current == nil)
                    }
                    .buttonStyle(.plain).pointerCursor()
                }
                ForEach(servers) { s in
                    Button {
                        selectedID = s.id; isOpen = false
                    } label: {
                        row(s)
                    }
                    .buttonStyle(.plain).pointerCursor()
                }
            }
            .padding(flush ? 0 : 4)   // flush: rows go edge-to-edge, side to side
        }
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 320)
        .fixedSize(horizontal: false, vertical: true)   // shrink to content under the cap
        .background(Theme.card)
        // Flush: a full-bleed panel, square edges, only a top + bottom divider so
        // it reads as one continuous strip with the field. Boxed: rounded bottom
        // corners + accent outline that join the field into a single control.
        .clipShape(UnevenRoundedRectangle(
            bottomLeadingRadius: flush ? 0 : Theme.corner,
            bottomTrailingRadius: flush ? 0 : Theme.corner))
        .overlay(alignment: .top) {
            if flush { Divider().overlay(Theme.border) }
        }
        .overlay(alignment: .bottom) {
            if flush { Divider().overlay(Theme.border) }
        }
        .overlay {
            if !flush {
                UnevenRoundedRectangle(bottomLeadingRadius: Theme.corner, bottomTrailingRadius: Theme.corner)
                    .stroke(Theme.accent, lineWidth: 1.6)
            }
        }
        .shadow(color: .black.opacity(flush ? 0.25 : 0.35), radius: flush ? 8 : 12, y: flush ? 6 : 8)
    }

    private func row(_ s: ServerInstance) -> some View {
        ScopeRow(server: s, selected: s.id == current?.id, running: running(s))
    }

    static func created(_ d: Date?) -> String {
        guard let d else { return "created date unknown" }
        let f = DateFormatter()
        f.dateFormat = "dd-MM-yyyy  HH:mm"
        return "created \(f.string(from: d))"
    }
}

// One row in the scope dropdown: a circled tick on the left (filled for the
// selected server), name + created date in the middle, and the version pill +
// running status pushed to the RIGHT. Hover/selected highlight + pointer cursor.
private struct ScopeRow: View {
    let server: ServerInstance
    let selected: Bool
    let running: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Theme.accent : Theme.textDim)
            VStack(alignment: .leading, spacing: 2) {
                Text(server.displayName).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(ConfigScopePicker.created(server.createdAt))
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim).lineLimit(1)
            }
            Spacer(minLength: 8)
            if let v = server.versionTag { Pill(text: "v\(v)", color: Theme.accent) }
            HStack(spacing: 4) {
                Circle().fill(running ? Theme.good : Theme.bad).frame(width: 7, height: 7)
                Text(running ? "running" : "stopped")
                    .font(.system(size: 10)).foregroundStyle(Theme.textDim)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: ScopeRow.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Theme.accent.opacity(0.18)
                    : (selected ? Theme.cardHi.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }

    // Fixed row height so the "All" row and server rows are exactly uniform.
    static let rowHeight: CGFloat = 52
}

// The "All servers" row of the scope dropdown: a circled tick + the label, kept
// at the same height as a ScopeRow so the list rows are all uniform.
private struct ScopeAllRow: View {
    let label: String
    let selected: Bool
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: selected ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 14))
                .foregroundStyle(selected ? Theme.accent : Theme.textDim)
            Text(label).font(.system(size: 13, weight: .semibold)).lineLimit(1)
            Spacer(minLength: 8)
        }
        .padding(.horizontal, 12)
        .frame(height: ScopeRow.rowHeight)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(hovering ? Theme.accent.opacity(0.18)
                    : (selected ? Theme.cardHi.opacity(0.6) : .clear))
        .contentShape(Rectangle())
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
    }
}

// Single-select gamemode list — only one can be selected at a time. Each option
// is a tappable row with a radio dot; the current gamemode is highlighted. The
// "— none —" choice only appears when there are NO gamemodes on disk (once one is
// detected, none is dropped). A gamemode listed in the config but missing from
// gamemodes/ is still shown (flagged) so it isn't silently dropped.
struct GamemodeSelector: View {
    @Binding var selection: String
    let options: [String]

    private var rows: [(value: String, label: String)] {
        var r: [(String, String)] = []
        // Offer "none" only when nothing is available to pick.
        if options.isEmpty { r.append(("", "— none —")) }
        if !selection.isEmpty && !options.contains(selection) {
            r.append((selection, "\(selection)  (missing)"))
        }
        r.append(contentsOf: options.map { ($0, $0) })
        return r
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(rows, id: \.value) { opt in
                Button { selection = opt.value } label: {
                    HStack(spacing: 8) {
                        Image(systemName: opt.value == selection ? "largecircle.fill.circle" : "circle")
                            .font(.system(size: 13))
                            .foregroundStyle(opt.value == selection ? Theme.accent : Theme.textDim)
                        Text(opt.label).font(.system(size: 13))
                            .foregroundStyle(opt.value.isEmpty ? Theme.textDim : Theme.text)
                            .lineLimit(1)
                        Spacer(minLength: 8)
                    }
                    .padding(.horizontal, 10).padding(.vertical, 7)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(opt.value == selection ? Theme.accent.opacity(0.12) : .clear)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain).pointerCursor()
            }
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border, lineWidth: 1))
    }
}

// Yes / No segmented control for the "announce" setting, sized to match the
// Max-players input box beside it (same height, one outer border, no inner box).
// Yes = listed on the open.mp master server list; No = unlisted.
struct AnnounceToggle: View {
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 8) {
            segment(title: "No", on: false, color: Theme.badDark)
            segment(title: "Yes", on: true, color: Theme.goodDark)
        }
        .padding(4)
        .frame(maxWidth: .infinity)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .overlay(RoundedRectangle(cornerRadius: 5).stroke(Theme.border, lineWidth: 1))
    }

    private func segment(title: String, on: Bool, color: Color) -> some View {
        let selected = isOn == on
        return Button { isOn = on } label: {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(selected ? .white : Theme.textDim)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(selected ? color : .clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain).focusable(false).pointerCursor()
    }
}

// A label on the left and an iOS-style red/green switch on the right. Red = off,
// green = on. Used for filterscript + plugin toggles. When `disabled`, the toggle
// is greyed and inert and a warning icon appears whose popover (click or hover)
// explains why.
struct ToggleRow: View {
    let label: String
    @Binding var isOn: Bool
    var disabled: Bool = false
    var warning: String? = nil
    var onToggle: ((Bool) -> Void)? = nil
    /// When set, a "×" button is shown next to the warning to remove the row
    /// (used to drop a missing filterscript that's only listed in the config).
    var onRemove: (() -> Void)? = nil
    var removeHelp: String? = nil
    @State private var showWhy = false
    @State private var hoverWarn = false
    @State private var hoverRemove = false

    var body: some View {
        HStack(spacing: 8) {
            Text(label).font(.system(size: 13))
                .foregroundStyle(disabled ? Theme.textDim : Theme.text).lineLimit(1)
            if let warning {
                Button { showWhy.toggle() } label: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12)).foregroundStyle(Theme.warn)
                        .padding(2)
                        .background(hoverWarn ? Theme.warn.opacity(0.15) : .clear)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).focusable(false)
                .onHover { h in
                    hoverWarn = h
                    showWhy = h        // hover opens; click toggles/pins
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
                .popover(isPresented: $showWhy, arrowEdge: .bottom) {
                    Text(warning)
                        .font(.system(size: 12)).foregroundStyle(Theme.text)
                        .padding(12).frame(width: 280)
                }
            }
            if let onRemove {
                Button { onRemove() } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold)).foregroundStyle(Theme.bad)
                        .padding(3)
                        .background(hoverRemove ? Theme.bad.opacity(0.18) : .clear)
                        .clipShape(Circle())
                        .contentShape(Circle())
                }
                .buttonStyle(.plain).focusable(false)
                .help(removeHelp ?? "Remove from config")
                .onHover { h in
                    hoverRemove = h
                    if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
                }
            }
            Spacer(minLength: 8)
            IOSToggle(isOn: $isOn, onUserToggle: { onToggle?($0) })
                .opacity(disabled ? 0.4 : 1)
                .disabled(disabled)
                .allowsHitTesting(!disabled)
        }
        .padding(.vertical, 3)
    }
}

// Integer text field: digits only (strips '-'/letters). While you're typing the
// field shows exactly what you typed (so editing 7777 → 7778 works normally); the
// bound `value` follows the parsed number, capped at the upper bound. The lower
// bound and any empty field are only enforced on blur/submit, so a number you're
// midway through typing isn't fought. Scroll-wheel-proof (a plain TextField
// doesn't respond to scroll, unlike a Stepper/NSStepper).
struct NumberBox: View {
    @Binding var value: Int
    let range: ClosedRange<Int>
    @State private var text: String = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField("", text: $text)
            .textFieldStyle(.plain)
            .focused($focused)
            .onAppear { text = String(value) }
            // Reflect external value changes ONLY when we're not the one editing.
            .onChange(of: value) { _, new in
                if !focused && text != String(new) { text = String(new) }
            }
            .onChange(of: text) { _, new in
                let digits = new.filter(\.isNumber)
                if digits != new { text = digits; return }   // re-enters with cleaned text
                // Push the parsed value (cap the top only; keep showing what's typed).
                if let n = Int(digits) {
                    let capped = min(n, range.upperBound)
                    if capped != value { value = capped }
                    if capped != n { text = String(capped) }   // only rewrite if we capped
                }
            }
            .onChange(of: focused) { _, isFocused in if !isFocused { commit() } }
            .onSubmit { commit() }
    }

    // Snap to a valid in-range integer when editing ends.
    private func commit() {
        let n = Int(text.filter(\.isNumber)) ?? range.lowerBound
        value = min(max(n, range.lowerBound), range.upperBound)
        text = String(value)
    }
}
