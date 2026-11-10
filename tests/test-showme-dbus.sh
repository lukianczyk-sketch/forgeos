#!/usr/bin/env bash
# Tests for Show Me How (Job 22), case H: the real D-Bus link the KWin overlay reads (a private session bus on
# this runner): where to point, the step panel (Next / Back / Stop), one walk at a time, Stop, and a stop when a
# stranger can see the screen. KWin itself is a pretend busctl. Needs dbus-run-session, python3-dbus, python3-gi.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-showme-dbus.sh <repo-root>
set -u
if [ -z "${SHOWME_ON_BUS:-}" ]; then
  command -v dbus-run-session >/dev/null 2>&1 || { echo "FAIL H0 dbus-run-session is needed"; exit 1; }
  SHOWME_ON_BUS=1 exec dbus-run-session -- bash "$0" "$@"
fi
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill $(jobs -p) 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/showme-fakes.sh
. "$ROOT/tests/showme-fakes.sh"
python3 -c "import dbus, gi" 2>/dev/null || { echo "FAIL H0 python3-dbus and python3-gi are needed"; exit 1; }
unset FORGEOS_SHOWME_FAST
# the step panel waits until the test answers it ($WORK/panel = the button: 0 Next, 1 Back, 2 Stop)
fake kdialog 'case "$*" in *--yesnocancel*) while [ ! -e "$WORK/panel" ]; do sleep 0.2; done; c="$(cat "$WORK/panel")"; rm -f "$WORK/panel"; exit "$c" ;; esac; exit 0'
STATE() { python3 -c "import dbus; print(dbus.SessionBus().get_object('org.forgeos.ShowMe', '/ShowMe').State('$1', dbus_interface='org.forgeos.ShowMe'))" 2>/dev/null; }
STOP() { python3 -c "import dbus; dbus.SessionBus().get_object('org.forgeos.ShowMe', '/ShowMe').Stop(dbus_interface='org.forgeos.ShowMe')" 2>/dev/null; }
wait_for() { for _ in $(seq 75); do eval "$1" && return 0; sleep 0.2; done; return 1; }

# H1-H2: a walk with the arrow: KWin loads our one overlay file; the overlay asks where to point; the panel
fresh; app org.kde.skanpage; screen 0 "Scan@100,100"
SM guide scan > "$WORK/out1" 2>&1 & P1=$!
wait_for 'grep -q "Step 1 of 2" "$WORK/calls.log" 2>/dev/null'
OUT="$(STATE '[]')"
check H1 'grep -q "\"show\": true, \"x\": 0.0521, \"y\": 0.0926" <<< "$OUT" && grep -q "\"corner\": \"rb\", \"size\": 1.0" <<< "$OUT" && grep -q "^busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadDeclarativeScript ss $FORGEOS_SHOWME_SHARE/overlay.qml forgeos-showme$" "$WORK/calls.log" && grep -q "org.kde.kwin.Scripting start$" "$WORK/calls.log"'
check H2 'grep -q "^kdialog --title Show Me How --yes-label Next --no-label Back --cancel-label Stop --yesnocancel Step 1 of 2" "$WORK/calls.log" && grep -q "You do the clicking. Show Me How only points." "$WORK/calls.log"'
# H3: Next -> step 2 (Save is not on the screen: the panel says so, with Try again)
echo 0 > "$WORK/panel"
wait_for 'grep -q "yes-label Try again --no-label Show me where to start --cancel-label Stop --yesnocancel I can.t see \"Save\"" "$WORK/calls.log"'; CODE=$?
OUT="$(STATE '[]')"
check H3 '[ "$CODE" = 0 ] && grep -q "\"show\": false" <<< "$OUT" && grep -q "\"step\": 2" <<< "$OUT"'
# H4: a second walk ends the first one (one at a time); Stop ends the second; KWin unloads the overlay
SM guide print > "$WORK/out2" 2>&1 & P2=$!
C1=99; wait_for '! kill -0 $P1 2>/dev/null' && { wait "$P1"; C1=$?; }
wait_for 'STATE "[]" | grep -q "\"total\": 2"'
STOP
C2=99; wait_for '! kill -0 $P2 2>/dev/null' && { wait "$P2"; C2=$?; }
check H4 '[ "$C1" = 1 ] && [ "$C2" = 1 ] && [ "$(grep -c "unloadScript s forgeos-showme" "$WORK/calls.log")" -ge 4 ] && [ -z "$(STATE "[]")" ] && [ ! -e "$WORK/run/forgeos-showme-$(id -u)/screen.png" ]'
# H5: our own panel (sent by the overlay) is never pointed at; a stranger on the screen ends the walk with a note
fresh; app org.kde.skanpage; screen 0 "Scan@100,100"
SM guide scan > "$WORK/out3" 2>&1 & P3=$!
wait_for 'STATE "[[0, 0, 0.5, 0.5]]" | grep -q "\"step\": 1"'
sleep 2.5
OUT="$(STATE '[[0, 0, 0.5, 0.5]]')"
printf 'SERVICE\ton\nSHARING\tAnyDesk\n' > "$WORK/say/techguard"
C3=99; wait_for '! kill -0 $P3 2>/dev/null' && { wait "$P3"; C3=$?; }
check H5 'grep -q "\"show\": false" <<< "$OUT" && [ "$C3" = 1 ] && grep -q "^kdialog --title Show Me How --msgbox Show Me How stopped because someone else can see" "$WORK/calls.log"'

echo
if [ "$failures" -eq 0 ]; then echo "All Show Me How tests H passed."; else echo "$failures Show Me How test(s) failed."; exit 1; fi
