#!/usr/bin/env bash
# Tests for Ransomware Tripwire (Job 16), cases H-J: "Remove the program", "It's mine, let it go" (trusted
# next time, unless the program file changed), "Turn the internet back on", root only acts on YOUR incidents,
# a program outside an app scope is stopped with SIGSTOP (a real process), and the helpers' strict arguments.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-tripwire-actions.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'kill -9 "${SLEEPER:-0}" 2>/dev/null; rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/tripwire-fakes.sh
. "$ROOT/tests/tripwire-fakes.sh"
caught() { for i in $(seq 1 22); do letter "$H/Documents/letter $i.txt" "$i"; done; attack "$1" "$H/Documents" 22; replay >/dev/null; }
locked() { python3 -B -c "import sys; sys.path.insert(0, sys.argv[1]); from guardlib import quarantine; [print(e[2]) for e in quarantine.entries()]" "$FORGEOS_TW_GUARD_LIB"; }
CG="$WORK/cg$APP/app-wine-4242.scope"

# H: Remove the program: the whole app is ended and its program file (in your Downloads) is locked away
fresh; prog 4242 invoice.exe "$APP/app-wine-4242.scope" "$H/Downloads/invoice.exe"; caught 4242; ID="$(inc)"
OUT="$(TW remove "$ID")"; RC=$?
check H1 '[ "$RC" -eq 0 ] && [ "$(cat "$CG/cgroup.kill")" = 1 ] && [ "$(py "$ID" "i[\"state\"]")" = removed ] && grep -q "^Program removed and its file locked away: $H/Downloads/invoice.exe$" <<< "$OUT"'
check H2 '[ ! -e "$H/Downloads/invoice.exe" ] && locked | grep -qx "$H/Downloads/invoice.exe" && calls | grep -qx "pkexec $FORGEOS_TW_HELPER remove $ID"'
TW remove "$ID" >/dev/null; R1=$?
check H3 '[ "$R1" -eq 1 ]'
fresh; prog 4243 other.exe "$APP/app-wine-4243.scope"; caught 4243; ID="$(inc)"
PK_UID=4321 TW remove "$ID" >/dev/null; R1=$?; touch "$WORK/pkexec-no"; TW remove "$ID" >/dev/null; R2=$?; rm "$WORK/pkexec-no"
check H4 '[ "$R1" -eq 3 ] && [ "$R2" -eq 126 ] && [ "$(py "$ID" "i[\"state\"]")" = frozen ] && [ "$(cat "$WORK/cg$APP/app-wine-4243.scope/cgroup.kill")" = 0 ]'

# I: It's mine: unfrozen and trusted; the same program is not stopped next time; a CHANGED program file is
fresh; prog 4242 encryptor "$APP/app-wine-4242.scope" "$WORK/progs/encryptor"; caught 4242; ID="$(inc)"
TW release "$ID" >/dev/null; RC=$?
check I1 '[ "$RC" -eq 0 ] && [ "$(cat "$CG/cgroup.freeze")" = 0 ] && [ "$(py "$ID" "i[\"state\"]")" = released ] && calls | grep -qx "pkexec $FORGEOS_TW_RELEASE release $ID"'
check I2 'python3 -c "import json,sys; a=json.load(open(sys.argv[1])); assert a[0][\"exe\"] == sys.argv[2] and len(a[0][\"sha256\"]) == 64" "$WORK/var/allowed.json" "$WORK/progs/encryptor" && grep -qx "TRUSTED${T}encryptor${T}$WORK/progs/encryptor" <<< "$(TW status)"'
rm -f "$WORK/var/incidents/"*; caught 4242
check I3 '[ -z "$(inc)" ]'
echo "changed" >> "$WORK/progs/encryptor"; caught 4242
check I4 '[ -n "$(inc)" ]'
# I5: Wine runs every Windows program: "It's mine" trusts only that one Windows program, not all of them
fresh; prog 4242 wine64 "$APP/app-wine-4242.scope" "$WORK/progs/wine64" "wine64 C:/Tools/7zip.exe"; caught 4242
TW release "$(inc)" >/dev/null; rm -f "$WORK/var/incidents/"*; caught 4242
check I5 '[ -z "$(inc)" ] && python3 -c "import json,sys; assert json.load(open(sys.argv[1]))[0][\"cmd\"] == \"wine64 C:/Tools/7zip.exe\"" "$WORK/var/allowed.json"'
prog 4244 wine64 "$APP/app-wine-4244.scope" "$WORK/progs/wine64" "wine64 C:/Users/robert/Downloads/invoice.exe"; caught 4244
check I6 '[ "$(py "$(inc)" "i[\"pid\"]")" = 4244 ]'

# J1: Turn the internet back on (only if it was on before); J2: a program outside an app scope gets SIGSTOP
fresh; prog 4242 x.exe "$APP/app-wine-4242.scope"; caught 4242
check J1 '[ "$(cat "$WORK/net-state")" = disabled ] && grep -qx "INTERNET${T}cut" <<< "$(TW status)"'
OUT="$(TW net-on)"; RC=$?
check J2 '[ "$RC" -eq 0 ] && [ "$OUT" = "The internet is back on." ] && [ "$(cat "$WORK/net-state")" = enabled ] && [ ! -e "$WORK/run/net-cut" ] && grep -qx "INTERNET${T}normal" <<< "$(TW status)"'
fresh; echo disabled > "$WORK/net-state"; caught 4242; TW net-on >/dev/null
check J3 '[ "$(cat "$WORK/net-state")" = disabled ] && ! calls | grep -qx "nmcli networking on"'
fresh; sleep 300 & SLEEPER=$!
prog "$SLEEPER" sleep "/user.slice/user-1000.slice/session-2.scope"; caught "$SLEEPER"; ID="$(inc)"
check J4 '[ "$(py "$ID" "i[\"frozen\"]")" = program ] && [ "$(ps -o stat= -p "$SLEEPER" | cut -c1)" = T ] && [ ! -s "$WORK/cg/user.slice/user-1000.slice/session-2.scope/cgroup.freeze" ] || [ "$(cat "$WORK/cg/user.slice/user-1000.slice/session-2.scope/cgroup.freeze")" = 0 ]'
TW remove "$ID" >/dev/null; sleep 0.3
check J5 '! kill -0 "$SLEEPER" 2>/dev/null'
FORGEOS_TW_ROOT=1 bash "$FORGEOS_TW_HELPER" remove "../../etc" >/dev/null 2>&1; R1=$?
FORGEOS_TW_ROOT=1 bash "$FORGEOS_TW_HELPER" release "$ID" >/dev/null 2>&1; R2=$?
FORGEOS_TW_ROOT=1 bash "$FORGEOS_TW_RELEASE" remove "$ID" >/dev/null 2>&1; R3=$?
FORGEOS_TW_ROOT=0 TW root-do net-on >/dev/null 2>&1; R4=$?
check J6 '[ "$R1$R2$R3$R4" = 3333 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
