# herdr-lid-awake

herdr-lid-awake keeps a Mac running with its lid closed while the cup in the [Herdr UI](https://github.com/penso/herdr-gpui) status bar is on. Turn the cup on, close the lid, and the agents keep working. Turn it off, and the Mac sleeps as usual.

```sh
$ pmset -g | grep SleepDisabled
 SleepDisabled		0
# click the cup
$ pmset -g | grep SleepDisabled
 SleepDisabled		1
# click it again
$ pmset -g | grep SleepDisabled
 SleepDisabled		0
```

```
$ tail -2 $(brew --prefix)/var/log/herdr-lid-awake.log
2026-10-24 10:03:50 lid: awake
2026-10-24 10:03:52 lid: sleeps
```

## Why herdr-lid-awake

The cup holds a power assertion, the same one `caffeinate` holds. macOS ignores power assertions when the lid closes, so the Mac sleeps anyway. Only `pmset disablesleep` stops that, and it needs root. Building it into Herdr UI [was proposed and declined](https://github.com/penso/herdr-gpui/pull/337), fairly: the app would have to install a sudoers rule and run scripts as root. So it lives here, outside the app.

- **One switch.** The cup you already use. No second app to keep in sync.
- **Within a second.** It follows the assertion log, nothing is polled.
- **Leaves others alone.** It only clears a `SleepDisabled 1` it set itself. If Amphetamine or you disabled sleep first, it does not touch it.
- **Gives sleep back.** Cup off, Herdr quit or crashed, watcher stopped or killed: sleep is restored.
- **One bash script.** About 90 lines, nothing but what ships with macOS.

## Install

```sh
brew install lejmr/tap/herdr-lid-awake
herdr-lid-awake install-sudoers     # asks for your password, once
brew services start herdr-lid-awake
```

`install-sudoers` writes `/etc/sudoers.d/herdr-lid-awake`, which lets your user run exactly two commands without a password: `pmset disablesleep 0` and `pmset disablesleep 1`. It checks the rule with `visudo -c` before installing it, because a broken file in `sudoers.d` disables `sudo` altogether. To see the rule first:

```sh
$ herdr-lid-awake sudoers
milos ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1
```

## Use

There is nothing to use. Click the cup.

To check that it works: turn the cup on and run `pmset -g | grep SleepDisabled`, it says `1`. Every change is logged to `$(brew --prefix)/var/log/herdr-lid-awake.log`. `herdr-lid-awake --version` prints the version.

If the sudoers rule is missing, the log says `sudoers rule missing: run herdr-lid-awake install-sudoers`, once, and the watcher keeps running.

## How it works

`pmset -g assertionslog` prints every power assertion as it is created and released. The watcher reads it, and on any line from Herdr it asks `pmset -g assertions` whether Herdr still holds `PreventUserIdleSystemSleep`. If it does, `sudo -n pmset disablesleep 1`. If it stopped, `sudo -n pmset disablesleep 0`. A quit or a crash releases the assertion too, so it takes the same path.

`pmset` buffers its output when it is not writing to a terminal, and the lines would arrive late. The watcher runs it under `script`, which gives it one.

While it holds `disablesleep 1`, the watcher keeps a marker file in `~/.local/state/herdr-lid-awake/`. If it is killed with `kill -9`, or the Mac loses power, no one can clear `SleepDisabled`. The next start finds the marker: if the cup is off it sets `disablesleep 0` and removes the marker, if the cup is still on it takes over and releases later as usual. Without a marker, a `SleepDisabled 1` is not ours and stays.

## What is in, what is out

- macOS only. Herdr UI runs on Windows and Linux too, but lid sleep works differently there (on Linux a logind inhibitor needs no root), and I do not use either for this.
- `kill -9` of the watcher leaves `SleepDisabled 1` until the watcher starts again, which `brew services` does by itself. By hand: `sudo pmset disablesleep 0`.
- No cutoff on low battery. Mind the charge.
- Any Herdr UI process holding the assertion counts: with two instances, sleep comes back when the last cup goes off.
- A Mac with its lid closed in a bag does not cool well. Turn the cup off before you pack it.

## Uninstall

```sh
brew services stop herdr-lid-awake
brew uninstall herdr-lid-awake
sudo rm /etc/sudoers.d/herdr-lid-awake
```

## AI disclosure

I wanted my agents to keep running while the laptop is closed, and the cup in Herdr UI looked like the switch for it. It is not, macOS has the last word on a closed lid. Before writing anything I had Claude Code go through the Herdr UI issues and PRs. Someone had already built this into the app, and the maintainer closed it for reasons I agree with. So I asked for the smallest thing that does it from the outside.

Claude Code wrote the script and the formula in one session; I tested it on my MacBook. It is small enough to read in two minutes, and you should, since it runs `sudo`.

## Contributing

Something broken, or a better way than `pmset disablesleep`? Open an issue or a pull request, I am happy to be told there is a simpler way. `bash tests/run.sh` runs the tests, see [DEVELOPMENT.md](DEVELOPMENT.md).

## License

BSD 3-Clause, see [LICENSE](LICENSE).
