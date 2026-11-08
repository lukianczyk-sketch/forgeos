# shellcheck shell=bash
# Fake PC for the Find My PC tests (Job 19). Sourced by tests/test-locate*.sh.
# A pretend relay + location services (tests/locate-fake-relay.py, on 127.0.0.1), a pretend root state
# folder, and fake nmcli, who, loginctl, systemctl, ffmpeg, pactl, paplay, flatpak, keepassxc, notify-send,
# kdialog, qrencode, pkexec and the money lock. The lock (AES-256-GCM) is REAL. Fakes log to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/var" "$WORK/run" "$WORK/sys/BAT0" "$WORK/dmi" "$WORK/user/1000"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
SYS="$ROOT/files/system"
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH" PYTHONDONTWRITEBYTECODE=1
export FORGEOS_LOC_LIB="$SYS/usr/lib/forgeos-locate" FORGEOS_LOC_SHARE="$SYS/usr/share/forgeos/locate"
export FORGEOS_LOC_VAR="$WORK/var" FORGEOS_LOC_RUN="$WORK/run" FORGEOS_LOC_SYS="$WORK/sys"
export FORGEOS_LOC_SERIAL="$WORK/dmi/serial" FORGEOS_LOC_MONEY="$WORK/bin/techguard" FORGEOS_LOC_SOUND="$WORK/ring.oga"
export FORGEOS_LOC_HELPER="$SYS/usr/libexec/forgeos-locate-root" FORGEOS_LOC_SCREENS="$SYS/usr/libexec"
export FORGEOS_LOC_POKE="$WORK/user/*/forgeos-locate-poke" XDG_RUNTIME_DIR="$WORK/user/1000" FORGEOS_LOC_HOSTS="$WORK/hosts"
ENGINE="$SYS/usr/bin/forgeos-locate"
GUI="$SYS/usr/bin/forgeos-locate-gui"
LOC() { FORGEOS_LOC_ROOT=0 python3 -B "$ENGINE" "$@"; }    # as Robert
ROOTLOC() { FORGEOS_LOC_ROOT=1 python3 -B "$ENGINE" "$@"; }  # as root (the service, the helper)
T=$'\t'
Q="'"  # a single quote, for checking Python lists
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-locate"
chmod +x "$WORK/bin/forgeos-locate"
export FORGEOS_LOC_ENGINE="$WORK/bin/forgeos-locate"
echo "PF3XK9QZ" > "$WORK/dmi/serial"; echo 57 > "$WORK/sys/BAT0/capacity"; echo Discharging > "$WORK/sys/BAT0/status"
echo "pretend sound" > "$WORK/ring.oga"
# Nearby Wi-Fi (nmcli -t: IN-USE:BSSID:SIGNAL:SECURITY:SSID, a real ":" written as "\:")
printf '%s\n' '*:AA\:BB\:CC\:00\:11\:22:80:WPA2:Home Net' ':AA\:BB\:CC\:00\:11\:33:55:WPA2:Neighbor' \
  ':AA\:BB\:CC\:00\:11\:44:40::Free Cafe Wi-Fi' > "$WORK/wifi.txt"
