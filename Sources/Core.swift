import SwiftUI
import AppKit
import Combine
import Foundation
import Darwin
import IOKit

let kAutoPurgeKey = "autoPurgeEnabled"

// MARK: - Palette

extension Color {
    init(hex: UInt32) {
        self.init(.sRGB,
                  red: Double((hex >> 16) & 0xFF) / 255,
                  green: Double((hex >> 8) & 0xFF) / 255,
                  blue: Double(hex & 0xFF) / 255,
                  opacity: 1)
    }
}

enum Pal {
    static let bg          = Color(hex: 0x0C0C0E)
    static let card        = Color(hex: 0x1A1A1D)
    static let cardBorder  = Color(hex: 0x2A2A2F)
    static let track       = Color(hex: 0x2A2A30)
    static let sub         = Color(hex: 0x8A8A8F)
    static let headerGray  = Color(hex: 0x9A9AA0)
    static let purple      = Color(hex: 0x7C6CF0)
    static let blue        = Color(hex: 0x3B82F6)
    static let teal        = Color(hex: 0x2DD4BF)
    static let red         = Color(hex: 0xFF453A)
    static let yellow      = Color(hex: 0xFFD60A)
    static let green       = Color(hex: 0x32D74B)
    static var accent: [Color] { [purple, blue, teal] }
}

func gbStr(_ bytes: Double) -> String { String(format: "%.2f", bytes / 1_073_741_824) }
func gbShort(_ bytes: Double) -> String { String(format: "%.1f", bytes / 1_073_741_824) }

// MARK: - System readings

struct MemInfo {
    var used = 0.0, total = 1.0, freePercent = 100.0
    var wired = 0.0, compressed = 0.0, app = 0.0
    var cached = 0.0          // file-backed / cached files
    var swapUsed = 0.0, swapTotal = 0.0
}

func memoryStats() -> MemInfo {
    let host = mach_host_self()
    var pageSize: vm_size_t = 0
    host_page_size(host, &pageSize)

    var stats = vm_statistics64_data_t()
    var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64_data_t>.stride / MemoryLayout<integer_t>.stride)
    let kr = withUnsafeMutablePointer(to: &stats) { ptr -> kern_return_t in
        ptr.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { intPtr in
            host_statistics64(host, HOST_VM_INFO64, intPtr, &count)
        }
    }

    var total: UInt64 = 0
    var s = MemoryLayout<UInt64>.size
    sysctlbyname("hw.memsize", &total, &s, nil, 0)

    var info = MemInfo()
    info.total = Double(total)
    guard kr == KERN_SUCCESS else { return info }

    let ps = Double(pageSize)
    info.app = max(0, Double(stats.internal_page_count) - Double(stats.purgeable_count)) * ps
    info.wired = Double(stats.wire_count) * ps
    info.compressed = Double(stats.compressor_page_count) * ps
    info.cached = Double(stats.external_page_count) * ps
    info.used = info.app + info.wired + info.compressed
    info.freePercent = max(0, min(100, (1.0 - info.used / info.total) * 100.0))

    var sw = xsw_usage()
    var swSize = MemoryLayout<xsw_usage>.size
    if sysctlbyname("vm.swapusage", &sw, &swSize, nil, 0) == 0 {
        info.swapUsed = Double(sw.xsu_used)
        info.swapTotal = Double(sw.xsu_total)
    }
    return info
}

func pressureLevel() -> Int {
    var level: Int32 = 1
    var size = MemoryLayout<Int32>.size
    sysctlbyname("kern.memorystatus_vm_pressure_level", &level, &size, nil, 0)
    return Int(level)
}

// MARK: - Network readings

/// Cumulative rx/tx bytes across all non-loopback interfaces.
func netCounters() -> (rx: UInt64, tx: UInt64) {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return (0, 0) }
    defer { freeifaddrs(ifaddr) }
    var rx: UInt64 = 0, tx: UInt64 = 0
    var ptr = ifaddr
    while let p = ptr {
        let ifa = p.pointee
        if let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_LINK {
            let name = String(cString: ifa.ifa_name)
            if !name.hasPrefix("lo"), let raw = ifa.ifa_data {
                let d = raw.assumingMemoryBound(to: if_data.self).pointee
                rx += UInt64(d.ifi_ibytes)
                tx += UInt64(d.ifi_obytes)
            }
        }
        ptr = ifa.ifa_next
    }
    return (rx, tx)
}

