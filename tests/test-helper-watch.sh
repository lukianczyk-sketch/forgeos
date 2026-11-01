#!/usr/bin/env bash
# Tests for Forge Helper (Job 13c), cases Q-T: speaks up first (watch-tick) - one note, max 3 a day,
# never during games or videos, "Not now" snoozes 3 days, the button is the user's Yes.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-watch.sh <repo-root>
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
T=$'\t'
tick() { : > "$WORK/calls.log"; python3 -B "$ROOT/tests/helper-watch-run.py" "$WORK"; }
notes() { grep -c "^notify-send" "$WORK/calls.log"; }
LOG="$WORK/state/forgeos/helper-watch.log"
ST="$WORK/state/forgeos/helper-watch.json"

# Q: nothing wrong -> no note; a full drive -> one note offering to empty the trash
tick
check Q1 '[ "$(notes)" -eq 0 ] && [ -s "$ST" ]'
echo 93 > "$WORK/disk-used"
mkdir -p "$WORK/data/Trash/files"; truncate -s 600M "$WORK/data/Trash/files/big"
echo fix > "$WORK/notify-answer"
tick
check Q2 '[ "$(notes)" -eq 1 ] && grep -q "drive is almost full (93% used).*frees 0.6 GB" "$WORK/calls.log" && grep -q -- "--action=fix=Empty the trash" "$WORK/calls.log"'
check Q3 'grep -qx "forgeos-askpc fix empty-trash" "$WORK/calls.log" && grep -q "shown disk" "$LOG" && grep -q "fix disk: pc_fix empty-trash -> 0" "$LOG"'
# The same topic is not shown again the same day.
tick
check Q4 '[ "$(notes)" -eq 0 ]'
rm -rf "$WORK/data/Trash"
echo 86500 > "$WORK/now-plus"
echo later > "$WORK/notify-answer"
tick
check Q5 '[ "$(notes)" -eq 1 ] && grep -q -- "--action=fix=Ask Your PC" "$WORK/calls.log" && ! grep -q "forgeos-askpc fix" "$WORK/calls.log" && grep -q "snoozed disk" "$LOG"'
# Snoozed for 3 days, back after that.
echo 180000 > "$WORK/now-plus"; tick; A="$(notes)"
echo 360000 > "$WORK/now-plus"; echo "" > "$WORK/notify-answer"; tick; B="$(notes)"
check Q6 '[ "$A" -eq 0 ] && [ "$B" -eq 1 ]'
echo 50 > "$WORK/disk-used"; rm -f "$WORK/now-plus"; rm -f "$ST"

# R: other problems: failed update, Guard caught something, health, a program hogging the PC, old backup
echo "uupd.service" > "$WORK/failed-units"
tick
check R1 'grep -q "update did not finish" "$WORK/calls.log" && grep -q -- "--action=fix=Open Undo Button" "$WORK/calls.log"'
rm "$WORK/failed-units"
printf '2026-10-31 10:00:00\tvirus\tdownloads\t%s/Downloads/bad.exe\tEicar\tq1\t20261031100000-1\n' "$H" > "$WORK/guard-events"
tick
check R2 'grep -q "Guard stopped 1 dangerous" "$WORK/calls.log"'
tick
check R3 '! grep -q "Guard stopped" "$WORK/calls.log"'
printf 'OK Drive space\n! Some background services stopped working: bluetooth\n' > "$WORK/health"; echo 1 > "$WORK/health-rc"
tick
check R4 'grep -q "found a problem: Some background services stopped working: bluetooth" "$WORK/calls.log"'
printf 'plasmashell 9000 99.0\nminer 1200 95.5\nbrave 30 50\n' > "$WORK/ps-out"
echo fix > "$WORK/notify-answer"; rm -f "$ST"; rm "$WORK/health-rc"; : > "$WORK/guard-events"
tick
check R5 'grep -q "miner has been using most" "$WORK/calls.log" && grep -qx "forgeos-askpc fix close-busy-app miner" "$WORK/calls.log"'
rm "$WORK/ps-out"; rm -f "$ST"
P="$H/.var/app/org.gnome.World.PikaBackup/config/pika-backup"; mkdir -p "$P"; echo '{}' > "$P/backup.json"; echo '{}' > "$P/histories.json"
touch -d "20 days ago" "$P/histories.json"
echo "" > "$WORK/notify-answer"
tick
check R6 'grep -q "last backup is more than 2 weeks old" "$WORK/calls.log"'
touch "$P/histories.json"; rm -f "$ST"; tick
check R7 '[ "$(notes)" -eq 0 ]'

# S: never more than 3 notes a day
rm -f "$ST"
for topic in 1 2 3 4; do
  case $topic in
    1) echo 95 > "$WORK/disk-used" ;;
    2) echo "uupd.service" > "$WORK/failed-units" ;;
    3) echo 1 > "$WORK/health-rc" ;;
    4) touch -d "20 days ago" "$P/histories.json" ;;
  esac
  tick; echo "$(notes)" >> "$WORK/counts"
done
check S1 '[ "$(tr -d "\n" < "$WORK/counts")" = 1110 ] && python3 -c "import json,sys; d=json.load(open(sys.argv[1])); sys.exit(d[\"count\"] != 3)" "$ST"'

# T: nothing while a game or video is playing (it stops the screen saver) or gamescope runs
rm -f "$ST"; echo "b true" > "$WORK/busctl-out"
tick
check T1 '[ "$(notes)" -eq 0 ]'
rm "$WORK/busctl-out"; touch "$WORK/gamescope"; tick; A="$(notes)"
rm "$WORK/gamescope"; tick; B="$(notes)"
check T2 '[ "$A" -eq 0 ] && [ "$B" -eq 1 ] && [ "$(stat -c %a "$ST")" = 600 ]'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper tests Q-T passed."; else echo "$failures Forge Helper test(s) failed."; fi
exit "$((failures > 0))"
