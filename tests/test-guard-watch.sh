#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases E-H: the guard watching Downloads and the Desktop for real
# (inotify): a browser download (.crdownload renamed), a virus locked away + big warning, risky programs,
# folders made later, Download Guard off/on, low-memory mode checks a batch with one clamscan.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-watch.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_clamd; kill "$WPID" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
D="$HOME/Downloads"; WPID=""
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }
watch_start() { G watch --for "$1" > "$WORK/watch.out" 2>&1 & WPID=$!; sleep 1.5; }
watch_end() { wait "$WPID" 2>/dev/null; WPID=""; }
# wait_for FILE PATTERN [SECONDS]: wait until FILE has a line matching PATTERN
wait_for() { local i; for i in $(seq 1 $((${3:-40} * 4))); do grep -q -- "$2" "$1" 2>/dev/null && return 0; sleep 0.25; done; return 1; }
FAST=0; start_clamd && FAST=1

# E: a browser download: written as .crdownload (not checked), renamed when done -> virus locked away + big warning
echo "old file" > "$D/old.txt"; : > "$WORK/calls.log"
watch_start 25
virus "$D/Unconfirmed 1234.crdownload"; sleep 1.5
mv "$D/Unconfirmed 1234.crdownload" "$D/tax refund.pdf"
wait_for "$EV" "virus${T}download${T}$D/tax refund.pdf"
check E1 '[ ! -e "$D/tax refund.pdf" ] && grep -q "^$(date +%Y)-.*${T}virus${T}download${T}$D/tax refund.pdf${T}ForgeOS.Test.Eicar.UNOFFICIAL${T}2.*/tax refund.pdf${T}" "$EV" && grep -q "watching [0-9]* folders" "$WORK/watch.out"'
calls_wait "^notify-send .*Virus stopped"; calls_wait "^kdialog "
check E2 'grep -q "^kdialog --title Always-On Guard - virus stopped --sorry STOP - this download had a virus." "$WORK/calls.log" && grep -q "File: tax refund.pdf" "$WORK/calls.log" && grep -q "^notify-send .*--urgency=critical Virus stopped tax refund.pdf was locked away" "$WORK/calls.log" && ! grep -q "crdownload" "$EV"'
check E3 '[ "$FAST" = 0 ] || grep -q "^clamdscan .*--stream --no-summary $D/tax refund.pdf$" "$WORK/calls.log"'
# risky program on the Desktop; a hidden file; a clean file; a folder made later with a file in it
echo MZ > "$HOME/Desktop/Setup.exe"; echo x > "$D/.hidden"; echo "fine" > "$D/recipe.txt"
mkdir -p "$D/unzipped/inner"; virus "$D/unzipped/inner/game.dll"
wait_for "$EV" "virus${T}download${T}$D/unzipped/inner/game.dll"; wait_for "$EV" "risky${T}download${T}$HOME/Desktop/Setup.exe"
calls_wait "Be careful with this file Setup.exe"
check E4 'grep -q "${T}risky${T}download${T}$HOME/Desktop/Setup.exe${T}a Windows program or script (.exe)${T}" "$EV" && grep -q "Be careful with this file Setup.exe is a Windows program or script (.exe). Programs from emails and websites are the #1 way scammers get in." "$WORK/calls.log"'
check E5 '[ ! -e "$D/unzipped/inner/game.dll" ] && ! grep -q "hidden\|recipe.txt\|old.txt" "$EV" && [ -e "$D/recipe.txt" ]'
watch_end

# F: Download Guard OFF - a virus is left alone; turned back ON - the next one is caught
G off downloads >/dev/null; : > "$WORK/calls.log"
watch_start 12
virus "$D/off.zip"; sleep 4
G on downloads >/dev/null; virus "$D/on.zip"
wait_for "$EV" "virus${T}download${T}$D/on.zip" 15
check F1 '[ -e "$D/off.zip" ] && [ ! -e "$D/on.zip" ] && ! grep -q "off.zip" "$EV"'
watch_end; rm -f "$D/off.zip"

# G: low-memory mode (no always-ready checker): three files at once = ONE clamscan run
stop_clamd; : > "$WORK/calls.log"
watch_start 15
virus "$D/one.doc"; echo two > "$D/two.txt"; echo three > "$D/three.txt"
wait_for "$EV" "virus${T}download${T}$D/one.doc" 20; sleep 1
check G1 '[ "$(grep -c "^clamscan " "$WORK/calls.log")" = 1 ] && grep -q "^clamscan .* -- .*one.doc" "$WORK/calls.log" && grep -q "two.txt" <<< "$(grep "^clamscan " "$WORK/calls.log")" && ! grep -q "^clamdscan" "$WORK/calls.log"'
# H: too big to check -> noted (no pop-up); a file still being written is checked only once it stops growing
truncate -s 401M "$D/bigvideo.mkv"
( for i in 1 2 3; do echo "part $i" >> "$D/growing.txt"; sleep 0.6; done )
wait_for "$EV" "unchecked${T}download${T}$D/bigvideo.mkv" 15; sleep 2.5
check H1 'grep -q "${T}unchecked${T}download${T}$D/bigvideo.mkv${T}too big or the virus checker could not run" "$EV" && ! grep -q "bigvideo" <<< "$(grep "^notify-send\|^kdialog" "$WORK/calls.log")" && [ "$(grep -c "growing.txt" "$WORK/calls.log")" = 1 ]'
watch_end; rm -f "$D/bigvideo.mkv"

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
