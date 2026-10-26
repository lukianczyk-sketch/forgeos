#!/usr/bin/env bash
# Tests for the Panic Button (Job 6) with fake tools + a fake /sys.
# Usage: bash tests/test-panic.sh <repo-root>
set -u
ROOT="$(cd "${1:-.}" && pwd)"
U="$ROOT/files/system/usr"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }

# --- fake /sys: USB camera (video0 + video1 on one device), one built-in non-USB camera ---
S="$WORK/sys"
CAM="$S/devices/pci0/usb1/1-5"
mkdir -p "$CAM/1-5:1.0" "$S/devices/platform/ipu6" "$S/class/video4linux"
echo 1 > "$CAM/authorized"; echo 046d > "$CAM/idVendor"; echo 1 > "$CAM/1-5:1.0/authorized"
for v in video0 video1; do mkdir -p "$S/class/video4linux/$v"; ln -s "$CAM/1-5:1.0" "$S/class/video4linux/$v/device"; done

# --- fake tools ---
B="$WORK/bin"; mkdir -p "$B"
LOG="$WORK/log"
mk() { printf '#!/usr/bin/env bash\n%s\n' "$2" > "$B/$1"; chmod +x "$B/$1"; }
mk rfkill 'echo "rfkill $*" >> "$LOG"
if [ "$1" = "--noheadings" ]; then printf "0 wlan unblocked\n1 bluetooth unblocked\n2 wwan blocked\n3 wlan blocked\n"; fi
exit 0'
mk nmcli 'if [ "$#" -eq 1 ]; then echo "${FAKE_NM:-enabled}"; exit 0; fi
echo "nmcli $*" >> "$LOG"; exit "${FAKE_NM_RC:-0}"'
mk pactl 'case "$1" in
list) printf "0\talsa_input.mic\tPipeWire\n1\talsa_output.spk.monitor\tPipeWire\n2\tbluez_input.headset\tPipeWire\n" ;;
get-source-mute) echo "Mute: $(cat "$WORK/mute_$2" 2>/dev/null || echo no)" ;;
set-source-mute) echo "pactl set $2 $3" >> "$LOG"; if [ "$3" = 1 ]; then echo yes > "$WORK/mute_$2"; else echo no > "$WORK/mute_$2"; fi ;;
esac'
mk dbus-send 'echo "dbus-send $*" >> "$LOG"; exit "${FAKE_DBUS_RC:-0}"'
mk loginctl 'echo "loginctl $*" >> "$LOG"; exit 0'
mk notify-send 'echo "notify $*" >> "$LOG"'
mk kdialog 'echo "kdialog" >> "$LOG"; exit "${FAKE_KD_RC:-0}"'
mk pkexec 'echo "pkexec $*" >> "$LOG"; exec bash "$@"'
export PATH="$B:$PATH" LOG WORK
export FORGEOS_PANIC_TEST=1 FORGEOS_PANIC_SYS="$S" FORGEOS_PANIC_RUN="$WORK/run"
export FORGEOS_PANIC_HELPER="$U/libexec/forgeos-panic-helper" FORGEOS_PANIC_STATE="$WORK/state"
export FORGEOS_PANIC_NOGUARD=1
H="$U/libexec/forgeos-panic-helper"
P="$U/bin/forgeos-panic"
reset() { : > "$LOG"; rm -rf "$WORK/run" "$WORK/state" "$WORK"/mute_*; echo 1 > "$CAM/authorized"; }

# A: cut -> USB camera off once, saved; Wi-Fi radio 0 saved (not 1 bt, 2/3 already blocked); internet off
reset
out="$(bash "$H" cut)"; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$CAM/authorized")" = 0 ] && [ "$(cat "$WORK/run/cameras")" = "$CAM" ] \
  && [ "$(cat "$WORK/run/radios")" = 0 ] && grep -qx "nmcli networking off" "$LOG" \
  && grep -qx "rfkill block wlan" "$LOG" && ! grep -q "block bluetooth" "$LOG" \
  && echo "$out" | grep -qx "camera_off 1" && echo "$out" | grep -qx "internet off" && [ -e "$WORK/run/active" ]; then
  pass "A cut"; else fail "A cut (rc=$rc out=$out)"; fi

# B: second press keeps the first saved state (networking stays "enabled", one camera line)
FAKE_NM=disabled bash "$H" cut >/dev/null
if [ "$(cat "$WORK/run/networking")" = enabled ] && [ "$(wc -l < "$WORK/run/cameras")" -eq 1 ]; then
  pass "B second press"; else fail "B second press"; fi

# C: restore -> camera on, only radio 0 unblocked, internet on, state removed
: > "$LOG"; bash "$H" restore; rc=$?
if [ "$rc" -eq 0 ] && [ "$(cat "$CAM/authorized")" = 1 ] && grep -qx "rfkill unblock 0" "$LOG" \
  && [ "$(grep -c unblock "$LOG")" -eq 1 ] && grep -qx "nmcli networking on" "$LOG" && [ ! -e "$WORK/run/active" ]; then
  pass "C restore"; else fail "C restore (rc=$rc)"; fi

# D: restore with no saved state (after a restart) -> Wi-Fi + internet back on
reset; bash "$H" restore
if grep -qx "rfkill unblock wlan" "$LOG" && grep -qx "nmcli networking on" "$LOG"; then
  pass "D restore after restart"; else fail "D restore after restart"; fi

# E: network was already off before the panic -> restore leaves it off
reset; FAKE_NM=disabled bash "$H" cut >/dev/null; : > "$LOG"; bash "$H" restore
if ! grep -q "networking on" "$LOG"; then pass "E keeps network off"; else fail "E keeps network off"; fi

