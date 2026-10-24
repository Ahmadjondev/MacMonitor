# Architecture

Developer notes for Mac Monitor. The [README](../README.md) has the user-facing
overview; this file covers how the code is put together and the rules that keep it
working.

## Design philosophy

On macOS, low "free RAM" is normal and healthy: the kernel uses otherwise idle memory as
file cache. The number that matters is **memory pressure**, not free %. "RAM cleaners"
that purge on a timer evict useful cache and make the system slower. Mac Monitor
therefore runs `purge` only when you press **Clean now**, or automatically only while
pressure is **critical (red)**, and at most once every 60 s.

## Building blocks

There is no Xcode project and no package manager. `build.sh` copies `Info.plist` and
`Resources/AppIcon.icns` into a bundle, then `scripts/compile.sh` runs `swiftc` once per
architecture (`-target arm64-apple-macos13.0` / `x86_64-apple-macos13.0`) and joins the
results with `lipo`. The bundle is ad-hoc signed with `codesign --sign -`.

Swift allows top-level code only in `main.swift`. Everything else in `Sources/` is
declarations. The preview tools in `tools/` have their own `@main` and are compiled with
`-parse-as-library` together with the source files they render.

| File | Role |
|---|---|
| `Sources/main.swift` | `AppDelegate`: status item, popover, windows, the sampling timer, purge/notification triggers, LaunchAgent writer, app bootstrap. |
| `Sources/Core.swift` | Palette, core readings (memory, pressure, network, disk, top apps, purge), `Stats` and `AppSettings` observable state, all dashboard cards, `SettingsView`, `DashboardView`. |
| `Sources/Advanced.swift` | Window-only readings: load average, process/thread counts, packets and per-interface totals, battery, GPU. |
| `Sources/History.swift` | `Sample` and `History`: rolling in-memory samples plus persisted 1-minute aggregates. |
| `Sources/Insights.swift` | `AreaChart` and `InsightsView` (RAM/CPU charts with now/average/peak). |
| `Sources/MainWindow.swift` | `AppWindowView` (`NavigationSplitView` sidebar: Dashboard / Insights / Settings) and `WindowDashboard`. |
| `Sources/Welcome.swift` | First-launch onboarding: language, notifications, launch at login. |
| `Sources/Localization.swift` | `Loc`: the EN/RU/UZ string table and runtime language switch. |

## Sampling loop

`AppDelegate.update()` runs on a main-run-loop `Timer` every 1, 2 or 3 s (Settings →
Update rate, 10% tolerance so macOS can coalesce wakeups). Each tick it:

1. reads memory, pressure, CPU (total and per core), load average and network counters,
   all sub-millisecond calls;
2. reads disk I/O counters, and uses a cached volume capacity that a background queue
   refreshes every 30 s while a dashboard is on screen, otherwise every 5 min
   (`diskCapacity()` takes 15–40 ms and makes the system recount purgeable space);
3. while the popover or main window is on screen, asks a background queue to rerun `ps`
   for the top-apps list, at most every 3 s (`ps` takes ~90 ms). The previous list stays
   on screen until the new one arrives;
4. reads processes/threads, packets/interfaces, battery and GPU **only** while the main
   window is on screen (`windowVisible`);
5. redraws the menu-bar image, but only if its text changed;
6. appends a `Sample` to `History`;
7. if pressure is critical, triggers auto-clean and/or a notification (both opt-in and
   throttled).

### Keeping the UI cheap

The app wakes every second for its whole life, so idle cost matters more than anything.
It stays around 1% CPU because of these rules:

- **`Stats` has plain properties, not `@Published`.** The tick fills them and then sends
  **one** `objectWillChange`, and only if some UI is on screen (`uiVisible`). Publishing
  ~25 properties every tick made every hosting view, even hidden ones, re-run layout
  continuously. `History.recent` is not published for the same reason.
- **"On screen" means really visible**: `isVisible` *and*
  `occlusionState.contains(.visible)`, so a minimized, covered or other-Space window
  doesn't count. `windowDidChangeOcclusionState` refreshes a window as it comes back.
- **Closed windows are released.** The main and Insights windows are rebuilt on each
  open (the main window keeps its frame via `setFrameAutosaveName`). The popover's
  dashboard is detached in `popoverDidClose` and re-attached before showing, with a
  forced refresh.
- **Nothing slow runs on the main thread.** `ps` and volume capacity run on a utility
  queue and post results back.
- **No per-tick animations.** The donut's conic gradient is rendered on the CPU, so the
  ring snaps to whole percents and only animates when the visible value changes.
