#!/usr/bin/env bash
# Tests for Plain-English Errors (Job 23), case D: Fix it does ONLY things from the checked list (each runs the
# right program, everything else is refused, nothing without --yes); Meta+Shift+E explains a newly copied error
# first, else the screen (the screenshot is deleted at once); What Went Wrong keeps 30 days with counts and fixes.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-errors-fix.sh <repo-root>
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
app brave-browser Brave

# D1: every kind of checked fix runs the right program
fresh
for f in askpc:restart-internet open:willitrun settings:kcm_clock showme:wifi reopen:brave-browser print-queue techguard:escape family-call; do
  ER fix "$f" --yes > /dev/null || echo "  $f failed"
done
for w in "forgeos-askpc fix restart-internet" "forgeos-willitrun-gui" "systemsettings kcm_clock" "forgeos-showme guide wifi" "kioclient exec $WORK/data/applications/brave-browser.desktop" "cancel -a" "forgeos-techguard escape" "forgeos-family-call"; do
  waitfor "^$w" || echo "  not run: $w"
done
check D1 '[ "$(calls | grep -vc "^systemd-run --user --scope --quiet -- ")" = 8 ] && [ "$(calls | grep -c "^systemd-run --user --scope --quiet -- ")" = 5 ]'
# D2: anything not on the list is refused (exit 3) and nothing runs; empty-trash deletes files so it is not on it
fresh
for f in open:nope askpc:empty-trash askpc:close-busy-app "rm -rf ~" reopen:nothere showme:nothere settings:kcm_nope open; do
  ER fix "$f" --yes > "$WORK/out" 2>&1; c=$?; [ "$c" = 3 ] && grep -q "not on the checked list" "$WORK/out" || echo "  not refused: $f ($c)"
done
check D2 '[ -z "$(calls)" ]'
# D3: no --yes = wrong use, nothing done
ER fix print-queue > /dev/null 2>&1; CODE=$?
check D3 '[ "$CODE" = 3 ] && [ -z "$(calls)" ]'
# D4: Meta+Shift+E with a newly copied error: that one is explained (and remembered so it is not used twice)
fresh; echo "The program can't start because MSVCP140.dll is missing from your computer." > "$WORK/say/clip"
screen "Printer HP stopped: Filter failed@100,100"
OUT="$(ER this)"; OUT2="$(ER this)"
check D4 'grep -q "^CARD${T}win-vcruntime${T}" <<< "$OUT" && grep -q "^CARD${T}print-filter-failed${T}" <<< "$OUT2" && grep -q "^spectacle -b -n -f -o" "$WORK/calls.log"'
# D5: the screenshot was deleted right after it was read
check D5 '[ -z "$(find "$WORK/run" -name "*.png")" ]'
# D6: copied words that are not an error -> the screen; nothing on the screen -> said honestly, exit 1
fresh; echo "grocery list: milk eggs" > "$WORK/say/clip"; screen "Welcome@100,100"
OUT="$(ER this)"; CODE=$?
check D6 '[ "$CODE" = 1 ] && grep -q "^I could not read an error there" <<< "$OUT" && grep -q "^tesseract" "$WORK/calls.log"'
# D7: What Went Wrong: newest first, counts, fixed marks; an error 31 days old is gone
fresh
FORGEOS_ERRORS_NOW=1797300000 ER explain "Segmentation fault (core dumped)" > /dev/null
FORGEOS_ERRORS_NOW=1799990000 ER explain "ERR_TOO_MANY_REDIRECTS" > /dev/null
ER explain "No space left on device" > /dev/null; ER explain "No space left on device" > /dev/null
ER fixed web-redirects; F=$?; ER fixed nothing-like-this; F2=$?
OUT="$(ER recent)"
check D7 '[ "$F$F2" = 01 ] && [ "$(cut -f2 <<< "$OUT" | tr "\n" " ")" = "disk-full web-redirects " ] && grep -q "${T}yellow${T}The drive is full (2 times)${T}-$" <<< "$OUT" && grep -q "${T}fixed$" <<< "$(grep web-redirects <<< "$OUT")"'
# D8: after a fix, the same error again is a new line (it came back), and the history file is only yours
ER explain "ERR_TOO_MANY_REDIRECTS" > /dev/null
check D8 '[ "$(ER recent | grep -c "${T}web-redirects${T}")" = 2 ] && [ "$(stat -c %a "$WORK/data/forgeos/errors")" = 700 ]'
# D9: nothing went wrong -> said plainly
fresh; OUT="$(ER recent 7)"
check D9 '[ "$OUT" = "Nothing went wrong in the last 7 days." ]'
# D10: Clear stuck print jobs clears only your own; a window that is not installed = said plainly, exit 1
fresh; ER fix print-queue --yes > /dev/null; A=$?; mv "$WORK/bin/forgeos-slow-gui" "$WORK/slow"
OUT="$(ER fix open:slow --yes)"; B=$?; mv "$WORK/slow" "$WORK/bin/forgeos-slow-gui"
check D10 '[ "$A$B" = 01 ] && grep -qx "cancel -a -u $(id -un)" "$WORK/calls.log" && [ "$OUT" = "That window could not be opened." ]'
# D11: a password copied from a password manager is never read (the screen is used instead)
fresh; echo "MSVCP140.dll is missing" > "$WORK/say/clip"; printf 'text/plain\nx-kde-passwordManagerHint\n' > "$WORK/say/cliptypes"
screen "Printer HP stopped: Filter failed@100,100"; OUT="$(ER this)"
check D11 'grep -q "^CARD${T}print-filter-failed${T}" <<< "$OUT" && ! grep -q "^wl-paste --no-newline" "$WORK/calls.log"'
# D12: copied words with "error" in them that no one knows -> the screen (the clipboard is used only for known ones)
fresh; echo "Sync error: the frobnicator stopped" > "$WORK/say/clip"; screen "Printer HP stopped: Filter failed@100,100"
OUT="$(ER this)"
check D12 'grep -q "^CARD${T}print-filter-failed${T}" <<< "$OUT" && grep -q "^tesseract" "$WORK/calls.log"'

echo
if [ "$failures" -eq 0 ]; then echo "All Plain-English Errors tests D passed."; else echo "$failures test(s) failed."; fi
exit "$((failures > 0))"
