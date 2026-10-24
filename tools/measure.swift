import SwiftUI
import AppKit

@main
struct Measure {
    static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)

        let stats = Stats()
        var m = MemInfo()
        m.total = 24 * 1_073_741_824
        m.used = 18.5 * 1_073_741_824
        m.wired = 3 * 1_073_741_824
        m.compressed = 1.9 * 1_073_741_824
        m.freePercent = (1 - m.used / m.total) * 100
        stats.mem = m
        stats.cpuHistory = Array(repeating: 5, count: 18)
        stats.top = (0..<5).map { Proc(name: "App \($0)", bytes: Double(5 - $0) * 1_073_741_824) }

        let view = DashboardView(stats: stats, settings: AppSettings(), onClean: {}, onQuit: {}, onSettings: {}, onInsights: {}, onWindow: {})
        let hosting = NSHostingController(rootView: view)
        hosting.sizingOptions = [.preferredContentSize]

        // force layout
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 380, height: 800),
                           styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentViewController = hosting
        win.layoutIfNeeded()

        let fitting = hosting.view.fittingSize
        let pref = hosting.preferredContentSize
        let intrinsic = hosting.view.intrinsicContentSize
        print("fittingSize     = \(fitting)")
        print("preferredContent= \(pref)")
        print("intrinsicSize   = \(intrinsic)")
    }
}
