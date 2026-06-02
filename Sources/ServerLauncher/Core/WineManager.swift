// Manages a self-contained 32-bit-capable Wine runtime for running the Windows
// open.mp server on Apple Silicon. macOS dropped native 32-bit support, so we
// use a wine32on64-capable build (Gcenx's macOS_Wine_builds) which runs 32-bit
// PE binaries inside a 64-bit process.
//
// Lifecycle (all under ~/Library/Application Support, no admin needed):
//   not installed ──Download──▶ downloaded (cached .tar.xz)
//   downloaded     ──Install──▶ installed (extracted, wine binary present)
//   installed      ──Uninstall─▶ downloaded (keeps the cached archive so a
//                                 re-install needs no re-download)
//
// The cached archive is kept on uninstall on purpose: uninstall removes the
// extracted runtime but leaves the download so re-install is instant.
import Foundation
import Combine

@MainActor
final class WineManager: ObservableObject {
    enum State: Equatable {
        case notInstalled        // nothing on disk
        case downloading(Double) // 0...1 progress
        case downloaded          // archive cached, not extracted
        case installing
        case installed           // wine binary ready
        case failed(String)
    }

    @Published private(set) var state: State = .notInstalled

    // Gcenx macOS_Wine_builds — wine-staging, osx64, wine32on64-capable.
    // Bump the version/URL when a newer build is adopted.
    static let wineVersion = "11.9"
    private let downloadURL = URL(string:
        "https://github.com/Gcenx/macOS_Wine_builds/releases/download/11.9/wine-staging-11.9-osx64.tar.xz")!

    // MARK: Paths (all user-level App Support)

    private var appSupport: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server Manager", isDirectory: true)
    }
    private var archiveURL: URL { appSupport.appendingPathComponent("wine-\(Self.wineVersion).tar.xz") }
    private var runtimeDir: URL { appSupport.appendingPathComponent("wine", isDirectory: true) }

    /// Path to the wine executable once installed, else nil. The Gcenx tarball
    /// extracts to "Wine Staging.app"/"Wine Devel.app" with Contents/Resources/
    /// wine/bin/wine — search for any bin/wine under the runtime dir.
    var wineBinary: String? {
        guard let found = findWineBinary(in: runtimeDir) else { return nil }
        return found.path
    }

    var isInstalled: Bool { wineBinary != nil }

    // MARK: State refresh (call on appear)

    func refresh() {
        if isInstalled { state = .installed }
        else if FileManager.default.fileExists(atPath: archiveURL.path) { state = .downloaded }
        else { state = .notInstalled }
    }

    // MARK: Download

    /// One-tap setup: download (if needed) then extract/install automatically.
    func downloadAndInstall() {
        switch state {
        case .notInstalled:
            autoInstallAfterDownload = true
            download()
        case .downloaded:
            install()
        default:
            break
        }
    }
    private var autoInstallAfterDownload = false

    func download() {
        guard case .notInstalled = state else { return }
        state = .downloading(0)
        ensureAppSupport()

        let dest = archiveURL  // capture off the actor before the closure
        let task = URLSession.shared.downloadTask(with: downloadURL) { [weak self] tmp, _, error in
            if let error {
                Task { @MainActor in self?.state = .failed(error.localizedDescription) }
                return
            }
            guard let tmp else {
                Task { @MainActor in self?.state = .failed("Download failed.") }
                return
            }
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                Task { @MainActor in
                    self?.state = .downloaded
                    if self?.autoInstallAfterDownload == true {
                        self?.autoInstallAfterDownload = false
                        self?.install()
                    }
                }
            } catch {
                let msg = error.localizedDescription
                Task { @MainActor in self?.state = .failed(msg) }
            }
        }
        // Progress via KVO.
        progressObservation = task.progress.observe(\.fractionCompleted) { [weak self] prog, _ in
            Task { @MainActor in
                if case .downloading = self?.state {
                    self?.state = .downloading(prog.fractionCompleted)
                }
            }
        }
        task.resume()
    }
    private var progressObservation: NSKeyValueObservation?

    // MARK: Install (extract)

    func install() {
        guard case .downloaded = state else { return }
        state = .installing
        let archive = archiveURL
        let dest = runtimeDir

        Task.detached {
            do {
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.createDirectory(at: dest, withIntermediateDirectories: true)
                // bsdtar (system) handles .tar.xz.
                let r = Shell.run("/usr/bin/tar", ["-xJf", archive.path, "-C", dest.path], timeout: 300)
                let ok = r.exitCode == 0
                await MainActor.run {
                    if ok && self.isInstalled {
                        self.state = .installed
                    } else {
                        self.state = .failed(r.stderr.isEmpty ? "Extraction failed." : r.stderr)
                    }
                }
            } catch {
                await MainActor.run { self.state = .failed(error.localizedDescription) }
            }
        }
    }

    // MARK: Uninstall (keep cached archive)

    func uninstall() {
        try? FileManager.default.removeItem(at: runtimeDir)
        refresh()  // -> .downloaded (archive kept) or .notInstalled
    }

    /// Also remove the cached download (full cleanup).
    func removeCachedDownload() {
        try? FileManager.default.removeItem(at: archiveURL)
        refresh()
    }

    // MARK: Helpers

    private func ensureAppSupport() {
        try? FileManager.default.createDirectory(at: appSupport, withIntermediateDirectories: true)
    }

    private func findWineBinary(in root: URL) -> URL? {
        let fm = FileManager.default
        guard fm.fileExists(atPath: root.path) else { return nil }
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in en {
            if url.lastPathComponent == "wine" && url.deletingLastPathComponent().lastPathComponent == "bin" {
                if fm.isExecutableFile(atPath: url.path) { return url }
            }
        }
        return nil
    }
}
