// Downloads the native macOS Qawno (PAWN compiler/editor) from the Mac Andreas
// repo, ad-hoc codesigns it (so Gatekeeper lets it run), and installs it into a
// server's `qawno/` folder. Windows downloads ship a Windows Qawno (.exe) that
// can't run natively on macOS, so macOS servers get this instead.
//
// The download is cached under Application Support so repeated installs don't
// re-download.
import Foundation

enum QawnoInstaller {
    // Mac Andreas · Qawno-macOS. URLSession follows the release-asset redirect.
    private static let repo = "Mac-Andreas/Qawno-macOS"

    private static var cacheDir: URL {
        let d = FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Server Manager/qawno", isDirectory: true)
        try? FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        return d
    }

    private struct GHRelease: Decodable {
        let tag_name: String
        let assets: [GHAsset]
    }
    private struct GHAsset: Decodable { let name: String; let browser_download_url: URL }

    /// Resolve the latest Qawno-macOS zip asset URL.
    private static func latestAsset() async throws -> (name: String, url: URL) {
        var req = URLRequest(url: URL(string: "https://api.github.com/repos/\(repo)/releases/latest")!)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("Server-Manager", forHTTPHeaderField: "User-Agent")
        let (data, _) = try await URLSession.shared.data(for: req)
        let rel = try JSONDecoder().decode(GHRelease.self, from: data)
        guard let asset = rel.assets.first(where: { $0.name.lowercased().hasSuffix(".zip") }) else {
            throw err("No Qawno-macOS .zip asset found in the latest release.")
        }
        return (asset.name, asset.browser_download_url)
    }

    /// Download (cached), extract, ad-hoc codesign, and install Qawno into
    /// `serverFolder/qawno`. Best-effort: throws on hard failures, but a signing
    /// hiccup is non-fatal (the user can still right-click→open).
    static func install(into serverFolder: String) async throws {
        let fm = FileManager.default
        let (assetName, url) = try await latestAsset()
        let archive = cacheDir.appendingPathComponent(assetName)

        if !fm.fileExists(atPath: archive.path) {
            let (tmp, _) = try await URLSession.shared.download(from: url)
            try? fm.removeItem(at: archive)
            try fm.moveItem(at: tmp, to: archive)
        }

        // Extract into a clean staging dir.
        let stage = cacheDir.appendingPathComponent("stage", isDirectory: true)
        try? fm.removeItem(at: stage)
        try fm.createDirectory(at: stage, withIntermediateDirectories: true)
        let r = Shell.run("/usr/bin/unzip", ["-o", archive.path, "-d", stage.path], timeout: 300)
        guard r.exitCode == 0 else { throw err(r.stderr.isEmpty ? "Could not unzip Qawno." : r.stderr) }

        // Merge the archive's contents INTO <server>/qawno — never wipe the
        // folder first. The platform-independent scaffolding (the include/ PAWN
        // stdlib, *.new config templates and the Qawno LICENSE/README that come
        // from the open.mp Windows zip) is laid down before this step, and must
        // survive: the macOS Qawno release ships only Qawno.app + the native
        // compiler, with no docs of its own.
        let dest = URL(fileURLWithPath: serverFolder).appendingPathComponent("qawno", isDirectory: true)
        try fm.createDirectory(at: dest, withIntermediateDirectories: true)
        // If the zip has a single top-level folder, copy its contents; else copy all.
        let entries = (try? fm.contentsOfDirectory(at: stage, includingPropertiesForKeys: nil)) ?? []
        let roots: [URL]
        if entries.count == 1, (try? entries[0].resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            roots = (try? fm.contentsOfDirectory(at: entries[0], includingPropertiesForKeys: nil)) ?? []
        } else {
            roots = entries
        }
        for item in roots {
            let target = dest.appendingPathComponent(item.lastPathComponent)
            // Replace only the item we're installing (e.g. Qawno.app), leaving the
            // rest of qawno/ (include/, templates, LICENSE/README) untouched.
            try? fm.removeItem(at: target)
            try fm.copyItem(at: item, to: target)
        }

        // Ad-hoc codesign any .app bundle and executables so Gatekeeper allows
        // launching, and clear the download quarantine flag.
        _ = Shell.run("/usr/bin/xattr", ["-dr", "com.apple.quarantine", dest.path], timeout: 30)
        // Collect URLs first (the enumerator iterator isn't usable in async ctx).
        var urls: [URL] = []
        if let en = fm.enumerator(at: dest, includingPropertiesForKeys: [.isExecutableKey, .isRegularFileKey]) {
            while let u = en.nextObject() as? URL { urls.append(u) }
        }
        for u in urls {
            if u.pathExtension == "app" {
                _ = Shell.run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", u.path], timeout: 120)
            } else if fm.isExecutableFile(atPath: u.path),
                      (try? u.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
                _ = Shell.run("/usr/bin/codesign", ["--force", "--sign", "-", u.path], timeout: 60)
            }
        }
    }

    private static func err(_ m: String) -> NSError {
        NSError(domain: "Qawno", code: 1, userInfo: [NSLocalizedDescriptionKey: m])
    }
}
