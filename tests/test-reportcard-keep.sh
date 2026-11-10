#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), cases J-K: the monthly report card (saved once a month, 12 months kept,
# a broken line skipped), "what changed since last month", Forge Helper speaks up once when the grade drops
# or a new F shows up (never during a game), past report cards, and the one-page PDF.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard-keep.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/card-fakes.sh
. "$ROOT/tests/card-fakes.sh"
CARDS="$WORK/state/forgeos/reportcard/cards.jsonl"
JUNE="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 6, 15, 12).timestamp()))')"
JULY="$(python3 -c 'import datetime; print(int(datetime.datetime(2026, 7, 15, 12).timestamp()))')"
at() { FORGEOS_CARD_NOW="$1" RC "${@:2}"; }
notes() { grep -c "^notify-send" "$WORK/calls.log" 2>/dev/null; }

# J1-J2: the first monthly card is saved (no note); a second run in the same month changes nothing
healthy_pc; : > "$WORK/calls.log"
at "$JUNE" monthly; at "$((JUNE + DAY))" monthly
check J1 '[ "$(wc -l < "$CARDS")" = 1 ] && grep -q "\"month\": \"2026-06\"" "$CARDS" && grep -q "\"grade\": \"A\"" "$CARDS" && [ "$(notes)" = 0 ]'
check J2 '[ "$(grep -c "^forgeos-guard status" "$WORK/calls.log")" = 1 ]'

# J3-J4: next month the backups got old and the drive is failing: what changed, and ONE note with what helps most
say forgeos-drivehealth "CHECKED${T}$((NOW - DAY))${T}danger\nDRIVE${T}sda${T}danger${T}WD Blue${T}hdd${T}2 TB\nBACKUP${T}set${T}40\n"
OUT="$(at "$JULY" check)"
check J3 'grep -qx "CHANGE${T}Since June: Drive health A to F (worse); Backups A to F (worse)." <<< "$OUT"'
say notify-send "later"; : > "$WORK/calls.log"
at "$JULY" monthly
check J4 '[ "$(notes)" = 1 ] && grep -q "^notify-send --app-name=Forge Helper .*--action=open=Show me .*Drive health and Backups got an F on this month.s PC Report Card. What would help most: Drive health - This drive may be failing: WD Blue. Back up today." "$WORK/calls.log" && [ "$(wc -l < "$CARDS")" = 2 ]'

# J5: a game is on - nothing is saved and nobody is interrupted (the next start-up catches up)
rm -f "$CARDS"; : > "$WORK/calls.log"
GAME=true at "$JUNE" monthly
check J5 '[ ! -e "$CARDS" ] && [ "$(notes)" = 0 ]'

# J6: 12 months are kept; a broken line is skipped; "Show me" opens the window
python3 -c "
import json, sys
for m in range(1, 13):
    print(json.dumps({'t': 0, 'month': '2025-%02d' % m, 'grade': 'A', 'points': 95, 'grades': {'drive': 'A'}, 'names': {}}))
print('not json'); print(json.dumps({'month': '2026-13', 'grades': {}}))" > "$CARDS"
fake forgeos-reportcard-gui 'exit 0'; say notify-send "open"
at "$JUNE" monthly; sleep 1
check J6 '[ "$(wc -l < "$CARDS")" = 12 ] && ! grep -q "2025-01\|not json\|2026-13" "$CARDS" && grep -q "2026-06" "$CARDS" && grep -q "^forgeos-reportcard-gui" "$WORK/calls.log"'

# K1: past report cards, newest first
OUT="$(RC history)"
check K1 '[ "$(sed -n 1p <<< "$OUT")" = "June 2026: C (79 points)" ] && [ "$(sed -n 2p <<< "$OUT")" = "December 2025: A (95 points)" ] && [ "$(wc -l <<< "$OUT")" = 12 ]'
# K2-K3: the PDF - a real one-page PDF in Documents with the grades in it; ( ) and \ in text can't break it
healthy_pc; say forgeos-locate "SETUP${T}no\n"; sweep yellow 3 'A camera (Wyze) on C:\\cams'

F="$(at "$JUNE" save)"
check K2 '[ "$F" = "$WORK/home/Documents/PC-Report-Card-2026-06-15.pdf" ] && head -c 8 "$F" | grep -q "^%PDF-1.4" && tail -c 6 "$F" | grep -q "%%EOF"'
if command -v pdftotext >/dev/null; then
  TXT="$(pdftotext "$F" - 2>/dev/null)"; PAGES="$(pdfinfo "$F" 2>/dev/null | awk "/^Pages:/ {print \$2}")"
  check K3 '[ "$PAGES" = 1 ] && grep -q "^PC Report Card$" <<< "$TXT" && grep -q "^Overall: A - Excellent$" <<< "$TXT" && grep -q "Find My PC is not set up" <<< "$TXT" && grep -qF "A camera (Wyze) on C:\\cams." <<< "$TXT" && grep -q "Nothing was sent anywhere" <<< "$TXT"'
else
  check K3 'grep -q "(Overall: A - Excellent) Tj" "$F"'
fi
# K4: a long card with curly quotes still fits on one page, with the footer
healthy_pc; sweep red 1 "$(printf 'A camera \xe2\x80\x9cWyze\xe2\x80\x9d %.0s- really long words here' {1..6})"
say forgeos-guard "SERVICE${T}stopped\nGUARD${T}websites${T}off${T}0${T}\nVIRUSLIST${T}$(day 30)\n"
F="$(RC save "$WORK/long.pdf")"
check K4 '! command -v pdftotext >/dev/null || { [ "$(pdfinfo "$F" | awk "/^Pages:/ {print \$2}")" = 1 ] && pdftotext "$F" - | grep -q "Nothing was sent anywhere" && pdftotext "$F" - | grep -q "“Wyze”"; }'
# K5: wrong use
check K5 'RC frobnicate 2>/dev/null; [ $? = 3 ] && RC check extra 2>/dev/null; [ $? = 3 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests J-K passed."; else echo "$failures PC Report Card test(s) failed."; fi
exit "$((failures > 0))"
