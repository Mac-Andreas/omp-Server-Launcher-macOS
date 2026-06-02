// Server tab: pick a platform (macOS / Windows-32 via Wine) with a full-width
// flush tab strip, add/import servers, and run each one independently with its
// own live log. Each platform keeps its own expand/collapse state.
import SwiftUI
import AppKit

struct ServerView: View {
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    @EnvironmentObject private var releases: ReleasesStore
    @EnvironmentObject private var telemetry: Telemetry

    @State private var platform: ServerPlatform = .macos
    @State private var showAddSheet = false

    @State private var importError: String?
    // Server-row actions are presented here (not inside the row) so their modal
    // backdrop covers the whole content pane instead of just one card.
    @State private var pendingEdit: ServerInstance?
    @State private var pendingDelete: ServerInstance?

    var body: some View {
        PageScaffold(
            header: {
                // Tabs sit at the very top (no "Servers" title above them).
                FlushTabBar(tabs: ServerPlatform.allCases.map { ($0, $0.label) },
                            selection: $platform)
            },
            footer: {
                // Install + Import side by side, pinned to the bottom (shown in
                // both the empty and populated states).
                PageFooterBar(items: [
                    .init(title: "Install a \(platform.shortLabel) server",
                          icon: "plus.circle.fill", tint: Theme.good,
                          action: { telemetry.recordAction("install_open"); showAddSheet = true }),
                    .init(title: "Import a \(platform.shortLabel) server",
                          icon: "square.and.arrow.down", tint: Theme.accent,
                          action: { telemetry.recordAction("import"); importServer() }),
                ])
            }
        ) {
            let list = servers.servers(for: platform)
            if list.isEmpty {
                emptyState
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(list) { inst in
                            ServerRow(instance: inst,
                                      onEdit: { pendingEdit = inst },
                                      onDelete: { pendingDelete = inst })
                                .environmentObject(registry.controller(for: inst))
                        }
                    }
                    .padding(20)
                }
            }
        }
        .onAppear { releases.loadIfNeeded() }
        .animation(.easeInOut(duration: 0.15), value: showAddSheet)
        .animation(.easeInOut(duration: 0.15), value: pendingEdit)
        .animation(.easeInOut(duration: 0.15), value: pendingDelete)
        .appModal(isPresented: $showAddSheet) {
            AddServerSheet(platform: platform) { showAddSheet = false }
        }
        .appModal(isPresented: Binding(get: { pendingEdit != nil },
                                       set: { if !$0 { pendingEdit = nil } })) {
            if let inst = pendingEdit {
                EditServerSheet(instance: inst) { pendingEdit = nil }
            }
        }
        .appModal(isPresented: Binding(get: { pendingDelete != nil },
                                       set: { if !$0 { pendingDelete = nil } })) {
            if let inst = pendingDelete {
                DeleteServerSheet(instance: inst) { pendingDelete = nil }
                    .environmentObject(registry.controller(for: inst))
            }
        }
        .alert("Couldn’t import that server",
               isPresented: Binding(get: { importError != nil },
                                    set: { if !$0 { importError = nil } })) {
            Button("OK", role: .cancel) { importError = nil }
        } message: {
            Text(importError ?? "")
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "server.rack").font(.system(size: 30)).foregroundStyle(Theme.textDim)
            Text("No \(platform.label) servers yet").font(.system(size: 14, weight: .semibold))
            Text("Install an official build, or import an existing \(platform.binaryName).")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                .multilineTextAlignment(.center).frame(maxWidth: 440)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(20)
    }

    // Import a server FOLDER for the current platform tab. The folder is scanned
    // for the server binary, whose file format tells us the real OS; if it
    // doesn't match the tab (e.g. a Linux or Windows server under the macOS tab)
    // we refuse with an explanatory popup instead of importing the wrong thing.
    private func importServer() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Select your \(platform.shortLabel) server folder (the one containing \(platform.binaryName))."
        panel.prompt = "Import"
        guard panel.runModal() == .OK, let url = panel.url else { return }

        let scan = ServerDetect.scanImportFolder(url.path)
        guard let binaryPath = scan.binaryPath else {
            importError = "No open.mp server was found in that folder. Pick the folder that directly contains \(platform.binaryName)."
            return
        }

        // What OS does the binary actually target, and does it match this tab?
        let want: ServerDetect.BinaryOS = (platform == .macos) ? .macos : .windows
        if scan.os != want {
            importError = mismatchMessage(found: scan.os)
            return
        }

        if servers.add(path: binaryPath, platform: platform, imported: true) == nil {
            importError = "That server is already in the launcher."
        }
    }

    // Friendly explanation when the imported binary's OS doesn't match the tab.
    private func mismatchMessage(found: ServerDetect.BinaryOS) -> String {
        let support = "Server Manager only supports macOS and Windows-32 (via Wine) servers."
        switch found {
        case .linux:
            return "That looks like a Linux server. \(support)"
        case .windows:
            return "That's a Windows server — import it from the “Windows-32 (via Wine)” tab instead. \(support)"
        case .macos:
            return "That's a macOS server — import it from the “macOS” tab instead. \(support)"
        case .unknown:
            return "Couldn't recognise that \(platform.binaryName) as a \(platform.shortLabel) server binary. \(support)"
        }
    }
}

