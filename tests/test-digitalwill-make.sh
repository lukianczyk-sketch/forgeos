#!/usr/bin/env bash
# Tests for Digital Will (Job 18), cases D-E: making the Emergency Envelope with REAL 7-Zip - what is inside
# (and that it really is locked), the letter outside has no secrets, nothing unlocked is left on the drive,
# Test my envelope, the two-key lock, and a new envelope replaces the old one.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-make.sh <repo-root>
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
DAY="$(date +%Y-%m-%d)"; ENV1="$BOX/Emergency-Envelope-$DAY.7z"

# D: one code card, USB stick, no PC unlock
fresh; answers > /dev/null
OUT="$(secrets "right sign-in" "master pw" $'Phone passcode 1234\nBank PIN 9876' | DW make --holder Brianna --usb "$STICK")"; RC=$?
CODE="$(awk -F "$T" '$1 == "CODE" {print $2}' <<< "$OUT")"; CARDS="$(awk -F "$T" '$1 == "CARDS" {print $2}' <<< "$OUT")"
check D1 '[ "$RC" = 0 ] && [ "$(wc -w <<< "$CODE")" = 10 ] && grep -qx "ENVELOPE${T}$ENV1" <<< "$OUT" && grep -qx "ENVELOPE${T}$STICK/ForgeOS Emergency Envelope/Emergency-Envelope-$DAY.7z" <<< "$OUT" && [ "$(grep -c "^LETTER${T}" <<< "$OUT")" = 2 ] && [ "$(stat -c %a "$CARDS")" = 600 ] && tail -n 1 <<< "$OUT" | grep -qx "Your Emergency Envelope is made and tested."'
open_env "$ENV1" "$CODE"; IN="$(cat "$WORK/open/Open me first.html" 2>/dev/null)"
check D2 '[ "$(cd "$WORK/open" && find . -type f | sort | tr "\n" "|")" = "./Kept folders/Pictures/Trip/beach.jpg|./Letters/For Brianna.txt|./Open me first.html|./Password safe/Passwords.kdbx|" ] && cmp -s "$WORK/open/Password safe/Passwords.kdbx" "$H/Documents/Passwords.kdbx"'
check D3 'grep -q "with this password: <span class=\"code\">right sign-in</span>" <<< "$IN" && grep -q "Its master password: <span class=\"code\">master pw</span>" <<< "$IN" && grep -q "Bank PIN 9876" <<< "$IN" && grep -q "<td>Bank or credit union</td><td>Give it to Brianna</td><td>Papers in the desk</td>" <<< "$IN" && grep -q "Simple service, please." <<< "$IN" && grep -q "<h1>Robert L.s Emergency Envelope</h1>" <<< "$IN"'
check D4 '! printf "wrong words\n" | 7z l -- "$ENV1" > /dev/null 2>&1 && ! grep -q "Open me first" "$ENV1" && ! grep -aq "master pw" "$ENV1"'
LET="$(cat "$BOX/Letter to my family.html")"
check D5 'grep -q "Brianna has the opening code on a code card." <<< "$LET" && grep -q "7-zip.org" <<< "$LET" && grep -q "Emergency-Envelope-$DAY.7z" <<< "$LET" && ! grep -q "master pw\|right sign-in\|9876\|$CODE" <<< "$LET" && grep -q "This is not a legal will." <<< "$LET"'
check D6 '! grep -rlq "master pw" "$H" "$STICK" "$WORK/data" "$WORK/state" && [ "$(ls "$WORK/run/forgeos-digitalwill")" = code-cards.html ] && grep -q "$CODE" "$CARDS" && DW forget-cards && [ ! -e "$CARDS" ]'
OUT="$(DW status)"
check D7 'grep -qx "ENVELOPE${T}$DAY${T}0${T}Emergency-Envelope-$DAY.7z" <<< "$OUT" && [ "$(grep -c "^WHERE${T}" <<< "$OUT")" = 2 ] && grep -qx "HOLDER${T}Code card${T}Brianna" <<< "$OUT" && grep -qx "UNLOCKIN${T}no" <<< "$OUT" && [ "$(st "s[\"two\"]")" = False ]'

# E: Test my envelope; the two-key lock; a new envelope replaces the old one (the USB stick keeps the old one)
R1="$(printf ' %s ' "${CODE^^}" | tr " " "-" | DW test)"; RC1=$?; R2="$(printf 'acid acorn' | DW test)"; RC2=$?
check E1 '[ "$RC1" = 0 ] && [[ "$R1" == "Your envelope opens with that code and everything in it is readable"* ]] && [ "$RC2" = 1 ] && [[ "$R2" == "The envelope did NOT open with that code."* ]]'
OUT="$(secrets "" "" "" | DW make --two --holder Brianna --holder "my lawyer")"; RC=$?
A="$(awk -F "$T" '$2 == "A" {print $3}' <<< "$OUT")"; B="$(awk -F "$T" '$2 == "B" {print $3}' <<< "$OUT")"; ENV2="$BOX/Emergency-Envelope-$DAY-2.7z"
check E2 '[ "$RC" = 0 ] && [ "$(wc -w <<< "$A $B")" = 10 ] && [ -f "$ENV2" ] && [ ! -e "$ENV1" ] && [ -f "$STICK/ForgeOS Emergency Envelope/Emergency-Envelope-$DAY.7z" ] && [ "$(ls "$BOX" | tr "\n" "|")" = "Emergency-Envelope-$DAY-2.7z|Letter to my family.html|" ]'
open_env "$ENV2" "$A $B"; IN="$(cat "$WORK/open/Open me first.html" 2>/dev/null)"; LET="$(cat "$BOX/Letter to my family.html")"
check E3 'grep -q "I did not put the password here" <<< "$IN" && grep -q "(not written here)" <<< "$IN" && grep -q "<li>Half A: Brianna</li><li>Half B: my lawyer</li>" <<< "$LET" && grep -q "Type Half A, one space, then Half B." <<< "$LET"'
R3="$(printf '%s' "$A" | DW test)"; RC3=$?; printf '%s\n%s' "$A" "$B" | DW test > /dev/null; RC4=$?
check E4 '[ "$RC3" = 1 ] && [[ "$R3" == *"(Half A, one space, then Half B)." ]] && [ "$RC4" = 0 ] && [ "$(st "s[\"two\"]")" = True ] && grep -q "Half B - Robert L" "$WORK/run/forgeos-digitalwill/code-cards.html"'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests D-E passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"
