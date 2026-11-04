#!/usr/bin/env bash
# Tests for Moving Day (Job 14), cases A-C: finding the old drives, opening them READ-ONLY (BitLocker with
# the recovery key), and what a scan finds on a Windows drive.
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-movingday.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/movingday-fakes.sh
. "$ROOT/tests/movingday-fakes.sh"
H="$FORGEOS_MD_MOUNT"

# A: find - Windows drive (closed), BitLocker drive, a USB stick with a Moving Box, the start-up partition and
# ForgeOS's own drive are left out
win_tree "$WORK/disks/sda3"; mkdir -p "$WORK/disks/sdb1-inside/Users/Ann/Documents" "$WORK/stick/ForgeOS Moving Box"
echo '{}' > "$WORK/stick/ForgeOS Moving Box/box.json"
lsblk_json "$(disk /dev/sda sata "$(part /dev/sda1 vfat 100M "" "" c12a7328-f81f-11d2-ba4b-00a0c93ec93b),$(part /dev/sda3 ntfs 475.9G Windows "")"),
$(disk /dev/sdb usb "$(part /dev/sdb1 BitLocker 931.5G Backup "")"),$(disk /dev/sdc usb "$(part /dev/sdc1 exfat 58G STICK "$WORK/stick")"),
$(disk /dev/nvme0n1 nvme "$(part /dev/nvme0n1p3 btrfs 1.8T "" /)")"
OUT="$(MD find)"; R=$?
check A1 '[ "$R" = 0 ] && [ "$(grep -c "^SOURCE" <<< "$OUT")" = 3 ] && grep -q "^SOURCE${T}/dev/sda3${T}drive${T}closed${T}-${T}Windows${T}475.9G${T}no${T}Drive \"Windows\" (475.9G) - not opened yet$" <<< "$OUT"'
check A2 'grep -q "^SOURCE${T}/dev/sdb1${T}drive${T}locked${T}-${T}Backup${T}931.5G${T}yes${T}USB Drive \"Backup\" (931.5G) - locked with BitLocker$" <<< "$OUT" && grep -q "^SOURCE${T}/dev/sdc1${T}box${T}open${T}$WORK/stick${T}STICK${T}58G${T}yes${T}Moving Box \"STICK\" (58G)$" <<< "$OUT" && ! grep -q "sda1\|nvme" <<< "$OUT"'
lsblk_json ""; OUT="$(MD find)"; R=$?
check A3 '[ "$R" = 1 ] && [ -z "$OUT" ]'

