#!/usr/bin/env bash
# Tests for Install & Switch (Job 13e), cases A-C: the start-up list helper (Windows found by name or by
# bootmgfw.efi, next start-up only), "Restart into Windows" (KDE restart, fallback message, no Windows,
# no UEFI), status lines and the once-only first run (desktop icon + welcome window).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-switch.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/switch-fakes.sh
. "$ROOT/tests/switch-fakes.sh"
B() { bash "$FORGEOS_SWITCH_BOOT" "$@"; }
NL=$'\n'  # a newline

# A: the start-up list helper
efi_list "0000 Windows Boot Manager" "0001 Fedora" "0002 UEFI OS"
OUT="$(B list)"
check A1 'grep -qx "0000${T}Windows Boot Manager" <<< "$OUT" && grep -qx "0001${T}Fedora" <<< "$OUT" && grep -qx "CURRENT${T}0001" <<< "$OUT" && ! grep -q "^NEXT" <<< "$OUT"'
OUT="$(B windows-next)"; RC=$?
check A2 '[ "$RC" -eq 0 ] && [ "$OUT" = "NEXT${T}0000" ] && grep -qx "efibootmgr -n 0000" "$WORK/calls.log" && grep -qx "NEXT${T}0000" <<< "$(B list)" && ! grep -q "efibootmgr -o" "$WORK/calls.log"'
check A3 '[ "$(B clear-next)" = CLEARED ] && ! grep -q "^NEXT" <<< "$(B list)"'
# an old efibootmgr with a different name: found by its bootmgfw.efi path
efi_list "0003 Windows" "0001 Fedora"; printf 'Boot0001* Fedora\tHD(1)/File(\\EFI\\fedora\\shimx64.efi)\nBoot0003* Windows\tHD(2)/File(\\EFI\\Microsoft\\Boot\\bootmgfw.efi)\n' > "$WORK/efi-v.txt"
check A4 '[ "$(B windows-next)" = "NEXT${T}0003" ]'
efi_list "0001 Fedora"; rm -f "$WORK/efi-v.txt"
OUT="$(B windows-next 2>&1)"; RC=$?
check A5 '[ "$RC" -eq 1 ] && [ "$OUT" = "Windows was not found in the start-up list." ]'
B bogus >/dev/null 2>&1; R1=$?
OUT="$(env -u FORGEOS_SWITCH_TEST bash "$FORGEOS_SWITCH_BOOT" list 2>&1)"
check A6 '[ "$R1" -eq 3 ] && { [ "$(id -u)" -eq 0 ] || grep -q "must run as root" <<< "$OUT"; }'

# B: Restart into Windows from ForgeOS
efi_list "0000 Windows Boot Manager" "0001 Fedora"; rm -f "$WORK/bootnext"; : > "$WORK/calls.log"
OUT="$(SW windows --yes)"; RC=$?
check B1 '[ "$RC" -eq 0 ] && [ "$OUT" = "Restarting into Windows. Next time you turn the PC on, ForgeOS starts again as usual." ] && grep -qx "efibootmgr -n 0000" "$WORK/calls.log" && grep -q "^busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logoutAndReboot" "$WORK/calls.log"'
echo 1 > "$WORK/busctl-rc"
check B2 '[ "$(SW windows --yes)" = "Windows is set for the next start-up. Save your work and restart from the menu." ]'
rm -f "$WORK/busctl-rc"; echo 1 > "$WORK/efi-rc"; : > "$WORK/calls.log"
OUT="$(SW windows --yes)"; RC=$?
check B3 '[ "$RC" -eq 1 ] && [ "$OUT" = "Could not set the next start-up to Windows. Nothing was changed." ] && ! grep -q busctl "$WORK/calls.log"'
rm -f "$WORK/efi-rc"; efi_list "0001 Fedora"
OUT="$(SW windows --yes)"; RC=$?
check B4 '[ "$RC" -eq 2 ] && [ "$OUT" = "Windows was not found on this PC." ]'
SW windows >/dev/null 2>&1; R1=$?; SW nope >/dev/null 2>&1; R2=$?
rmdir "$WORK/efi"; OUT="$(SW windows --yes)"; RC=$?
check B5 '[ "$R1$R2" = 33 ] && [ "$RC" -eq 2 ] && grep -q "does not start with UEFI" <<< "$OUT" && [ "$(SW status)" = "EFI${T}no${NL}WINDOWS${T}missing${T}-" ]'
mkdir -p "$WORK/efi"

# C: status lines and the once-only first run
rm -f "$WORK/bootnext"; efi_list "0000 Windows Boot Manager" "0001 Fedora"
OUT="$(SW status)"
check C1 'grep -qx "EFI${T}yes" <<< "$OUT" && grep -qx "WINDOWS${T}found${T}0000" <<< "$OUT" && grep -qx "NEXT${T}-" <<< "$OUT" && grep -qx "BUTTON${T}no" <<< "$OUT" && grep -qx "ICON${T}no" <<< "$OUT"'
: > "$WORK/calls.log"; SW first-run; RC=$?
check C2 '[ "$RC" -eq 0 ] && [ -x "$HOME/Desktop/forgeos-restart-windows.desktop" ] && grep -q "^X-ForgeOS-Switch=true" "$HOME/Desktop/forgeos-restart-windows.desktop" && calls_wait "^gui --first-run$" && grep -qx "ICON${T}yes" <<< "$(SW status)"'
: > "$WORK/calls.log"; rm -f "$HOME/Desktop/forgeos-restart-windows.desktop"; SW first-run
check C3 '[ ! -e "$HOME/Desktop/forgeos-restart-windows.desktop" ] && ! grep -q "^gui" "$WORK/calls.log"'
rm -rf "$WORK/state"; efi_list "0001 Fedora"; : > "$WORK/calls.log"; SW first-run
check C4 '[ ! -e "$HOME/Desktop/forgeos-restart-windows.desktop" ] && ! grep -q "^gui" "$WORK/calls.log" && [ -f "$WORK/state/forgeos/switch/first-run-done" ] && [ "$(stat -c %a "$WORK/state/forgeos/switch")" = 700 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
