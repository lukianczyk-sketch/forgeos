#!/usr/bin/env bash
# Tests for Family Mode (Job 13), cases E-G: when a step fails (kept and finished later),
# fonts sized in pixels, own pointer sizes, wrong use.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-family-more.sh <repo-root>
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
K="$WORK/kcfg"; SAVED="$WORK/state/forgeos/family/saved.json"; D="$HOME/Desktop"
key() { cat "$K/$1" 2>/dev/null; }
mode() { stat -c %a "$1"; }

F helper set --name Brianna --phone 661-555-0123 --rustdesk-id 987654321 --me Robert >/dev/null
mkdir -p "$K/kdeglobals/General"; echo "Inter,11,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" > "$K/kdeglobals/General/font"
BEFORE="$(snap)"

# E: a step fails - Plasma not answering (fonts still done); a write failing on the way off (kept, retried)
OUT="$(FAKE_NO_PLASMA=1 F on)"; RC=$?
check E1 '[ "$RC" -eq 1 ] && grep -q "^Problem: The taskbar could not be made taller (Plasma did not answer).$" <<< "$OUT" && [ "$(key kdeglobals/General/menuFont)" = "Noto Sans,14,-1,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(paste -sd, "$WORK/panels")" = "1:44,7:60" ]'
OUT="$(FAKE_KWRITE_FAIL=1 F off)"; RC=$?
check E2 '[ "$RC" -eq 1 ] && grep -q "^Problem: The words could not be set back" <<< "$OUT" && [ -e "$SAVED" ] && grep -q "^STATUS${T}off$" <<< "$(F status)"'
F off >/dev/null; RC=$?
check E3 '[ "$RC" -eq 0 ] && [ "$(snap)" = "$BEFORE" ] && [ ! -e "$SAVED" ]'

# F: a font sized in pixels; an own pointer size (smaller = 48, bigger stays); back exactly
echo "Hack,-1,16,5,400,0,0,0,0,0,0,0,0,0,0,1" > "$K/kdeglobals/General/font"
mkdir -p "$K/kcminputrc/Mouse"; echo 32 > "$K/kcminputrc/Mouse/cursorSize"
BEFORE2="$(snap)"
F on >/dev/null
check F1 '[ "$(key kdeglobals/General/font)" = "Hack,-1,22,5,400,0,0,0,0,0,0,0,0,0,0,1" ] && [ "$(key kcminputrc/Mouse/cursorSize)" = 48 ]'
F off >/dev/null; echo 72 > "$K/kcminputrc/Mouse/cursorSize"; F on --size bigger >/dev/null
check F2 '[ "$(key kcminputrc/Mouse/cursorSize)" = 72 ] && { F off >/dev/null; [ "$(key kcminputrc/Mouse/cursorSize)" = 72 ]; } && [ "$(F helper show | head -n 1)" = "name${T}Brianna" ]'
echo 32 > "$K/kcminputrc/Mouse/cursorSize"
check F3 '[ "$(snap)" = "$BEFORE2" ]'

# G: wrong use
codes=""
for a in "" "on --size huge" "on big" "size medium" "helper set --name" "helper set --colour red" "helper" "text" "call now" "nonsense"; do
  # shellcheck disable=SC2086  # split the test words on purpose
  F $a >/dev/null 2>&1; codes="$codes$?"
done
check G '[ "$codes" = 3333333333 ] && grep -q "^usage: forgeos-family on" <<< "$(F 2>&1)"'

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
