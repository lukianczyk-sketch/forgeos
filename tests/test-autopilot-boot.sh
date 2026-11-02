#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases F-G: the after-restart check (first look, same version,
# a new version that works, a part that stopped working) and the "Go back" / "Keep this version" note.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-boot.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/autopilot-fakes.sh
. "$ROOT/tests/autopilot-fakes.sh"
dmi "Acer" "Predator" "V1" "$(date -d "-30 days" +%m/%d/%Y)"
newpkgs() { printf 'kernel\t6.17.4-200.fc44\nnvidia-driver\t590.12-1.fc44\nmesa-dri-drivers\t25.2.4-1.fc44\npipewire\t1.4.8-1.fc44\n' > "$WORK/rpm-qa.txt"; }

# F: first look remembers; same version = same (an unplugged USB camera is not a problem); new version works
normal_pc; os aaa
check F1 '[ "$(AP after-boot)" = "OK${T}first${T}" ]'
rm -rf "$WORK/sys/bus/usb/devices/3-1" "$WORK/sys/bus/usb/devices/3-1:1.0"
check F2 '[ "$(AP after-boot)" = "OK${T}same${T}" ]'
usb 3-1 0e 046d 0825 uvcvideo; os bbb; newpkgs
OUT="$(AP after-boot)"; RC=$?
check F3 '[ "$RC" -eq 0 ] && [ "$OUT" = "OK${T}works${T}Core drivers (Linux kernel) 6.17.1 to 6.17.4, Graphics driver (NVIDIA) 580.95 to 590.12" ] && grep -q "${T}works${T}New system version works (Core drivers (Linux kernel) 6.17.1 to 6.17.4, Graphics driver (NVIDIA) 580.95 to 590.12)." "$LOGF"'
OUT="$(AP drivers)"
check F4 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); assert d[\"last_good\"][\"checksum\"]==\"bbb\" and \"590.12\" in d[\"last_change\"][\"text\"]" "$ST" && grep -q "^Last change (.*): Core drivers (Linux kernel) 6.17.1 to 6.17.4, Graphics driver (NVIDIA) 580.95 to 590.12.$" <<< "$OUT"'
# a USB part plugged in at the new version with no driver is not "stopped working" (it never worked)
usb 3-5 0e 1111 2222; os ccc
check F5 '[ "$(AP after-boot | cut -f 1,2)" = "OK${T}works" ]'
rm -rf "$WORK/sys/bus/usb/devices/3-5"*

# G: new version, Wi-Fi lost its driver + the NVIDIA card is gone -> problem; note: Go back / Keep
os ddd; nodriver 0000:00:14.3; rm -rf "$WORK/sys/bus/pci/devices/0000:01:00.0"
OUT="$(AP after-boot)"; RC=$?
check G1 '[ "$RC" -eq 1 ] && [ "$OUT" = "PROBLEM${T}Wi-Fi stopped working (Intel Corporation Meteor Lake PCH CNVi WiFi). Graphics card stopped working (NVIDIA Corporation GB203M [GeForce RTX 5090 Max-Q / Mobile])." ]'
check G2 'grep -q "^AFTERBOOT${T}problem${T}Wi-Fi stopped working" <<< "$(AP status)" && AP check | grep -q "^PROBLEM after the last update: Wi-Fi stopped working" && [ "$(grep -c "${T}problem${T}" "$LOGF")" = 1 ]'
echo back > "$WORK/clicks"; : > "$WORK/calls.log"; AP tick; RC=$?
check G3 '[ "$RC" -eq 1 ] && grep -q "^notify-send .*--urgency=critical --action=back=Go back --action=keep=Keep this version Something stopped working After the last update: Wi-Fi stopped working" "$WORK/calls.log" && grep -qx "forgeos-undo undo-update" "$WORK/calls.log" && calls_wait "Going back Done. Restart the PC"'
# the same problem in the same boot is not shown again; a new boot shows it again; the last good version is kept
: > "$WORK/calls.log"; AP tick
check G4 '! grep -q "Something stopped working" "$WORK/calls.log" && python3 -c "import json,sys; assert json.load(open(sys.argv[1]))[\"last_good\"][\"checksum\"]==\"ccc\"" "$ST"'
export FORGEOS_AP_BOOT_ID=boot-2; echo keep > "$WORK/clicks"; : > "$WORK/calls.log"; AP tick
check G5 'grep -q "Something stopped working" "$WORK/calls.log" && ! grep -q forgeos-undo "$WORK/calls.log" && grep -q "${T}kept${T}Kept the new version" "$LOGF" && [ "$(AP after-boot | cut -f 1,2)" = "OK${T}same" ]'
# go back by hand: back on the old version (ccc) everything is the same as the last good one
os ddd; pci 0000:01:00.0 0x030200 10de 2c58 nvidia; pci 0000:00:14.3 0x028000 8086 7e40 iwlwifi
check G6 'AP go-back --yes | grep -qx "Done. Restart the PC to use the version from before the update." && AP go-back >/dev/null 2>&1; [ $? -eq 3 ]'
fake forgeos-undo 'exit 1'
check G7 '! AP go-back --yes >/dev/null && grep -q "${T}go-back${T}.*FAILED" "$LOGF"'
# busy (a game) does not stop the "stopped working" note, but stops every other note
os eee; nodriver 0000:00:1f.3; touch "$WORK/busy"; export FORGEOS_AP_BOOT_ID=boot-3; echo "" > "$WORK/clicks"; : > "$WORK/calls.log"; AP tick
check G8 'grep -q "Something stopped working After the last update: Sound stopped working" "$WORK/calls.log"'
rm -f "$WORK/busy"

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
