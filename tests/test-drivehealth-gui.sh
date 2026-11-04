#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), case J: the Drive Health window (cards, Check now, Back up now with
# and without a backup set up, Pika Backup missing, What does this mean?) with a pretend kdialog.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/drivehealth-fakes.sh
. "$ROOT/tests/drivehealth-fakes.sh"
# kdialog answers from $WORK/kd-queue, one line each: "EXIT-CODE ANSWER" (no line left = Cancel).
# Every call is logged with its text, and --textbox files are copied to $WORK/textbox-N.
fake kdialog 'for a in "$@"; do printf "%s\n" "$a"; done >> "$WORK/kd-args"; echo "----" >> "$WORK/kd-args"
prev=""; for a in "$@"; do [ "$prev" = --textbox ] && cp "$a" "$WORK/textbox-$(ls "$WORK" | grep -c "^textbox-")"; prev="$a"; done
line="$(head -n 1 "$WORK/kd-queue" 2>/dev/null)"; sed -i 1d "$WORK/kd-queue" 2>/dev/null
[ -n "$line" ] || exit 1; echo "${line#* }"; exit "${line%% *}"'
fake flatpak '[ "$1" = info ] && exit "$(cat "$WORK/flatpak-rc" 2>/dev/null || echo 0)"; exit 0'
win() { : > "$WORK/calls.log"; rm -f "$WORK/kd-args" "$WORK"/textbox-*; printf '%s\n' "$@" > "$WORK/kd-queue"; timeout 60 bash "$GUI" "${ARGS[@]}" >/dev/null 2>&1; echo $?; }
ARGS=()

# J: cards for every drive, Check now, What does this mean?, Back up now (set up / not set up / no Pika), usage
normal_pc; drives "/dev/nvme0n1:1000204886016:nvme:0:Samsung SSD 990 PRO 1TB" "/dev/sda:4000787030016:sata:1:WDC WD40EZAX" \
  "/dev/sdc:5000981078016:usb:1:Backup Plus"
smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 hours=26300 temp=35 passed=0 exit=8
backup none; DH system-check >/dev/null
RC="$(win "0 explain")"
check J1 '[ "$RC" = 0 ] && grep -q "^GOOD   Samsung SSD 990 PRO 1TB$" "$WORK/kd-args" && grep -q "^       NVMe SSD, 1 TB, about 3% worn out, 2 years of use, 41 degrees C$" "$WORK/kd-args"'
check J2 'grep -q "^DANGER WDC WD40EZAX-22C8UB0 - back up your files today$" "$WORK/kd-args" && grep -q "^       ! The drive itself says it is failing\.$" "$WORK/kd-args" && grep -q "^?      Backup Plus - can.t read this drive.s health$" "$WORK/kd-args" && grep -q "^       USB drive, 5 TB, USB$" "$WORK/kd-args"'
check J3 'grep -q "^Backup: NOT set up yet - drives can die without warning.$" "$WORK/kd-args" && grep -q "^Honest limits: some drives die with no warning at all" "$WORK/textbox-0" && [ "$(grep -c "^--menu$" "$WORK/kd-args")" = 2 ]'
RC="$(win "0 check")"
check J4 '[ "$RC" = 0 ] && grep -q "^smartctl -j -a /dev/nvme0n1$" "$WORK/calls.log" && grep -q "^Checking your drives" "$WORK/kd-args"'
check J5 'grep -q "^Drive Health - last checked " "$WORK/textbox-0" && grep -q "^A drive may be failing. Back up your files today" "$WORK/textbox-0"'
ARGS=(--backup); RC="$(win "0 ")"
check J6 '[ "$RC" = 0 ] && grep -q "^Let.s make your first backup\." "$WORK/kd-args" && grep -q "^Never back up to the drive that may be failing.$" "$WORK/kd-args" && grep -qx "flatpak run org.gnome.World.PikaBackup" "$WORK/calls.log"'
RC="$(win "1 ")"
check J7 '[ "$RC" = 0 ] && ! grep -q "flatpak run" "$WORK/calls.log"'
backup set 2; RC="$(win "0 ")"
check J8 'grep -qx "flatpak run org.gnome.World.PikaBackup" "$WORK/calls.log" && grep -q "^Plug in your backup drive, then press \"Back Up Now\" in Pika Backup.$" "$WORK/kd-args" && ! grep -q "first backup" "$WORK/kd-args"'
echo 1 > "$WORK/flatpak-rc"; RC="$(win "0 ")"
check J9 '! grep -q "flatpak run" "$WORK/calls.log" && grep -q "^Pika Backup (the free backup app) is not installed" "$WORK/kd-args"'
rm -f "$WORK/flatpak-rc"; ARGS=(); RC="$(win)"
check J10 '[ "$RC" = 0 ] && grep -q "^Backup: last one 2 day(s) ago.$" "$WORK/kd-args"'
ARGS=(--nope); RC="$(win)"; ARGS=(--explain); RC2="$(win)"
check J11 '[ "$RC" = 3 ] && [ "$RC2" = 0 ] && [ -s "$WORK/textbox-0" ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
