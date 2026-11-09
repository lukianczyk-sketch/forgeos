#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case J1-J10: the fixes - close (only the same program, only the person's
# own, never a desktop part), power mode and switching it back, pause Find Anything, start-up off / on (undo).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-fix.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill "$P1" "$P2" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/slow-fakes.sh
. "$ROOT/tests/slow-fakes.sh"

# J1-J4: close - a real program of ours is closed; a changed, a gone and a desktop program are not
sleep 300 & P1=$!
sleep 301 & P2=$!
ME="$(id -u)"
export FORGEOS_SLOW_PROC=/proc FORGEOS_SLOW_UID="$ME"
OUT="$(SL fix close "$P1" sleep)"; RC=$?; sleep 0.3
check J1 '[ "$RC" = 0 ] && [ "$OUT" = "Sleep was asked to close." ] && ! kill -0 "$P1" 2>/dev/null'
OUT="$(SL fix close "$P2" firefox)"; RC=$?
check J2 '[ "$RC" = 1 ] && [ "$OUT" = "That program is not running any more, so nothing was closed." ] && kill -0 "$P2"'
OUT="$(FORGEOS_SLOW_UID=4242 SL fix close "$P2" sleep)"; RC=$?
check J3 '[ "$RC" = 1 ] && [ "$OUT" = "That program is part of the system, so it was not closed." ] && kill -0 "$P2"'
export FORGEOS_SLOW_PROC="$WORK/proc" FORGEOS_SLOW_UID=1000
OUT="$(SL fix close 999999 sleep)"; RC=$?
check J4 '[ "$RC" = 1 ] && grep -q "close 999999 sleep: That program is not running any more" "$LOGF"'

# J5-J6: power mode, and back to what it was
echo power-saver > "$WORK/power-mode"
OUT="$(SL fix power balanced)"
check J5 '[ "$OUT" = "Power mode is now Balanced." ] && [ "$(cat "$WORK/power-mode")" = balanced ] && grep -q "^powerprofilesctl set balanced$" "$WORK/calls.log"'
OUT="$(SL fix power undo)"
check J6 '[ "$OUT" = "Power mode is now Power Saver." ] && [ "$(cat "$WORK/power-mode")" = power-saver ] && [ "$(SL fix power turbo)" = "Unknown power mode." ]'

# J7: pause Find Anything (only Find Anything)
OUT="$(SL fix pause find)"
check J7 '[ "$OUT" = "Find Anything is paused. It carries on by itself later." ] && grep -qx "systemctl --user stop forgeos-find-index.service" "$WORK/calls.log" && [ "$(SL fix pause guard)" = "Only Find Anything can be paused here." ]'

# J8-J10: start-up off / on: a system entry gets the person's own Hidden copy (removed again), their own entry
# only loses Hidden=true; desktop parts can't be switched
printf '[Desktop Entry]\nType=Application\nName=Discord\nExec=discord\n' > "$WORK/xdg-autostart/discord.desktop"
mkdir -p "$WORK/config/autostart"; printf '[Desktop Entry]\nType=Application\nName=Steam\nExec=steam\n' > "$WORK/config/autostart/steam.desktop"
cp "$WORK/xdg-autostart/discord.desktop" "$WORK/xdg-autostart/org.kde.kalendarac.desktop"
SL fix startup-off discord >/dev/null; SL fix startup-off steam >/dev/null
check J8 'grep -qx "Hidden=true" "$WORK/config/autostart/discord.desktop" && grep -qx "X-ForgeOS-Slow=off" "$WORK/config/autostart/discord.desktop" && [ "$(sed -n 2p "$WORK/config/autostart/steam.desktop")" = "Hidden=true" ] && ! grep -q X-ForgeOS "$WORK/config/autostart/steam.desktop" && [ "$(SL startup | cut -f 4 | tr "\n" " ")" = "off off " ]'
OUT="$(SL fix startup-on discord)"; SL fix startup-on steam >/dev/null
check J9 '[ "$OUT" = "Discord will start with the PC again." ] && [ ! -e "$WORK/config/autostart/discord.desktop" ] && ! grep -q Hidden "$WORK/config/autostart/steam.desktop" && grep -qx "Name=Steam" "$WORK/config/autostart/steam.desktop"'
check J10 '[ "$(SL fix startup-off org.kde.kalendarac)" = "That program is not in the start-up list." ] && [ "$(SL fix startup-on steam)" = "That program already starts with the PC." ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests J1-J10 passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
