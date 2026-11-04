#!/usr/bin/env bash
# Tests for Drive Death Warning (Job 15), cases D-F: USB drives (backup drive read through SAT, a USB box that
# hides the health, small sticks left out), the monthly self-test (idle + wall power only), "Check now" as a
# normal user (pkexec), no report yet, older SSD wear attributes, history size.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-drivehealth-more.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/drivehealth-fakes.sh
. "$ROOT/tests/drivehealth-fakes.sh"
tests_run() { grep -c "^smartctl -t short" "$WORK/calls.log" 2>/dev/null; }

# D: USB: a 2 TB backup drive is read through SAT, a USB box that hides health = "can't read", sticks left out
normal_pc
drives "/dev/nvme0n1:1000204886016:nvme:0:Samsung SSD 990 PRO 1TB" "/dev/sdb:2000398934016:usb:1:Elements 25A3" \
  "/dev/sdc:5000981078016:usb:1:Backup Plus" "/dev/sdd:32017047552:usb:0:Cruzer Blade" "/dev/zram0:8589934592::0:" \
  "/dev/loop0:104857600::0:" "/dev/mmcblk0boot0:4194304::0:"
smart sdb kind=hdd "model=WDC WD20SDRW-11VUUS0" serial=WX-SECRET temp=33
: > "$WORK/calls.log"
DH system-check --timer >/dev/null; RC=$?
OUT="$(DH status)"
check D1 '[ "$RC" -eq 0 ] && calls | grep -qx "smartctl -j -a -l devstat -d sat /dev/sdb" && grep -q "^DRIVE${T}.*${T}good${T}WDC WD20SDRW-11VUUS0${T}hard drive${T}2 TB${T}-${T}.*${T}/dev/sdb${T}yes$" <<< "$OUT"'
check D2 'grep -q "^DRIVE${T}.*${T}unknown${T}Backup Plus${T}USB drive${T}5 TB${T}-${T}-${T}-${T}/dev/sdc${T}yes$" <<< "$OUT" && grep -q "^REASON${T}.*${T}Can.t read this drive.s health (some USB boxes hide it).$" <<< "$OUT"'
check D3 '! calls | grep -q "sdd\|zram\|loop\|mmcblk" && [ "$(grep -c "^DRIVE" <<< "$OUT")" = 3 ] && DH report | grep -qx "Backup Plus (USB drive, 5 TB): can.t read its health."'
check D4 'calls | grep -qx "smartctl -t short /dev/nvme0n1" && ! calls | grep -q "smartctl -t short /dev/sd[bc]"'
echo '{"blockdevices": []}' > "$WORK/lsblk.json"; DH system-check >/dev/null; RC=$?
check D5 '[ "$RC" -eq 0 ] && DH report | grep -qx "No drives with a health report were found."'

# E: the monthly self-test: only on wall power and when idle, again after 30 days
normal_pc; rm -f "$REP" "$HIS"; power 0; : > "$WORK/calls.log"
DH system-check --timer >/dev/null
check E1 '[ "$(tests_run)" = 0 ] && [ "$(py "r[\"selftest\"]")" = "[]" ]'
power 1; FORGEOS_DH_LOAD=3.5 DH system-check --timer >/dev/null
check E2 '[ "$(tests_run)" = 0 ]'
DH system-check >/dev/null
check E3 '[ "$(tests_run)" = 0 ]'
DH system-check --timer >/dev/null
check E4 '[ "$(tests_run)" = 2 ] && [ "$(py "r[\"selftest\"]")" = "['"'"'/dev/nvme0n1'"'"', '"'"'/dev/sda'"'"']" ]'
day 20; DH system-check --timer >/dev/null
check E5 '[ "$(tests_run)" = 2 ]'
echo 4 > "$WORK/smart/sda.trc"; day 31; DH system-check --timer >/dev/null
check E6 '[ "$(tests_run)" = 4 ] && [ "$(py "r[\"selftest\"]")" = "['"'"'/dev/nvme0n1'"'"']" ]'
day 32; DH system-check --timer >/dev/null
check E7 '[ "$(tests_run)" = 5 ] && calls | tail -n 1 | grep -qx "smartctl -t short /dev/sda"'
rm -f "$WORK/smart/sda.trc"; day 0

# F: "Check now" as a normal user goes through pkexec; refused = clear message; no report yet; old SSD wear
normal_pc; rm -f "$REP" "$HIS"
OUT="$(FORGEOS_DH_ROOT=0 FORGEOS_DH_PKEXEC=pkexec DH status)"; RC=$?
check F1 '[ "$RC" -eq 3 ] && grep -qx "CHECKED${T}never${T}-" <<< "$OUT" && DH report | grep -q "^Drive Health has not checked your drives yet."'
: > "$WORK/calls.log"
OUT="$(FORGEOS_DH_ROOT=0 DH check)"; RC=$?
check F2 '[ "$RC" -eq 0 ] && calls | grep -q "^pkexec .*forgeos-drivehealth-check$" && grep -q "Samsung SSD 990 PRO 1TB (NVMe SSD, 1 TB): Good" <<< "$OUT" && [ -f "$REP" ]'
touch "$WORK/pkexec-no"
OUT="$(FORGEOS_DH_ROOT=0 DH check)"; RC=$?
check F3 '[ "$RC" -eq 3 ] && [ "$OUT" = "Drive Health could not check the drives right now." ]'
rm -f "$WORK/pkexec-no"
OUT="$(bash "$FORGEOS_DH_CHECKER" extra 2>&1)"; RC=$?
check F4 '[ "$RC" -eq 3 ] && grep -q "^usage: forgeos-drivehealth-check" <<< "$OUT"'
drives "/dev/sda:512110190592:sata:0:Old SSD"
smart sda kind=ssd model=INTEL-SSDSC2 life=233:7; DH system-check >/dev/null; RC=$?
check F5 '[ "$RC" -eq 1 ] && DH status | grep -q "^DRIVE${T}.*${T}watch${T}INTEL-SSDSC2${T}SSD${T}512 GB${T}93${T}" && DH status | grep -q "about 93% worn out"'
smart sda kind=ssd model=Samsung-850 worn=12 life=177:40; DH system-check >/dev/null
check F6 'DH status | grep -q "^DRIVE${T}.*${T}good${T}Samsung-850${T}SSD${T}512 GB${T}12${T}"'
for i in $(seq 1 125); do day "$i"; DH system-check >/dev/null; done
check F7 '[ "$(py "max(len(v) for v in h[\"drives\"].values())")" = 120 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
