#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), cases Q-S: the window (sweep, results, what is it, hunt meter,
# "it's mine", "these are all mine", rooms, report, background watch on/off) and the trip window.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/ghost-fakes.sh
. "$ROOT/tests/ghost-fakes.sh"
# shellcheck source=tests/ghost-gui-fakes.sh
. "$ROOT/tests/ghost-gui-fakes.sh"
start_net
power() { python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["power"])' "$WORK/ble.json"; }

# Q: Bluetooth is off -> turn it on; sweep; AirTag: info, hunt (Cancel on the 3rd reading), it's mine;
#    these are all mine; back; rooms; report; background watch on, then off; close -> Bluetooth back off.
BLE_POWER=off world
printf '%s\n' sweep AA:00:00:00:00:01 info hunt safe allmine back rooms report watch watch > "$WORK/menu"
printf '%s\n' no no yes > "$WORK/cancel"
bash "$GUI"; RC=$?
SHOWN="$(cat "$WORK/shown")"
check Q1 '[ "$RC" -eq 0 ] && grep -q "Bluetooth is off, so trackers" <<< "$SHOWN" && [ "$(power)" = off ] && [ ! -s "$WORK/menu" ]'
check Q2 'grep -q "^RED - possible camera or tracker found" <<< "$SHOWN" && grep -qx "🔴 Camera on this network: camera made by Hangzhou Hikvision Digital Technology Co.,Ltd. - 127.0.0.10" <<< "$SHOWN" && grep -qx "🟡 AirTag away from its owner - very close (a few feet)" <<< "$SHOWN"'
check Q3 'grep -q "white side" <<< "$SHOWN" && grep -q "^hunt$" <<< "$SHOWN" && grep -q "won'"'"'t warn you about this one again" <<< "$SHOWN" && grep -qx "AA:00:00:00:00:01${T}AirTag away from its owner - very close (a few feet)" <(G safe list)'
check Q4 '[ "$(grep -c "^pw-play $WORK/home/.cache/forgeos/ghost-beep.wav$" "$WORK/calls.log")" -eq 1 ] && grep -q "Properties.Set string:org.kde.kdialog.ProgressDialog string:value variant:int32:80$" "$WORK/calls.log" && grep -q "setLabelText string:HOT  (80%)" "$WORK/calls.log" && grep -q "ProgressDialog.close$" "$WORK/calls.log"'
# After "it's mine" the AirTag is gone from the list; after "these are all mine" new devices are gone, cameras stay.
LAST="$(awk '/^Pick one/{n++} END{print n}' <<< "$SHOWN")"
check Q5 '[ "$LAST" -eq 3 ] && grep -q "Marked 4 device(s) on this network as yours." <<< "$SHOWN" && grep -q "Cameras and trackers are never marked this way" <<< "$SHOWN" && [ "$(grep -c "^🟡 New device" <<< "$SHOWN")" -eq 8 ]'
check Q6 'grep -q "^Bedroom: smoke detector" <<< "$SHOWN" && grep -q "Sweep at HomeNet (AA:BB:CC:DD:EE:01): RED" <<< "$SHOWN" && grep -q "Background watch is on. Every 10 minutes" <<< "$SHOWN" && grep -q "^Background watch is off.$" <<< "$SHOWN" && [ "$(cat "$WORK/watch-state")" = disabled ]'

# R: trip window - Bluetooth off and not turned on -> can't watch; then a trip with 2 checks
: > "$WORK/shown"; : > "$WORK/calls.log"; BLE_POWER=off ble ""
printf '%s\n' trip > "$WORK/menu"; printf '%s\n' 1 0 > "$WORK/yes"
bash "$GUI"
check R1 'grep -q "Bluetooth is off, so a trip can'"'"'t be watched" "$WORK/shown" && [ ! -e "$WORK/data/forgeos/ghost/trip.json" ]'
: > "$WORK/shown"; world
printf '%s\n' trip > "$WORK/menu"; { printf 'no\n%.0s' {1..40}; echo yes; } > "$WORK/cancel"
bash "$GUI"
check R2 'grep -q "^systemd-inhibit --what=idle:sleep --who=GhostFinder --why=Watching this trip for trackers sleep 86400$" "$WORK/calls.log" && grep -q "Watching this trip... 2 check(s) done." "$WORK/calls.log" && grep -q "The trip was too short to tell" "$WORK/shown" && ! grep -q "^ITEM" "$WORK/shown"'
check R3 '[ ! -e "$WORK/data/forgeos/ghost/trip.json" ] && grep -q "Trip watch: 2 checks" "$WORK/home/Documents/GhostFinder/GhostFinder report.txt"'

# S: wrong use; no kdialog
bash "$METER" >/dev/null 2>&1; R1=$?; bash "$METER" hunt >/dev/null 2>&1; R2=$?
mkdir -p "$WORK/nokd"; for t in bash env python3 mktemp rm dirname; do ln -sf "$(command -v "$t")" "$WORK/nokd/$t"; done
PATH="$WORK/nokd" bash "$GUI" 2> "$WORK/err"; R3=$?
check S '[ "$R1$R2$R3" = 333 ] && grep -q "kdialog is needed" "$WORK/err"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
