#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), cases I-P: the hot / cold hunt (Bluetooth and Wi-Fi), background
# watch ("is a tracker following me?"), the follow rule's limits, trip watch, and a follower in a sweep.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost-watch.sh <repo-root>
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
export FAKE_OFFLINE=1
S="$WORK/data/forgeos/ghost/sightings.jsonl"
R="$WORK/home/Documents/GhostFinder/GhostFinder report.txt"
T0=1800000000
at() { FORGEOS_GHOST_NOW="$1" G "${@:2}"; }
notes() { grep -c "^notify-send" "$WORK/calls.log"; }

# I: Bluetooth hunt - hotter as you get closer; "searching" for up to 10 s, then "lost"
ble "T1,-95,apple,$AIRTAG" "T1,-80,apple,$AIRTAG" "T1,-64,apple,$AIRTAG" "T1,-48,apple,$AIRTAG" "X,-50,none"
OUT="$(G hunt t1 --secs 15)"; RC=$?
check I1 '[ "$RC" -eq 0 ] && [ "$(head -n 4 <<< "$OUT" | cut -f2,3 | tr "\t\n" ":|")" = "8:COLD|33:COOL|60:WARM|86:RIGHT ON IT|" ]'
check I2 '[ "$(sed -n 5p <<< "$OUT")" = "LEVEL${T}86${T}searching..." ] && [ "$(sed -n 13p <<< "$OUT")" = "LEVEL${T}86${T}searching..." ] && [ "$(sed -n 14p <<< "$OUT")" = "LEVEL${T}0${T}lost the signal - move around" ] && [ "$(wc -l <<< "$OUT")" -eq 15 ]'

# J: Wi-Fi hunt follows the spy camera's signal; a missed reading cools down by 10
printf '%s\n' 30 70 x 90 > "$WORK/wifi-seq"
OUT="$(G hunt wifi:aa:bb:cc:dd:ee:02 --secs 4)"
check J '[ "$(cut -f2,3 <<< "$OUT" | tr "\t\n" ":|")" = "30:COOL|70:HOT|60:searching...|90:RIGHT ON IT|" ]'

# K: no hunt with Bluetooth off
BLE_POWER=off ble ""
G hunt T1 --secs 2 > "$WORK/out" 2> "$WORK/err"; RC=$?
check K '[ "$RC" -eq 4 ] && grep -q "Bluetooth is off" "$WORK/err" && [ ! -s "$WORK/out" ]'

# L: background watch
: > "$WORK/calls.log"
at "$T0" watch-tick; RC=$?
check L1 '[ "$RC" -eq 0 ] && [ ! -e "$S" ] && [ "$(notes)" -eq 0 ]'
printf 'AA:00:00:00:00:07\tMy own AirTag\n' >> "$WORK/cfg/forgeos/ghost-safe.txt"
ble "AA:00:00:00:00:01,-70,apple,$AIRTAG;AA:00:00:00:00:07,-60,apple,$AIRTAG;AA:00:00:00:00:02,-60,apple,$AIRTAG_NEAR"
at "$T0" watch-tick                                  # at home
grep -v '^\*' "$WORK/wifi.home" > "$WORK/wifi"
at $((T0 + 1800)) watch-tick                         # driving: no Wi-Fi
check L2 '[ "$(notes)" -eq 0 ] && [ "$(wc -l < "$S")" -eq 2 ] && ! grep -q "AA:00:00:00:00:0[27]" "$S" && grep -q "\"place\": \"no Wi-Fi\"" "$S"'
printf '%s\n' '*:WorkNet:AA\:BB\:CC\:DD\:EE\:77:60' > "$WORK/wifi"
OUT="$(at $((T0 + 3700)) watch-tick)"                 # at work, 61 minutes later
check L3 '[ "$(notes)" -eq 1 ] && [ "$OUT" = "A tracker (AirTag) may be following you: heard 3 times over 61 minutes in 3 places." ] && grep -q "^notify-send -u critical -a GhostFinder .*Open GhostFinder and sweep to find it.$" "$WORK/calls.log"'
check L4 'grep -q "Background watch: possible tracker following you" "$R" && grep -q "   ID: AA:00:00:00:00:01" "$R"'
at $((T0 + 3700 + 7200)) watch-tick >/dev/null; N1="$(notes)"      # 2 hours later: no repeat yet
at $((T0 + 3700 + 14400)) watch-tick >/dev/null; N2="$(notes)"
check L5 '[ "$N1" -eq 1 ] && [ "$N2" -eq 2 ]'
OUT="$(at $((T0 + 5000)) sweep --secs 1)"
check P '[[ "$(item red AA:00:00:00:00:01)" == "AirTag may be FOLLOWING you - heard "*" times over "*" minutes in 3 places" ]] && [ "$(item green AA:00:00:00:00:07)" = "yours: My own AirTag" ]'

