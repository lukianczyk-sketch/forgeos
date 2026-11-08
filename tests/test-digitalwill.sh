#!/usr/bin/env bash
# Tests for Digital Will (Job 18), cases A-C: the answers (trusted people, accounts, password safe, folders,
# letters, note, company checklist), what is refused, and the status / report lines. No passwords are kept.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-digitalwill.sh <repo-root>
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
DRAFT="$WORK/data/forgeos/will/draft.json"

# A: nothing yet -> not ready, report says how to start (exit 1); answers are saved, only you can read them
fresh
OUT="$(DW status)"; REP="$(DW report)"; RC=$?
check A1 'grep -qx "PEOPLE${T}0${T}" <<< "$OUT" && grep -qx "READY${T}no${T}Add at least one trusted person first." <<< "$OUT" && grep -qx "ENVELOPE${T}-${T}-${T}-" <<< "$OUT" && [ "$RC" = 1 ] && grep -q "You have not set it up yet" <<< "$REP"'
answers > /dev/null
OUT="$(DW status)"
check A2 'grep -qx "PEOPLE${T}2${T}Brianna, Kasia" <<< "$OUT" && grep -qx "PERSON${T}Brianna${T}555-0101" <<< "$OUT" && grep -qx "PERSON${T}Kasia${T}-" <<< "$OUT" && grep -qx "READY${T}yes${T}" <<< "$OUT"'
check A3 'grep -qx "ACCOUNT${T}bank${T}Bank or credit union${T}give${T}Brianna${T}Papers in the desk" <<< "$OUT" && grep -qx "ACCOUNT${T}facebook${T}Facebook or Instagram${T}memorial${T}-${T}-" <<< "$OUT" && grep -qx "ACCOUNT${T}other-church-site${T}Church site${T}close${T}-${T}-" <<< "$OUT"'
check A4 'grep -qx "SAFE${T}$H/Documents/Passwords.kdbx" <<< "$OUT" && grep -qx "FOLDER${T}$H/Pictures" <<< "$OUT" && grep -qx "LETTER${T}Brianna" <<< "$OUT" && grep -qx "NOTE${T}yes" <<< "$OUT" && [ "$(stat -c %a "$DRAFT")" = 600 ] && [ "$(DW letter-show Brianna)" = "$(printf "Dear Brianna,\nThank you.")" ]'
check A5 'grep -qx "LEGACY${T}google${T}Google${T}https://myaccount.google.com/inactive${T}todo${T}.*" <<< "$OUT" && [ "$(grep -c "^LEGACY${T}" <<< "$OUT")" = 5 ] && grep -qx "UNLOCK${T}no-luks" <<< "$OUT"'

# B: what is refused (plain-English reasons, exit 3), and changes
B1="$(DW person add brianna)"; R1=$?; DW person add Third > /dev/null; B2="$(DW person add Fourth)"; R2=$?
check B1 '[ "$R1" = 3 ] && [ "$B1" = "brianna is already on your list." ] && [ "$R2" = 3 ] && [ "$B2" = "You can pick up to 3 trusted people." ]'
B3="$(DW account set bank give Nobody)"; B4="$(DW account set spaceship keep)"; B5="$(DW account set bank sell)"
check B2 '[ "$B3" = "Pick who gets it from your trusted people." ] && [ "$B4" = "That account is not on the list." ] && [[ "$B5" == "Pick what should happen: keep, close, give, memorial." ]]'
mkdir -p "$WORK/outside" "$H/.secret"; echo x > "$H/notes.txt"
B6="$(DW folders "$WORK/outside")"; B7="$(DW folders "$H/.secret")"; B8="$(DW safe "$H/notes.txt")"
check B3 '[[ "$B6" == *"is not a folder in your home folder." ]] && [ "$B7" = "Pick a normal folder, not a hidden one." ] && [[ "$B8" == "Pick your KeePassXC password safe file"* ]] && grep -qx "FOLDER${T}$H/Pictures" <<< "$(DW status)"'
DW person remove Brianna > /dev/null; DW account remove facebook > /dev/null; printf '' | DW letter Kasia > /dev/null; DW safe none > /dev/null; DW folders none > /dev/null
OUT="$(DW status)"
check B4 '! grep -q "^PERSON${T}Brianna" <<< "$OUT" && ! grep -q "^LETTER" <<< "$OUT" && ! grep -q "^ACCOUNT${T}facebook" <<< "$OUT" && grep -qx "SAFE${T}-" <<< "$OUT" && ! grep -q "^FOLDER" <<< "$OUT"'
DW legacy-done apple > /dev/null; DW legacy-done google > /dev/null; DW legacy-undo google > /dev/null; B9="$(DW legacy-done myspace)"
check B5 'grep -q "^apple${T}Apple${T}https://support.apple.com/102631${T}done${T}" <<< "$(DW legacy)" && grep -q "^google${T}.*${T}todo${T}" <<< "$(DW legacy)" && [ "$B9" = "That is not on the checklist." ]'
DW legacy-open facebook > /dev/null; RC1=$?; DW legacy-open bank > /dev/null; RC2=$?
check B6 '[ "$RC1" = 0 ] && grep -q "^xdg-open https://www.facebook.com/help/1568013990080948$" <<< "$(calls)" && [ "$RC2" = 3 ]'
check B7 'DW person add "  Bad${T}name  " > /dev/null && grep -q "^PERSON${T}Bad name${T}-$" <<< "$(DW status)" && DW nonsense 2>&1 >/dev/null | grep -q "^usage: forgeos-digitalwill"'

# C: the catalog, the word list, and the report
fresh; answers > /dev/null
CAT="$(DW catalog)"
check C1 '[ "$(grep -vc "${T}Other${T}" <<< "$CAT")" = 23 ] && grep -qx "bank${T}Bank or credit union${T}Money${T}on${T}give${T}Brianna" <<< "$CAT" && grep -qx "email${T}Email (Gmail, Outlook, Yahoo...)${T}Everyday${T}off${T}-${T}-" <<< "$CAT" && grep -qx "other-church-site${T}Church site${T}Other${T}on${T}close${T}-" <<< "$CAT"'
WL="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from willlib import words
c = words.opening_code(); k = words.unlock_code(); a, b = words.halves(c)
print(len(words.wordlist()), len(c.split()), len(k.split()), a + ' ' + b == c, words.tidy(' Acid-Acorn,  ACRE\nzoom. '))" "$FORGEOS_WILL_LIB")"
check C2 '[ "$WL" = "1295 10 8 True acid acorn acre zoom" ]'
REP="$(DW report)"; RC=$?
check C3 '[ "$RC" = 1 ] && grep -q "Trusted people: Brianna, Kasia." <<< "$REP" && grep -q "Accounts listed: 3. Letters written: 1. Folders to keep: 1." <<< "$REP" && grep -q "No Emergency Envelope made yet" <<< "$REP" && grep -q "Company checklist: still to do - Google, Apple" <<< "$REP"'

echo
if [ "$failures" -eq 0 ]; then echo "All Digital Will tests A-C passed."; else echo "$failures Digital Will test(s) failed."; fi
exit "$((failures > 0))"
