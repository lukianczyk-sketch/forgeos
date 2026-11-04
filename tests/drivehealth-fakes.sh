# shellcheck shell=bash
# Fake PC for the Drive Health tests (Job 15). Sourced by tests/test-drivehealth*.sh.
# Fake smartctl, lsblk, btrfs, pkexec and desktop tools. Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/smart" "$WORK/parent" "$WORK/sys/class/power_supply" "$WORK/pika"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
export FORGEOS_DH_LIB="$ROOT/files/system/usr/lib/forgeos-drivehealth" FORGEOS_DH_VAR="$WORK/var"
export FORGEOS_DH_SYS="$WORK/sys" FORGEOS_DH_PIKA="$WORK/pika" FORGEOS_DH_ROOT=1 FORGEOS_DH_LOAD=0.2
export FORGEOS_DH_FS="/var/home" FORGEOS_DH_CHECKER="$ROOT/files/system/usr/libexec/forgeos-drivehealth-check"
ENGINE="$ROOT/files/system/usr/bin/forgeos-drivehealth"
GUI="$ROOT/files/system/usr/bin/forgeos-drivehealth-gui"
DH() { python3 -B "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
REP="$WORK/var/report.json"
HIS="$WORK/var/history.json"
DAYS=0
# git keeps the scripts without the "run" bit, so they are started through small wrappers.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-drivehealth"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/dh-gui"
chmod +x "$WORK/bin/forgeos-drivehealth" "$WORK/bin/dh-gui"
export FORGEOS_DH_ENGINE="$WORK/bin/forgeos-drivehealth" FORGEOS_DH_GUI="$WORK/bin/dh-gui"
# day N: move the clock N days ahead of the real one (the history needs days to pass)
day() { DAYS="$1"; FORGEOS_DH_NOW="$(python3 -c "import time,sys; print(time.time() + float(sys.argv[1]) * 86400)" "$1")"; export FORGEOS_DH_NOW; }
day 0

# drives DEV:SIZE:TRAN:ROTA:MODEL... = what lsblk lists. smart NAME key=value... = that drive's health report.
drives() { python3 -B "$ROOT/tests/drivehealth-make.py" lsblk "$WORK/lsblk.json" "$@"; }
smart() { local n="$1"; shift; python3 -B "$ROOT/tests/drivehealth-make.py" smart "$WORK/smart/$n.json" "$@"; }
# power AC-ONLINE: a laptop with the charger in (1) or out (0); power - = a desktop (no battery)
power() {
  rm -rf "$WORK/sys/class/power_supply"; mkdir -p "$WORK/sys/class/power_supply"
  [ "$1" = - ] && return 0
  mkdir -p "$WORK/sys/class/power_supply/AC" "$WORK/sys/class/power_supply/BAT0"
  echo Mains > "$WORK/sys/class/power_supply/AC/type"; echo "$1" > "$WORK/sys/class/power_supply/AC/online"
  echo Battery > "$WORK/sys/class/power_supply/BAT0/type"
}
# backup none|set [DAYS-OLD]: Pika Backup not set up / set up, last backup DAYS-OLD days before the clock
backup() {
  rm -f "$WORK/pika/backup.json" "$WORK/pika/histories.json"
  [ "$1" = none ] && return 0
  echo '[{"id": "b1"}]' > "$WORK/pika/backup.json"
  [ -n "${2:-}" ] && { echo '{}' > "$WORK/pika/histories.json"
    touch -d "@$(python3 -c "import sys; print(int(float(sys.argv[1]) - float(sys.argv[2]) * 86400))" "$FORGEOS_DH_NOW" "$2")" "$WORK/pika/histories.json"; }
  return 0
}

fake smartctl 'dev="${*: -1}"; n="${dev##*/}"
[ "$1" = -t ] && exit "$(cat "$WORK/smart/$n.trc" 2>/dev/null || echo 0)"
[ -f "$WORK/smart/$n.json" ] || { echo "{\"smartctl\": {\"exit_status\": 2}}"; exit 2; }
cat "$WORK/smart/$n.json"; exit "$(cat "$WORK/smart/$n.rc" 2>/dev/null || echo 0)"'
fake lsblk 'case " $* " in
  *" -d "*) cat "$WORK/lsblk.json" ;;
  *" -s "*) p="${*: -1}"; d="$(cat "$WORK/parent/${p##*/}" 2>/dev/null)"
    printf "{\"blockdevices\": [{\"path\": \"%s\", \"type\": \"part\", \"children\": [{\"path\": \"%s\", \"type\": \"crypt\", \"children\": [{\"path\": \"%s\", \"type\": \"disk\"}]}]}]}\n" "$p" "$p-luks" "${d:-/dev/none}" ;;
esac'
fake btrfs 'case "$1 $2" in
  "device stats") cat "$WORK/btrfs-stats" 2>/dev/null; exit "$(cat "$WORK/btrfs-stats.rc" 2>/dev/null || echo 0)" ;;
  "scrub status") cat "$WORK/btrfs-scrub" 2>/dev/null ;;
esac'
# btrfs_errs PART READ CORRUPT [UNFIXED]: the file system's error counts for one partition
btrfs_errs() {
  printf '[%s].write_io_errs    0\n[%s].read_io_errs     %s\n[%s].flush_io_errs    0\n[%s].corruption_errs  %s\n[%s].generation_errs  0\n' \
    "$1" "$1" "$2" "$1" "$1" "$3" "$1" > "$WORK/btrfs-stats"
  printf 'UUID: x\ndata_extents_scrubbed: 10\ncorrected_errs: 0\nuncorrectable_errs: %s\n' "${4:-0}" > "$WORK/btrfs-scrub"
}
fake pkexec '[ -e "$WORK/pkexec-no" ] && exit 126; FORGEOS_DH_ROOT=1 exec bash "$@"'
fake notify-send 'cat "$WORK/notify-answer" 2>/dev/null; exit 0'
fake kdialog 'exit "$(cat "$WORK/kdialog-rc" 2>/dev/null || echo 1)"'
fake busctl 'cat "$WORK/busctl-out" 2>/dev/null || echo "b false"'
fake gamemoded 'echo "gamemode is inactive"'
fake pgrep '[ -e "$WORK/gamescope" ]'
calls() { cat "$WORK/calls.log" 2>/dev/null; }
# py EXPR: print a value from the saved report (r) or history (h)
py() { python3 -c "import json,sys; r=json.load(open(sys.argv[1])); h=json.load(open(sys.argv[2])) if sys.argv[3]=='1' else {}; print($1)" "$REP" "$HIS" "$([ -f "$HIS" ] && echo 1 || echo 0)"; }

# A normal desktop: a Samsung NVMe SSD (2 years old) and a WD hard drive, both healthy, no errors.
normal_pc() {
  rm -f "$WORK/smart/"* "$WORK/btrfs-stats" "$WORK/btrfs-scrub"; power -
  drives "/dev/nvme0n1:1000204886016:nvme:0:Samsung SSD 990 PRO 1TB" "/dev/sda:4000787030016:sata:1:WDC WD40EZAX"
  smart nvme0n1 kind=nvme "model=Samsung SSD 990 PRO 1TB" serial=S6Z1NJ0SECRET worn=3 hours=17532 temp=41
  smart sda kind=hdd "model=WDC WD40EZAX-22C8UB0" serial=WD-SECRET2 hours=26300 temp=35
  echo /dev/nvme0n1 > "$WORK/parent/nvme0n1p3"; btrfs_errs /dev/nvme0n1p3 0 0
}
