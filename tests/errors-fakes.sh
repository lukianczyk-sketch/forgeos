# shellcheck shell=bash
# Pretend desktop for the Plain-English Errors tests (Job 23). Sourced by tests/test-errors*.sh.
# notify-send, kdialog, coredumpctl, journalctl, wl-paste, gamemoded, pgrep (games only), systemd-run, spectacle +
# tesseract (a pretend screen), cancel, systemsettings, kioclient and the ForgeOS tools are fakes. Everything is logged to $WORK/calls.log.
# shellcheck disable=SC2016,SC2034  # fakes are written out single-quoted on purpose; the tests use the variables
[ -n "${WORK:-}" ] && [ -d "$WORK" ] || { echo "errors-fakes.sh: set WORK to a new temp folder first" >&2; return 1; }
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/run" "$WORK/say" "$WORK/data/applications"
chmod 700 "$WORK/run"
fake() { printf '#!/usr/bin/env bash\necho "%s $*" >> "$WORK/calls.log"\n%s\n' "$1" "$2" > "$WORK/bin/$1"; chmod +x "$WORK/bin/$1"; }
export WORK HOME="$WORK/home" XDG_RUNTIME_DIR="$WORK/run" XDG_DATA_HOME="$WORK/data" XDG_CONFIG_HOME="$WORK/config"
export XDG_DATA_DIRS="$WORK/nowhere" PYTHONDONTWRITEBYTECODE=1 PATH="$WORK/bin:$PATH"
export FORGEOS_ERRORS_LIB="$ROOT/files/system/usr/lib/forgeos-errors" FORGEOS_ERRORS_SHARE="$ROOT/files/system/usr/share/forgeos/errors"
export FORGEOS_SHOWME_LIB="$ROOT/files/system/usr/lib/forgeos-showme" FORGEOS_SHOWME_SHARE="$ROOT/files/system/usr/share/forgeos/showme"
export FORGEOS_HELPER_LIB="$ROOT/files/system/usr/lib/forgeos-helper" FORGEOS_HELPER_SHARE="$ROOT/files/system/usr/share/forgeos/helper"
export FORGEOS_ERRORS_LIBEXEC="$WORK/bin" FORGEOS_OLLAMA_URL="http://127.0.0.1:9" FORGEOS_ERRORS_NOW=1800000000
ENGINE="$ROOT/files/system/usr/bin/forgeos-errors"
GUI="$ROOT/files/system/usr/bin/forgeos-errors-gui"
ER() { python3 -B "$ENGINE" "$@"; }
T=$'\t'
HIST="$WORK/data/forgeos/errors/history.json"
fake forgeos-errors 'exec python3 -B "'"$ENGINE"'" "$@"'
fake notify-send 'cat "$WORK/say/click" 2>/dev/null; exit 0'
fake kdialog 'case "$*" in *--menu*) cat "$WORK/say/pick" 2>/dev/null ;; esac; exit "$(cat "$WORK/kdialog-code" 2>/dev/null || echo 0)"'
fake coredumpctl 'cat "$WORK/say/coredumps" 2>/dev/null; exit 0'
fake journalctl 'cat "$WORK/say/journal" 2>/dev/null; exit 0'
fake wl-paste '[ "$1" = --list-types ] && { cat "$WORK/say/cliptypes" 2>/dev/null || echo text/plain; exit 0; }; cat "$WORK/say/clip" 2>/dev/null; exit 0'
fake gamemoded '[ -e "$WORK/gaming" ] && echo "gamemode is active" || echo "gamemode is inactive"; exit 0'
fake pgrep 'case "$*" in *gamescope*) [ -e "$WORK/steam" ] ;; *) exec /usr/bin/pgrep "$@" ;; esac'
fake systemd-run 'while [ "$1" != -- ]; do shift; done; shift; exec "$@"'
fake spectacle 'while [ $# -gt 0 ]; do [ "$1" = -o ] && echo pretend-png > "$2"; shift; done; exit 0'
fake tesseract '[ -e "$WORK/screen.tsv" ] || exit 1; cat "$WORK/screen.tsv"'
fake forgeos-askpc 'echo "Done: $2"; exit 0'
fake forgeos-techguard 'exit 0'
fake forgeos-showme 'exit 0'
fake systemsettings 'exit 0'
fake kioclient 'exit 0'
fake cancel 'exit 0'
fake forgeos-family-call 'exit 0'
for g in willitrun guard slow drivehealth autopilot scamshield undo askpc techguard privacy helper cleansweep errors; do fake "forgeos-$g-gui" 'exit 0'; done
fake forgeos-ai-setup 'exit 0'
# screen "words@x,y" ...: what the quiet screenshot sees (1920 x 1080)
screen() { python3 "$ROOT/tests/showme-make.py" "$WORK/screen.tsv" 1920 1080 "$@"; }
fresh() { rm -rf "$WORK/data/forgeos" "$WORK/calls.log" "$WORK/screen.tsv" "$WORK/say/"*; }
calls() { cat "$WORK/calls.log" 2>/dev/null; }
# wait for background fakes (the pop-up runs in its own process) to write to calls.log
waitfor() { for _ in $(seq 50); do grep -q "$1" "$WORK/calls.log" 2>/dev/null && return 0; sleep 0.1; done; return 1; }
app() { printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s\n' "$2" "$1" > "$WORK/data/applications/$1.desktop"; }
