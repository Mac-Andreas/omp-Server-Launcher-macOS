// Best-effort auto-detection of open.mp server binaries on disk so the Setup
// tab can suggest "omp-server (version) detected in <path>" and let the user
// add it with one click.
//
// We scan a few likely roots under the user's home (Documents, Desktop,
// Downloads, and home itself) to a limited depth — a full-disk crawl would be
// slow and needs permissions we don't want to require.
import Foundation

struct DetectedServer: Identifiable, Equatable {
    var id: String { binaryPath }
    var binaryPath: String
    var platform: ServerPlatform
    var version: String?   // parsed from the binary if available

    /// Folder containing the binary.
    var folder: String { (binaryPath as NSString).deletingLastPathComponent }
}

enum ServerDetect {
    /// Roots we scan, shallowly. Home itself is included at a shallower depth.
    private static var scanRoots: [(url: URL, depth: Int)] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        let docs = home.appendingPathComponent("Documents")
        return [
            (docs, 4),
            (home.appendingPathComponent("Desktop"), 3),
            (home.appendingPathComponent("Downloads"), 3),
            (home, 2),
        ]
    }

    /// Scan for binaries of the given platform. Runs off the main thread by the
    /// caller. Returns unique binary paths.
    static func scan(platform: ServerPlatform) -> [DetectedServer] {
        let fm = FileManager.default
        let target = platform.binaryName
        var found: [String: DetectedServer] = [:]

        for root in scanRoots {
            guard fm.fileExists(atPath: root.url.path) else { continue }
            let baseDepth = root.url.pathComponents.count
            guard let en = fm.enumerator(
                at: root.url,
                includingPropertiesForKeys: [.isRegularFileKey],
                options: [.skipsHiddenFiles, .skipsPackageDescendants]
            ) else { continue }

            for case let url as URL in en {
                // Prune deep trees to keep the scan fast.
                if url.pathComponents.count - baseDepth > root.depth {
                    en.skipDescendants()
                    continue
                }
                guard url.lastPathComponent == target else { continue }
                // For macOS, require it to be executable (the Windows .exe won't be).
                if platform == .macos && !fm.isExecutableFile(atPath: url.path) { continue }
                let std = (url.path as NSString).standardizingPath
                if found[std] == nil {
                    found[std] = DetectedServer(
                        binaryPath: std,
                        platform: platform,
                        version: version(of: std, platform: platform))
                }
            }
        }
        return Array(found.values).sorted { $0.binaryPath < $1.binaryPath }
    }

    /// Best-effort version, WITHOUT executing the server (omp-server has no
    /// --version flag; it only prints the version at runtime startup, and the
    /// Windows .exe shouldn't be run at all during a scan). We instead look for
    /// an x.y.z[.w] version token in a sibling README / version file if one
    /// exists; otherwise nil and the UI just shows the path.
    private static func version(of path: String, platform: ServerPlatform) -> String? {
        let folder = (path as NSString).deletingLastPathComponent
        let candidates = ["version.txt", "VERSION", "README.md", "README.txt"]
        for name in candidates {
            let p = (folder as NSString).appendingPathComponent(name)
            guard let text = try? String(contentsOfFile: p, encoding: .utf8) else { continue }
            if let m = text.range(of: #"\d+\.\d+\.\d+(\.\d+)?"#, options: .regularExpression) {
                return String(text[m])
            }
        }
        return nil
    }

    /// Format a path the way the UI wants to show it: keep the user's home
    /// prefix but trim nothing — e.g. /Users/Name/Documents/.../omp-server.
    /// (Kept as a helper in case we want to shorten later.)
    static func displayPath(_ path: String) -> String { path }

    // MARK: Folder import detection

    /// The OS a server binary targets, by its file format. `linux` is recognised
    /// so we can reject it with a clear message (we only support macOS/Windows).
    enum BinaryOS: Equatable { case macos, windows, linux, unknown }

    /// Result of scanning a folder the user picked to import.
    struct FolderScan: Equatable {
        var binaryPath: String?   // the omp-server / omp-server.exe found
        var os: BinaryOS          // detected from the binary's magic bytes
    }

    /// Scan a picked folder (shallowly) for an open.mp server binary and detect
    /// which OS it targets. Looks for "omp-server" / "omp-server.exe" at the
    /// folder root first, then one level down.
    static func scanImportFolder(_ folder: String) -> FolderScan {
        let fm = FileManager.default
        let root = URL(fileURLWithPath: folder)
        // Search the root and its immediate subfolders.
        var dirs = [root]
        if let subs = try? fm.contentsOfDirectory(at: root, includingPropertiesForKeys: [.isDirectoryKey],
                                                  options: [.skipsHiddenFiles]) {
            dirs += subs.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true }
        }
        for dir in dirs {
            for name in ["omp-server.exe", "omp-server"] {
                let candidate = dir.appendingPathComponent(name)
                if fm.fileExists(atPath: candidate.path) {
                    return FolderScan(binaryPath: candidate.path, os: binaryOS(of: candidate.path))
                }
            }
        }
        return FolderScan(binaryPath: nil, os: .unknown)
    }

    /// Detect a binary's target OS from its leading magic bytes (Mach-O = macOS,
    /// PE/"MZ" = Windows, ELF = Linux).
    static func binaryOS(of path: String) -> BinaryOS {
        guard let fh = FileHandle(forReadingAtPath: path) else { return .unknown }
        defer { try? fh.close() }
        guard let data = try? fh.read(upToCount: 4), data.count == 4 else { return .unknown }
        let b = [UInt8](data)
        // PE executable: "MZ"
        if b[0] == 0x4D && b[1] == 0x5A { return .windows }
        // ELF: 0x7F 'E' 'L' 'F'
        if b[0] == 0x7F && b[1] == 0x45 && b[2] == 0x4C && b[3] == 0x46 { return .linux }
        // Mach-O (thin or fat), both endiannesses.
        let magic = UInt32(b[0]) << 24 | UInt32(b[1]) << 16 | UInt32(b[2]) << 8 | UInt32(b[3])
        let machO: Set<UInt32> = [0xFEEDFACE, 0xFEEDFACF, 0xCEFAEDFE, 0xCFFAEDFE, 0xCAFEBABE, 0xBEBAFECA]
        if machO.contains(magic) { return .macos }
        return .unknown
    }
}
