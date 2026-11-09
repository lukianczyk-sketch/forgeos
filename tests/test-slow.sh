#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), cases A-E: a healthy PC, a busy program, full memory, a full or failing
# drive, heat and power saver.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow.sh <repo-root>
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

# A: a healthy PC - nothing found (exit 0); wrong use = exit 3
OUT="$(SL check)"; RC=$?
check A1 '[ "$RC" = 0 ] && ! grep -q "^PROBLEM" <<< "$OUT" && grep -qx "OK${T}memory${T}Memory: 10 GB free of 16 GB." <<< "$OUT" && grep -qx "OK${T}internet${T}Internet: fine (12 ms)." <<< "$OUT"'
OUT="$(SL report)"; RC=$?
check A2 '[ "$RC" = 0 ] && grep -qx "Your PC looks fine right now - nothing is slowing it down." <<< "$OUT" && grep -qx "Earlier: Nothing was slowing the PC in the last 30 minutes." <<< "$OUT"'
SL bogus >/dev/null 2>&1; RC1=$?; SL earlier 0 >/dev/null 2>&1; RC2=$?
check A3 '[ "$RC1" = 3 ] && [ "$RC2" = 3 ] && grep -q "^ping -n -c 3 -W 2 192.168.1.1$" "$WORK/calls.log" && grep -q "^ping -n -c 3 -W 2 9.9.9.9$" "$WORK/calls.log"'
OUT="$(SL check --no-internet)"
check A4 '! grep -q "internet" <<< "$OUT"'

# B: a busy program - friendly name, Close for your own program
app com.brave.Browser Brave
prog 2001 comm=brave cpu=150 rss=900 cgroup=/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.brave.Browser-12345.scope
prog 2002 comm=brave cpu=20 rss=300 cgroup=/user.slice/user-1000.slice/user@1000.service/app.slice/app-flatpak-com.brave.Browser-12345.scope
OUT="$(SL check)"; RC=$?
check B1 '[ "$RC" = 1 ] && [ "$(line busy)" = "PROBLEM${T}busy${T}yellow${T}Brave is using most of the computer'"'"'s power. Closing it makes the PC fast again (unsaved work in it may be lost).${T}close 2001 com.brave.Browser${T}Close Brave" ]'
mk pressure "$WORK/proc" cpu 55.00 30.00 0.00
OUT="$(SL check)"
check B2 'line busy | grep -q "${T}red${T}"'
normal_pc; prog 3001 comm=Game.exe cpu=180 rss=2000
OUT="$(SL check)"
check B3 'line busy | grep -q "Game.exe is using most of the computer.s power. That is normal while a game is running.${T}-${T}-$"'
normal_pc; prog 3002 comm=rpm-ostree uid=0 cpu=95
OUT="$(SL check)"
check B4 'line busy | grep -q "It is part of the system and usually finishes by itself.${T}-${T}-$" && line background | grep -q "ForgeOS is downloading or installing an update"'
normal_pc; prog 3003 comm=kwin_wayland cpu=120
OUT="$(SL check)"
check B5 '! grep -q "^PROBLEM${T}busy" <<< "$OUT"'

# C: memory nearly full - biggest app, browser tip, upgrade tip
normal_pc; mk mem "$WORK/proc" 8 0.3; mk pressure "$WORK/proc" memory 25.00 18.00 12.00
app com.brave.Browser Brave
prog 4001 comm=brave cpu=5 rss=3000 cgroup=/user.slice/app-flatpak-com.brave.Browser-1.scope
prog 4002 comm=brave cpu=5 rss=2200 cgroup=/user.slice/app-flatpak-com.brave.Browser-1.scope
prog 4003 comm=kate cpu=0 rss=200
OUT="$(SL check)"
check C1 'line memory | grep -q "^PROBLEM${T}memory${T}red${T}The memory is nearly full (307 MB free of 8 GB), so the PC has to wait. Brave is using 5.1 GB. Every open tab uses memory"'
check C2 'line memory | grep -q "This PC has 8 GB of memory; 16 GB would fix this for good.${T}close 4001 com.brave.Browser${T}Close Brave$"'
normal_pc; mk mem "$WORK/proc" 32 3; mk pressure "$WORK/proc" memory 5.00 12.00 0.00
OUT="$(SL check)"
check C3 'line memory | grep -q "${T}yellow${T}" && ! line memory | grep -q "16 GB would" && line memory | grep -q "${T}-${T}-$"'

# D: drive full, drive failing, waiting for the drive
normal_pc; export FORGEOS_SLOW_DF="$((500 * GB)) $((2 * GB))"
OUT="$(SL check)"
check D1 '[ "$(line disk)" = "PROBLEM${T}disk${T}red${T}Your drive is nearly full (2 GB free). A full drive makes everything slow.${T}space${T}Free up space" ]'
export FORGEOS_SLOW_DF="$((500 * GB)) $((40 * GB))"
OUT="$(SL check)"
check D2 'line disk | grep -q "${T}yellow${T}"'
normal_pc; printf 'CHECKED\t2026-11-08\tdanger\n' > "$WORK/dh-status"; echo 2 > "$WORK/dh-rc"
OUT="$(SL check)"
check D3 '[ "$(line drive)" = "PROBLEM${T}drive${T}red${T}A drive may be failing - back up your files today. A failing drive is often very slow.${T}drivehealth${T}Open Drive Health" ]'
normal_pc; mk pressure "$WORK/proc" io 40.00 45.00 10.00
OUT="$(SL check)"
check D4 'line drive | grep -q "^PROBLEM${T}drive${T}yellow${T}The PC keeps waiting for the drive"'

# E: too hot, power saver on battery
normal_pc; mk temp "$WORK/sys" coretemp 96; mk freq "$WORK/sys" 1200 4000
OUT="$(SL check)"
check E1 '[ "$(line heat)" = "PROBLEM${T}heat${T}red${T}Your PC is hot (96 degrees C) and slowed itself down to cool off. Check the vents for dust and keep it on a hard, flat surface (not a bed or a lap). No button can fix heat.${T}-${T}-" ]'
mk temp "$WORK/sys" coretemp 91; mk freq "$WORK/sys" 3900 4000
OUT="$(SL check)"
check E2 'line heat | grep -q "${T}yellow${T}Your PC is hot (91 degrees C). Check"'
normal_pc; echo power-saver > "$WORK/power-mode"
mkdir -p "$WORK/sys/class/power_supply/AC"; echo Mains > "$WORK/sys/class/power_supply/AC/type"; echo 0 > "$WORK/sys/class/power_supply/AC/online"
OUT="$(SL check)"
check E3 '[ "$(line power)" = "PROBLEM${T}power${T}yellow${T}Power saver mode is on, which slows the PC down to save power. It is running on battery.${T}power balanced${T}Switch to Balanced" ]'
OUT="$(SL report)"; RC=$?
check E4 '[ "$RC" = 1 ] && grep -qx "Why Is It Slow? found 1 thing slowing your PC:" <<< "$OUT" && grep -qx "   Fix: \"Switch to Balanced\" in the Why Is It Slow? window." <<< "$OUT"'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests A-E passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
