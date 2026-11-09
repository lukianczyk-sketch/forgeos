#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case J11-J17: free up space (Trash, previews, unused apps, downloads only
# to the Trash), the internet, opening Clean Sweep, restart, wrong use and the log.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-space.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/slow-fakes.sh
. "$ROOT/tests/slow-fakes.sh"

# J11-J14: free up space
mkdir -p "$HOME/.local/share/Trash/files" "$HOME/.cache/thumbnails/large" "$HOME/Downloads/old"
head -c 3000 /dev/zero > "$HOME/.local/share/Trash/files/a"; head -c 2000 /dev/zero > "$HOME/.cache/thumbnails/large/t.png"
head -c 5000 /dev/zero > "$HOME/Downloads/old/big setup.iso"; touch -d "120 days ago" "$HOME/Downloads/old/big setup.iso"
head -c 5000 /dev/zero > "$HOME/Downloads/new.zip"; head -c 10 /dev/zero > "$HOME/Downloads/small.txt"; touch -d "120 days ago" "$HOME/Downloads/small.txt"
head -c 5000 /dev/zero > "$HOME/keep.iso"
OUT="$(FORGEOS_SLOW_BIG=4000 SL space)"
check J11 '[ "$OUT" = "TRASH${T}3000"$'"'"'\n'"'"'"THUMBS${T}2000"$'"'"'\n'"'"'"BIG${T}$HOME/Downloads/old/big setup.iso${T}5000${T}120" ]'
SL fix empty-trash >/dev/null; SL fix thumbs >/dev/null; SL fix unused-apps >/dev/null
check J12 '[ ! -e "$HOME/.local/share/Trash/files/a" ] && [ ! -e "$HOME/.cache/thumbnails" ] && grep -qx "flatpak uninstall --unused -y --noninteractive" "$WORK/calls.log"'
OUT="$(SL fix trash "$HOME/Downloads/old/big setup.iso")"
check J13 '[ "$OUT" = "big setup.iso is in the Trash (you can still get it back)." ] && [ -e "$WORK/trashed/big setup.iso" ]'
OUT="$(SL fix trash "$HOME/keep.iso")"; OUT2="$(SL fix trash "$HOME/Downloads/../keep.iso")"
check J14 '[ "$OUT" = "Only files in your Downloads folder can be moved to the Trash here." ] && [ "$OUT2" = "$OUT" ] && [ -e "$HOME/keep.iso" ]'

# J15-J17: internet, open windows, restart, wrong use, the log
OUT="$(SL fix internet)"; SL fix cleansweep >/dev/null; sleep 0.3
check J15 '[ "$OUT" = "The internet was restarted." ] && grep -qx "forgeos-askpc fix restart-internet" "$WORK/calls.log" && grep -qx "forgeos-cleansweep-gui " "$WORK/calls.log"'
SL fix restart >/dev/null
check J16 'grep -qx "busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logoutAndReboot" "$WORK/calls.log" && ! grep -q "^systemctl reboot" "$WORK/calls.log"'
SL fix rm -rf / >/dev/null; RC1=$?; SL fix close abc sleep >/dev/null; RC2=$?
check J17 '[ "$RC1" = 3 ] && [ "$RC2" = 3 ] && grep -q " emptied the Trash$" "$LOGF" && grep -q " moved to the Trash: $HOME/Downloads/old/big setup.iso$" "$LOGF" && grep -q " restart$" "$LOGF"'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests J11-J17 passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
