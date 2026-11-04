# shellcheck shell=bash
# Fake PC for the Moving Day tests (Job 14). Sourced by tests/test-movingday*.sh.
# Drives are folders under $WORK/disks; fake lsblk (JSON from $WORK/lsblk.json, FSTYPE-/PARTTYPE- files),
# mount/umount/mountpoint, cryptsetup (BitLocker key in $WORK/bitlk-key), pkexec, forgeos-undo, forgeos-guard,
# systemd-run, systemctl, wl-copy, flatpak, setsid, dbus-send. Fakes log their name + arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/disks" "$WORK/mnt" "$WORK/mapper"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
SYS="$ROOT/files/system"
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" FORGEOS_MD_TEST=1
export FORGEOS_MD_LIB="$SYS/usr/lib/forgeos-movingday" FORGEOS_MD_SHARE="$SYS/usr/share/forgeos/movingday"
export FORGEOS_MD_MOUNT="$SYS/usr/libexec/forgeos-movingday-mount" FORGEOS_MD_MNT="$WORK/mnt" FORGEOS_MD_MAPPER="$WORK/mapper"
export FORGEOS_MD_PKEXEC="$WORK/bin/pkexec" FORGEOS_MD_BRAVE="$WORK/home/brave" FORGEOS_WIR_LISTS="$SYS/usr/share/forgeos/willitrun"
export FORGEOS_MD_SCREENS="$SYS/usr/libexec/forgeos-movingday-screens" FORGEOS_MD_WIR="$WORK/bin/forgeos-willitrun"
ENGINE="$SYS/usr/bin/forgeos-movingday"
GUI="$SYS/usr/bin/forgeos-movingday-gui"
MD() { python3 -B "$ENGINE" "$@"; }
T=$'\t'
NL=$'\n'
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/md-engine"
chmod +x "$WORK/bin/md-engine"
export FORGEOS_MD_ENGINE="$WORK/bin/md-engine"

fake pkexec '[ -f "$WORK/pk-rc" ] && exit "$(cat "$WORK/pk-rc")"; PKEXEC_UID="$(id -u)" exec "$@"'
fake lsblk 'case "$1" in
  -J) cat "$WORK/lsblk.json" 2>/dev/null || echo "{\"blockdevices\": []}" ;;
  -no) cat "$WORK/$2-${3##*/}" 2>/dev/null ;;
esac'
fake mount 'dev="$5"; dir="$6"; base="${dev##*/}"
[ -d "$WORK/disks/$base" ] || exit 32
rmdir "$dir" && ln -s "$WORK/disks/$base" "$dir"'
fake umount 'rm -f "$1"'
fake mountpoint '[ -L "$2" ]'
fake cryptsetup 'case "$1" in
  open) key="$(cat)"; [ "$key" = "$(cat "$WORK/bitlk-key")" ] || exit 2
        map="${*: -1}"; dev="${*: -2:1}"; touch "$WORK/mapper/$map"; echo ntfs > "$WORK/FSTYPE-$map"
        ln -sfn "$WORK/disks/${dev##*/}-inside" "$WORK/disks/$map" ;;
  close) rm -f "$WORK/mapper/$2" ;;
esac'
fake forgeos-undo 'exit "$(cat "$WORK/undo-rc" 2>/dev/null || echo 0)"'
fake forgeos-guard 'shift; for f in "$@"; do case "$f" in *eicar*) printf "VIRUS\t%s\tEicar-Test-Signature\t1\n" "$f"; rm -f "$f" ;; *) printf "CLEAN\t%s\n" "$f" ;; esac; done'
fake forgeos-willitrun 'exit 0'
fake systemd-run 'exit 0'
fake systemctl 'exit 0'
fake wl-copy 'exit 0'
fake flatpak 'exit 0'
fake setsid 'exit 0'
fake dbus-send 'exit 0'

# lsblk_json 'JSON list of devices' (a disk with partitions as children).
lsblk_json() { printf '{"blockdevices": [%s]}\n' "$1" > "$WORK/lsblk.json"; }
part() { # part PATH FSTYPE SIZE LABEL MOUNTPOINT [PARTTYPE] -> one partition (JSON)
  printf '{"path": "%s", "fstype": "%s", "size": "%s", "label": "%s", "mountpoint": %s, "parttype": "%s", "type": "part"}' \
    "$1" "$2" "$3" "$4" "$([ -n "$5" ] && printf '"%s"' "$5" || echo null)" "${6:-ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}"
  echo "$2" > "$WORK/FSTYPE-${1##*/}"; echo "${6:-ebd0a0a2-b9e5-4433-87c0-68b6b72699c7}" > "$WORK/PARTTYPE-${1##*/}"
}
disk() { printf '{"path": "%s", "type": "disk", "tran": "%s", "rm": false, "fstype": null, "children": [%s]}' "$1" "$2" "$3"; }

# shellcheck source=tests/movingday-tree.sh
. "$ROOT/tests/movingday-tree.sh"
