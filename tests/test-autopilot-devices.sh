#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases C-E: Device Check (names, advice), the right ForgeOS
# version for the graphics card (and switching), an NVIDIA driver blocked by Secure Boot.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-devices.sh <repo-root>
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
normal_pc; os aaa

# C: Device Check: hwdata names, no driver, the general tip, an unknown maker, bridges skipped
pci 0000:03:00.0 0x028000 14e4 43a0
pci 0000:04:00.0 0x028000 abcd 1234
OUT="$(AP devices)"; RC=$?
check C1 '[ "$RC" -eq 1 ] && grep -qx "MISSING${T}Wi-Fi${T}Broadcom Inc. and subsidiaries BCM4360 802.11ac Dual Band Wireless Network Adapter${T}pci:14e4:43a0${T}This Wi-Fi chip has no Linux driver. A USB Wi-Fi adapter that says .Linux. on the box works right away." <<< "$OUT"'
check C2 'grep -q "^MISSING${T}Wi-Fi${T}maker abcd model 1234${T}pci:abcd:1234${T}" <<< "$OUT" && ! grep -q "^OK" <<< "$OUT" && ! grep -q smbus <<< "$(AP devices --all)" && [ "$(AP devices --all | grep -c "^OK")" = 6 ]'
check C3 'grep -qx "DEVICES${T}2" <<< "$(AP status)" && AP check | grep -q "^No driver: Wi-Fi (Broadcom Inc. and subsidiaries BCM4360"'
rm -rf "$WORK/sys/bus/pci/devices/0000:03:00.0" "$WORK/sys/bus/pci/devices/0000:04:00.0"
usb 3-2 0e 1234 5678; usb 3-3 08 0781 5583 usb-storage
check C4 'AP devices | grep -qx "MISSING${T}Camera${T}maker 1234 model 5678${T}usb:1234:5678${T}This camera has no driver. Most USB webcams that say .UVC. work right away." && [ "$(AP devices | wc -l)" = 1 ]'

# D: right version for the graphics card: NVIDIA on the plain image, no NVIDIA on the NVIDIA image,
# an old (Pascal) NVIDIA card stays on plain; switching rebases to the other signed image
rm -rf "$WORK/sys/bus/usb/devices/3-2"* "$WORK/sys/bus/usb/devices/3-3"*
os aaa "" "$REF_PLAIN"
OUT="$(AP image)"
check D1 '[ "$OUT" = "IMAGE${T}to-nvidia${T}${REF_PLAIN}${T}${REF_NV}" ] && grep -qx "IMAGE${T}to-nvidia" <<< "$(AP status)" && AP check | grep -qx "This PC would run better on the NVIDIA version of ForgeOS."'
: > "$WORK/calls.log"; OUT="$(AP switch-image --yes)"; RC=$?
check D2 '[ "$RC" -eq 0 ] && grep -qx "rpm-ostree rebase $REF_NV" "$WORK/calls.log" && [ "$OUT" = "Done. Restart the PC to finish switching." ]'
echo 1 > "$WORK/rebase-rc"; OUT="$(AP switch-image --yes)"; RC=$?; rm -f "$WORK/rebase-rc"
check D3 '[ "$RC" -eq 1 ] && [ "$OUT" = "Could not switch (nothing was changed)." ]'
rm -rf "$WORK/sys/bus/pci/devices/0000:01:00.0"; os aaa "" "$REF_NV"
check D4 '[ "$(AP image | cut -f 2,4)" = "to-plain${T}${REF_PLAIN}" ] && AP check | grep -qx "This PC would run better on the AMD/Intel version of ForgeOS."'
pci 0000:01:00.0 0x030000 10de 1c8d nouveau
check D5 '[ "$(AP image | cut -f 2)" = to-plain ] && os aaa "" "$REF_PLAIN" && [ "$(AP image | cut -f 2)" = old-nvidia ] && AP check | grep -q "^Graphics: this NVIDIA card is older than" && [ "$(AP check >/dev/null; echo $?)" = 1 ]'
os aaa "" "ostree-image-signed:docker://ghcr.io/ublue-os/bazzite:stable"
check D6 '[ "$(AP image | cut -f 2,4)" = "unknown${T}-" ] && AP switch-image --yes | grep -q "^Could not switch"'

# E: NVIDIA image, new card, driver not loaded: Secure Boot on = blocked (fix opens a terminal); off = not loaded
pci 0000:01:00.0 0x030200 10de 2c58; os aaa "" "$REF_NV"; nvidia_loaded no; secureboot 1
check E1 'grep -qx "NVIDIA${T}secure-boot" <<< "$(AP status)" && AP check | grep -qx "Secure Boot is blocking the NVIDIA driver. A one-time setup fixes it."'
: > "$WORK/calls.log"; AP enroll-key; RC=$?
check E2 '[ "$RC" -eq 0 ] && calls_wait "^konsole -e ujust enroll-secure-boot-key$"'
secureboot 0
check E3 'grep -qx "NVIDIA${T}not-loaded" <<< "$(AP status)" && AP check | grep -qx "The NVIDIA graphics driver did not start."'
nvidia_loaded yes
check E4 'grep -qx "NVIDIA${T}ok" <<< "$(AP status)" && os aaa "" "$REF_PLAIN" && nvidia_loaded no && grep -qx "NVIDIA${T}ok" <<< "$(AP status)"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