# B: open + close through the root helper: read-only mount options, BitLocker key from stdin, wrong key, refusals
lsblk_json "$(disk /dev/sda sata "$(part /dev/sda1 vfat 100M "" "" c12a7328-f81f-11d2-ba4b-00a0c93ec93b),$(part /dev/sda3 ntfs 475.9G Windows "")")"
OUT="$(MD open /dev/sda3)"; R=$?
check B1 '[ "$R" = 0 ] && [ "$OUT" = "OPEN${T}/dev/sda3${T}$WORK/mnt/sda3" ] && [ -d "$WORK/mnt/sda3/Users/Robert" ] && grep -q "^mount -t ntfs3 -o ro,nosuid,nodev,noexec,uid=$(id -u),gid=$(id -g),umask=077 /dev/sda3 $WORK/mnt/sda3$" "$WORK/calls.log"'
OUT="$(MD open /dev/sda3)"; R=$?; MD close /dev/sda3 >/dev/null; R2=$?
check B2 '[ "$R$R2" = 00 ] && [ "$(grep -c "^mount " "$WORK/calls.log")" = 1 ] && [ ! -e "$WORK/mnt/sda3" ]'
part /dev/sdb1 BitLocker 931.5G Backup "" > /dev/null; echo "111111-222222-333333-444444-555555-666666-777777-888888" > "$WORK/bitlk-key"
OUT="$(MD open /dev/sdb1 2>&1)"; R1=$?
OUT2="$(echo "000000-000000-000000-000000-000000-000000-000000-000000" | MD open /dev/sdb1 --key-stdin 2>&1)"; R2=$?
check B3 '[ "$R1" = 5 ] && grep -q "locked with BitLocker" <<< "$OUT" && [ "$R2" = 6 ] && grep -q "did not open the drive" <<< "$OUT2" && [ ! -e "$WORK/mapper/forgeos-md-sdb1" ]'
OUT="$(echo " 111111-222222-333333-444444-555555-666666-777777-888888 " | MD open /dev/sdb1 --key-stdin)"; R=$?
check B4 '[ "$R" = 0 ] && [ "$OUT" = "OPEN${T}/dev/sdb1${T}$WORK/mnt/sdb1" ] && grep -q "^cryptsetup open --type bitlk --readonly --key-file=- /dev/sdb1 forgeos-md-sdb1$" "$WORK/calls.log" && grep -q "^mount -t ntfs3 -o ro,.* $WORK/mapper/forgeos-md-sdb1 $WORK/mnt/sdb1$" "$WORK/calls.log" && [ -d "$WORK/mnt/sdb1/Users/Ann" ]'
MD close /dev/sdb1 >/dev/null
check B5 '[ ! -e "$WORK/mapper/forgeos-md-sdb1" ] && grep -q "^cryptsetup close forgeos-md-sdb1$" "$WORK/calls.log"'
OUT="$(MD open /dev/sda1 2>&1)"; R1=$?; bash "$H" open "/dev/../etc/x" 2>/dev/null; R2=$?; bash "$H" open /dev/sda3 --x 2>/dev/null; R3=$?
echo 1 > "$WORK/pk-rc"; OUT2="$(MD open /dev/sda3 2>&1)"; R4=$?; rm "$WORK/pk-rc"; env -u FORGEOS_MD_TEST bash "$H" open /dev/sda3 2>/dev/null; R5=$?
check B6 '[ "$R1$R2$R3" = 133 ] && [ "$R5" != 0 ] && grep -q "start-up partition" <<< "$OUT" && [ "$R4" = 1 ] && [ "$(grep -c "^mount " "$WORK/calls.log")" = 2 ]'

# C: scan - the user Robert (Public + Default left out), folder sizes without junk, links and the password file
OUT="$(MD scan "$WORK/disks/sda3")"; R=$?
check C1 '[ "$R" = 0 ] && grep -qx "ROOT${T}windows${T}$WORK/disks/sda3" <<< "$OUT" && grep -qx "USER${T}Robert${T}34${T}6" <<< "$OUT" && [ "$(grep -c "^USER" <<< "$OUT")" = 1 ]'
check C2 'grep -qx "ITEM${T}Robert${T}files:Documents${T}19${T}3" <<< "$OUT" && grep -qx "ITEM${T}Robert${T}files:Downloads${T}6${T}1" <<< "$OUT" && grep -qx "ITEM${T}Robert${T}files:Desktop${T}0${T}0" <<< "$OUT"'
check C3 'grep -qx "ITEM${T}Robert${T}bookmarks${T}0${T}2${T}Chrome, Firefox" <<< "$OUT" && grep -qx "ITEM${T}Robert${T}passwords${T}0${T}1${T}2" <<< "$OUT" && grep -qx "ITEM${T}Robert${T}programs${T}0${T}3" <<< "$OUT"'
OUT="$(MD scan "$WORK/nothing" 2>&1)"; R1=$?; mkdir -p "$WORK/empty"; MD scan "$WORK/empty" >/dev/null; R2=$?; MD scan 2>/dev/null; R3=$?
check C4 '[ "$R1$R2$R3" = 313 ]'

echo "----"
if [ "$failures" -eq 0 ]; then echo "ALL PASS"; else echo "$failures FAILED"; exit 1; fi
