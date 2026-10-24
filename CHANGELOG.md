# Changelog

## 0.2.0 - 2026-10-24

- Cup off with the lid closed puts the Mac to sleep (`pmset sleepnow`), so the cup "until agents finish" lets a closed Mac sleep when the last agent finishes. Not with an external display attached.
- The check that the sudoers rule works now runs the rule (writing back the current `SleepDisabled`) instead of `sudo -l`. On an admin account `sudo -l` said yes without the rule, so `install-sudoers` could not tell that sudo ignores the file, and the watcher warned about a missing rule only at the first cup change instead of at start.
- Under `sudo herdr-lid-awake install-sudoers` that check runs as your user, not as root, who passes any sudo.

## 0.1.0 - 2026-10-24

First release.

- Follows the Herdr UI cup: cup on sets `pmset disablesleep 1`, cup off, Herdr quit or crash sets it back to `0`, within a second.
- Leaves a `SleepDisabled 1` set by something else alone.
- Restores sleep when the watcher is stopped, and after `kill -9` or a power loss on the next start.
- Says `sudoers rule missing: run herdr-lid-awake install-sudoers` once if the sudoers rule is not installed.
- `herdr-lid-awake sudoers` prints the rule, `install-sudoers` checks it with `visudo` before installing, `--version` prints the version.
- One sudoers file per account (`/etc/sudoers.d/herdr-lid-awake-<uid>`), checked to be effective after install; under `sudo` the rule names `SUDO_USER`.
- A second watcher refuses to start. `--help` prints usage.