- **The menu-bar image is only replaced when its text changes.** Setting a new image
  makes AppKit re-snapshot the status item for every display, which is about 70% of the
  app's idle CPU. `lastBarKey` (mode + unit + text) skips identical ticks. This helps in
  RAM/CPU mode and on a quiet network; with live traffic the speed text changes almost
  every tick, so the update interval is the only real lever.
- **No ticking while the displays sleep.** `screensDidSleepNotification` stops the timer;
  `screensDidWakeNotification` re-seeds the rate counters and restarts it. History has
  a gap for that time, and auto-clean and notifications pause with it.

Rates (network speed, disk throughput, IOPS, CPU %) are deltas of cumulative kernel
counters divided by elapsed time. Network and disk counters are seeded at launch and on
display wake (`seedRateCounters()`) so the first sample is not a spike; a counter that goes backwards (reset or wrap) yields 0 for
that tick instead of a huge number.

## Where each number comes from

### Memory (`memoryStats()`, `pressureLevel()`)
- `host_statistics64(HOST_VM_INFO64)` page counts × `host_page_size`:
  - **App** = `internal_page_count − purgeable_count`
  - **Wired** = `wire_count`
  - **Compressed** = `compressor_page_count`
  - **Cached** = `external_page_count` (file-backed pages)
  - **Used** = App + Wired + Compressed, which closely matches Activity Monitor's
    "Memory Used".
- **Total** = `sysctlbyname("hw.memsize")`.
- **Swap** = `sysctlbyname("vm.swapusage")` (`xsw_usage.xsu_used` / `xsu_total`).
- **Pressure** = `sysctlbyname("kern.memorystatus_vm_pressure_level")`:
  1 = normal (green), 2 = warning (yellow), 4 = critical (red). The pressure graph plots
  a fixed height per level (`pressureH`).

### CPU (`cpuUsage()`, `perCoreUsage()` in `main.swift`; `loadAverage()`, `processThreadCounts()`)
- Total: `host_statistics(HOST_CPU_LOAD_INFO)` tick deltas. busy = user + system + nice;
  usage = Δbusy / Δ(busy + idle). The window also shows the User (user + nice), System
  and Idle split.
- Per core: `host_processor_info(PROCESSOR_CPU_LOAD_INFO)` with the same formula per
  processor. The returned buffer is released with `vm_deallocate`.
- Load average: `getloadavg` (1 / 5 / 15 min).
- Processes / threads: `proc_listpids(PROC_ALL_PIDS)`, then
  `proc_pidinfo(PROC_PIDTASKINFO).pti_threadnum` per pid. Without root some pids can't be
  inspected, so the thread count is a best-effort lower bound.

### Network (`netCounters()`, `localIPv4()`, `netDetail()`)
- `getifaddrs`, `AF_LINK` entries, every interface except loopback (`lo*`):
  `if_data.ifi_ibytes` / `ifi_obytes` summed, then differenced over time for ↓/↑ speed.
- **Total** in the Network card shows those cumulative kernel counters (since each
  interface came up), not traffic since the app started.
- Packets: `ifi_ipackets` / `ifi_opackets`. Per-interface rows list interfaces that have
  moved any bytes, busiest first.
- Local IP: the first `AF_INET` address on an `en*` interface, preferring `en0`,
  formatted with `getnameinfo(NI_NUMERICHOST)`.
- **Known limitation:** `struct if_data` counters are 32-bit, so per-interface totals
  wrap after 4 GiB. Speeds are unaffected apart from one dropped sample at the wrap.
  Moving to `sysctl(NET_RT_IFLIST2)` / `if_data64` would fix the totals.

### Storage (`diskCapacity()`, `diskIO()`)
- Capacity: `URL(fileURLWithPath: "/").resourceValues` →
  `volumeTotalCapacity`, `volumeAvailableCapacityForImportantUsage`, `volumeName`.
  Used = total − available-for-important-usage (purgeable space counts as free, as in
  Finder). Sizes use decimal GB (÷ 10⁹), as Finder does. Memory uses binary GiB.
- I/O: IOKit, every `IOBlockStorageDriver` service, its `Statistics` dictionary:
  `Bytes (Read)`, `Bytes (Write)`, `Operations (Read)`, `Operations (Write)`, summed.
  Deltas give read/write throughput and IOPS; "Session" is the total since app launch.

### Battery (`readBattery()`, window only)
- `IOPSCopyPowerSourcesInfo` / `IOPSGetPowerSourceDescription`: charge %, AC vs battery,
  charging, time to empty/full.
