#!/usr/bin/env bash
# Tests for Find My PC (Job 19), case G: your session's side - Ring (sound unmuted and all the way up, a loud
# sound again and again), the "please return" message, the password safe locked when lost, each shown once.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-locate-alert.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/locate-fakes.sh
. "$ROOT/tests/locate-fakes.sh"
fresh
# say KIND [TEXT] [AGE]: the root watcher's alert (as root), AGE seconds ago
say() { FORGEOS_LOC_NOW=$((FORGEOS_LOC_NOW - ${3:-0})) FORGEOS_LOC_ROOT=1 python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from locatelib import commands; commands.alert(sys.argv[2], sys.argv[3])" "$FORGEOS_LOC_LIB" "$1" "${2:-}"; }
A() { LOC alert-watch --once; }

check G1 '[ -z "$(A)" ] && [ -z "$(calls)" ]'
say lost; OUT="$(A)"
check G2 '[ "$OUT" = "SHOWN${T}lost" ] && grep -qx "flatpak run --command=keepassxc org.keepassxc.KeePassXC --lock" <<< "$(calls)" && grep -qx "keepassxc --lock" <<< "$(calls)" && ! grep -q "^notify-send\|^kdialog" <<< "$(calls)"'
check G3 '[ -z "$(A)" ] && [ "$(stat -c %a "$WORK/state/forgeos/locate.json")" = 600 ]'
: > "$WORK/calls.log"; say message "Reward! Call 555-0101"; OUT="$(A)"; sleep 0.3
check G4 '[ "$OUT" = "SHOWN${T}message" ] && grep -q "^notify-send --app-name=Find My PC --icon=find-location --urgency=critical -- This PC is lost Reward! Call 555-0101$" <<< "$(calls)" && grep -q "<h1>This PC is lost</h1><h2>Reward! Call 555-0101</h2>" "$WORK/shown"'
# Ring 115 seconds ago: only the 5 seconds left are rung
: > "$WORK/calls.log"; say ring "" 115; SECONDS=0; OUT="$(A)"; TOOK=$SECONDS
check G5 '[ "$OUT" = "SHOWN${T}ring" ] && grep -qx "pactl set-sink-mute @DEFAULT_SINK@ 0" <<< "$(calls)" && grep -qx "pactl set-sink-volume @DEFAULT_SINK@ 100%" <<< "$(calls)" && [ "$(grep -c "^paplay $WORK/ring.oga$" <<< "$(calls)")" -ge 3 ] && [ "$TOOK" -ge 4 ] && [ "$TOOK" -le 9 ]'
# a ring from 3 minutes ago is over; a message from yesterday is not shown; found says welcome back
: > "$WORK/calls.log"; say ring "" 180; say message "old" 50000; say found
OUT="$(A)"; sleep 0.3
check G6 '[ "$OUT" = "SHOWN${T}found" ] && ! grep -q "^paplay\|^pactl" <<< "$(calls)" && grep -q "^notify-send .*--urgency=normal -- Find My PC Lost mode is off. Welcome back!$" <<< "$(calls)"'
check G7 '[ "$(python3 -c "import json,sys; print(len(json.load(open(sys.argv[1]))[\"list\"]))" "$WORK/run/alert.json")" = 5 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find My PC tests G passed."; else echo "$failures Find My PC test(s) failed."; fi
exit "$((failures > 0))"