/// Primary local IPv4 address (prefers en0).
func localIPv4() -> String {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return "—" }
    defer { freeifaddrs(ifaddr) }
    var result = "—"
    var ptr = ifaddr
    while let p = ptr {
        let ifa = p.pointee
        if let addr = ifa.ifa_addr, Int32(addr.pointee.sa_family) == AF_INET {
            let name = String(cString: ifa.ifa_name)
            if name.hasPrefix("en") {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host,
                            socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                let ip = String(cString: host)
                if !ip.isEmpty && ip != "0.0.0.0" {
                    result = ip
                    if name == "en0" { break }
                }
            }
        }
        ptr = ifa.ifa_next
    }
    return result
}

/// Formats a byte/sec rate. bits=true → Mb/s (network convention); bits=false → MB/s.
/// At most three digits ("8.4", "52", "999"), so the menu-bar item can stay narrow.
func speedStr(_ bytesPerSec: Double, bits: Bool = true) -> String {
    let units = bits ? ["b/s", "kb/s", "Mb/s", "Gb/s"] : ["B/s", "KB/s", "MB/s", "GB/s"]
    var v = max(0, bytesPerSec) * (bits ? 8 : 1)
    var i = 0
    while v >= 999.5 && i < units.count - 1 { v /= 1000; i += 1 }   // 999.5 would print as "1000"
    let fmt = (i > 0 && v < 9.95) ? "%.1f %@" : "%.0f %@"
    return String(format: fmt, v, units[i])
}

/// Widest string `speedStr` can return for a unit system (digits are monospaced).
func speedStrWidest(bits: Bool) -> [String] {
    bits ? ["888 kb/s", "888 Mb/s", "8.8 Gb/s"] : ["888 KB/s", "888 MB/s", "8.8 GB/s"]
}

// MARK: - Disk / storage readings

/// Decimal GB (disks use base-10, like Finder).
func gbDec(_ bytes: Double) -> String { String(format: "%.1f", bytes / 1_000_000_000) }

/// Root-volume capacity: used / total (bytes) + volume name.
func diskCapacity() -> (used: Double, total: Double, name: String) {
    let url = URL(fileURLWithPath: "/")
    let keys: Set<URLResourceKey> = [.volumeTotalCapacityKey,
                                     .volumeAvailableCapacityForImportantUsageKey,
                                     .volumeNameKey]
    guard let v = try? url.resourceValues(forKeys: keys) else { return (0, 1, "Disk") }
    let total = Double(v.volumeTotalCapacity ?? 0)
    let avail = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
    return (max(0, total - avail), max(total, 1), v.volumeName ?? "Macintosh HD")
}

