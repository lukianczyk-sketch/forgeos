#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases O-P: the Always-On Guard window - the three guards shown in plain
# words, recent warnings + why, locked-away files (keep, put back, delete), check a file now, unblock a website
# (password through pkexec), guards off (asks first) / on, the "Show why" button (--why).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-gui.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/guard-fakes.sh
. "$ROOT/tests/guard-fakes.sh"
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }
# shellcheck source=tests/guard-gui-fakes.sh
. "$ROOT/tests/guard-gui-fakes.sh"

# O: the guards in plain words; recent warnings + why; locked-away files; check a file now
W
check O1 'S | grep -qx "Download Guard: ON - every new download is checked for viruses (low-memory mode)" && S | grep -qx "Website Guard: ON - 2 scam and virus websites blocked" && S | grep -qx "Email Guard: ON - every new email is checked for scams (when you set up Thunderbird)" && S | grep -qx "The guard is not running right now." && S | grep -qx "Turn Download Guard OFF"'
virus "$D/prize.pdf"; G scan "$D/prize.pdf" >/dev/null; QID="$(G quarantine list | cut -f 1)"
mkmail "Crook <c@crook.example>" "You won" "SCAMWORD" > "$WORK/s.eml"; G check-mail "$WORK/s.eml" >/dev/null; EID="$(G events 1 | cut -f 7)"
W warnings "$EID"
check O2 'S | grep -q "^$(date +%Y)-.* [0-9][0-9]:[0-9][0-9]  Scam email from c@crook.example: You won$" && S | grep -q "VIRUS locked away: prize.pdf (ForgeOS.Test.Eicar.UNOFFICIAL)" && S | grep -qx "Why Always-On Guard warned you:" && S | grep -q "It asks for gift cards" && [ "$(S | grep -n "Scam email" | cut -d: -f1)" -lt "$(S | grep -n "VIRUS locked" | cut -d: -f1)" ]'
W locked "$QID" keep
check O3 '[ -e "$WORK/data/forgeos/guard/quarantine/$QID" ] && S | grep -q "prize.pdf  (ForgeOS.Test.Eicar.UNOFFICIAL)" && S | grep -qx "Keep it locked away (safest)"'
printf '%s\n' 1 > "$WORK/yes"; W locked "$QID" restore
check O4 '[ -e "$WORK/data/forgeos/guard/quarantine/$QID" ] && [ ! -e "$D/prize.pdf" ] && S | grep -q "This file had a VIRUS."'
W locked "$QID" restore
check O5 '[ -e "$D/prize.pdf" ] && S | grep -qx "Put back: $D/prize.pdf"'
G scan "$D/prize.pdf" >/dev/null; QID="$(G quarantine list | cut -f 1)"
W locked "$QID" delete
check O6 '[ ! -e "$WORK/data/forgeos/guard/quarantine/$QID" ] && S | grep -qx "Deleted for good." && W locked && S | grep -qx "No files are locked away."'
virus "$D/check.doc"; echo "clean" > "$D/fine.txt"; echo MZ > "$D/tool.exe"; printf '%s\n' "$D/check.doc" "$D/fine.txt" "$D/tool.exe" > "$WORK/file"
W check check check
check O7 'S | grep -q "^VIRUS FOUND in check.doc: ForgeOS.Test.Eicar.UNOFFICIAL" && S | grep -qx "No virus found in fine.txt." && S | grep -q "^No virus found, but be careful: tool.exe is a Windows program or script (.exe)." && [ ! -e "$D/check.doc" ]'

# P: unblock a website (warning first, the password through pkexec); guards off (asks; No = nothing) and on; --why
printf '%s\n' "www.fake-bank.test" > "$WORK/input"; : > "$WORK/calls.log"
W unblock
check P1 'S | grep -q "If someone on the phone tells you to do this, it is a scam - hang up." && S | grep -qx "Unblock www.fake-bank.test?" && S | grep -qx "Unblocked: fake-bank.test" && grep -q "^pkexec $FORGEOS_GUARD_HOSTS_HELPER allow www.fake-bank.test$" "$WORK/calls.log" && ! grep -q fake-bank "$WORK/hosts"'
printf '%s\n' 1 > "$WORK/yes"; W dl
check P2 '! grep -q "downloads=off" "$WORK/cfg/forgeos/guard.conf" 2>/dev/null && S | grep -q "Your PC will be less safe."'
W dl em
check P3 'grep -qx "downloads=off" "$WORK/cfg/forgeos/guard.conf" && grep -qx "email=off" "$WORK/cfg/forgeos/guard.conf" && S | grep -qx "Email Guard is OFF." && S | grep -qx "Download Guard: OFF - every new download is checked for viruses (low-memory mode)"'
W dl
check P4 'grep -qx "downloads=on" "$WORK/cfg/forgeos/guard.conf" && S | grep -qx "Download Guard is ON." && ! S | grep -q "less safe"'
: > "$WORK/shown"; bash "$GUI" --why "$EID"; R1=$?
bash "$GUI" --oops >/dev/null 2>&1; R2=$?
check P5 '[ "$R1$R2" = 03 ] && S | grep -q "It asks for gift cards" && (PATH="/usr/bin:/bin"; bash "$GUI" >/dev/null 2>&1; [ $? -eq 3 ])'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