// A full-bleed, borderless bar that reads as one big clickable button: the whole
// width is the hit target, with hover/press highlight and a tinted icon+label.
struct FlushBarButton: View {
    let title: String
    let icon: String
    var tint: Color = Theme.accent
    let action: () -> Void
    @State private var hovering = false
    @State private var pressing = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: icon).font(.system(size: 14))
                Text(title).font(.system(size: 13, weight: .bold))
            }
            .foregroundStyle(tint)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(tint.opacity(pressing ? 0.22 : (hovering ? 0.12 : 0)))
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

// MARK: Add-server sheet (version + name + Install)

private struct AddServerSheet: View {
    let platform: ServerPlatform
    let onClose: () -> Void
    @EnvironmentObject private var releases: ReleasesStore
    @EnvironmentObject private var servers: ServersStore

    @State private var selectedTag: String = ""
    @State private var name: String = ""
    @State private var rcon: String = ""
    @State private var revealRcon = false
    @State private var showNameHelp = false
    @State private var showRconHelp = false
    @State private var working = false
    @State private var error: String?
    // Set once the user clicks Install while a required field is invalid, so we
    // highlight the offending field(s) with an orange border.
    @State private var validated = false

    private static let defaultRcon = "changeme"

    // Default server name, tagged with the platform so several servers are easy
    // to tell apart. Pre-filled and editable.
    private var defaultName: String {
        switch platform {
        case .macos:   return "open.mp server [MacOS]"
        case .windows: return "open.mp server [Win32-Wine]"
        }
    }

    private var rconIsDefault: Bool {
        rcon.trimmingCharacters(in: .whitespaces).lowercased() == Self.defaultRcon
    }
    private var rconInvalid: Bool {
        rcon.trimmingCharacters(in: .whitespaces).isEmpty || rconIsDefault
    }
    // RCON is required and must differ from the public default. Name is optional
    // here — empty falls back to the build's default name.
    private var canInstall: Bool {
        !working && !selectedTag.isEmpty && !rconInvalid
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Install a \(platform.label) server").font(.system(size: 16, weight: .bold))

            // 1. Server name — placeholder shows the build's default (not filled).
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("Server name", help: $showNameHelp, helpView: nameHelp)
                InputBox {
                    TextField(defaultName, text: $name)
                        .onSubmit(submitInstall)   // Enter installs when valid
                }
            }

            // 2. RCON password — required; plain text with an eye toggle INSIDE
            //    the field (trailing). No example placeholder.
            VStack(alignment: .leading, spacing: 6) {
                fieldLabel("RCON password", help: $showRconHelp, helpView: rconHelp)
                InputBox(invalid: validated && rconInvalid) {
                    HStack(spacing: 0) {
                        Group {
                            if revealRcon {
                                TextField("", text: $rcon)
                            } else {
                                SecureField("", text: $rcon)
                            }
                        }
                        .onSubmit(submitInstall)   // Enter from RCON installs
                        .textCursor()              // I-beam, like the name field
                        Button { revealRcon.toggle() } label: {
                            Image(systemName: revealRcon ? "eye.slash" : "eye")
                                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        }
                        .buttonStyle(.plain).focusable(false)
                        .pointerCursor()
                        .help(revealRcon ? "Hide password" : "Show password")
                    }
                }
                if rconIsDefault {
                    Label("Change it from the default “\(Self.defaultRcon)” — that default is public and insecure.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.warn)
                } else if validated && rconInvalid {
                    Label("Set an RCON password before installing.",
                          systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11)).foregroundStyle(Theme.warn)
                }
            }

            // 3. Version — app-rendered dropdown, full-width, semver only.
            let builds = releases.builds(for: platform)
            VStack(alignment: .leading, spacing: 6) {
                Text("Version").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                AppDropdown(
                    selection: $selectedTag,
                    options: builds.map { ($0.tag, $0.version + ($0.isPrerelease ? "  (beta)" : "")) },
                    dropUp: true)
            }

            if let error {
                Text(error).font(.system(size: 12)).foregroundStyle(Theme.bad)
            }