/// Cumulative bytes + operations read/written across all block-storage drivers (IOKit).
func diskIO() -> (read: UInt64, write: UInt64, rops: UInt64, wops: UInt64) {
    var read: UInt64 = 0, write: UInt64 = 0, rops: UInt64 = 0, wops: UInt64 = 0
    var iterator = io_iterator_t()
    let matching = IOServiceMatching("IOBlockStorageDriver")
    guard IOServiceGetMatchingServices(kIOMainPortDefault, matching, &iterator) == KERN_SUCCESS else {
        return (0, 0, 0, 0)
    }
    var drive = IOIteratorNext(iterator)
    while drive != 0 {
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(drive, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let dict = props?.takeRetainedValue() as? [String: Any],
           let stats = dict["Statistics"] as? [String: Any] {
            if let r = stats["Bytes (Read)"] as? NSNumber { read += r.uint64Value }
            if let w = stats["Bytes (Write)"] as? NSNumber { write += w.uint64Value }
            if let r = stats["Operations (Read)"] as? NSNumber { rops += r.uint64Value }
            if let w = stats["Operations (Write)"] as? NSNumber { wops += w.uint64Value }
        }
        IOObjectRelease(drive)
        drive = IOIteratorNext(iterator)
    }
    IOObjectRelease(iterator)
    return (read, write, rops, wops)
}

struct DiskInfo {
    var used = 0.0, total = 1.0, name = "Disk"
    var readSpeed = 0.0, writeSpeed = 0.0   // bytes/sec
    var readOps = 0.0, writeOps = 0.0       // ops/sec (IOPS)
    var sessionRead = 0.0, sessionWritten = 0.0  // bytes since app launch
    var usedPercent: Double { total > 0 ? used / total * 100 : 0 }
}

func friendlyName(_ path: String) -> String {
    if let r = path.range(of: ".app/") {
        let before = path[..<r.lowerBound]
        if let slash = before.lastIndex(of: "/") { return String(before[before.index(after: slash)...]) }
        return String(before)
    }
    if let slash = path.lastIndex(of: "/") { return String(path[path.index(after: slash)...]) }
    return path
}

struct Proc: Identifiable {
    var id: String { name }
    let name: String
    let bytes: Double
}

func topConsumers(limit: Int) -> [Proc] {
    let p = Process()
    p.launchPath = "/bin/ps"
    p.arguments = ["-axo", "rss=,comm="]
    let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
    do { try p.run() } catch { return [] }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    guard let out = String(data: data, encoding: .utf8) else { return [] }

    var agg: [String: Double] = [:]
    for line in out.split(separator: "\n") {
        let t = line.trimmingCharacters(in: .whitespaces)
        guard let sp = t.firstIndex(of: " "), let rss = Double(t[..<sp]) else { continue }
        let comm = String(t[t.index(after: sp)...]).trimmingCharacters(in: .whitespaces)
        if comm.isEmpty { continue }
        agg[friendlyName(comm), default: 0] += rss * 1024
    }
    return agg.sorted { $0.value > $1.value }.prefix(limit).map { Proc(name: $0.key, bytes: $0.value) }
}

func runPurge(interactive: Bool) {
    let sudo = Process()
    sudo.launchPath = "/usr/bin/sudo"
    sudo.arguments = ["-n", "/usr/sbin/purge"]
    sudo.standardOutput = Pipe(); sudo.standardError = Pipe()
    do { try sudo.run(); sudo.waitUntilExit() } catch {}
    if sudo.terminationStatus == 0 { return }
    guard interactive else { return }
    let osa = Process()
    osa.launchPath = "/usr/bin/osascript"
    osa.arguments = ["-e", "do shell script \"/usr/sbin/purge\" with administrator privileges"]
    osa.standardOutput = Pipe(); osa.standardError = Pipe()
    do { try osa.run(); osa.waitUntilExit() } catch {}
}

/// True when the optional sudoers rule lets `purge` run without a password.
/// `sudo -n -l <cmd>` only looks the rule up; it runs nothing.
func purgeRuleInstalled() -> Bool {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
    p.arguments = ["-n", "-l", "/usr/sbin/purge"]
    p.standardOutput = Pipe(); p.standardError = Pipe()
    do { try p.run(); p.waitUntilExit() } catch { return false }
    return p.terminationStatus == 0
}

// MARK: - Observable state

/// Plain properties on purpose: the sampler fills them every tick, then sends ONE
/// `objectWillChange` and only while some UI is on screen (see `AppDelegate.update()`).
/// Hidden views therefore never re-render.
final class Stats: ObservableObject {
    var mem = MemInfo()
    var pressure = 1
    var cpu = 0.0
    var cpuHistory: [Double] = []
    var coreUsage: [Double] = []   // per-core %
    var cpuUser = 0.0
    var cpuSys = 0.0
    var cpuIdle = 0.0
    var loadAvg: [Double] = []
    var processCount = 0
    var threadCount = 0
    var top: [Proc] = []
    var downSpeed = 0.0   // bytes/sec
    var upSpeed = 0.0     // bytes/sec
    var totalRx = 0.0     // cumulative bytes received (since boot)
    var totalTx = 0.0     // cumulative bytes sent
    var packetsIn = 0.0
    var packetsOut = 0.0
    var interfaces: [NetIface] = []
    var localIP = "—"
    var disk = DiskInfo()
    var battery: BatteryInfo? = nil
    var gpu: Double? = nil
    var usedPercent: Double { 100 - mem.freePercent }
}

// MARK: - Settings

enum BarMode: Int, CaseIterable, Identifiable {
    case network = 0, ram = 1, cpu = 2
    var id: Int { rawValue }
    var label: String {
        switch self { case .network: return "Network"; case .ram: return "RAM"; case .cpu: return "CPU" }
    }
}

let kLaunchAgentPath = NSHomeDirectory() + "/Library/LaunchAgents/app.macmonitor.MacMonitor.plist"

final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard
    @Published var barMode: Int        { didSet { d.set(barMode, forKey: "barMode") } }
    @Published var intervalSec: Int    { didSet { d.set(intervalSec, forKey: "intervalSec") } }
    @Published var speedBits: Bool     { didSet { d.set(speedBits, forKey: "speedBits") } }
    @Published var autoPurge: Bool     { didSet { d.set(autoPurge, forKey: kAutoPurgeKey) } }
    // card visibility (Memory is always shown as the hero)
    @Published var showCPU: Bool       { didSet { d.set(showCPU, forKey: "showCPU") } }
    @Published var showNetwork: Bool   { didSet { d.set(showNetwork, forKey: "showNetwork") } }
    @Published var showStorage: Bool   { didSet { d.set(showStorage, forKey: "showStorage") } }
    @Published var showTop: Bool       { didSet { d.set(showTop, forKey: "showTop") } }
    @Published var notify: Bool        { didSet { d.set(notify, forKey: "notify") } }
    // launch at login is reflected by the LaunchAgent plist existing (handled in AppDelegate)
    @Published var launchAtLogin: Bool

    init() {
        barMode = d.object(forKey: "barMode") as? Int ?? 0
        intervalSec = d.object(forKey: "intervalSec") as? Int ?? 1
        speedBits = d.object(forKey: "speedBits") as? Bool ?? true
        autoPurge = d.object(forKey: kAutoPurgeKey) as? Bool ?? false
        showCPU = d.object(forKey: "showCPU") as? Bool ?? true
        showNetwork = d.object(forKey: "showNetwork") as? Bool ?? true
        showStorage = d.object(forKey: "showStorage") as? Bool ?? true
        showTop = d.object(forKey: "showTop") as? Bool ?? true
        notify = d.object(forKey: "notify") as? Bool ?? false
        launchAtLogin = FileManager.default.fileExists(atPath: kLaunchAgentPath)
    }
}

