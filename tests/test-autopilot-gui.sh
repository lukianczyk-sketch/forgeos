#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases O-P: the Drivers & BIOS window (kdialog is faked:
# it answers menus and yes/no questions from $WORK/kd, one line per question, and keeps every text shown).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-gui.sh <repo-root>
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
fake kdialog 'case "$3" in
  --msgbox|--sorry) printf "%s\n" "$4" >> "$WORK/shown"; exit 0 ;;
  --textbox) cat "$4" >> "$WORK/shown"; exit 0 ;;
esac
a="$(head -n 1 "$WORK/kd" 2>/dev/null)"; sed -i 1d "$WORK/kd" 2>/dev/null
printf "%s\n" "$4" >> "$WORK/asked"
case "$a" in no|"") exit 1 ;; yes) exit 0 ;; *) echo "$a" ;; esac'
win() { : > "$WORK/calls.log"; : > "$WORK/shown"; : > "$WORK/asked"; printf '%s\n' "${@:2}" > "$WORK/kd"; bash "$GUI" "$1"; }
normal_pc; os aaa; dmi "Acer" "Predator PHN18-72" "V1.05" "01/10/2022"; AP after-boot >/dev/null

# O: main window: plain head lines; Check everything; Install waiting updates; Device Check; Settings
win "" check
check O1 'grep -q "^Drivers: up to date (they update by themselves)$" "$WORK/asked" && grep -q "^BIOS: V1.05 from 01/10/2022 - your maker doesn.t send updates to ForgeOS$" "$WORK/asked" && grep -q "^Devices: every part has a driver" "$WORK/asked" && grep -q "^Your BIOS is over a year old" "$WORK/shown"'
echo "{\"Devices\": [$BIOS_DEV, $MOUSE_DEV]}" > "$WORK/fw-devices.json"
fw_updates "$BIOS_DEV" "$(rel 1.21.0 "Fixes.")" "$MOUSE_DEV" "$(rel RQR12.11 "Better.")"
win "" install rcv1
check O2 'grep -q "^BIOS: new version 1.21.0 is ready$" "$WORK/asked" && grep -q "^Device firmware: 1 update(s) ready$" "$WORK/asked" && grep -qx "fwupdmgr update rcv1 --assume-yes --no-reboot-check" "$WORK/calls.log" && grep -qx "Unifying Receiver is up to date." "$WORK/shown"'
power 1 20; win "" install bios1
check O3 'grep -qx "Let the battery charge to at least 50% first (now 20%)." "$WORK/shown" && ! grep -q "^fwupdmgr update" "$WORK/calls.log"'
power 1 90; win "" install bios1 yes
check O4 'grep -q "^The BIOS update installs the next time you restart" "$WORK/asked" && grep -qx "fwupdmgr update bios1 --assume-yes --no-reboot-check" "$WORK/calls.log" && grep -q "^Ready. It installs the next time you restart" "$WORK/shown"'
rm -f "$WORK/fw-updates.json"; pci 0000:05:00.0 0x028000 14e4 43a0
win "" devices
check O5 'grep -q "^Devices: 1 part(s) with NO driver$" "$WORK/asked" && grep -qx "These parts have NO driver:" "$WORK/shown" && grep -qx "! Wi-Fi: Broadcom Inc. and subsidiaries BCM4360 802.11ac Dual Band Wireless Network Adapter (pci:14e4:43a0)" "$WORK/shown" && grep -qx "Working parts:" "$WORK/shown"'
rm -rf "$WORK/sys/bus/pci/devices/0000:05:00.0"
win "" settings ask
check O6 'grep -qx "devices=ask" "$WORK/cfg/forgeos/autopilot.conf" && grep -qx "Device firmware: asks you first." "$WORK/shown"'
echo '{"pkgdiff": [["kernel", 2, {"PreviousPackage": ["kernel", "6.17.1-1", "x"], "NewPackage": ["kernel", "6.17.4-1", "x"]}]]}' > "$WORK/dbdiff.json"; os aaa bbb
win "" changed install restart yes
check O7 'grep -qx "New drivers are ready: Core drivers (Linux kernel) 6.17.1 to 6.17.4." "$WORK/shown" && grep -qx -- "- Graphics driver (NVIDIA): 580.95" "$WORK/shown" && grep -q "logoutAndReboot" "$WORK/calls.log"'
os aaa

# P: BIOS help (maker page / LVFS), switch version, the after-update problem, the no-kdialog and wrong-use exits
rm -f "$WORK/fw-devices.json"; win --bios yes
check P1 'grep -q "^Your PC maker does not send BIOS updates to ForgeOS by itself" "$WORK/asked" && grep -q "ask a PC shop or a helper with Windows" "$WORK/asked" && calls_wait "^xdg-open https://www.acer.com/us-en/support/drivers-and-manuals$"'
dmi "ASUSTeK COMPUTER INC." "ROG" "310" "01/10/2022"; win --bios no
check P2 'grep -q "with the BIOS.s own EZ Flash tool" "$WORK/asked" && ! grep -q xdg-open "$WORK/calls.log"'
echo "{\"Devices\": [$BIOS_DEV]}" > "$WORK/fw-devices.json"; win --bios
check P3 'grep -q "Your PC maker sends BIOS updates to ForgeOS" "$WORK/shown"'
os aaa "" "$REF_PLAIN"; win --image yes
check P4 'grep -q "^This PC has an NVIDIA graphics card" "$WORK/asked" && grep -qx "rpm-ostree rebase $REF_NV" "$WORK/calls.log" && grep -qx "Done. Restart the PC to finish switching." "$WORK/shown"'
os aaa; win --image
check P5 'grep -qx "You are on the right version of ForgeOS for this PC.s graphics." "$WORK/shown"'
os ccc; nodriver 0000:00:1f.3; win --problem back
check P6 'grep -q "^After the last update: Sound stopped working" "$WORK/asked" && grep -qx "forgeos-undo undo-update" "$WORK/calls.log"'
win "" problem keep
check P7 'grep -q "^PROBLEM after the last update: Sound stopped working" "$WORK/asked" && grep -qx "OK - ForgeOS will keep this version." "$WORK/shown" && [ "$(AP after-boot | cut -f 1,2)" = "OK${T}same" ]'
bash "$GUI" --nope 2>/dev/null; R1=$?; mv "$WORK/bin/kdialog" "$WORK/bin/kd-off"; PATH="$WORK/bin:/usr/bin:/bin" bash "$GUI" 2>/dev/null; R2=$?
check P8 '[ "$R1$R2" = 33 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
