#!/bin/bash
# Acceptance tests, one per CI row of DEVELOPMENT.md. Plain bash, no framework.
# pmset, sudo and visudo are fakes; `script -q /dev/null` is the real one.
# Usage: bash tests/run.sh
# shellcheck disable=SC2329  # test_N are called by name from the loop below

ROOT=$(cd "$(dirname "$0")/.." && pwd)
FIX=$ROOT/tests/fixtures
BIN=$ROOT/herdr-lid-awake
RAW=$FIX/assertionslog-raw.txt

# Log lines from the real capture. There is no Herdr ClientDied line in it, so
# it is derived from the caffeinate ClientDied line: pid, id and name replaced
# with the Herdr values of the Created line.
CREATED=$(grep -m1 'Created.*PreventUserIdleSystemSleep.*Herdr' "$RAW")
RELEASED=$(grep -m1 'Released.*PreventUserIdleSystemSleep.*Herdr' "$RAW")
DIED=$(grep -m1 'ClientDied.*caffeinate' "$RAW" |
  sed -e 's/ 88572 / 10444 /' -e 's/0xe3c3300019b66/0xe3c3000019b64/' \
      -e 's/caffeinate command-line tool/Herdr keeps the display awake/')

# Fresh fake world in $T: fake pmset, sudo, visudo, and a FIFO standing in for the log.
setup() {
  T=$(mktemp -d)
  export FAKE_DIR=$T FAKE_FIX=$FIX
  echo 0 > "$T/sleepdisabled"; echo off > "$T/cup"
  cat > "$T/pmset" <<'FAKE'
#!/bin/bash
case "$*" in
  "-g") cat "$FAKE_FIX/pmset-g-sleep-$([ "$(cat "$FAKE_DIR/sleepdisabled")" = 1 ] && echo disabled || echo enabled).txt" ;;
  "-g assertions") cat "$FAKE_FIX/assertions-cup-$(cat "$FAKE_DIR/cup").txt" ;;
  "-g assertionslog") echo $$ > "$FAKE_DIR/logpid"
    echo "Showing all currently held IOKit power assertions"
    exec cat "$FAKE_DIR/log" ;;
  "disablesleep "*) echo "$2" > "$FAKE_DIR/sleepdisabled"; echo "disablesleep $2" >> "$FAKE_DIR/calls" ;;
esac
FAKE
  cat > "$T/sudo" <<'FAKE'
#!/bin/bash
if [ "$1" = -n ]; then
  shift
  [ -e "$FAKE_DIR/sudo_fail" ] && exit 1
  [ "$1" = -l ] && exit 0
  exec "$@"
fi
# Never really install anything.
[ "$1" = install ] && { echo "sudo install" >> "$FAKE_DIR/calls"; echo "$*" > "$FAKE_DIR/install_args"; exit 0; }
exec "$@"
FAKE
  printf '#!/bin/bash\nexit 0\n' > "$T/visudo"
  chmod +x "$T/pmset" "$T/sudo" "$T/visudo"
  mkfifo "$T/log"
  exec 9<> "$T/log"   # hold the FIFO open so the fake log never sees EOF
  export HERDR_LID_AWAKE_PMSET=$T/pmset HERDR_LID_AWAKE_SUDO=$T/sudo
  export HERDR_LID_AWAKE_VISUDO=$T/visudo HERDR_LID_AWAKE_STATE_DIR=$T/state
}

teardown() {
  [ -n "$W" ] && { kill -9 "$W"; wait "$W"; } 2>/dev/null
  pkill -f "$T/pmset" 2>/dev/null
  exec 9>&-
  rm -rf "$T"
}

# Start the watcher, wait until its log stream is live.
start() {
  rm -f "$T/logpid"
  "$BIN" >> "$T/out" 2>&1 9>&- &
  W=$!
  for _ in $(seq 100); do [ -e "$T/logpid" ] && return; sleep 0.05; done
  echo "watcher did not start" >&2; return 1
}

emit() { echo "$1" > "$T/cup"; shift; printf '%s\n' "$@" >&9; }   # emit on|off LINE...
sd() { "$T/pmset" -g | awk '/SleepDisabled/{print $2}'; }
# Within 1 s, SleepDisabled must read $1.
within_1s() { for _ in $(seq 20); do [ "$(sd)" = "$1" ] && return; sleep 0.05; done
  echo "SleepDisabled is $(sd), wanted $1 within 1 s" >&2; return 1; }
