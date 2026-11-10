#!/usr/bin/env bash
# Tests for Show Me How (Job 22), case D: a whole walk with no drawing (opens the right app, points, moves on
# by itself, done), can't see it (says so + the written steps), stops for a stranger on the screen and after
# 2 minutes with no progress, screenshots deleted at once.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-walk.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
PY() { python3 -B -c "import sys; sys.path.insert(0, '$FORGEOS_SHOWME_LIB'); $1"; }

# D1-D2: scan a paper: Skanpage opens, the arrow points at Scan, then at Save, then done (exit 0)
fresh; app org.kde.skanpage
screen 1 "Scan@100,100" "Settings@600,100"
screen 2 "Save@200,900" "Settings@600,100"
screen 3 "Settings@600,100"
OUT="$(SM guide scan --no-draw)"; CODE=$?
check D1 '[ "$CODE" = 0 ] && [ "$(grep -c "^VIEW${T}point" <<< "$OUT")" = 3 ] && grep -q "^VIEW${T}point${T}1/2${T}0.0521 0.0926 0.0187 0.0148${T}rb${T}Put the page on the scanner, then click Scan.$" <<< "$OUT" && grep -q "^VIEW${T}point${T}2/2${T}0.1042 0.8333 0.0187 0.0148${T}rt${T}Click Save" <<< "$OUT" && grep -q "^VIEW${T}end${T}2/2" <<< "$OUT" && grep -q "^END${T}done${T}All done!" <<< "$OUT"'
check D2 'grep -q "^gio launch $WORK/data/applications/org.kde.skanpage.desktop$" "$WORK/calls.log" && [ "$(wc -l < "$WORK/pictures")" = 5 ] && grep -q "^$WORK/run/forgeos-showme-$(id -u)/screen.png$" "$WORK/pictures" && [ ! -e "$WORK/run/forgeos-showme-$(id -u)/screen.png" ] && [ "$(stat -c %a "$WORK/run/forgeos-showme-$(id -u)")" = 700 ]'
# D3: the thing is not on the screen: it says so (never points at a guess) and shows the steps in writing
fresh; screen 0 "Settings@600,100"
OUT="$(SM guide scan --no-draw)"; CODE=$?
check D3 '[ "$CODE" = 1 ] && ! grep -q "^VIEW${T}point" <<< "$OUT" && grep -q "^VIEW${T}lost${T}1/2${T}- - - -${T}rb${T}I can.t see \"Scan\" on your screen.$" <<< "$OUT" && grep -q "^WRITTEN${T}1. Put the page on the scanner, then click Scan. / 2. Click Save" <<< "$OUT"'
# D4: someone can see this screen (Fake Tech Support Guard): it stops at once, nothing is read
fresh; screen 0 "Scan@100,100"
printf 'SERVICE\ton\nSHARING\tAnyDesk\n' > "$WORK/say/techguard"
OUT="$(SM guide scan --no-draw)"; CODE=$?
printf 'SERVICE\ton\nSHARING\t-\nALARM\t7\tpaused\t2026-11-09 10:00\tAnyDesk\n' > "$WORK/say/techguard"
OUT2="$(SM guide scan --no-draw)"; CODE2=$?
check D4 '[ "$CODE" = 1 ] && grep -q "^END${T}stranger${T}Show Me How stopped because someone else can see" <<< "$OUT" && [ "$CODE2" = 1 ] && grep -q "^END${T}stranger" <<< "$OUT2" && [ ! -e "$WORK/pictures" ]'
printf 'SERVICE\ton\nSHARING\t-\n' > "$WORK/say/techguard"
# D5: 2 minutes and nothing is clicked: it stops by itself
fresh; screen 0 "Scan@100,100"
OUT="$(SM guide scan --no-draw)"; CODE=$?
check D5 '[ "$CODE" = 1 ] && grep -q "^END${T}stuck${T}Show Me How stopped: nothing changed for 2 minutes." <<< "$OUT" && [ "$(grep -c "^VIEW" <<< "$OUT")" = 62 ]'
# D6: the screen can't be read (no screenshot): it keeps looking, never points, then says it can't see it
fresh; touch "$WORK/no-shot"; screen 0 "Scan@100,100"
OUT="$(FORGEOS_SHOWME_LOOKS=5 SM guide scan --no-draw)"; CODE=$?
rm -f "$WORK/no-shot"
check D6 '[ "$CODE" = 1 ] && ! grep -q "^VIEW${T}point" <<< "$OUT" && [ ! -e "$WORK/pictures" ]'
# D7: no screenshot tool / no Tesseract on this PC: it says it can't read the screen and gives the steps
fresh; rm -f "$WORK/bin/spectacle"
OUT="$(SM guide scan --no-draw)"; CODE=$?
check D7 '[ "$CODE" = 1 ] && grep -q "^Show Me How can.t read the screen on this PC. Here are the steps:" <<< "$OUT" && grep -q "^1. Put the page on the scanner" <<< "$OUT"'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests D passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi
