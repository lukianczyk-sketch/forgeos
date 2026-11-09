#!/usr/bin/env bash
# Tests for PC Report Card (Job 21), cases A-C: the grades - a healthy PC (and a laptop battery), the safety
# guards (worst problem first, the tool that raises the grade), updates; "not checked yet" costs nothing.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-reportcard.sh <repo-root>
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

# A1-A2: a healthy desktop PC - all A, exit 0, Passwords shown last but not graded, no battery line
healthy_pc
OUT="$(RC check)"; CODE=$?
check A1 '[ "$CODE" = 0 ] && grep -qx "OVERALL${T}A${T}100${T}Excellent${T}Your PC is in good shape. Keep it that way: let it update and keep backing up." <<< "$OUT" && [ "$(grep -c "^SUBJECT${T}[a-z]*${T}A${T}100${T}" <<< "$OUT")" = 10 ]'
check A2 'grep "^SUBJECT" <<< "$OUT" | tail -n 1 | grep -q "^SUBJECT${T}passwords${T}-${T}-${T}Passwords${T}-${T}-${T}Coming with" && ! grep -q "${T}battery${T}" <<< "$OUT" && grep -qx "CHANGE${T}This is the first report card. Next month it shows what changed." <<< "$OUT"'
# A3: a laptop battery that holds 65% -> C with a tip; a mouse battery (no power supply) is not graded
say upower "/org/freedesktop/UPower/devices/mouse_dev_1\n/org/freedesktop/UPower/devices/battery_BAT0\n"
fake upower 'case "$*" in -e) cat "$WORK/say/upower" ;; *mouse*) printf "  power supply:         no\n  capacity:            20%%\n" ;; *) printf "  power supply:         yes\n  capacity:            65.4%%\n" ;; esac'
OUT="$(RC check)"
check A3 '[ "$(grade_of battery)" = C ] && [ "$(why_of battery)" = "It holds 65% of what it held when new. A new battery brings back the hours." ] && [ "$(grep -c "${T}battery${T}" <<< "$OUT")" = 1 ]'
fake upower 'exit 0'

# B1-B3: safety guards - worst problems said first, each guard off costs points, old lists, the tool to open
healthy_pc
say forgeos-guard "SERVICE${T}stopped\nGUARD${T}downloads${T}on${T}fast\nGUARD${T}websites${T}off${T}0${T}\nGUARD${T}email${T}off${T}no-thunderbird\nVIRUSLIST${T}$(day 1)\n"
OUT="$(RC check)"
check B1 '[ "$(grade_of safety)" = F ] && [ "$(why_of safety)" = "Always-On Guard is stopped; the scam website blocker is off." ] && grep -q "^SUBJECT${T}safety${T}F${T}50${T}Safety guards${T}Raise this grade${T}guard${T}" <<< "$OUT"'
healthy_pc; say forgeos-guard "SERVICE${T}running\nGUARD${T}websites${T}on${T}9${T}$(day 12) 03:00\nVIRUSLIST${T}$(day 10)\n"
OUT="$(RC check)"
check B2 '[ "$(grade_of safety)" = C ] && [ "$(why_of safety)" = "The virus list is 10 days old; the scam website list is 12 days old." ]'
healthy_pc; say forgeos-tripwire "SERVICE${T}on\nINTERNET${T}cut\n"
OUT="$(RC check)"
check B3 '[ "$(grade_of safety)" = C ] && grep -q "^SUBJECT${T}safety${T}C${T}70${T}Safety guards${T}Raise this grade${T}tripwire${T}Ransomware Tripwire cut the internet - open it to see why.$" <<< "$OUT"'

# B4: someone can see or control the PC right now (Fake Tech Support Guard)
healthy_pc; say forgeos-techguard "SERVICE${T}on\nSHARING${T}AnyDesk\nINTERNET${T}on\n"
OUT="$(RC check)"
check B4 'grep -q "^SUBJECT${T}safety${T}D${T}60${T}.*${T}techguard${T}Someone can see or control this PC right now.$" <<< "$OUT"'

# C1-C3: updates - updates switched off, ForgeOS 70 days old, an update ready after a restart
healthy_pc; say forgeos-autopilot "DRIVERS${T}current${T}\nUPDATES${T}off\nFIRMWARE${T}2${T}1.30${T}checked\nDEVICES${T}0\n"
OUT="$(RC check)"
check C1 '[ "$(grade_of updates)" = F ] && [ "$(why_of updates)" = "Automatic updates are switched off; 2 device updates are waiting." ]'
healthy_pc; say rpm-ostree "{\"deployments\": [{\"staged\": true, \"timestamp\": $NOW}, {\"booted\": true, \"timestamp\": $((NOW - 70 * DAY))}]}"
OUT="$(RC check)"
check C2 '[ "$(grade_of updates)" = F ] && [ "$(why_of updates)" = "ForgeOS has not updated in 70 days; an update is ready - restart to finish." ]'
healthy_pc; say forgeos-autopilot "UPDATES${T}ok\nAFTERBOOT${T}problem${T}No sound\n"
OUT="$(RC check)"; AB="$(why_of updates)"
healthy_pc; say forgeos-autopilot ""; say rpm-ostree "not json"
OUT="$(RC check)"
check C3 '[ "$AB" = "Something stopped working after the last update." ] && grep -q "^SUBJECT${T}updates${T}-${T}-${T}Updates${T}Check now${T}autopilot${T}Drivers & BIOS did not answer.$" <<< "$OUT" && [ "$(overall)" = A ]'

echo
if [ "$failures" -eq 0 ]; then echo "All PC Report Card tests A-C passed."; else echo "$failures PC Report Card test(s) failed."; fi
exit "$((failures > 0))"