calls() { cat "$T/calls" 2>/dev/null; }

test_1() { start && emit on "$CREATED" && within_1s 1; }
test_2() { start && emit on "$CREATED" && within_1s 1 && emit off "$RELEASED" && within_1s 0; }
test_3() { start && emit on "$CREATED" && within_1s 1 && emit off "$DIED" && within_1s 0; }

test_4() {
  echo 1 > "$T/sleepdisabled"
  start && emit on "$CREATED" && sleep 0.5 && emit off "$RELEASED" && sleep 0.5 || return 1
  [ "$(sd)" = 1 ] && [ -z "$(calls)" ] || { echo "sd=$(sd) calls: $(calls)" >&2; return 1; }
}

test_5() {
  start && emit on "$CREATED" && within_1s 1 || return 1
  emit on "$RELEASED"; sleep 0.5          # one instance let go, the other still holds
  [ "$(sd)" = 1 ] || { echo "released early" >&2; return 1; }
  emit off "$RELEASED"; within_1s 0
}

test_6() {
  start && emit on "$CREATED" && within_1s 1 || return 1
  kill -TERM "$W"; wait "$W" 2>/dev/null; W=
  within_1s 0 || return 1
  sleep 0.2
  pgrep -f "$T/pmset" >&2 && { echo "leftover pmset/script" >&2; return 1; }
  return 0
}

test_7() {
  # Crash while holding, restart with the cup off.
  start && emit on "$CREATED" && within_1s 1 || return 1
  [ -e "$T/state/holding" ] || { echo "no marker while holding" >&2; return 1; }
  kill -9 "$W"; wait "$W" 2>/dev/null; pkill -f "$T/pmset"
  echo off > "$T/cup"
  start && within_1s 0 || return 1
  sleep 0.2; [ ! -e "$T/state/holding" ] || { echo "marker not removed" >&2; return 1; }
  kill -TERM "$W"; wait "$W" 2>/dev/null; W=; pkill -f "$T/pmset"
  # Crash while holding, restart with the cup still on: adopt, release later.
  start && emit on "$CREATED" && within_1s 1 || return 1
  kill -9 "$W"; wait "$W" 2>/dev/null; pkill -f "$T/pmset"
  start; sleep 0.5
  [ "$(sd)" = 1 ] || { echo "adoption let go while cup on" >&2; return 1; }
  emit off "$RELEASED"; within_1s 0
}

test_8() {
  touch "$T/sudo_fail"
  start && emit on "$CREATED" && emit off "$RELEASED" && emit on "$CREATED" && sleep 0.5 || return 1
  kill -0 "$W" 2>/dev/null || { echo "watcher died" >&2; return 1; }
  [ "$(cat "$T/out")" = "sudoers rule missing: run herdr-lid-awake install-sudoers" ] ||
    { echo "output was: $(cat "$T/out")" >&2; return 1; }
}

test_9() {
  "$BIN" sudoers > "$T/rule" || return 1
  [ "$(cat "$T/rule")" = "$(id -un) ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1" ] ||
    { echo "rule: $(cat "$T/rule")" >&2; return 1; }
  out=$(/usr/sbin/visudo -cf "$T/rule" 2>&1); echo "$out"
  case $out in *"parsed OK"*) ;; *) return 1 ;; esac
}

test_10() {
  # Control: a valid rule does reach `sudo install`.
  "$BIN" install-sudoers >/dev/null || return 1
  [ "$(calls)" = "sudo install" ] || { echo "control: install not called" >&2; return 1; }
  rm -f "$T/calls"
  printf '#!/bin/bash\nexit 1\n' > "$T/visudo"
  "$BIN" install-sudoers >/dev/null 2>&1 && { echo "exit 0 on invalid rule" >&2; return 1; }
  [ -z "$(calls)" ] || { echo "install called: $(calls)" >&2; return 1; }
}

test_x1() {
  # Run as `bash herdr-lid-awake`, $0 has no slash; a same-named decoy earlier on PATH must not run.
  mkdir "$T/decoy"
  cat > "$T/decoy/herdr-lid-awake" <<'DECOY'
#!/bin/bash
echo decoy >> "$FAKE_DIR/calls"
DECOY
  chmod +x "$T/decoy/herdr-lid-awake"
  (cd "$ROOT" && PATH=$T/decoy:$PATH bash herdr-lid-awake install-sudoers) >/dev/null 2>&1
  [ "$(calls)" = "sudo install" ] || { echo "calls: $(calls)" >&2; return 1; }
}

test_x2() {
  # Marker left over, but sleep is enabled (reboot, someone cleared it): the marker is stale,
  # cup on must disable sleep again.
  mkdir -p "$T/state"; : > "$T/state/holding"; echo on > "$T/cup"
  start; within_1s 1 || return 1
  emit off "$RELEASED"; within_1s 0
}

test_x3() {
  # State dir not writable: without a marker a kill -9 could never be healed, so do not disable sleep.
  mkdir "$T/ro"; chmod 555 "$T/ro"; export HERDR_LID_AWAKE_STATE_DIR=$T/ro/state
  start && emit on "$CREATED" && sleep 0.5 || return 1
  [ "$(sd)" = 0 ] && [ -z "$(calls)" ] || { echo "sd=$(sd) calls: $(calls)" >&2; return 1; }
  [ -s "$T/out" ] || { echo "no message" >&2; return 1; }
}

test_x4() {
  # Under `sudo`, id -un says root; the rule must name SUDO_USER, and refuse without one.
  mkdir "$T/fakeid"
  cat > "$T/fakeid/id" <<'ID'
#!/bin/bash
[ "$1" = -u ] && echo 0 || echo root
ID
  chmod +x "$T/fakeid/id"
  out=$(PATH=$T/fakeid:$PATH SUDO_USER=jana SUDO_UID=501 "$BIN" sudoers)
  [ "$out" = "jana ALL=(root) NOPASSWD: /usr/bin/pmset disablesleep 0, /usr/bin/pmset disablesleep 1" ] ||
    { echo "rule: $out" >&2; return 1; }
  for u in "" root; do
    PATH=$T/fakeid:$PATH SUDO_USER=$u "$BIN" install-sudoers >/dev/null 2>&1 && { echo "exit 0 as root, SUDO_USER='$u'" >&2; return 1; }
  done
  [ -z "$(calls)" ] || { echo "install called: $(calls)" >&2; return 1; }
}

test_x5() {
  # One file per user, named by uid (no '.' in it, one account must not overwrite another's rule).
  "$BIN" install-sudoers >/dev/null || return 1
  case $(cat "$T/install_args") in
    *" /etc/sudoers.d/herdr-lid-awake-$(id -u)") ;;
    *) echo "args: $(cat "$T/install_args")" >&2; return 1 ;;
  esac
}

test_x6() {
  # sudo does not honour the installed file (no #includedir): say so, exit non-zero.
  touch "$T/sudo_fail"
  "$BIN" install-sudoers >/dev/null 2>"$T/err" && { echo "exit 0 although sudo -l fails" >&2; return 1; }
  grep -q includedir "$T/err" || { echo "no hint: $(cat "$T/err")" >&2; return 1; }
}

test_12() { (cd "$ROOT" && shellcheck herdr-lid-awake tests/*.sh); }

fail=0
for n in 1 2 3 4 5 6 7 8 9 10 12 x1 x2 x3 x4 x5 x6; do
  desc=$(sed -n "s/^# row $n: //p" "$ROOT/tests/run.sh" | head -1)
  if (setup; W=; trap teardown EXIT; "test_$n") >&2; then echo "ok $n - $desc"; else echo "not ok $n - $desc"; fail=1; fi
done
exit $fail

# row 1: cup on, lid does not sleep
# row 2: cup off, sleeps normally
# row 3: Herdr crashes or quits, sleeps
# row 4: foreign SleepDisabled 1 is left untouched
# row 5: two instances, one off does not release
# row 6: stopping the watcher restores sleep
# row 7: after kill -9, next start restores or adopts
# row 8: missing sudoers gives one clear message
# row 9: sudoers prints a valid rule
# row 10: install-sudoers never installs an invalid rule
# row 12: script is lint-clean
# row x1: install-sudoers does not re-run itself through PATH
# row x2: stale marker with sleep enabled is dropped, cup on disables sleep
# row x3: unwritable state dir means no disablesleep, with a message
# row x4: under sudo the rule names SUDO_USER, never root
# row x5: sudoers file is per uid
# row x6: install-sudoers fails when sudo does not use the file
