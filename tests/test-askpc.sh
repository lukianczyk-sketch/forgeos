#!/usr/bin/env bash
# Tests for Ask Your PC (Job 9), cases A-H: health snapshot, health check, the safe fix list, fixes.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-askpc.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/askpc-fakes.sh
. "$ROOT/tests/askpc-fakes.sh"

# A: the snapshot shows the PC's health in plain words
OUT="$(bash "$AP" status)"; RC=$?
check A1 '[ "$RC" -eq 0 ] && grep -q "System: ForgeOS Test 44" <<< "$OUT" && grep -q "Memory free: 25%" <<< "$OUT"'
check A2 'grep -q "Drive used: system 40%, home 40%" <<< "$OUT" && grep -q "Battery: 80% (Discharging)" <<< "$OUT" && grep -q "Internet: full" <<< "$OUT"'
check A3 'grep -q "Core 0" <<< "$OUT" && ! grep -q "12.00 V" <<< "$OUT" && ! grep -q loopback <<< "$OUT" && grep -q "fake error one" <<< "$OUT"'
check A4 'grep -q "Update waiting for a restart: no" <<< "$OUT" && grep -q "Trash: 12M" <<< "$OUT" && grep -q "Fake_Printer" <<< "$OUT"'

# B: a healthy PC
OUT="$(bash "$AP" health)"; RC=$?
check B '[ "$RC" -eq 0 ] && grep -q "Everything looks good." <<< "$OUT" && ! grep -q "^!" <<< "$OUT"'

# C: every problem is found, in plain words
echo 5 > "$WORK/power/BAT0/capacity"
OUT="$(FAKE_DF=95 FAKE_NET=none FAKE_VOL="Volume: 0.40 [MUTED]" FAKE_FAILED=cups.service FAKE_STAGED=1 bash "$AP" health)"; RC=$?
check C1 '[ "$RC" -eq 1 ] && [ "$(grep -c "^!" <<< "$OUT")" -eq 6 ] && ! grep -q "Everything looks good" <<< "$OUT"'
check C2 'grep -q "95% full" <<< "$OUT" && grep -q "No internet" <<< "$OUT" && grep -q "muted" <<< "$OUT" && grep -q "battery is low (5%)" <<< "$OUT"'
check C3 'grep -q "stopped working: cups.service" <<< "$OUT" && grep -q "Restart the PC to finish" <<< "$OUT"'
echo Charging > "$WORK/power/BAT0/status"
OUT="$(FAKE_NET=portal bash "$AP" health)"
check C4 'grep -q "wants you to sign in" <<< "$OUT" && ! grep -q "battery is low" <<< "$OUT"'

# D: the fix list: only known fixes, the busiest program is named, the desktop itself is never picked
OUT="$(bash "$AP" fixes)"; RC=$?
check D1 '[ "$RC" -eq 0 ] && [ "$(wc -l <<< "$OUT")" -eq 12 ] && grep -q "^close-busy-app.*most computer power: fakegame.*fakegame$" <<< "$OUT"'
printf '  101 plasmashell\n  102 kwin_wayland\n  103 bwrap\n' > "$WORK/ps.txt"
OUT="$(bash "$AP" fixes)"
check D2 '[ "$(wc -l <<< "$OUT")" -eq 11 ] && ! grep -q close-busy-app <<< "$OUT"'

# E: simple fixes run the right command and are written to the history
: > "$WORK/calls.log"
OUT="$(bash "$AP" fix restart-sound)"; RC=$?
check E1 '[ "$RC" -eq 0 ] && grep -q "Done: Restart the sound system." <<< "$OUT" && grep -q "^systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service$" "$WORK/calls.log"'
bash "$AP" fix restart-taskbar >/dev/null
bash "$AP" fix unmute-sound >/dev/null
check E2 'grep -q "^systemctl --user restart plasma-plasmashell.service$" "$WORK/calls.log" && grep -q "^wpctl set-mute @DEFAULT_AUDIO_SINK@ 0$" "$WORK/calls.log" && grep -q "^wpctl set-volume @DEFAULT_AUDIO_SINK@ 0.5$" "$WORK/calls.log"'
OUT="$(bash "$AP" log)"
check E3 '[ "$(wc -l <<< "$OUT")" -eq 3 ] && grep -q "restart-sound: done" <<< "$OUT" && grep -q "unmute-sound: done" <<< "$OUT"'
OUT="$(FAKE_RESTART_RC=1 bash "$AP" fix restart-sound)"; RC=$?
check E4 '[ "$RC" -eq 1 ] && grep -q "That did not work" <<< "$OUT" && grep -q "restart-sound: did not work" "$WORK/state/forgeos/askpc.log"'

# F: the internet is always turned back on, even if turning it off failed
: > "$WORK/calls.log"
FAKE_OFF_RC=1 bash "$AP" fix restart-internet >/dev/null; RC=$?
check F '[ "$RC" -eq 0 ] && [ "$(paste -sd "|" "$WORK/calls.log")" = "nmcli networking off|nmcli networking on" ]'

# G: close the busiest program only if it is still the one the user agreed to
sleep 300 & VICTIM=$!
printf '  101 plasmashell\n  %s fakegame\n' "$VICTIM" > "$WORK/ps.txt"
OUT="$(bash "$AP" fix close-busy-app firefox)"; RC=$?
check G1 '[ "$RC" -eq 1 ] && grep -q "nothing was closed" <<< "$OUT" && kill -0 "$VICTIM"'
bash "$AP" fix close-busy-app >/dev/null; RC=$?
check G2 '[ "$RC" -eq 1 ] && kill -0 "$VICTIM"'
OUT="$(bash "$AP" fix close-busy-app fakegame)"; RC=$?
wait "$VICTIM" 2>/dev/null
check G3 '[ "$RC" -eq 0 ] && grep -q "Done: Close fakegame." <<< "$OUT" && ! kill -0 "$VICTIM" 2>/dev/null'
kill "$VICTIM" 2>/dev/null

# H: unknown fixes are refused; files fixes and "open" fixes work
OUT="$(bash "$AP" fix "rm -rf /")"; RC=$?
check H1 '[ "$RC" -eq 2 ] && grep -q "does not know how" <<< "$OUT"'
bash "$AP" fix clear-thumbnails >/dev/null; RC=$?
check H2 '[ "$RC" -eq 0 ] && [ ! -e "$WORK/home/.cache/thumbnails" ] && [ -d "$WORK/home/.cache" ]'
: > "$WORK/calls.log"
bash "$AP" fix empty-trash >/dev/null && bash "$AP" fix open-cleansweep >/dev/null; RC=$?
check H3 '[ "$RC" -eq 0 ] && grep -q "^gio trash --empty$" "$WORK/calls.log" && grep -q "^setsid -f forgeos-cleansweep-gui$" "$WORK/calls.log"'
bash "$AP" fix open-undo >/dev/null; RC=$?
check H4 '[ "$RC" -eq 1 ]'
bash "$AP" bogus >/dev/null 2>&1; RC=$?
check H5 '[ "$RC" -eq 3 ]'

echo "$failures failure(s)"
[ "$failures" -eq 0 ]
