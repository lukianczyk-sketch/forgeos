# shellcheck shell=bash
# Fake PC for the Ransomware Tripwire tests (Job 16). Sourced by tests/test-tripwire*.sh.
# A pretend /var/home with Robert's folders, pretend running programs (/proc) and apps (cgroups),
# pretend Undo Button snapshots, and fake nmcli, snapper, pkexec and desktop tools.
# Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/homes/robert" "$WORK/proc" "$WORK/cg" "$WORK/var" "$WORK/run" "$WORK/media" "$WORK/state"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
[ "$(id -u)" = 0 ] && chown 1000:1000 "$WORK/homes/robert"
ME="$(stat -c %u "$WORK/homes/robert")"
H="$WORK/homes/robert"
export WORK HOME="$H" XDG_STATE_HOME="$WORK/state" XDG_DATA_HOME="$WORK/data" PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
export FORGEOS_TW_LIB="$ROOT/files/system/usr/lib/forgeos-tripwire" FORGEOS_TW_VAR="$WORK/var" FORGEOS_TW_RUN="$WORK/run"
export FORGEOS_TW_HOMES="$WORK/homes" FORGEOS_TW_MEDIA="$WORK/media" FORGEOS_TW_PROC="$WORK/proc" FORGEOS_TW_CGROUP="$WORK/cg"
export FORGEOS_TW_TRUSTED="$ROOT/files/system/etc/forgeos/tripwire-trusted.list" FORGEOS_TW_UID="$ME"
export FORGEOS_TW_GUARD_LIB="$ROOT/files/system/usr/lib/forgeos-guard" FORGEOS_TW_GUI="$WORK/bin/tw-gui"
export FORGEOS_TW_HELPER="$ROOT/files/system/usr/libexec/forgeos-tripwire-helper"
export FORGEOS_TW_RELEASE="$ROOT/files/system/usr/libexec/forgeos-tripwire-release"
ENGINE="$ROOT/files/system/usr/bin/forgeos-tripwire"
GUI="$ROOT/files/system/usr/bin/forgeos-tripwire-gui"
TW() { FORGEOS_TW_ROOT=0 python3 -B "$ENGINE" "$@"; }  # as Robert (not root)
ROOTTW() { FORGEOS_TW_ROOT=1 python3 -B "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
# git keeps the scripts without the "run" bit, so they are started through small wrappers.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-tripwire"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/tw-gui"
chmod +x "$WORK/bin/forgeos-tripwire" "$WORK/bin/tw-gui"
export FORGEOS_TW_ENGINE="$WORK/bin/forgeos-tripwire"
for f in Documents Pictures Desktop Downloads Music Videos; do mkdir -p "$H/$f"; done

fake nmcli '[ "$*" = networking ] && { cat "$WORK/net-state" 2>/dev/null || echo enabled; exit 0; }
[ "$*" = "networking off" ] && echo disabled > "$WORK/net-state"; [ "$*" = "networking on" ] && echo enabled > "$WORK/net-state"; exit 0'
fake snapper 'echo 77'
fake systemctl '[ "$2" = forgeos-tripwire.service ] && echo active'
fake notify-send 'exit 0'
fake kdialog 'case " $* " in *" --passivepopup "*) exit 0 ;; esac
a="$(head -n 1 "$WORK/kd-answers" 2>/dev/null)"; sed -i 1d "$WORK/kd-answers" 2>/dev/null
case "$a" in rc1) exit 1 ;; "") exit 0 ;; *) echo "$a" ;; esac'
fake pkexec '[ -e "$WORK/pkexec-no" ] && exit 126; PKEXEC_UID="${PK_UID:-$FORGEOS_TW_UID}" FORGEOS_TW_ROOT=1 exec bash "$@"'
calls() { cat "$WORK/calls.log" 2>/dev/null; }

# prog PID NAME CGROUP [EXE] [CMD] [PPID]: a pretend running program owned by Robert
prog() {
  local d="$WORK/proc/$1" exe="${4:-$WORK/progs/$2}"
  rm -rf "$d"; mkdir -p "$d" "$WORK/progs"
  [ -e "$exe" ] || printf 'pretend program %s\n' "$2" 2>/dev/null > "$exe"
  printf 'Name:\t%s\nPPid:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "$2" "${6:-1}" "$ME" "$ME" "$ME" "$ME" > "$d/status"
  printf '%s\n' "$2" > "$d/comm"; printf '0::%s\n' "$3" > "$d/cgroup"; printf '%s\0' "${5:-$exe}" > "$d/cmdline"
  ln -s "$exe" "$d/exe"
  mkdir -p "$WORK/cg$3"; echo 0 > "$WORK/cg$3/cgroup.freeze"; echo 0 > "$WORK/cg$3/cgroup.kill"
}
APP=/user.slice/user-1000.slice/user@1000.service/app.slice
# feed lines: write T PID PATH / gone T PATH (T = seconds after the start of the replay)
write() { printf '{"t": %s, "pid": %s, "kind": "write", "path": "%s"}\n' "$1" "$2" "$3" >> "$WORK/feed"; }
gone() { printf '{"t": %s, "kind": "gone", "path": "%s"}\n' "$1" "$2" >> "$WORK/feed"; }
replay() { ROOTTW watch --feed "$WORK/feed"; rm -f "$WORK/feed"; }
noise() { head -c "${2:-4096}" /dev/urandom > "$1"; }  # a scrambled-looking file
letter() { python3 -c "import sys; open(sys.argv[1], 'w').write(('Dear Sir, this is letter ' + sys.argv[2] + '. ') * 80)" "$1" "$2"; }
# attack PID FOLDER N [STEP] [END]: the program scrambles N letters into NAME.locked copies, deleting the letters
attack() {
  local i t=0 f
  for i in $(seq 1 "$3"); do
    f="$2/letter $i.txt"; noise "$f.${5:-locked}"; rm -f "$f"; write "$t" "$1" "$f.${5:-locked}"
    t="$(python3 -c "print($t + ${4:-0.1})")"
  done
}
# snap N HOURS-AGO: an Undo Button snapshot of Robert's home as it is now
snap() {
  local d="$WORK/homes/.snapshots/$1"
  mkdir -p "$d/snapshot"; cp -a "$H" "$d/snapshot/robert"
  printf '<?xml version="1.0"?>\n<snapshot>\n  <type>single</type>\n  <num>%s</num>\n  <date>%s</date>\n  <cleanup>timeline</cleanup>\n</snapshot>\n' \
    "$1" "$(date -u -d "@$(( $(date +%s) - $2 * 3600 ))" '+%Y-%m-%d %H:%M:%S')" > "$d/info.xml"
}
inc() { ls "$WORK/var/incidents" 2>/dev/null | sed -n "${1:-1}p" | sed 's/\.json$//'; }  # the Nth incident id (oldest first)
# py ID EXPR: print a value from that incident (i)
py() { python3 -c "import json,sys; i=json.load(open(sys.argv[1])); print($2)" "$WORK/var/incidents/$1.json"; }
fresh() { rm -rf "${WORK:?}/var" "$WORK/run" "$WORK/state" "$WORK/data" "$WORK/feed" "$WORK/calls.log" "$WORK/net-state" "$WORK/kd-answers"; mkdir -p "$WORK/var" "$WORK/run"; }
