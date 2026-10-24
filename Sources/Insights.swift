import SwiftUI
import AppKit

// Area+line chart over a series of values (0...maxVal).
struct AreaChart: View {
    let values: [Double]
    var maxVal: Double = 100
    var tint: Color? = nil   // when set, fill + stroke use this single color (e.g. pressure)
    var body: some View {
        GeometryReader { g in
            if values.count >= 2 {
                let n = values.count
                let stepX = g.size.width / CGFloat(n - 1)
                let pts: [CGPoint] = (0..<n).map { i in
                    let v = min(maxVal, max(0, values[i]))
                    return CGPoint(x: CGFloat(i) * stepX, y: g.size.height * (1 - CGFloat(v / maxVal)))
                }
                ZStack {
                    Path { p in
                        p.move(to: CGPoint(x: 0, y: g.size.height))
                        p.addLine(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                        p.addLine(to: CGPoint(x: g.size.width, y: g.size.height))
                        p.closeSubpath()
                    }
                    .fill(LinearGradient(colors: [(tint ?? Pal.blue).opacity(0.38), (tint ?? Pal.blue).opacity(0.03)],
                                         startPoint: .top, endPoint: .bottom))
                    Path { p in
                        p.move(to: pts[0])
                        for pt in pts.dropFirst() { p.addLine(to: pt) }
                    }
                    .stroke(tint != nil ? AnyShapeStyle(tint!) : AnyShapeStyle(LinearGradient(colors: Pal.accent, startPoint: .leading, endPoint: .trailing)),
                            style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))
                }
            } else {
                Capsule().fill(Pal.track).frame(height: 2).frame(maxHeight: .infinity, alignment: .center)
            }
        }
    }
}

struct InsightsView: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var hist = History.shared
    @ObservedObject private var loc = Loc.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(loc.t("insights")).font(.system(size: 15, weight: .bold)).foregroundColor(.white)

            section(loc.t("memory"),
                    values: hist.recent.map { $0.ram },
                    now: stats.usedPercent,
                    avg: hist.avg({ $0.ram }, hist.recent),
                    peak: hist.peak({ $0.ram }, hist.longTerm + hist.recent))

            section(loc.t("processor"),
                    values: hist.recent.map { $0.cpu },
                    now: stats.cpu,
                    avg: hist.avg({ $0.cpu }, hist.recent),
                    peak: hist.peak({ $0.cpu }, hist.longTerm + hist.recent))

            HStack {
                stat(loc.t("pressure_events"), "\(hist.criticalMinutes) min")
                Spacer()
                Button {
                    NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Activity Monitor.app"))
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up.forward.app")
                        Text(loc.t("open_activity"))
                    }
                    .font(.system(size: 11, weight: .medium)).foregroundColor(Pal.blue)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(width: 360)
        .background(Pal.bg)
    }

    func section(_ title: String, values: [Double], now: Double, avg: Double, peak: Double) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("waveform.path.ecg", title)
            AreaChart(values: values, maxVal: 100).frame(height: 58)
            HStack(spacing: 16) {
                stat(loc.t("now"), String(format: "%.0f%%", now))
                stat(loc.t("average"), String(format: "%.0f%%", avg))
                stat(loc.t("peak"), String(format: "%.0f%%", peak))
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.card))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Pal.cardBorder, lineWidth: 1))
    }

    func stat(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(label).font(.system(size: 9.5)).foregroundColor(Pal.sub)
            Text(value).font(.system(size: 12, weight: .semibold)).foregroundColor(.white)
        }
    }
}
