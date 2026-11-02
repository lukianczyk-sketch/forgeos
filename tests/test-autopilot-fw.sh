#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases H-I: firmware from fwupd (only signed LVFS updates),
# device firmware by itself / ask first / stop after 2 failures.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-fw.sh <repo-root>
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
normal_pc; os aaa; dmi "Dell Inc." "XPS 13" "1.18.0" "$(date -d "-30 days" +%m/%d/%Y)"; AP after-boot >/dev/null
echo "{\"Devices\": [$BIOS_DEV, $MOUSE_DEV]}" > "$WORK/fw-devices.json"
WEB="{\"Name\": \"Webcam\", \"DeviceId\": \"cam1\", \"Flags\": [\"updatable\"], \"Version\": \"1.0\"}"

# H: list: the BIOS and a receiver; lvfs-testing and unsigned releases are skipped; nothing = exit 0
fw_updates "$BIOS_DEV" "$(rel 1.21.0 "Fixes 2 security problems.")" "$MOUSE_DEV" "$(rel RQR12.11 "Better battery life.")" \
  "$WEB" "$(rel 2.0 "Test build." lvfs-testing)"
OUT="$(AP firmware list)"; RC=$?
check H1 '[ "$RC" -eq 2 ] && grep -qx "UPDATE${T}bios1${T}System Firmware${T}1.18.0${T}1.21.0${T}bios${T}-${T}Fixes 2 security problems." <<< "$OUT" && grep -qx "UPDATE${T}rcv1${T}Unifying Receiver${T}RQR12.10${T}RQR12.11${T}device${T}-${T}Better battery life." <<< "$OUT" && ! grep -q cam1 <<< "$OUT"'
fw_updates "$WEB" "$(rel 2.0 "Unsigned." lvfs none)"
check H2 '! AP firmware list | grep -q cam1'
rm -f "$WORK/fw-updates.json"
check H3 '[ "$(AP firmware list)" = "All firmware is up to date." ] && grep -qx "BIOS${T}Dell Inc.${T}XPS 13${T}1.18.0${T}$(date -d "-30 days" +%m/%d/%Y)${T}lvfs" <<< "$(AP status)" && AP check | grep -qx "BIOS: up to date (version 1.18.0)."'
echo "{\"Devices\": [$MOUSE_DEV]}" > "$WORK/fw-devices.json"
check H4 'grep -q "^BIOS${T}.*${T}unknown$" <<< "$(AP status)" && grep -qx "WAY${T}unknown" <<< "$(AP bios)"'
echo "{\"Devices\": [${BIOS_DEV/\"updatable\", /}]}" > "$WORK/fw-devices.json"
check H5 'grep -qx "WAY${T}watch" <<< "$(AP bios)" && grep -qx "PAGE${T}Dell${T}https://www.dell.com/support/home/en-us" <<< "$(AP bios)"'
echo "{\"Devices\": [$BIOS_DEV, $MOUSE_DEV]}" > "$WORK/fw-devices.json"

# I: device firmware installs by itself (with notes); ask mode asks; 2 failures = stop trying that version
fw_updates "$MOUSE_DEV" "$(rel RQR12.11 "Better battery life.")"
: > "$WORK/calls.log"; AP tick
check I1 'grep -qx "fwupdmgr update rcv1 --assume-yes --no-reboot-check" "$WORK/calls.log" && calls_wait "Updating Unifying Receiver Better battery life." && calls_wait "Done Unifying Receiver is up to date." && grep -q "${T}firmware${T}Unifying Receiver RQR12.10 to RQR12.11: installed" "$LOGF"'
echo 1 > "$WORK/fw-update-rc"; : > "$WORK/calls.log"; AP tick; AP tick; AP tick
check I2 '[ "$(grep -c "^fwupdmgr update rcv1" "$WORK/calls.log")" = 2 ] && calls_wait "Firmware update failed Unifying Receiver was not changed" && [ "$(grep -c "RQR12.11: FAILED" "$LOGF")" = 2 ]'
rm -f "$WORK/fw-update-rc"; fw_updates "$MOUSE_DEV" "$(rel RQR12.12 "Newer.")"; AP set devices ask >/dev/null
echo go > "$WORK/clicks"; : > "$WORK/calls.log"; AP tick
check I3 'grep -q "^notify-send .*--wait.*--action=go=Install --action=later=Not now Firmware update Unifying Receiver: RQR12.10 to RQR12.12. Newer." "$WORK/calls.log" && grep -qx "fwupdmgr update rcv1 --assume-yes --no-reboot-check" "$WORK/calls.log" && calls_wait "Unifying Receiver Updated."'
: > "$WORK/calls.log"; AP tick
check I4 '! grep -q "Firmware update" "$WORK/calls.log"'
AP set devices auto >/dev/null; OUT="$(AP firmware install devices)"; RC=$?
check I5 '[ "$RC" -eq 0 ] && [ "$OUT" = "Unifying Receiver is up to date." ] && [ "$(AP firmware install nope)" = "No update is waiting for that." ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
