// GitHub release update check. Queries releases/latest for the configured repo
// and reports whether a newer tag exists. Never blocks the UI.
//
// Ported from Updater.cpp. v1.0 does the CHECK only (shows a button linking to
// the release page); in-app download/install is deferred (see STATUS.md).
import Foundation
import Combine

@MainActor
final class Updater: ObservableObject {
    struct Result: Equatable {
        var available: Bool
        var latestVersion: String
        var htmlURL: URL?
    }

    @Published private(set) var result = Result(available: false, latestVersion: "", htmlURL: nil)

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
            let newer = Self.compareVersions(AppInfo.version, tag) < 0
            Task { @MainActor in
                self?.result = Result(available: newer, latestVersion: tag, htmlURL: html)
            }
        }.resume()
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