- IOKit `AppleSmartBattery` registry entry: `CycleCount`, `Temperature` (÷100 → °C),
  `Voltage` (mV), `Amperage` (mA, signed), `AppleRawMaxCapacity` (or `MaxCapacity`),
  `DesignCapacity` (health = max ÷ design), `AdapterDetails.Watts`.
- The card is hidden on Macs without a battery.

### GPU (`gpuUtilization()`, window only)
- IOKit `IOAccelerator` services, `PerformanceStatistics` → `Device Utilization %` (or
  `GPU Activity(%)`), maximum across accelerators. Hidden if no value is exposed.

### Top apps (`topConsumers()`)
- Spawns `/bin/ps -axo rss=,comm=` and sums resident memory per name. Paths inside an
  `.app` bundle collapse to the app name, so helpers count toward their app. Runs on a
  background queue, at most every 3 s, only while a dashboard is on screen.

## History and Insights (`History.swift`)

- `recent`: the last 180 raw samples in memory (≈3 min at 1 s).
- Every ≥60 s the pending samples are folded into one aggregate (mean of RAM, CPU, disk
  and speeds, **max** of pressure) and appended to `longTerm`, capped at 1,440 entries
  (24 h of 1-minute buckets).
- `longTerm` is written to
  `~/Library/Application Support/MacMonitor/history.json` after every aggregate and
  loaded at launch, so it survives restarts. The cap counts entries, so after downtime
  the file can hold minutes from more than 24 wall-clock hours ago.
- Insights shows *now* and *average* from `recent`, *peak* from `longTerm + recent`, and
  "Critical (24h)" = the number of stored minutes whose max pressure was critical.

## Menu bar rendering

The status item shows a template `NSImage` drawn from an attributed string:
- fixed width, sized for the widest value it can show (`↓ 888 MB/s`, `RAM 100%`), so
  neighbouring menu-bar items never shift. `speedStr` keeps rates to three digits
  (`8.4`, `52`, `999`) and steps up a unit after that, which keeps this width small;
- vertically centred to `NSStatusBar.system.thickness`; resolution-independent, so it
  stays crisp on Retina; `isTemplate = true`, so it follows light/dark menu bars;
- network mode is two lines: arrows pinned left, values right-aligned on a tab stop, so
  nothing moves as digits change and spare room never collects at the right edge.
  RAM/CPU modes are single centred lines.

## Popover sizing rules

The dashboard is SwiftUI inside an `NSPopover` (`.darkAqua`, `.transient`). The popover
must stay content-sized:
- `hosting.sizingOptions = [.preferredContentSize]`;
- no `maxHeight: .infinity` in the root layout: it makes the popover think it is huge
  and pushes it off-screen. The Memory/CPU row is pinned with `.frame(height: 132)` for
  this reason.

`tools/measure.swift` prints the fitting size if you need to debug geometry.

## Hybrid menu-bar / window model

- `Info.plist` sets `LSUIElement`, and `main.swift` also calls
  `setActivationPolicy(.accessory)`, so the app has no Dock icon even when started by
  launchd.
- First launch ever (`didOnboard` unset): the Welcome window opens.
- Later launches without `--menubar` (the user opened the app): the main window opens.
  Launches with `--menubar` (the LaunchAgent): menu bar only.
- While the main or welcome window is open the app switches to `.regular` (Dock icon and
  app menu). `windowWillClose` switches back to `.accessory`.
- `applicationShouldHandleReopen` (Dock, Finder, Launchpad, Spotlight) reopens the main
  window.
- Cards take a `detailed` flag. The window passes `true` and gets extra rows plus the
  Battery and GPU cards; the popover stays compact.

## Launch at login

Turning the setting on writes `~/Library/LaunchAgents/app.macmonitor.MacMonitor.plist`:

```xml
<key>Label</key><string>app.macmonitor.MacMonitor</string>
<key>ProgramArguments</key><array><string>/path/to/MacMonitor</string><string>--menubar</string></array>
<key>RunAtLoad</key><true/>
<key>ProcessType</key><string>Interactive</string>
```

Turning it off deletes the file. The app never calls `launchctl bootout`, so toggling
never kills the running instance; changes take effect at the next login. The setting's
state is simply "does the plist exist". To load it immediately:

```bash
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.macmonitor.MacMonitor.plist
launchctl bootout    gui/$(id -u)/app.macmonitor.MacMonitor
```

macOS applies launch constraints to LaunchAgent spawns. If the first exec of a fresh
ad-hoc binary (a new build or a just-replaced bundle) is the LaunchAgent's, AMFI kills it
(`OS_REASON_CODESIGNING`, "Launch Constraint Violation"); that attempt makes Gatekeeper
scan the binary, so the next spawn works. `build.sh` therefore runs
`MacMonitor --version` once after signing (`spctl --assess` does not trigger the scan).
For users, opening the app once after installing or updating does the same.

