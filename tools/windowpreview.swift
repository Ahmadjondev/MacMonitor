import SwiftUI
import AppKit

@main
struct WindowPreview {
    static func main() {
        for i in 0..<40 { History.shared.add(Sample(t: Double(i), ram: 60 + 10*sin(Double(i)/5), cpu: 20, disk: 36, down: 6e6, up: 1e5, pressure: 1)) }
        let stats = Stats()
        var m = MemInfo(); m.total = 24e9; m.used = 17e9; m.wired = 3.2e9; m.compressed = 1.9e9
        m.app = m.used - m.wired - m.compressed; m.cached = 4.1e9; m.swapUsed = 1.9e9; m.swapTotal = 3e9
        m.freePercent = (1 - m.used/m.total)*100
        stats.mem = m; stats.cpu = 12
        stats.downSpeed = 6.4e6/8; stats.upSpeed = 136e3/8; stats.localIP = "192.168.1.42"
        var d = DiskInfo(); d.total = 994.6e9; d.used = 359.6e9; d.name = "Macintosh HD"; d.readSpeed = 24e6; d.writeSpeed = 3.1e6
        stats.disk = d
        stats.top = [Proc(name:"Google Chrome",bytes:2.9e9),Proc(name:"claude",bytes:1.7e9),Proc(name:"Telegram",bytes:1.1e9)]

        let view = WindowDashboard(stats: stats, settings: AppSettings()).frame(width: 560, height: 760).environment(\.colorScheme, .dark)
        let r = ImageRenderer(content: view); r.scale = 2
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "win.png"
        if let img = r.nsImage, let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) { try? png.write(to: URL(fileURLWithPath: out)); print("wrote \(out)") }
    }
}
