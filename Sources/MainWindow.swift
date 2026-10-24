import SwiftUI
import AppKit

// The full window app (opened from Applications / Dock / footer), with a sidebar
// like Usage: Dashboard · Insights · Settings.

struct WindowDashboard: View {
    @ObservedObject var stats: Stats
    @ObservedObject var settings: AppSettings
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                MemoryCard(stats: stats)
                if settings.showCPU { CPUCard(stats: stats, detailed: true) }
                if settings.showNetwork { NetworkCard(stats: stats, settings: settings, detailed: true) }
                if settings.showStorage { StorageCard(stats: stats, detailed: true) }
                BatteryCard(stats: stats)   // shows only if a battery is present
                GPUCard(stats: stats)       // shows only if GPU utilization is available
                if settings.showTop { TopCard(stats: stats) }
            }
            .padding(18)
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
        .background(Pal.bg)
    }
}

struct AppWindowView: View {
    @ObservedObject var stats: Stats
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loc = Loc.shared
    @State private var sel: String? = "dashboard"

    var body: some View {
        NavigationSplitView {
            List(selection: $sel) {
                Label(loc.t("dashboard"), systemImage: "square.grid.2x2").tag("dashboard")
                Label(loc.t("insights"), systemImage: "chart.xyaxis.line").tag("insights")
                Label(loc.t("settings"), systemImage: "gearshape").tag("settings")
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 170, ideal: 190, max: 220)
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Pal.bg)
                .navigationTitle("Mac Monitor")
        }
        .preferredColorScheme(.dark)
    }

    @ViewBuilder
    var detailView: some View {
        switch sel {
        case "insights":
            ScrollView { InsightsView(stats: stats).padding(.vertical, 8) }
                .frame(maxWidth: .infinity).background(Pal.bg)
        case "settings":
            ScrollView { SettingsView(settings: settings).padding(.vertical, 8) }
                .frame(maxWidth: .infinity).background(Pal.bg)
        default:
            WindowDashboard(stats: stats, settings: settings)
        }
    }
}
