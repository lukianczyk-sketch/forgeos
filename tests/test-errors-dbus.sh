#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case F: the real watcher on a real private session bus on this
# runner. Pop-up messages are sent the way programs send them (a Notify call); the real busctl monitor hears
# them, the watcher explains the errors and leaves everything else alone. Needs dbus-run-session, dbus-send
# and busctl (no notification server is needed: the monitor hears the call either way).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors-dbus.sh <repo-root>
set -u
if [ -z "${ERRORS_ON_BUS:-}" ]; then
  command -v dbus-run-session >/dev/null 2>&1 || { echo "FAIL F0 dbus-run-session is needed"; exit 1; }
  ERRORS_ON_BUS=1 exec dbus-run-session -- bash "$0" "$@"
fi
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/errors-fakes.sh
. "$ROOT/tests/errors-fakes.sh"
for p in dbus-send busctl; do command -v "$p" >/dev/null 2>&1 || { echo "FAIL F0 $p is needed"; exit 1; }; done
unset FORGEOS_ERRORS_NOW
items() { python3 -c "import json,sys; print(' '.join('%s:%d' % (e['key'], e['count']) for e in json.load(open(sys.argv[1]))))" "$HIST" 2>/dev/null; }
wait_for() { for _ in $(seq 75); do eval "$1" && return 0; sleep 0.2; done; return 1; }
# notify APP TITLE TEXT: a pop-up, sent the way every program sends one
notify() {
  dbus-send --session --type=method_call --dest=org.freedesktop.Notifications /org/freedesktop/Notifications \
    org.freedesktop.Notifications.Notify string:"$1" uint32:0 string:"" string:"$2" string:"$3" array:string: dict:string:string: int32:-1 2>/dev/null
}

ER watch > "$WORK/watch.log" 2>&1 &
WPID=$!
# F1: the watcher is running and listening (its first look at crashes and the system log happens at once)
check F1 'wait_for "grep -qs \"^journalctl\" \"$WORK/calls.log\"" && kill -0 "$WPID" && wait_for "pgrep -f \"busctl --user monitor\" >/dev/null"'
sleep 1
# F2: an error pop-up -> explained and written down, and our pop-up offers "What does this mean?"
notify "Printer Manager" "Printer HP stopped" "Filter failed"
check F2 'wait_for "[ \"\$(items)\" = print-filter-failed:1 ]" && wait_for "grep -qs \"^notify-send -a ForgeOS Errors .*The printer could not understand the print job\" \"$WORK/calls.log\""'
# F3: a song, a chat message and our own pop-up are left alone; a text over two lines still works
notify "Elisa" "Now playing" "Pearl Jam - Alive"; notify "Signal" "Mom" "Dinner at 6?"
notify "ForgeOS Errors" "The printer could not understand the print job" "Filter failed"
notify "Disks & Devices" "Problem" "Could not copy.
cp: error writing x: No space left on device"
check F3 'wait_for "[ \"\$(items)\" = \"print-filter-failed:1 disk-full:1\" ]" && sleep 1 && [ "$(items)" = "print-filter-failed:1 disk-full:1" ]'
# F4: a fake "virus" pop-up from a website is called a scam at once (serious: shown even right after another)
notify "Brave" "Microsoft Security Alert" "Your PC is infected! Call 1-888-555-0199 immediately"
check F4 'wait_for "grep -qE \"scam-fake-error/[0-9a-f]{10}:1\" <<< \"\$(items)\"" && wait_for "grep -qs \"This is a scam, not a real error\" \"$WORK/calls.log\""'
# F5: the watcher is still running after all of it, and wrote nothing to its log
check F5 'kill -0 "$WPID" && [ ! -s "$WORK/watch.log" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests F passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"
