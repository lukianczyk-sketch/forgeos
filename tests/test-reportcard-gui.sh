#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), case L: the window with a pretend kdialog - the overall grade and each
# subject (letter + color, worst first), a button opens only ForgeOS's own tool, "Check now", the PDF copy,
# past report cards, text is escaped, a broken engine, wrong use.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard-gui.sh <repo-root>
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
export FORGEOS_CARD_ENGINE="$WORK/bin/forgeos-reportcard"
# kdialog answers from $WORK/kd-queue, one line each: "EXIT-CODE ANSWER" (no line left = Cancel). Every call is logged.
fake kdialog 'for a in "$@"; do printf "%s\n" "$a"; done >> "$WORK/kd-args"; echo "----" >> "$WORK/kd-args"
[ "$3" = --passivepopup ] && exit 0
line="$(head -n 1 "$WORK/kd-queue" 2>/dev/null)"; sed -i 1d "$WORK/kd-queue" 2>/dev/null
[ -n "$line" ] || exit 1; echo "${line#* }"; exit "${line%% *}"'
for t in guard tripwire techguard autopilot drivehealth undo privacy ghost digitalwill locate slow; do fake "forgeos-$t-gui" 'exit 0'; done
fake xdg-open 'exit 0'
win() { : > "$WORK/calls.log"; rm -f "$WORK/kd-args"; printf '%s\n' "$@" > "$WORK/kd-queue"; timeout 60 bash "$GUI" "${ARGS[@]}" >/dev/null 2>&1; echo $?; sleep 0.3; }
ARGS=()

# L1-L2: the card - overall in big letters, worst first with colors; the first button opens the guard window
healthy_pc; say forgeos-guard "SERVICE${T}stopped\nVIRUSLIST${T}$(day 1)\n"
RC="$(win "0 open1")"
check L1 '[ "$RC" = 0 ] && grep -q "^<span style=\"font-size:x-large; color:#2e7d32\"><b>Overall: A - Excellent</b></span><br>Do this first: Safety guards - Always-On Guard is stopped.<br><br><span style=\"color:#b26a00\"><b>C</b></span> &nbsp;<b>Safety guards</b> - Always-On Guard is stopped.<br>" "$WORK/kd-args"'
check L2 'grep -qx "Safety guards (C): Raise this grade" "$WORK/kd-args" && grep -qx "forgeos-guard-gui " "$WORK/calls.log" && [ "$(grep -c "^--menu$" "$WORK/kd-args")" = 2 ] && grep -q "<i>This is the first report card." "$WORK/kd-args"'

# L3: not checked yet - grey, "Check now" opens that tool; Passwords has no button; "space" opens Free up space
healthy_pc; say forgeos-drivehealth ""; export FORGEOS_CARD_SPACE="40000000000 1000000000000"
RC="$(win "0 open1" "0 open10")"
check L3 'grep -q "color:#757575\"><b>not checked</b></span> &nbsp;<b>Drive health</b>" "$WORK/kd-args" && grep -qx "Drive health (not checked): Check now" "$WORK/kd-args" && ! grep -q "^Passwords (" "$WORK/kd-args" && grep -qx "forgeos-slow-gui --space" "$WORK/calls.log" && grep -qx "forgeos-drivehealth-gui " "$WORK/calls.log"'

# L4: the PDF copy for a family helper - saved in Documents and opened
healthy_pc
RC="$(win "0 save" "0 ")"
check L4 'ls "$WORK/home/Documents"/PC-Report-Card-*.pdf >/dev/null && grep -q "^xdg-open $WORK/home/Documents/PC-Report-Card-.*\.pdf$" "$WORK/calls.log" && grep -q "^Saved in Documents as PC-Report-Card-.*\.pdf\.<br><br>It opens now" "$WORK/kd-args"'
# L5: past report cards
mkdir -p "$WORK/state/forgeos/reportcard"
echo '{"t": 0, "month": "2026-10", "grade": "B", "points": 84, "grades": {}, "names": {}}' > "$WORK/state/forgeos/reportcard/cards.jsonl"
RC="$(win "0 history" "0 ")"
check L5 'grep -qx "October 2026: B (84 points)<br>" "$WORK/kd-args"'

# L6: text from other tools can't put HTML into the window (< > removed, & escaped)
sweep red 1 "<b>Bad</b> & cam"
RC="$(win)"
check L6 'grep -q "The last sweep found something to check: b Bad /b &amp; cam." "$WORK/kd-args" && ! grep -q "<b>Bad</b>" "$WORK/kd-args"'
# L7: the engine is broken - the window says so instead of showing nothing
fake forgeos-reportcard 'exit 1'
RC="$(win)"
check L7 'grep -q "Overall: - - Not checked yet</b></span><br>The report card could not be made right now. Try again in a minute." "$WORK/kd-args"'
# L8: wrong use; L9: no kdialog = a clear message
check L8 'E="$(bash "$GUI" --bad 2>&1 >/dev/null)"; [ $? = 3 ] && [ "$E" = "usage: forgeos-reportcard-gui" ]'
rm "$WORK/bin/kdialog"
check L9 'command -v kdialog >/dev/null || { bash "$GUI" 2>&1 >/dev/null | grep -q "forgeos-reportcard report"; }'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests L passed."; else echo "$failures PC Report Card test(s) failed."; fi
exit "$((failures > 0))"
