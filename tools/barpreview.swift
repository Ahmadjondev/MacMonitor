import AppKit

// Renders the menu-bar speed image (with simulated bar background) to inspect
// vertical centering / sizing / padding. Compile with ../Sources/Core.swift.

@main
struct BarPreview {
    static func main() {
        let height = NSStatusBar.system.thickness
        let barFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
        let width = ceil(NSAttributedString(string: "↓ 88.8 Mb/s", attributes: [.font: barFont]).size().width) + 2
        print("thickness=\(height) width=\(width)")

        let para = NSMutableParagraphStyle()
        para.alignment = .center
        para.maximumLineHeight = 10.5
        para.minimumLineHeight = 10.5
        let str = NSAttributedString(
            string: "↓ \(speedStr(6.4e6/8))\n↑ \(speedStr(136e3/8))",
            attributes: [.font: barFont, .foregroundColor: NSColor.white, .paragraphStyle: para])
        let textH = str.size().height

        let scale: CGFloat = 6
        let img = NSImage(size: NSSize(width: width * scale, height: height * scale))
        img.lockFocus()
        NSColor(calibratedWhite: 0.12, alpha: 1).setFill()
        NSRect(x: 0, y: 0, width: width * scale, height: height * scale).fill()
        NSGraphicsContext.current!.cgContext.scaleBy(x: scale, y: scale)
        str.draw(in: NSRect(x: 0, y: (height - textH) / 2, width: width, height: textH))
        img.unlockFocus()

        if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "bar.png"))
            print("textHeight=\(textH)")
        }
    }
}
