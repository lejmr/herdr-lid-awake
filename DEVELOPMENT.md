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

Rows `x1` to `x10` in `tests/run.sh` are regression tests for defects found after the table was written (PATH lookup of `$0`, stale marker, unwritable state dir, rule for root, per-uid sudoers file, ineffective sudoers file, second watcher, `--help`, the startup race, `PreventSystemSleep`).

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
| 13 | Cup toggles real sleep | Real Mac: `brew install lejmr/tap/herdr-lid-awake`, `herdr-lid-awake install-sudoers`, `brew services start herdr-lid-awake`; cup on/off, `pmset -g \| grep SleepDisabled` | `1`, then `0` | maintainer |
| 14 | Lid closed on battery, cup on, loop keeps running | Real Mac on battery: cup on, lid closed 5 min, a `while :; do date >> ~/lid.log; sleep 5; done` loop running | no gap > 10 s in `~/lid.log` | maintainer |
| 15 | System scope also disables sleep | `keep_awake_scope = "system"` (Settings or `Herdr config set status_bar.keep_awake_scope system`), cup off then on | `SleepDisabled 1` | maintainer |

## Release

1. Bump `VERSION=` in `herdr-lid-awake`, add a `## X.Y.Z - YYYY-MM-DD` section to `CHANGELOG.md`.
2. `bash tests/run.sh`, commit, push, wait for CI.
3. `git tag vX.Y.Z && git push origin vX.Y.Z`.
4. `release.yml` fails unless the tag is `v$VERSION` and the changelog has the section. Then it creates the GitHub release with that section as notes, computes the sha256 of the tag tarball and commits the new `url` and `sha256` to `lejmr/homebrew-tap`. It needs the repository secret `TAP_TOKEN`, a token with write access to the tap.
5. Wait for the tap CI (row 11), then run the manual batch below.

## Manual batch (rows 13 to 15)

Run on a MacBook with Herdr UI.

| Row | Do | Good = |
| --- | --- | --- |
| 13 | `brew install lejmr/tap/herdr-lid-awake`, `herdr-lid-awake install-sudoers`, `brew services start herdr-lid-awake`. Cup on, `pmset -g \| grep SleepDisabled`. Cup off, again. | `1`, then `0` |
| 14 | On battery: cup on, close the lid for 5 minutes with `while :; do date >> ~/lid.log; sleep 5; done` running. Open the lid, check `~/lid.log`. | No gap longer than 10 s in `~/lid.log` |
| 15 | Set `keep_awake_scope = "system"` (Settings, or `Herdr config set status_bar.keep_awake_scope system`). Cup off, then on. `pmset -g \| grep SleepDisabled`. | `SleepDisabled 1` |
