import SwiftUI
import AppKit

// Renders DashboardView with sample data to a PNG so the design can be reviewed.
// Compile together with ../Sources/Core.swift, then run: preview <out.png>

@main
struct Preview {
    static func main() {
        let stats = Stats()
        var m = MemInfo()
        m.total = 23.08 * 1_073_741_824
        m.used = 13.82 * 1_073_741_824
        m.wired = 3.2 * 1_073_741_824
        m.compressed = 1.9 * 1_073_741_824
        m.app = m.used - m.wired - m.compressed
        m.cached = 4.1 * 1_073_741_824
        m.swapUsed = 1.9 * 1_073_741_824
        m.swapTotal = 3.0 * 1_073_741_824
        m.freePercent = (1 - m.used / m.total) * 100
        stats.mem = m
        stats.pressure = 1
        stats.cpu = 7.7
        stats.downSpeed = 6.4e6 / 8   // ~6.4 Mb/s
        stats.upSpeed = 136e3 / 8     // ~136 kb/s
        stats.totalRx = 42.7e9; stats.totalTx = 8.3e9
        stats.coreUsage = [22, 8, 41, 15, 63, 12, 30, 9, 18, 6]
        stats.localIP = "192.168.1.42"
        var disk = DiskInfo()
        disk.total = 994.6e9; disk.used = 359.6e9; disk.name = "Macintosh HD"
        disk.readSpeed = 24e6; disk.writeSpeed = 3.1e6
        stats.disk = disk
        stats.cpuHistory = [42, 30, 22, 18, 12, 9, 7, 6, 8, 5, 4, 3, 2, 3, 2, 1, 2, 1, 1, 2, 1, 1, 1, 1, 8, 8]
        stats.top = [
            Proc(name: "Google Chrome", bytes: 2.9 * 1_073_741_824),
            Proc(name: "Figma", bytes: 1.7 * 1_073_741_824),
            Proc(name: "Code", bytes: 0.9 * 1_073_741_824),
            Proc(name: "Telegram", bytes: 0.7 * 1_073_741_824),
            Proc(name: "WindowServer", bytes: 0.3 * 1_073_741_824),
        ]

        if CommandLine.arguments.count > 2 { Loc.shared.lang = CommandLine.arguments[2] }
        for i in 0..<60 {
            let phase = Double(i) / 6.0
            History.shared.add(Sample(t: Double(i), ram: 60 + 12 * sin(phase),
                                      cpu: 20 + 18 * sin(phase * 1.7), disk: 36,
                                      down: 6e6, up: 1e5, pressure: (i % 17 == 0) ? 2 : 1))
        }
        let view = DashboardView(stats: stats, settings: AppSettings(), onClean: {}, onQuit: {}, onSettings: {}, onInsights: {}, onWindow: {})
            .environment(\.colorScheme, .dark)

        let renderer = ImageRenderer(content: view)
        renderer.scale = 2

        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "preview.png"
        if let img = renderer.nsImage,
           let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
        } else {
            print("render failed")
        }
    }
}
