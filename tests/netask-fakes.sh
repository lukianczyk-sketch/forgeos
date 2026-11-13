# shellcheck shell=bash
# Pretend PC for the Ask Before Connecting tests (Job 24). Sourced by tests/test-netask*.sh.
# The service runs for real (as you, FORGEOS_NETASK_TEST=1) on sockets in $WORK; a pretend OpenSnitch daemon
# (tests/netask-fake-daemon.py) speaks the real UI protocol to it. /proc is a pretend folder; kdialog, loginctl,
# pgrep (games), systemctl and Clean Sweep are fakes. Everything they are asked is logged to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
[ -n "${WORK:-}" ] && [ -d "$WORK" ] || { echo "netask-fakes.sh: set WORK to a new temp folder first" >&2; return 1; }
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/proc" "$WORK/root" "$WORK/exe" "$WORK/var" "$WORK/rules" "$WORK/say" "$WORK/apps" "$WORK/proto" \
  "$WORK/runuser/$(id -u)" "$WORK/sock" "$WORK/req"
: > "$WORK/runuser/$(id -u)/wayland-0"
ME="$(id -u)"
# fake NAME BODY: a pretend program ($W in BODY = the work folder, written in, so it works with a clean env too)
fake() { printf '#!/usr/bin/env bash\nW=%q\necho "%s $*" >> "$W/calls.log"\n%s\n' "$WORK" "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" PYTHONDONTWRITEBYTECODE=1 PATH="$WORK/bin:$PATH"
export FORGEOS_NETASK_TEST=1 FORGEOS_NETASK_LIB="$ROOT/files/system/usr/lib/forgeos-netask"
export FORGEOS_NETASK_SHARE="$ROOT/files/system/usr/share/forgeos/netask" FORGEOS_TG_SHARE="$ROOT/files/system/usr/share/forgeos/techguard"
export FORGEOS_NETASK_PROC="$WORK/proc" FORGEOS_NETASK_VAR="$WORK/var" FORGEOS_NETASK_RULES="$WORK/rules"
export FORGEOS_NETASK_SOCK="$WORK/sock/osui.sock" FORGEOS_NETASK_REQ="$WORK/req/req.sock" FORGEOS_NETASK_HOME="$WORK/home"
export FORGEOS_NETASK_APPDIRS="$WORK/apps" FORGEOS_HOSTS="$WORK/hosts" FORGEOS_NETASK_RUNUSER="$WORK/runuser"
export FORGEOS_NETASK_CLI="$WORK/bin/forgeos-netask" FORGEOS_NETASK_PROTO="$WORK/proto" FORGEOS_NETASK_ROOT="$WORK/root"
export FORGEOS_NETASK_ASK_SECONDS=5 FORGEOS_NETASK_CONFIRMS=100 FORGEOS_NETASK_MOST_ASKS=100 FORGEOS_HELPER_LIB="$ROOT/files/system/usr/lib/forgeos-helper" FORGEOS_OLLAMA_URL="http://127.0.0.1:9"
ENGINE="$ROOT/files/system/usr/bin/forgeos-netask"
GUI="$ROOT/files/system/usr/bin/forgeos-netask-gui"
NA() { python3 -B "$ENGINE" "$@"; }
T=$'\t'
H="$WORK/home"
# OpenSnitch's real ui.proto -> Python, the same way the image build does it
python3 -m grpc_tools.protoc -I "$FORGEOS_NETASK_SHARE" --python_out="$WORK/proto" --grpc_python_out="$WORK/proto" "$FORGEOS_NETASK_SHARE/ui.proto" \
  || { echo "netask-fakes.sh: could not make the protocol (python3 grpc_tools missing?)" >&2; return 1; }
fake forgeos-netask 'exec python3 -B '"$(printf %q "$ENGINE")"' "$@"'
# kdialog: answers come from $W/say/codes (one exit code per question, first line first; default 0),
# $W/say/picks (--menu answers, first line first; else $W/say/pick) and $W/say/check (a --checklist answer).
# A --textbox file is copied to $W/textbox.txt.
fake kdialog 'case "$*" in *--passivepopup*|*--msgbox*) exit 0 ;; esac
code=0; if [ -s "$W/say/codes" ]; then code="$(head -n 1 "$W/say/codes")"; sed -i 1d "$W/say/codes"; fi
[ "$code" = kill ] && kill -TERM $$
case "$*" in
  *--menu*) if [ -s "$W/say/picks" ]; then pick="$(head -n 1 "$W/say/picks")"; sed -i 1d "$W/say/picks"; else pick="$(cat "$W/say/pick" 2>/dev/null)"; fi
            [ -n "$pick" ] || exit 1; [ "$code" = 0 ] && echo "$pick" ;;
  *--checklist*) [ "$code" = 0 ] && cat "$W/say/check" 2>/dev/null ;;
  *--textbox*) while [ "$1" != --textbox ]; do shift; done; cp "$2" "$W/textbox.txt"; exit 0 ;;