            // Cancel (red) + Install (green) — equal size, with icons. Install
            // greys out when invalid; clicking it then flags the bad field.
            HStack(spacing: 10) {
                SheetActionButton(title: "Cancel", icon: "xmark",
                                  fill: Theme.badDark, enabled: !working) { onClose() }
                SheetActionButton(title: "Install", icon: "arrow.down.circle.fill",
                                  fill: Theme.goodDark, enabled: canInstall,
                                  working: working) {
                    if canInstall { install() } else { validated = true }
                }
            }
        }
        .padding(22)
        .frame(width: 460)
        .background(Theme.bg)
        .onAppear {
            releases.loadIfNeeded()
            if selectedTag.isEmpty { selectedTag = releases.builds(for: platform).first?.tag ?? "" }
            // Pre-fill the platform-tagged default name so it's editable.
            if name.isEmpty { name = defaultName }
        }
    }

    // A field label with a trailing (?) that opens an in-app explainer popover.
    @ViewBuilder private func fieldLabel(_ title: String, help: Binding<Bool>,
                                         helpView: some View) -> some View {
        HStack(spacing: 6) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
            HelpButton(isPresented: help, helpView: helpView)
        }
    }

    private var nameHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server name").font(.system(size: 13, weight: .bold))
            Text("This is your name for the server. It’s pre-filled with a default (“\(defaultName)”) you can change. It’s saved into the server’s config.json and shown as the server’s name on the Open Multiplayer launcher / server list.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .padding(14).frame(width: 300)
    }

    // In-app explainer for RCON (rendered by the app, not an OS dialog).
    private var rconHelp: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Remote CONsole (RCON) Password").font(.system(size: 13, weight: .bold))
            Text("""
                RCON lets you administer the server remotely — from the in-game \
                console (using /rcon login <password>) or external admin tools — \
                running commands like kick, ban, changemode and reading server \
                status.
                """)
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            Text("open.mp ships with the default password “changeme”. You must change it to something private before installing — anyone who knows the password can fully control your server.")
                .font(.system(size: 11)).foregroundStyle(Theme.textDim)
        }
        .padding(14).frame(width: 320)
    }

    // Enter/Return from a field installs when everything's valid; otherwise it
    // flags the offending field (same as clicking the greyed Install button).
    private func submitInstall() {
        if canInstall { install() } else { validated = true }
    }

    private func install() {
        guard let build = releases.builds(for: platform).first(where: { $0.tag == selectedTag })
        else { error = "Pick a version."; return }
        working = true
        error = nil
        let trimmedName = name.trimmingCharacters(in: .whitespaces)
        InstallFlow.run(build: build,
                        name: trimmedName.isEmpty ? defaultName : trimmedName,
                        rconPassword: rcon,
                        releases: releases, servers: servers) { err in
            working = false
            if let err { error = err } else { onClose() }
        }
    }
}

// MARK: Edit server (name + RCON) — writes to config.json

private struct EditServerSheet: View {
    let instance: ServerInstance
    let onClose: () -> Void
    @EnvironmentObject private var servers: ServersStore

    @State private var name = ""
    @State private var serverPassword = ""
    @State private var rcon = ""
    @State private var port = 7777
    @State private var announce = false
    @State private var revealServerPw = false
    @State private var revealRcon = false

    private var nameInvalid: Bool { name.trimmingCharacters(in: .whitespaces).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Edit server").font(.system(size: 16, weight: .bold))

            VStack(alignment: .leading, spacing: 6) {
                Text("Server name").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                InputBox(invalid: nameInvalid) { TextField("open.mp server", text: $name) }
            }

            // Server password — leaving it blank keeps the server unlocked; setting
            // one locks it (players must enter it to join).
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("Server password").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                    Text(serverPassword.trimmingCharacters(in: .whitespaces).isEmpty ? "— unlocked" : "— locked")
                        .font(.system(size: 11))
                        .foregroundStyle(serverPassword.trimmingCharacters(in: .whitespaces).isEmpty ? Theme.good : Theme.warn)
                }
                InputBox {
                    HStack(spacing: 0) {
                        if revealServerPw { TextField("Leave blank to keep the server open", text: $serverPassword) }
                        else { SecureField("Leave blank to keep the server open", text: $serverPassword) }
                        Button { revealServerPw.toggle() } label: {
                            Image(systemName: revealServerPw ? "eye.slash" : "eye")
                                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        }
                        .buttonStyle(.plain).focusable(false).pointerCursor()
                    }
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("RCON password").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                InputBox {
                    HStack(spacing: 0) {
                        if revealRcon { TextField("", text: $rcon) }
                        else { SecureField("", text: $rcon) }
                        Button { revealRcon.toggle() } label: {
                            Image(systemName: revealRcon ? "eye.slash" : "eye")
                                .font(.system(size: 13)).foregroundStyle(Theme.textDim)
                        }
                        .buttonStyle(.plain).focusable(false).pointerCursor()
                    }
                }
            }

            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Port").font(.system(size: 12, weight: .semibold)).foregroundStyle(Theme.textDim)
                    InputBox { NumberBox(value: $port, range: 1...65535) }
                }
                .frame(width: 160)
                VStack(alignment: .leading, spacing: 6) {
                    Text("List server on open.mp").font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.textDim)
                    AnnounceToggle(isOn: $announce)
                }
                .frame(maxWidth: .infinity)
            }

            HStack(spacing: 10) {
                SheetActionButton(title: "Cancel", icon: "xmark", fill: Theme.badDark) { onClose() }
                SheetActionButton(title: "Save", icon: "checkmark", fill: Theme.goodDark,
                                  enabled: !nameInvalid) { if !nameInvalid { save() } }
            }
        }
        .padding(22).frame(width: 460).background(Theme.bg)
        .onAppear {
            name = instance.displayName
            serverPassword = ConfigJSON.value(forNested: ["password"], at: instance.configPath) ?? ""
            rcon = ConfigJSON.value(forNested: ["rcon", "password"], at: instance.configPath) ?? ""
            port = ConfigJSON.intValue(forNested: ["network", "port"], at: instance.configPath) ?? 7777
            announce = ConfigJSON.boolValue(forNested: ["announce"], at: instance.configPath) ?? false
        }
    }

    private func save() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { servers.rename(instance, to: trimmed) }  // writes config.json name
        ConfigJSON.setRconPassword(rcon, at: instance.configPath)
        ConfigJSON.update(at: instance.configPath) { obj in
            obj["password"] = serverPassword
            obj["announce"] = announce
            var net = (obj["network"] as? [String: Any]) ?? [:]
            net["port"] = port
            obj["network"] = net
        }
        servers.configChanged()
        onClose()
    }
}