// MARK: - UI helpers

func cardHeader(_ symbol: String, _ title: String) -> some View {
    HStack(spacing: 6) {
        Image(systemName: symbol).font(.system(size: 11, weight: .semibold))
        Text(title).font(.system(size: 12.5, weight: .semibold))
    }
    .foregroundColor(Pal.headerGray)
}

struct CardBG: ViewModifier {
    var fillHeight = false
    func body(content: Content) -> some View {
        content
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: fillHeight ? .infinity : nil, alignment: .topLeading)
            .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(Pal.card))
            .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(Pal.cardBorder, lineWidth: 1))
    }
}
extension View { func card(fillHeight: Bool = false) -> some View { modifier(CardBG(fillHeight: fillHeight)) } }

func pressureColor(_ p: Int) -> Color { p == 4 ? Pal.red : (p == 2 ? Pal.yellow : Pal.green) }
func pressureText(_ p: Int) -> String { Loc.shared.t(p == 4 ? "critical" : (p == 2 ? "warning" : "normal")) }
func pressureH(_ p: Int) -> Double { p == 4 ? 100 : (p == 2 ? 55 : 16) }   // graph height by level

struct Pill: View {
    let symbol: String
    let text: String
    var tint: Color = Pal.headerGray
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: symbol).font(.system(size: 8.5, weight: .bold)).foregroundColor(tint)
            Text(text).font(.system(size: 11, weight: .medium)).foregroundColor(.white.opacity(0.92))
        }
        .padding(.horizontal, 9).padding(.vertical, 5)
        .background(Capsule().fill(Pal.cardBorder))
    }
}

struct Donut: View {
    let fraction: Double
    var lineWidth: CGFloat = 9
    var body: some View {
        // Ring snaps to whole percents: the value moves a little every tick, and animating
        // the (CPU-rendered) conic gradient each second costs ~20% CPU. 1% = 3.6°, unnoticeable.
        let shown = (fraction * 100).rounded() / 100
        ZStack {
            Circle().stroke(Pal.track, lineWidth: lineWidth)
            Circle()
                .trim(from: 0, to: max(0.001, min(1, shown)))
                .stroke(AngularGradient(gradient: Gradient(colors: Pal.accent + [Pal.purple]), center: .center),
                        style: StrokeStyle(lineWidth: lineWidth, lineCap: .round))
                .rotationEffect(.degrees(-90))
                .animation(.easeInOut(duration: 0.5), value: shown)
            Text(String(format: "%.0f%%", fraction * 100))
                .font(.system(size: 12, weight: .bold)).foregroundColor(.white)
        }
    }
}

