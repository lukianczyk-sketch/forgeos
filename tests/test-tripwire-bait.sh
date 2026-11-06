#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases E5-E8: a safety file deleted by hand (a quiet note) or by a
# scrambling program (frozen), USB drives, and the internet when it was already off.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-bait.sh <repo-root>
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

# E5: a safety file deleted while nobody was writing (probably by hand): a quiet note, no freezing, internet on
fresh; : > "$WORK/feed"; replay >/dev/null; rm "$H/Videos/000 Bank statements.pdf"; gone 0 "$H/Videos/000 Bank statements.pdf"
replay >/dev/null; ID="$(inc)"
check E5 '[ "$(py "$ID" "i[\"kind\"], i[\"state\"]")" = "bait done" ] && ! calls | grep -q "nmcli networking off" && [ -f "$H/Videos/000 Bank statements.pdf" ]'
# E6: a safety file deleted right after a program scrambled a few files: that program is frozen.
# The same right after Dolphin copied normal files (you deleting a whole folder by hand): only the quiet note.
fresh; : > "$WORK/feed"; replay >/dev/null; prog 603 wiper "$APP/app-wiper-603.scope"; prog 604 dolphin "$APP/app-dolphin-604.scope"
for i in 1 2 3 4; do noise "$H/Videos/v$i.dat"; write "0.$i" 603 "$H/Videos/v$i.dat"; done
rm "$H/Videos/000 Bank statements.pdf"; gone 1 "$H/Videos/000 Bank statements.pdf"; replay >/dev/null; ID="$(inc)"
check E6 '[ "$(py "$ID" "i[\"kind\"], i[\"program\"]")" = "attack wiper" ] && grep -q "deleted or renamed one of ForgeOS" <<< "$(py "$ID" "i[\"reason\"]")" && calls | grep -qx "nmcli networking off"'
fresh; : > "$WORK/feed"; replay >/dev/null
for i in $(seq 1 30); do letter "$H/Videos/v$i.txt" "$i"; write "0.$i" 604 "$H/Videos/v$i.txt"; done
rm "$H/Videos/000 Bank statements.pdf"; gone 4 "$H/Videos/000 Bank statements.pdf"; replay >/dev/null; ID="$(inc)"
check E6b '[ "$(py "$ID" "i[\"kind\"]")" = bait ] && ! calls | grep -q "nmcli networking off" && [ "$(cat "$WORK/cg$APP/app-dolphin-604.scope/cgroup.freeze")" = 0 ]'
# E7: a USB drive is watched too (the files on it can't be put back later)
fresh; prog 604 usb.exe "$APP/app-wine-604.scope"; mkdir -p "$WORK/media/robert/STICK/Photos"
for i in $(seq 1 22); do letter "$WORK/media/robert/STICK/Photos/letter $i.txt" "$i"; done
attack 604 "$WORK/media/robert/STICK/Photos" 22; replay >/dev/null; ID="$(inc)"
check E7 '[ "$(py "$ID" "i[\"kind\"]")" = attack ] && py "$ID" "i[\"files\"][0]" | grep -q "/media/robert/STICK/Photos/letter 1.txt.locked$"'
# E8: the internet was already off before: it stays off afterwards; a second program the same day is caught too
fresh; echo disabled > "$WORK/net-state"; prog 605 a.exe "$APP/app-wine-605.scope"; prog 606 b.exe "$APP/app-wine-606.scope"
for i in $(seq 1 44); do letter "$H/Documents/letter $i.txt" "$i"; done
attack 605 "$H/Documents" 22; replay >/dev/null
for i in $(seq 23 44); do f="$H/Documents/letter $i.txt"; noise "$f.locked"; rm -f "$f"; write "0.$i" 606 "$f.locked"; done; replay >/dev/null
check E8 '[ "$(cat "$WORK/run/net-cut")" = disabled ] && [ "$(py "$(inc 1)" "i[\"internet\"]") $(py "$(inc 2)" "i[\"internet\"]")" != "cut cut" ] && [ "$(ls "$WORK/var/incidents" | wc -l)" = 2 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
