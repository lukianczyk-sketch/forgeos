#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case C: the watcher. Error pop-ups get "What does this mean?", others
# are never written down; repeats = a count; one pop-up per 10 minutes, none in games (serious ones always);
# crashes and hidden problems (log: yes only) are found; a click on the pop-up opens the card.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors-watch.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/errors-fakes.sh
. "$ROOT/tests/errors-fakes.sh"
items() { python3 -c "import json,sys; print(' '.join('%s:%d' % (e['key'], e['count']) for e in json.load(open(sys.argv[1]))))" "$HIST" 2>/dev/null; }
pops() { grep -c "^notify-send" "$WORK/calls.log" 2>/dev/null || true; }
settle() { sleep 1; }

# C1: busctl monitor's real layout (tests/errors-monitor-sample.txt): app, title with quotes, text over two lines
OUT="$(python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); from errlib import watch
print(watch.parse_monitor(open(sys.argv[2]).read().splitlines()))" "$FORGEOS_ERRORS_LIB" "$ROOT/tests/errors-monitor-sample.txt")"
check C1 '[ "$OUT" = "[('"'"'Printer Manager'"'"', '"'"'Printer \"HP\" stopped'"'"', '"'"'Filter failed.\nCheck the driver.'"'"')]" ]'
# C2: an error pop-up -> written down (only the words that matched) + our pop-up in its own process
fresh; ER notice "Printer Manager" "Printer HP stopped" "Filter failed for Mary's tax letter"; CODE=$?
waitfor notify-send
check C2 '[ "$CODE" = 0 ] && [ "$(items)" = "print-filter-failed:1" ] && ! grep -q "Mary" "$HIST" && grep -q "^notify-send -a ForgeOS Errors -i dialog-information -u normal --action=open=What does this mean? --wait The printer could not understand the print job" "$WORK/calls.log"'
# C3: a song, a chat message and ForgeOS's own pop-ups are never written down
ER notice "Elisa" "Now playing" "Pearl Jam - Alive"; A=$?; ER notice "Signal" "Mom" "See you at dinner"; B=$?
ER notice "ForgeOS Errors" "Printer stopped" "Filter failed"; C=$?; ER notice "Clean Sweep" "Scan failed" "Filter failed"; D=$?
check C3 '[ "$A$B$C$D" = 1111 ] && [ "$(items)" = "print-filter-failed:1" ]'
# C4: the same error again within a day = a count, no second pop-up
settle; ER notice "Printer Manager" "Printer HP stopped" "Filter failed"; settle
check C4 '[ "$(items)" = "print-filter-failed:2" ] && [ "$(pops)" = 1 ]'
# C5: 1 minute later: written down, no pop-up (10-minute gap); a serious one shows anyway
FORGEOS_ERRORS_NOW=1800000060 ER notice "Network Management" "Connection deactivated" "No secrets were provided"
FORGEOS_ERRORS_NOW=1800000090 ER notice "Disks & Devices" "Drive error" "I/O error, dev sdb, sector 1"; settle
check C5 '[ "$(items)" = "print-filter-failed:2 wifi-password:1 drive-io-error:1" ] && waitfor "Serious. Act now" && [ "$(pops)" = 2 ] && grep -q -- "-i dialog-warning -u critical" "$WORK/calls.log"'
# C6: in a game: written down, no pop-up; after the game pop-ups show again
touch "$WORK/gaming"; FORGEOS_ERRORS_NOW=1800000700 ER notice "Steam" "Update failed" "An error occurred while updating Halo (disk write error)"; settle
rm -f "$WORK/gaming"; FORGEOS_ERRORS_NOW=1800000710 ER notice "Bazaar" "Install failed" "Installation failed: error: Failed to install org.gimp.GIMP"
check C6 'grep -q "steam-disk-write:1" <<< "$(items)" && waitfor "The program did not install" && [ "$(pops)" = 3 ]'
# C7: an error pop-up no one knows is left alone (not written down, no pop-up); Steam's gamescope = a game
fresh; ER notice "Foo" "Sync failed" "The frobnicator could not sync"; A=$?; touch "$WORK/steam"
ER notice "Printer Manager" "Printer HP stopped" "Filter failed"; settle; rm -f "$WORK/steam"
check C7 '[ "$A" = 1 ] && [ "$(items)" = "print-filter-failed:1" ] && [ "$(pops)" = 0 ]'
# C8: crashes: yours only, one line per program, Open it again; 3 in a week = yellow
fresh; app brave-browser "Brave"
U="$(id -u)"; printf '[{"uid":%s,"exe":"/usr/bin/brave-browser"},{"uid":%s,"exe":"/usr/bin/brave-browser"},{"uid":64999,"exe":"/usr/sbin/sshd"}]' "$U" "$U" > "$WORK/say/coredumps"
ER tick; OUT="$(ER card app-crash/brave-browser)"
check C8 '[ "$(items)" = "app-crash/brave-browser:1" ] && grep -qx "Brave closed by itself" <<< "$OUT" && grep -qx "FIX${T}reopen:brave-browser${T}Open it again" <<< "$OUT" && grep -q -- "--since=@" "$WORK/calls.log"'
FORGEOS_ERRORS_NOW=1800090000 ER tick; FORGEOS_ERRORS_NOW=1800180000 ER tick
OUT="$(ER card app-crash/brave-browser)"
check C8b 'grep -qx "CARD${T}app-crash/brave-browser${T}yellow${T}Brave closed by itself" <<< "$OUT" && grep -q "It keeps closing (3 times this week)" <<< "$OUT"'
# C9: the system log: only errors marked log: yes; a 404 and noise are not
fresh
printf '%s\n' '{"MESSAGE":"cp: error writing x: No space left on device"}' '{"MESSAGE":"HTTP 404 not found"}' '{"MESSAGE":"kernel: random noise"}' '{"MESSAGE":[110,111,45,115,101,99,114,101,116,115]}' > "$WORK/say/journal"
ER tick
check C9 '[ "$(items)" = "disk-full:1 wifi-password:1" ] && grep -q "^journalctl -b -p warning -o json" "$WORK/calls.log"'
# C10: a click on the pop-up opens that error's card
fresh; echo open > "$WORK/say/click"; ER notice "Printer Manager" "Printer stopped" "Filter failed"
check C10 'waitfor "forgeos-errors-gui --card print-filter-failed"'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests C passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"
