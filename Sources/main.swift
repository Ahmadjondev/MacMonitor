import SwiftUI
import AppKit
import Combine
import Foundation
import Darwin
import UserNotifications

// MARK: - App entry point

class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSPopoverDelegate {
    let stats = Stats()
    let settings = AppSettings()
    var statusItem: NSStatusItem!
    let popover = NSPopover()
    var settingsWindow: NSWindow?
    var insightsWindow: NSWindow?
    var mainWindow: NSWindow?
    var welcomeWindow: NSWindow?
    var timer: Timer?
    var cancellables = Set<AnyCancellable>()
    var lastAutoPurge = Date.distantPast
    var lastNotify = Date.distantPast
    var prevBusy = 0.0, prevTotal = 0.0
    var prevUser = 0.0, prevSys = 0.0, prevIdle = 0.0, prevNice = 0.0
    var prevCoreBusy: [Double] = [], prevCoreTotal: [Double] = []
    var prevRx: UInt64 = 0, prevTx: UInt64 = 0
    var lastNetTime = Date()
    var prevRead: UInt64 = 0, prevWrite: UInt64 = 0
    var prevReadOps: UInt64 = 0, prevWriteOps: UInt64 = 0
    var startReadBytes = 0.0, startWriteBytes = 0.0
    var lastDiskTime = Date()
    var dashboard: NSViewController!          // popover content; detached while closed
    var cachedCap: (used: Double, total: Double, name: String) = (0, 1, "Disk")
    var lastCapTime = Date.distantPast, capInFlight = false
    var lastTopTime = Date.distantPast, topInFlight = false
    var lastBarKey = ""                        // text last drawn in the menu bar
    /// Actually on screen: not closed, minimized, fully covered, or on another Space.
    func onScreen(_ w: NSWindow?) -> Bool { w?.isVisible == true && w?.occlusionState.contains(.visible) == true }
    var windowVisible: Bool { onScreen(mainWindow) }
    /// Anything on screen that renders `Stats`. When false, ticks publish nothing.
    var uiVisible: Bool { popover.isShown || windowVisible || onScreen(insightsWindow) }
    let barFont = NSFont.monospacedDigitSystemFont(ofSize: 10, weight: .semibold)
    let barFontBig = NSFont.monospacedDigitSystemFont(ofSize: 13, weight: .semibold)

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        if let b = statusItem.button {
            b.action = #selector(togglePopover(_:))
            b.target = self
            b.imagePosition = .imageOnly
        }

        seedRateCounters()
        startReadBytes = Double(prevRead); startWriteBytes = Double(prevWrite)
        cachedCap = diskCapacity(); lastCapTime = Date()
        refreshTopIfNeeded()   // prefetch so the first popover open isn't empty

        popover.behavior = .transient
        popover.animates = true
        popover.appearance = NSAppearance(named: .darkAqua)
        popover.delegate = self
        let hosting = NSHostingController(rootView:
            DashboardView(
                stats: stats,
                settings: settings,
                onClean: { DispatchQueue.global().async { runPurge(interactive: true) } },
                onQuit: { NSApplication.shared.terminate(nil) },
                onSettings: { [weak self] in self?.openSettings() },
                onInsights: { [weak self] in self?.openInsights() },
                onWindow: { [weak self] in self?.openMainWindow() }))
        hosting.sizingOptions = [.preferredContentSize]
        dashboard = hosting
        popover.contentViewController = hosting

        // react to settings changes: restart timer (interval) + refresh the bar
        settings.objectWillChange
            .sink { [weak self] in DispatchQueue.main.async { self?.applySettings() } }
            .store(in: &cancellables)

        update()
        startTimer()