// MARK: Delete server (press-and-hold confirm) — moves the folder to Trash

private struct DeleteServerSheet: View {
    let instance: ServerInstance
    let onClose: () -> Void
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("\(instance.isImported ? "Remove" : "Delete") “\(instance.displayName)”?")
                .font(.system(size: 16, weight: .bold))
            Text(instance.isImported
                 ? "This removes the server from the launcher only — your files are NOT deleted and stay in:"
                 : "This moves the entire server folder to the Trash:")
                .font(.system(size: 12)).foregroundStyle(Theme.textDim)
            Text(instance.folder)
                .font(.system(size: 11, design: .monospaced)).foregroundStyle(Theme.textDim)
                .lineLimit(3).truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(10).background(Theme.card).clipShape(RoundedRectangle(cornerRadius: 7))

            HStack(spacing: 10) {
                SheetActionButton(title: "Cancel", icon: "xmark", fill: Theme.cardHi) { onClose() }
                HoldToConfirmButton(
                    seconds: 2.5,
                    title: instance.isImported ? "Hold to remove" : "Hold to delete",
                    icon: instance.isImported ? "xmark" : "trash",
                    doneText: instance.isImported ? "Removing…" : "Deleting…") {
                    instance.isImported ? removeFromLauncher() : deleteToTrash()
                    onClose()
                }
            }
        }
        .padding(24).frame(width: 460).background(Theme.bg)
    }

    private func deleteToTrash() {
        registry.discard(instance.id)
        // Move the server folder to Trash (recoverable), then drop it from the list.
        try? FileManager.default.trashItem(
            at: URL(fileURLWithPath: instance.folder), resultingItemURL: nil)
        servers.remove(instance)
    }

    // Imported servers: only unlink from the launcher; leave all files on disk.
    private func removeFromLauncher() {
        registry.discard(instance.id)
        servers.remove(instance)
    }
}

// MARK: Install helper (download if needed → extract → auto-add)

enum InstallFlow {
    /// Unique install dir: Documents/omp-server-manager/omp-server-<plat>-<ver>/<name-or-server>-<id>
    /// The trailing short id guarantees several servers (even with the same
    /// name) get distinct folders, so none get blocked as duplicate paths.
    static func defaultDir(for build: ReleaseBuild, name: String?) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("omp-server-manager", isDirectory: true)
            .appendingPathComponent("omp-server-\(build.platform.rawValue)-\(build.version)", isDirectory: true)
        let leafName = (name?.isEmpty == false ? name! : "server")
        let safe = leafName.replacingOccurrences(of: "/", with: "-")
        let shortID = String(UUID().uuidString.prefix(8)).lowercased()
        return base.appendingPathComponent("\(safe)-\(shortID)", isDirectory: true)
    }

    @MainActor
    static func isInstalled(_ build: ReleaseBuild, in servers: ServersStore) -> Bool {
        let token = "omp-server-\(build.platform.rawValue)-\(build.version)"
        return servers.servers(for: build.platform).contains { $0.folder.contains(token) }
    }

    /// Download (if not cached) then extract + register. No folder picker.
    @MainActor
    static func run(build: ReleaseBuild, name: String?, rconPassword: String? = nil,
                    releases: ReleasesStore, servers: ServersStore,
                    completion: ((String?) -> Void)? = nil) {
        func extractAndAdd() {
            do {
                let dir = defaultDir(for: build, name: name)
                let bin = try releases.install(build, into: dir)
                servers.add(path: bin, platform: build.platform, name: name, rconPassword: rconPassword)
                // macOS servers ship only the native binary + components. Overlay
                // the platform-independent scaffolding (gamemodes/, the Qawno PAWN
                // include stdlib, config templates, …) from the matching-version
                // Windows zip, then install a NATIVE Qawno (the Windows qawno.exe
                // can't run on macOS). Both run in the background, best-effort.
                if build.platform == .macos {
                    let folder = (bin as NSString).deletingLastPathComponent
                    let version = build.version
                    Task.detached {
                        await releases.overlayWindowsScaffolding(forMacVersion: version, into: folder)
                        try? await QawnoInstaller.install(into: folder)
                    }
                }
                completion?(nil)
            } catch {
                completion?(error.localizedDescription)
            }
        }
        if releases.isDownloaded(build) {
            extractAndAdd()
        } else {
            releases.download(build)
            // Poll for the cached archive, then install.
            pollThenInstall(build: build, releases: releases, extractAndAdd: extractAndAdd, tries: 0)
        }
    }

    @MainActor
    private static func pollThenInstall(build: ReleaseBuild, releases: ReleasesStore,
                                        extractAndAdd: @escaping () -> Void, tries: Int) {
        if releases.isDownloaded(build) { extractAndAdd(); return }
        if releases.downloading[build.id] == nil && tries > 2 {
            // download finished or failed; one more check then give up
            if releases.isDownloaded(build) { extractAndAdd() }
            return
        }
        if tries > 600 { return }  // ~5 min cap
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pollThenInstall(build: build, releases: releases, extractAndAdd: extractAndAdd, tries: tries + 1)
        }
    }
}

