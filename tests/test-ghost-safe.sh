#!/usr/bin/env bash
# Tests for GhostFinder (Job 12), cases D-H: notes when something can't be checked, Wi-Fi fallback,
# the "it's mine" list, "these are all mine", the plain-English advice and the command line.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-ghost-safe.sh <repo-root>
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
R="$WORK/home/Documents/GhostFinder/GhostFinder report.txt"

# D: offline, Bluetooth off / missing / skipped -> notes say what was not checked
BLE_POWER=off ble ""
OUT="$(FAKE_OFFLINE=1 G sweep --secs 1)"
check D1 'grep -qx "NOTE${T}Bluetooth is off, so trackers were not checked." <<< "$OUT" && grep -qx "NOTE${T}Not connected to a network, so cameras on the network were not checked." <<< "$OUT" && grep -qx "VERDICT${T}red" <<< "$OUT" && [ "$(grep -c "^ITEM" <<< "$OUT")" -eq 3 ]'
BLE_POWER=none ble ""
OUT="$(FAKE_OFFLINE=1 G sweep --secs 1)"
check D2 'grep -qx "NOTE${T}This PC has no Bluetooth, so trackers were not checked." <<< "$OUT"'
: > "$WORK/wifi"; ble ""
OUT="$(FAKE_OFFLINE=1 G sweep --secs 1 --no-bt)"
check D3 '[ "$(sed -n 2p <<< "$OUT")" = "GREEN - all clear. No cameras or trackers found." ] && grep -qx "NOTE${T}Trackers were not checked." <<< "$OUT" && grep -q "Sweep at no Wi-Fi: GREEN" "$R"'

# E: a refused Wi-Fi rescan falls back to the list the PC already has
printf '%s\n' '*:Hotel:AA\:BB\:CC\:DD\:EE\:09:70' ':HDWiFiCam-<b>22</b>:AA\:BB\:CC\:DD\:EE\:0A:44' > "$WORK/wifi"; : > "$WORK/calls.log"
OUT="$(FAKE_RESCAN_FAIL=1 FAKE_OFFLINE=1 G sweep --secs 1)"
check E 'grep -q "^nmcli .* --rescan yes$" "$WORK/calls.log" && grep -q "^nmcli .* --rescan no$" "$WORK/calls.log" && [ "$(item red WIFI:AA:BB:CC:DD:EE:0A)" = "Spy-camera Wi-Fi \"HDWiFiCam-b22/b\" nearby - signal 44%" ]'

# F: "it's mine" list and "these are all mine"
cp "$WORK/wifi.home" "$WORK/wifi"; world
G sweep --secs 2 >/dev/null
G safe add aa:00:00:00:00:01 "My keys"; G safe add WIFI:AA:BB:CC:DD:EE:03; G safe add AA:00:00:00:00:99 Old; G safe remove aa:00:00:00:00:99
check F1 '[ "$(G safe list | cut -f1 | tr "\n" " ")" = "AA:00:00:00:00:01 F0:18:98:00:00:17 WIFI:AA:BB:CC:DD:EE:03 " ] && grep -qx "AA:00:00:00:00:01${T}My keys" <<< "$(G safe list)"'
check F2 'grep -q "^WIFI:AA:BB:CC:DD:EE:03${T}Spy-camera Wi-Fi \"V380_77\" nearby - signal 20%$" <<< "$(G safe list)"'
OUT="$(G known-all)"
check F3 '[ "$OUT" = "Marked 4 device(s) on this network as yours." ] && grep -q "^3C:2A:F4:00:00:15${T}printer - 127.0.0.15" <<< "$(G safe list)" && ! grep -Eq "^(BC:AD|00:0C|00:24|WIFI:AA:BB:CC:DD:EE:02|AA:00:00:00:00:0[3468])" <<< "$(G safe list)"'
OUT="$(G sweep --secs 2)"
check F4 '[ "$(item green AA:00:00:00:00:01)" = "yours: My keys" ] && [ -n "$(item green 3C:2A:F4:00:00:15)" ] && [ -n "$(item red BC:AD:28:00:00:10)" ] && [ "$(grep -c "^ITEM${T}yellow" <<< "$OUT")" -eq 5 ]'

# G: what is it / what do I do now
check G1 'grep -q "acts like a camera (maker: Hangzhou Hikvision" <<< "$(G info BC:AD:28:00:00:10)" && grep -q "(port [0-9]* open: video stream (RTSP); maker: VMware, Inc.)" <<< "$(G info 00:0C:29:00:00:11)" && grep -q "answers the network-camera call (ONVIF)" <<< "$(G info 00:24:8c:00:00:12)"'
check G2 'grep -q "Unknown tag search" <<< "$(G info AA:00:00:00:00:03)" && grep -q "1-800-799-7233" <<< "$(G info AA:00:00:00:00:03)" && grep -q "Hunt it" <<< "$(G info WIFI:AA:BB:CC:DD:EE:02)" && grep -q "unplug gadgets one by one" <<< "$(G info 24:D7:EB:00:00:13)"'
G info NOPE >/dev/null 2>&1; RC=$?
check G3 '[ "$RC" -eq 1 ] && grep -q "These are all mine" <<< "$(G info DA:A1:19:00:00:14)" && grep -q "^Bathroom:" <<< "$(G checklist)"'

# H: wrong use, Bluetooth on/off
G >/dev/null 2>&1; R1=$?; G bogus >/dev/null 2>&1; R2=$?; G safe add >/dev/null 2>&1; R3=$?; G trip go >/dev/null 2>&1; R4=$?
check H1 '[ "$R1$R2$R3$R4" = 3333 ]'
BLE_POWER=off ble ""; G bt on; R1=$?; BLE_POWER=off BLE_BLOCKED=1 ble ""; G bt on; R2=$?; BLE_POWER=none ble ""; G bt on; R3=$?
check H2 '[ "$R1$R2$R3" = 044 ] && [ "$(G bt status)" = none ]'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
