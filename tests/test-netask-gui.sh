#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case E: the "Who Uses the Internet" window (pretend kdialog) on the
# real service, the question script's own words and answers, and "What is this?" with no private AI.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_service; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/netask-fakes.sh
. "$ROOT/tests/netask-fakes.sh" || exit 1
start_service || exit 1
export FORGEOS_NETASK_ENGINE="$WORK/bin/forgeos-netask"
MD5=0123456789abcdef0123456789abcdef
mkdir -p "$H/Apps"
proc 301 -- "$H/Apps/Chat"; real /usr/bin/kdeconnectd; proc 302 -- /usr/bin/kdeconnectd; proc 303 -- "$H/Apps/Bad"
echo 124 > "$WORK/say/codes"; answer "$(conn 301 "$H/Apps/Chat" $MD5 chat.example)" > /dev/null
answer "$(conn 302 /usr/bin/kdeconnectd $MD5)" > /dev/null
echo 1 > "$WORK/say/codes"; answer "$(conn 303 "$H/Apps/Bad" $MD5 bad.example)" > /dev/null
ping '{"events": [{"uid": '"$ME"', "path": "'"$H"'/Apps/Chat", "nano": 9}]}' > /dev/null
gui() { bash "$GUI"; }

# E1: the main list: Today, Something stopped working?, Lock down, YOUR apps with their answers, ForgeOS's own
#     programs in one line, Advanced view, the off switch; Today shows counts only
fresh; printf 'today\n' > "$WORK/say/picks"; gui; M="$(calls | grep -A1 -m1 -- "--menu The first time")"
check E1 'grep -q "today Today: which apps went online undo Something stopped working? (blocked in the last hour) lockon Lock down" <<< "$M" && grep -q "path:$H/Apps/Bad Bad - Blocked path:$H/Apps/Chat Chat - Asks each time ours ForgeOS programs and Steam: always allowed (1) advanced Advanced view (the details) off Turn Ask Before Connecting off" <<< "$M" && calls | grep -q -- "--msgbox Today (how many times each app went online - counts only, no web addresses):"'
# E2: pick an app -> Allow / Block / Ask me each time / What is this?; Block = done, no question
fresh; printf '%s\nblock\n' "path:$H/Apps/Chat" > "$WORK/say/picks"; gui
check E2 'calls | grep -q -- "--menu Chat: Asks each time now." && calls | grep -q "allow Allow - may always use the internet block Block - never ask Ask me each time what What is this?" && calls | grep -q -- "--passivepopup Chat is blocked from the internet." && [ "$(store "path:$H/Apps/Chat" answer)" = block ]'
# E3: Something stopped working? -> what was blocked in the last hour -> allow it (the PC asks Yes first)
fresh; printf 'undo\n%s\n' "path:$H/Apps/Bad" > "$WORK/say/picks"; printf '0\n0\n' > "$WORK/say/codes"; gui
check E3 'calls | grep -q -- "--menu Something stopped working? These were blocked in the last hour." && calls | grep -q "Bad (you blocked it, to bad.example)" && calls | grep -q -- "--yesno Allow Bad to use the internet from now on?" && calls | grep -q -- "--passivepopup Bad may use the internet now." && [ "$(store "path:$H/Apps/Bad" answer)" = allow ]'
# E4: Advanced view: the real files, answers and blocked addresses; Lock down from the window
fresh; printf 'advanced\nlockon\n' > "$WORK/say/picks"; gui
check E4 'grep -q "^Every program that tried to use the internet" "$WORK/textbox.txt" && grep -q "allow  system   KDE Connect\|allow  system   kdeconnectd" "$WORK/textbox.txt" && grep -q "Blocked in the last day" "$WORK/textbox.txt" && grep -q "bad.example" "$WORK/textbox.txt" && calls | grep -q -- "--passivepopup Lock down is on" && NA status | grep -qx "LOCKDOWN${T}on"'
# E5: the service is not running -> the window says so plainly
stop_service; fresh; gui; start_service
check E5 'calls | grep -q -- "--msgbox Ask Before Connecting is not running right now"'
# E6: the questions themselves (answers are the windows' exit codes; a killed window = no answer): Allow / Block / Just this once / no answer, red, remote, confirm, later
fresh; q() { python3 -B -c 'import sys; sys.path.insert(0, sys.argv[1]); from netlib import dialog; print(dialog.ask(int(sys.argv[2]), sys.argv[3:], 30))' "$FORGEOS_NETASK_LIB" "$ME" "$@"; }
echo 0 > "$WORK/say/codes"; R1="$(q normal App example.com app /x)"; echo 1 > "$WORK/say/codes"; R2="$(q normal App example.com app /x)"
printf '2\n0\n' > "$WORK/say/codes"; echo once > "$WORK/say/pick"; R3="$(q normal App example.com app /x)"
echo 124 > "$WORK/say/codes"; R4="$(q normal App example.com app /x)"
echo 2 > "$WORK/say/codes"; R5="$(q red App example.com "in your Downloads folder" /x)"
echo 1 > "$WORK/say/codes"; R6="$(q remote AnyDesk example.com AnyDesk /x)"
echo 0 > "$WORK/say/codes"; R7="$(q confirm "Allow it?")"
echo '"1" "3"' > "$WORK/say/check"; R8="$(q later 3 A B C)"
echo kill > "$WORK/say/codes"; R9="$(q normal App example.com app /x)"; R10="$(q bogus)"
check E6 '[ "$R1" = allow ] && [ "$R2" = block ] && [ "$R3" = once ] && [ -z "$R4" ] && [ "$R5" = block ] && waitfor_call "forgeos-cleansweep-gui" && [ "$R6" = allow ] && [ "$R7" = yes ] && [ "$R8" = "1,3" ] && [ -z "$R9" ] && [ -z "$R10" ]'
# E7: "What is this?" with no private AI: says so, never guesses, and the question comes back
fresh; printf '2\n0\n0\n' > "$WORK/say/codes"; echo what > "$WORK/say/pick"
R="$(q normal "Odd Tool" example.com app /x)"
X="$(NA explain "Odd Tool" /x)"; CX=$?
check E7 '[ "$R" = allow ] && calls | grep -q "forgeos-netask explain Odd Tool /x" && [ "$CX" = 1 ] && grep -q "^The private AI is not set up on this PC, so I can.t say what Odd Tool is." <<< "$X" && [ "$(calls | grep -c -- "--yesnocancel Odd Tool wants")" = 2 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests E passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
