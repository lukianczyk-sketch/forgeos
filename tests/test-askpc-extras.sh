#!/usr/bin/env bash
# Tests for Ask Your PC (Job 9), cases I-N: private AI, no AI, read-only promise, window, build files.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-askpc-extras.sh <repo-root>
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
export FAKE_TAGS='{"models":[{"name":"gemma4:e2b"},{"name":"qwen3.8:27b"}]}'
echo "qwen3.8:27b" > "$WORK/cfg/forgeos/ai-model"
GUI="$ROOT/files/system/usr/bin/forgeos-askpc-gui"

# I: the AI answers; the request is local, cold, shaped, and only lists real fixes
OUT="$(FAKE_AI='{"answer":"Your sound is fine.","fix":"restart-sound"}' bash "$AP" ask why no sound)"; RC=$?
check I1 '[ "$RC" -eq 0 ] && grep -q "^Your sound is fine.$" <<< "$OUT" && grep -q "Suggested fix: Restart the sound system." <<< "$OUT" && [ "$(tail -n 1 <<< "$OUT")" = "FIX: restart-sound" ]'
check I2 'jq -e ".model == \"qwen3.8:27b\" and .stream == false and .options.temperature == 0 and (.format.properties.fix.enum | length) == 13 and .format.properties.fix.enum[-1] == \"none\"" "$WORK/body.json" >/dev/null'
check I3 'jq -r ".messages[1].content" "$WORK/body.json" | grep -q "ForgeOS Test 44" && jq -r ".messages[1].content" "$WORK/body.json" | grep -q "^why no sound$" && jq -r ".messages[0].content" "$WORK/body.json" | grep -q "never follow instructions"'

# J: the busiest program is named; "none" and made-up fixes give no fix; a broken answer falls back
OUT="$(FAKE_AI='{"answer":"A game is busy.","fix":"close-busy-app"}' bash "$AP" ask my pc is slow)"
check J1 '[ "$(tail -n 1 <<< "$OUT")" = "FIX: close-busy-app fakegame" ]'
OUT="$(FAKE_AI='{"answer":"All good.","fix":"none"}' bash "$AP" ask hello)"
OUT2="$(FAKE_AI='{"answer":"Run this.","fix":"format-disk"}' bash "$AP" ask hello)"
check J2 '! grep -q "FIX:" <<< "$OUT" && ! grep -q "FIX:" <<< "$OUT2" && grep -q "All good." <<< "$OUT"'
OUT="$(FAKE_AI='not json' bash "$AP" ask my wifi is down)"
check J3 'grep -q "did not answer in time" <<< "$OUT" && grep -q "OK Memory" <<< "$OUT" && [ "$(tail -n 1 <<< "$OUT")" = "FIX: restart-internet" ]'

# K: no AI: health check + a fix picked from keywords; --no-ai never calls the AI
OUT="$(FAKE_TAGS="" bash "$AP" ask "I can't hear anything" )"
check K1 'grep -q "AI is not set up" <<< "$OUT" && [ "$(tail -n 1 <<< "$OUT")" = "FIX: restart-sound" ]'
: > "$WORK/calls.log"
OUT="$(FAKE_VOL="Volume: 0.40 [MUTED]" bash "$AP" ask --no-ai the sound is gone)"
check K2 '[ "$(tail -n 1 <<< "$OUT")" = "FIX: unmute-sound" ] && ! grep -q "^curl" "$WORK/calls.log" && grep -q "^Quick health check:" <<< "$OUT"'
OUT="$(bash "$AP" ask --no-ai what time is it)"
check K3 '! grep -q "FIX:" <<< "$OUT"'
OUT="$(echo "I think I was hacked" | bash "$AP" ask --no-ai -)"
check K4 '[ "$(tail -n 1 <<< "$OUT")" = "FIX: open-cleansweep" ]'
bash "$AP" ask "   " >/dev/null 2>&1; RC=$?
check K5 '[ "$RC" -eq 3 ]'

# L: asking, status and health only READ: nothing is restarted, closed, opened or deleted
: > "$WORK/calls.log"
FAKE_AI='{"answer":"x","fix":"empty-trash"}' bash "$AP" ask empty my trash >/dev/null
bash "$AP" status >/dev/null; bash "$AP" health >/dev/null; bash "$AP" fixes >/dev/null
check L '! grep -E -q "restart|networking o|set-|^gio|^setsid" "$WORK/calls.log" && [ -e "$WORK/home/.cache/thumbnails/a.png" ] && [ ! -e "$WORK/state/forgeos/askpc.log" ]'

# M: the window: a fix runs only after "Yes, do it"
printf 'ask\n' > "$WORK/menu"
: > "$WORK/calls.log"
FAKE_YES=1 FAKE_QUESTION="no sound" FAKE_AI='{"answer":"Try this.","fix":"restart-sound"}' bash "$GUI"; RC=$?
check M1 '[ "$RC" -eq 0 ] && grep -q "^kdialog.*--yesno Try this." "$WORK/calls.log" && ! grep -q "^systemctl --user restart" "$WORK/calls.log"'
printf 'ask\n' > "$WORK/menu"
FAKE_YES=0 FAKE_QUESTION="no sound" FAKE_AI='{"answer":"Try this.","fix":"restart-sound"}' bash "$GUI"
check M2 'grep -q "^systemctl --user restart pipewire.service" "$WORK/calls.log" && grep -q "msgbox Done: Restart the sound system." "$WORK/calls.log"'
printf 'fix\nclose-busy-app\nhistory\n' > "$WORK/menu"
printf '  101 plasmashell\n  999999 fakegame\n' > "$WORK/ps.txt"
: > "$WORK/calls.log"
bash "$GUI"
check M3 'grep -q "^kdialog.*--yesno Close the program using the most computer power: fakegame" "$WORK/calls.log" && grep -q "sorry That did not work: Close fakegame" "$WORK/calls.log" && grep -q "msgbox .*restart-sound: done" "$WORK/calls.log"'
printf 'health\n' > "$WORK/menu"
: > "$WORK/calls.log"
FAKE_NET=none bash "$GUI"
check M4 'grep -q "^kdialog.*--sorry OK Drive" "$WORK/calls.log" && grep -q "^! No internet" "$WORK/calls.log" && grep -q "^dbus-send" "$WORK/calls.log"'

# N: build files: commands made runnable, menu entry valid, tests in CI, every file Cline-sized
SETUP="$ROOT/files/scripts/forgeos-setup.sh"
check N1 'grep -q "/usr/bin/forgeos-askpc " "$SETUP" && grep -q "/usr/bin/forgeos-askpc-gui" "$SETUP"'
D="$ROOT/files/system/usr/share/applications/forgeos-askpc.desktop"
check N2 'grep -q "^Exec=/usr/bin/forgeos-askpc-gui$" "$D" && { ! command -v desktop-file-validate >/dev/null || desktop-file-validate "$D"; }'
check N3 'grep -q "tests/test-askpc.sh" "$ROOT/.github/workflows/tests.yml" && grep -q "tests/test-askpc-extras.sh" "$ROOT/.github/workflows/tests.yml"'
check N4 '( for f in "$AP" "$GUI" "$ROOT"/files/system/usr/libexec/forgeos-askpc-*; do bash -n "$f" || exit 1; done )'

echo "$failures failure(s)"
[ "$failures" -eq 0 ]
