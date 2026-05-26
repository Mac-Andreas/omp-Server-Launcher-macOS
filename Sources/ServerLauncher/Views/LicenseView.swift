// License tab: shows the bundled LICENSE.txt (GPLv3). Read from the app
// bundle's Resources; falls back to the repo copy when run unbundled.
import SwiftUI

struct LicenseView: View {
    @State private var text: String = "Loading license…"

    var body: some View {
        ScrollView([.vertical, .horizontal]) {
            Text(text)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(Theme.textDim)
                .textSelection(.enabled)
                .lineSpacing(2)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, 18)
                .padding(.vertical, 16)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onAppear(perform: load)
    }

    private func load() {
        for bundle in [Bundle.main, Bundle.module] {
            if let url = bundle.url(forResource: "LICENSE", withExtension: "txt"),
               let s = try? String(contentsOf: url, encoding: .utf8) {
                text = s; return
            }
        }
        // Unbundled fallback: repo LICENSE.txt one level up from swift-launcher.
        let candidates = [
            "../LICENSE.txt",
            "LICENSE.txt",
        ]
        for c in candidates {
            if let s = try? String(contentsOfFile: c, encoding: .utf8) { text = s; return }
        }
        text = "LICENSE.txt not found. This software is licensed under the GNU GPL v3 or later."
    }
}
