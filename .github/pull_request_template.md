## What and why

<!-- What does this change, and what problem does it solve? Link the issue if there is one (Fixes #123). -->

## How I tested it

<!-- macOS version, Mac (Apple silicon / Intel), and what you checked in the running app. -->

## Checklist

- [ ] `./build.sh` succeeds without new warnings
- [ ] New user-visible text goes through `loc.t("key")`, with `en`, `ru` and `uz` strings
- [ ] CPU use stays around 1% (`ps -o %cpu= -p $(pgrep -x MacMonitor)` before and after)
- [ ] Screenshots attached for UI changes
- [ ] `CHANGELOG.md` updated under *Unreleased*, if users will notice the change