struct Bars: View {
    let values: [Double]
    let count: Int
    var body: some View {
        GeometryReader { geo in
            HStack(alignment: .bottom, spacing: 3) {
                ForEach(0..<count, id: \.self) { i in
                    let idx = i - (count - values.count)
                    let v = (idx >= 0 && idx < values.count) ? values[idx] : 0
                    RoundedRectangle(cornerRadius: 2, style: .continuous)
                        .fill(LinearGradient(colors: [Pal.blue, Pal.purple], startPoint: .bottom, endPoint: .top))
                        .frame(height: max(2, geo.size.height * CGFloat(min(1, v / 100))))
                        .opacity(idx >= 0 ? 1 : 0.18)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
    }
}

// MARK: - Cards

struct MemorySegBar: View {
    let m: MemInfo
    var body: some View {
        GeometryReader { g in
            let total = max(m.total, 1)
            let segs: [(Double, Color)] = [
                (m.app, Pal.blue), (m.wired, Pal.purple),
                (m.compressed, Pal.teal), (m.cached, Pal.sub.opacity(0.55))
            ]
            HStack(spacing: 1) {
                ForEach(Array(segs.enumerated()), id: \.offset) { _, seg in
                    Rectangle().fill(seg.1).frame(width: max(0, g.size.width * CGFloat(seg.0 / total)))
                }
                Rectangle().fill(Pal.track)   // remaining = free
            }
            .clipShape(Capsule())
        }
        .frame(height: 8)
    }
}

struct MemoryCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    @ObservedObject private var hist = History.shared
    var body: some View {
        let m = stats.mem
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                cardHeader("memorychip", loc.t("memory"))
                Spacer()
                Pill(symbol: "circle.fill", text: pressureText(stats.pressure), tint: pressureColor(stats.pressure))
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f%%", stats.usedPercent))
                        .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    Text("\(gbStr(m.used)) / \(gbStr(m.total)) GB")
                        .font(.system(size: 12)).foregroundColor(Pal.sub)
                }
                Spacer()
                Donut(fraction: stats.usedPercent / 100).frame(width: 64, height: 64)
            }
            MemorySegBar(m: m)
            HStack(spacing: 10) {
                legend(Pal.blue, loc.t("app"), m.app)
                legend(Pal.purple, loc.t("wired"), m.wired)
                legend(Pal.teal, loc.t("compressed"), m.compressed)
                legend(Pal.sub.opacity(0.7), loc.t("cache"), m.cached)
            }
            if m.swapTotal > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.left.arrow.right.circle.fill")
                        .font(.system(size: 10)).foregroundColor(Pal.sub)
                    Text("\(loc.t("swap")): \(gbShort(m.swapUsed)) / \(gbShort(m.swapTotal)) GB")
                        .font(.system(size: 11)).foregroundColor(Pal.sub)
                }
            }
            if hist.recent.count >= 2 {
                VStack(alignment: .leading, spacing: 3) {
                    Text(loc.t("pressure")).font(.system(size: 9.5)).foregroundColor(Pal.sub)
                    AreaChart(values: hist.recent.map { pressureH($0.pressure) }, maxVal: 100,
                              tint: pressureColor(stats.pressure))
                        .frame(height: 24)
                }
            }
        }
        .card()
    }

    func legend(_ color: Color, _ name: String, _ bytes: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(name).font(.system(size: 9.5)).foregroundColor(Pal.sub)
            Text(gbShort(bytes)).font(.system(size: 9.5, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct CPUCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    var detailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cardHeader("cpu", loc.t("processor"))
            Text(String(format: "%.1f%%", stats.cpu))
                .font(.system(size: 22, weight: .bold)).foregroundColor(.white)
            // per-core usage (advanced) — one bar per core
            if detailed {
                Bars(values: stats.coreUsage, count: max(stats.coreUsage.count, 1)).frame(height: 46)
            } else {
                Bars(values: stats.coreUsage, count: max(stats.coreUsage.count, 1)).frame(maxHeight: .infinity)
            }
            Text("\(stats.coreUsage.count) \(loc.t("cores").lowercased())")
                .font(.system(size: 9)).foregroundColor(Pal.sub)

            if detailed {
                HStack(spacing: 12) {
                    dot(Pal.blue, "User", stats.cpuUser)
                    dot(Pal.purple, "System", stats.cpuSys)
                    dot(Pal.sub, "Idle", stats.cpuIdle)
                }
                .padding(.top, 2)
                HStack(spacing: 14) {
                    if stats.loadAvg.count == 3 {
                        kv("Load", String(format: "%.2f  %.2f  %.2f", stats.loadAvg[0], stats.loadAvg[1], stats.loadAvg[2]))
                    }
                    Spacer()
                    kv(loc.t("processes"), "\(stats.processCount)")
                    kv(loc.t("threads"), "\(stats.threadCount)")
                }
            }
        }
        .card(fillHeight: !detailed)
    }

    func dot(_ c: Color, _ label: String, _ v: Double) -> some View {
        HStack(spacing: 4) {
            Circle().fill(c).frame(width: 6, height: 6)
            Text(label).font(.system(size: 10)).foregroundColor(Pal.sub)
            Text(String(format: "%.0f%%", v)).font(.system(size: 10, weight: .semibold)).foregroundColor(.white)
        }
    }
    func kv(_ k: String, _ v: String) -> some View {
        VStack(alignment: .leading, spacing: 1) {
            Text(k).font(.system(size: 9)).foregroundColor(Pal.sub)
            Text(v).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
        }
    }
}

