#!/usr/bin/env bash
# Tests for Forge Helper in KDE search (Job 13c), cases X1-X6: the KRunner D-Bus runner on a private
# test session bus (dbus-run-session). Needs python3-dbus + python3-gi (CI installs them from Ubuntu).
# shellcheck disable=SC2016,SC2034  # the checks are single-quoted on purpose: check() runs them with eval
# Usage: bash tests/test-helper-krunner.sh <repo-root>     (FORGEOS_TEST_PY = which python3 to use)
set -u
ROOT="$(cd "${1:-.}" && pwd)"
PY="${FORGEOS_TEST_PY:-python3}"
if [ -z "${DBUS_TEST_INNER:-}" ]; then
  if ! "$PY" -c "import dbus, dbus.mainloop.glib; from gi.repository import GLib" 2>/dev/null; then
    echo "FAIL X0 python3-dbus and python3-gi are needed for this test"; exit 1
  fi
  command -v dbus-run-session >/dev/null && command -v gdbus >/dev/null || { echo "FAIL X0 dbus-run-session and gdbus are needed"; exit 1; }
  DBUS_TEST_INNER=1 exec dbus-run-session -- bash "$0" "$ROOT"
fi
WORK="$(mktemp -d)"
failures=0
pass() { echo "PASS $1"; }
fail() { echo "FAIL $1"; failures=$((failures + 1)); }
check() { if eval "$2"; then pass "$1"; else fail "$1"; fi; }
# shellcheck source=tests/helper-fakes.sh
. "$ROOT/tests/helper-fakes.sh"
fake forgeos-helper-gui 'exit 0'
export FORGEOS_HELPER_GUI="$WORK/bin/forgeos-helper-gui" FORGEOS_HELPER_KRUNNER_QUIET=3
"$PY" -B "$ROOT/files/system/usr/libexec/forgeos-helper-krunner" &
RPID=$!
trap 'kill "$RPID" 2>/dev/null; rm -rf "$WORK"' EXIT
call() { gdbus call --session --dest org.forgeos.helper --object-path /runner --method "org.kde.krunner1.$1" "${@:2}" 2>&1; }
for _ in $(seq 50); do call Actions >/dev/null && break; sleep 0.1; done

OUT="$(call Match "help is this email a scam")"
check X1 'grep -qF "Ask Forge Helper: is this email a scam" <<< "$OUT" && grep -q "^(\[(.is this email a scam., .Ask Forge Helper: is this email a scam., .help-browser., 100, 1.0, {" <<< "$OUT"'
check X2 'grep -q "Forge Helper will check it for scams" <<< "$OUT"'
OUT="$(call Match "why is my computer so slow?")"
check X3 'grep -q "Ask Forge Helper: why is my computer so slow?" <<< "$OUT" && grep -q ", 50, 0.6" <<< "${OUT/0.59999999999999998/0.6}" && grep -q "check this PC" <<< "$OUT"'
OUT="$(call Match "firefox")"; OUT2="$(call Match "help")"
check X4 'grep -qx "(\[\],)\|(@a(sssida{sv}) \[\],)" <<< "$OUT" && grep -qx "(\[\],)\|(@a(sssida{sv}) \[\],)" <<< "$OUT2"'
call Run "is this email a scam" "" >/dev/null
sleep 0.5
check X5 'grep -qx "forgeos-helper-gui --ask is this email a scam" "$WORK/calls.log"'
# Quits by itself after the quiet time (3 s in this test; 10 minutes for real).
for _ in $(seq 40); do kill -0 "$RPID" 2>/dev/null || break; sleep 0.5; done
check X6 '! kill -0 "$RPID" 2>/dev/null'

echo
if [ "$failures" -eq 0 ]; then echo "All Forge Helper KDE search tests X1-X6 passed."; else echo "$failures Forge Helper KDE search test(s) failed."; fi
exit "$((failures > 0))"
