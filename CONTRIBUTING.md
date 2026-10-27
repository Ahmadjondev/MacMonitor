# Contributing to Mac Monitor

Thanks for helping! Bug reports, feature ideas, translations and pull requests are all
welcome. Please use the issue templates for bugs and features. For anything larger
than a small fix, open an issue first so we can agree on the approach.

Everyone taking part is expected to follow the [Code of Conduct](CODE_OF_CONDUCT.md).
Found a security problem? Don't open an issue; see [SECURITY.md](SECURITY.md).

## Build

You need macOS 13+ and the Xcode Command Line Tools (`xcode-select --install`). There
is no Xcode project and no dependencies.

```bash
git clone https://github.com/Ahmadjondev/MacMonitor.git
cd MacMonitor
./build.sh                                   # → /Applications/Mac Monitor.app
open "/Applications/Mac Monitor.app"
```

`build.sh` wipes and rebuilds the destination bundle. To keep your installed copy, build
elsewhere:

```bash
APP="$PWD/build/Mac Monitor.app" ./build.sh
open "build/Mac Monitor.app"
```

Quit the running app (menu bar → **Quit**) before replacing it. If you use launch at
login and want to restart it the same way:

```bash
launchctl bootout   gui/$(id -u)/app.macmonitor.MacMonitor 2>/dev/null
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/app.macmonitor.MacMonitor.plist
```

CI builds every push and pull request on `macos-latest` with the same
`scripts/compile.sh`, so make sure `./build.sh` succeeds without warnings you
introduced.

### Previewing UI without running the app

The renderers in `tools/` draw views to PNG with mock data, which is handy for design
changes and screenshots:

```bash
swiftc -O -parse-as-library Sources/Core.swift Sources/Localization.swift Sources/History.swift \
  Sources/Advanced.swift Sources/Insights.swift tools/preview.swift -o /tmp/mm_preview
/tmp/mm_preview /tmp/dash.png ru && open /tmp/dash.png      # 2nd arg: en / ru / uz
```

## Code style

Match the code around you. In practice:

- **Plain Swift, no dependencies.** Use system frameworks only (SwiftUI, AppKit,
  Foundation, Darwin, IOKit, UserNotifications). The app must keep building with a bare
  `swiftc` call.
- **Top-level code lives only in `main.swift`.** Other files contain declarations only.
- **Where code goes:** readings shown in the popover go in `Core.swift`; heavier,
  window-only readings go in `Advanced.swift` and must be sampled only while the window
  is visible (`windowVisible` in `AppDelegate.update()`). AppKit glue (status item,
  windows, timer) stays in `main.swift`.
- **Be cheap.** The app wakes every second and should idle around 1% CPU. Keep
  anything slower than ~1 ms off the main thread, gate work that only matters on screen
  behind `uiVisible` / `windowVisible`, and don't animate values that change every tick.
  Don't add `@Published` to `Stats`: the timer sends one `objectWillChange` per tick. See
  [Keeping the UI cheap](docs/ARCHITECTURE.md#keeping-the-ui-cheap). Check
  `ps -o %cpu= -p $(pgrep -x MacMonitor)` before and after your change.
- **Keep the popover content-sized.** Don't use `maxHeight: .infinity` in the dashboard
  root. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md#popover-sizing-rules).
- **No hard-coded UI text.** Every user-visible string goes through `loc.t("key")`
  (brand name, numbers and units excepted).
- **Colors come from `Pal`.** Don't add ad-hoc hex values in views.
- Formatting: 4-space indentation, short doc comments (`///`) on reading functions
  explaining *where the number comes from*, and `// MARK: -` sections in long files.
- Keep the design philosophy: never purge on a timer; memory pressure, not free %, is
  the signal.

## Adding a language

All strings live in one table in `Sources/Localization.swift`.

1. Add the language code (ISO 639-1) to `langs` and a short label to `langName`:

   ```swift
   static let langs = ["en", "ru", "uz", "de"]
   static let langName: [String: String] = ["en": "EN", "ru": "RU", "uz": "UZ", "de": "DE"]
   ```

2. Add a translation for that code to **every** entry in `table`:

   ```swift
   "memory": ["en": "Memory", "ru": "Память", "uz": "Xotira", "de": "Speicher"],
   ```

   A missing key falls back to English, so a partial translation won't crash, but please
   cover them all. Keep labels about as short as the English ones; the popover is narrow.

3. Build, pick the language in **Settings → Language**, and check every screen:
   popover, full window (Dashboard / Insights / Settings) and the welcome window (reset
   it with `defaults delete app.macmonitor.MacMonitor didOnboard`). The preview tool takes
   the language as its second argument.

To add a **new string**, add a key with all languages to `table` and use
`loc.t("your_key")` in a view that holds `@ObservedObject private var loc = Loc.shared`,
so it re-renders when the language changes.

## Pull requests

- One focused change per PR, with a short description of what and why. Add before/after
  screenshots for UI changes.
- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md).
- Commit messages: [Conventional Commits](https://www.conventionalcommits.org/) style
  (`feat: …`, `fix: …`, `docs: …`).
- By contributing you agree your work is released under the [MIT License](LICENSE).
