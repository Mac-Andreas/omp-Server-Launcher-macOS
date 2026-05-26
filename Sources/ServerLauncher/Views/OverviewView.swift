// Overview: setup state at a glance.
//  1. Wine runtime — download / install / uninstall (installs under
//     ~/Library/Application Support; cached archive kept for fast re-install).
//  2. Wine prefix — the "bottle" the server runs in.
//  3. Server files — whether omp-server.exe is present beside the .app.
import SwiftUI
import AppKit

struct OverviewView: View {
    @EnvironmentObject private var wine: WineManager

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Overview").font(.system(size: 18, weight: .bold))
                wineCard
                prefixCard
                serverFilesCard
            }
            .padding(22)
        }
        .onAppear { wine.refresh() }
    }

    // MARK: Wine runtime

    private var wineCard: some View {
        StatusCard(
            title: "Wine runtime",
            subtitle: "32-bit Wine (\(WineManager.wineVersion)) to run the Windows open.mp server.",
            indicator: wineIndicator
        ) {
            switch wine.state {
            case .notInstalled:
                Button("Download") { wine.download() }
                    .buttonStyle(PillButtonStyle(kind: .primary))

            case .downloading(let p):
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: p).tint(Theme.accent).frame(maxWidth: 320)
                    Text("Downloading… \(Int(p * 100))%")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }

            case .downloaded:
                HStack(spacing: 12) {
                    Button("Install") { wine.install() }
                        .buttonStyle(PillButtonStyle(kind: .primary))
                    Button("Remove download") { wine.removeCachedDownload() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                    Text("Cached — install needs no re-download.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }

            case .installing:
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Installing…").font(.system(size: 12)).foregroundStyle(Theme.textDim)
                }

            case .installed:
                HStack(spacing: 12) {
                    Label("Installed", systemImage: "checkmark.circle.fill")
                        .foregroundStyle(Theme.good).font(.system(size: 12, weight: .semibold))
                    Button("Uninstall") { wine.uninstall() }
                        .buttonStyle(PillButtonStyle(kind: .danger))
                    Text("Cached archive kept for re-install.")
                        .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                }

            case .failed(let msg):
                VStack(alignment: .leading, spacing: 8) {
                    Text(msg).font(.system(size: 12)).foregroundStyle(Theme.bad)
                    Button("Retry") { wine.refresh(); wine.download() }
                        .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
        }
    }

    private var wineIndicator: StatusIndicator {
        switch wine.state {
        case .installed:                 return .init(color: Theme.good, text: "Ready")
        case .downloading, .installing:  return .init(color: Theme.warn, text: "Working")
        case .downloaded:                return .init(color: Theme.warn, text: "Not installed")
        case .failed:                    return .init(color: Theme.bad,  text: "Error")
        case .notInstalled:              return .init(color: Theme.bad,  text: "Missing")
        }
    }

    // MARK: Prefix (bottle)

    private var prefixCard: some View {
        StatusCard(
            title: "Wine prefix",
            subtitle: "The bottle the server runs in. Created automatically on first start.",
            indicator: ServerEnv.prefixExists
                ? .init(color: Theme.good, text: "Created")
                : .init(color: Theme.textDim, text: "Not yet")
        ) {
            if ServerEnv.prefixExists {
                Button("Reset prefix") { ServerEnv.deletePrefix() }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
            } else {
                Text("Will be created when you first start the server.")
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
            }
        }
    }

    // MARK: Server files

    private var serverFilesCard: some View {
        StatusCard(
            title: "Server files",
            subtitle: ServerEnv.serverDir,
            indicator: ServerEnv.filesPresent
                ? .init(color: Theme.good, text: "Found")
                : .init(color: Theme.bad, text: "Missing")
        ) {
            if ServerEnv.filesPresent {
                Label("omp-server.exe present", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(Theme.good).font(.system(size: 12))
            } else {
                HStack(spacing: 12) {
                    Text("Missing: \(ServerEnv.missingFiles.joined(separator: ", "))")
                        .font(.system(size: 12)).foregroundStyle(Theme.bad)
                    Button("Open folder") {
                        NSWorkspace.shared.open(URL(fileURLWithPath: ServerEnv.serverDir))
                    }
                    .buttonStyle(PillButtonStyle(kind: .secondary))
                }
            }
        }
    }
}

struct StatusIndicator { var color: Color; var text: String }

// A card with a left title/subtitle/action block and a right status dot+label.
struct StatusCard<Content: View>: View {
    let title: String
    let subtitle: String
    let indicator: StatusIndicator
    @ViewBuilder var content: Content

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title).font(.system(size: 14, weight: .bold))
                Text(subtitle)
                    .font(.system(size: 11)).foregroundStyle(Theme.textDim)
                    .lineLimit(2).truncationMode(.middle)
                content
            }
            Spacer()
            HStack(spacing: 7) {
                Circle().fill(indicator.color).frame(width: 9, height: 9)
                Text(indicator.text)
                    .font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.textDim)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(18)
        .background(Theme.card)
        .clipShape(RoundedRectangle(cornerRadius: Theme.corner))
        .overlay(RoundedRectangle(cornerRadius: Theme.corner).stroke(Theme.border))
    }
}
