# Homebrew Cask for Mac Monitor.
# Bump version + sha256 each release.
# Recompute sha256 with:  shasum -a 256 dist/MacMonitor.dmg
#
# This repo doubles as a Homebrew tap:
#   brew tap ahmadjondev/macmonitor https://github.com/Ahmadjondev/MacMonitor
#   brew install --cask mac-monitor
# The build is ad-hoc signed (not notarized), so the first launch needs
# right-click → Open (see README).
cask "mac-monitor" do
  version "1.0.0"
  sha256 "9632824fd078d43ff15665e227c1bf2e53ebe04f70b585552fccfdb7a375c989"

  url "https://github.com/Ahmadjondev/MacMonitor/releases/download/v#{version}/MacMonitor.dmg"
  name "Mac Monitor"
  desc "Lightweight macOS menu-bar system monitor (RAM, CPU, network, disk)"
  homepage "https://github.com/Ahmadjondev/MacMonitor"

  depends_on macos: ">= :ventura"

  app "Mac Monitor.app"

  zap trash: [
    "~/Library/LaunchAgents/app.macmonitor.MacMonitor.plist",
    "~/Library/Application Support/MacMonitor",
    "~/Library/Preferences/app.macmonitor.MacMonitor.plist",
  ]
end
