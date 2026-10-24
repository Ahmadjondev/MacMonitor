import SwiftUI
import AppKit

// Renders SettingsView to a PNG for design review. Compile with ../Sources/Core.swift.

@main
struct SettingsPreview {
    static func main() {
        let s = AppSettings()
        let view = SettingsView(settings: s).environment(\.colorScheme, .dark)
        let renderer = ImageRenderer(content: view)
        renderer.scale = 2
        let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "settings.png"
        if let img = renderer.nsImage, let tiff = img.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: URL(fileURLWithPath: out))
            print("wrote \(out)")
        } else { print("render failed") }
    }
}
