# Development

## Tests

```sh
bash tests/run.sh          # prints ok N / not ok N, exits non-zero on any failure
shellcheck herdr-lid-awake tests/*.sh
```

Needs macOS (the real `script`, `visudo`, `pgrep`) and `shellcheck`. `pmset`, `sudo` and `visudo` are fakes written by the test into a temp dir, wired in with the env overrides below. Nothing touches the real power settings or sudoers.

| Variable | Default |
| --- | --- |
| `HERDR_LID_AWAKE_PMSET` | `/usr/bin/pmset` |
| `HERDR_LID_AWAKE_SUDO` | `sudo` |
| `HERDR_LID_AWAKE_VISUDO` | `/usr/sbin/visudo` |
| `HERDR_LID_AWAKE_STATE_DIR` | `${XDG_STATE_HOME:-$HOME/.local/state}/herdr-lid-awake` |

`tests/fixtures/` holds output captured on a real Mac (macOS 27.0.1, Herdr UI 20261020.1). The capture has no Herdr `ClientDied` line, so `tests/run.sh` derives one from the caffeinate `ClientDied` line by substituting the Herdr pid, assertion id and name.

## Acceptance table

The permanent requirement set. A change is done when every row holds.

| # | Behaviour | Observed | Expected | Checked by |
|---|---|---|---|---|
| 1 | Cup on, lid does not sleep | fake log emits Herdr `Created` line, cup state on; then fake `pmset -g` | `SleepDisabled 1` within 1 s | `tests/run.sh` |
| 2 | Cup off, sleeps normally | `Released` line, cup off | `0` within 1 s | `tests/run.sh` |
| 3 | Herdr crashes or quits, sleeps | Herdr `ClientDied` line, cup off | `0` | `tests/run.sh` |
| 4 | NEG: foreign `SleepDisabled 1` untouched | start with 1 and no marker; cup on then off | still `1`, zero `disablesleep` calls | `tests/run.sh` |
| 5 | Two Herdr instances: one off does not release | cup state stays on while one `Released` line arrives, then off | `1`, then `0` after the last | `tests/run.sh` |
| 6 | Stopping the watcher restores sleep | `kill -TERM` while holding | `0`, no leftover child processes | `tests/run.sh` |
| 7 | After kill -9 or power loss, next start restores | `kill -9` while holding (marker remains), restart with cup off | `0`, marker removed; restart with cup on adopts (stays `1`, later off gives `0`) | `tests/run.sh` |
| 8 | Missing sudoers gives a clear message | `sudo -n -l` fails at start | exactly one line `sudoers rule missing: run herdr-lid-awake install-sudoers`, watcher keeps running, no spam per event | `tests/run.sh` |
| 9 | `sudoers` prints a valid rule | `herdr-lid-awake sudoers > f && /usr/sbin/visudo -cf f` | `parsed OK`; rule is `<user> ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1` | `tests/run.sh` |
| 10 | NEG: `install-sudoers` never installs an invalid rule | fake visudo fails | `sudo install` never called, exit not 0 | `tests/run.sh` |
| 11 | Tap install on a fresh macOS | `brew install`, `brew test`, `brew audit --strict --online` | all pass | tap CI (`homebrew-tap/.github/workflows/ci.yml`) |
| 12 | Script is lint-clean | `shellcheck herdr-lid-awake tests/*.sh` | no output | `tests/run.sh`, CI |
| 13 | Real cup toggles real sleep | real Herdr UI, watcher started by `brew services`; click the cup, `pmset -g \| grep SleepDisabled`, click again | `1`, then `0`; log has `lid: awake`, `lid: sleeps` | maintainer |
| 14 | Lid closed with cup on, Mac stays reachable | cup on, close the lid on battery, `ping` the Mac from another device for a minute | replies keep coming | maintainer |
| 15 | Lid closed with cup off, Mac sleeps; `kill -9` heals | cup off, close the lid; then cup on, `kill -9` the watcher, wait for `brew services` to restart it, cup off | pings stop; after the restart `SleepDisabled 0` | maintainer |

## Release

1. Bump `VERSION=` in `herdr-lid-awake`, add a `## X.Y.Z - YYYY-MM-DD` section to `CHANGELOG.md`.
2. `bash tests/run.sh`, commit, push, wait for CI.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. `release.yml` fails unless the tag is `v$VERSION` and the changelog has the section. Then it creates the GitHub release with that section as notes, computes the sha256 of the tag tarball and commits the new `url` and `sha256` to `lejmr/homebrew-tap`. It needs the repository secret `TAP_TOKEN`, a token with write access to the tap.
5. Wait for the tap CI (row 11), then run the manual batch below.

## Manual batch (rows 13 to 15)

Run on a MacBook with Herdr UI, after `brew upgrade herdr-lid-awake` and `brew services restart herdr-lid-awake`.

| Row | Do | Good = |
| --- | --- | --- |
| 13 | Cup on, `pmset -g \| grep SleepDisabled`. Cup off, again. `tail -2 $(brew --prefix)/var/log/herdr-lid-awake.log`. | `1`, then `0`; the two log lines `lid: awake` and `lid: sleeps` |
| 14 | Cup on, close the lid on battery, `ping <mac>.local` from a phone or another computer for a minute. Open the lid, cup off. | Replies the whole time; afterwards `SleepDisabled 0` |
| 15 | Cup off, close the lid, ping. Open it. Cup on, `kill -9 $(pgrep -f herdr-lid-awake)`, wait a few seconds, cup off. | Pings stop within a minute or so; after the restart and cup off, `SleepDisabled 0` |
