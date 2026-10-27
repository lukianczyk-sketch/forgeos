#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), cases A-C: which Bluetooth signals are trackers away from their owner, and a
# full sweep of a fake network (real sockets on 127.0.0.x).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost.sh <repo-root>
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
start_net

# kind HEX-OR-SPEC: what trackers.classify says ("kind sure extra", or "none").
kind() {
  python3 -B - "$@" <<'PYEOF'
import os, sys
sys.path.insert(0, os.environ["FORGEOS_GHOST_LIB"])
from ghostlib import trackers
where, value = sys.argv[1], bytes.fromhex(sys.argv[2]) if len(sys.argv) > 2 else b""
dev = {"mfg": {0x4C: value}} if where == "apple" else {"svc": {where: value}} if len(sys.argv) > 2 else {"uuids": [where]}
k = trackers.classify(dev)
print("none" if k is None else "%s %s %s" % (k["kind"], k["sure"], k["extra"]))
PYEOF
}

# A: tracker signals (AirGuard / IETF DULT facts)
check A1 '[ "$(kind apple "$AIRTAG")" = "airtag True battery medium" ] && [ "$(kind apple "$AIRTAG_NEAR")" = none ]'
check A2 '[ "$(kind apple "$AIRPODS")" = "airpods True battery low" ] && [ "$(kind apple 1219E0)" = "findmy True battery very low" ] && [ "$(kind apple 121900)" = "apple True battery full" ] && [ "$(kind apple 0719AA)" = none ]'
check A3 '[ "$(kind fd5a 03)" = "smarttag True " ] && [ "$(kind fd5a 02)" = "smarttag True " ] && [ "$(kind fd5a 01)" = none ] && [ "$(kind fd5a 05)" = none ]'
check A4 '[ "$(kind feaa 41AB)" = "google True " ] && [ "$(kind feaa 40AB)" = none ] && [ "$(kind feaa 10AB)" = none ]'
check A5 '[ "$(kind fcb2 0100)" = "dult True " ] && [ "$(kind fcb2 0101)" = none ] && [ "$(kind fd69 00)" = "galaxy True " ]'
check A6 '[ "$(kind 0000FEED-0000-1000-8000-00805F9B34FB)" = "tile False " ] && [ "$(kind fe33)" = "chipolo False " ] && [ "$(kind fa25)" = "pebblebee False " ] && [ "$(kind 180f)" = none ]'
LV="$(python3 -B -c 'import os,sys; sys.path.insert(0, os.environ["FORGEOS_GHOST_LIB"]); from ghostlib.trackers import level, words; print(*[level(r) for r in (-110, -100, -70, -40, -20)], *[words(l) for l in (0, 30, 50, 70, 90)])')"
check A7 '[ "$LV" = "0 0 50 100 100 COLD COOL WARM HOT RIGHT ON IT" ]'

# B: one full sweep of the fake world
world
OUT="$(G sweep --secs 2)"; RC=$?
check B1 '[ "$RC" -eq 0 ] && [ "$(sed -n 2p <<< "$OUT")" = "RED - possible camera or tracker found. Look at the red items." ] && grep -qx "VERDICT${T}red" <<< "$OUT"'
check B2 '[ "$(item red BC:AD:28:00:00:10)" = "Camera on this network: camera made by Hangzhou Hikvision Digital Technology Co.,Ltd. - 127.0.0.10" ] && [ "$(item red 00:0C:29:00:00:11)" = "Camera on this network: camera made by VMware, Inc. - 127.0.0.11" ] && [ "$(item red 00:24:8C:00:00:12)" = "Camera on this network: camera - 127.0.0.12" ]'
check B3 '[ "$(item red WIFI:AA:BB:CC:DD:EE:02)" = "Spy-camera Wi-Fi \"IPC-4F2A91\" nearby - signal 55%" ] && [ -n "$(item yellow WIFI:AA:BB:CC:DD:EE:03)" ] && [ -n "$(item yellow WIFI:AA:BB:CC:DD:EE:05)" ] && ! grep -q "Bob\|HomeNet" <<< "$OUT"'
check B4 '[ "$(item yellow AA:00:00:00:00:01)" = "AirTag away from its owner - very close (a few feet)" ] && [ -z "$(item yellow AA:00:00:00:00:02)" ] && [ -z "$(item yellow AA:00:00:00:00:09)" ] && [ "$(item yellow AA:00:00:00:00:06)" = "item tracker (Android / any brand) away from its owner - close (same room)" ]'
check B5 '[ "$(item yellow AA:00:00:00:00:08)" = "Tile tracker nearby (this brand can'"'"'t say if its owner is with it) - farther away (next room or outside)" ] && [ -n "$(item yellow AA:00:00:00:00:03)" ] && [ -n "$(item yellow AA:00:00:00:00:04)" ]'
check B6 '[ "$(item yellow 3C:2A:F4:00:00:15)" = "New device: printer - 127.0.0.15 \"Brother HL-L2350DW v1.2 i\"" ] && [ -n "$(item yellow 24:D7:EB:00:00:13)" ] && [[ "$(item yellow DA:A1:19:00:00:14)" == *"hides its maker"* ]] && [[ "$(item yellow 00:12:AB:00:00:18)" == *"chip often used in cheap cameras"* ]]'
check B7 '[ "$(item green F0:18:98:00:00:17)" = "yours: My MacBook" ] && [[ "$(item green 00:11:22:33:44:01)" == "your router"* ]] && ! grep -Eq "127.0.0.1[69]( |$)" <<< "$OUT" && [ "$(grep -c "^ITEM" <<< "$OUT")" -eq 17 ] && grep -q "^2 known or safe device(s) look fine.$" <<< "$OUT"'
check B8 'grep -q "NetworkVideoTransmitter" "$WORK/wsd-probe" && grep -q "uuid:forgeos-" "$WORK/wsd-probe" && grep -q "^avahi-browse -aprt$" "$WORK/calls.log"'
R="$WORK/home/Documents/GhostFinder/GhostFinder report.txt"
check B9 'grep -q "Sweep at HomeNet (AA:BB:CC:DD:EE:01): RED" "$R" && grep -q "   RED: Camera on this network: camera - 127.0.0.12" "$R" && ! grep -q "yours:" "$R" && [ -s "$WORK/data/forgeos/ghost/last-sweep.json" ] && [ "$(stat -c %a "$WORK/data/forgeos/ghost")" = 700 ]'

# C: the AirTag was heard twice; the strongest signal is kept and it is remembered once per sweep
check C1 'grep -q "very close" <<< "$(item yellow AA:00:00:00:00:01)" && [ "$(grep -c "AA:00:00:00:00:01" "$WORK/data/forgeos/ghost/sightings.jsonl")" -eq 1 ] && ! grep -q "AA:00:00:00:00:02" "$WORK/data/forgeos/ghost/sightings.jsonl"'
G sweep --json --secs 1 > "$WORK/json"
check C2 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"level\"]==\"red\" and len(d[\"items\"])==16" "$WORK/json"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
