# shellcheck shell=bash
# Fake tools for the Family Mode tests (Job 13). Sourced by tests/test-family*.sh.
# Every fake writes its name and arguments to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home/Desktop" "$WORK/cfg" "$WORK/state" "$WORK/kcfg" "$WORK/rd"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_CONFIG_HOME="$WORK/cfg" XDG_STATE_HOME="$WORK/state" PATH="$WORK/bin:$PATH"
export FORGEOS_FAMILY_LIB="$ROOT/files/system/usr/lib/forgeos-family" FORGEOS_FAMILY_RUSTDESK_DIR="$WORK/rd"
export FORGEOS_FAMILY_APPS="$ROOT/files/system/usr/share/applications" FORGEOS_FAMILY_SELF=/usr/bin/forgeos-family
export FORGEOS_FAMILY_ID_WAIT=3 FORGEOS_FAMILY_STEP=0
ENGINE="$ROOT/files/system/usr/bin/forgeos-family"
GUI="$ROOT/files/system/usr/bin/forgeos-family-gui"
CALL="$ROOT/files/system/usr/libexec/forgeos-family-call"
F() { python3 "$ENGINE" "$@"; }
T=$'\t'  # a tab, for checking the tab-separated lines
# The windows run the engine and each other through these wrappers (git keeps no exec bits).
printf '#!/usr/bin/env bash\nexec python3 "%s" "$@"\n' "$ENGINE" > "$WORK/bin/ff-engine"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$GUI" > "$WORK/bin/ff-gui"
printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$CALL" > "$WORK/bin/ff-call"
chmod +x "$WORK/bin/ff-engine" "$WORK/bin/ff-gui" "$WORK/bin/ff-call"
export FORGEOS_FAMILY_ENGINE="$WORK/bin/ff-engine" FORGEOS_FAMILY_GUI="$WORK/bin/ff-gui" FORGEOS_FAMILY_CALL="$WORK/bin/ff-call"

# KDE settings: one file per key in $WORK/kcfg/FILE/GROUP/KEY. FAKE_KWRITE_FAIL=1 = writing fails.
fake kreadconfig6 'f="" g="" k=""; while [ $# -gt 0 ]; do case "$1" in --file) f="$2"; shift ;; --group) g="$2"; shift ;; --key) k="$2"; shift ;; esac; shift; done
cat "$WORK/kcfg/$f/$g/$k" 2>/dev/null; exit 0'
fake kwriteconfig6 '[ "${FAKE_KWRITE_FAIL:-0}" = 1 ] && exit 1
f="" g="" k="" d=0 v=""; while [ $# -gt 0 ]; do case "$1" in --file) f="$2"; shift ;; --group) g="$2"; shift ;; --key) k="$2"; shift ;;
  --delete) d=1 ;; --notify) ;; *) v="$1" ;; esac; shift; done
if [ "$d" = 1 ]; then rm -f "$WORK/kcfg/$f/$g/$k"; else mkdir -p "$WORK/kcfg/$f/$g"; printf "%s\n" "$v" > "$WORK/kcfg/$f/$g/$k"; fi'
# Plasma: the panels are "id:height" lines in $WORK/panels. FAKE_NO_PLASMA=1 = Plasma does not answer.
fake dbus-send 'case "$*" in *org.kde.plasmashell*)
  [ "${FAKE_NO_PLASMA:-0}" = 1 ] && exit 1
  case "$*" in *"print(panels()"*) echo "method return"; echo "   string \"$(paste -sd, "$WORK/panels")\"" ;;
  *panelById*) grep -o "panelById([0-9]*).height = [0-9]*" <<< "$*" | while read -r p _ h; do
      id="${p#panelById(}"; id="${id%%)*}"; sed -i "s/^$id:.*/$id:$h/" "$WORK/panels"; done; echo "   string \"\"" ;;
  esac ;; esac; exit 0'
printf '%s\n' 1:44 7:60 > "$WORK/panels"

# RustDesk (Flatpak): $WORK/running holds the app id while it runs; the ID comes from $WORK/ids
# (one answer per --get-id, last line repeats). FAKE_NO_KILL=1 = it won't close.
fake flatpak 'case "$*" in
  "ps --columns=application") cat "$WORK/running" 2>/dev/null ;;
  "kill com.rustdesk.RustDesk") [ "${FAKE_NO_KILL:-0}" = 1 ] || : > "$WORK/running" ;;
  "run com.rustdesk.RustDesk") echo com.rustdesk.RustDesk > "$WORK/running" ;;
  "run --command=rustdesk com.rustdesk.RustDesk --get-id") l="$(head -n 1 "$WORK/ids" 2>/dev/null)"
    [ "$(wc -l < "$WORK/ids" 2>/dev/null)" -gt 1 ] && sed -i 1d "$WORK/ids"; echo "$l" ;;
  *) exit 1 ;;
esac'
echo 123456789 > "$WORK/ids"
# Phone (KDE Connect): paired phones here now in $WORK/devices. FAKE_SMS_RC = exit code of a text.
fake kdeconnect-cli 'case "$*" in "-a --id-only") cat "$WORK/devices" 2>/dev/null ;; *--send-sms*) exit "${FAKE_SMS_RC:-0}" ;; esac'
# Services: enabled units are lines in $WORK/enabled. FAKE_ENABLE_FAIL=1 = turning one on fails.
fake systemctl 'u="${!#}"; case "$*" in
  *is-enabled*) grep -qx "$u" "$WORK/enabled" 2>/dev/null && { echo enabled; exit 0; }; echo disabled; exit 1 ;;
  *"enable --now"*) [ "${FAKE_ENABLE_FAIL:-0}" = 1 ] && exit 1; echo "$u" >> "$WORK/enabled" ;;
esac; exit 0'
printf '%s\n' clamav-freshclam.service forgeos-cleansweep.timer forgeos-scamshield-update.timer \
  forgeos-willitrun-update.timer forgeos-privacy-watch.service > "$WORK/enabled"
fake systemd-run 'exit 0'
fake notify-send 'exit 0'
fake xdg-user-dir 'echo "$HOME/Desktop"'
fake nmcli 'echo "${FAKE_NET:-full}"'

# snap: every KDE setting, panel and RustDesk file, to compare before / after.
snap() { (cd "$WORK" && find kcfg rd -type f | sort | while read -r f; do echo "== $f"; cat "$f"; done; cat panels); }
