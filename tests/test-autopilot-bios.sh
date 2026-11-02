#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), case J: BIOS updates: safety checks (battery, charger, VM),
# the TPM warning, "Get it ready", the result after the restart, stop after 2 failures.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot-bios.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/autopilot-fakes.sh
. "$ROOT/tests/autopilot-fakes.sh"
normal_pc; os aaa; dmi "Dell Inc." "XPS 13" "1.18.0" "$(date -d "-30 days" +%m/%d/%Y)"; AP after-boot >/dev/null
echo "{\"Devices\": [$BIOS_DEV, $MOUSE_DEV]}" > "$WORK/fw-devices.json"

# J: BIOS: blockers (battery, charger, VM), note -> Get it ready -> made ready; the result after the restart
fw_updates "$BIOS_DEV" "$(rel 1.21.0 "Fixes 2 security problems.")"
power 1 30; : > "$WORK/calls.log"; AP tick
check J1 '! grep -q "BIOS update ready" "$WORK/calls.log" && grep -qx "BLOCKED${T}Let the battery charge to at least 50% first (now 30%)." <<< "$(AP bios)" && [ "$(AP firmware install bios1)" = "Not yet: Let the battery charge to at least 50% first (now 30%)." ]'
power 0 90; touch "$WORK/vm"
check J2 'grep -qx "BLOCKED${T}Plug in the charger first." <<< "$(AP bios)" && grep -q "^BLOCKED${T}This is a virtual machine" <<< "$(AP bios)" && ! grep -q "^fwupdmgr update bios1" "$WORK/calls.log"'
power 1 90; rm -f "$WORK/vm"; echo "luks-1 UUID=x none tpm2-device=auto" > "$WORK/etc/crypttab"
echo go > "$WORK/clicks"; : > "$WORK/calls.log"; AP tick
check J3 'grep -q "^notify-send .*--action=go=Get it ready --action=later=Not now BIOS update ready A new BIOS for your PC is ready (1.18.0 to 1.21.0). Fixes 2 security problems." "$WORK/calls.log" && grep -q "type your disk password once" "$WORK/calls.log" && grep -qx "fwupdmgr update bios1 --assume-yes --no-reboot-check" "$WORK/calls.log"'
check J4 'calls_wait "BIOS update Ready. It installs the next time you restart (about 4 minutes)" && grep -qx "BIOS 1.21.0 is ready and installs at the next restart." <<< "$(AP firmware results)" && grep -qx "TPM${T}yes" <<< "$(AP bios)"'
: > "$WORK/calls.log"; AP tick
check J5 '! grep -q "BIOS update ready" "$WORK/calls.log" && ! grep -q "^fwupdmgr get-results" "$WORK/calls.log"'
export FORGEOS_AP_BOOT_ID=boot-2; echo "{\"Name\": \"System Firmware\", \"DeviceId\": \"bios1\", \"UpdateState\": \"success\", \"Version\": \"1.21.0\"}" > "$WORK/fw-results.json"
rm -f "$WORK/fw-updates.json"; : > "$WORK/calls.log"; AP tick
check J6 'grep -qx "fwupdmgr get-results bios1 --json" "$WORK/calls.log" && calls_wait "BIOS updated Your BIOS update worked (now 1.21.0)." && grep -q "${T}bios${T}BIOS update worked (now 1.21.0)." "$LOGF"'
# a failed one: tell, try again next week; failed twice = stop
fw_updates "$BIOS_DEV" "$(rel 1.22.0 "More fixes.")"
for b in 3 4; do
  printf 'go\n' > "$WORK/clicks"; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.get('told',{}).pop('bios-1.22.0',None); json.dump(d,open(p,'w'))" "$ST"
  export FORGEOS_AP_BOOT_ID=boot-$b; AP tick
  echo '{"DeviceId": "bios1", "UpdateState": "failed", "UpdateError": "capsule not applied"}' > "$WORK/fw-results.json"
  export FORGEOS_AP_BOOT_ID=boot-$b-x; : > "$WORK/calls.log"; AP tick
done
check J7 'calls_wait "ForgeOS stopped trying" && [ "$(grep -c "BIOS update did not finish (failed capsule not applied)" "$LOGF")" = 2 ]'
: > "$WORK/calls.log"; python3 -c "import json,sys; p=sys.argv[1]; d=json.load(open(p)); d.get('told',{}).pop('bios-1.22.0',None); json.dump(d,open(p,'w'))" "$ST"; AP tick
check J8 '! grep -q "BIOS update ready" "$WORK/calls.log"'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
