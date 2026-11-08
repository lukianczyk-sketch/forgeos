#!/usr/bin/env bash
# Tests for Digital Will (Job 18), cases E5-F: the sign-in password check (a wrong one makes nothing; a PC
# without the checker still works), and what is refused (exit 3, nothing made); the USB stick list.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/digitalwill-fakes.sh
. "$ROOT/tests/digitalwill-fakes.sh"
command -v 7z > /dev/null || { echo "FAIL 7z is needed (sudo apt-get install 7zip)"; exit 1; }
DAY="$(date +%Y-%m-%d)"

# E5-E6: the sign-in password is checked with the PC's own checker before anything is made
fresh; answers > /dev/null
secrets "" "" "" | DW make --holder Brianna > /dev/null
R5="$(secrets "wrong one" "" "" | DW make --holder Kasia)"; RC5=$?
check E5 '[ "$RC5" = 2 ] && [ "$R5" = "That is not your PC sign-in password. Nothing was made." ] && [ -f "$BOX/Emergency-Envelope-$DAY.7z" ] && [ "$(st "s[\"holders\"][0][1]")" = Brianna ]'
secrets "anything" "" "" | FORGEOS_WILL_CHKPWD="$WORK/no-such-checker" DW make --holder Kasia > /dev/null; RC6=$?
check E6 '[ "$RC6" = 0 ] && [ "$(st "s[\"holders\"][0][1]")" = Kasia ]'

# F: what is refused (exit 3, nothing made)
fresh
F1="$(secrets "" "" "" | DW make --holder Brianna)"; RC1=$?
answers > /dev/null
F2="$(secrets "" "" "" | DW make --holder Nobody)"; F3="$(secrets "" "" "" | DW make --two --holder Brianna --holder "")"
F4="$(secrets "" "" "" | DW make --holder Brianna --usb "$WORK/media/robert/GONE")"; F5="$(DW make --holder 2>/dev/null)"; RC5=$?
check F1 '[ "$RC1" = 3 ] && [ "$F1" = "Add at least one trusted person first." ] && [ "$F2" = "Pick which trusted person gets the code card." ] && [[ "$F3" == "Pick who gets Half A"* ]] && [ "$F4" = "That USB stick is not plugged in." ] && [ "$RC5" = 3 ] && [ ! -e "$BOX" ]'
F6="$(printf 'acid' | DW test)"; RC6=$?
check F2 '[ "$RC6" = 3 ] && [ "$F6" = "No Emergency Envelope found. Make one first." ] && FORGEOS_WILL_7Z=no-7z DW status | grep -qx "READY${T}no${T}7-Zip is missing."'
drives none
check F3 '[ -z "$(DW usb)" ] && drives stick && [ "$(DW usb | cut -f 1,2)" = "$STICK${T}STICK" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests E5-F passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"
