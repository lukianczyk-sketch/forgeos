#!/usr/bin/env bash
# Tests for Driver & BIOS Autopilot (Job 13d), cases A-B: status + plain report, driver changes from
# rpm-ostree (and the fallback when db diff fails).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-autopilot.sh <repo-root>
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
RECENT="$(date -d "-30 days" +%m/%d/%Y)"

# A: a healthy PC: status lines, plain report, exit codes, last good version remembered
normal_pc; dmi "Acer" "Predator PHN18-72" "V1.05" "$RECENT"; os aaa
OUT="$(AP status)"; RC=$?
check A1 '[ "$RC" -eq 0 ] && grep -qx "DRIVERS${T}current${T}" <<< "$OUT" && grep -qx "UPDATES${T}ok" <<< "$OUT" && grep -qx "FIRMWARE${T}0${T}-${T}checked" <<< "$OUT" && grep -qx "DEVICES${T}0" <<< "$OUT"'
check A2 'grep -qx "BIOS${T}Acer${T}Predator PHN18-72${T}V1.05${T}${RECENT}${T}unknown" <<< "$OUT" && grep -qx "IMAGE${T}ok" <<< "$OUT" && grep -qx "NVIDIA${T}ok" <<< "$OUT" && grep -qx "AFTERBOOT${T}first${T}" <<< "$OUT" && grep -qx "SETTING${T}devices${T}auto" <<< "$OUT"'
check A3 'python3 -c "import json,sys; d=json.load(open(sys.argv[1])); g=d[\"last_good\"]; assert g[\"checksum\"]==\"aaa\" and len(g[\"devices\"])==6 and g[\"packages\"][\"Graphics driver (NVIDIA)\"]==\"580.95\"" "$ST" && [ "$(stat -c %a "$(dirname "$ST")")" = 700 ]'
OUT="$(AP check)"; RC=$?
check A4 '[ "$RC" -eq 0 ] && grep -qx "Drivers: up to date (they update by themselves with ForgeOS)." <<< "$OUT" && grep -qx "Devices: every important part has a driver." <<< "$OUT" && grep -q "^BIOS: version V1.05 from .* Acer doesn.t send BIOS updates to ForgeOS by itself.$" <<< "$OUT" && ! grep -q "over a year" <<< "$OUT"'
dmi "Acer" "Predator PHN18-72" "V1.02" "01/10/2022"
OUT="$(AP check)"; RC=$?
check A5 '[ "$RC" -eq 1 ] && grep -q "^BIOS: version V1.02 from January 2022\." <<< "$OUT" && grep -qx "Your BIOS is over a year old - Drivers & BIOS shows how to update it." <<< "$OUT"'
echo failed > "$WORK/uupd-result"
check A6 '[ "$(AP status | grep "^UPDATES")" = "UPDATES${T}failing" ] && AP check | grep -qx "Automatic updates are failing. Drivers & BIOS can fix that."'
echo disabled > "$WORK/uupd"
check A7 '[ "$(AP status | grep "^UPDATES")" = "UPDATES${T}off" ]'
rm -f "$WORK/uupd" "$WORK/uupd-result"
AP bogus >/dev/null 2>&1; R1=$?; AP set devices sometimes >/dev/null 2>&1; R2=$?; AP firmware nope >/dev/null 2>&1; R3=$?
check A8 '[ "$R1$R2$R3" = 333 ] && AP set devices ask | grep -qx "Device firmware: asks you first." && grep -qx "devices=ask" "$WORK/cfg/forgeos/autopilot.conf" && AP set devices auto >/dev/null'

# B: driver changes: a waiting version (db diff), only drivers shown, epochs dropped; db diff fails = no list
cat > "$WORK/dbdiff.json" <<'EOF'
{"ostree-commit-from": "aaa", "ostree-commit-to": "bbb", "pkgdiff": [
 ["kernel", 2, {"PreviousPackage": ["kernel", "6.17.1-200.fc44", "x86_64"], "NewPackage": ["kernel", "6.17.4-200.fc44", "x86_64"]}],
 ["kernel-core", 2, {"PreviousPackage": ["kernel-core", "6.17.1-200.fc44", "x86_64"], "NewPackage": ["kernel-core", "6.17.4-200.fc44", "x86_64"]}],
 ["nvidia-driver", 2, {"PreviousPackage": ["nvidia-driver", "3:580.95-1.fc44", "x86_64"], "NewPackage": ["nvidia-driver", "3:590.12-1.fc44", "x86_64"]}],
 ["bluez", 0, {"NewPackage": ["bluez", "5.83-1.fc44", "x86_64"]}],
 ["bash", 2, {"PreviousPackage": ["bash", "5.3-1.fc44", "x86_64"], "NewPackage": ["bash", "5.3-2.fc44", "x86_64"]}]],
 "advisories": [["FEDORA-2026-a1", 1, 2, [], {}], ["FEDORA-2026-b2", 1, 3, [], {}], ["FEDORA-2026-c3", 1, 2, [], {}]]}
EOF
os aaa bbb; dmi "Acer" "Predator PHN18-72" "V1.05" "$RECENT"
OUT="$(AP drivers)"; RC=$?
check B1 '[ "$RC" -eq 2 ] && grep -qx "New drivers are ready: Core drivers (Linux kernel) 6.17.1 to 6.17.4, Graphics driver (NVIDIA) 580.95 to 590.12, Bluetooth 5.83 (new), 3 security fixes." <<< "$OUT" && ! grep -q bash <<< "$OUT"'
check B2 'grep -qx "DRIVER${T}Graphics driver (NVIDIA)${T}580.95" <<< "$OUT" && grep -qx "DRIVER${T}Sound${T}1.4.8" <<< "$OUT" && grep -q "^DRIVERS${T}waiting${T}Core drivers" <<< "$(AP status)" && [ "$(AP check >/dev/null; echo $?)" = 2 ]'
mv "$WORK/dbdiff.json" "$WORK/dbdiff.off"
OUT="$(AP drivers)"; OUT2="$(AP check)"
check B3 'grep -qx "New drivers are ready: fixes and improvements." <<< "$OUT" && grep -q "^New drivers are ready (fixes and improvements)" <<< "$OUT2"'
os aaa; echo '{"deployments": []}' > "$WORK/os.json"
OUT="$(AP drivers)"; RC=$?
check B4 '[ "$RC" -eq 3 ] && grep -qx "Could not read the system version (rpm-ostree)." <<< "$OUT"'
os aaa

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
