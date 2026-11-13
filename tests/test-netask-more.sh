#!/usr/bin/env bash
# Tests for Ask Before Connecting (Job 24), case C: games and away (asked after), Lock down,
# the window's requests: only YOUR apps; anything that lets more through is confirmed by a question the service shows.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-netask-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'stop_service; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/netask-fakes.sh
. "$ROOT/tests/netask-fakes.sh" || exit 1
start_service || exit 1
MD5=0123456789abcdef0123456789abcdef
mkdir -p "$H/Apps" "$H/Downloads"
rules() { find "$WORK/rules" -name '500-forgeos-netask-*.json' | wc -l; }

# C1: in a game: no question, blocked for now; after the game ONE list; the ticked one is allowed (rule written)
fresh; touch "$WORK/gaming"; proc 201 -- "$H/Apps/Game Helper"; proc 202 -- "$H/Apps/Chat"
A="$(answer "$(conn 201 "$H/Apps/Game Helper" $MD5)")"; B="$(answer "$(conn 202 "$H/Apps/Chat" $MD5)")"
N="$(calls | grep -c "^kdialog")"
echo 2 > "$WORK/say/check"; rm -f "$WORK/gaming"
for _ in $(seq 50); do [ "$(store "path:$H/Apps/Game Helper" later)" = False ] && break; sleep 0.2; done
check C1 '[ "$A" = "deny once forgeos-netask-once" ] && [ "$B" = "deny once forgeos-netask-once" ] && [ "$N" = 0 ] && calls | grep -q -- "--checklist While you were busy (a game or away), these 2 program(s) tried to use the internet." && calls | grep -q "1 Chat off 2 Game Helper off" && [ "$(store "path:$H/Apps/Game Helper" answer)" = allow ] && [ "$(store "path:$H/Apps/Chat" answer)" = ask ] && grep -q "\"data\": \"$H/Apps/Game Helper\"" "$WORK"/rules/500-forgeos-netask-*game-helper*.json'
# C2: away from the desk (no active desktop) = blocked for now and asked later, never a question into nowhere
fresh; touch "$WORK/away"; proc 203 -- "$H/Apps/Night"
A="$(answer "$(conn 203 "$H/Apps/Night" $MD5)")"
check C2 '[ "$A" = "deny once forgeos-netask-once" ] && ! calls | grep -q "^kdialog" && [ "$(store "path:$H/Apps/Night" later)" = True ]'
rm -f "$WORK/away"; echo none > "$WORK/say/check"; sleep 2.5
# C3: Lock down: every NEW program blocked without asking; allowed apps keep working; turning it off asks first
fresh; OUT="$(NA lockdown on)"; proc 204 -- "$H/Apps/New"
A="$(answer "$(conn 204 "$H/Apps/New" $MD5)")"; B="$(answer "$(conn 201 "$H/Apps/Game Helper" $MD5)")"
echo 1 > "$WORK/say/codes"; NA lockdown off > /dev/null; C="$(NA status)"
echo 0 > "$WORK/say/codes"; D="$(NA lockdown off)"; E="$(NA status)"
check C3 'grep -q "^Lock down is on" <<< "$OUT" && [ "$A" = "deny once forgeos-netask-once" ] && [ "${B% *}" = "allow always" ] && grep -qx "LOCKDOWN${T}on" <<< "$C" && grep -q "^Lock down is off" <<< "$D" && grep -qx "LOCKDOWN${T}off" <<< "$E" && calls | grep -q -- "--yesno Turn off Lock down? New programs will be asked again." && NA blocked 60 | grep -q "${T}New${T}example.com${T}lock down$"'
# C4: the list: only this person's apps, with their answers; why APP explains
fresh; OUT="$(NA list)"; W="$(NA why "game helper")"
check C4 'grep -qx "APP${T}path:$H/Apps/Game Helper${T}allow${T}app${T}Game Helper${T}-" <<< "$OUT" && grep -qx "APP${T}path:$H/Apps/Chat${T}ask${T}app${T}Chat${T}-" <<< "$OUT" && grep -qx "Game Helper: Allowed." <<< "$W"'
# C5: Block from the window: no question needed, the allow rule is replaced by a block rule
fresh; OUT="$(NA block "Game Helper")"
check C5 '[ "$OUT" = "Game Helper is blocked from the internet." ] && ! calls | grep -q kdialog && grep -q "\"action\": \"deny\"" "$WORK"/rules/500-forgeos-netask-*game-helper*.json && [ "$(grep -l "Game Helper" "$WORK"/rules/*.json | wc -l)" = 1 ]'
# C6: Allow from the window needs a Yes on the PC's own question; No = nothing changes
fresh; echo 1 > "$WORK/say/codes"; OUT="$(NA allow "Game Helper")"; C1=$?
echo 0 > "$WORK/say/codes"; OUT2="$(NA allow "Game Helper")"; C2=$?
check C6 '[ "$C1" = 1 ] && [ "$OUT" = "Nothing changed." ] && [ "$C2" = 0 ] && [ "$OUT2" = "Game Helper may use the internet now." ] && grep -q "\"action\": \"allow\"" "$WORK"/rules/500-forgeos-netask-*game-helper*.json && [ "$(calls | grep -c -- "--yesno Allow Game Helper to use the internet from now on?")" = 2 ]'
# C7: a program in Downloads can't be allowed for good, not even from the window (and its Block stays)
fresh; proc 205 -- "$H/Downloads/tool"; echo 0 > "$WORK/say/codes"; answer "$(conn 205 "$H/Downloads/tool" $MD5)" > /dev/null
R0="$(rules)"; OUT="$(NA allow tool)"; C1=$?; R1="$(rules)"
check C7 '[ "$C1" = 1 ] && grep -q "^tool is in your Downloads folder, so it can.t be allowed for good from here. Nothing changed.$" <<< "$OUT" && [ "$R1" = "$R0" ] && [ "$(store "path:$H/Downloads/tool" answer)" = block ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Ask Before Connecting tests C passed."; else echo "$failures test(s) failed."; cat "$WORK/service.log"; fi
exit "$((failures > 0))"