// MARK: In-place update + revert

// Updates a server's ENGINE in place — the omp-server binary and the components/
// folder only — leaving config.json, scripts, plugins, bans etc. untouched. The
// files being replaced are first copied into a hidden ".omp-backup/" inside the
// server folder so the change can be reverted. The backup persists until the next
// update (which overwrites it).
enum UpdateFlow {
    static let backupDirName = ".omp-backup"

    /// Whether a revertable backup exists for this server.
    static func hasBackup(_ folder: String) -> Bool {
        FileManager.default.fileExists(atPath: (folder as NSString).appendingPathComponent(backupDirName))
    }

    /// The engine pieces we replace/back up: the binary and components/.
    private static func enginePieces(for inst: ServerInstance) -> [String] {
        [(inst.binaryPath as NSString).lastPathComponent, "components"]
    }

    /// Download (if needed) the latest build for the server's platform, back up
    /// the current engine, then copy the new binary + components/ over it.
    @MainActor
    static func run(for inst: ServerInstance, releases: ReleasesStore,
                    completion: @escaping (String?) -> Void) {
        guard let latest = releases.builds(for: inst.platform)
            .first(where: { !$0.isPrerelease }) ?? releases.builds(for: inst.platform).first
        else { completion("No release information available."); return }

        func extractAndSwap() {
            do {
                // Extract the new build into a throwaway temp dir.
                let tmp = URL(fileURLWithPath: NSTemporaryDirectory())
                    .appendingPathComponent("omp-update-\(UUID().uuidString)", isDirectory: true)
                _ = try releases.install(latest, into: tmp)
                defer { try? FileManager.default.removeItem(at: tmp) }
                try swapEngine(for: inst, from: tmp)
                completion(nil)
            } catch {
                completion(error.localizedDescription)
            }
        }
        if releases.isDownloaded(latest) {
            extractAndSwap()
        } else {
            releases.download(latest)
            pollThenSwap(build: latest, releases: releases, run: extractAndSwap, tries: 0)
        }
    }

    @MainActor
    private static func pollThenSwap(build: ReleaseBuild, releases: ReleasesStore,
                                     run: @escaping () -> Void, tries: Int) {
        if releases.isDownloaded(build) { run(); return }
        if tries > 600 { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            pollThenSwap(build: build, releases: releases, run: run, tries: tries + 1)
        }
    }

    /// Back up the current engine pieces, then copy the new ones over.
    private static func swapEngine(for inst: ServerInstance, from newRoot: URL) throws {
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: inst.folder)
        let backup = folder.appendingPathComponent(backupDirName, isDirectory: true)

        // Fresh backup of the pieces we're about to replace.
        try? fm.removeItem(at: backup)
        try fm.createDirectory(at: backup, withIntermediateDirectories: true)
        for piece in enginePieces(for: inst) {
            let src = folder.appendingPathComponent(piece)
            guard fm.fileExists(atPath: src.path) else { continue }
            try fm.copyItem(at: src, to: backup.appendingPathComponent(piece))
        }

        // Copy the new pieces over (the new binary may have a different file name
        // only if the platform's binaryName changed — it doesn't, so names match).
        for piece in enginePieces(for: inst) {
            let src = newRoot.appendingPathComponent(piece)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = folder.appendingPathComponent(piece)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        if inst.platform == .macos {
            _ = Shell.run("/bin/chmod", ["+x", inst.binaryPath], timeout: 10)
        }
    }

    /// Restore the backed-up engine and delete the backup.
    static func revert(_ inst: ServerInstance) throws {
        let fm = FileManager.default
        let folder = URL(fileURLWithPath: inst.folder)
        let backup = folder.appendingPathComponent(backupDirName, isDirectory: true)
        guard fm.fileExists(atPath: backup.path) else { return }
        for piece in enginePieces(for: inst) {
            let src = backup.appendingPathComponent(piece)
            guard fm.fileExists(atPath: src.path) else { continue }
            let dst = folder.appendingPathComponent(piece)
            try? fm.removeItem(at: dst)
            try fm.copyItem(at: src, to: dst)
        }
        try? fm.removeItem(at: backup)
        if inst.platform == .macos {
            _ = Shell.run("/bin/chmod", ["+x", inst.binaryPath], timeout: 10)
        }
    }
}

// MARK: One server row (pills + collapse/expand controls + log)

private struct ServerRow: View {
    let instance: ServerInstance
    let onEdit: () -> Void
    let onDelete: () -> Void
    @EnvironmentObject private var controller: InstanceController
    @EnvironmentObject private var servers: ServersStore
    @EnvironmentObject private var registry: ControllerRegistry
    @EnvironmentObject private var releases: ReleasesStore
    @EnvironmentObject private var wine: WineManager
    @EnvironmentObject private var telemetry: Telemetry

