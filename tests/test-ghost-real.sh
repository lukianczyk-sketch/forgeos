#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), cases U-V: GhostFinder's REAL Bluetooth code (python3-dbus) talking
# to a fake BlueZ on a private D-Bus bus (tests/ghost-fake-bluez.py). Needs dbus-daemon, python3-dbus
# and python3-gi (CI installs them). GHOST_PY = the python that has them (default python3).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost-real.sh <repo-root>
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
PY="${GHOST_PY:-python3}"
G() { "$PY" "$ENGINE" "$@"; }
unset FORGEOS_GHOST_BLE_FAKE
export FORGEOS_GHOST_BUS=session FAKE_OFFLINE=1
: > "$WORK/wifi"

DBUS_SESSION_BUS_ADDRESS="$(dbus-daemon --session --fork --print-address=1 --print-pid=3 3> "$WORK/bus-pid")"
export DBUS_SESSION_BUS_ADDRESS
"$PY" "$ROOT/tests/ghost-fake-bluez.py" "$WORK" &
BLUEZ_PID=$!
trap 'kill "$BLUEZ_PID" "$(cat "$WORK/bus-pid")" 2>/dev/null; rm -rf "$WORK"' EXIT
for _ in $(seq 50); do grep -q ready "$WORK/bluez.log" 2>/dev/null && break; sleep 0.1; done
L="$WORK/bluez.log"

# U: listen through real D-Bus: only devices heard now; trackers near their owner are ignored
check U1 '[ "$(G bt status)" = on ]'
OUT="$(G sweep --secs 2)"
check U2 '[ -n "$(item yellow AA:00:00:00:00:01)" ] && [ -n "$(item yellow AA:00:00:00:00:03)" ] && [[ "$(item yellow AA:00:00:00:00:08)" == "Tile tracker nearby"* ]] && [ "$(grep -c "^ITEM" <<< "$OUT")" -eq 3 ] && ! grep -q "NOTE${T}Bluetooth" <<< "$OUT"'
check U3 'grep -qx "SetDiscoveryFilter DuplicateData=1 Transport=le" "$L" && [ "$(grep -c "^StartDiscovery$" "$L")" -eq 1 ] && [ "$(grep -c "^StopDiscovery$" "$L")" -eq 1 ]'
# The AirTag gets 15 dBm closer every look: -90 and -75 in the sweep, so -60, -45, -40 now.
OUT="$(G hunt aa:00:00:00:00:01 --secs 3)"
check U4 '[ "$(cut -f2 <<< "$OUT" | tr "\n" " ")" = "66 91 100 " ] && [ "$(grep -c "^StopDiscovery$" "$L")" -eq 2 ]'

# V: Bluetooth turned off -> status off, sweep says so, no discovery started; then back on
G bt off; R1=$?
OUT="$(G sweep --secs 1)"
check V1 '[ "$R1" -eq 0 ] && [ "$(G bt status)" = off ] && grep -q "^Set org.bluez.Adapter1 Powered False$" "$L" && grep -qx "NOTE${T}Bluetooth is off, so trackers were not checked." <<< "$OUT" && [ "$(grep -c "^StartDiscovery$" "$L")" -eq 2 ]'
G hunt AA:00:00:00:00:01 --secs 1 >/dev/null 2>&1; R2=$?
G bt on; R3=$?
check V2 '[ "$R2" -eq 4 ] && [ "$R3" -eq 0 ] && [ "$(G bt status)" = on ]'
kill "$BLUEZ_PID"; wait "$BLUEZ_PID" 2>/dev/null
OUT="$(G sweep --secs 1)"
check V3 '[ "$(G bt status)" = none ] && grep -qx "NOTE${T}This PC has no Bluetooth, so trackers were not checked." <<< "$OUT"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