struct NetworkCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loc = Loc.shared
    var detailed = false
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            cardHeader("globe", loc.t("network"))
            HStack(spacing: 6) {
                Image(systemName: "arrow.down").font(.system(size: 10, weight: .bold)).foregroundColor(Pal.blue)
                Text(speedStr(stats.downSpeed, bits: settings.speedBits))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            HStack(spacing: 6) {
                Image(systemName: "arrow.up").font(.system(size: 10, weight: .bold)).foregroundColor(Pal.purple)
                Text(speedStr(stats.upSpeed, bits: settings.speedBits))
                    .font(.system(size: 14, weight: .bold)).foregroundColor(.white)
                    .lineLimit(1).minimumScaleFactor(0.6)
            }
            if !detailed { Spacer(minLength: 0) }
            Text("\(loc.t("total"))  ↓ \(gbShort(stats.totalRx))  ↑ \(gbShort(stats.totalTx)) GB")
                .font(.system(size: 9.5)).foregroundColor(Pal.sub).lineLimit(1).minimumScaleFactor(0.7)

            if detailed {
                Text("\(loc.t("packets"))  ↓ \(pkt(stats.packetsIn))  ↑ \(pkt(stats.packetsOut))")
                    .font(.system(size: 9.5)).foregroundColor(Pal.sub)
                ForEach(stats.interfaces.prefix(4)) { i in
                    HStack {
                        Text(i.name).font(.system(size: 10, weight: .medium)).foregroundColor(.white)
                        Spacer()
                        Text("↓ \(gbShort(i.rx))  ↑ \(gbShort(i.tx)) GB")
                            .font(.system(size: 9.5)).foregroundColor(Pal.sub)
                    }
                }
            }
            Text(stats.localIP).font(.system(size: 10)).foregroundColor(Pal.sub).lineLimit(1)
        }
        .card(fillHeight: !detailed)
    }

    func pkt(_ n: Double) -> String {
        n >= 1_000_000 ? String(format: "%.1fM", n / 1_000_000) : (n >= 1_000 ? String(format: "%.0fK", n / 1_000) : String(format: "%.0f", n))
    }
}

struct StorageCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    var detailed = false
    var body: some View {
        let d = stats.disk
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                cardHeader("internaldrive", loc.t("storage"))
                Spacer()
                Pill(symbol: "externaldrive.fill", text: d.name)
            }
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f%%", d.usedPercent))
                        .font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                    Text("\(gbDec(d.used)) / \(gbDec(d.total)) GB")
                        .font(.system(size: 12)).foregroundColor(Pal.sub)
                }
                Spacer()
                Donut(fraction: d.usedPercent / 100).frame(width: 64, height: 64)
            }
            GeometryReader { g in
                ZStack(alignment: .leading) {
                    Capsule().fill(Pal.track)
                    Capsule()
                        .fill(LinearGradient(colors: Pal.accent, startPoint: .leading, endPoint: .trailing))
                        .frame(width: g.size.width * CGFloat(min(1, d.usedPercent / 100)))
                }
            }
            .frame(height: 8)
            HStack(spacing: 14) {
                HStack(spacing: 5) {
                    Image(systemName: "arrow.down.circle.fill").font(.system(size: 10)).foregroundColor(Pal.blue)
                    Text(speedStr(d.readSpeed, bits: false)).font(.system(size: 11)).foregroundColor(.white)
                }
                HStack(spacing: 5) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 10)).foregroundColor(Pal.purple)
                    Text(speedStr(d.writeSpeed, bits: false)).font(.system(size: 11)).foregroundColor(.white)
                }
                Spacer()
                Text("\(loc.t("free")): \(gbDec(d.total - d.used)) GB").font(.system(size: 11)).foregroundColor(Pal.sub)
            }
            if detailed {
                HStack(spacing: 14) {
                    Text("\(loc.t("session"))  ↓ \(gbDec(d.sessionRead))  ↑ \(gbDec(d.sessionWritten)) GB")
                        .font(.system(size: 10)).foregroundColor(Pal.sub)
                    Spacer()
                    Text("IOPS  R \(Int(d.readOps))  W \(Int(d.writeOps))")
                        .font(.system(size: 10)).foregroundColor(Pal.sub)
                }
            }
        }
        .card()
    }
}

func miniStat(_ k: String, _ v: String) -> some View {
    VStack(alignment: .leading, spacing: 1) {
        Text(k).font(.system(size: 9)).foregroundColor(Pal.sub)
        Text(v).font(.system(size: 11, weight: .semibold)).foregroundColor(.white)
    }
}

struct BatteryCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    var body: some View {
        if let b = stats.battery {
            VStack(alignment: .leading, spacing: 11) {
                HStack {
                    cardHeader("battery.100", loc.t("battery"))
                    Spacer()
                    Pill(symbol: b.onAC ? "powerplug.fill" : "bolt.fill",
                         text: b.charging ? "Charging" : (b.onAC ? "AC" : "Battery"),
                         tint: b.charging ? Pal.green : Pal.headerGray)
                }
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(b.percent)%").font(.system(size: 30, weight: .bold)).foregroundColor(.white)
                        if b.timeMin > 0 {
                            Text("\(b.timeMin / 60)h \(b.timeMin % 60)m").font(.system(size: 12)).foregroundColor(Pal.sub)
                        }
                    }
                    Spacer()
                    Donut(fraction: Double(b.percent) / 100).frame(width: 64, height: 64)
                }
                HStack(spacing: 16) {
                    miniStat(loc.t("health"), "\(b.healthPct)%")
                    miniStat(loc.t("cycles"), "\(b.cycles)")
                    miniStat("Temp", String(format: "%.0f°C", b.tempC))
                    Spacer()
                }
                HStack(spacing: 16) {
                    miniStat("Power", String(format: "%.1f W", b.powerW))
                    miniStat("Voltage", String(format: "%.2f V", b.voltage))
                    if b.adapterW > 0 { miniStat("Adapter", "\(Int(b.adapterW)) W") }
                    Spacer()
                }
            }
            .card()
        }
    }
}

