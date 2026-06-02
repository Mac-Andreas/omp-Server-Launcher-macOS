// GitHub release update check + in-app download/install. Queries releases/latest
// for the configured repo, reports whether a newer tag exists, and (on request)
// downloads the release .zip, unzips it, swaps the new .app over the running one
// via a detached helper script, ad-hoc re-signs it, and relaunches.
//
// The swap can't happen from inside the running bundle, so the heavy lifting is
// done by a short shell script that waits for this process to exit first.
import Foundation
import Combine
import AppKit

@MainActor
final class Updater: NSObject, ObservableObject {
    struct Result: Equatable {
        var available: Bool
        var latestVersion: String
        var htmlURL: URL?
        var downloadURL: URL?      // the release .zip asset, when present
    }

    // Where we are in the in-app update flow, for the UI.
    enum Phase: Equatable {
        case idle
        case downloading(progress: Double, bytesPerSec: Double)
        case unpacking
        case installing
        case failed(String)
    }

    @Published private(set) var result = Result(available: false, latestVersion: "", htmlURL: nil, downloadURL: nil)
    @Published private(set) var phase: Phase = .idle

    // Download bookkeeping (for the speed/progress readout).
    private var session: URLSession?
    private var downloadStart = Date()
    private var pendingVersion = ""

    // MARK: Check

    func check() {
        let urlStr = "https://api.github.com/repos/\(AppInfo.updateOwner)/\(AppInfo.updateRepo)/releases/latest"
        guard let url = URL(string: urlStr) else { return }

        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("openmp-server-launcher", forHTTPHeaderField: "User-Agent")

        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let data,
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = obj["tag_name"] as? String, !tag.isEmpty
            else { return }
            let html = (obj["html_url"] as? String).flatMap(URL.init(string:))
            // First .zip asset is the packaged .app; fall back to a .dmg if that's
            // all that's published (we only auto-install .zip; .dmg opens in UI).
            let assets = obj["assets"] as? [[String: Any]] ?? []
            let zip = assets.first { ($0["name"] as? String)?.lowercased().hasSuffix(".zip") == true }
            let dl = (zip?["browser_download_url"] as? String).flatMap(URL.init(string:))
            let newer = Self.compareVersions(AppInfo.version, tag) < 0
            Task { @MainActor in
                self?.result = Result(available: newer, latestVersion: tag,
                                      htmlURL: html, downloadURL: dl)
            }
        }.resume()
    }

    // MARK: Download + install

    /// True when an in-app update can actually be installed (a .zip asset exists).
    var canAutoInstall: Bool { result.downloadURL != nil }

    func downloadAndInstall() {
        guard let url = result.downloadURL else {
            phase = .failed("This release has no installable package."); return
        }
        pendingVersion = result.latestVersion
        downloadStart = Date()
        phase = .downloading(progress: 0, bytesPerSec: 0)

        var req = URLRequest(url: url)
        req.setValue("openmp-server-launcher", forHTTPHeaderField: "User-Agent")
        let cfg = URLSessionConfiguration.default
        let s = URLSession(configuration: cfg, delegate: self, delegateQueue: nil)
        session = s
        s.downloadTask(with: req).resume()
    }

    // Unzip the downloaded archive, locate the .app, then hand off to the swap
    // helper. Runs off the main actor for the file work, reporting phase back.
    private func install(downloaded tmp: URL) {
        Task { @MainActor in phase = .unpacking }
        do {
            let fm = FileManager.default
            let work = fm.temporaryDirectory
                .appendingPathComponent("omp-update-\(UUID().uuidString)", isDirectory: true)
            try fm.createDirectory(at: work, withIntermediateDirectories: true)
            let zip = work.appendingPathComponent("update.zip")
            try? fm.removeItem(at: zip)
            try fm.moveItem(at: tmp, to: zip)

            // Unzip with ditto (handles macOS bundle metadata cleanly).
            try run("/usr/bin/ditto", ["-x", "-k", zip.path, work.path])

            // Find the .app bundle in the extracted tree (top level first).
            guard let newApp = Self.findApp(in: work, fm: fm) else {
                throw UpdateError("The downloaded update didn't contain an app bundle.")
            }

            Task { @MainActor in phase = .installing }
            let target = Bundle.main.bundleURL          // replace where we run from
            try Self.spawnSwapHelper(newApp: newApp, target: target, work: work)

            // Quit so the detached helper can swap the bundle and relaunch us.
            Task { @MainActor in NSApp.terminate(nil) }
        } catch {
            Task { @MainActor in
                self.phase = .failed((error as? UpdateError)?.message ?? error.localizedDescription)
            }
        }
    }

    // MARK: Helpers

    private struct UpdateError: Error { let message: String; init(_ m: String) { message = m } }

    private static func findApp(in dir: URL, fm: FileManager) -> URL? {
        guard let items = try? fm.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return nil }
        if let top = items.first(where: { $0.pathExtension == "app" }) { return top }
        // One level deeper (some zips nest the app in a folder).
        for d in items where (try? d.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true {
            if let nested = (try? fm.contentsOfDirectory(at: d, includingPropertiesForKeys: nil))?
                .first(where: { $0.pathExtension == "app" }) { return nested }
        }
        return nil
    }

    @discardableResult
    private func run(_ launchPath: String, _ args: [String]) throws -> String {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: launchPath)
        p.arguments = args
        let pipe = Pipe()
        p.standardOutput = pipe; p.standardError = pipe
        try p.run()
        p.waitUntilExit()
        let out = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        if p.terminationStatus != 0 {
            throw UpdateError("Update step failed (\(launchPath)): \(out)")
        }
        return out
    }

    // Write and launch a detached helper that waits for this app to quit, swaps
    // the new bundle over the old one, ad-hoc re-signs it, strips quarantine, and
    // relaunches. Detached via setsid so it outlives our process.
    private static func spawnSwapHelper(newApp: URL, target: URL, work: URL) throws {
        let pid = ProcessInfo.processInfo.processIdentifier
        let script = work.appendingPathComponent("swap.sh")
        // Quote paths for safe interpolation into the shell script.
        func q(_ u: URL) -> String { "'" + u.path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

        let body = """
        #!/bin/bash
        set -e
        NEW=\(q(newApp))
        TARGET=\(q(target))
        WORK=\(q(work))

        # Wait (max ~30s) for the running app to exit before swapping.
        for i in $(seq 1 300); do
          if ! kill -0 \(pid) 2>/dev/null; then break; fi
          sleep 0.1
        done

        # Swap: replace the target bundle's contents with the new one.
        rsync -a --delete "$NEW/" "$TARGET/" 2>/dev/null || {
          rm -rf "$TARGET"
          cp -R "$NEW" "$TARGET"
        }

        # Ad-hoc re-sign and clear the download quarantine so Gatekeeper allows it.
        codesign --force --deep --sign - "$TARGET" 2>/dev/null || true
        xattr -dr com.apple.quarantine "$TARGET" 2>/dev/null || true

        # Relaunch the updated app, then clean up.
        open "$TARGET"
        rm -rf "$WORK"
        """
        try body.write(to: script, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)

        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/setsid")
        p.arguments = ["/bin/bash", script.path]
        do { try p.run() } catch {
            // setsid may be absent on some systems; fall back to nohup-style detach.
            let p2 = Process()
            p2.executableURL = URL(fileURLWithPath: "/bin/bash")
            p2.arguments = ["-c", "nohup /bin/bash \(q(script)) >/dev/null 2>&1 &"]
            try p2.run()
        }
    }

    /// Compare dotted versions ("1.10.0" > "1.9.0"). Non-numeric chars (a
    /// leading "v", pre-release suffixes) are stripped per segment.
    nonisolated static func compareVersions(_ a: String, _ b: String) -> Int {
        let as_ = a.split(separator: ".").map(String.init)
        let bs_ = b.split(separator: ".").map(String.init)
        let n = max(as_.count, bs_.count)
        func seg(_ s: [String], _ i: Int) -> Int {
            guard i < s.count else { return 0 }
            let digits = s[i].filter(\.isNumber)
            return Int(digits) ?? 0
        }
        for i in 0..<n {
            let x = seg(as_, i), y = seg(bs_, i)
            if x != y { return x < y ? -1 : 1 }
        }
        return 0
    }
}