# F: refuses non-root without the test switch; unknown word -> exit 2
reset
FORGEOS_PANIC_TEST='' bash "$H" cut >/dev/null 2>&1; f1=$?
bash "$H" "/etc/passwd" >/dev/null 2>&1; f2=$?
if [ "$(id -u)" -ne 0 ] && [ "$f1" -eq 2 ] && [ "$f2" -eq 2 ] && [ "$(cat "$CAM/authorized")" = 1 ]; then
  pass "F refuses"; elif [ "$(id -u)" -eq 0 ] && [ "$f2" -eq 2 ]; then pass "F refuses (root: word check only)"
  else fail "F refuses ($f1/$f2)"; fi

# G: built-in non-USB camera is reported, not touched
reset; mkdir -p "$S/class/video4linux/video2"; ln -s "$S/devices/platform/ipu6" "$S/class/video4linux/video2/device"
out="$(bash "$H" cut)"
if echo "$out" | grep -qx "camera_nonusb 1" && echo "$out" | grep -qx "camera_off 1"; then
  pass "G non-USB camera"; else fail "G non-USB camera ($out)"; fi
rm -rf "$S/class/video4linux/video2"

# H: forgeos-panic on -> mics muted (not the speaker monitor), only ON mics remembered,
#    helper via pkexec, screen locked over D-Bus, critical notification
reset; echo yes > "$WORK/mute_bluez_input.headset"
out="$(bash "$P" on)"; rc=$?
if [ "$rc" -eq 0 ] && grep -qx "pactl set alsa_input.mic 1" "$LOG" && grep -qx "pactl set bluez_input.headset 1" "$LOG" \
  && ! grep -q "monitor" "$LOG" && [ "$(cat "$WORK/state/mics")" = alsa_input.mic ] \
  && grep -q "pkexec .*forgeos-panic-helper cut" "$LOG" && grep -q "org.freedesktop.ScreenSaver.Lock" "$LOG" \
  && grep -q "notify -u critical" "$LOG" && echo "$out" | grep -q "Internet: OFF" && [ -e "$WORK/state/active" ]; then
  pass "H panic on"; else fail "H panic on (rc=$rc)"; fi

# I: All Clear --yes -> only the remembered mic unmuted, helper restore, guard flag gone
: > "$LOG"; bash "$P" off --yes >/dev/null; rc=$?
if [ "$rc" -eq 0 ] && grep -qx "pactl set alsa_input.mic 0" "$LOG" && ! grep -q "headset 0" "$LOG" \
  && grep -q "forgeos-panic-helper restore" "$LOG" && [ ! -e "$WORK/state/active" ] && [ "$(cat "$CAM/authorized")" = 1 ]; then
  pass "I all clear"; else fail "I all clear (rc=$rc)"; fi

# J: All Clear asks first; "No" changes nothing
reset; bash "$P" on >/dev/null; : > "$LOG"
FAKE_KD_RC=1 bash "$P" off; rc=$?
if [ "$rc" -eq 1 ] && grep -qx kdialog "$LOG" && ! grep -q restore "$LOG" && [ -e "$WORK/state/active" ]; then
  pass "J asks first"; else fail "J asks first"; fi

# K: lock falls back to loginctl when D-Bus lock fails; internet failure is reported
reset; FAKE_DBUS_RC=1 FAKE_NM_RC=1 bash "$P" on > "$WORK/out"; rc=$?
if [ "$rc" -eq 1 ] && grep -qx "loginctl lock-session" "$LOG" && grep -q "could NOT be cut" "$WORK/out"; then
  pass "K fallbacks"; else fail "K fallbacks (rc=$rc)"; fi

# L: guard re-mutes a mic that got unmuted while the panic is on
reset; bash "$P" on >/dev/null; echo no > "$WORK/mute_alsa_input.mic"; : > "$LOG"
bash "$P" guard --once
if grep -qx "pactl set alsa_input.mic 1" "$LOG"; then pass "L guard"; else fail "L guard"; fi

# M: menu files, shortcut and polkit rule
D="$U/share/applications"; X="$U/share/polkit-1/actions/org.forgeos.panic.policy"
m=0
grep -qx "X-KDE-Shortcuts=Meta+Shift+Esc" "$D/forgeos-panic.desktop" || m=1
grep -qx "Exec=/usr/bin/forgeos-panic on" "$D/forgeos-panic.desktop" || m=1
grep -qx "Exec=/usr/bin/forgeos-panic off" "$D/forgeos-all-clear.desktop" || m=1
grep -q '<annotate key="org.freedesktop.policykit.exec.path">/usr/libexec/forgeos-panic-helper</annotate>' "$X" || m=1
grep -q '<allow_active>yes</allow_active>' "$X" || m=1
grep -q '<allow_any>auth_admin</allow_any>' "$X" || m=1
if command -v desktop-file-validate >/dev/null 2>&1; then desktop-file-validate "$D/forgeos-panic.desktop" "$D/forgeos-all-clear.desktop" || m=1; fi
if command -v xmllint >/dev/null 2>&1; then xmllint --noout "$X" || m=1; fi
grep -q "/usr/bin/forgeos-panic /usr/libexec/forgeos-panic-helper" "$ROOT/files/scripts/forgeos-setup.sh" || m=1
if [ "$m" -eq 0 ]; then pass "M menu + shortcut + polkit"; else fail "M menu + shortcut + polkit"; fi

echo "----"
[ "$failures" -eq 0 ] && { echo "ALL PASS"; exit 0; }
echo "$failures FAILED"; exit 1