esac
exit "$code"'
fake loginctl 'case "$1" in list-sessions) echo "  4 '"$ME"' tester seat0 tty2" ;; show-session) if [ -e "$W/away" ]; then echo Active=no; else printf "Type=wayland\nActive=yes\nRemote=no\n"; fi ;; esac'
fake pgrep '[ -e "$W/gaming" ]'
fake systemctl 'case "$1" in is-active) cat "$W/say/active" 2>/dev/null || echo active ;; esac; exit 0'
fake forgeos-cleansweep-gui 'exit 0'
# shellcheck source=tests/netask-proc.sh
. "$ROOT/tests/netask-proc.sh"
# ask JSON: what our service answered the pretend daemon (line 1: action duration name; line 2: the operator)
ask() { python3 -B "$ROOT/tests/netask-fake-daemon.py" "$WORK/proto" "$FORGEOS_NETASK_SOCK" ask "$1"; }
ping() { python3 -B "$ROOT/tests/netask-fake-daemon.py" "$WORK/proto" "$FORGEOS_NETASK_SOCK" ping "$1"; }
daemon() { python3 -B "$ROOT/tests/netask-fake-daemon.py" "$WORK/proto" "$FORGEOS_NETASK_SOCK" "$@"; }
# conn PID PATH [MD5] [HOST] [extra JSON fields]: a connection as JSON
conn() { printf '{"pid": %s, "uid": %s, "path": "%s", "md5": "%s", "host": "%s"%s}' "$1" "$ME" "$2" "${3:-}" "${4:-example.com}" "${5:+, $5}"; }
answer() { ask "$1" | sed -n 1p; }
app() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$2" "$3" > "$WORK/apps/$1.desktop"; }
start_service() {
  python3 -B "$ROOT/files/system/usr/libexec/forgeos-netask-service" > "$WORK/service.log" 2>&1 &
  SERVICE_PID=$!
  for _ in $(seq 100); do [ -S "$FORGEOS_NETASK_SOCK" ] && [ -S "$FORGEOS_NETASK_REQ" ] && return 0; sleep 0.1; done
  echo "the service did not start:" >&2; cat "$WORK/service.log" >&2; return 1
}
stop_service() { [ -n "${SERVICE_PID:-}" ] && kill "$SERVICE_PID" 2>/dev/null && wait "$SERVICE_PID" 2>/dev/null; SERVICE_PID=""; }
store() { python3 -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d.get(sys.argv[2], {}).get(sys.argv[3], ""))' "$WORK/var/apps-$ME.json" "$1" "$2" 2>/dev/null; }
calls() { cat "$WORK/calls.log" 2>/dev/null; }
waitfor_call() { for _ in $(seq 30); do calls | grep -q "$1" && return 0; sleep 0.1; done; return 1; }
fresh() { rm -f "$WORK/calls.log" "$WORK/say/"* "$WORK/gaming" "$WORK/away"; }
