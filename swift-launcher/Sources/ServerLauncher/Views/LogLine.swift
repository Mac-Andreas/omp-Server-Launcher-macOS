// One server-log line. A leading "[HH:MM:SS]" timestamp is rendered in a
// smaller, dimmer font than the message so logs scan more easily.
import SwiftUI

struct LogLine: View {
    let line: String
    var size: CGFloat = 11

    var body: some View {
        let (stamp, rest) = Self.split(line)
        return (
            Text(stamp)
                .font(.system(size: max(size - 3, 8), weight: .regular, design: .monospaced))
                .foregroundStyle(Theme.textDim)
            + Text(rest)
                .font(.system(size: size, weight: .regular, design: .monospaced))
                .foregroundStyle(Self.color(rest))
        )
        .textSelection(.enabled)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Returns (timestamp-with-trailing-space, remainder). Empty stamp if the
    /// line doesn't begin with a "[...]" token.
    static func split(_ line: String) -> (String, String) {
        guard line.hasPrefix("["), let close = line.firstIndex(of: "]") else {
            return ("", line)
        }
        let after = line.index(after: close)
        var stamp = String(line[..<after])
        var rest = String(line[after...])
        if rest.hasPrefix(" ") { stamp += " "; rest.removeFirst() }
        return (stamp, rest)
    }

    static func color(_ text: String) -> Color {
        let l = text.lowercased()
        if l.contains("error") { return Theme.bad }
        if l.contains("warning") { return Theme.warn }
        if text.hasPrefix("—") { return Theme.textDim }
        return Theme.text
    }
}