## Settings

`SettingsView` is shared by the Settings window and the main window's Settings pane:
grouped cards (General, Menu bar, Cards, Memory) of rows with the label and an optional
caption on the left and the control right-aligned at its natural size. The Settings
window's hosting controller uses `sizingOptions = [.preferredContentSize]`; the default
sizing under-measures wrapped captions on first layout and clipped the view.

## Memory cleaning (`runPurge`)

1. Try `sudo -n /usr/sbin/purge` (non-interactive; succeeds only with the optional
   sudoers rule from the README).
2. If that fails and the user pressed **Clean now**, fall back to
   `osascript -e 'do shell script "/usr/sbin/purge" with administrator privileges'`,
   the standard macOS admin password prompt.
3. Auto-clean (off by default) only calls step 1, only while pressure is critical, and
   at most once per 60 s. Without the sudoers rule it does nothing, so `SettingsView`
   checks for the rule with `purgeRuleInstalled()` (`sudo -n -l /usr/sbin/purge`, a
   lookup that runs nothing) and warns under the Auto-clean switch when it's missing.

Critical-pressure notifications (`UNUserNotificationCenter`, off by default) are
throttled to one every 5 minutes.

## Settings and localization

- `AppSettings` mirrors each property to `UserDefaults` in `didSet`. Keys: `barMode`,
  `intervalSec`, `speedBits`, `autoPurgeEnabled`, `showCPU`, `showNetwork`,
  `showStorage`, `showTop`, `notify`; plus `lang` (`Loc`) and `didOnboard`.
  (`AppSettings`, not `Settings`, to avoid clashing with SwiftUI's `Settings` scene.)
- `Loc.shared` is an `ObservableObject` holding `lang` and a `[key: [lang: string]]`
  table. Every view holds `@ObservedObject private var loc = Loc.shared`, so changing the
  language re-renders everything live. Missing translations fall back to English, then
  to the key. Brand name, numbers, units and volume names are not translated. See
  [CONTRIBUTING.md](../CONTRIBUTING.md#adding-a-language) to add a language.

## Preview tools

`tools/*.swift` render views to PNG with `ImageRenderer` for design review, using mock
data. Pickers and toggles render as placeholder boxes in static renders.

```bash
swiftc -O -parse-as-library Sources/Core.swift Sources/Localization.swift Sources/History.swift \
  Sources/Advanced.swift Sources/Insights.swift tools/preview.swift -o /tmp/mm_preview
/tmp/mm_preview /tmp/dash.png en && open /tmp/dash.png
```

| Tool | Renders |
|---|---|
| `tools/preview.swift` | Popover dashboard (`DashboardView`). Optional 2nd arg: `en` / `ru` / `uz`. |
| `tools/windowpreview.swift` | Full-window dashboard. |
| `tools/insightspreview.swift` | Insights view. |
| `tools/settingspreview.swift` | Settings view. |
| `tools/barpreview.swift` | Menu-bar speed image on a simulated bar. |
| `tools/measure.swift` | Prints the popover's fitting size. |
| `tools/dmgbg.swift` | `assets/dmg-background.png` (640×400). |
| `Resources/icongen.swift` | The app logo, `Resources/icon_1024.png`. |

### Regenerating the icon

```bash
cd Resources
swiftc -O icongen.swift -o /tmp/icongen && /tmp/icongen icon_1024.png
rm -rf AppIcon.iconset && mkdir AppIcon.iconset
for s in 16 32 128 256 512; do
  sips -z $s $s icon_1024.png --out AppIcon.iconset/icon_${s}x${s}.png
  sips -z $((s*2)) $((s*2)) icon_1024.png --out AppIcon.iconset/icon_${s}x${s}@2x.png
done
iconutil -c icns AppIcon.iconset -o AppIcon.icns
```

The logo is a purple→blue→teal gauge ring (~78%) with a white activity sparkline inside
that reads as an "M", on a dark squircle.

## Releasing

- `scripts/release.sh`: universal build, ad-hoc sign, styled drag-to-install
  `dist/MacMonitor.dmg`. The Finder styling step uses AppleScript and may ask for
  Automation permission; if denied you still get a plain DMG.
- `scripts/notarize.sh`: the same with a Developer ID signature, hardened runtime,
  notarization and stapling. It needs a paid Apple Developer account.
- After publishing a DMG, update `version` and `sha256` (`shasum -a 256
  dist/MacMonitor.dmg`) in `Casks/mac-monitor.rb`.
