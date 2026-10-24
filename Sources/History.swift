import Foundation
import Combine

// Rolling metric history with two layers:
//  • recent  — raw 1s samples (for live sparklines / charts)
//  • longTerm — 1-minute aggregates, persisted to disk (for 24h trends/peaks)

struct Sample: Codable {
    var t: Double          // timeIntervalSinceReferenceDate
    var ram: Double        // used %
    var cpu: Double        // %
    var disk: Double       // used %
    var down: Double       // bytes/sec
    var up: Double         // bytes/sec
    var pressure: Int
}

final class History: ObservableObject {
    static let shared = History()

    // not @Published: views re-render with `Stats` once per tick, so no extra updates
    private(set) var recent: [Sample] = []
    private(set) var longTerm: [Sample] = []

    private var bucket: [Sample] = []
    private var lastFlushT = 0.0
    private let maxRecent = 180     // ~3 min at 1s
    private let maxLong = 1440      // 24h of 1-min aggregates

    private let fileURL: URL = {
        let base = (FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                    ?? URL(fileURLWithPath: NSTemporaryDirectory()))
            .appendingPathComponent("MacMonitor", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }()

    init() { load() }

    func add(_ s: Sample) {
        recent.append(s)
        if recent.count > maxRecent { recent.removeFirst(recent.count - maxRecent) }
        bucket.append(s)
        if lastFlushT == 0 { lastFlushT = s.t }
        if s.t - lastFlushT >= 60 { flush(at: s.t) }
    }

    private func flush(at t: Double) {
        defer { lastFlushT = t }
        guard !bucket.isEmpty else { return }
        let n = Double(bucket.count)
        let agg = Sample(
            t: t,
            ram: bucket.reduce(0) { $0 + $1.ram } / n,
            cpu: bucket.reduce(0) { $0 + $1.cpu } / n,
            disk: bucket.reduce(0) { $0 + $1.disk } / n,
            down: bucket.reduce(0) { $0 + $1.down } / n,
            up: bucket.reduce(0) { $0 + $1.up } / n,
            pressure: bucket.map { $0.pressure }.max() ?? 1)
        longTerm.append(agg)
        if longTerm.count > maxLong { longTerm.removeFirst(longTerm.count - maxLong) }
        bucket.removeAll(keepingCapacity: true)
        save()
    }

    private func save() {
        if let data = try? JSONEncoder().encode(longTerm) { try? data.write(to: fileURL) }
    }
    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let arr = try? JSONDecoder().decode([Sample].self, from: data) else { return }
        longTerm = arr
    }

    // MARK: insights helpers
    func avg(_ kp: (Sample) -> Double, _ arr: [Sample]) -> Double {
        arr.isEmpty ? 0 : arr.reduce(0) { $0 + kp($1) } / Double(arr.count)
    }
    func peak(_ kp: (Sample) -> Double, _ arr: [Sample]) -> Double {
        arr.map(kp).max() ?? 0
    }
    var criticalMinutes: Int { longTerm.filter { $0.pressure == 4 }.count }
    /// Best available long history (falls back to recent before the first minute flush).
    var longOrRecent: [Sample] { longTerm.isEmpty ? recent : longTerm }
}
