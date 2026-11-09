#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), cases D-E: drive health (one F holds the overall grade to C; unreadable
# drives are not graded), backups by age, the Undo safety net (off, old, undated snapshots, did not answer).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard-drives.sh <repo-root>
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

# D1-D3: drive health - early wear = C; a failing drive = F and the overall grade can't be above C
healthy_pc; say forgeos-drivehealth "CHECKED${T}$((NOW - DAY))${T}watch\nDRIVE${T}sda${T}watch${T}WD Blue${T}hdd${T}2 TB\nDRIVE${T}nvme0${T}good${T}Samsung${T}ssd${T}1 TB\nBACKUP${T}set${T}1\n"
OUT="$(RC check)"; CODE=$?
check D1 '[ "$CODE" = 1 ] && [ "$(grade_of drive)" = C ] && [ "$(why_of drive)" = "Early signs of wear: WD Blue. Back up now." ] && [ "$(overall)" = A ]'
say forgeos-drivehealth "CHECKED${T}$((NOW - DAY))${T}danger\nDRIVE${T}sda${T}danger${T}WD Blue${T}hdd${T}2 TB\nBACKUP${T}set${T}1\n"
OUT="$(RC check)"
check D2 'grep -qx "OVERALL${T}C${T}79${T}Needs some care${T}Drive health is failing, so the overall grade can.t be above C. Fix that first." <<< "$OUT" && grep "^SUBJECT" <<< "$OUT" | head -n 1 | grep -q "${T}drive${T}F${T}40${T}"'
say forgeos-drivehealth "CHECKED${T}never${T}-\nBACKUP${T}none\n"
OUT="$(RC check)"
check D3 'grep -q "^SUBJECT${T}drive${T}-${T}-${T}Drive health${T}Check now${T}drivehealth${T}Drive Health has not read" <<< "$OUT" && [ "$(grade_of backup)" = F ]'
# D4: every drive unreadable (Drive Health then says "good" overall) = not checked, never a false A
say forgeos-drivehealth "CHECKED${T}$((NOW - DAY))${T}good\nDRIVE${T}sdb${T}unknown${T}USB box${T}hdd${T}4 TB\nBACKUP${T}set${T}1\n"
OUT="$(RC check)"
check D4 '[ "$(grade_of drive)" = - ] && [ "$(grade_of backup)" = A ]'

# E1-E3: backups by age; the Undo Button off / old snapshots / undated snapshots / did not answer
healthy_pc; say forgeos-drivehealth "CHECKED${T}$((NOW - 40 * DAY))${T}good\nDRIVE${T}nvme0${T}good${T}Samsung${T}ssd${T}1 TB\nBACKUP${T}set${T}20\n"
OUT="$(RC check)"
check E1 '[ "$(grade_of backup)" = C ] && [ "$(why_of backup)" = "Your last backup was 20 days ago. That is getting old." ] && [ "$(why_of drive)" = "All drives are healthy (last checked 40 days ago)." ] && [ "$(grade_of drive)" = A ]'
healthy_pc; say forgeos-undo "Undo Button: OFF (no snapshots folder at /var/home/.snapshots)\n"; echo 1 > "$WORK/code/forgeos-undo"
OUT="$(RC check)"
check E2 '[ "$(grade_of undo)" = F ] && [ "$(why_of undo)" = "The Undo Button is off - deleted or changed files can'"'"'t come back." ]'
say forgeos-undo "Undo Button: ON — 12 snapshots, from $(day 30) 10:00 to $(day 5) 09:00\n"; echo 0 > "$WORK/code/forgeos-undo"
OUT="$(RC check)"
A="$(why_of undo)"; B="$(grade_of undo)"
say forgeos-undo "Undo Button: ON — 3 snapshots, from unknown date to unknown date\n"
C="$(RC check)"; echo 3 > "$WORK/code/forgeos-undo"; OUT="$(RC check)"
check E3 'grep -q "${T}undo${T}A${T}90${T}.*${T}3 snapshots kept.$" <<< "$C" && [ "$B" = B ] && [ "$A" = "12 snapshots kept; the newest is from 5 days ago." ] && [ "$(grade_of undo)" = - ]'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests D-E passed."; else echo "$failures PC Report Card test(s) failed."; fi
exit "$((failures > 0))"
