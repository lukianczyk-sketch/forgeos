#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), cases F-I: speed from Why Is It Slow?'s 7-day history, room on the drive,
# privacy, hidden devices, ready for trouble, and a PC where no tool answers.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/card-fakes.sh
. "$ROOT/tests/card-fakes.sh"

# F1-F2: speed - slow 8% of the time (Why Is It Slow?'s reason); a game using the processor is not "slow";
# too little history = not checked
healthy_pc; slow_history 100 8
OUT="$(RC check)"
check F1 '[ "$(grade_of speed)" = C ] && [ "$(why_of speed)" = "Slow about 8% of the time in the last 7 days, mostly because the memory was nearly full." ]'
python3 - "$WORK/state/forgeos/slow/history.jsonl" <<'PY'
import json, sys
rows = [json.loads(x) for x in open(sys.argv[1])]
for r in rows[:30]:
    r.update(mem=0, cpu=95, top=["Cyberpunk2077.exe", 790])
open(sys.argv[1], "w").write("".join(json.dumps(r) + "\n" for r in rows))
PY
OUT="$(RC check)"; GAME_SPEED="$(grade_of speed)"
slow_history 5 0
OUT="$(RC check)"
check F2 '[ "$GAME_SPEED" = A ] && [ "$(grade_of speed)" = - ] && [ "$(why_of speed)" = "Not enough history yet - it fills in while the PC is on." ] && [ "$(overall)" = A ]'

# G1-G3: room to work (8% free = D with a tip); Privacy Report off = D; on, with the apps it noted this week
healthy_pc; export FORGEOS_CARD_SPACE="80000000000 1000000000000"
OUT="$(RC check)"
check G1 '[ "$(grade_of space)" = D ] && [ "$(why_of space)" = "80 GB free (8% of the drive). Free up space so the PC can work and update." ] && grep -q "${T}space${T}D${T}62${T}Room to work${T}Raise this grade${T}space${T}" <<< "$OUT"'
healthy_pc; say systemctl "inactive\n"; echo 3 > "$WORK/code/systemctl"
OUT="$(RC check)"
check G2 '[ "$(grade_of privacy)" = D ] && grep -q "^The Privacy Report is off" <<< "$(why_of privacy)"'
healthy_pc; echo 0 > "$WORK/code/systemctl"; mkdir -p "$WORK/state/forgeos-privacy"
printf '%s\tstart\tmic\tzoom\tZoom\n%s\tstop\tmic\tzoom\tZoom\n%s\tstart\tcamera\tcheese\tCheese\n%s\tstart\tmic\told\tOld App\n' \
  "$((NOW - 3600))" "$((NOW - 3000))" "$((NOW - DAY))" "$((NOW - 9 * DAY))" > "$WORK/state/forgeos-privacy/usage.log"
OUT="$(RC check)"
check G3 '[ "$(grade_of privacy)" = A ] && [ "$(why_of privacy)" = "On. 2 apps used the camera, microphone or screen this week (Cheese, Zoom). Have a look if one surprises you." ]'

# H1-H3: hidden devices - a red sweep = F; a clean but old sweep = B; never swept = not checked
healthy_pc; sweep red 2 "A camera you don't know: Wansview"
OUT="$(RC check)"
check H1 '[ "$(grade_of ghost)" = F ] && [ "$(why_of ghost)" = "The last sweep found something to check: A camera you don'"'"'t know: Wansview." ]'
sweep green 100
OUT="$(RC check)"
check H2 '[ "$(grade_of ghost)" = B ] && [ "$(why_of ghost)" = "The last sweep found nothing worrying. Sweep again - the last one was 100 days ago." ]'
rm -f "$WORK/data/forgeos/ghost/last-sweep.json"
OUT="$(RC check)"
check H3 'grep -q "^SUBJECT${T}ghost${T}-${T}-${T}Hidden devices${T}Check now${T}ghost${T}No sweep" <<< "$OUT"'
# H4: ready for trouble - no Emergency Envelope and no Find My PC = D, opens Digital Will first
healthy_pc; say forgeos-digitalwill "PEOPLE${T}0${T}\nENVELOPE${T}-${T}-${T}-\n"; say forgeos-locate "SETUP${T}no\n"
OUT="$(RC check)"
check H4 'grep -q "^SUBJECT${T}ready${T}D${T}60${T}Ready for trouble${T}Raise this grade${T}digitalwill${T}No Emergency Envelope yet (Digital Will); Find My PC is not set up.$" <<< "$OUT"'

# I1-I2: no ForgeOS tool answers at all (and the slow library is broken): nothing is graded, exit 1, no crash
for t in forgeos-guard forgeos-tripwire forgeos-techguard forgeos-autopilot forgeos-drivehealth forgeos-undo \
         forgeos-digitalwill forgeos-locate rpm-ostree; do rm -f "$WORK/bin/$t"; done
fake systemctl 'echo "Failed to connect to bus"; exit 1'  # the GitHub runner has a real systemctl in /usr/bin
rm -rf "$WORK/data" "$WORK/state"; unset FORGEOS_CARD_SPACE
OUT="$(HOME=/nonexistent FORGEOS_SLOW_LIB=/nonexistent PATH="$WORK/bin:/usr/bin:/bin" RC check)"; CODE=$?
check I1 '[ "$CODE" = 1 ] && grep -qx "OVERALL${T}-${T}-${T}Not checked yet${T}Nothing could be checked yet. Open each tool once, then look again." <<< "$OUT"'
check I2 '[ "$(grep -c "^SUBJECT${T}[a-z]*${T}-${T}-${T}" <<< "$OUT")" = 11 ] && HOME=/nonexistent PATH="$WORK/bin:/usr/bin:/bin" RC report | head -n 1 | grep -qx "PC Report Card: Not checked yet"'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests F-I passed."; else echo "$failures PC Report Card test(s) failed."; fi
exit "$((failures > 0))"
