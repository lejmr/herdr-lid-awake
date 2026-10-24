# Changelog

## 0.1.0 - 2026-10-24

First release.

- Follows the Herdr UI cup: cup on sets `pmset disablesleep 1`, cup off, Herdr quit or crash sets it back to `0`, within a second.
- Leaves a `SleepDisabled 1` set by something else alone.
- Restores sleep when the watcher is stopped, and after `kill -9` or a power loss on the next start.
- Says `sudoers rule missing: run herdr-lid-awake install-sudoers` once if the sudoers rule is not installed.
- `herdr-lid-awake sudoers` prints the rule, `install-sudoers` checks it with `visudo` before installing, `--version` prints the version.
