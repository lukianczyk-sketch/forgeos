#!/usr/bin/env bash
# Tests for Show Me How (Job 22), cases I-J: Forge Helper (a "show me how" question, the "Show me" button on
# help answers, the showme action checked and started with no Yes needed - it only points) and the Show Me How
# window (pick a guide, type something else, --guide / --ask, no guides).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-gui.sh <repo-root>
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
HELPER="$ROOT/files/system/usr/bin/forgeos-helper"
FH() { python3 -B "$HELPER" "$@"; }
# forgeos-showme: "find" and "list" are the real thing; a walk is only written down
fake forgeos-showme 'case "$1" in find|list) exec python3 -B "'"$ENGINE"'" "$@" ;; esac; exit 0'
export FORGEOS_SHOWME_ENGINE="$WORK/bin/forgeos-showme"

# I1-I2: "show me how ..." goes to Show Me How: a guide when one fits, else the private AI on real words
OUT="$(FH ask --no-ai "show me how to print a letter")"
check I1 'grep -q "^TOOL${T}show_me${T}rules$" <<< "$OUT" && grep -qx "ACTION${T}showme${T}print${T}Show me on the screen" <<< "$OUT" && grep -q "^I can show you on the screen: Print something. A yellow arrow points at each thing to click. You do the clicking.$" <<< "$OUT"'
OUT="$(FH ask --no-ai "walk me through flying a kite")"
check I2 'grep -q "^TOOL${T}show_me${T}" <<< "$OUT" && grep -qx "ACTION${T}showme${T}ask:walk me through flying a kite${T}Try Show Me How" <<< "$OUT" && grep -q "^There is no built-in guide for that yet." <<< "$OUT"'
# I3: a help answer gets a "Show me" button only when there is a guide for that help card
OUT="$(FH ask --no-ai "how do I scan a document")"
OUT2="$(FH ask --no-ai "how do I zip a folder")"
check I3 'grep -q "^TOOL${T}help_answer" <<< "$OUT" && grep -qx "ACTION${T}showme${T}scan${T}Show me on the screen" <<< "$OUT" && grep -q "^TOOL${T}help_answer" <<< "$OUT2" && ! grep -q "showme" <<< "$OUT2"'
# I4: the showme action: a real guide or a short question starts the walk; anything else is refused
rm -f "$WORK/calls.log"
FH run showme scan --yes >/dev/null; C1=$?
FH run showme "ask:fly a kite" --yes >/dev/null; C2=$?
FH run showme ../../etc/passwd --yes >/dev/null; C3=$?
FH run showme nothing --yes >/dev/null; C4=$?
FH run showme "ask:x" --yes >/dev/null; C5=$?
sleep 1
check I4 '[ "$C1$C2$C3$C4$C5" = 00222 ] && grep -qx "forgeos-showme guide scan" "$WORK/calls.log" && grep -qx "forgeos-showme ask fly a kite" "$WORK/calls.log" && [ "$(grep -c "^forgeos-showme" "$WORK/calls.log")" = 2 ]'
# I5: the Forge Helper window starts Show Me How with no "Yes" question (pointing changes nothing)
check I5 'grep -q "^    open|open_file|showme) \"\$ENGINE\" run \"\$act\" \"\$arg\" --yes >/dev/null 2>&1; return ;;$" "$ROOT/files/system/usr/bin/forgeos-helper-gui"'

# J1: the window lists every guide (most used first) + "Something else"; picking one starts that walk
fake kdialog 'case "$*" in *--menu*) cat "$WORK/pick" ;; *--inputbox*) cat "$WORK/typed" ;; esac; exit "$(cat "$WORK/kdialog-code" 2>/dev/null || echo 0)"'
rm -f "$WORK/calls.log"; echo wifi > "$WORK/pick"
bash "$GUI"; CODE=$?
check J1 '[ "$CODE" = 0 ] && grep -q "^kdialog --title Show Me How --menu What should I show you?" "$WORK/calls.log" && grep -q "print Print something wifi Connect to Wi-Fi sound" "$WORK/calls.log" && grep -q "other Something else (type what you want to do)$" "$WORK/calls.log" && grep -qx "forgeos-showme guide wifi" "$WORK/calls.log"'
# J2: "Something else" -> type it -> Show Me How is asked; an empty answer does nothing
rm -f "$WORK/calls.log"; echo other > "$WORK/pick"; echo "change the mouse speed" > "$WORK/typed"
bash "$GUI"
echo "   " > "$WORK/typed"; bash "$GUI"
check J2 'grep -qx "forgeos-showme ask change the mouse speed" "$WORK/calls.log" && [ "$(grep -c "^forgeos-showme ask" "$WORK/calls.log")" = 1 ]'
# J3: --guide / --ask from Forge Helper or a desktop icon; Cancel = nothing; wrong use = 3
rm -f "$WORK/calls.log"
bash "$GUI" --guide scan; bash "$GUI" --ask "print a photo"
echo 1 > "$WORK/kdialog-code"; bash "$GUI"; CODE=$?; rm -f "$WORK/kdialog-code"
bash "$GUI" --guide 2>/dev/null; C2=$?; bash "$GUI" --nonsense 2>/dev/null; C3=$?
check J3 'grep -qx "forgeos-showme guide scan" "$WORK/calls.log" && grep -qx "forgeos-showme ask print a photo" "$WORK/calls.log" && [ "$CODE" = 0 ] && [ "$(grep -c "^forgeos-showme guide" "$WORK/calls.log")" = 1 ] && [ "$C2" = 3 ] && [ "$C3" = 3 ]'
# J4: no guides on this PC: it says so (Forge Helper instead) and exits 1
mkdir -p "$WORK/empty/guides"; rm -f "$WORK/calls.log"
FORGEOS_SHOWME_SHARE="$WORK/empty" bash "$GUI"; CODE=$?
check J4 '[ "$CODE" = 1 ] && grep -q "^kdialog --title Show Me How --msgbox Show Me How has no guides on this PC right now." "$WORK/calls.log"'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests I-J passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi
