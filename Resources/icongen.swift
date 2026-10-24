import AppKit

// Renders the Mac Monitor app logo: a gradient gauge ring with an activity
// sparkline inside, on a dark squircle. Usage: icongen <output.png>

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
let ctx = NSGraphicsContext.current!.cgContext
let c = CGPoint(x: S / 2, y: S / 2)

func rounded(_ r: CGRect, _ rad: CGFloat) -> CGPath {
    CGPath(roundedRect: r, cornerWidth: rad, cornerHeight: rad, transform: nil)
}
func lerp(_ a: (CGFloat, CGFloat, CGFloat), _ b: (CGFloat, CGFloat, CGFloat), _ t: CGFloat) -> (CGFloat, CGFloat, CGFloat) {
    (a.0 + (b.0 - a.0) * t, a.1 + (b.1 - a.1) * t, a.2 + (b.2 - a.2) * t)
}
let purple: (CGFloat, CGFloat, CGFloat) = (0.486, 0.424, 0.941)
let blue:   (CGFloat, CGFloat, CGFloat) = (0.231, 0.510, 0.965)
let teal:   (CGFloat, CGFloat, CGFloat) = (0.176, 0.831, 0.749)
func gradColor(_ t: CGFloat) -> CGColor {
    let v = t < 0.5 ? lerp(purple, blue, t / 0.5) : lerp(blue, teal, (t - 0.5) / 0.5)
    return CGColor(red: v.0, green: v.1, blue: v.2, alpha: 1)
}

// --- Dark squircle background with subtle gradient ---
let m: CGFloat = 96
let bg = CGRect(x: m, y: m, width: S - 2 * m, height: S - 2 * m)
ctx.saveGState()
ctx.addPath(rounded(bg, (S - 2 * m) * 0.2237))
ctx.clip()
let cs = CGColorSpaceCreateDeviceRGB()
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.13, green: 0.13, blue: 0.18, alpha: 1),
    CGColor(red: 0.06, green: 0.06, blue: 0.09, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: bg.minX, y: bg.maxY),
                       end: CGPoint(x: bg.maxX, y: bg.minY), options: [])
ctx.restoreGState()

// --- Gauge track (full dark ring) ---
let R: CGFloat = 250, W: CGFloat = 62
ctx.setLineCap(.round)
ctx.setLineWidth(W)
ctx.setStrokeColor(CGColor(red: 0.18, green: 0.18, blue: 0.24, alpha: 1))
ctx.beginPath()
ctx.addArc(center: c, radius: R, startAngle: 0, endAngle: 2 * .pi, clockwise: false)
ctx.strokePath()

// --- Gauge fill (gradient arc, ~78%, from top clockwise) ---
let segs = 90
let sweep: CGFloat = 0.78 * 2 * .pi
let start = CGFloat.pi / 2
for i in 0..<segs {
    let t = CGFloat(i) / CGFloat(segs - 1)
    let a1 = start - (CGFloat(i) / CGFloat(segs)) * sweep
    let a2 = start - (CGFloat(i + 1) / CGFloat(segs)) * sweep
    ctx.setLineWidth(W)
    ctx.setStrokeColor(gradColor(t))
    ctx.beginPath()
    ctx.addArc(center: c, radius: R, startAngle: a1, endAngle: a2, clockwise: true)
    ctx.strokePath()
}

// --- Activity sparkline (white) inside the ring ---
ctx.setLineWidth(28)
ctx.setLineJoin(.round)
ctx.setLineCap(.round)
ctx.setStrokeColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
let pts: [(CGFloat, CGFloat)] = [(-150, -18), (-88, 48), (-30, -28), (32, 72), (94, -40), (150, 18)]
ctx.beginPath()
for (idx, p) in pts.enumerated() {
    let pt = CGPoint(x: c.x + p.0, y: c.y + p.1)
    if idx == 0 { ctx.move(to: pt) } else { ctx.addLine(to: pt) }
}
ctx.strokePath()

img.unlockFocus()

let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
if let tiff = img.tiffRepresentation,
   let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: outPath))
    print("wrote \(outPath)")
} else {
    print("failed")
}
