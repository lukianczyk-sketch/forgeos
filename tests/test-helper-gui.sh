#!/usr/bin/env bash
# Tests for the Forge Helper window (Job 13c), cases U-W: a fake kdialog clicks through it.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/helper-fakes.sh
. "$ROOT/tests/helper-fakes.sh"
# Fake kdialog: text boxes answer from $WORK/input, menus from $WORK/menu (one line each; none left =
# Cancel), Yes/No from $WORK/yes (one 0/1 per line; none left = 0 = yes). What it shows goes to $WORK/shown.
fake kdialog 'for a in "$@"; do case "$a" in
  --menu) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/menu" 2>/dev/null)"; sed -i 1d "$WORK/menu" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --inputbox) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/input" 2>/dev/null)"; sed -i 1d "$WORK/input" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --yesno|--warningyesno) printf "%s\n" "$@" >> "$WORK/shown"; l="$(head -n 1 "$WORK/yes" 2>/dev/null)"; sed -i 1d "$WORK/yes" 2>/dev/null; exit "${l:-0}" ;;
  --msgbox|--error|--sorry|--textbox) printf "%s\n" "$@" >> "$WORK/shown"; exit 0 ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
esac; done; exit 0'
fake dbus-send 'exit 0'
GUI="$ROOT/files/system/usr/bin/forgeos-helper-gui"
# reset: empty the click lists and logs. G: run the window.
reset() { : > "$WORK/calls.log"; : > "$WORK/shown"; rm -f "$WORK/input" "$WORK/menu" "$WORK/yes"; }
G() { timeout 60 bash "$GUI" "$@" >/dev/null 2>&1; }
fake forgeos-scamshield 'echo "RESULT: Looks like a scam"; exit 2'

# U: type a question -> the answer with its buttons; a change asks Yes first, then runs
reset
echo "my computer has no sound" > "$WORK/input"
printf '1\n' > "$WORK/menu"; echo 0 > "$WORK/yes"
G
check U1 'grep -q "^The sound is turned off." "$WORK/shown" && grep -qx "Fix it: Turn the sound on (unmute) and set the volume to half" "$WORK/shown" && grep -qx "Thumbs up - that helped" "$WORK/shown"'
check U2 'grep -q "^Fix it: Turn the sound on (unmute) and set the volume to half?" "$WORK/shown" && grep -qx "forgeos-askpc fix unmute-sound" "$WORK/calls.log"'
reset
echo "my computer has no sound" > "$WORK/input"
printf '1\n' > "$WORK/menu"; echo 1 > "$WORK/yes"
G
check U3 '! grep -q "forgeos-askpc fix " "$WORK/calls.log"'
# Opening a window needs no extra question.
reset
echo "who used my camera" > "$WORK/input"; printf '1\n' > "$WORK/menu"
G
sleep 0.3
check U4 'grep -qx "forgeos-privacy-gui " "$WORK/calls.log" && ! grep -q "Forge Helper will do this only" "$WORK/shown"'
reset
G --ask "panic"
check U5 'grep -qx "Panic now" "$WORK/shown" && ! grep -q forgeos-panic "$WORK/calls.log"'
reset; echo Brianna > "$WORK/family-helper"
printf '1\n' > "$WORK/menu"; echo 0 > "$WORK/yes"
G --ask "call my daughter for help"
sleep 0.3
check U6 'grep -q "^Call Brianna for help?" "$WORK/shown" && grep -qx "forgeos-family-call " "$WORK/calls.log"'

# V: thumbs down is saved with the tool and question; the "More..." menu
reset
printf 'where is the paper tray\n' > "$WORK/input"; printf 'down\n' > "$WORK/menu"
G
check V1 'grep -q "\"kind\": \"down\", \"tool\": \"find\", \"q\": \"where is the paper tray\"" "$WORK/data/forgeos/helper/feedback.jsonl" && grep -q "keep testing itself" "$WORK/shown"'
reset
F remember "I like big text" >/dev/null
printf ' \n' > "$WORK/input"; printf 'memory\n' > "$WORK/menu"
G
check V2 'grep -q "^- I like big text$" "$WORK/shown"'
reset
printf ' \n' > "$WORK/input"; printf 'copied\n' > "$WORK/menu"
G
check V3 'grep -qx "forgeos-scamshield check-clipboard" "$WORK/calls.log" && grep -q "RESULT: Looks like a scam" "$WORK/shown"'
reset
printf ' \n' > "$WORK/input"; printf 'forget\n' > "$WORK/menu"; echo 0 > "$WORK/yes"
G
check V4 '[ ! -e "$WORK/cfg/forgeos/helper/memory.json" ]'
reset
G --clipboard
check V5 'grep -qx "forgeos-scamshield check-clipboard" "$WORK/calls.log"'

# W: offers the quick brain ONCE (asks first); a better model suggestion too; nothing without Yes
start_fake_ollama
echo '{"models":[{"name":"gemma4:e4b"}]}' > "$WORK/ai-tags"
reset; echo 1 > "$WORK/yes"
G
check W1 'grep -q "small quick brain (~5GB download" "$WORK/shown" && ! grep -q "ollama pull" "$WORK/calls.log"'
reset
G
check W2 '! grep -q "quick brain" "$WORK/shown"'
mkdir -p "$WORK/state/forgeos"
echo '{"_suggest": [["gemma4:12b", "~8GB"]]}' > "$WORK/state/forgeos/helper-models.json"
reset; echo 0 > "$WORK/yes"
G
check W3 'grep -q "A better free AI brain is out: gemma4:12b (~8GB" "$WORK/shown" && grep -qx "ollama pull gemma4:12b" "$WORK/calls.log"'
mv "$WORK/bin/kdialog" "$WORK/kdialog.off"
OUT="$(PATH="$WORK/bin:/usr/bin:/bin" bash "$GUI" 2>&1)"; RC=$?
check W4 'command -v kdialog >/dev/null 2>&1 || { [ "$RC" -eq 3 ] && grep -q "kdialog is needed" <<< "$OUT"; }'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests U-W passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"