    @State private var hoverStatus = false
    @State private var showLogs = false
    @State private var updating = false
    @State private var updateError: String?
    // Recomputed when an update/revert finishes; drives the "↩ updated" badge.
    @State private var hasBackup = false

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 0) {
                topLine
                if showLogs {
                    Divider().overlay(Theme.border).padding(.top, 12)
                    logSection.padding(.top, 10)
                }
            }
        }
        .onAppear { hasBackup = UpdateFlow.hasBackup(instance.folder) }
    }

    // "↩ updated" badge shown after an in-place update — tap to revert to the
    // previous engine. Stays until the next update.
    private var revertBadge: some View {
        Button { doRevert() } label: {
            HStack(spacing: 5) {
                Image(systemName: "arrow.uturn.backward").font(.system(size: 10, weight: .bold))
                Text("updated").font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(Theme.good)
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Theme.good.opacity(0.18)).clipShape(Capsule())
        }
        .buttonStyle(.plain).focusable(false).pointerCursor()
        .help("Revert to the previous version")
    }

    private func runUpdate() {
        guard !controller.isRunning else {
            updateError = "Stop the server before updating."; return
        }
        let target = releases.latestVersion(for: instance.platform)
        updating = true; updateError = nil
        UpdateFlow.run(for: instance, releases: releases) { err in
            updating = false
            updateError = err
            hasBackup = UpdateFlow.hasBackup(instance.folder)
            if err == nil {
                servers.setInstalledVersion(target, for: instance)   // reflect new version
                telemetry.recordAction("server_updated")
            }
        }
    }

    private func doRevert() {
        guard !controller.isRunning else {
            updateError = "Stop the server before reverting."; return
        }
        do {
            try UpdateFlow.revert(instance)
            hasBackup = false
            servers.setInstalledVersion(nil, for: instance)   // back to original version
        } catch {
            updateError = error.localizedDescription
        }
    }

    // Inline per-server log: the live session buffer for this controller, newest
    // at the bottom, in a dark scrolling pane (matches the Logs tab styling).
    private var logSection: some View {
        Group {
            if controller.logLines.isEmpty {
                Text(controller.isRunning ? "Waiting for output…"
                     : "No log yet — start the server to see output here.")
                    .font(.system(size: 12)).foregroundStyle(Theme.textDim)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 6)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 1) {
                            ForEach(Array(controller.logLines.enumerated()), id: \.offset) { i, line in
                                LogLine(line: line, size: 11).id(i)
                            }
                        }
                        .padding(10)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .frame(maxHeight: 260)
                    .background(Color(hex: 0x10131A))
                    .clipShape(RoundedRectangle(cornerRadius: 7))
                    .onChange(of: controller.logLines.count) { _, c in
                        withAnimation { proxy.scrollTo(c - 1, anchor: .bottom) }
                    }
                }
            }
        }
    }

    // Two-line layout.
    // Line 1: [● status] name [edit]            <spacer>  Restart? · Start · Reveal
    // Line 2: [version] [up-to-date/update]      <spacer>  Delete · Logs
    private var topLine: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                statusDot
                Text(instance.displayName).font(.system(size: 15, weight: .bold)).lineLimit(1)
                // Lock state as a bare icon right after the name (green open =
                // unlocked, orange closed = locked). Hover explains it.
                lockIcon
                if instance.exists {
                    Button { onEdit() } label: {
                        Image(systemName: "square.and.pencil").font(.system(size: 15))
                            .foregroundStyle(Theme.textDim)
                    }
                    .buttonStyle(.plain).focusable(false).pointerCursor().help("Edit name & RCON password")
                }
                Spacer(minLength: 12)
                primaryActions
            }
            HStack(spacing: 8) {
                versionLine
                Spacer(minLength: 12)
                secondaryActions
            }
        }
    }

    // Line-2 left side: version pill + update status (or the imported badge).
    @ViewBuilder private var versionLine: some View {
        if let v = instance.versionTag {
            Pill(text: "v\(v)", color: Theme.accent, big: true)
            if updating {
                HStack(spacing: 5) {
                    ProgressView().controlSize(.small)
                    Text("updating…").font(.system(size: 11, weight: .bold))
                }
                .foregroundStyle(Theme.warn)
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Theme.warn.opacity(0.18)).clipShape(Capsule())
            } else if hasBackup {
                revertBadge
            } else {
                UpdatePill(installed: v,
                           latest: releases.latestVersion(for: instance.platform),
                           big: true,
                           onUpdate: { runUpdate() })
            }
            if let e = updateError {
                Text(e).font(.system(size: 11)).foregroundStyle(Theme.bad).lineLimit(1)
            }
        }
        if instance.isImported {
            Pill(text: "imported", color: Theme.warn, big: true)
        }
        // The port pill stays on line 2; lock state moved up next to the name.
        if let p = serverPort {
            LabeledPill(icon: "network", text: "Port \(p)", color: Theme.accent)
        }
    }

    // Bare lock icon next to the server name: orange closed = locked (has a
    // server password), green open = unlocked. Hover popover explains it.
    private var lockIcon: some View {
        Image(systemName: serverLocked ? "lock.fill" : "lock.open.fill")
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(serverLocked ? Theme.warn : Theme.good)
            .help(serverLocked
                  ? "Locked — players need the server password to join."
                  : "Unlocked — anyone can join.")
    }

    private var deleteTooltip: String {
        if controller.isRunning {
            return "The server is running — deletion isn’t possible. Stop the server first, then delete."
        }
        return instance.isImported
            ? "Remove from the launcher (keeps your files)"
            : "Delete this server (moves its folder to the Trash)"
    }

    // A non-empty "password" key means the server is locked (join requires it).
    private var serverLocked: Bool {
        !(ConfigJSON.value(forNested: ["password"], at: instance.configPath) ?? "")
            .trimmingCharacters(in: .whitespaces).isEmpty
    }
    private var serverPort: Int? {
        ConfigJSON.intValue(forNested: ["network", "port"], at: instance.configPath)
    }

    // Colored status dot: hovering reveals a popover describing the state.
    // Crash also adds a "check logs" hint.
    private var statusDot: some View {
        Circle().fill(statusColor).frame(width: 10, height: 10)
            .onHover { hoverStatus = $0 }
            .popover(isPresented: $hoverStatus, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(statusText).font(.system(size: 12, weight: .bold)).foregroundStyle(statusColor)
                    if controller.state == .crashed {
                        Text("The server crashed — check the Logs tab for more info.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    } else if controller.isExternal {
                        Text("This server was started outside the app (terminal or another tool). It’s being tracked here — output is tailed from log.txt and you can stop it.")
                            .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    }
                }
                .padding(10).frame(width: 220)
            }
    }

    // Compact Start/Stop — or "Remove" when the server's files are gone.
    @ViewBuilder private var startStopButton: some View {
        if !instance.exists {
            Button { registry.discard(instance.id); servers.remove(instance) } label: {
                Label("Remove", systemImage: "xmark")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.badDark)).help("Remove this server from the list")
        } else if controller.isRunning {
            Button { controller.stop(); telemetry.recordAction("server_stop") } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.badDark)).help("Stop the server")
        } else if instance.platform == .windows && !wine.isInstalled {
            // Wine missing is its own block — keep the simple greyed Start.
            Button {} label: { Label("Start", systemImage: "play.fill") }
                .buttonStyle(MiniButtonStyle(fill: Theme.goodDark))
                .disabled(true)
                .help("Install the Wine runtime from the Setup tab first.")
        } else {
            // Pre-flight: gamemode set, RCON not default, no port clash with a
            // running server. Any problem → greyed Start with a (?) that explains.
            let problems = ServerReadiness.problems(
                for: instance,
                runningPorts: registry.runningInstances(excluding: instance.id).map {
                    ($0.displayName, ConfigJSON.intValue(forNested: ["network", "port"], at: $0.configPath) ?? -1)
                })
            if problems.isEmpty {
                Button { controller.start(); telemetry.recordAction("server_start") } label: {
                    Label("Start", systemImage: "play.fill")
                }
                .buttonStyle(MiniButtonStyle(fill: Theme.goodDark)).help("Start the server")
            } else {
                BlockedStartButton(problems: problems)
            }
        }
    }

    // Line-1 right side: [CPU/RAM usage] · Restart (greyed until running) · Start/Stop.
    private var primaryActions: some View {
        HStack(spacing: 8) {
            if let u = controller.usage {
                UsageBox(usage: u)
            }
            Button { controller.restart(); telemetry.recordAction("server_restart") } label: {
                Label("Restart", systemImage: "arrow.clockwise")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.warnDark))
            .disabled(!controller.isRunning)
            .help(controller.isRunning ? "Restart the server" : "Start the server first")

            startStopButton
        }
        .fixedSize()
    }

    // Line-2 right side: Delete/Remove · Reveal in Finder · Logs.
    private var secondaryActions: some View {
        HStack(spacing: 8) {
            // Imported servers offer Remove (unlink, keep files; minus icon);
            // managed ones offer Delete (move the whole folder to Trash; dark red).
            // While running, Delete is disabled — the .help() lives on the wrapper
            // (a disabled Button swallows its own tooltip) so the "stop it first"
            // hint still shows on hover.
            Button { onDelete() } label: {
                Label(instance.isImported ? "Remove" : "Delete",
                      systemImage: instance.isImported ? "minus.circle" : "trash")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.badDark))
            .disabled(controller.isRunning)
            .allowsHitTesting(!controller.isRunning)
            .overlay {
                // Transparent hover catcher carrying the tooltip while disabled.
                if controller.isRunning {
                    Color.clear.contentShape(Rectangle()).help(deleteTooltip)
                }
            }
            .help(controller.isRunning ? "" : deleteTooltip)

            Button { NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: instance.binaryPath)]) } label: {
                Label("Finder", systemImage: "folder")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.cardHi)).help("Reveal in Finder")
            .disabled(!instance.exists)

            // Show / hide this server's live + recent log inline.
            Button { withAnimation(.easeInOut(duration: 0.18)) { showLogs.toggle() } } label: {
                Label("Logs", systemImage: showLogs ? "chevron.up" : "chevron.down")
            }
            .buttonStyle(MiniButtonStyle(fill: Theme.cardHi))
            .help(showLogs ? "Hide logs" : "Show logs")
        }
        .fixedSize()
    }

    // Status colors per spec: offline (red), online (green), transitional /
    // running-with-warnings (yellow), error / crash (orange).
    private var statusColor: Color {
        if !instance.exists { return Theme.bad }
        // A server adopted from outside the app gets a distinct purple dot.
        if controller.isExternal { return Theme.accent }
        switch controller.state {
        case .running:             return Theme.good
        case .starting, .stopping: return Theme.caution
        case .crashed:             return Theme.warn
        case .stopped:             return Theme.bad
        }
    }
    private var statusText: String {
        if !instance.exists { return "Deleted" }
        switch controller.state {
        case .running:  return controller.isExternal ? "Online (external)" : "Online"
        case .starting: return "Starting…"
        case .stopping: return "Stopping…"
        case .crashed:  return "Crashed"
        case .stopped:  return "Offline"
        }
    }
}

// MARK: Hold-to-confirm button

// A destructive button the user must press and HOLD for `seconds` to confirm.
// A red fill sweeps left→right while held; releasing early cancels and the fill
// recedes. Fires `action` once full. Hover brightens it so it reads as live.
struct HoldToConfirmButton: View {
    let seconds: Double
    let title: String
    var icon: String = "trash"
    var doneText: String = "Working…"
    let action: () -> Void

    @State private var progress: Double = 0
    @State private var holding = false
    @State private var hovering = false
    @State private var done = false
    // Bumped each press so a stale completion task from a cancelled hold is ignored.
    @State private var holdToken = 0

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Theme.bad.opacity(0.22)
                Theme.bad.frame(width: geo.size.width * progress)
                HStack(spacing: 6) {
                    Image(systemName: done ? "checkmark" : icon)
                    Text(done ? doneText : title)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
            }
            .frame(width: geo.size.width, height: geo.size.height)
        }
        .frame(height: 40)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner)
            .stroke(Theme.bad.opacity(holding ? 1 : 0.6), lineWidth: holding ? 1.6 : 1))
        .brightness(hovering && !holding ? 0.06 : 0)
        .contentShape(RoundedRectangle(cornerRadius: Theme.corner))
        .onHover { h in
            hovering = h
            if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in if !holding && !done { startHold() } }
                .onEnded { _ in if !done { cancelHold() } }
        )
        .help("Press and hold for \(Int(seconds)) seconds to confirm.")
    }

    private func startHold() {
        holding = true
        holdToken += 1
        let token = holdToken
        let remaining = seconds * (1 - progress)
        withAnimation(.linear(duration: remaining)) { progress = 1 }
        // Fire when the fill completes — unless this hold was cancelled.
        DispatchQueue.main.asyncAfter(deadline: .now() + remaining) {
            guard holding, token == holdToken, !done else { return }
            done = true
            holding = false
            action()
        }
    }

    private func cancelHold() {
        holding = false
        holdToken += 1   // invalidate the pending completion
        withAnimation(.easeOut(duration: 0.2)) { progress = 0 }
    }
}

// MARK: Resource usage box

// A compact rounded box showing the running server's CPU and RAM use, e.g.
// "CPU 1%  ·  RAM 10 MB (15%)". Sits next to the Restart button while running.
private struct UsageBox: View {
    let usage: InstanceController.ResourceUsage

    var body: some View {
        HStack(spacing: 8) {
            stat(icon: "cpu", text: "CPU \(pct(usage.cpuPercent))")
            Divider().frame(height: 12).overlay(Theme.border)
            stat(icon: "memorychip",
                 text: "RAM \(bytes(usage.rssBytes)) (\(pct(usage.ramPercent)))")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border, lineWidth: 1))
        .help("Live CPU and memory use of the running server process")
    }

    private func stat(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(Theme.textDim)
            Text(text).font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.text)
        }
    }

    private func pct(_ v: Double) -> String {
        v >= 10 ? "\(Int(v.rounded()))%" : String(format: "%.1f%%", v)
    }
    private func bytes(_ b: Int64) -> String {
        let mb = Double(b) / 1_048_576
        if mb >= 1024 { return String(format: "%.1f GB", mb / 1024) }
        return "\(Int(mb.rounded())) MB"
    }
}

// MARK: Blocked Start button

// A greyed, non-startable Start: "⚠ Start (?)". The whole pill is inert; the
// trailing (?) opens a popover listing exactly what's wrong (no gamemode, default
// RCON, port clash). Same compact size as MiniButtonStyle.
private struct BlockedStartButton: View {
    let problems: [String]
    @State private var showWhy = false
    @State private var hoverWhy = false

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill").imageScale(.small)
            Text("Start").font(.system(size: 12, weight: .semibold))
            Button { showWhy.toggle() } label: {
                Image(systemName: "questionmark.circle\(showWhy || hoverWhy ? ".fill" : "")")
                    .font(.system(size: 12))
            }
            .buttonStyle(.plain).focusable(false)
            .onHover { h in
                hoverWhy = h; showWhy = h
                if h { NSCursor.pointingHand.push() } else { NSCursor.pop() }
            }
            .popover(isPresented: $showWhy, arrowEdge: .bottom) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Can’t start this server").font(.system(size: 13, weight: .bold))
                    ForEach(problems, id: \.self) { p in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 12)).foregroundStyle(Theme.bad)
                            Text(p).font(.system(size: 12)).foregroundStyle(Theme.text)
                        }
                    }
                }
                .padding(12).frame(width: 320)
            }
        }
        .foregroundStyle(Theme.textDim)
        .padding(.horizontal, 12).padding(.vertical, 6)
        .background(Theme.disabled)
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}
