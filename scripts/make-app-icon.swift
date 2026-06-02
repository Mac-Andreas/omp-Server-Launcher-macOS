// Generates the app icon (1024×1024) in open.mp's visual theme — dark navy
// background with a warm amber accent — WITHOUT copying their logo. The mark is
// a server-rack (this app manages servers) with an open.mp-style amber "open
// ring" (a broken circle, evoking the lowercase "o" / open paren) wrapping a
// play glyph. Output: a macOS-style rounded-rect icon PNG.
import AppKit

let S: CGFloat = 1024
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "assets/icon_1024x1024.png"

let rep = NSBitmapImageRep(
    bitmapDataPlanes: nil, pixelsWide: Int(S), pixelsHigh: Int(S),
    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
let ctx = NSGraphicsContext(bitmapImageRep: rep)!
NSGraphicsContext.current = ctx
let c = ctx.cgContext

func col(_ r: Int, _ g: Int, _ b: Int, _ a: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r)/255, green: CGFloat(g)/255, blue: CGFloat(b)/255, alpha: a)
}

// Purple theme matching the app accent (Theme.accent = #7B5CFF), on a dark
// slate-violet background.
let navyTop = col(0x2E, 0x29, 0x46)   // dark slate-violet
let navyBot = col(0x14, 0x12, 0x20)   // near-black violet
let amber    = col(0x7B, 0x5C, 0xFF)  // app purple accent
let amberHi  = col(0xA9, 0x93, 0xFF)  // lighter purple
let panel    = col(0x3C, 0x3A, 0x5E)  // server-rack panel (violet-tinted)
let panelEdge = col(0x52, 0x4E, 0x80)

// 1. Rounded-rect background with a vertical gradient (macOS superellipse-ish).
let corner: CGFloat = S * 0.225
let bgRect = CGRect(x: 0, y: 0, width: S, height: S)
let bgPath = CGPath(roundedRect: bgRect, cornerWidth: corner, cornerHeight: corner, transform: nil)
c.addPath(bgPath); c.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [navyTop, navyBot] as CFArray, locations: [0, 1])!
c.drawLinearGradient(grad, start: CGPoint(x: 0, y: S), end: CGPoint(x: 0, y: 0), options: [])

// Subtle top sheen.
c.setFillColor(col(0xFF, 0xFF, 0xFF, 0.04))
c.fill(CGRect(x: 0, y: S*0.62, width: S, height: S*0.38))

// 2. Two server-rack bars (rounded), centred upper area.
func roundRect(_ r: CGRect, _ rad: CGFloat, _ fill: CGColor, stroke: CGColor? = nil, lw: CGFloat = 0) {
    let p = CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
    c.addPath(p); c.setFillColor(fill); c.fillPath()
    if let stroke {
        c.addPath(p); c.setStrokeColor(stroke); c.setLineWidth(lw); c.strokePath()
    }
}

let barW = S * 0.52
let barH = S * 0.135
let barX = (S - barW) / 2
let barRad = barH * 0.28
// Bar 1 (upper) and Bar 2 (lower).
let bar1Y = S * 0.585
let bar2Y = S * 0.425
for by in [bar1Y, bar2Y] {
    roundRect(CGRect(x: barX, y: by, width: barW, height: barH), barRad, panel,
              stroke: panelEdge, lw: S*0.004)
    // Amber status LED on the left of each bar.
    let led = barH * 0.30
    c.setFillColor(amber)
    c.fillEllipse(in: CGRect(x: barX + barH*0.42, y: by + barH/2 - led/2, width: led, height: led))
    // Two slot lines on the right.
    c.setFillColor(col(0x28, 0x26, 0x42))
    let slotW = barW * 0.26, slotH = barH * 0.12
    let slotX = barX + barW - slotW - barH*0.42
    roundRect(CGRect(x: slotX, y: by + barH*0.34, width: slotW, height: slotH), slotH/2, col(0x28,0x26,0x42))
    roundRect(CGRect(x: slotX, y: by + barH*0.54, width: slotW, height: slotH), slotH/2, col(0x28,0x26,0x42))
}

// 3. open.mp "open ring" — a thick amber arc (broken circle) lower-centre,
//    with a play triangle inside. Evokes the open.mp "o" without copying it.
let ringC = CGPoint(x: S/2, y: S*0.285)
let ringR = S * 0.135
c.setLineWidth(S * 0.052)
c.setLineCap(.round)
c.setStrokeColor(amber)
// Arc with a gap at the lower-right (the "opening").
c.addArc(center: ringC, radius: ringR,
         startAngle: .pi * -0.35, endAngle: .pi * 1.15, clockwise: false)
c.strokePath()

// Play triangle inside the ring.
let pr = ringR * 0.62
c.setFillColor(amberHi)
c.move(to: CGPoint(x: ringC.x - pr*0.5, y: ringC.y + pr*0.72))
c.addLine(to: CGPoint(x: ringC.x - pr*0.5, y: ringC.y - pr*0.72))
c.addLine(to: CGPoint(x: ringC.x + pr*0.78, y: ringC.y))
c.closePath()
c.fillPath()

// Write PNG.
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("encode failed\n".data(using: .utf8)!); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("wrote \(outPath)")
