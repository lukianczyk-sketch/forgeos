#!/usr/bin/env bash
# Tests for Find Anything (Job 11), cases A-H: reading every kind of file, keeping the list
# up to date, what is never searched, ranking, the simple search type, privacy, exit codes.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-find.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/find-fakes.sh
. "$ROOT/tests/find-fakes.sh"
top() { first "$(F search "$@")"; }

# A: an empty list says so; then every kind of file is read
F search milk >/dev/null; RC=$?
check A1 '[ "$RC" -eq 2 ]'
OUT="$(F index)"; RC=$?
check A2 '[ "$RC" -eq 0 ] && grep -q "Search list updated: 13 files read, 0 removed, 13 in the list." <<< "$OUT"'
check A3 '[ "$(top coffee)" = "$H/Documents/list.txt" ] && [ "$(top saturday)" = "$H/Documents/sale.html" ] && [ "$(top forecast)" = "$H/Documents/budget.docx" ]'
check A4 '[ "$(top tehachapi)" = "$H/Documents/miles.xlsx" ] && [ "$(top tomatoes)" = "$H/Documents/garden.pptx" ] && [ "$(top green chili)" = "$H/Documents/chili.odt" ]'
check A5 '[ "$(top 9921)" = "$H/Documents/statement.pdf" ] && [ "$(top walmart)" = "$H/Pictures/receipt.jpg" ] && [ "$(top holiday)" = "$H/Pictures/holiday.mp4" ]'
# A scanned PDF is read with OCR, both pages.
check A6 '[ "$(top lease agreement)" = "$H/Documents/scan-lease.pdf" ] && [ "$(top rent 1500)" = "$H/Documents/scan-lease.pdf" ] && grep -q "^pdftoppm -r 200 -png -l 3 $H/Documents/scan-lease.pdf " "$WORK/calls.log"'
# A tiny picture (an icon) is found by name only; HTML tags and &amp; are cleaned.
check A7 '! grep -q "^tesseract .*tiny-license-icon" "$WORK/calls.log" && [ "$(top icon)" = "$H/Pictures/tiny-license-icon.png" ] && F search more | grep -q "^   .*[[]more[]]"'
check A8 'F search sale | grep -q "Garage [[]sale[]] on Saturday" && ! F search sale | grep -q "<b>"'

# B: the next run reads only new and changed files, and forgets deleted ones
: > "$WORK/calls.log"
OUT="$(F index)"
check B1 'grep -q "0 files read, 0 removed, 13 in the list" <<< "$OUT" && ! grep -Eq "^(tesseract|pdftotext)" "$WORK/calls.log"'
echo "Shopping list: bread and butter please" > "$H/Documents/list.txt"
rm "$H/Pictures/holiday.mp4"
OUT="$(F index)"
check B2 'grep -q "1 files read, 1 removed, 12 in the list" <<< "$OUT" && [ "$(top butter)" = "$H/Documents/list.txt" ]'
F search coffee >/dev/null; RC1=$?
F search holiday >/dev/null; RC2=$?
check B3 '[ "$RC1" -eq 1 ] && [ "$RC2" -eq 1 ]'
OUT="$(F index --full --quiet)"
check B4 '[ -z "$OUT" ] && [ "$(top butter)" = "$H/Documents/list.txt" ] && F status | grep -q "Files in the search list: 12"'

# C: hidden folders, the skip list, node_modules, Games and links elsewhere are never searched
OUT="$(F search zebra)"; RC=$?
check C '[ "$RC" -eq 1 ] && ! grep -Eq "secret|skip.txt|mod.txt|game.txt|out.txt" <<< "$OUT"'

# D: a word in the file name beats the same word inside another file; several hits come back
echo "hello there" > "$H/Documents/invoice-4471.txt"
echo "the invoice from the plumber" > "$H/Documents/plumber.txt"
touch -d 2020-01-01 "$H/Documents/invoice-4471.txt"  # older, so only the name can put it first
F index --quiet
OUT="$(F search invoice)"
check D1 '[ "$(top invoice)" = "$H/Documents/invoice-4471.txt" ] && [ "$(grep -c "^RESULT" <<< "$OUT")" -eq 2 ] && grep -q "^Found 2:" <<< "$OUT"'
# All words first; if no file has them all, files with some of them.
check D2 '[ "$(top invoice plumber)" = "$H/Documents/plumber.txt" ] && [ "$(top plumber walrus)" = "$H/Documents/plumber.txt" ]'
check D3 'F search --limit 1 invoice | grep -c "^RESULT" | grep -qx 1'

# E: --kind keeps only that kind of file
echo "receipt for the new tires" > "$H/Documents/receipt.txt"
F index --quiet
OUT="$(F search --kind photo receipt)"
check E1 '[ "$(grep -c "^RESULT" <<< "$OUT")" -eq 1 ] && grep -q "^RESULT.$H/Pictures/receipt.jpg.photo." <<< "$OUT"'
OUT="$(F search --kind text receipt)"
check E2 '[ "$(grep -c "^RESULT" <<< "$OUT")" -eq 1 ] && grep -q "receipt.txt" <<< "$OUT"'

# F: without FTS5 (simple search type) the same files come out on top; the list is rebuilt
OUT="$(FORGEOS_FIND_NO_FTS=1 F status)"
check F1 'grep -q "Search type: simple" <<< "$OUT" && grep -q "Files in the search list: 0" <<< "$OUT"'
FORGEOS_FIND_NO_FTS=1 F index --quiet
check F2 '[ "$(FORGEOS_FIND_NO_FTS=1 top invoice)" = "$H/Documents/invoice-4471.txt" ] && [ "$(FORGEOS_FIND_NO_FTS=1 top walmart)" = "$H/Pictures/receipt.jpg" ]'
check F3 '[ "$(FORGEOS_FIND_NO_FTS=1 top plumber walrus)" = "$H/Documents/plumber.txt" ] && FORGEOS_FIND_NO_FTS=1 F search --kind photo receipt | grep -c "^RESULT" | grep -qx 1'
check F4 'FORGEOS_FIND_NO_FTS=1 F search lease | grep -q "[[]lease[]]" && F status | grep -q "Search type: fast (FTS5)"'
F index --quiet

# G: only this user can read the search list (an old list that others could read is fixed)
chmod 644 "$DB"; F status >/dev/null
check G '[ "$(stat -c %a "$DB")" = 600 ] && [ "$(stat -c %a "$(dirname "$DB")")" = 700 ] && [ "$(stat -c %a "$DB.lock")" = 600 ]'

# H: wrong use, and forget
F search --kind car x >/dev/null 2>&1; RC1=$?
F nonsense >/dev/null 2>&1; RC2=$?
F search >/dev/null 2>&1; RC3=$?
check H1 '[ "$RC1" -eq 3 ] && [ "$RC2" -eq 3 ] && [ "$RC3" -eq 3 ]'
OUT="$(F forget "$H/Pictures")"
check H2 'grep -q "Removed 3 files" <<< "$OUT" && grep -qx "$H/Pictures" "$WORK/cfg/forgeos/find-skip.txt"'
F index --quiet
F search walmart >/dev/null; RC=$?
check H3 '[ "$RC" -eq 1 ] && [ "$(grep -c Pictures "$WORK/cfg/forgeos/find-skip.txt")" -eq 1 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Find Anything tests (A-H) passed."; else echo "$failures Find Anything test(s) failed."; exit 1; fi