struct GPUCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    var body: some View {
        if let g = stats.gpu {
            VStack(alignment: .leading, spacing: 9) {
                cardHeader("speedometer", loc.t("gpu"))
                Text(String(format: "%.0f%%", g)).font(.system(size: 26, weight: .bold)).foregroundColor(.white)
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Pal.track)
                        Capsule().fill(LinearGradient(colors: Pal.accent, startPoint: .leading, endPoint: .trailing))
                            .frame(width: geo.size.width * CGFloat(min(1, g / 100)))
                    }
                }
                .frame(height: 8)
            }
            .card()
        }
    }
}

struct TopCard: View {
    @ObservedObject var stats: Stats
    @ObservedObject private var loc = Loc.shared
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            cardHeader("list.bullet", loc.t("top"))
            let maxV = max(stats.top.first?.bytes ?? 1, 1)
            ForEach(stats.top) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack {
                        Text(item.name).font(.system(size: 11.5)).foregroundColor(.white).lineLimit(1)
                        Spacer(minLength: 8)
                        Text("\(gbShort(item.bytes)) GB").font(.system(size: 10.5)).foregroundColor(Pal.sub)
                    }
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(Pal.track)
                            Capsule()
                                .fill(LinearGradient(colors: [Pal.purple, Pal.blue], startPoint: .leading, endPoint: .trailing))
                                .frame(width: max(3, g.size.width * CGFloat(item.bytes / maxV)))
                        }
                    }
                    .frame(height: 3.5)
                }
            }
        }
        .card()
    }
}

struct Footer: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loc = Loc.shared
    let onClean: () -> Void
    let onQuit: () -> Void
    let onSettings: () -> Void
    let onInsights: () -> Void
    let onWindow: () -> Void
    @State private var cleaning = false
    var body: some View {
        VStack(spacing: 9) {
            Button {
                cleaning = true
                onClean()
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { cleaning = false }
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: cleaning ? "sparkles" : "wand.and.stars")
                    Text(cleaning ? loc.t("cleaning") : loc.t("clean_now"))
                }
                .font(.system(size: 12.5, weight: .semibold))
                .frame(maxWidth: .infinity).padding(.vertical, 8)
                .background(LinearGradient(colors: [Pal.purple, Pal.blue], startPoint: .leading, endPoint: .trailing))
                .foregroundColor(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(spacing: 8) {
                Toggle(isOn: $settings.autoPurge) {
                    Text("\(loc.t("autoclean_short")) · 🔴").font(.system(size: 10.5)).foregroundColor(Pal.sub).lineLimit(1)
                }
                .toggleStyle(.switch).controlSize(.mini).tint(Pal.blue)
                Spacer(minLength: 4)
                Button(action: onWindow) {
                    Image(systemName: "macwindow").font(.system(size: 11)).foregroundColor(Pal.sub)
                }
                .buttonStyle(.plain)
                Button(action: onInsights) {
                    Image(systemName: "chart.xyaxis.line").font(.system(size: 11)).foregroundColor(Pal.sub)
                }
                .buttonStyle(.plain)
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill").font(.system(size: 11)).foregroundColor(Pal.sub)
                }
                .buttonStyle(.plain)
                Button(action: onQuit) {
                    Text(loc.t("quit")).font(.system(size: 10.5, weight: .medium)).foregroundColor(Pal.sub)
                }
                .buttonStyle(.plain)
            }
        }
    }
}

struct SettingsView: View {
    @ObservedObject var settings: AppSettings
    @ObservedObject private var loc = Loc.shared
    @State private var purgeRule: Bool?          // nil until checked

    private var version: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            section(loc.t("general")) {
                row(loc.t("language")) {
                    segmented($loc.lang, Loc.langs.map { ($0, Loc.langName[$0] ?? $0) })
                }
                rowDivider
                row(loc.t("launch_login"), loc.t("launch_login_desc")) { toggle($settings.launchAtLogin) }
            }

