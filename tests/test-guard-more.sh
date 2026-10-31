#!/usr/bin/env bash
# Tests for Always-On Guard (Job 13b), cases C-D: locked-away files (list, put back, delete), status,
# guards on/off, warnings + why, wrong use.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-guard-more.sh <repo-root>
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
D="$HOME/Downloads"
command -v clamscan >/dev/null 2>&1 || { echo "FAIL clamscan is needed (apt-get install clamav)"; exit 1; }

# C: locked-away files - list, put back (name taken -> "(restored 1)"), delete, wrong IDs
virus "$D/photo.jpg"; QID="$(G scan "$D/photo.jpg" | cut -f 4)"
virus "$D/report.pdf"; G scan "$D/report.pdf" >/dev/null; echo "new one" > "$D/report.pdf"
LIST="$(G quarantine list)"; QR="$(grep "${T}$D/report.pdf${T}" <<< "$LIST" | cut -f 1)"
check C1 '[ "$(wc -l <<< "$LIST")" -ge 2 ] && grep -q "^$QID${T}20[0-9-]* [0-9:]*${T}$D/photo.jpg${T}ForgeOS.Test.Eicar.UNOFFICIAL$" <<< "$LIST"'
OUT="$(G quarantine restore "$QR")"; RC=$?
check C2 '[ "$RC" -eq 0 ] && [ "$OUT" = "Put back: $D/report (restored 1).pdf" ] && [ "$(stat -c %a "$D/report (restored 1).pdf")" = 600 ] && [ "$(cat "$D/report.pdf")" = "new one" ] && ! grep -q "$QR" <<< "$(G quarantine list)"'
OUT="$(G quarantine delete "$QID")"; RC=$?
G quarantine delete "$QID" >/dev/null; R1=$?; G quarantine restore "../../etc" >/dev/null; R2=$?; G quarantine >/dev/null 2>&1; R3=$?
check C3 '[ "$RC$R1$R2$R3" = 0113 ] && [ "$OUT" = "Deleted for good." ] && [ ! -e "$QD/$QID" ] && ! grep -q "^$QID" <<< "$(G quarantine list)"'

# D: status, guards on/off (settings + the service), warnings + why, wrong use
virus "$D/x1.doc"; virus "$D/x2.doc"; G scan "$D/x1.doc" "$D/x2.doc" >/dev/null
printf 'state=on\nblocked=48213\nupdated=2026-10-28 03:00\n' > "$WORK/hosts-status"; touch "$WORK/active"
ST="$(G status)"
check D1 'grep -qx "SERVICE${T}running" <<< "$ST" && grep -qx "GUARD${T}websites${T}on${T}48213${T}2026-10-28 03:00" <<< "$ST" && grep -qx "GUARD${T}email${T}on${T}no-thunderbird" <<< "$ST" && grep -q "^VIRUSLIST${T}20[0-9][0-9]-" <<< "$ST" && grep -q "^LOCKED${T}[1-9]" <<< "$ST"'
: > "$WORK/calls.log"
check D2 '[ "$(G off email)" = "Email Guard is OFF." ] && grep -qx "email=off" "$WORK/cfg/forgeos/guard.conf" && grep -qx "GUARD${T}email${T}off${T}no-thunderbird" <<< "$(G status)" && grep -q "^systemctl --user enable --now forgeos-guard.service" "$WORK/calls.log"'
G off all >/dev/null
check D3 'grep -q "^systemctl --user disable --now forgeos-guard.service" "$WORK/calls.log" && [ "$(G on all)" = "$(printf "Download Guard is ON.\nEmail Guard is ON.")" ] && [ "$(tail -n 1 "$WORK/calls.log")" = "systemctl --user enable --now forgeos-guard.service" ]'
EID="$(G events 1 | cut -f 7)"; mkdir -p "$WORK/state/forgeos/guard/why"; echo "Because." > "$WORK/state/forgeos/guard/why/$EID.txt"
G why "../x" >/dev/null 2>&1; R1=$?; G scan >/dev/null 2>&1; R2=$?; G on wifi >/dev/null 2>&1; R3=$?; G events x >/dev/null 2>&1; R4=$?; G >/dev/null 2>&1; R5=$?
check D4 '[ "$(G why "$EID")" = Because. ] && [ "$R1$R2$R3$R4$R5" = 33333 ] && [ "$(G events 3 | wc -l)" = 3 ] && [ "$(G events | head -n 1 | awk -F"\t" "{print NF}")" = 7 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
