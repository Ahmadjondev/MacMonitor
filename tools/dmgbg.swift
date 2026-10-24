import AppKit

// Renders the drag-to-install DMG background at EXACTLY 640x400 px (1x, so Finder
// shows it 1:1 in a 640x400-point window). Usage: dmgbg <out.png>
// Icon slots (set by release.sh): app at (160,200), Applications at (480,200).

let W = 640, H = 400
let WF = CGFloat(W), HF = CGFloat(H)

let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: W, pixelsHigh: H,
                          bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true,
                          isPlanar: false, colorSpaceName: .deviceRGB,
                          bytesPerRow: 0, bitsPerPixel: 0)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
let ctx = NSGraphicsContext.current!.cgContext
let cs = CGColorSpaceCreateDeviceRGB()

// dark diagonal gradient background
let grad = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.08, green: 0.08, blue: 0.11, alpha: 1),
    CGColor(red: 0.04, green: 0.04, blue: 0.06, alpha: 1)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(grad, start: CGPoint(x: 0, y: HF), end: CGPoint(x: WF, y: 0), options: [])

// NSBitmap context origin is bottom-left; Finder icon coords are top-left.
func flip(_ yTop: CGFloat) -> CGFloat { HF - yTop }

// gradient arrow at the icon row (yTop = 200), between the two icon slots
let ay = flip(200)
ctx.setLineCap(.round); ctx.setLineJoin(.round); ctx.setLineWidth(7)
ctx.saveGState()
ctx.move(to: CGPoint(x: 250, y: ay))
ctx.addLine(to: CGPoint(x: 395, y: ay))
ctx.addLine(to: CGPoint(x: 378, y: ay + 14))
ctx.move(to: CGPoint(x: 395, y: ay))
ctx.addLine(to: CGPoint(x: 378, y: ay - 14))
ctx.replacePathWithStrokedPath()
ctx.clip()
let ag = CGGradient(colorsSpace: cs, colors: [
    CGColor(red: 0.486, green: 0.424, blue: 0.941, alpha: 0.95),
    CGColor(red: 0.176, green: 0.831, blue: 0.749, alpha: 0.95)
] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(ag, start: CGPoint(x: 250, y: ay), end: CGPoint(x: 395, y: ay), options: [])
ctx.restoreGState()

func draw(_ s: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, yTop: CGFloat) {
    let p = NSMutableParagraphStyle(); p.alignment = .center
    let str = NSAttributedString(string: s, attributes: [
        .font: NSFont.systemFont(ofSize: size, weight: weight),
        .foregroundColor: color, .paragraphStyle: p])
    let h = str.size().height
    str.draw(in: NSRect(x: 0, y: flip(yTop) - h / 2, width: WF, height: h))
}
draw("Mac Monitor", size: 30, weight: .bold, color: .white, yTop: 64)
draw("Drag the app into the Applications folder to install",
     size: 13, weight: .regular, color: NSColor(white: 0.62, alpha: 1), yTop: 98)

NSGraphicsContext.restoreGraphicsState()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmg-background.png"
if let png = rep.representation(using: .png, properties: [:]) {
    try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out) (\(W)x\(H))")
}
