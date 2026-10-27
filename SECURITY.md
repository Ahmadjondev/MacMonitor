# Security Policy

## Supported versions

Only the latest release gets security fixes.

| Version | Supported |
| ------- | --------- |
| 1.0.x   | ✅        |
| < 1.0   | ❌        |

## Reporting a vulnerability

Please **do not open a public issue** for security problems.

Report them privately through GitHub instead: open the repository's
[**Security** tab](https://github.com/Ahmadjondev/MacMonitor/security) and click
**Report a vulnerability**. Only the maintainer can see the report.

Include what you can:

- the Mac Monitor version and macOS version,
- what an attacker could do, and what they need first (local access, another user
  account, a modified file, …),
- steps to reproduce, or a proof of concept.

You can expect a first reply within 7 days. If the issue is confirmed, a fix is released
as soon as possible and you are credited in the release notes, unless you prefer not to be.

## Scope

Mac Monitor runs as your user, makes no network connections and collects no data. The
parts most relevant to security are:

- **The optional sudoers rule** (`/etc/sudoers.d/macmonitor`), which lets your user run
  exactly `/usr/sbin/purge` as root without a password. The app never installs it; the
  README shows how to install it by hand.
- **The LaunchAgent** (`~/Library/LaunchAgents/app.macmonitor.MacMonitor.plist`), written
  only when you turn on *Launch at login*.
- **Local files**: settings in `UserDefaults` and history in
  `~/Library/Application Support/MacMonitor/history.json`.
- **The release build**, which is ad-hoc signed and not notarized. Download it only from
  this repository's [Releases](https://github.com/Ahmadjondev/MacMonitor/releases) page.

Problems in macOS itself, or in `purge` and `sudo`, should go to Apple.
