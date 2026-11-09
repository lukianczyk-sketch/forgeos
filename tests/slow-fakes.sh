# shellcheck shell=bash
# Fake PC for the Why Is It Slow? tests (Job 20). Sourced by tests/test-slow*.sh.
# A pretend /proc and /sys (tests/slow-make.py) and fake powerprofilesctl, Drive Health, systemd-analyze, ip,
# nmcli, ping, rpm-ostree, gio, flatpak, systemctl, qdbus and Ask Your PC. Fakes log to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/apps" "$WORK/xdg-autostart"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_STATE_HOME="$WORK/state" XDG_CONFIG_HOME="$WORK/config" PATH="$WORK/bin:$PATH"
export PYTHONDONTWRITEBYTECODE=1 FORGEOS_SLOW_LIB="$ROOT/files/system/usr/lib/forgeos-slow"
export FORGEOS_SLOW_PROC="$WORK/proc" FORGEOS_SLOW_SYS="$WORK/sys" FORGEOS_SLOW_WAIT=0 FORGEOS_SLOW_UID=1000
export FORGEOS_SLOW_APPDIRS="$WORK/apps" FORGEOS_SLOW_XDG_AUTOSTART="$WORK/xdg-autostart" FORGEOS_SLOW_LOOKUP=localhost
ENGINE="$ROOT/files/system/usr/bin/forgeos-slow"
GUI="$ROOT/files/system/usr/bin/forgeos-slow-gui"
SL() { python3 -B "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
GB=1073741824
HIST="$WORK/state/forgeos/slow/history.jsonl"
LOGF="$WORK/state/forgeos/slow/fixes.log"
# git keeps the scripts without the "run" bit, so they are started through a small wrapper.
printf '#!/usr/bin/env bash\nexec python3 -B "%s" "$@"\n' "$ENGINE" > "$WORK/bin/forgeos-slow"
chmod +x "$WORK/bin/forgeos-slow"
export FORGEOS_SLOW_ENGINE="$WORK/bin/forgeos-slow" FORGEOS_SLOW_SCREENS="$ROOT/files/system/usr/libexec/forgeos-slow-screens"
mk() { python3 -B "$ROOT/tests/slow-make.py" "$@"; }
# prog PID key=value...: a running program (see tests/slow-make.py)
prog() { mk proc "$WORK/proc" "$@"; }
app() { printf '[Desktop Entry]\nType=Application\nName=%s\n' "$2" > "$WORK/apps/$1.desktop"; }
line() { grep "^PROBLEM${T}$1${T}" <<< "$OUT"; }
# normal_pc: a healthy PC - 16 GB with 10 free, nothing waiting, cool, Balanced, a good drive, quick start-up,
# strong Wi-Fi, a fast internet, on for 2 days, only the desktop running
normal_pc() {
  rm -rf "$WORK/proc" "$WORK/sys" "$WORK/calls.log" "${WORK:?}/home"/* "$WORK/config" "${WORK:?}/xdg-autostart"/* "$WORK/state" "$WORK"/net-*
  mkdir -p "$WORK/proc" "$WORK/sys/class/power_supply"
  mk mem "$WORK/proc" 16 10; mk uptime "$WORK/proc" 2
  for k in cpu memory io; do mk pressure "$WORK/proc" "$k" 0.00 0.00 0.00; done
  mk temp "$WORK/sys" k10temp 55; mk freq "$WORK/sys" 3000 4000
  prog 900 comm=plasmashell cpu=3 rss=400
  echo balanced > "$WORK/power-mode"
  printf 'CHECKED\t2026-11-08\tgood\n' > "$WORK/dh-status"; echo 0 > "$WORK/dh-rc"
  echo "Startup finished in 6.1s (firmware) + 2.0s (loader) + 3.2s (kernel) + 18.3s (userspace) = 29.6s" > "$WORK/boot"
  echo "yes:80:HomeWiFi" > "$WORK/wifi"
  echo '{"deployments": [{"booted": true}]}' > "$WORK/ostree"
  export FORGEOS_SLOW_DF="$((500 * GB)) $((200 * GB))"
}
fake powerprofilesctl '[ "$1" = get ] && cat "$WORK/power-mode"; [ "$1" = set ] && echo "$2" > "$WORK/power-mode"; exit 0'
fake forgeos-drivehealth 'cat "$WORK/dh-status"; exit "$(cat "$WORK/dh-rc")"'
fake systemd-analyze 'cat "$WORK/boot"'
fake ip '[ -e "$WORK/net-noroute" ] || echo "default via 192.168.1.1 dev wlp2s0 proto dhcp metric 600"'
fake nmcli 'cat "$WORK/wifi"'
fake ping 'h="${*: -1}"
if [ -e "$WORK/net-$h" ]; then cat "$WORK/net-$h"; exit 1; fi
printf "3 packets transmitted, 3 received, 0%% packet loss, time 2003ms\nrtt min/avg/max/mdev = 9.1/12.0/15.2/2.1 ms\n"'
fake rpm-ostree 'cat "$WORK/ostree"'
fake gio 'if [ "$2" = --empty ]; then rm -rf "$HOME/.local/share/Trash/files"; else mkdir -p "$WORK/trashed"; mv "$2" "$WORK/trashed/"; fi'
fake flatpak 'exit 0'
fake systemctl 'exit 0'
fake qdbus 'exit 0'
fake forgeos-askpc 'echo "The internet was restarted."'
fake forgeos-cleansweep-gui 'exit 0'
fake forgeos-drivehealth-gui 'exit 0'
fake busctl 'echo "b false"'
fake gamemoded 'echo "gamemode is inactive"'
fake pgrep '[ -e "$WORK/game" ]'
normal_pc
