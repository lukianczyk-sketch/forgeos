#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases F-G: "Put my files back" from the Undo Button snapshot taken
# before the attack (renamed copies, files scrambled in place, a ransom note, files made after the snapshot,
# USB files), and what happens with no snapshot or someone else's incident.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-restore.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/tripwire-fakes.sh
. "$ROOT/tests/tripwire-fakes.sh"
val() { awk -F "$T" -v k="$1" '$1 == k {print $2; exit}' <<< "$OUT"; }
locked() { python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); from guardlib import quarantine; [print(e[2]) for e in quarantine.entries()]" "$FORGEOS_TW_GUARD_LIB"; }

# F: Robert's papers, an hourly snapshot, then new work, then an attack
fresh; rm -rf "$WORK/homes/.snapshots"
for i in $(seq 1 25); do letter "$H/Documents/letter $i.txt" "$i"; done
{ printf 'PK\003\004'; head -c 9000 /dev/urandom; } > "$H/Documents/Report.docx"; cp "$H/Documents/Report.docx" "$WORK/report-before"
{ printf '\xff\xd8\xff\xe0'; head -c 9000 /dev/urandom; } > "$H/Pictures/dog.jpg"; cp "$H/Pictures/dog.jpg" "$WORK/dog-before"
snap 5 2; sed -i 's/letter 3\./letter THREE./' "$H/Documents/letter 3.txt"; snap 6 1
letter "$H/Documents/new notes.txt" new
prog 4242 invoice.exe "$APP/app-wine-4242.scope" "$H/Downloads/invoice.exe"
noise "$H/Documents/Report.docx" 9000; write 0 4242 "$H/Documents/Report.docx"
noise "$H/Documents/new notes.txt" 5000; write 0.05 4242 "$H/Documents/new notes.txt"
letter "$H/Documents/HOW_TO_DECRYPT.txt" pay; write 0.06 4242 "$H/Documents/HOW_TO_DECRYPT.txt"
attack 4242 "$H/Documents" 3; replay >/dev/null; ID="$(inc)"
check F0 'calls | grep -qx "snapper -c root modify -c  -d Kept by Ransomware Tripwire: your files from before the attack 6"'
check F1 '[ "$(py "$ID" "len(i[\"files\"])")" = 6 ] && [ -f "$H/Documents/letter 4.txt" ] && [ ! -f "$H/Documents/letter 1.txt" ] && grep -q "ransom note" <<< "$(py "$ID" "i[\"reason\"]")"'
OUT="$(TW restore "$ID")"; RC=$?
check F2 '[ "$RC" -eq 0 ] && [ "$(val BACK)" = 4 ] && [ "$(val LOCKED)" = 6 ] && [ "$(val LOST)" = 1 ] && [ "$(val USB)" = 0 ] && grep -qx "LOSTFILE${T}$H/Documents/new notes.txt" <<< "$OUT"'
check F3 'for i in $(seq 1 3); do cmp -s "$H/Documents/letter $i.txt" "$WORK/homes/.snapshots/6/snapshot/robert/Documents/letter $i.txt" || exit 1; done; grep -q "letter THREE" "$H/Documents/letter 3.txt" && cmp -s "$H/Documents/Report.docx" "$WORK/report-before"'
check F4 '[ -z "$(ls "$H/Documents" | grep -E "\.locked$|HOW_TO_DECRYPT|new notes")" ] && [ "$(locked | grep -c "\.locked$")" = 3 ] && locked | grep -q "HOW_TO_DECRYPT.txt$" && locked | grep -q "Report.docx$"'
check F5 'cmp -s "$H/Pictures/dog.jpg" "$WORK/dog-before" && [ -f "$H/Documents/letter 25.txt" ] && [ "$(ls "$H/Documents" | grep -c "^letter .*\.txt$")" = 25 ]'
check F6 'grep -q "^INCIDENT${T}$ID${T}attack${T}frozen${T}.*${T}yes${T}" <<< "$(TW status)" && grep -q "Ransomware" "$WORK/data/forgeos/guard/quarantine/quarantine.log"'
OUT="$(TW restore "$ID")"
check F7 '[ "$(val BACK)" = 0 ] && [ "$(val LOCKED)" = 0 ] && [ "$(ls "$H/Documents" | grep -c "^letter .*\.txt$")" = 25 ]'

# G1: no snapshot from before the attack: nothing is changed
fresh; rm -rf "$WORK/homes/.snapshots" "$H/Documents/"*
for i in $(seq 1 22); do letter "$H/Documents/letter $i.txt" "$i"; done
prog 700 x.exe "$APP/app-wine-700.scope"; attack 700 "$H/Documents" 22; replay >/dev/null; ID="$(inc)"
OUT="$(TW restore "$ID")"; RC=$?
check G1 '[ "$RC" -eq 1 ] && grep -q "^NO-SNAPSHOT" <<< "$OUT" && [ "$(ls "$H/Documents" | grep -c "\.locked$")" = 22 ]'
# G2: files on a USB drive are listed as "can't come back"; G3: someone else's incident is refused
snap 1 1; fresh; mkdir -p "$WORK/media/robert/STICK"
for i in $(seq 1 21); do letter "$WORK/media/robert/STICK/letter $i.txt" "$i"; done
prog 701 y.exe "$APP/app-wine-701.scope"; attack 701 "$WORK/media/robert/STICK" 21; replay >/dev/null; ID="$(inc)"
OUT="$(TW restore "$ID")"
check G2 '[ "$(val USB)" = 20 ] && [ "$(val BACK)" = 0 ] && grep -q "^USBFILE${T}$WORK/media/robert/STICK/letter 1.txt.locked$" <<< "$OUT"'
FORGEOS_TW_UID=4321 TW restore "$ID" >/dev/null; R1=$?
check G3 '[ "$R1" -eq 3 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
