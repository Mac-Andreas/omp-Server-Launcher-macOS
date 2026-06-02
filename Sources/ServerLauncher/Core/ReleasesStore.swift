// Fetches downloadable open.mp server builds from GitHub releases and tracks
// which versions have been downloaded/installed locally.
//
//   • macOS arm64 builds  ← github.com/xyranaut/omp-server-macos
//   • Windows-32 builds   ← github.com/openmultiplayer/open.mp
//
// For each release we pick the asset matching the platform (a macOS arm64
// tarball, or the Windows x86 zip). Downloaded archives are cached under
// Application Support; "installed" means we've extracted one to a folder and
// registered it as a server.
import Foundation
import Combine

/// One downloadable build (a release + its platform-matching asset).
struct ReleaseBuild: Identifiable, Equatable {
    var id: String { "\(platform.rawValue)#\(tag)" }
    var tag: String            // e.g. "v1.5.8.3079-macos-arm64"
    var version: String        // cleaned, e.g. "1.5.8.3079"
    var platform: ServerPlatform
    var assetName: String
    var downloadURL: URL
    var isPrerelease: Bool
}

@MainActor
final class ReleasesStore: ObservableObject {
    enum LoadState: Equatable { case idle, loading, loaded, failed(String) }

    @Published private(set) var builds: [ReleaseBuild] = []
    @Published private(set) var state: LoadState = .idle

    /// version -> local download progress (0...1) while downloading.
    @Published private(set) var downloading: [String: Double] = [:]
    /// Cached-archive presence by build id.
    @Published private(set) var downloaded: Set<String> = []

    private let macRepo = "xyranaut/omp-server-macos"
    private let winRepo = "openmultiplayer/open.mp"

    private nonisolated var cacheDir: URL {
        let dir = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server Manager/downloads", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    func builds(for platform: ServerPlatform) -> [ReleaseBuild] {
        builds.filter { $0.platform == platform }
    }

    /// Newest non-prerelease version available for a platform (releases are listed
    /// newest-first). Falls back to the newest of any kind. Nil if none loaded.
    func latestVersion(for platform: ServerPlatform) -> String? {
        let p = builds(for: platform)
        return p.first(where: { !$0.isPrerelease })?.version ?? p.first?.version
    }

    func cachedArchive(for build: ReleaseBuild) -> URL? {
        let url = cacheDir.appendingPathComponent(build.assetName)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    func isDownloaded(_ build: ReleaseBuild) -> Bool {
        cachedArchive(for: build) != nil
    }

    // MARK: Load release lists

    func loadIfNeeded() {
        if case .loaded = state { return }
        if case .loading = state { return }
        load()
    }

    func load() {
        state = .loading
        Task {
            do {
                async let mac = fetchReleases(repo: macRepo, platform: .macos)
                async let win = fetchReleases(repo: winRepo, platform: .windows)
                let all = try await (mac + win)
                builds = all
                refreshDownloadedSet()
                state = .loaded
            } catch {
                state = .failed(error.localizedDescription)
            }
        }
    }

    private func refreshDownloadedSet() {
        downloaded = Set(builds.filter { isDownloaded($0) }.map(\.id))
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let prerelease: Bool
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable {
        let name: String
        let browser_download_url: URL
    }

    private func fetchReleases(repo: String, platform: ServerPlatform) async throws -> [ReleaseBuild] {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases?per_page=30")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Server-Manager", forHTTPHeaderField: "User-Agent")
        let (data, resp) = try await URLSession.shared.data(for: req)
        guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else {
            throw NSError(domain: "GitHub", code: (resp as? HTTPURLResponse)?.statusCode ?? -1,
                          userInfo: [NSLocalizedDescriptionKey: "GitHub API error for \(repo)."])
        }
        let releases = try JSONDecoder().decode([GHRelease].self, from: data)
        return releases.compactMap { rel in
            guard let asset = pickAsset(rel.assets, for: platform) else { return nil }
            return ReleaseBuild(
                tag: rel.tag_name,
                version: cleanVersion(rel.tag_name),
                platform: platform,
                assetName: asset.name,
                downloadURL: asset.browser_download_url,
                isPrerelease: rel.prerelease)
        }
    }

    /// Match the right downloadable archive for the platform.
    private func pickAsset(_ assets: [GHAsset], for platform: ServerPlatform) -> GHAsset? {
        switch platform {
        case .macos:
            return assets.first { $0.name.lowercased().contains("macos")
                && ($0.name.hasSuffix(".tar.gz") || $0.name.hasSuffix(".tgz") || $0.name.hasSuffix(".zip")) }
        case .windows:
            // open.mp ships open.mp-win-x86.zip
            return assets.first { let n = $0.name.lowercased()
                return n.contains("win") && n.hasSuffix(".zip") }
        }
    }

    private func cleanVersion(_ tag: String) -> String {
        if let m = tag.range(of: #"\d+\.\d+\.\d+(\.\d+)?"#, options: .regularExpression) {
            return String(tag[m])
        }
        return tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
    }

    // MARK: Download

    func download(_ build: ReleaseBuild) {
        guard downloading[build.id] == nil, !isDownloaded(build) else { return }
        downloading[build.id] = 0
        let dest = cacheDir.appendingPathComponent(build.assetName)

        let task = URLSession.shared.downloadTask(with: build.downloadURL) { [weak self] tmp, _, error in
            Task { @MainActor in
                guard let self else { return }
                self.downloading[build.id] = nil
                guard let tmp, error == nil else { return }
                try? FileManager.default.removeItem(at: dest)
                try? FileManager.default.moveItem(at: tmp, to: dest)
                self.refreshDownloadedSet()
            }
        }
        observations[build.id] = task.progress.observe(\.fractionCompleted) { [weak self] p, _ in
            Task { @MainActor in
                if self?.downloading[build.id] != nil {
                    self?.downloading[build.id] = p.fractionCompleted
                }
            }
        }
        task.resume()
    }
    private var observations: [String: NSKeyValueObservation] = [:]

    // MARK: Install (extract cached archive to a folder)

    /// Extract the cached archive for `build` into `destDir`. Returns the path
    /// to the omp-server binary found inside, or throws.
    func install(_ build: ReleaseBuild, into destDir: URL) throws -> String {
        guard let archive = cachedArchive(for: build) else {
            throw NSError(domain: "Install", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Archive not downloaded."])
        }
        let fm = FileManager.default
        try fm.createDirectory(at: destDir, withIntermediateDirectories: true)

        let name = archive.lastPathComponent.lowercased()
        let r: Shell.Result
        if name.hasSuffix(".zip") {
            r = Shell.run("/usr/bin/unzip", ["-o", archive.path, "-d", destDir.path], timeout: 300)
        } else {
            // .tar.gz / .tgz
            r = Shell.run("/usr/bin/tar", ["-xzf", archive.path, "-C", destDir.path], timeout: 300)
        }
        guard r.exitCode == 0 else {
            throw NSError(domain: "Install", code: 2,
                          userInfo: [NSLocalizedDescriptionKey: r.stderr.isEmpty ? "Extraction failed." : r.stderr])
        }
        // The archives wrap everything in a single top-level "Server/" folder.
        // Flatten it so files land directly in destDir (no extra /Server level).
        flattenSingleWrapper(in: destDir)
        guard let bin = findBinary(in: destDir, name: build.platform.binaryName) else {
            throw NSError(domain: "Install", code: 3,
                          userInfo: [NSLocalizedDescriptionKey: "\(build.platform.binaryName) not found in the archive."])
        }
        if build.platform == .macos {
            _ = Shell.run("/bin/chmod", ["+x", bin], timeout: 10)
        }
        return bin
    }

    /// If `dir` contains exactly one entry and it's a directory (the archive's
    /// "Server" wrapper), move its contents up into `dir` and delete the wrapper.
    private func flattenSingleWrapper(in dir: URL) {
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(
            at: dir, includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]) else { return }
        guard entries.count == 1,
              (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
        else { return }
        let wrapper = entries[0]
        guard let inner = try? fm.contentsOfDirectory(at: wrapper, includingPropertiesForKeys: nil) else { return }
        for item in inner {
            let target = dir.appendingPathComponent(item.lastPathComponent)
            try? fm.removeItem(at: target)
            try? fm.moveItem(at: item, to: target)
        }
        try? fm.removeItem(at: wrapper)
    }

    // MARK: macOS scaffolding overlay (platform-independent files from Win zip)

    /// The macOS arm64 release ships only the native binary + components. The
    /// open.mp scaffolding (config/bans templates, gamemodes/, filterscripts/,
    /// the Qawno PAWN include stdlib, etc.) only lives in the Windows zip. For a
    /// macOS install we overlay those platform-INDEPENDENT files from the
    /// matching-version Windows zip, while excluding every Windows binary (we
    /// supply a native server + native Qawno separately).
    ///
    /// Best-effort: if the matching Windows build can't be found or downloaded,
    /// this does nothing and never throws.
    nonisolated func overlayWindowsScaffolding(forMacVersion version: String, into serverFolder: String) async {
        // 1. Find the exact-version Windows build.
        guard let win = await MainActor.run(body: {
            self.builds.first { $0.platform == .windows && $0.version == version }
        }) else { return }

        // 2. Ensure its zip is cached (download synchronously if needed).
        let archive: URL
        if let cached = await MainActor.run(body: { self.cachedArchive(for: win) }) {
            archive = cached
        } else {
            let dest = cacheDir.appendingPathComponent(win.assetName)
            do {
                let (tmp, resp) = try await URLSession.shared.download(from: win.downloadURL)
                guard (resp as? HTTPURLResponse)?.statusCode == 200 else { return }
                try? FileManager.default.removeItem(at: dest)
                try FileManager.default.moveItem(at: tmp, to: dest)
                archive = dest
                await MainActor.run { self.refreshDownloadedSet() }
            } catch { return }
        }

        // 3. Extract into a clean staging dir.
        let fm = FileManager.default
        let stage = cacheDir.appendingPathComponent("win-overlay-stage", isDirectory: true)
        try? fm.removeItem(at: stage)
        guard (try? fm.createDirectory(at: stage, withIntermediateDirectories: true)) != nil else { return }
        defer { try? fm.removeItem(at: stage) }
        let r = Shell.run("/usr/bin/unzip", ["-o", "-q", archive.path, "-d", stage.path], timeout: 300)
        guard r.exitCode == 0 else { return }

        // Descend into a single top-level wrapper folder if present.
        var root = stage
        if let entries = try? fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: [.isDirectoryKey],
                                                     options: [.skipsHiddenFiles]),
           entries.count == 1,
           (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            root = entries[0]
        }

        // 4. Copy the allowed scaffolding, skipping anything that excludes.
        let dest = URL(fileURLWithPath: serverFolder)
        copyScaffolding(from: root, to: dest)
    }

    /// Files/folders we carry over from the Windows zip. Everything else (and any
    /// excluded item below) is skipped. We never overwrite a file that already
    /// exists in the destination (the native install/Qawno win).
    private nonisolated func copyScaffolding(from root: URL, to dest: URL) {
        let fm = FileManager.default

        // Top-level config/data files worth seeding (templates).
        let topFiles = ["config.json", "bans.json"]
        for name in topFiles {
            let src = root.appendingPathComponent(name)
            let dst = dest.appendingPathComponent(name)
            if fm.fileExists(atPath: src.path) && !fm.fileExists(atPath: dst.path) {
                try? fm.copyItem(at: src, to: dst)
            }
        }

        // Whole folders that are platform-independent script/content scaffolding.
        let topDirs = ["filterscripts", "gamemodes", "models", "npcmodes", "scriptfiles"]
        for name in topDirs {
            let src = root.appendingPathComponent(name, isDirectory: true)
            guard fm.fileExists(atPath: src.path) else { continue }
            copyTreeExcludingBinaries(from: src, to: dest.appendingPathComponent(name, isDirectory: true))
        }

        // Qawno: take ONLY the include/ stdlib and any *.new templates + the
        // editor's license/readme text — never the Windows qawno.exe/pawncc etc.
        let qawnoSrc = root.appendingPathComponent("qawno", isDirectory: true)
        if fm.fileExists(atPath: qawnoSrc.path) {
            let qawnoDst = dest.appendingPathComponent("qawno", isDirectory: true)
            // include/ stdlib
            let incSrc = qawnoSrc.appendingPathComponent("include", isDirectory: true)
            if fm.fileExists(atPath: incSrc.path) {
                copyTreeExcludingBinaries(from: incSrc, to: qawnoDst.appendingPathComponent("include", isDirectory: true))
            }
            // *.new templates + license/readme text at the qawno root
            if let entries = try? fm.contentsOfDirectory(at: qawnoSrc, includingPropertiesForKeys: nil,
                                                         options: [.skipsHiddenFiles]) {
                for e in entries {
                    let n = e.lastPathComponent.lowercased()
                    let keep = n.hasSuffix(".new")
                        || n.contains("license") || n.contains("readme")
                    guard keep, !isExcludedBinary(n) else { continue }
                    let dst = qawnoDst.appendingPathComponent(e.lastPathComponent)
                    if !fm.fileExists(atPath: dst.path) {
                        try? fm.createDirectory(at: qawnoDst, withIntermediateDirectories: true)
                        try? fm.copyItem(at: e, to: dst)
                    }
                }
            }
        }
    }

    /// Recursively copy `src` into `dst`, skipping Windows binaries and never
    /// overwriting existing destination files.
    private nonisolated func copyTreeExcludingBinaries(from src: URL, to dst: URL) {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: src, includingPropertiesForKeys: [.isDirectoryKey],
                                     options: [.skipsHiddenFiles]) else { return }
        try? fm.createDirectory(at: dst, withIntermediateDirectories: true)
        for case let url as URL in en {
            let rel = url.path.replacingOccurrences(of: src.path + "/", with: "")
            let isDir = (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
            let target = dst.appendingPathComponent(rel)
            if isDir {
                try? fm.createDirectory(at: target, withIntermediateDirectories: true)
            } else {
                guard !isExcludedBinary(url.lastPathComponent.lowercased()) else { continue }
                if !fm.fileExists(atPath: target.path) {
                    try? fm.createDirectory(at: target.deletingLastPathComponent(),
                                            withIntermediateDirectories: true)
                    try? fm.copyItem(at: url, to: target)
                }
            }
        }
    }

    /// True for Windows-only binaries we must never carry over to a macOS server.
    private nonisolated func isExcludedBinary(_ lowercasedName: String) -> Bool {
        let exts = [".exe", ".dll", ".pdb"]
        if exts.contains(where: { lowercasedName.hasSuffix($0) }) { return true }
        // Belt-and-suspenders for known Windows Qawno/editor binaries.
        let names = ["qawno.exe", "pawncc.exe", "pawnc.dll", "omp-server.exe"]
        return names.contains(lowercasedName)
    }

    private func findBinary(in root: URL, name: String) -> String? {
        let fm = FileManager.default
        guard let en = fm.enumerator(at: root, includingPropertiesForKeys: nil) else { return nil }
        for case let url as URL in en where url.lastPathComponent == name {
            return url.path
        }
        return nil
    }
}
