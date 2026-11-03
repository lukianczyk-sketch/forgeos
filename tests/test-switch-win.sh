#!/usr/bin/env bash
# Tests for Install & Switch (Job 13e), cases D-F: the "Restart into ForgeOS" button on the Windows desktop -
# found and written (Windows line endings, only 2 files), taken off again, an already-open Windows drive,
# BitLocker / not fully shut down / no Windows refused, cancelled password; the Windows script itself
# (run with PowerShell when it is installed, with a fake bcdedit).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-switch-win.sh <repo-root>
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
W() { bash "$FORGEOS_SWITCH_WINSETUP" "$@"; }
CR=$'\r'  # a carriage return (Windows line endings)
D="$WORK/disks/sda3"; CMD="$D/Users/Public/Desktop/Restart into ForgeOS.cmd"; PS1="$D/Users/Public/Documents/ForgeOS/restart-into-forgeos.ps1"

# D: find + install + remove on a normal Windows drive (a data NTFS drive without Windows is skipped)
windows_disk sda2 nowin; windows_disk sda3
check D1 '[ "$(W find)" = "WINDOWS${T}/dev/sda3${T}no" ]'
OUT="$(W install)"; RC=$?
check D2 '[ "$RC" -eq 0 ] && [ "$OUT" = "INSTALLED${T}/dev/sda3" ] && [ -f "$CMD" ] && [ -f "$PS1" ] && [ ! -e "$WORK/disks/sda2/Users/Public/Desktop" ]'
check D3 '[ "$(grep -c "${CR}\$" "$CMD")" = "$(wc -l < "$CMD")" ] && [ "$(grep -c "${CR}\$" "$PS1")" = "$(wc -l < "$PS1")" ] && diff <(tr -d "\r" < "$PS1") "$FORGEOS_SWITCH_SRC/restart-into-forgeos.ps1" >/dev/null'
check D4 '[ "$(find "$D" -type f | wc -l)" = 2 ] && [ -z "$(ls -A "$WORK/mnt")" ] && grep -q "^mount -t ntfs3 -o rw,noatime /dev/sda3 " "$WORK/calls.log" && grep -q "^umount $WORK/mnt/sda3" "$WORK/calls.log"'
check D5 '[ "$(W find)" = "WINDOWS${T}/dev/sda3${T}yes" ] && [ "$(W remove)" = "REMOVED${T}/dev/sda3" ] && [ ! -e "$CMD" ] && [ ! -e "$D/Users/Public/Documents/ForgeOS" ]'
# a Windows drive the user already opened in the file manager is used where it is (not mounted again)
mkdir -p "$WORK/open"; rm -f "$WORK/lsblk.txt"; windows_disk sda2 nowin; echo "/dev/sdb1 ntfs $WORK/open" >> "$WORK/lsblk.txt"
mkdir -p "$WORK/open/Windows/System32" "$WORK/open/Users/Public"; : > "$WORK/calls.log"
check D6 '[ "$(W install)" = "INSTALLED${T}/dev/sdb1" ] && [ -f "$WORK/open/Users/Public/Desktop/Restart into ForgeOS.cmd" ] && ! grep -q "sdb1" <(grep "^mount" "$WORK/calls.log")'

# E: refused: BitLocker, not fully shut down (Fast Startup), no Windows at all, wrong use
rm -rf "$WORK/disks"/* "$WORK/open"; rm -f "$WORK/lsblk.txt"; windows_disk sda3 locked
OUT="$(W install 2>&1)"; RC=$?
check E1 '[ "$RC" -eq 5 ] && grep -q "locked with BitLocker" <<< "$OUT"'
rm -f "$WORK/lsblk.txt"; windows_disk sda3 dirty
OUT="$(W install 2>&1)"; RC=$?
check E2 '[ "$RC" -eq 4 ] && grep -q "not fully shut down" <<< "$OUT" && [ ! -e "$CMD" ] && [ -z "$(ls -A "$WORK/mnt")" ]'
rm -f "$WORK/lsblk.txt" "$WORK/dirty-sda3"
OUT="$(W install 2>&1)"; RC=$?; W bogus >/dev/null 2>&1; R3=$?
check E3 '[ "$RC" -eq 1 ] && [ "$OUT" = "No Windows drive was found on this PC." ] && [ "$R3" -eq 3 ]'

# F: the forgeos-switch command around it (remembers the button), a cancelled password, the Windows script
windows_disk sda3
OUT="$(SW windows-button)"
check F1 '[ "$OUT" = "Done. Windows now has a \"Restart into ForgeOS\" button on its desktop." ] && grep -qx "BUTTON${T}yes" <<< "$(SW status)"'
check F2 '[ "$(SW windows-button remove)" = "The \"Restart into ForgeOS\" button was taken off the Windows desktop." ] && grep -qx "BUTTON${T}no" <<< "$(SW status)"'
echo 126 > "$WORK/pk-rc"; OUT="$(SW windows-button)"; RC=$?; rm -f "$WORK/pk-rc"
check F3 '[ "$RC" -eq 1 ] && [ "$OUT" = "Cancelled - nothing was changed." ] && [ ! -e "$CMD" ]'
rm -f "$WORK/lsblk.txt"; windows_disk sda3 dirty; OUT="$(SW windows-button)"
check F4 'grep -q "^Windows was not fully shut down" <<< "$OUT"'
check F5 'grep -q "%PUBLIC%\\\\Documents\\\\ForgeOS\\\\restart-into-forgeos.ps1" "$FORGEOS_SWITCH_SRC/Restart into ForgeOS.cmd" && grep -q -- "-Verb RunAs" "$FORGEOS_SWITCH_SRC/Restart into ForgeOS.cmd"'
if command -v pwsh >/dev/null 2>&1; then
  OUT="$(bash "$ROOT/tests/switch-pwsh.sh" "$FORGEOS_SWITCH_SRC/restart-into-forgeos.ps1" "$WORK" 2>&1)"
  check F6 'grep -qx "SET {6a2b1c3d-1111-2222-3333-444455556666}" <<< "$OUT" && grep -qx "RESTART" <<< "$OUT" && grep -qx "NOTFOUND 1" <<< "$OUT"'
else
  echo "SKIP F6 (PowerShell is not installed; GitHub's Ubuntu runners have it)"
fi

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