        // nobody can see the menu bar while the displays sleep: stop ticking until they wake
        let ws = NSWorkspace.shared.notificationCenter
        ws.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.timer?.invalidate(); self?.timer = nil
        }
        ws.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            guard let self, self.timer == nil else { return }
            self.seedRateCounters()   // otherwise the first rates average over the whole sleep
            self.update(); self.startTimer()
        }

        let onboarded = UserDefaults.standard.bool(forKey: "didOnboard")
        let userLaunched = !CommandLine.arguments.contains("--menubar")
        if !onboarded {
            DispatchQueue.main.async { [weak self] in self?.openWelcome() }      // first ever launch
        } else if userLaunched {
            DispatchQueue.main.async { [weak self] in self?.openMainWindow() }   // user double-clicked
        }
    }

    /// Baselines for the network and disk rate deltas, so the next sample isn't a spike.
    func seedRateCounters() {
        let n = netCounters()
        prevRx = n.rx; prevTx = n.tx
        lastNetTime = Date()
        let io = diskIO()
        prevRead = io.read; prevWrite = io.write
        prevReadOps = io.rops; prevWriteOps = io.wops
        lastDiskTime = Date()
    }

    func startTimer() {
        timer?.invalidate()
        let interval = TimeInterval(max(1, settings.intervalSec))
        timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in self?.update() }
        timer?.tolerance = interval * 0.1   // lets macOS coalesce wakeups
    }

    func applySettings() {
        if timer != nil { startTimer() }   // nil while the displays sleep; wake restarts it
        updateStatusBar()
        applyLaunchAtLogin(settings.launchAtLogin)
        if settings.notify {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
        }
    }

    /// Reflects the "launch at login" toggle by writing/removing the LaunchAgent plist.
    /// Does NOT bootout (so the running app is never killed); takes effect next login.
    func applyLaunchAtLogin(_ on: Bool) {
        let fm = FileManager.default
        let exists = fm.fileExists(atPath: kLaunchAgentPath)
        if on && !exists {
            let exe = Bundle.main.executableURL?.path ?? "/Applications/Mac Monitor.app/Contents/MacOS/MacMonitor"
            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key><string>app.macmonitor.MacMonitor</string>
                <key>ProgramArguments</key><array><string>\(exe)</string><string>--menubar</string></array>
                <key>RunAtLoad</key><true/>
                <key>ProcessType</key><string>Interactive</string>
            </dict>
            </plist>
            """
            try? plist.write(toFile: kLaunchAgentPath, atomically: true, encoding: .utf8)
        } else if !on && exists {
            try? fm.removeItem(atPath: kLaunchAgentPath)
        }
    }

    // MARK: Status bar rendering

    func renderImage(_ str: NSAttributedString, width: CGFloat, height: CGFloat) -> NSImage {
        let textH = str.size().height
        let img = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            str.draw(in: NSRect(x: 0, y: (height - textH) / 2, width: width, height: textH))
            return true
        }
        img.isTemplate = true   // adapts to light/dark menu bar
        return img
    }

    func updateStatusBar() {
        let mode = settings.barMode, bits = settings.speedBits
        let text: String
        switch mode {
        case 1:  text = "RAM \(Int(stats.usedPercent.rounded()))%"
        case 2:  text = "CPU \(Int(stats.cpu.rounded()))%"
        default: text = "↓\t\(speedStr(stats.downSpeed, bits: bits))\n↑\t\(speedStr(stats.upSpeed, bits: bits))"
        }
        // a new image makes AppKit re-snapshot the item on every display; most ticks
        // show the same text, so skip them
        let key = "\(mode)|\(bits)|\(text)"
        guard key != lastBarKey else { return }
        lastBarKey = key

        let height = NSStatusBar.system.thickness
        let width: CGFloat
        let para = NSMutableParagraphStyle()

        switch mode {
        case 1, 2: // RAM % / CPU %
            para.alignment = .center
            width = ceil(NSAttributedString(string: "\(mode == 1 ? "RAM" : "CPU") 100%", attributes: [.font: barFontBig]).size().width) + 6
        default: // network speed (two lines)
            // fixed width = widest value speedStr can produce in this unit, so it never clips
            width = speedStrWidest(bits: bits).map {
                ceil(NSAttributedString(string: "↓ " + $0, attributes: [.font: barFont]).size().width)
            }.max()! + 4
            // arrows pinned left, values right-aligned on a tab stop: nothing shifts as the
            // value width changes, and spare room sits between them instead of trailing
            para.alignment = .left
            para.maximumLineHeight = 10.5
            para.minimumLineHeight = 10.5
            para.firstLineHeadIndent = 2
            para.headIndent = 2
            para.tabStops = [NSTextTab(textAlignment: .right, location: width - 2)]
        }

        let s = NSAttributedString(string: text, attributes: [
            .font: mode == 1 || mode == 2 ? barFontBig : barFont,
            .foregroundColor: NSColor.black, .paragraphStyle: para])
        if statusItem.length != width { statusItem.length = width }
        statusItem.button?.image = renderImage(s, width: width, height: height)
    }

    // MARK: Settings window

    func openSettings() {
        if settingsWindow == nil {
            let vc = NSHostingController(rootView: SettingsView(settings: settings))
            // follow the content: the first layout under-measures wrapped captions, and
            // the sudoers warning can appear after the window is open
            vc.sizingOptions = [.preferredContentSize]
            let win = NSWindow(contentViewController: vc)
            win.title = "Mac Monitor — " + Loc.shared.t("settings")
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: .darkAqua)
            settingsWindow = win
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.center()
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    func openInsights() {
        if insightsWindow == nil {
            let vc = NSHostingController(rootView: InsightsView(stats: stats))
            let win = NSWindow(contentViewController: vc)
            win.title = "Mac Monitor — Insights"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: .darkAqua)
            win.delegate = self
            insightsWindow = win
        }
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        insightsWindow?.center()
        insightsWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: Main app window (full window mode, like a normal app)

    func openMainWindow() {
        if mainWindow == nil {
            let vc = NSHostingController(rootView: AppWindowView(stats: stats, settings: settings))
            let win = NSWindow(contentViewController: vc)
            win.title = "Mac Monitor"
            win.setContentSize(NSSize(width: 780, height: 580))
            win.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: .darkAqua)
            win.delegate = self
            win.center()
            win.setFrameAutosaveName("MainWindow")   // window is rebuilt on each open; keep its frame
            mainWindow = win
        }
        // become a regular app (Dock icon + menu) while the window is open
        NSApp.setActivationPolicy(.regular)
        popover.performClose(nil)
        NSApp.activate(ignoringOtherApps: true)
        mainWindow?.makeKeyAndOrderFront(nil)
    }

    // MARK: First-launch welcome / onboarding

    func openWelcome() {
        if welcomeWindow == nil {
            let vc = NSHostingController(rootView:
                WelcomeView(settings: settings, onDone: { [weak self] in self?.finishOnboarding() }))
            let win = NSWindow(contentViewController: vc)
            win.title = "Mac Monitor"
            win.styleMask = [.titled, .closable]
            win.isReleasedWhenClosed = false
            win.appearance = NSAppearance(named: .darkAqua)
            win.delegate = self
            welcomeWindow = win
        }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        welcomeWindow?.center()
        welcomeWindow?.makeKeyAndOrderFront(nil)
    }

    func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "didOnboard")
        welcomeWindow?.close()
    }

    // coming back into view after being covered / on another Space: refresh at once
    func windowDidChangeOcclusionState(_ notification: Notification) {
        if uiVisible { stats.objectWillChange.send() }
    }

    func windowWillClose(_ notification: Notification) {
        let w = notification.object as? NSWindow
        if w === welcomeWindow {
            UserDefaults.standard.set(true, forKey: "didOnboard")   // closing also counts as done
        }
        // when the main/welcome window closes, drop back to menu-bar-only (hide Dock icon)
        if w === mainWindow || w === welcomeWindow {
            NSApp.setActivationPolicy(.accessory)
        }
        // drop closed windows that render Stats, so their SwiftUI graphs stop updating
        if w === mainWindow { mainWindow = nil }
        if w === insightsWindow { insightsWindow = nil }
    }

    // A closed popover keeps its (off-screen) window; detach the dashboard so it doesn't
    // keep laying out while the main window is open.
    func popoverDidClose(_ notification: Notification) {
        popover.contentViewController = nil
    }

    // Reopen (double-click in Finder / Launchpad / Dock) opens the window again
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        openMainWindow()
        return true
    }

    @objc func togglePopover(_ sender: Any?) {
        guard let b = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(sender)
        } else {
            if popover.contentViewController == nil { popover.contentViewController = dashboard }
            stats.objectWillChange.send()   // the detached view missed updates; refresh it
            refreshTopIfNeeded()            // async; the previous list shows until it lands
            NSApp.activate(ignoringOtherApps: true)
            popover.show(relativeTo: b.bounds, of: b, preferredEdge: .minY)
        }
    }

    func sampleNetwork() {
        let now = Date()
        let dt = max(0.2, now.timeIntervalSince(lastNetTime))
        let n = netCounters()
        let drx = n.rx >= prevRx ? Double(n.rx - prevRx) : 0
        let dtx = n.tx >= prevTx ? Double(n.tx - prevTx) : 0
        prevRx = n.rx; prevTx = n.tx; lastNetTime = now
        stats.downSpeed = drx / dt
        stats.upSpeed = dtx / dt
        stats.totalRx = Double(n.rx)
        stats.totalTx = Double(n.tx)
        stats.localIP = localIPv4()
    }

    func sampleDisk() {
        let now = Date()
        let dt = max(0.2, now.timeIntervalSince(lastDiskTime))
        let io = diskIO()
        let dr  = io.read  >= prevRead     ? Double(io.read  - prevRead)     : 0
        let dw  = io.write >= prevWrite    ? Double(io.write - prevWrite)    : 0
        let dro = io.rops  >= prevReadOps  ? Double(io.rops  - prevReadOps)  : 0
        let dwo = io.wops  >= prevWriteOps ? Double(io.wops  - prevWriteOps) : 0
        prevRead = io.read; prevWrite = io.write
        prevReadOps = io.rops; prevWriteOps = io.wops; lastDiskTime = now
        refreshCapacityIfNeeded()
        let cap = cachedCap
        var d = stats.disk
        d.used = cap.used; d.total = cap.total; d.name = cap.name
        d.readSpeed = dr / dt; d.writeSpeed = dw / dt
        d.readOps = dro / dt; d.writeOps = dwo / dt
        d.sessionRead = max(0, Double(io.read) - startReadBytes)
        d.sessionWritten = max(0, Double(io.write) - startWriteBytes)
        stats.disk = d
    }

    func cpuUsage() -> Double {
        var size = mach_msg_type_number_t(MemoryLayout<host_cpu_load_info_data_t>.stride / MemoryLayout<integer_t>.stride)
        var info = host_cpu_load_info_data_t()
        let kr = withUnsafeMutablePointer(to: &info) { p -> kern_return_t in
            p.withMemoryRebound(to: integer_t.self, capacity: Int(size)) { ip in
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, ip, &size)
            }
        }
        guard kr == KERN_SUCCESS else { return 0 }
        let user = Double(info.cpu_ticks.0), sys = Double(info.cpu_ticks.1)
        let idle = Double(info.cpu_ticks.2), nice = Double(info.cpu_ticks.3)
        let busy = user + sys + nice
        let total = busy + idle
        let dUser = (user + nice) - (prevUser + prevNice)
        let dSys = sys - prevSys, dIdle = idle - prevIdle
        let db = busy - prevBusy, dt = total - prevTotal
        prevUser = user; prevNice = nice; prevSys = sys; prevIdle = idle
        prevBusy = busy; prevTotal = total
        guard dt > 0 else { return 0 }
        stats.cpuUser = max(0, min(100, dUser / dt * 100))
        stats.cpuSys  = max(0, min(100, dSys / dt * 100))
        stats.cpuIdle = max(0, min(100, dIdle / dt * 100))
        return max(0, min(100, db / dt * 100))
    }

    func perCoreUsage() -> [Double] {
        var count: natural_t = 0
        var infoPtr: processor_info_array_t!
        var infoCnt: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &count, &infoPtr, &infoCnt) == KERN_SUCCESS else {
            return prevCoreBusy.map { _ in 0 }
        }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(UInt(bitPattern: infoPtr)),
                          vm_size_t(infoCnt) * vm_size_t(MemoryLayout<integer_t>.stride))
        }
        let n = Int(count)
        let states = Int(CPU_STATE_MAX)
        if prevCoreBusy.count != n { prevCoreBusy = Array(repeating: 0, count: n); prevCoreTotal = Array(repeating: 0, count: n) }
        var out = [Double](repeating: 0, count: n)
        for i in 0..<n {
            let base = states * i
            let user = Double(infoPtr[base + Int(CPU_STATE_USER)])
            let sys  = Double(infoPtr[base + Int(CPU_STATE_SYSTEM)])
            let idle = Double(infoPtr[base + Int(CPU_STATE_IDLE)])
            let nice = Double(infoPtr[base + Int(CPU_STATE_NICE)])
            let busy = user + sys + nice
            let total = busy + idle
            let db = busy - prevCoreBusy[i], dt = total - prevCoreTotal[i]
            prevCoreBusy[i] = busy; prevCoreTotal[i] = total
            out[i] = dt > 0 ? max(0, min(100, db / dt * 100)) : 0
        }
        return out
    }

    /// Volume capacity is slow to query (15–40 ms, and it makes the system recount
    /// purgeable space) and changes slowly: refresh it off the main thread every 30 s
    /// while a dashboard is on screen, otherwise every 5 min (history only).
    func refreshCapacityIfNeeded() {
        let maxAge: TimeInterval = uiVisible ? 30 : 300
        guard !capInFlight, Date().timeIntervalSince(lastCapTime) >= maxAge else { return }
        capInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let cap = diskCapacity()
            DispatchQueue.main.async {
                self?.cachedCap = cap; self?.lastCapTime = Date(); self?.capInFlight = false
            }
        }
    }

    /// `ps` takes ~90 ms: run it off the main thread, at most every 3 s.
    func refreshTopIfNeeded() {
        guard !topInFlight, Date().timeIntervalSince(lastTopTime) >= 3 else { return }
        topInFlight = true
        DispatchQueue.global(qos: .utility).async { [weak self] in
            let top = topConsumers(limit: 5)
            DispatchQueue.main.async {
                guard let self else { return }
                self.lastTopTime = Date(); self.topInFlight = false
                if self.uiVisible { self.stats.objectWillChange.send() }
                self.stats.top = top
            }
        }
    }

    func update() {
        // one invalidation per tick, and none while nothing is on screen
        if uiVisible { stats.objectWillChange.send() }
        stats.mem = memoryStats()
        stats.pressure = pressureLevel()
        let c = cpuUsage()
        stats.cpu = c
        var h = stats.cpuHistory
        h.append(c)
        if h.count > 26 { h.removeFirst(h.count - 26) }
        stats.cpuHistory = h
        stats.coreUsage = perCoreUsage()
        stats.loadAvg = loadAverage()
        sampleNetwork()
        sampleDisk()

        // top processes spawn `ps`; only while a dashboard is visible
        if popover.isShown || windowVisible { refreshTopIfNeeded() }

        // advanced, app-only detail — computed only while the full window is open
        if windowVisible {
            let pt = processThreadCounts()
            stats.processCount = pt.procs; stats.threadCount = pt.threads
            let nd = netDetail()
            stats.packetsIn = nd.packetsIn; stats.packetsOut = nd.packetsOut; stats.interfaces = nd.ifaces
            stats.battery = readBattery()
            stats.gpu = gpuUtilization()
        }

        updateStatusBar()

        History.shared.add(Sample(
            t: Date().timeIntervalSinceReferenceDate,
            ram: stats.usedPercent, cpu: c, disk: stats.disk.usedPercent,
            down: stats.downSpeed, up: stats.upSpeed, pressure: stats.pressure))

        if stats.pressure == 4 {
            if settings.autoPurge && Date().timeIntervalSince(lastAutoPurge) > 60 {
                lastAutoPurge = Date()
                DispatchQueue.global().async { runPurge(interactive: false) }
            }
            if settings.notify && Date().timeIntervalSince(lastNotify) > 300 {
                lastNotify = Date()
                notifyCritical()
            }
        }
    }

    func notifyCritical() {
        let c = UNUserNotificationCenter.current()
        let content = UNMutableNotificationContent()
        content.title = "Mac Monitor"
        content.body = String(format: "⚠️ Memory pressure critical · %.0f%% used", stats.usedPercent)
        content.sound = .default
        c.add(UNNotificationRequest(identifier: "pressure", content: content, trigger: nil))
    }
}

// `--version` prints and exits before any UI starts (build.sh runs it once, see there)
if CommandLine.arguments.contains("--version") {
    print(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
    exit(0)
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
