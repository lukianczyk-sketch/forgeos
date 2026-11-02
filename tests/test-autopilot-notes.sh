#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases K-N: the notes the timer shows (one per run, most
# important first, none during a game): new drivers ready, automatic updates broken, Secure Boot,
# the better ForgeOS version, a part with no driver, BIOS Watch for an old BIOS.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-notes.sh <repo-root>
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
normal_pc; os aaa; dmi "Acer" "Predator" "V1.05" "$(date -d "-30 days" +%m/%d/%Y)"; AP after-boot >/dev/null
tick() { : > "$WORK/calls.log"; printf '%s\n' "$@" > "$WORK/clicks"; AP tick; }
notes() { grep -c "^notify-send .*--wait" "$WORK/calls.log"; }
forget() { python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.pop('told',None); d.pop('later_until',None); d.pop('pending_told',None); json.dump(d,open(p,'w'))" "$ST"; }

# K: nothing to say = no note; new drivers waiting: Restart now = KDE restart; Later = not again for 20 hours
tick
check K1 '[ "$(notes)" = 0 ] && grep -q "^fwupdmgr get-updates --json" "$WORK/calls.log"'
echo '{"pkgdiff": [["mesa-dri-drivers", 2, {"PreviousPackage": ["mesa-dri-drivers", "25.2.4-1", "x86_64"], "NewPackage": ["mesa-dri-drivers", "25.2.6-1", "x86_64"]}]], "advisories": []}' > "$WORK/dbdiff.json"
os aaa bbb; tick later
check K2 '[ "$(notes)" = 1 ] && grep -q "^notify-send .*--action=restart=Restart now --action=later=Later New drivers are ready New: Graphics driver (AMD/Intel) 25.2.4 to 25.2.6." "$WORK/calls.log" && ! grep -q logoutAndReboot "$WORK/calls.log"'
tick restart
check K3 '[ "$(notes)" = 0 ]'
forget; tick restart
check K4 'grep -qx "busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logoutAndReboot" "$WORK/calls.log"'
forget; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d['pending_told']='bbb'; json.dump(d,open(p,'w'))" "$ST"; tick
check K5 '[ "$(notes)" = 0 ]'
os aaa; rm -f "$WORK/dbdiff.json"

# L: automatic updates switched off: Fix it = switch the updater back on (the PC password is asked)
echo disabled > "$WORK/uupd"; tick fix
check L1 'grep -q "Automatic updates Automatic system and driver updates are not working. Fix it now?" "$WORK/calls.log" && grep -qx "systemctl enable --now uupd.timer" "$WORK/calls.log" && calls_wait "Automatic updates Fixed."'
tick fix
check L2 '[ "$(notes)" = 0 ] && AP fix-updates | grep -qx "Automatic updates are on again."'
rm -f "$WORK/uupd"; forget

# M: Secure Boot blocks NVIDIA (fix = terminal); a better ForgeOS version (Show me = window); a part with no driver (once)
nvidia_loaded no; secureboot 1; tick fix
check M1 'grep -q "^notify-send .*--urgency=critical .*Graphics driver blocked Secure Boot is blocking the NVIDIA driver" "$WORK/calls.log" && calls_wait "^konsole -e ujust enroll-secure-boot-key$"'
nvidia_loaded yes; os aaa "" "$REF_PLAIN"; tick show
check M2 'grep -q "Faster graphics This PC would run better on the NVIDIA version of ForgeOS." "$WORK/calls.log" && calls_wait "^gui --image$"'
tick show
check M3 '[ "$(notes)" = 0 ]'
os aaa; pci 0000:05:00.0 0x028000 14e4 43a0; tick show
check M4 'grep -q "A part has no driver Broadcom Inc. and subsidiaries BCM4360 802.11ac Dual Band Wireless Network Adapter: This Wi-Fi chip has no Linux driver." "$WORK/calls.log" && calls_wait "^gui --devices$"'
tick show
check M5 '[ "$(notes)" = 0 ]'
rm -rf "$WORK/sys/bus/pci/devices/0000:05:00.0"

# N: BIOS Watch: an old BIOS from a maker not on the LVFS (twice a year); not when fwupd can update the BIOS
dmi "Acer" "Predator" "V1.02" "01/10/2022"; tick show
check N1 'grep -q "Old BIOS Your BIOS is from January 2022. Acer doesn.t send BIOS updates to ForgeOS by itself." "$WORK/calls.log" && calls_wait "^gui --bios$"'
tick show
check N2 '[ "$(notes)" = 0 ]'
forget; echo "{\"Devices\": [$BIOS_DEV]}" > "$WORK/fw-devices.json"; tick show
check N3 '[ "$(notes)" = 0 ]'
# a game is running: no notes at all (and firmware waits); one note per run, most important first
forget; rm -f "$WORK/fw-devices.json"; touch "$WORK/busy"; echo disabled > "$WORK/uupd"; tick show
check N4 '[ "$(notes)" = 0 ] && ! grep -q "^fwupdmgr" "$WORK/calls.log"'
rm -f "$WORK/busy"; tick later later later
check N5 '[ "$(notes)" = 1 ] && grep -q "Automatic updates" "$WORK/calls.log"'
tick later later
check N6 '[ "$(notes)" = 1 ] && grep -q "Old BIOS" "$WORK/calls.log"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
