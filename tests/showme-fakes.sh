# shellcheck shell=bash
# Pretend desktop for the Show Me How tests (Job 22). Sourced by tests/test-showme*.sh.
# spectacle writes a pretend picture; tesseract prints $WORK/screens/N.tsv for look N (the last one again when
# there are no more), or $WORK/screen.tsv. kdialog, systemsettings, gio, busctl (KWin) and the ForgeOS tools
# they ask are fakes too. Everything is logged to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/run" "$WORK/screens" "$WORK/say" "$WORK/data/applications"
chmod 700 "$WORK/run"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config"
export XDG_DATA_DIRS="$WORK/nowhere" XDG_STATE_HOME="$WORK/state" PYTHONDONTWRITEBYTECODE=1 PATH="$WORK/bin:$PATH"
export FORGEOS_SHOWME_LIB="$ROOT/files/system/usr/lib/forgeos-showme" FORGEOS_SHOWME_SHARE="$ROOT/files/system/usr/share/forgeos/showme"
export FORGEOS_HELPER_LIB="$ROOT/files/system/usr/lib/forgeos-helper" FORGEOS_HELPER_SHARE="$ROOT/files/system/usr/share/forgeos/helper"
export FORGEOS_OLLAMA_URL="http://127.0.0.1:9" FORGEOS_SHOWME_FAST=1
ENGINE="$ROOT/files/system/usr/bin/forgeos-showme"
GUI="$ROOT/files/system/usr/bin/forgeos-showme-gui"
SM() { python3 -B "$ENGINE" "$@"; }
T=$'\t'
fake spectacle '[ -e "$WORK/no-shot" ] && exit 1; while [ $# -gt 0 ]; do [ "$1" = -o ] && echo pretend-png > "$2"; shift; done; exit 0'
fake tesseract 'n=$(( $(cat "$WORK/looks" 2>/dev/null || echo 0) + 1 )); echo "$n" > "$WORK/looks"; echo "$1" >> "$WORK/pictures"
[ -e "$1" ] || exit 1
if [ -e "$WORK/screens/1.tsv" ]; then while [ "$n" -gt 1 ] && [ ! -e "$WORK/screens/$n.tsv" ]; do n=$((n - 1)); done; cat "$WORK/screens/$n.tsv"; else cat "$WORK/screen.tsv"; fi'
fake kdialog 'exit "$(cat "$WORK/kdialog-code" 2>/dev/null || echo 0)"'
fake systemsettings 'exit 0'
fake gio 'exit 0'
fake busctl 'case "$*" in *loadDeclarativeScript*) echo "i 3" ;; *unloadScript*) echo "b true" ;; esac; exit 0'
fake forgeos-family 'cat "$WORK/say/family" 2>/dev/null; exit 0'
fake forgeos-techguard 'cat "$WORK/say/techguard" 2>/dev/null; exit 0'
printf 'STATUS\toff\n' > "$WORK/say/family"
printf 'SERVICE\ton\nSHARING\t-\n' > "$WORK/say/techguard"
# screen N "words@x,y" ...: what look N sees (1920 x 1080); screen 0 ... = the same screen for every look
screen() {
  local n="$1"; shift
  if [ "$n" = 0 ]; then python3 "$ROOT/tests/showme-make.py" "$WORK/screen.tsv" 1920 1080 "$@"
  else python3 "$ROOT/tests/showme-make.py" "$WORK/screens/$n.tsv" 1920 1080 "$@"; fi
}
fresh() { rm -rf "$WORK/screens" "$WORK/looks" "$WORK/pictures" "$WORK/calls.log" "$WORK/screen.tsv"; mkdir -p "$WORK/screens"; }
app() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=true\n' "$1" > "$WORK/data/applications/$1.desktop"; }