# N: the follow rule needs 3+ sightings, 60+ minutes and 2+ places, all in the last day
rule() {
  python3 - "$S" "$T0" "$@" <<'PYEOF'
import json, sys
path, t0, rows = sys.argv[1], int(sys.argv[2]), []
for spec in sys.argv[3:]:
    minute, place = spec.split("@")
    rows.append({"t": t0 + int(minute) * 60, "id": "AA:00:00:00:00:05", "label": "Tile tracker", "place": place})
open(path, "w").write("".join(json.dumps(r) + "\n" for r in rows))
PYEOF
  at $((T0 + 7200)) watch-tick
}
ble ""
check N1 '[ -z "$(rule 0@a 30@b 59@b)" ] && [ -z "$(rule 0@a 120@b)" ] && [ -z "$(rule 0@a 30@a 60@a)" ] && [ -z "$(rule -2000@a 30@b 90@b)" ]'
check N2 '[[ "$(rule 0@a 30@b 60@b)" == *"(Tile tracker)"*"3 times over 60 minutes in 2 places." ]]'

# M: trip watch
: > "$WORK/cfg/forgeos/ghost-safe.txt"
at "$T0" trip tick >/dev/null 2>&1; R1=$?
at "$T0" trip start
ble "AA:00:00:00:00:01,-70,apple,$AIRTAG;AA:00:00:00:00:08,-80,uuid:feed"
at "$T0" trip tick > "$WORK/out"
ble "AA:00:00:00:00:01,-72,apple,$AIRTAG"
at $((T0 + 300)) trip tick >/dev/null
ble "AA:00:00:00:00:01,-70,apple,$AIRTAG;AA:00:00:00:00:08,-80,uuid:feed"   # the Tile: only 2 of 3 checks
at $((T0 + 660)) trip tick >/dev/null
OUT="$(at $((T0 + 700)) trip stop)"
check M1 '[ "$R1" -eq 1 ] && [ "$(cat "$WORK/out")" = "TRIP${T}1" ] && grep -qx "RED - AirTag stayed with you the whole trip (heard in 3 of 3 checks)" <<< "$OUT" && ! grep -q Tile <<< "$OUT" && grep -q "ITEM${T}red${T}AA:00:00:00:00:01${T}ble${T}" <<< "$OUT"'
check M2 '[ ! -e "$WORK/data/forgeos/ghost/trip.json" ] && grep -q "Trip watch: 3 checks" "$R" && grep -q "   AirTag stayed with you the whole trip" "$R"'
ble ""; at "$T0" trip start; at "$T0" trip tick >/dev/null; at $((T0 + 60)) trip tick >/dev/null
check M3 '[[ "$(at $((T0 + 99)) trip stop)" == "The trip was too short to tell"* ]]'
at "$T0" trip start; for m in 0 60 120; do at $((T0 + m)) trip tick >/dev/null; done
check M4 '[ "$(at $((T0 + 200)) trip stop)" = "GREEN - no tracker stayed with you on this trip (3 checks)." ] && grep -q "No tracker stayed with you." "$R"'
at "$T0" trip start; BLE_POWER=off ble ""; at "$T0" trip tick >/dev/null 2>&1; R1=$?
check M5 '[ "$R1" -eq 4 ]'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
