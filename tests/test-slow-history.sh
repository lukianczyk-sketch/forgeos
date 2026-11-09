#!/usr/bin/env bash
# Tests for Why Is It Slow? (Job 20), case K: the 5-minute samples (kept 7 days), "it was slow a few minutes
# ago", the 15-minute "still slow" note for Forge Helper (never during a game), the report's "Earlier" line,
# and the real /proc of this computer (a busy program is found by its real processor use, even on a busy runner).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-slow-history.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill "$BUSY" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/slow-fakes.sh
. "$ROOT/tests/slow-fakes.sh"
NOW="$(date +%s)"
at() { FORGEOS_SLOW_NOW=$((NOW + $1)) SL "${@:2}"; }

# K1-K3: a sample is one short line; samples older than 7 days are dropped; a broken line is skipped
app com.brave.Browser Brave
prog 7001 comm=brave cpu=40 rss=900 cgroup=/user.slice/app-flatpak-com.brave.Browser-1.scope
at -700000 sample; echo "not json" >> "$HIST"; at -3600 sample
check K1 '[ "$(wc -l < "$HIST")" = 1 ] && python3 -c "
import json, sys
x = [json.loads(l) for l in open(sys.argv[1])][-1]
assert sorted(x) == [\"big\", \"cpu\", \"free\", \"io\", \"mem\", \"t\", \"temp\", \"top\"] and x[\"top\"] == [\"Brave\", 40]
assert x[\"big\"] == [\"Brave\", 943718400] and x[\"free\"] == 62.5 and x[\"temp\"] == 55.0" "$HIST"'
check K2 '[ "$(wc -c < "$HIST")" -lt 400 ] && ! grep -q "not json" "$HIST"'
OUT="$(at 0 earlier 30)"
check K3 '[ "$OUT" = "Nothing was slowing the PC in the last 30 minutes." ]'

# K4-K6: memory got full 10 and 5 minutes ago, then it was fine: "earlier" still says what happened
mk mem "$WORK/proc" 8 0.2; mk pressure "$WORK/proc" memory 30.00 25.00 15.00
prog 7001 comm=brave cpu=40 rss=5200 cgroup=/user.slice/app-flatpak-com.brave.Browser-1.scope
at -600 sample; at -300 sample
cp "$HIST" "$WORK/h"; normal_pc; mkdir -p "${HIST%/*}"; mv "$WORK/h" "$HIST"; app com.brave.Browser Brave; at 0 sample
OUT="$(at 0 earlier 15)"
WHEN="$(date -d "@$((NOW - 300))" "+%I:%M %p" | sed "s/^0//" | tr "A-Z" "a-z")"
check K4 '[ "$OUT" = "At $WHEN the memory was nearly full (Brave was using 5.1 GB). It happened 2 times in the last 15 minutes." ]'
OUT="$(at 0 report --no-internet)"
check K5 'grep -qx "Earlier: At $WHEN the memory was nearly full (Brave was using 5.1 GB). It happened 2 times in the last 30 minutes." <<< "$OUT"'
OUT="$(at 0 quick)"; RC=$?
check K6 '[ "$RC" = 0 ] && [ -z "$OUT" ]'

# K7-K9: slow for the last 15 minutes for the same reason -> the note (not during a game; not mixed reasons)
rm -f "$HIST"; mk temp "$WORK/sys" coretemp 95
for s in -600 -300 0; do at "$s" sample; done
OUT="$(at 0 quick)"; RC=$?
check K7 '[ "$RC" = 1 ] && [ "$OUT" = "Your PC has been slow for 15 minutes because the PC was too hot (95 degrees C) and slowed itself down." ]'
touch "$WORK/game"; OUT="$(at 0 quick)"; RC=$?; rm -f "$WORK/game"
check K8 '[ "$RC" = 0 ] && [ -z "$OUT" ]'
mk temp "$WORK/sys" coretemp 50; mk pressure "$WORK/proc" io 50.00 50.00 20.00; at 1 sample
OUT="$(at 2 quick)"; RC=$?
check K9 '[ "$RC" = 0 ]'

# K10: the real /proc of this computer - a program that keeps the processor busy is found and named
ME="$(id -u)"
export FORGEOS_SLOW_PROC=/proc FORGEOS_SLOW_WAIT=1 FORGEOS_SLOW_UID="$ME"
python3 -B -c "
import sys
sys.argv[0] = 'slow-busy-test'
while True:
    pass" &
BUSY=$!
sleep 0.5
OUT="$(python3 -B -c "
import sys; sys.path.insert(0, sys.argv[1])
from slowlib import procs
a = next(x for x in procs.apps(procs.table()) if x['main'] == int(sys.argv[2]))
print(a['name'], a['app'], a['cpu'] >= 30, a['keep'], a['bad'])" "$FORGEOS_SLOW_LIB" "$BUSY")"
check K10 '[ "$OUT" = "Python3 python3 True False False" ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Why Is It Slow? tests K passed."; else echo "$failures Why Is It Slow? test(s) failed."; fi
exit "$((failures > 0))"
