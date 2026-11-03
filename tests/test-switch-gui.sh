#!/usr/bin/env bash
# Tests for Install & Switch (Job 13e), case G: the "Windows & ForgeOS" window (kdialog is faked: it answers
# menus and yes/no questions from $WORK/kd, one line per question, and keeps every text shown).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-switch-gui.sh <repo-root>
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
fake kdialog 'case "$3" in
  --msgbox|--sorry) printf "%s\n" "$4" >> "$WORK/shown"; exit 0 ;;
esac
a="$(head -n 1 "$WORK/kd" 2>/dev/null)"; sed -i 1d "$WORK/kd" 2>/dev/null
printf "%s\n" "$4" >> "$WORK/asked"
case "$a" in no|"") exit 1 ;; yes) exit 0 ;; *) echo "$a" ;; esac'
win() { : > "$WORK/calls.log"; : > "$WORK/shown"; : > "$WORK/asked"; rm -f "$WORK/bootnext"; printf '%s\n' "${@:2}" > "$WORK/kd"; bash "$GUI" "$1"; }
efi_list "0000 Windows Boot Manager" "0001 Fedora"; windows_disk sda3

# G: the desktop icon asks first (No = nothing happens); the main window; the Windows button; first run
win --windows no
check G1 'grep -q "^Restart into Windows now?" "$WORK/asked" && ! grep -q "efibootmgr -n" "$WORK/calls.log" && [ ! -s "$WORK/shown" ]'
win --windows yes
check G2 'grep -qx "efibootmgr -n 0000" "$WORK/calls.log" && grep -qx "Restarting into Windows. Next time you turn the PC on, ForgeOS starts again as usual." "$WORK/shown"'
win "" button yes
check G3 'grep -qx "Windows 11 and ForgeOS are both on this PC." "$WORK/asked" && grep -qx "Windows desktop button: not set up yet" "$WORK/asked" && grep -q "^Done. Windows now has" "$WORK/shown" && [ -f "$WORK/disks/sda3/Users/Public/Desktop/Restart into ForgeOS.cmd" ]'
win "" howto menu
check G4 'grep -qx "Windows desktop button: set up" "$WORK/asked" && grep -q "^Switching between Windows 11 and ForgeOS:" "$WORK/shown" && grep -q "^A terminal opens" "$WORK/shown" && calls_wait "^konsole -e ujust regenerate-grub$"'
win --first-run yes
check G5 'grep -q "^Welcome to ForgeOS!" "$WORK/asked" && grep -q "^Done. Windows now has" "$WORK/shown"'
efi_list "0001 Fedora"; win ""
check G6 'grep -q "^Windows was not found on this PC." "$WORK/shown" && [ ! -s "$WORK/asked" ]'
rmdir "$WORK/efi"; win ""
check G7 'grep -q "does not start with UEFI" "$WORK/shown"'
bash "$GUI" --nope 2>/dev/null; R1=$?; mv "$WORK/bin/kdialog" "$WORK/bin/kd-off"; PATH="$WORK/bin:/usr/bin:/bin" bash "$GUI" 2>/dev/null; R2=$?
check G8 '[ "$R1$R2" = 33 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
