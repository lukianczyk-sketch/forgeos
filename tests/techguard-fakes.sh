# shellcheck shell=bash
# Fake PC for the Fake Tech Support Guard tests (Job 17). Sourced by tests/test-techguard*.sh.
# Robert's home, pretend running programs (/proc) and apps (cgroups), a pretend screen sharing (pw-dump),
# a pretend /etc/hosts, and fake systemctl, notify-send, nmcli, pkexec, flatpak and desktop tools.
# Fakes log their name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/proc" "$WORK/cg" "$WORK/var" "$WORK/state" "$WORK/run"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
H="$WORK/home"
ME="$(id -u)"
export WORK HOME="$H" XDG_STATE_HOME="$WORK/state" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config"
export XDG_RUNTIME_DIR="$WORK/run" PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
export FORGEOS_TG_LIB="$ROOT/files/system/usr/lib/forgeos-techguard" FORGEOS_TG_SHARE="$ROOT/files/system/usr/share/forgeos/techguard"
export FORGEOS_TG_VAR="$WORK/var" FORGEOS_TG_PROC="$WORK/proc" FORGEOS_TG_CGROUP="$WORK/cg" FORGEOS_HOSTS="$WORK/hosts"
export FORGEOS_TG_GUARD_LIB="$ROOT/files/system/usr/lib/forgeos-guard" FORGEOS_TG_GUI="$WORK/bin/tg-gui" FORGEOS_TG_UID="$ME"
export FORGEOS_TG_MONEY="$ROOT/files/system/usr/libexec/forgeos-techguard-money"
export FORGEOS_TG_TRUST="$ROOT/files/system/usr/libexec/forgeos-techguard-trust"
ENGINE="$ROOT/files/system/usr/bin/forgeos-techguard"
GUI="$ROOT/files/system/usr/bin/forgeos-techguard-gui"
TG() { FORGEOS_TG_ROOT=0 python3 -B "$ENGINE" "$@"; }  # as Robert (not root)
T=$'\t'  # a tab, for checking the tab-separated lines
# git keeps the scripts without the "run" bit, so they are started through small wrappers.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-techguard"
printf '#!/usr/bin/env bash\necho "gui $*" >> "$WORK/calls.log"\n' > "$WORK/bin/tg-gui"
chmod +x "$WORK/bin/forgeos-techguard" "$WORK/bin/tg-gui"
export FORGEOS_TG_ENGINE="$WORK/bin/forgeos-techguard"
mkdir -p "$H/Downloads" "$H/Desktop" "$H/Documents"
fake systemctl 'case "$*" in
  *"is-active forgeos-techguard.service") [ -e "$WORK/service-off" ] && { echo inactive; exit 3; }; echo active ;;
  *"is-active forgeos-family-call-end.timer") [ -e "$WORK/call-on" ] && { echo active; exit 0; }; echo inactive; exit 3 ;;
esac'
fake notify-send 'echo 7'
fake gdbus 'exit 0'
fake nmcli '[ -e "$WORK/nmcli-fails" ] && exit 1; [ "$*" = "networking off" ] && echo off > "$WORK/net-state"; [ "$*" = "networking on" ] && echo on > "$WORK/net-state"; exit 0'
fake pw-dump 'cat "$WORK/pw.json" 2>/dev/null || echo "[]"'
fake pkexec '[ -e "$WORK/pkexec-no" ] && exit 126; PKEXEC_UID="${PK_UID:-$FORGEOS_TG_UID}" FORGEOS_TG_ROOT=1 exec bash "$@"'
fake flatpak '[ "$1" = list ] && cat "$WORK/flatpaks" 2>/dev/null; [ "$1" = uninstall ] && [ "$2" = "--user" ] && [ -e "$WORK/flatpak-user-fails" ] && exit 1; exit 0'
fake forgeos-family 'exit 0'
fake kdialog 'case " $* " in *" --passivepopup "*) exit 0 ;; esac
printf "%s\n" "$*" >> "$WORK/shown"
a="$(head -n 1 "$WORK/kd-answers" 2>/dev/null)"; sed -i 1d "$WORK/kd-answers" 2>/dev/null
case "$a" in rc1) exit 1 ;; "") exit 0 ;; *) echo "$a" ;; esac'
calls() { cat "$WORK/calls.log" 2>/dev/null; }
printf '127.0.0.1 localhost\n::1 localhost\n' > "$WORK/hosts"
cp "$WORK/hosts" "$WORK/hosts.start"

