# shellcheck shell=bash
# Fake PC for the Install & Switch tests (Job 13e). Sourced by tests/test-switch*.sh.
# Fake efibootmgr (start-up list from $WORK/efi.txt), lsblk + mount/umount (Windows drives are folders
# under $WORK/disks), pkexec, busctl, konsole, kdialog. Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Desktop" "$WORK/disks" "$WORK/mnt" "$WORK/efi"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" FORGEOS_SWITCH_TEST=1
SYS="$ROOT/files/system"
export FORGEOS_SWITCH_BOOT="$SYS/usr/libexec/forgeos-switch-boot" FORGEOS_SWITCH_WINSETUP="$SYS/usr/libexec/forgeos-switch-winsetup"
export FORGEOS_SWITCH_SRC="$SYS/usr/share/forgeos/switch" FORGEOS_SWITCH_MNT="$WORK/mnt" FORGEOS_SWITCH_EFI="$WORK/efi"
export FORGEOS_SWITCH_APPS="$SYS/usr/share/applications" FORGEOS_SWITCH_GUI="$WORK/bin/sw-gui" FORGEOS_SWITCH_PKEXEC="$WORK/bin/pkexec"
ENGINE="$SYS/usr/bin/forgeos-switch"
GUI="$SYS/usr/bin/forgeos-switch-gui"
SW() { bash "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$ENGINE" > "$WORK/bin/sw-engine"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/sw-gui"
chmod +x "$WORK/bin/sw-engine" "$WORK/bin/sw-gui"
export FORGEOS_SWITCH_ENGINE="$WORK/bin/sw-engine"

# --- the start-up list (efibootmgr 18 style: a TAB before the device path) ---
efi_list() { # efi_list "0000 Windows Boot Manager" "0001 Fedora" ...
  { printf 'BootCurrent: 0001\nTimeout: 0 seconds\nBootOrder: 0001,0000\n'
    local e; for e in "$@"; do printf 'Boot%s* %s\tHD(1,GPT,abcd,0x800,0x32000)/\\EFI\\x.efi\n' "${e%% *}" "${e#* }"; done; } > "$WORK/efi.txt"
}
fake efibootmgr 'case "${1:-}" in
  -n) echo "$2" > "$WORK/bootnext"; exit "$(cat "$WORK/efi-rc" 2>/dev/null || echo 0)" ;;
  -N) rm -f "$WORK/bootnext"; exit 0 ;;
  -v) cat "$WORK/efi-v.txt" 2>/dev/null || cat "$WORK/efi.txt" ;;
  *) awk -v n="$(cat "$WORK/bootnext" 2>/dev/null)" '\''NR == 2 && n != "" {print "BootNext: " n} {print}'\'' "$WORK/efi.txt" ;;
esac'
fake pkexec '[ -f "$WORK/pk-rc" ] && exit "$(cat "$WORK/pk-rc")"; exec "$@"'

# --- drives: windows_disk NAME [locked|dirty|nowin] makes /dev/NAME; lsblk lists $WORK/lsblk.txt ---
windows_disk() {
  local d="$WORK/disks/$1"
  case "${2:-}" in
    locked) echo "/dev/$1 BitLocker " >> "$WORK/lsblk.txt"; return 0 ;;
    dirty) touch "$WORK/dirty-$1" ;;
  esac
  mkdir -p "$d/Users/Public"
  [ "${2:-}" = nowin ] || mkdir -p "$d/Windows/System32"
  echo "/dev/$1 ntfs " >> "$WORK/lsblk.txt"
}
fake lsblk 'cat "$WORK/lsblk.txt" 2>/dev/null; echo "/dev/nvme0n1p3 btrfs /"'
fake mount 'opts="$4"; dev="$5"; dir="$6"; base="${dev##*/}"
[ -d "$WORK/disks/$base" ] || exit 32
case "$opts" in rw*) [ -f "$WORK/dirty-$base" ] && exit 32 ;; esac
rmdir "$dir" && ln -s "$WORK/disks/$base" "$dir"'
fake umount 'rm -f "$1"; mkdir -p "$1"'
fake sync 'exit 0'
fake busctl 'exit "$(cat "$WORK/busctl-rc" 2>/dev/null || echo 0)"'
fake konsole 'exit 0'
fake xdg-user-dir 'echo "$HOME/Desktop"'
fake kdialog 'exit 0'
# Wait (up to 5 s) until calls.log has N lines matching $1 (programs started in the background).
calls_wait() { local i; for i in $(seq 1 20); do [ "$(grep -c -- "$1" "$WORK/calls.log" 2>/dev/null)" -ge "${2:-1}" ] && return 0; sleep 0.25; done; return 1; }