// MARK: URLSession download delegate (progress + speed)

extension Updater: URLSessionDownloadDelegate {
    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didWriteData bytesWritten: Int64, totalBytesWritten: Int64,
                                totalBytesExpectedToWrite: Int64) {
        let total = totalBytesExpectedToWrite
        Task { @MainActor in
            let elapsed = max(Date().timeIntervalSince(downloadStart), 0.001)
            let speed = Double(totalBytesWritten) / elapsed
            let progress = total > 0 ? Double(totalBytesWritten) / Double(total) : 0
            phase = .downloading(progress: progress, bytesPerSec: speed)
        }
    }

    nonisolated func urlSession(_ session: URLSession, downloadTask: URLSessionDownloadTask,
                                didFinishDownloadingTo location: URL) {
        // The temp file is removed when this delegate returns, so copy it now.
        let fm = FileManager.default
        let keep = fm.temporaryDirectory.appendingPathComponent("omp-dl-\(UUID().uuidString).zip")
        do { try fm.copyItem(at: location, to: keep) }
        catch { Task { @MainActor in phase = .failed("Couldn't save the download.") }; return }
        Task { @MainActor in install(downloaded: keep) }
    }

    nonisolated func urlSession(_ session: URLSession, task: URLSessionTask,
                                didCompleteWithError error: Error?) {
        if let error {
            Task { @MainActor in phase = .failed(error.localizedDescription) }
        }
    }
}
