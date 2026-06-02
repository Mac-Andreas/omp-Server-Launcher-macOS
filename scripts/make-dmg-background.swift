// Renders the DMG background: a dark canvas with a curved arrow pointing from
// the app icon (left) toward the Applications folder (right) and a caption.
// Output: a @1x and @2x PNG combined into a multi-resolution TIFF the Finder
// can use. Usage: swift make-dmg-background.swift <out.png>
import AppKit

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"

// Logical canvas size (points). The Finder window content is sized to match.
let W = 640, H = 400

func render(scale: Int) -> NSBitmapImageRep {
    let pxW = W * scale, pxH = H * scale
    let rep = NSBitmapImageRep(
        bitmapDataPlanes: nil, pixelsWide: pxW, pixelsHigh: pxH,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    rep.size = NSSize(width: W, height: H)

    let ctx = NSGraphicsContext(bitmapImageRep: rep)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = ctx
    let c = ctx.cgContext

    // Soft LIGHT gradient (cool white → light lavender-grey). Light enough that
    // Finder's dark icon labels stay legible, so no label plates are needed.
    let cs = CGColorSpaceCreateDeviceRGB()
    let gTop = CGColor(srgbRed: 0xFB/255, green: 0xFB/255, blue: 0xFE/255, alpha: 1) // near white
    let gBot = CGColor(srgbRed: 0xE9/255, green: 0xEA/255, blue: 0xF2/255, alpha: 1) // light lavender-grey
    let grad = CGGradient(colorsSpace: cs, colors: [gTop, gBot] as CFArray, locations: [0, 1])!
    c.drawLinearGradient(grad, start: CGPoint(x: 0, y: CGFloat(H)), end: .zero, options: [])

    // Text helper (CoreGraphics y is bottom-up).
    func draw(_ s: String, _ size: CGFloat, _ y: CGFloat, _ color: NSColor, bold: Bool) {
        let style = NSMutableParagraphStyle(); style.alignment = .center
        let font = bold ? NSFont.boldSystemFont(ofSize: size) : NSFont.systemFont(ofSize: size)
        let attrs: [NSAttributedString.Key: Any] = [
            .font: font, .foregroundColor: color, .paragraphStyle: style]
        NSAttributedString(string: s, attributes: attrs)
            .draw(in: NSRect(x: 0, y: y, width: CGFloat(W), height: size + 8))
    }

    let textDark = NSColor(srgbRed: 0x20/255, green: 0x22/255, blue: 0x28/255, alpha: 1)
    let textGrey = NSColor(srgbRed: 0x8A/255, green: 0x90/255, blue: 0x9A/255, alpha: 1)

    // Icon row centers (CG y bottom-up). Must match the AppleScript positions.
    let appCenter  = CGPoint(x: 160, y: 200)
    let appsCenter = CGPoint(x: 480, y: 200)

    // Simple straight grey arrow between the two icons.
    let grey = CGColor(srgbRed: 0xB0/255, green: 0xB4/255, blue: 0xBC/255, alpha: 1)
    c.setStrokeColor(grey)
    c.setFillColor(grey)
    c.setLineWidth(4)
    c.setLineCap(.round)
    let start = CGPoint(x: appCenter.x + 80, y: appCenter.y)
    let end   = CGPoint(x: appsCenter.x - 92, y: appCenter.y)
    c.move(to: start)
    c.addLine(to: end)
    c.strokePath()
    let ah: CGFloat = 14
    c.move(to: CGPoint(x: end.x + ah, y: end.y))            // tip
    c.addLine(to: CGPoint(x: end.x, y: end.y + ah * 0.62))
    c.addLine(to: CGPoint(x: end.x, y: end.y - ah * 0.62))
    c.closePath()
    c.fillPath()

    // Hint at the very top (above the Read Me icon).
    draw("Trouble opening the app? Open “Read Me.txt”.", 11, 372, textGrey, bold: false)

    // Caption at the bottom.
    draw("Drag the app into Applications", 17, 56, textDark, bold: true)
    draw("Then eject this disk image.", 11, 36, textGrey, bold: false)

    NSGraphicsContext.restoreGraphicsState()
    return rep
}

// Build a multi-page TIFF (1x + 2x) so Finder picks the right resolution.
let rep1 = render(scale: 1)
let rep2 = render(scale: 2)
guard let data = NSBitmapImageRep.representationOfImageReps(
    in: [rep1, rep2], using: .tiff, properties: [:]) else {
    FileHandle.standardError.write("failed to encode\n".data(using: .utf8)!)
    exit(1)
}
do {
    try data.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} catch {
    FileHandle.standardError.write("write failed: \(error)\n".data(using: .utf8)!)
    exit(1)
}