            section(loc.t("menu_bar")) {
                row(loc.t("bar_metric")) {
                    segmented($settings.barMode, BarMode.allCases.map {
                        ($0.rawValue, $0 == .network ? loc.t("network") : $0.label)
                    })
                }
                rowDivider
                row(loc.t("update_interval")) {
                    segmented($settings.intervalSec, [(1, "1s"), (2, "2s"), (3, "3s")])
                }
                rowDivider
                row(loc.t("network_unit")) {
                    segmented($settings.speedBits, [(true, "Mb/s"), (false, "MB/s")])
                }
            }

            section(loc.t("cards")) {
                cardRow("memorychip", loc.t("memory"), .constant(true), locked: true)
                rowDivider
                cardRow("cpu", loc.t("processor"), $settings.showCPU)
                rowDivider
                cardRow("globe", loc.t("network"), $settings.showNetwork)
                rowDivider
                cardRow("internaldrive", loc.t("storage"), $settings.showStorage)
                rowDivider
                cardRow("list.bullet", loc.t("top"), $settings.showTop)
            }

            section(loc.t("memory")) {
                row(loc.t("auto_clean"), loc.t("auto_clean_desc"),
                    warning: settings.autoPurge && purgeRule == false ? loc.t("purge_rule_missing") : nil) {
                    toggle($settings.autoPurge)
                }
                rowDivider
                row(loc.t("notifications"), loc.t("notify_desc")) { toggle($settings.notify) }
            }

            Text("Mac Monitor \(version)")
                .font(.system(size: 10.5)).foregroundColor(Pal.sub)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .padding(20)
        .frame(width: 420)
        .background(Pal.bg)
        .task {
            // runs `sudo -n -l`, which only checks the rule; it never purges
            purgeRule = await Task.detached(priority: .utility) { purgeRuleInstalled() }.value
        }
    }

    // MARK: Building blocks

    @ViewBuilder
    func section<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 11.5, weight: .semibold)).foregroundColor(Pal.headerGray)
                .padding(.leading, 4)
            VStack(spacing: 0) { content() }
                .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Pal.card))
                .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Pal.cardBorder, lineWidth: 1))
        }
    }

    var rowDivider: some View {
        Rectangle().fill(Pal.cardBorder).frame(height: 1).padding(.leading, 14)
    }

    @ViewBuilder
    func row<Control: View>(_ title: String, _ detail: String? = nil, warning: String? = nil,
                            icon: String? = nil, @ViewBuilder _ control: () -> Control) -> some View {
        HStack(alignment: .center, spacing: 10) {
            if let icon {
                Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Pal.headerGray).frame(width: 18)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 12.5, weight: .medium)).foregroundColor(.white)
                if let detail {
                    Text(detail).font(.system(size: 10.5)).foregroundColor(Pal.sub)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let warning {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 10.5)).foregroundColor(Pal.yellow)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 8)
            control()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(minHeight: 44)
    }

    func cardRow(_ symbol: String, _ title: String, _ on: Binding<Bool>, locked: Bool = false) -> some View {
        row(title, locked ? loc.t("always_shown") : nil, icon: symbol) { toggle(on).disabled(locked) }
    }

    func toggle(_ on: Binding<Bool>) -> some View {
        Toggle("", isOn: on).toggleStyle(.switch).controlSize(.small).labelsHidden().tint(Pal.blue)
    }

    func segmented<T: Hashable>(_ sel: Binding<T>, _ options: [(T, String)]) -> some View {
        Picker("", selection: sel) {
            ForEach(options, id: \.0) { Text($0.1).tag($0.0) }
        }
        .pickerStyle(.segmented).labelsHidden().fixedSize()   // natural width, right-aligned by the row
    }
}

struct DashboardView: View {
    @ObservedObject var stats: Stats
    @ObservedObject var settings: AppSettings
    let onClean: () -> Void
    let onQuit: () -> Void
    let onSettings: () -> Void
    let onInsights: () -> Void
    let onWindow: () -> Void
    var body: some View {
        VStack(spacing: 9) {
            HStack(spacing: 7) {
                Circle().fill(pressureColor(stats.pressure)).frame(width: 7, height: 7)
                Text("Mac Monitor").font(.system(size: 12.5, weight: .bold)).foregroundColor(.white)
                Spacer()
            }
            MemoryCard(stats: stats)
            if settings.showCPU || settings.showNetwork {
                HStack(alignment: .top, spacing: 9) {
                    if settings.showCPU { CPUCard(stats: stats) }
                    if settings.showNetwork { NetworkCard(stats: stats, settings: settings) }
                }
                .frame(height: 134)
            }
            if settings.showStorage { StorageCard(stats: stats) }
            if settings.showTop { TopCard(stats: stats) }
            Footer(settings: settings, onClean: onClean, onQuit: onQuit, onSettings: onSettings, onInsights: onInsights, onWindow: onWindow)
        }
        .padding(12)
        .frame(width: 380)
        .background(Pal.bg)
    }
}