fake nmcli 'case "$*" in *"wifi list"*) cat "$WORK/wifi.txt" ;; *"wifi connect"*) [ -e "$WORK/join-ok" ] && rm -f "$WORK/down" ;; esac; exit 0'
fake who 'echo "robert   seat0        2027-01-15 10:00 (login screen)"; echo "robert   tty2         2027-01-15 10:01"'
fake loginctl 'exit 0'
fake systemctl 'case "$1" in is-active) [ -e "$WORK/svc-down" ] && { echo inactive; exit 3; }; echo active ;; esac; exit 0'
fake ffmpeg '[ -e "$WORK/no-camera" ] && exit 1; f="${!#}"; { printf "\xff\xd8\xff\xe0"; head -c "${PHOTO_BYTES:-5000}" /dev/zero | tr "\0" "x"; } > "$f"'
fake pactl 'exit 0'
fake paplay 'sleep 0.2'
fake flatpak 'exit 0'
fake keepassxc 'exit 0'
fake notify-send 'exit 0'
fake techguard 'exit 0'
fake qrencode 'f=""; while [ "$#" -gt 0 ]; do [ "$1" = -o ] && f="$2"; shift; done; echo png > "$f"'
fake pkexec '[ -e "$WORK/pkexec-no" ] && exit 126; FORGEOS_LOC_ROOT=1 exec bash "$@"'
fake kdialog 'case " $* " in *" --passivepopup "*) exit 0 ;; esac
printf "%s\n" "$*" >> "$WORK/shown"
[ -e "$WORK/kd-hook" ] && grep -q "tap <b>Test</b>" <<< "$*" && { bash "$WORK/kd-hook"; rm -f "$WORK/kd-hook"; }
a="$(head -n 1 "$WORK/kd-answers" 2>/dev/null)"; sed -i 1d "$WORK/kd-answers" 2>/dev/null
case "$a" in rc1) exit 1 ;; "") exit 0 ;; *) printf "%b\n" "$a" ;; esac'
calls() { cat "$WORK/calls.log" 2>/dev/null; }
# The pretend relay (started once per test file, stopped by stop_relay in the EXIT trap)
start_relay() {
  rm -f "$WORK/relay.port"
  python3 -B "$ROOT/tests/locate-fake-relay.py" "$WORK" & RELAY_PID=$!
  for _ in $(seq 1 50); do [ -s "$WORK/relay.port" ] && break; sleep 0.1; done
  local base
  base="http://127.0.0.1:$(cat "$WORK/relay.port")"
  export FORGEOS_LOC_RELAY="$base" FORGEOS_LOC_GEO="$base/geo" FORGEOS_LOC_IP="$base/ip" RELAY="$base"
}
stop_relay() { kill "${RELAY_PID:-0}" 2>/dev/null; }
# The phone: PY 'python using key, seal, topic' runs with the PC's key
PY() { python3 -B -c "
import json, sys, urllib.request; sys.path.insert(0, sys.argv[1])
from locatelib.seal import seal, unseal, topic
key = json.load(open(sys.argv[2]))['key']
def phone(c, t_ms, **extra):
    d = dict(c=c, t=t_ms); d.update(extra)
    urllib.request.urlopen(urllib.request.Request(sys.argv[3] + '/' + topic(key, 'cmd'), seal(key, 'cmd', d).encode())).read()
def got(name='rep', kind='rep'):
    out = []
    for line in urllib.request.urlopen(sys.argv[3] + '/' + topic(key, name) + '/json?poll=1&since=all').read().decode().splitlines():
        m = json.loads(line); o = unseal(key, kind, m['message']) if kind else m['message']
        if o is not None: out.append(o)
    return out
$1" "$FORGEOS_LOC_LIB" "$WORK/var/key.json" "$RELAY"; }
MS() { echo "$(( ${1:-$FORGEOS_LOC_NOW} * 1000 + ${2:-0} ))"; }  # phone time in ms
st() { python3 -c "import json,sys; s=json.load(open(sys.argv[1])); print($1)" "$WORK/var/state.json"; }
fresh() { rm -rf "${WORK:?}/var" "${WORK:?}/run" "${WORK:?}/state" "$WORK/calls.log" "$WORK/kd-answers" "$WORK/shown" "$WORK/pkexec-no" "$WORK/busy" "$WORK/down" "$WORK/join-ok" "$WORK/svc-down" "$WORK/no-camera"; mkdir -p "$WORK/var" "$WORK/run"; setnow 1800000000; }
setnow() { export FORGEOS_LOC_NOW="$1"; echo "$1" > "$WORK/now"; }  # the PC's and the relay's clock
