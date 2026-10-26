# shellcheck shell=bash
# Fake tools for the Ask Your PC tests (Job 9). Sourced by tests/test-askpc*.sh.
# Every fake writes its name and arguments to $WORK/calls.log. Answers come from FAKE_* settings.
# shellcheck disable=SC2016  # the fake scripts are written out single-quoted on purpose
mkdir -p "$WORK/bin" "$WORK/proc" "$WORK/power/BAT0" "$WORK/home/.cache/thumbnails" "$WORK/cfg/forgeos"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }

fake df 'echo "Filesystem 1024-blocks Used Available Capacity Mounted on"; echo "/dev/fake 100 50 50 ${FAKE_DF:-40}% /"'
fake nmcli 'case "$*" in
  "-t -f CONNECTIVITY general") echo "${FAKE_NET:-full}" ;;
  "-t -f DEVICE,TYPE,STATE device") echo "wlp2s0:wifi:connected"; echo "lo:loopback:connected" ;;
  "networking off") exit "${FAKE_OFF_RC:-0}" ;;
  "networking on") exit "${FAKE_ON_RC:-0}" ;;
esac'
fake wpctl '[ "$1" = get-volume ] && echo "${FAKE_VOL:-Volume: 0.40}"; exit 0'
fake systemctl 'case "$*" in
  "--failed --no-legend --plain") [ -n "${FAKE_FAILED:-}" ] && echo "$FAKE_FAILED loaded failed failed Fake" ;;
  "--user --failed --no-legend --plain") ;;
  *) exit "${FAKE_RESTART_RC:-0}" ;;
esac'
fake rpm-ostree 'if [ "${FAKE_STAGED:-0}" = 1 ]; then echo "{\"deployments\":[{\"booted\":false},{\"booted\":true}]}"; else echo "{\"deployments\":[{\"booted\":true}]}"; fi'
fake ps 'cat "$WORK/ps.txt"'
fake journalctl 'echo "kernel: fake error one"'
fake lpstat 'echo "printer Fake_Printer is idle."'
fake sensors 'echo "Core 0:        +45.0 C  (high = +80.0 C)"; echo "in0:  +12.00 V"'
fake uptime 'echo "up 2 hours, 5 minutes"'
fake du 'printf "12M\t%s\n" "$2"'
fake gio 'exit "${FAKE_GIO_RC:-0}"'
fake setsid 'exit 0'
fake forgeos-cleansweep-gui 'exit 0'
fake dbus-send 'exit 0'

# Fake curl: Ollama answers from FAKE_TAGS / FAKE_AI and keeps the request in $WORK/body.json.
fake curl 'last=""; for a in "$@"; do last="$a"; done
case "$last" in
  */api/tags) [ -n "${FAKE_TAGS:-}" ] || exit 7; printf "%s" "$FAKE_TAGS" ;;
  */api/chat) cat > "$WORK/body.json"; [ -n "${FAKE_AI:-}" ] || exit 28
    jq -n --arg c "$FAKE_AI" "{message: {role: \"assistant\", content: \$c}}" ;;
  *) exit 7 ;;
esac'

# Fake kdialog: menus pop answers from $WORK/menu (one per line; none left = Cancel),
# the question box answers FAKE_QUESTION, Yes/No answers FAKE_YES (0 = yes).
fake kdialog 'for a in "$@"; do case "$a" in
  --menu) l="$(head -n 1 "$WORK/menu" 2>/dev/null)"; sed -i 1d "$WORK/menu" 2>/dev/null; [ -n "$l" ] || exit 1; echo "$l"; exit 0 ;;
  --inputbox) echo "${FAKE_QUESTION:-}"; exit 0 ;;
  --yesno) exit "${FAKE_YES:-0}" ;;
  --progressbar) echo "org.fake /bar"; exit 0 ;;
esac; done; exit 0'

printf 'MemTotal: 1000 kB\nMemFree: 100 kB\nMemAvailable: 250 kB\n' > "$WORK/proc/meminfo"
echo "0.50 0.40 0.30 1/200 1234" > "$WORK/proc/loadavg"
echo 80 > "$WORK/power/BAT0/capacity"
echo Discharging > "$WORK/power/BAT0/status"
echo 'PRETTY_NAME="ForgeOS Test 44"' > "$WORK/os-release"
printf '  101 plasmashell\n  202 fakegame\n  303 firefox\n' > "$WORK/ps.txt"
: > "$WORK/home/.cache/thumbnails/a.png"

export WORK HOME="$WORK/home" PATH="$WORK/bin:$PATH" XDG_CONFIG_HOME="$WORK/cfg" XDG_STATE_HOME="$WORK/state"
export XDG_CACHE_HOME="$WORK/home/.cache" XDG_DATA_HOME="$WORK/home/.local/share"
export FORGEOS_ASKPC_LIBDIR="$ROOT/files/system/usr/libexec" FORGEOS_ASKPC_PROC="$WORK/proc"
export FORGEOS_ASKPC_POWER="$WORK/power" FORGEOS_ASKPC_OSREL="$WORK/os-release" FORGEOS_ASKPC_WAIT=0
AP="$ROOT/files/system/usr/bin/forgeos-askpc"
# git keeps the scripts without the "run" bit, so the window calls the engine through bash.
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$AP" > "$WORK/engine"
chmod +x "$WORK/engine"
export FORGEOS_ASKPC_ENGINE="$WORK/engine"
