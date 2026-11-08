#!/usr/bin/env bash
# Tests for Digital Will (Job 18), cases J-K: the window - Step 1 (people, accounts, letter, note, password
# safe, folders), Step 2 (two-key lock, sign-in password check, USB stick, the codes shown once, code cards
# printed then deleted), Test my envelope, and Step 3 (the company checklist).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill-gui.sh <repo-root>
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
A() { printf '%s\n' "$@" > "$WORK/kd-answers"; }  # the answers, in order ("" = OK / Yes, rc1 = Cancel / No)
G() { : > "$WORK/shown"; bash "$GUI" "$@" > /dev/null 2>&1; }
shown() { cat "$WORK/shown"; }

# J1: first time - the menu says to start with Step 1; add a trusted person
fresh
A step1 people add Brianna 555-0101 back back close
G
check J1 'grep -q "Trusted people: <b>none yet - start with Step 1</b>" <<< "$(shown)" && grep -q "Emergency Envelope: <b>not made yet</b>" <<< "$(shown)" && grep -qx "PERSON${T}Brianna${T}555-0101" <<< "$(DW status)"'
# J2: tick two accounts and say what happens to each; J3: letter, note, password safe, folder
A step1 accounts tick 'bank\nemail' close "" give Brianna "Papers in the desk" back back close
G
check J2 'grep -qx "ACCOUNT${T}bank${T}Bank or credit union${T}give${T}Brianna${T}Papers in the desk" <<< "$(DW status)" && grep -qx "ACCOUNT${T}email${T}Email (Gmail, Outlook, Yahoo...)${T}close${T}-${T}-" <<< "$(DW status)" && grep -q "Never a password\|NEVER a password" <<< "$(shown)"'
A step1 letters Brianna 'Dear Brianna,\nThank you.' note "Simple service." safe pick "$H/Documents/Passwords.kdbx" folders add "$H/Pictures" back back close
G
OUT="$(DW status)"
check J3 '[ "$(DW letter-show Brianna)" = "$(printf "Dear Brianna,\nThank you.")" ] && grep -qx "NOTE${T}yes" <<< "$OUT" && grep -qx "SAFE${T}$H/Documents/Passwords.kdbx" <<< "$OUT" && grep -qx "FOLDER${T}$H/Pictures" <<< "$OUT"'

# K1: Step 2 with the two-key lock, a wrong sign-in password first, the USB stick; codes shown, cards deleted
DW person add Kasia > /dev/null
A "" Brianna "my lawyer" "wrong one" "" "right sign-in" "mp" "mp" "PIN 1234" "$STICK" "" "" "" rc1
G --make
HA="$(sed -n 's/.*Half A (for Brianna): <b><big>\([a-z ]*\)<.*/\1/p' "$WORK/shown")"
HB="$(sed -n 's/.*Half B (my lawyer): <b><big>\([a-z ]*\)<.*/\1/p' "$WORK/shown")"
check K1 '[ "$(wc -w <<< "$HA $HB")" = 10 ] && grep -q "That is not your sign-in password. Please type it again." <<< "$(shown)" && grep -q "ForgeOS does not keep this code." <<< "$(shown)" && ls "$BOX"/Emergency-Envelope-*.7z > /dev/null && ls "$STICK/ForgeOS Emergency Envelope/"Emergency-Envelope-*.7z > /dev/null'
check K2 '[ ! -e "$WORK/run/forgeos-digitalwill/code-cards.html" ] && grep -q "^xdg-open $WORK/run/forgeos-digitalwill/code-cards.html$" <<< "$(calls)" && grep -q "^xdg-open $BOX/Letter to my family.html$" <<< "$(calls)" && grep -q ", and on your USB stick." <<< "$(shown)"'
open_env "$(ls "$BOX"/Emergency-Envelope-*.7z)" "$HA $HB"
check K3 'grep -q "right sign-in" "$WORK/open/Open me first.html" && grep -q "<span class=\"code\">mp</span>" "$WORK/open/Open me first.html" && grep -q "PIN 1234" "$WORK/open/Open me first.html"'
# K4: Test my envelope (Half A, then Half B); a wrong half
A "$HA" "$HB" ""
G --test
check K4 'grep -q "Type <b>Half A</b> of the opening code" <<< "$(shown)" && grep -q "Your envelope opens with that code" <<< "$(shown)"'
A "$HB" "$HA" ""
G --test
check K5 'grep -q "The envelope did NOT open with that code." <<< "$(shown)"'
# K6: the main menu after - envelope made, Test my envelope offered; Step 3 checklist: open Google, mark done
A step3 google "" "" back close
G
check K6 'grep -q "Emergency Envelope: made $(date +%Y-%m-%d) (0 days ago)" <<< "$(shown)" && grep -q "test Test my envelope" <<< "$(shown)" && grep -q "^xdg-open https://myaccount.google.com/inactive$" <<< "$(calls)" && grep -q "google Done: Google" <<< "$(shown)" && grep -q "^google${T}.*${T}done${T}" <<< "$(DW legacy)"'
# K7: not ready -> says why; K8: one code card, no USB stick now -> only in Documents
fresh
A ""
G --make
check K7 'grep -q "Add at least one trusted person first." <<< "$(shown)"'
fresh; answers > /dev/null
A rc1 Brianna "" "" "" "" none "" "" "" rc1
G --make
check K8 '[ "$(ls "$BOX" | grep -c "^Emergency-Envelope-")" = 1 ] && [ ! -e "$STICK/ForgeOS Emergency Envelope" ] && grep -q "Who gets the code card" <<< "$(shown)"'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests J-K passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"
