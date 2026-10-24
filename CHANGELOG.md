# Changelog

All notable changes to this project are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/) and the project uses
[Semantic Versioning](https://semver.org/).

## [Unreleased]

## [1.0.0] - 2026-10-24

First public release.

### Added
- Menu-bar item showing live network speed (↓/↑), RAM % or CPU %, in a fixed-width
  Retina-crisp template image.
- Dashboard popover with Memory (composition bar, swap, pressure graph), Processor
  (per-core bars), Network (speed, totals, local IP), Storage (capacity, disk I/O) and
  Top apps cards.
- Full window mode with sidebar (Dashboard / Insights / Settings) and extra detail:
  CPU split, load average, processes/threads, packets, per-interface totals, IOPS,
  Battery and GPU cards.
- Insights: RAM and CPU history charts with now / average / peak, and critical-pressure
  minutes over 24 h, persisted across restarts.
- Memory cleaning with `purge`: on demand, or automatically only at critical memory
  pressure (opt-in). Optional single-command sudoers rule for silent cleaning.
- Critical-pressure notifications (opt-in).
- English, Russian and Uzbek UI, switchable live.
- Settings for menu-bar metric, update rate, network unit, card visibility and launch
  at login (LaunchAgent), grouped into sections. Warns when auto-clean is on but the
  sudoers rule is missing.
- First-launch welcome window and a styled drag-to-install DMG.
- Universal binary (Apple Silicon + Intel) for macOS 13 Ventura and later.
- Lightweight sampling: about 1% CPU in normal use. Hidden views don't re-render, and
  `ps` and disk-capacity queries run off the main thread.

### Known issues
- The release is not notarized; the first launch has to be approved in System Settings
  (see README).
- Network "Total" values come from 32-bit kernel interface counters and wrap after
  4 GiB per interface.

[Unreleased]: https://github.com/Ahmadjondev/MacMonitor/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/Ahmadjondev/MacMonitor/releases/tag/v1.0.0
