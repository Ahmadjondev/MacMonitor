import Foundation
import Darwin
import IOKit
import IOKit.ps

// MARK: - CPU extras

/// 1 / 5 / 15-minute load averages.
func loadAverage() -> [Double] {
    var l = [Double](repeating: 0, count: 3)
    getloadavg(&l, 3)
    return l
}

/// Total process count and (best-effort) thread count. A little heavy (loops all
/// pids), so call it only while the window is visible.
func processThreadCounts() -> (procs: Int, threads: Int) {
    let need = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
    guard need > 0 else { return (0, 0) }
    let cap = Int(need) / MemoryLayout<pid_t>.stride + 32
    var pids = [pid_t](repeating: 0, count: cap)
    let got = proc_listpids(UInt32(PROC_ALL_PIDS), 0, &pids, Int32(cap * MemoryLayout<pid_t>.stride))
    let count = Int(got) / MemoryLayout<pid_t>.stride
    var procs = 0, threads = 0
    for i in 0..<count where pids[i] > 0 {
        procs += 1
        var ti = proc_taskinfo()
        let r = proc_pidinfo(pids[i], PROC_PIDTASKINFO, 0, &ti, Int32(MemoryLayout<proc_taskinfo>.size))
        if r == Int32(MemoryLayout<proc_taskinfo>.size) { threads += Int(ti.pti_threadnum) }
    }
    return (procs, threads)
}

// MARK: - Network extras

struct NetIface: Identifiable {
    var id: String { name }
    let name: String
    let rx: Double   // cumulative bytes
    let tx: Double
}

/// Per-interface cumulative bytes (non-loopback) + total packets in/out.
func netDetail() -> (ifaces: [NetIface], packetsIn: Double, packetsOut: Double) {
    var addr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&addr) == 0 else { return ([], 0, 0) }
    defer { freeifaddrs(addr) }
    var out: [NetIface] = []
    var pin: Double = 0, pout: Double = 0
    var p = addr
    while let cur = p {
        let ifa = cur.pointee
        if let a = ifa.ifa_addr, Int32(a.pointee.sa_family) == AF_LINK {
            let name = String(cString: ifa.ifa_name)
            if !name.hasPrefix("lo"), let raw = ifa.ifa_data {
                let d = raw.assumingMemoryBound(to: if_data.self).pointee
                pin += Double(d.ifi_ipackets); pout += Double(d.ifi_opackets)
                if d.ifi_ibytes > 0 || d.ifi_obytes > 0 {
                    out.append(NetIface(name: name, rx: Double(d.ifi_ibytes), tx: Double(d.ifi_obytes)))
                }
            }
        }
        p = ifa.ifa_next
    }
    out.sort { $0.rx + $0.tx > $1.rx + $1.tx }
    return (out, pin, pout)
}

// MARK: - Battery

struct BatteryInfo {
    var percent = 0
    var charging = false
    var onAC = false
    var timeMin = -1        // minutes to empty/full (-1 = unknown / calculating)
    var cycles = 0
    var tempC = 0.0
    var voltage = 0.0       // V
    var amperage = 0.0      // A (signed)
    var maxCap = 0.0        // mAh
    var designCap = 0.0     // mAh
    var adapterW = 0.0
    var healthPct: Int { designCap > 0 ? Int((maxCap / designCap * 100).rounded()) : 0 }
    var powerW: Double { abs(voltage * amperage) }
}

func readBattery() -> BatteryInfo? {
    var b = BatteryInfo()
    var present = false

    if let blob = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
       let list = IOPSCopyPowerSourcesList(blob)?.takeRetainedValue() as? [CFTypeRef] {
        for ps in list {
            guard let desc = IOPSGetPowerSourceDescription(blob, ps)?.takeUnretainedValue() as? [String: Any] else { continue }
            present = true
            if let c = desc[kIOPSCurrentCapacityKey] as? Int { b.percent = c }
            if let s = desc[kIOPSPowerSourceStateKey] as? String { b.onAC = (s == kIOPSACPowerValue) }
            if let ch = desc[kIOPSIsChargingKey] as? Bool { b.charging = ch }
            if let t = desc[kIOPSTimeToEmptyKey] as? Int, t > 0 { b.timeMin = t }
            if let t = desc[kIOPSTimeToFullChargeKey] as? Int, t > 0 { b.timeMin = t }
        }
    }

    var it = io_iterator_t()
    if IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"), &it) == KERN_SUCCESS {
        var svc = IOIteratorNext(it)
        while svc != 0 {
            var props: Unmanaged<CFMutableDictionary>?
            if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
               let d = props?.takeRetainedValue() as? [String: Any] {
                present = true
                if let c = d["CycleCount"] as? Int { b.cycles = c }
                if let t = d["Temperature"] as? Int { b.tempC = Double(t) / 100.0 }
                if let v = d["Voltage"] as? Int { b.voltage = Double(v) / 1000.0 }
                if let a = d["Amperage"] as? Int { b.amperage = Double(a) / 1000.0 }
                if let m = d["AppleRawMaxCapacity"] as? Int { b.maxCap = Double(m) }
                else if let m = d["MaxCapacity"] as? Int { b.maxCap = Double(m) }
                if let dc = d["DesignCapacity"] as? Int { b.designCap = Double(dc) }
                if let ad = d["AdapterDetails"] as? [String: Any], let w = ad["Watts"] as? Int { b.adapterW = Double(w) }
            }
            IOObjectRelease(svc); svc = IOIteratorNext(it)
        }
        IOObjectRelease(it)
    }
    return present ? b : nil
}

// MARK: - GPU

/// GPU utilization % (best across accelerators), or nil if unavailable.
func gpuUtilization() -> Double? {
    var it = io_iterator_t()
    guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &it) == KERN_SUCCESS else { return nil }
    defer { IOObjectRelease(it) }
    var best: Double? = nil
    var svc = IOIteratorNext(it)
    while svc != 0 {
        var props: Unmanaged<CFMutableDictionary>?
        if IORegistryEntryCreateCFProperties(svc, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
           let d = props?.takeRetainedValue() as? [String: Any],
           let perf = d["PerformanceStatistics"] as? [String: Any] {
            let u = (perf["Device Utilization %"] as? Int) ?? (perf["GPU Activity(%)"] as? Int)
            if let u = u { best = max(best ?? 0, Double(u)) }
        }
        IOObjectRelease(svc); svc = IOIteratorNext(it)
    }
    return best
}
