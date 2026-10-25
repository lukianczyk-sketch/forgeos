#!/usr/bin/env bash
# tests/test-undo-real.sh — Job 5 Step 5: cases U-Y on a REAL btrfs disk with
# real snapper (CI only: needs root, snapper, btrfs-progs). A 1 GB disk image is
# mounted at /var/home; it refuses to run if /var/home already exists.
set -uo pipefail

ROOT="$(cd "${1:-.}" && pwd)"
B="$ROOT/files/system/usr"
failures=0
pass() { echo "PASS: $1"; }
fail() { echo "FAIL: $1"; failures=$((failures + 1)); }

[ "$(id -u)" -eq 0 ] || { echo "SKIP: needs root"; exit 0; }
command -v snapper >/dev/null && command -v mkfs.btrfs >/dev/null || { echo "FAIL: install snapper btrfs-progs"; exit 1; }
[ -e /var/home ] && { echo "FAIL: /var/home already exists — refusing to touch it"; exit 1; }
snapper --no-dbus -c root get-config >/dev/null 2>&1 && { echo "FAIL: a snapper config 'root' already exists"; exit 1; }

WORK="$(mktemp -d)"
made_wheel=0   # Ubuntu has no wheel group (Fedora/Bazzite do); setup needs it
getent group wheel >/dev/null || { groupadd wheel && made_wheel=1; }
cleanup() {
  snapper --no-dbus -c root delete-config >/dev/null 2>&1; pkill -x snapperd 2>/dev/null
  umount /var/home 2>/dev/null; rmdir /var/home 2>/dev/null; rm -rf "$WORK"
  [ "$made_wheel" -eq 1 ] && groupdel wheel
}
trap cleanup EXIT
truncate -s 1G "$WORK/disk.img"
mkfs.btrfs -q "$WORK/disk.img" && mkdir /var/home && mount -o loop "$WORK/disk.img" /var/home \
  || { echo "FAIL: could not make the test disk"; exit 1; }
export FORGEOS_UNDO_HOME=/var/home FORGEOS_UNDO_MARKER="$WORK/done"
U="$B/bin/forgeos-undo"

# U: first-boot setup -> config "root" for /var/home with the safe limits
bash "$B/libexec/forgeos-undo-setup" > "$WORK/out" 2>&1; rc=$?
cfg="$(snapper --no-dbus --csvout -c root get-config 2>/dev/null)"
if [ "$rc" -eq 0 ] && grep -q '^enabled' "$WORK/done" && grep -qx 'SUBVOLUME,/var/home' <<< "$cfg" \
   && grep -qx 'FREE_LIMIT,0.2' <<< "$cfg" && grep -qx 'TIMELINE_LIMIT_HOURLY,1-12' <<< "$cfg"; then
  pass "U real setup"; else fail "U real setup (rc=$rc)"; cat "$WORK/out"; echo "$cfg"; fi
# A snapperd started before setup does not see the new config until it quits (~60 s idle).
pkill -x snapperd 2>/dev/null; sleep 1

# V: take a real snapshot, change the file, list + restore the old version
mkdir -p /var/home/bob && echo v1 > /var/home/bob/doc.txt
snapper --no-dbus -c root create -c number -d "test one" || fail "V snapper create"
echo v2 > /var/home/bob/doc.txt
vers="$(bash "$U" versions /var/home/bob/doc.txt)"; v1=$?
n="$(cut -f1 <<< "$vers" | head -n 1)"
dest="$(bash "$U" restore "$n" /var/home/bob/doc.txt)"; v2=$?
if [ "$v1" -eq 0 ] && grep -q $'\ttest one\tfile$' <<< "$vers" && [ "$v2" -eq 0 ] \
   && [ "$(cat "$dest")" = v1 ] && [ "$(cat /var/home/bob/doc.txt)" = v2 ]; then
  pass "V real versions + restore"; else fail "V (rcs=$v1/$v2 vers=$vers dest=$dest)"; fi

# W: deleted file -> back under its old name
rm /var/home/bob/doc.txt
dest="$(bash "$U" restore "$n" /var/home/bob/doc.txt)"
if [ "$dest" = /var/home/bob/doc.txt ] && [ "$(cat "$dest")" = v1 ]; then
  pass "W real deleted file"; else fail "W (dest=$dest)"; fi

# X: snapshot-now (snapper over D-Bus via snapperd) -> status shows 2
bash "$U" snapshot-now "test two" > "$WORK/out" 2>&1; x1=$?
st="$(bash "$U" status)"
if [ "$x1" -eq 0 ] && grep -q "ON — 2 snapshots" <<< "$st"; then
  pass "X real snapshot-now + status"; else fail "X (rc=$x1 $st)"; cat "$WORK/out"; fi

# Y: Clean Sweep Full Wipe Part 2b deletes every home snapshot for real
sed -n '/^wipe_snapshots_plan() {/,/^}/p' "$B/bin/forgeos-cleansweep" > "$WORK/wsp"
( export LOG_FILE="$WORK/wlog"; WIPE_ERRORS=0; WIPE_SNAPS=0
  log() { echo "$*"; }
  # shellcheck source=/dev/null
  . "$WORK/wsp"; wipe_snapshots_plan apply > "$WORK/out"
  echo "$WIPE_SNAPS $WIPE_ERRORS" > "$WORK/cnt" )
left="$(snapper --no-dbus --csvout -c root list --columns number | grep -cE '^[1-9]')"
if [ "$(cat "$WORK/cnt")" = "2 0" ] && [ "$left" -eq 0 ]; then
  pass "Y real wipe snapshots"; else fail "Y (cnt=$(cat "$WORK/cnt") left=$left)"; cat "$WORK/out" "$WORK/wlog"; fi

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
