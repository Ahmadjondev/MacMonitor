import SwiftUI
import AppKit

@main
struct InsightsPreview {
    static func main() {
        for i in 0..<90 {
            let p = Double(i) / 7.0
            History.shared.add(Sample(t: Double(i), ram: 62 + 14 * sin(p),
                                      cpu: 25 + 20 * sin(p * 1.6), disk: 36,
                                      down: 6e6, up: 1e5, pressure: i % 30 == 0 ? 4 : 1))
        }
        let stats = Stats()
        var m = MemInfo(); m.total = 24e9; m.used = 17e9; m.freePercent = (1 - 17.0/24.0) * 100
        stats.mem = m; stats.cpu = 31
        let view = InsightsView(stats: stats).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "insights.png"
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out)")
        } else { print("render failed") }
    }
}
