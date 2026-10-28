#!/usr/bin/env bash
# Tests for Family Mode (Job 13), cases O-Q: the Family Mode window (helper setup, on, text size,
# guards, off) and the Call for help window (text or phone, only-click-Accept warning, end help).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/family-fakes.sh
. "$ROOT/tests/family-fakes.sh"
# kdialog: menus answer from $WORK/menu, Yes/No from $WORK/yes (none left = yes), typed answers from
# $WORK/input ("@cancel" = Cancel; none left = Cancel). What it shows is logged to $WORK/shown.
next() { l="$(head -n 1 "$WORK/$1" 2>/dev/null)"; sed -i 1d "$WORK/$1" 2>/dev/null; }
fake kdialog "$(declare -f next)"'
for a in "$@"; do case "$a" in
  --menu) printf "%s\n" "$@" >> "$WORK/shown"; l=""; next menu; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --yesno) printf "%s\n" "$@" >> "$WORK/shown"; l=""; next yes; exit "${l:-0}" ;;
  --inputbox) printf "%s\n" "$@" >> "$WORK/shown"; l="@cancel"; [ -s "$WORK/input" ] && next input; [ "$l" = "@cancel" ] && exit 1; echo "$l"; exit 0 ;;
  --textbox) for b in "$@"; do [ -f "$b" ] && cat "$b" >> "$WORK/shown"; done; exit 0 ;;
  --msgbox|--sorry) printf "%s\n" "$@" >> "$WORK/shown"; exit 0 ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
esac; done; exit 0'
S() { cat "$WORK/shown"; }

# O: window - no helper: set up (a wrong number first), Bigger, on; Big; guards; change helper (Cancel); off
printf '%s\n' toggle bigger size big guards helper toggle > "$WORK/menu"
printf '%s\n' 0 0 > "$WORK/yes"
printf '%s\n' Brianna "not a number" 987654321 Robert Brianna 661-555-0123 "" Robert "@cancel" > "$WORK/input"
bash "$GUI"; RC=$?
check O1 '[ "$RC" -eq 0 ] && [ ! -s "$WORK/menu" ] && [ ! -s "$WORK/input" ] && grep -q "Set up your helper first?" <<< "$(S)" && grep -q "mobile number doesn.t look right" <<< "$(S)" && grep -q "^Please try again.$" <<< "$(S)" && grep -q "^Your helper is Brianna.$" <<< "$(S)"'
check O2 'grep -q "^Family Mode is ON. Text size: Bigger.$" <<< "$(S)" && grep -q "^Text size is now Big.$" <<< "$(S)" && grep -q "^Text size: Big - change it$" <<< "$(S)" && grep -q "^My helper: Brianna - change$" <<< "$(S)" && grep -q "^  On: Virus checker (ClamAV)" <<< "$(S)"'
check O3 'grep -q "^Family Mode is OFF. Text, mouse pointer" <<< "$(S)" && grep -q "^Family Mode is OFF.$" <<< "$(S)" && [ "$(F helper show | sed -n 2p)" = "phone${T}6615550123" ] && grep -q "^STATUS${T}off$" <<< "$(F status)"'

# P: Call for help - text it (phone here), "Not yet" once, then done; then no phone: read it out loud
: > "$WORK/shown"; : > "$WORK/calls.log"; echo phone1 > "$WORK/devices"
printf '%s\n' 0 0 1 0 > "$WORK/yes"
bash "$CALL"; RC=$?
check P1 '[ "$RC" -eq 0 ] && grep -q "^Get help from Brianna now?" <<< "$(S)" && grep -q "^Send Brianna a text with this PC.s number?" <<< "$(S)" && grep -q "^Brianna got your number in a text." <<< "$(S)" && grep -q "^        123 456 789$" <<< "$(S)"'
check P2 'grep -q "Only click Accept while you are talking to Brianna. If anyone else asks to get into your computer, it is a scam - hang up." <<< "$(S)" && [ "$(grep -c "^Is Brianna finished helping you?" <<< "$(S)")" -eq 2 ] && grep -q "^The help is over. RustDesk is closed" <<< "$(S)" && grep -q "^kdeconnect-cli -d phone1 --send-sms" "$WORK/calls.log" && [ ! -s "$WORK/running" ]'
: > "$WORK/shown"; : > "$WORK/devices"; printf '%s\n' 0 0 > "$WORK/yes"
bash "$CALL"
check P3 'grep -q "^Call Brianna at 6615550123 and read this number out loud:" <<< "$(S)" && ! grep -q "Send Brianna a text" <<< "$(S)"'
# no internet: the reason is shown, RustDesk never opens; "Not now": nothing happens
: > "$WORK/shown"; : > "$WORK/calls.log"; printf '%s\n' 0 > "$WORK/yes"
FAKE_NET=none bash "$CALL"
printf '%s\n' 1 > "$WORK/yes"; bash "$CALL"
check P4 'grep -q "not on the internet" <<< "$(S)" && ! grep -q "^flatpak run" "$WORK/calls.log" && [ ! -s "$WORK/yes" ]'

# Q: no helper yet -> the helper questions first (Cancel = stop); no kdialog -> exit 3 for both windows
F helper clear >/dev/null; : > "$WORK/shown"; printf '%s\n' "@cancel" > "$WORK/input"
bash "$CALL"; RC=$?
mkdir -p "$WORK/nokd"; for t in bash env mktemp rm dirname; do ln -sf "$(command -v "$t")" "$WORK/nokd/$t"; done
PATH="$WORK/nokd" bash "$GUI" 2> "$WORK/err1"; R1=$?
PATH="$WORK/nokd" bash "$CALL" 2> "$WORK/err2"; R2=$?
check Q '[ "$RC" -eq 0 ] && grep -q "^Who helps you with the computer?" <<< "$(S)" && ! grep -q "Get help from" <<< "$(S)" && [ "$R1$R2" = 33 ] && grep -q "kdialog is needed" "$WORK/err1" && grep -q "kdialog is needed" "$WORK/err2"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
