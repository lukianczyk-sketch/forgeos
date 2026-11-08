# shellcheck shell=bash
# Fake PC for the Digital Will tests (Job 18). Sourced by tests/test-digitalwill*.sh.
# Robert's home, a pretend list of drives (lsblk: a locked system drive + a USB stick), and fake pkexec,
# unix_chkpwd, notify-send, xdg-open and kdialog. 7-Zip is REAL (the envelope is really locked and opened).
# Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Documents" "$WORK/home/Pictures/Trip" "$WORK/run" "$WORK/media/robert/STICK"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
H="$WORK/home"
export WORK HOME="$H" XDG_STATE_HOME="$WORK/state" XDG_DATA_HOME="$WORK/data" XDG_RUNTIME_DIR="$WORK/run"
export PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1 FORGEOS_WILL_USER=robert FORGEOS_WILL_FULLNAME="Robert L"
SYS="$ROOT/files/system"
export FORGEOS_WILL_LIB="$SYS/usr/lib/forgeos-digitalwill" FORGEOS_WILL_SHARE="$SYS/usr/share/forgeos/digitalwill"
export FORGEOS_WILL_MEDIA="$WORK/media" FORGEOS_WILL_VAR="$WORK/var" FORGEOS_WILL_CHKPWD="$WORK/bin/unix_chkpwd"
export FORGEOS_WILL_UNLOCK="$SYS/usr/libexec/forgeos-digitalwill-unlock" FORGEOS_WILL_GUI="$WORK/bin/dw-gui"
export FORGEOS_WILL_SCREENS="$SYS/usr/libexec"
ENGINE="$SYS/usr/bin/forgeos-digitalwill"
GUI="$SYS/usr/bin/forgeos-digitalwill-gui"
DW() { FORGEOS_WILL_ROOT=0 python3 -B "$ENGINE" "$@"; }  # as Robert (not root)
T=$'\t'  # a tab, for checking the tab-separated lines
STICK="$WORK/media/robert/STICK"
BOX="$H/Documents/ForgeOS Emergency Envelope"
# git keeps the scripts without the "run" bit, so they are started through small wrappers.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-digitalwill"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/dw-gui"
chmod +x "$WORK/bin/forgeos-digitalwill" "$WORK/bin/dw-gui"
export FORGEOS_WILL_ENGINE="$WORK/bin/forgeos-digitalwill"
fake lsblk 'cat "$WORK/lsblk.json" 2>/dev/null || echo "{\"blockdevices\": []}"'
fake pkexec '[ -e "$WORK/pkexec-no" ] && exit 126; FORGEOS_WILL_ROOT=1 exec bash "$@"'
fake unix_chkpwd 'IFS= read -r -d "" pw; [ "$1" = robert ] && [ "$pw" = "right sign-in" ]'
fake notify-send '[ -e "$WORK/note-go" ] && echo go; exit 0'
fake xdg-open 'exit 0'
fake kdialog 'case " $* " in *" --passivepopup "*) exit 0 ;; esac
printf "%s\n" "$*" >> "$WORK/shown"
a="$(head -n 1 "$WORK/kd-answers" 2>/dev/null)"; sed -i 1d "$WORK/kd-answers" 2>/dev/null
case "$a" in rc1) exit 1 ;; "") exit 0 ;; *) printf "%b\n" "$a" ;; esac'
calls() { cat "$WORK/calls.log" 2>/dev/null; }
echo "pretend photo" > "$H/Pictures/Trip/beach.jpg"
echo "pretend password safe" > "$H/Documents/Passwords.kdbx"
# drives KIND: none = nothing locked, no stick; stick = a USB stick; luks = + a locked system drive ($WORK/disk.img)
drives() {
  local kids="" luks=""
  [ "$1" = luks ] && luks='{"path": "'"$WORK"'/disk.img", "fstype": "crypto_LUKS", "type": "part", "rm": false, "hotplug": false, "label": null, "size": 9, "mountpoints": [null], "children": [{"path": "/dev/mapper/luks-1", "fstype": "btrfs", "type": "crypt", "rm": false, "hotplug": false, "label": "fedora", "size": 9, "mountpoints": ["/sysroot", "/var/home"]}]}'
  [ "$1" != none ] && kids=', {"path": "/dev/sdb", "fstype": null, "type": "disk", "rm": true, "hotplug": true, "label": null, "size": 9, "mountpoints": [null], "children": [{"path": "/dev/sdb1", "fstype": "vfat", "type": "part", "rm": true, "hotplug": true, "label": "STICK", "size": 9, "mountpoints": ["'"$STICK"'"]}]}'
  printf '{"blockdevices": [{"path": "/dev/nvme0n1", "fstype": null, "type": "disk", "rm": false, "hotplug": false, "label": null, "size": 9, "mountpoints": [null], "children": [%s]}%s]}\n' "$luks" "$kids" > "$WORK/lsblk.json"
}
# A normal set of answers: two trusted people, three accounts, the password safe, Pictures, a letter, a note
answers() {
  DW person add Brianna 555-0101 && DW person add "Kasia" && DW account set bank give Brianna "Papers in the desk" \
    && DW account set facebook memorial && DW account other "Church site" close && DW safe "$H/Documents/Passwords.kdbx" \
    && DW folders "$H/Pictures" && printf 'Dear Brianna,\nThank you.' | DW letter Brianna && echo "Simple service, please." | DW note
}
b64() { printf '%s %s\n' "$1" "$(printf '%s' "$2" | base64 -w0)"; }
# secrets LOGIN SAFE EXTRA DISK -> the lines 'make' reads on stdin
secrets() { b64 login "$1"; b64 safe "$2"; b64 extra "$3"; b64 disk "${4:-}"; }
st() { python3 -c "import json,sys; s=json.load(open(sys.argv[1])); print($1)" "$WORK/state/forgeos/will/state.json"; }
# open ENVELOPE CODE -> unpacks into $WORK/open
open_env() { rm -rf "$WORK/open"; mkdir -p "$WORK/open"; printf '%s\n' "$2" | 7z x -y -o"$WORK/open" -- "$1" > /dev/null 2>&1; }
fresh() { rm -rf "${WORK:?}/state" "${WORK:?}/data" "${WORK:?}/var" "$BOX" "$STICK/ForgeOS Emergency Envelope" "$WORK/run/forgeos-digitalwill" "$WORK/calls.log" "$WORK/kd-answers" "$WORK/shown" "$WORK/note-go" "$WORK/pkexec-no"; drives stick; }