APP=/user.slice/user-1000.slice/user@1000.service/app.slice
# prog PID NAME CGROUP [EXE] [ARGV0] [PPID]: a pretend running program owned by Robert
prog() {
  local d="$WORK/proc/$1" exe="${4:-$WORK/progs/$2}"
  rm -rf "$d"; mkdir -p "$d" "$WORK/progs"
  [ -e "$exe" ] || printf 'pretend program %s\n' "$2" > "$exe"
  printf 'Name:\t%s\nPPid:\t%s\nUid:\t%s\t%s\t%s\t%s\n' "$2" "${6:-1}" "$ME" "$ME" "$ME" "$ME" > "$d/status"
  printf '%s\n' "$2" > "$d/comm"; printf '0::%s\n' "$3" > "$d/cgroup"; printf '%s\0--x\0' "${5:-$exe}" > "$d/cmdline"
  ln -s "$exe" "$d/exe"
  mkdir -p "$WORK/cg$3"; echo 0 > "$WORK/cg$3/cgroup.freeze"; echo 0 > "$WORK/cg$3/cgroup.kill"
  echo "$1" >> "$WORK/cg$3/cgroup.procs"
}
gone() { rm -rf "$WORK/proc/$1"; }
frozen() { [ "$(cat "$WORK/cg$1/cgroup.freeze")" = 1 ]; }
killed() { [ "$(cat "$WORK/cg$1/cgroup.kill")" = 1 ]; }
# share KEY NAME PID: a pretend screen sharing to that program (kwin-screencast stream); share none = stop
share() {
  [ "$1" = none ] && { echo "[]" > "$WORK/pw.json"; return 0; }
  printf '[{"id": 30, "type": "PipeWire:Interface:Client", "info": {"props": {"application.name": "%s", "application.process.id": "%s", "pipewire.access.portal.app_id": "%s"}}},
{"id": 40, "type": "PipeWire:Interface:Node", "info": {"state": "running", "props": {"media.class": "Stream/Output/Video", "media.name": "kwin-screencast-1"}}},
{"id": 41, "type": "PipeWire:Interface:Node", "info": {"state": "running", "props": {"media.class": "Stream/Input/Video", "client.id": 30, "application.name": "%s"}}},
{"id": 50, "type": "PipeWire:Interface:Link", "info": {"output-node-id": 40, "input-node-id": 41}}]\n' "$2" "$3" "$1" "$2" > "$WORK/pw.json"
}
tick() { TG watch --once; }
st() { python3 -c "import json,sys; s=json.load(open(sys.argv[1])); print($1)" "$WORK/state/forgeos/techguard/state.json"; }
alarm_id() { st "sorted(s['alarms'].values(), key=lambda a: a['time'])[${1:-0}]['id']"; }
astate() { st "s['alarms']['$1']['state']"; }
fresh() { rm -rf "${WORK:?}/state" "${WORK:?}/var" "${WORK:?}/proc" "${WORK:?}/cg" "$WORK/calls.log" "$WORK/net-state" "$WORK/kd-answers" "$WORK/pw.json" "$WORK/shown" "$WORK/call-on" "$WORK/data/forgeos" "$WORK/config/forgeos"; mkdir -p "$WORK/var" "$WORK/proc" "$WORK/cg"; cp "$WORK/hosts.start" "$WORK/hosts"; }
